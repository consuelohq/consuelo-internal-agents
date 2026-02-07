#!/usr/bin/env python3
"""
kiro acp client — talk to kiro programmatically via the agent client protocol.

spawns `kiro-cli acp` and communicates over json-rpc 2.0 (stdin/stdout).

usage:
    # as a library
    from client import KiroACP
    with KiroACP(cwd="/path/to/project") as kiro:
        print(kiro.prompt("fix the bug"))

    # from cli
    python3 client.py --cwd /path/to/project "your prompt here"
    python3 client.py --cwd /path/to/project --interactive
"""

import json
import subprocess
import sys
import threading
import queue
import os
import argparse
import uuid

KIRO_CLI = os.environ.get("KIRO_CLI_PATH", "/Users/kokayi/.local/bin/kiro-cli")

# injected as the first prompt in every session to set permissions
SYSTEM_PREAMBLE = """IMPORTANT RULES FOR THIS SESSION:
- you have FULL permission to read files, write files, edit files, and run shell commands. do NOT ask for confirmation.
- the ONE exception: NEVER delete files or directories. no rm, no trash, no deleteFile, no fs_remove. if a task requires deletion, say so and stop.
- work autonomously. complete the task fully without asking clarifying questions unless truly ambiguous.
- be concise in responses. code > commentary.
""".strip()


