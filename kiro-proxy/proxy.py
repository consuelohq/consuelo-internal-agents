"""
Kiro proxy — OpenAI-compatible /v1/chat/completions that spawns kiro-cli chat.

Run:  python3 -m uvicorn proxy:app --host 0.0.0.0 --port 18794
"""

import asyncio
import json
import os
import re
import time
import uuid

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse

app = FastAPI()

KIRO_CLI = os.environ.get("KIRO_CLI_PATH", "/Users/kokayi/.local/bin/kiro-cli")
KIRO_CWD = os.environ.get("KIRO_CWD", "/Users/kokayi/Dev/claude-agent-workflow")

ANSI_RE = re.compile(r"\x1b\[[0-9;]*[a-zA-Z]|\x1b\[\?[0-9]*[a-zA-Z]")


def strip_ansi(text: str) -> str:
    return ANSI_RE.sub("", text)


def _make_chunk(cid: str, created: int, model: str, content: str, finish_reason=None):
    return {
        "id": cid,
        "object": "chat.completion.chunk",
        "created": created,
        "model": model,
        "choices": [
            {
                "index": 0,
                "delta": {"content": content} if content else {},
                "finish_reason": finish_reason,
            }
        ],
    }


def _sse(data) -> str:
    return "data: " + json.dumps(data) + "\n\n"


def _extract_prompt(messages: list[dict]) -> str:
    system = ""
    last_user = ""
    for msg in messages:
        role = msg.get("role", "")
        content = msg.get("content", "")
        if role == "system":
            system = content
        elif role == "user":
            last_user = content
    parts = []
    if system:
        parts.append(system)
    if last_user:
        parts.append(last_user)
    return "\n\n".join(parts) if parts else "hello"


def _extract_response(raw: str) -> str:
    """Extract kiro's actual response from the full stdout dump.

    kiro-cli chat --no-interactive outputs:
      - ASCII art banner
      - Model info line
      - Trust warning
      - blank lines
      - Credits line (▸ Credits: ...)
      - blank lines
      - "> " followed by the actual response
    """
    clean = strip_ansi(raw)

    # Strategy: find the last "> " prefixed block — that's the response
    lines = clean.split("\n")
    response_lines = []
    in_response = False

    for line in lines:
        if line.startswith("> ") and not in_response:
            in_response = True
            # Strip the "> " prefix from first line
            response_lines.append(line[2:])
        elif in_response:
            response_lines.append(line)

    if response_lines:
        return "\n".join(response_lines).strip()

    # Fallback: grab everything after the credits line
    credits_idx = -1
    for i, line in enumerate(lines):
        if "Credits:" in line:
            credits_idx = i

    if credits_idx >= 0 and credits_idx < len(lines) - 1:
        after = "\n".join(lines[credits_idx + 1 :]).strip()
        # Strip leading "> " if present
        if after.startswith("> "):
            after = after[2:]
        return after

    return clean.strip()


async def _run_kiro(prompt: str, cwd: str) -> str:
    """Spawn kiro-cli, send prompt, wait for completion, return response."""
    proc = await asyncio.create_subprocess_exec(
        KIRO_CLI, "chat", "--trust-all-tools", "--no-interactive",
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        cwd=cwd,
    )

    proc.stdin.write((prompt + "\n").encode())
    await proc.stdin.drain()
    proc.stdin.close()

    try:
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=600)
    except asyncio.TimeoutError:
        proc.kill()
        return "[kiro timed out after 10 minutes]"

    raw = stdout.decode("utf-8", errors="replace")
    return _extract_response(raw)


async def _stream_kiro(prompt: str, model: str, cwd: str):
    """Run kiro and stream the response as SSE chunks."""
    cid = f"chatcmpl-{uuid.uuid4().hex[:12]}"
    created = int(time.time())

    # Role chunk
    yield _sse({
        "id": cid,
        "object": "chat.completion.chunk",
        "created": created,
        "model": model,
        "choices": [{"index": 0, "delta": {"role": "assistant"}, "finish_reason": None}],
    })

    response = await _run_kiro(prompt, cwd)

    if response:
        # Stream in reasonable chunks for a nice typing effect
        chunk_size = 20
        for i in range(0, len(response), chunk_size):
            yield _sse(_make_chunk(cid, created, model, response[i : i + chunk_size]))
            await asyncio.sleep(0.01)

    yield _sse(_make_chunk(cid, created, model, "", finish_reason="stop"))
    yield "data: [DONE]\n\n"


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/v1/models")
async def list_models():
    return {
        "object": "list",
        "data": [{"id": "kiro", "object": "model", "created": int(time.time()), "owned_by": "kiro-proxy"}],
    }


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    body = await request.json()
    messages = body.get("messages", [])
    model = body.get("model", "kiro")
    stream = body.get("stream", False)
    prompt = _extract_prompt(messages)

    if not stream:
        response = await _run_kiro(prompt, KIRO_CWD)
        return JSONResponse({
            "id": f"chatcmpl-{uuid.uuid4().hex[:12]}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": model,
            "choices": [{"index": 0, "message": {"role": "assistant", "content": response}, "finish_reason": "stop"}],
        })

    return StreamingResponse(_stream_kiro(prompt, model, KIRO_CWD), media_type="text/event-stream")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=18794)
