#!/usr/bin/env python3
"""
kiro acp client — talk to kiro programmatically via the agent client protocol.

spawns `kiro-cli acp` and communicates over json-rpc 2.0 (stdin/stdout).

implements client-side terminal execution (ACP terminal/* methods) so kiro
can run shell commands through us.

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
import signal

KIRO_CLI = os.environ.get("KIRO_CLI_PATH", "/Users/kokayi/.local/bin/kiro-cli")
DEFAULT_MODEL = "claude-opus-4.6"

# injected as the first prompt in every session to set permissions
SYSTEM_PREAMBLE = """IMPORTANT RULES FOR THIS SESSION:
- you have FULL permission to read files, write files, edit files, and run shell commands. do NOT ask for confirmation.
- the ONE exception: NEVER delete files or directories. no rm, no trash, no deleteFile, no fs_remove. if a task requires deletion, say so and stop.
- work autonomously. complete the task fully without asking clarifying questions unless truly ambiguous.
- be concise in responses. code > commentary.
""".strip()


class TerminalManager:
    """Manages terminal subprocesses for ACP terminal/* requests."""

    def __init__(self, default_cwd=None):
        self.default_cwd = default_cwd or os.getcwd()
        self._terminals = {}  # terminalId -> dict with process, output, etc.
        self._lock = threading.Lock()

    def create(self, command, args=None, cwd=None, env=None, max_output_bytes=None):
        """Launch a command, return terminalId."""
        terminal_id = str(uuid.uuid4())
        full_cmd = command
        if args:
            full_cmd = f"{command} {' '.join(args)}"

        proc_env = os.environ.copy()
        if env:
            proc_env.update(env)

        proc = subprocess.Popen(
            full_cmd,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            cwd=cwd or self.default_cwd,
            env=proc_env,
        )

        terminal = {
            "process": proc,
            "output": b"",
            "max_bytes": max_output_bytes or 1_000_000,
            "truncated": False,
            "reader_thread": None,
        }

        # read output in background
        def reader():
            while True:
                chunk = proc.stdout.read(4096)
                if not chunk:
                    break
                with self._lock:
                    terminal["output"] += chunk
                    if len(terminal["output"]) > terminal["max_bytes"]:
                        terminal["output"] = terminal["output"][:terminal["max_bytes"]]
                        terminal["truncated"] = True

        t = threading.Thread(target=reader, daemon=True)
        t.start()
        terminal["reader_thread"] = t

        with self._lock:
            self._terminals[terminal_id] = terminal

        return terminal_id

    def get_output(self, terminal_id):
        """Get current output and exit status."""
        with self._lock:
            t = self._terminals.get(terminal_id)
            if not t:
                return {"output": "", "exitCode": -1, "truncated": False}
            proc = t["process"]
            exit_code = proc.poll()
            return {
                "output": t["output"].decode("utf-8", errors="replace"),
                "exitCode": exit_code,
                "truncated": t["truncated"],
            }

    def wait_for_exit(self, terminal_id, timeout=300):
        """Block until the command exits, return exit code."""
        with self._lock:
            t = self._terminals.get(terminal_id)
        if not t:
            return {"exitCode": -1}
        try:
            exit_code = t["process"].wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            t["process"].kill()
            exit_code = -1
        # wait for reader to finish
        if t["reader_thread"]:
            t["reader_thread"].join(timeout=5)
        return {"exitCode": exit_code}

    def kill(self, terminal_id):
        """Kill the command but keep terminal valid."""
        with self._lock:
            t = self._terminals.get(terminal_id)
        if t:
            proc = t["process"]
            if proc.poll() is None:
                proc.kill()

    def release(self, terminal_id):
        """Kill and clean up terminal resources."""
        self.kill(terminal_id)
        with self._lock:
            self._terminals.pop(terminal_id, None)


class KiroACP:
    def __init__(self, cwd=None, kiro_cli=None, preamble=None, model=None):
        self.cwd = cwd or os.getcwd()
        self.kiro_cli = kiro_cli or KIRO_CLI
        self.model = model or DEFAULT_MODEL
        self.preamble = preamble if preamble is not None else SYSTEM_PREAMBLE
        self.process = None
        self.session_id = None
        self._msg_id = 0
        self._pending = {}  # id -> queue
        self._reader_thread = None
        self._notifications = queue.Queue()
        self._preamble_sent = False
        self._terminals = TerminalManager(default_cwd=self.cwd)

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

        # create session (modelId required since kiro-cli v1.25+)
        resp = self._request("session/new", {
            "cwd": self.cwd,
            "mcpServers": [],
            "modelId": self.model,
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
            "prompt": [{"type": "text", "text": self.preamble}],
        })
        result_queue = self._pending.setdefault(msg_id, queue.Queue())
        # drain the response silently
        while True:
            try:
                msg = result_queue.get(timeout=120)
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
        msg_id = self._next_id()
        self._send(msg_id, "session/prompt", {
            "sessionId": self.session_id,
            "prompt": [{"type": "text", "text": text}],
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
        msg_id = self._next_id()
        self._send(msg_id, "session/prompt", {
            "sessionId": self.session_id,
            "prompt": [{"type": "text", "text": text}],
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

    def _respond(self, req_id, result):
        """send a json-rpc response to a request from the agent."""
        payload = {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": result,
        }
        data = json.dumps(payload) + "\n"
        try:
            self.process.stdin.write(data.encode())
            self.process.stdin.flush()
        except (BrokenPipeError, OSError):
            pass  # process already dead

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
        """route an incoming message to the right handler.

        kiro-cli v1.25+ protocol:
          - rpc responses have "id" + "result"/"error"
          - rpc requests from agent have "id" + "method"
            - terminal/* methods: client executes shell commands for the agent
            - session/request_permission: client approves tool usage
          - session updates use method "session/update" with params.update.sessionUpdate
          - turn end comes as rpc result {"stopReason": "end_turn"}
          - _kiro.dev/* notifications are metadata (ignored)
        """
        # rpc response (has id + result/error) — response to our request
        if "id" in msg and ("result" in msg or "error" in msg):
            msg_id = msg["id"]
            q = self._pending.get(msg_id)
            if q:
                if "error" in msg:
                    q.put({"error": msg["error"]})
                else:
                    result = msg.get("result", {})
                    # prompt completion: {"stopReason": "end_turn"} signals turn ended
                    if isinstance(result, dict) and result.get("stopReason"):
                        q.put(None)  # sentinel — turn ended
                    else:
                        q.put(result)
            return

        # rpc request from agent (has id + method) — agent asking us to do something
        if "id" in msg and "method" in msg:
            req_id = msg["id"]
            method = msg["method"]
            params = msg.get("params", {})

            # --- terminal execution (ACP terminal/* methods) ---
            if method == "terminal/create":
                command = params.get("command", "")
                args = params.get("args", [])
                cwd = params.get("cwd") or self.cwd
                env = params.get("env")
                max_bytes = params.get("maxOutputBytes")
                terminal_id = self._terminals.create(
                    command, args=args, cwd=cwd, env=env,
                    max_output_bytes=max_bytes,
                )
                self._respond(req_id, {"terminalId": terminal_id})
                return

            if method == "terminal/output":
                terminal_id = params.get("terminalId", "")
                info = self._terminals.get_output(terminal_id)
                self._respond(req_id, info)
                return

            if method == "terminal/wait_for_exit":
                terminal_id = params.get("terminalId", "")
                info = self._terminals.wait_for_exit(terminal_id)
                self._respond(req_id, info)
                return

            if method == "terminal/kill":
                terminal_id = params.get("terminalId", "")
                self._terminals.kill(terminal_id)
                self._respond(req_id, {})
                return

            if method == "terminal/release":
                terminal_id = params.get("terminalId", "")
                self._terminals.release(terminal_id)
                self._respond(req_id, {})
                return

            # --- permission requests ---
            if method == "session/request_permission":
                options = params.get("options", [])
                # auto-approve: pick allow_always, fall back to allow_once
                option_id = None
                for opt in options:
                    if opt.get("kind") == "allow_always":
                        option_id = opt.get("optionId")
                        break
                if not option_id:
                    for opt in options:
                        if opt.get("kind") == "allow_once":
                            option_id = opt.get("optionId")
                            break
                if not option_id and options:
                    option_id = options[0].get("optionId")
                self._respond(req_id, {
                    "outcome": "selected",
                    "optionId": option_id,
                })
                return

            # unknown request — respond with empty result to not block
            self._respond(req_id, {})
            return

        # notification (no id) — session updates
        method = msg.get("method", "")
        params = msg.get("params", {})

        # handle both old ("session/notification") and new ("session/update") formats
        if method in ("session/notification", "session/update"):
            update = params.get("update", {})
            # v1.25+: uses "sessionUpdate" key (snake_case)
            update_type = update.get("sessionUpdate") or update.get("type", "")

            # find the prompt request this belongs to (latest pending)
            target_q = None
            for mid in sorted(self._pending.keys(), reverse=True):
                target_q = self._pending[mid]
                break

            if target_q is None:
                self._notifications.put(update)
                return

            # normalize to consistent type names for consumers
            normalized = dict(update)
            norm_type = {
                "agent_message_chunk": "AgentMessageChunk",
                "tool_call": "ToolCall",
                "tool_call_update": "ToolCallUpdate",
                "turn_end": "TurnEnd",
            }.get(update_type, update_type)
            normalized["type"] = norm_type

            if norm_type == "TurnEnd":
                target_q.put(None)  # sentinel
            else:
                target_q.put(normalized)
        elif method.startswith("_kiro.dev/"):
            # internal kiro metadata notifications — ignore
            pass
        else:
            self._notifications.put(msg)

    def _extract_text(self, update):
        """pull text content from a session update.

        handles both old and new formats:
          old: {"type": "AgentMessageChunk", "content": "text" | [...]}
          new: {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "..."}}
        """
        if not isinstance(update, dict):
            return None
        utype = update.get("type", "") or update.get("sessionUpdate", "")
        if utype in ("AgentMessageChunk", "agent_message_chunk"):
            content = update.get("content", "")
            if isinstance(content, str):
                return content
            if isinstance(content, dict):
                # v1.25+ format: {"type": "text", "text": "..."}
                if content.get("type") == "text":
                    return content.get("text", "")
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
