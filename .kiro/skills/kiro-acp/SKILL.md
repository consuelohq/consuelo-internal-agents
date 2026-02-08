# kiro-acp — Kiro Client

talk to kiro programmatically. two client implementations:

## client_chat.py (recommended — works now)

uses `kiro-cli chat --trust-all-tools --no-interactive` with stdin piping.
full tool execution, no permission issues.

```python
from client_chat import KiroChat, run_one_shot

# one-shot (simplest)
result = run_one_shot("fix the type error in src/utils.ts", cwd="/path/to/project")
print(result)

# or with context manager
with KiroChat(cwd="/path/to/project") as kiro:
    result = kiro.prompt("fix the bug")
    print(result)
```

each prompt spawns a fresh kiro process. no multi-turn sessions (each call is independent).

### cli usage

```bash
python3 client_chat.py --cwd /path/to/project "fix the bug in main.py"
python3 client_chat.py --cwd /path/to/project --interactive
```

## client.py (ACP — broken for tool execution)

uses `kiro-cli acp` with json-rpc 2.0. supports streaming and multi-turn sessions,
but **tool execution is blocked** because acp mode has no `--trust-all-tools` flag.
kiro sends `session/request_permission`, we respond correctly, but its internal
permission system still blocks execution.

kept for reference — may work in a future kiro-cli version that adds trust flags to acp.

## the kiro agent skill

the main kiro coding skill (`.opencode/skills/kiro/`) uses `client_chat.py` to
spawn kiro for coding tasks. see that skill's SKILL.md for the full workflow.
