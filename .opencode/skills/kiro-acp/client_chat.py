#!/usr/bin/env python3
"""
kiro chat client — talk to kiro via `kiro-cli chat --trust-all-tools --no-interactive`.

workaround for ACP mode lacking --trust-all-tools support. uses chat mode
with stdin piping instead of json-rpc, which gives full tool execution
without permission blocks.

usage:
    from client_chat import KiroChat
    with KiroChat(cwd="/path/to/project") as kiro:
        print(kiro.prompt("fix the bug"))

    # cli
    python3 client_chat.py --cwd /path/to/project "your prompt here"
    python3 client_chat.py --cwd /path/to/project --interactive
"""

import subprocess
import sys
import os
import re
import threading
import time
import argparse

KIRO_CLI = os.environ.get("KIRO_CLI_PATH", "/Users/kokayi/.local/bin/kiro-cli")
ANSI_RE = re.compile(r'\x1b\[[0-9;]*[a-zA-Z]|\x1b\[\?[0-9]*[a-zA-Z]')


def strip_ansi(text):
    return ANSI_RE.sub('', text)


class KiroChat:
    """Manages kiro coding sessions via `kiro-cli chat --trust-all-tools`."""

    def __init__(self, cwd=None, kiro_cli=None, model=None, preamble=None):
        self.cwd = cwd or os.getcwd()
        self.kiro_cli = kiro_cli or KIRO_CLI
        self.model = model
        self.preamble = preamble
        self.process = None
        self._output_chunks = []
        self._reader_thread = None
        self._lock = threading.Lock()

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, *args):
        self.stop()

    def start(self):
        """spawn kiro-cli chat with trust-all-tools."""
        cmd = [self.kiro_cli, 'chat', '--trust-all-tools', '--no-interactive']
        if self.model:
            cmd.extend(['--model', self.model])

        self.process = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=self.cwd,
        )

        # read stdout in background
        self._output_chunks = []
        self._reader_thread = threading.Thread(target=self._read_stdout, daemon=True)
        self._reader_thread.start()

        # also drain stderr
        threading.Thread(target=self._drain_stderr, daemon=True).start()

        return self

    def stop(self):
        """terminate kiro."""
        if self.process and self.process.poll() is None:
            try:
                self.process.stdin.close()
            except Exception:
                pass
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()
        self.process = None

    def prompt(self, text, timeout=300):
        """send a prompt and wait for the full response.

        since chat mode is single-turn with --no-interactive + stdin EOF,
        this sends the prompt, closes stdin, and collects all output.
        """
        full_prompt = text
        if self.preamble:
            full_prompt = self.preamble + "\n\n" + text

        self.process.stdin.write((full_prompt + "\n").encode())
        self.process.stdin.flush()
        self.process.stdin.close()

        # wait for process to finish
        try:
            self.process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            self.process.kill()

        # collect output
        if self._reader_thread:
            self._reader_thread.join(timeout=5)

        with self._lock:
            raw = ''.join(self._output_chunks)

        return self._clean_output(raw)

    def _read_stdout(self):
        while self.process and self.process.poll() is None:
            chunk = self.process.stdout.read(1)
            if not chunk:
                break
            with self._lock:
                self._output_chunks.append(chunk.decode('utf-8', errors='replace'))
        # read remaining
        remaining = self.process.stdout.read()
        if remaining:
            with self._lock:
                self._output_chunks.append(remaining.decode('utf-8', errors='replace'))

    def _drain_stderr(self):
        while self.process and self.process.poll() is None:
            self.process.stderr.read(1)

    def _clean_output(self, raw):
        """strip ansi codes and kiro chrome from output."""
        clean = strip_ansi(raw)
        # remove the kiro banner/header (everything before first "> ")
        lines = clean.split('\n')
        result = []
        started = False
        for line in lines:
            stripped = line.strip()
            if not started:
                if stripped.startswith('>') or stripped.startswith('I will run') or stripped.startswith('I\'ll'):
                    started = True
                    # skip the "> " prompt line itself
                    if stripped.startswith('>'):
                        content = stripped[1:].strip()
                        if content:
                            result.append(content)
                    else:
                        result.append(stripped)
                continue
            # skip credit/timing lines
            if stripped.startswith('▸ Credits:') or stripped.startswith('Credits:'):
                continue
            result.append(line)
        return '\n'.join(result).strip()


def run_one_shot(prompt_text, cwd=None, kiro_cli=None, model=None, preamble=None, timeout=300):
    """convenience: spawn kiro, send one prompt, return result, cleanup."""
    kiro = KiroChat(cwd=cwd, kiro_cli=kiro_cli, model=model, preamble=preamble)
    kiro.start()
    try:
        return kiro.prompt(prompt_text, timeout=timeout)
    finally:
        kiro.stop()


def main():
    parser = argparse.ArgumentParser(description="kiro chat client (trust-all workaround)")
    parser.add_argument("prompt", nargs="?", help="prompt to send")
    parser.add_argument("--cwd", default=os.getcwd())
    parser.add_argument("--kiro-cli", default=None)
    parser.add_argument("--model", default=None)
    parser.add_argument("--interactive", "-i", action="store_true")
    args = parser.parse_args()

    if args.interactive:
        print("interactive mode — each prompt spawns a fresh kiro session.", file=sys.stderr)
        print("type 'quit' to exit.\n", file=sys.stderr)
        while True:
            try:
                user_input = input("you> ").strip()
            except (EOFError, KeyboardInterrupt):
                break
            if user_input.lower() in ("quit", "exit", "q"):
                break
            if not user_input:
                continue
            result = run_one_shot(user_input, cwd=args.cwd, kiro_cli=args.kiro_cli, model=args.model)
            print(f"\nkiro> {result}\n")
    elif args.prompt:
        result = run_one_shot(args.prompt, cwd=args.cwd, kiro_cli=args.kiro_cli, model=args.model)
        print(result)
    else:
        text = sys.stdin.read().strip()
        if text:
            result = run_one_shot(text, cwd=args.cwd, kiro_cli=args.kiro_cli, model=args.model)
            print(result)
        else:
            parser.print_help()


if __name__ == "__main__":
    main()
