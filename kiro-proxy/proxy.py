"""
Kiro proxy — OpenAI-compatible /v1/chat/completions that spawns kiro-cli chat.

Features:
- True streaming: reads kiro-cli stdout incrementally
- Abort support: kills kiro-cli on client disconnect (via generator cleanup)
- Explicit abort endpoint: POST /v1/chat/abort

Run:  python3 -m uvicorn proxy:app --host 0.0.0.0 --port 18794
"""

import asyncio
import json
import logging
import os
import re
import time
import uuid

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, StreamingResponse

app = FastAPI()
log = logging.getLogger("kiro-proxy")

KIRO_CLI = os.environ.get("KIRO_CLI_PATH", "/Users/kokayi/.local/bin/kiro-cli")
KIRO_CWD = os.environ.get("KIRO_CWD", "/Users/kokayi/Dev/claude-agent-workflow")

ANSI_RE = re.compile(r"\x1b\[[0-9;]*[a-zA-Z]|\x1b\[\?[0-9]*[a-zA-Z]")

# Active kiro-cli processes keyed by conversation_id
_active_procs: dict[str, asyncio.subprocess.Process] = {}


def strip_ansi(text: str) -> str:
    return ANSI_RE.sub("", text)


def _make_chunk(cid, created, model, content, finish_reason=None):
    return {
        "id": cid, "object": "chat.completion.chunk", "created": created, "model": model,
        "choices": [{"index": 0, "delta": {"content": content} if content else {}, "finish_reason": finish_reason}],
    }


def _sse(data):
    return "data: " + json.dumps(data) + "\n\n"


def _extract_prompt(messages):
    system = ""
    last_user = ""
    for msg in messages:
        role = msg.get("role", "")
        content = msg.get("content", "")
        if role == "system":
            system = content
        elif role == "user":
            last_user = content
    parts = [p for p in [system, last_user] if p]
    return "\n\n".join(parts) if parts else "hello"


async def _kill_proc(conv_id):
    proc = _active_procs.pop(conv_id, None)
    if proc and proc.returncode is None:
        log.info(f"killing kiro-cli for conv {conv_id} (pid {proc.pid})")
        try:
            proc.kill()
            await asyncio.wait_for(proc.wait(), timeout=5)
        except Exception:
            pass


async def _stream_kiro(prompt, model, conv_id):
    """Spawn kiro-cli, stream output as SSE. Cleanup in finally block kills proc on disconnect."""
    cid = f"chatcmpl-{uuid.uuid4().hex[:12]}"
    created = int(time.time())

    await _kill_proc(conv_id)

    proc = await asyncio.create_subprocess_exec(
        KIRO_CLI, "chat", "--trust-all-tools", "--no-interactive",
        stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        cwd=KIRO_CWD,
    )
    _active_procs[conv_id] = proc
    log.info(f"spawned kiro-cli pid {proc.pid} for conv {conv_id}")

    proc.stdin.write((prompt + "\n").encode())
    await proc.stdin.drain()
    proc.stdin.close()

    # Role chunk
    yield _sse({
        "id": cid, "object": "chat.completion.chunk", "created": created, "model": model,
        "choices": [{"index": 0, "delta": {"role": "assistant"}, "finish_reason": None}],
    })

    found_response = False
    buffer = ""
    completed = False

    try:
        while True:
            try:
                chunk = await asyncio.wait_for(proc.stdout.read(4096), timeout=1.0)
            except asyncio.TimeoutError:
                if proc.returncode is not None:
                    break
                continue

            if not chunk:
                break

            text = strip_ansi(chunk.decode("utf-8", errors="replace"))
            buffer += text

            if not found_response:
                lines = buffer.split("\n")
                for i, line in enumerate(lines):
                    if line.startswith("> "):
                        found_response = True
                        response_start = line[2:]
                        remaining = "\n".join(lines[i + 1:])
                        first_chunk = response_start + ("\n" + remaining if remaining else "")
                        if first_chunk:
                            yield _sse(_make_chunk(cid, created, model, first_chunk))
                        buffer = ""
                        break
            else:
                if buffer:
                    yield _sse(_make_chunk(cid, created, model, buffer))
                    buffer = ""

        completed = True
        if found_response and buffer:
            yield _sse(_make_chunk(cid, created, model, buffer))

        yield _sse(_make_chunk(cid, created, model, "", finish_reason="stop"))
        yield "data: [DONE]\n\n"

    except (asyncio.CancelledError, GeneratorExit):
        # Client disconnected — starlette cancels the generator
        log.info(f"client disconnected for conv {conv_id}, killing kiro-cli")
        raise
    finally:
        # This ALWAYS runs — whether completed normally, cancelled, or errored
        if not completed:
            await _kill_proc(conv_id)
        else:
            _active_procs.pop(conv_id, None)


## ── suelo-status endpoint ──────────────────────────────────────────