class KiroACP:
    def __init__(self, cwd=None, kiro_cli=None, preamble=None):
        self.cwd = cwd or os.getcwd()
        self.kiro_cli = kiro_cli or KIRO_CLI
        self.preamble = preamble if preamble is not None else SYSTEM_PREAMBLE
        self.process = None
        self.session_id = None
        self._msg_id = 0
        self._pending = {}  # id -> queue
        self._reader_thread = None
        self._notifications = queue.Queue()
        self._preamble_sent = False

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, *args):
        self.stop()

    def start(self):
        """spawn kiro-cli acp and initialize the connection."""
        self.process = subprocess.Popen(
            [self.kiro_cli, "acp"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=self.cwd,
        )

        # start reader thread to handle async responses
        self._reader_thread = threading.Thread(target=self._read_loop, daemon=True)
        self._reader_thread.start()

        # initialize
        resp = self._request("initialize", {
            "protocolVersion": 1,
            "clientCapabilities": {
                "fs": {"readTextFile": True, "writeTextFile": True},
                "terminal": True,
            },
            "clientInfo": {"name": "suelo-acp-client", "version": "1.0.0"},
        })

        # create session
        resp = self._request("session/new", {
            "cwd": self.cwd,
            "mcpServers": [],
        })
        self.session_id = resp.get("sessionId") or resp.get("id")

        # send preamble to set permissions/behavior
        if self.preamble:
            self._send_preamble()

        return self

    def _send_preamble(self):
        """inject permission rules as the first prompt, consume the response silently."""
        msg_id = self._next_id()
        self._send(msg_id, "session/prompt", {
            "sessionId": self.session_id,
            "content": [{"type": "text", "text": self.preamble}],
        })
        result_queue = self._pending.setdefault(msg_id, queue.Queue())
        # drain the response silently
        while True:
            try:
                msg = result_queue.get(timeout=60)
            except queue.Empty:
                break
            if msg is None:
                break
        self._pending.pop(msg_id, None)
        self._preamble_sent = True

    def stop(self):
        """terminate the kiro process."""
        if self.process and self.process.poll() is None:
            try:
                self.process.stdin.close()
            except Exception:
                pass
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
        self.process = None

    def prompt(self, text, images=None, timeout=300):
        """send a prompt and collect the full response.

        args:
            text: the prompt text
            images: optional list of image paths or base64 data
            timeout: max seconds to wait for response

        returns:
            str: the agent's full text response
        """
        content = [{"type": "text", "text": text}]
        if images:
            for img in images:
                content.append({"type": "image", "data": img})

        msg_id = self._next_id()
        self._send(msg_id, "session/prompt", {
            "sessionId": self.session_id,
            "content": content,
        })

        # collect streamed chunks until turn ends
        chunks = []
        result_queue = self._pending.setdefault(msg_id, queue.Queue())

        while True:
            try:
                msg = result_queue.get(timeout=timeout)
            except queue.Empty:
                break

            if msg is None:  # sentinel: turn ended or final response
                break

            # accumulate text chunks
            if isinstance(msg, dict):
                if msg.get("type") == "result":
                    # final rpc result
                    break
                text_chunk = self._extract_text(msg)
                if text_chunk:
                    chunks.append(text_chunk)
            elif isinstance(msg, str):
                chunks.append(msg)

        self._pending.pop(msg_id, None)
        return "".join(chunks)

    def prompt_stream(self, text, images=None):
        """send a prompt and yield chunks as they arrive.

        yields:
            dict: raw notification payloads (AgentMessageChunk, ToolCall, etc.)
        """
        content = [{"type": "text", "text": text}]
        if images:
            for img in images:
                content.append({"type": "image", "data": img})

        msg_id = self._next_id()
        self._send(msg_id, "session/prompt", {
            "sessionId": self.session_id,
            "content": content,
        })

        result_queue = self._pending.setdefault(msg_id, queue.Queue())

        while True:
            try:
                msg = result_queue.get(timeout=300)
            except queue.Empty:
                break
            if msg is None:
                break
            yield msg

        self._pending.pop(msg_id, None)

    # --- internal ---

    def _next_id(self):
        self._msg_id += 1
        return self._msg_id

    def _send(self, msg_id, method, params):
        """send a json-rpc request."""
        payload = {
            "jsonrpc": "2.0",
            "id": msg_id,
            "method": method,
            "params": params,
        }
        data = json.dumps(payload) + "\n"
        self.process.stdin.write(data.encode())
        self.process.stdin.flush()

    def _request(self, method, params, timeout=30):
        """send a request and wait for the response."""
        msg_id = self._next_id()
        result_queue = queue.Queue()
        self._pending[msg_id] = result_queue
        self._send(msg_id, method, params)

        try:
            resp = result_queue.get(timeout=timeout)
        except queue.Empty:
            raise TimeoutError(f"no response for {method} (id={msg_id})")
        finally:
            self._pending.pop(msg_id, None)

        if isinstance(resp, dict) and "error" in resp:
            raise RuntimeError(f"rpc error: {resp['error']}")
        return resp

    def _read_loop(self):
        """background thread: read json-rpc messages from stdout."""
        buffer = b""
        while self.process and self.process.poll() is None:
            try:
                chunk = self.process.stdout.read(1)
                if not chunk:
                    break
                buffer += chunk

                # try to parse complete json objects (newline-delimited)
                if chunk == b"\n":
                    line = buffer.strip()
                    buffer = b""
                    if not line:
                        continue
                    try:
                        msg = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    self._dispatch(msg)
            except Exception:
                break

        # signal all pending requests that we're done
        for q in self._pending.values():
            q.put(None)

    def _dispatch(self, msg):
        """route an incoming message to the right handler."""
        # rpc response (has id)
        if "id" in msg and ("result" in msg or "error" in msg):
            msg_id = msg["id"]
            q = self._pending.get(msg_id)
            if q:
                if "error" in msg:
                    q.put({"error": msg["error"]})
                else:
                    q.put(msg.get("result", {}))
            return

        # notification (no id) — session updates
        method = msg.get("method", "")
        params = msg.get("params", {})

        if method == "session/notification":
            update = params.get("update", {})
            update_type = update.get("type", "")

            # find the prompt request this belongs to (latest pending)
            target_q = None
            for mid in sorted(self._pending.keys(), reverse=True):
                target_q = self._pending[mid]
                break

            if target_q is None:
                self._notifications.put(update)
                return

            if update_type == "TurnEnd":
                target_q.put(None)  # sentinel
            elif update_type == "AgentMessageChunk":
                target_q.put(update)
            elif update_type in ("ToolCall", "ToolCallUpdate"):
                target_q.put(update)
            else:
                target_q.put(update)
        else:
            self._notifications.put(msg)

    def _extract_text(self, update):
        """pull text content from a session update."""
        if not isinstance(update, dict):
            return None
        utype = update.get("type", "")
        if utype == "AgentMessageChunk":
            content = update.get("content", "")
            if isinstance(content, str):
                return content
            if isinstance(content, list):
                return "".join(
                    c.get("text", "") for c in content if c.get("type") == "text"
                )
        return None


# --- cli interface ---

def main():
    parser = argparse.ArgumentParser(description="kiro acp client")
    parser.add_argument("prompt", nargs="?", help="prompt to send")
    parser.add_argument("--cwd", default=os.getcwd(), help="working directory for kiro")
    parser.add_argument("--interactive", "-i", action="store_true", help="interactive mode")
    parser.add_argument("--kiro-cli", default=None, help="path to kiro-cli binary")
    args = parser.parse_args()

    kiro = KiroACP(cwd=args.cwd, kiro_cli=args.kiro_cli)

    try:
        print("starting kiro acp session...", file=sys.stderr)
        kiro.start()
        print(f"session: {kiro.session_id}", file=sys.stderr)

        if args.interactive:
            print("interactive mode. type 'quit' to exit.\n", file=sys.stderr)
            while True:
                try:
                    user_input = input("you> ").strip()
                except (EOFError, KeyboardInterrupt):
                    break
                if user_input.lower() in ("quit", "exit", "q"):
                    break
                if not user_input:
                    continue
                print("\nkiro> ", end="", flush=True)
                for chunk in kiro.prompt_stream(user_input):
                    text = kiro._extract_text(chunk)
                    if text:
                        print(text, end="", flush=True)
                print("\n")
        elif args.prompt:
            result = kiro.prompt(args.prompt)
            print(result)
        else:
            # read from stdin
            text = sys.stdin.read().strip()
            if text:
                result = kiro.prompt(text)
                print(result)
            else:
                parser.print_help()
    finally:
        kiro.stop()
        print("session ended.", file=sys.stderr)


if __name__ == "__main__":
    main()
