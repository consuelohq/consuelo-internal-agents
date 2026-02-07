# kiro-acp — ACP Client for Kiro

talk to kiro programmatically via the Agent Client Protocol.

## permissions

by default, every session starts with a preamble that gives kiro full autonomy:
- read, write, edit files — no confirmation needed
- run shell commands — no confirmation needed
- **delete is blocked** — kiro will refuse to delete files/dirs unless you explicitly override

to customize, pass your own `preamble`:
```python
kiro = KiroACP(cwd="/path", preamble="your custom rules here")
# or disable preamble entirely:
kiro = KiroACP(cwd="/path", preamble=None)
```

## usage

```python
from client import KiroACP

kiro = KiroACP(cwd="/path/to/project")
kiro.start()

result = kiro.prompt("fix the type error in src/utils.ts")
print(result)

# send another prompt in the same session
result = kiro.prompt("now add tests for that fix")
print(result)

kiro.stop()
```

## context manager

```python
with KiroACP(cwd="/path/to/project") as kiro:
    result = kiro.prompt("explain this codebase")
    print(result)
```

## cli usage

```bash
# one-shot prompt
python3 .opencode/skills/kiro-acp/client.py --cwd /path/to/project "fix the bug in main.py"

# interactive mode
python3 .opencode/skills/kiro-acp/client.py --cwd /path/to/project --interactive
```

## how it works

spawns `kiro-cli acp` as a subprocess, communicates via json-rpc 2.0 over stdin/stdout. sends a permission preamble on session start, then handles prompt streaming and cleanup.