SKILLS_DIR = os.environ.get("SKILLS_DIR", "/Users/kokayi/.openclaw/workspace/skills")
MEMORY_MD = os.environ.get("MEMORY_MD", "/Users/kokayi/.kiro/steering/MEMORY.md")
TOOLS_MD = os.environ.get("TOOLS_MD", "/Users/kokayi/.kiro/steering/TOOLS.md")
KO_MD = os.environ.get("KO_MD", "/Users/kokayi/.kiro/steering/ko.md")
MEM0_ENV = os.environ.get("MEM0_ENV", "/Users/kokayi/.openclaw/workspace/.env")


def _read_file(path):
    try:
        with open(path, "r") as f:
            return f.read()
    except Exception:
        return ""


def _load_skills():
    skills = []
    if not os.path.isdir(SKILLS_DIR):
        return skills
    for name in sorted(os.listdir(SKILLS_DIR)):
        skill_md = os.path.join(SKILLS_DIR, name, "SKILL.md")
        if not os.path.isfile(skill_md):
            continue
        raw = _read_file(skill_md)
        desc = ""
        # parse frontmatter
        if raw.startswith("---"):
            parts = raw.split("---", 2)
            if len(parts) >= 3:
                for line in parts[1].splitlines():
                    if line.strip().startswith("description:"):
                        desc = line.split(":", 1)[1].strip().strip('"').strip("'")
        skills.append({"name": name, "description": desc, "skillMd": raw})
    return skills


def _load_mem0_key():
    if os.environ.get("MEM0_API_KEY"):
        return os.environ["MEM0_API_KEY"]
    if os.path.isfile(MEM0_ENV):
        for line in open(MEM0_ENV):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                if k.strip() == "MEM0_API_KEY":
                    return v.strip()
    return ""


@app.get("/api/suelo-status")
async def suelo_status():
    import importlib, sys
    skills = _load_skills()
    tools_md = _read_file(TOOLS_MD) or "No TOOLS.md found"
    memory_md = _read_file(MEMORY_MD) or "No MEMORY.md found"
    ko_md = _read_file(KO_MD) or "No ko.md found"

    # mem0 memories
    mem0_memories = []
    api_key = _load_mem0_key()
    if api_key:
        try:
            from mem0 import MemoryClient
            client = MemoryClient(api_key=api_key)
            result = client.get_all(filters={"OR": [{"user_id": "ko"}]}, limit=100)
            if isinstance(result, list):
                mem0_memories = result
            elif isinstance(result, dict):
                mem0_memories = result.get("results", result.get("memories", []))
        except Exception as e:
            log.warning(f"mem0 fetch failed: {e}")

    return {
        "skills": skills,
        "tools": {"toolsMd": tools_md},
        "memory": {"memoryMd": memory_md, "koMd": ko_md, "mem0": mem0_memories},
        "crons": [],
    }


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/v1/models")
async def list_models():
    return {
        "object": "list",
        "data": [{"id": "kiro", "object": "model", "created": int(time.time()), "owned_by": "kiro-proxy"}],
    }


@app.post("/v1/chat/abort")
async def chat_abort(request: Request):
    body = await request.json()
    conv_id = body.get("conversation_id") or body.get("session_key") or ""
    if not conv_id:
        raise HTTPException(status_code=400, detail="conversation_id required")
    await _kill_proc(conv_id)
    return JSONResponse({"ok": True, "aborted": conv_id})


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    body = await request.json()
    messages = body.get("messages", [])
    model = body.get("model", "kiro")
    stream = body.get("stream", False)
    prompt = _extract_prompt(messages)
    conv_id = body.get("conversation_id", str(uuid.uuid4()))

    if not stream:
        await _kill_proc(conv_id)
        proc = await asyncio.create_subprocess_exec(
            KIRO_CLI, "chat", "--trust-all-tools", "--no-interactive",
            stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
            cwd=KIRO_CWD,
        )
        _active_procs[conv_id] = proc
        proc.stdin.write((prompt + "\n").encode())
        await proc.stdin.drain()
        proc.stdin.close()

        try:
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=600)
        except asyncio.TimeoutError:
            await _kill_proc(conv_id)
            stdout = b"[kiro timed out after 10 minutes]"

        _active_procs.pop(conv_id, None)
        raw = strip_ansi(stdout.decode("utf-8", errors="replace"))
        lines = raw.split("\n")
        response_lines = []
        in_response = False
        for line in lines:
            if line.startswith("> ") and not in_response:
                in_response = True
                response_lines.append(line[2:])
            elif in_response:
                response_lines.append(line)
        response = "\n".join(response_lines).strip() if response_lines else raw.strip()

        return JSONResponse({
            "id": f"chatcmpl-{uuid.uuid4().hex[:12]}",
            "object": "chat.completion", "created": int(time.time()), "model": model,
            "choices": [{"index": 0, "message": {"role": "assistant", "content": response}, "finish_reason": "stop"}],
        })

    return StreamingResponse(_stream_kiro(prompt, model, conv_id), media_type="text/event-stream")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=18794)
