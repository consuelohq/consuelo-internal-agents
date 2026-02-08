---
name: kiro
description: Orchestrate Kiro CLI coding sessions via ACP. Spawns Kiro for coding tasks, monitors progress, creates branches and PRs when done. Handles both chat-initiated and Linear-spec tasks. Use when asked to code, build, or implement features.
---

# Kiro Agent — Automated Coding via Kiro CLI

You (OpenCode) are the **orchestrator**. Kiro is the **coder**. You spawn Kiro, give it tasks, monitor its work, and handle the git/PR workflow when it's done.

**Everything is remote.** Kiro reads and writes code via the GitHub API — no local file changes. Multiple sessions can run simultaneously on different branches without conflicts.

## When to Use This Skill

- User asks to "build", "implement", "code", "create", or "fix" something or /kiro
- A Linear task is ready for development
- A previous deploy failed and the fix needs to be coded

## Architecture

```
OpenCode (you) ──ACP──> Kiro CLI (codes via GitHub API)
                              │
                              ├── reads files via github-dev scripts
                              ├── writes files via github-dev scripts
                              ├── commits via github-dev scripts
                              │
OpenCode (you) ──gh CLI──> GitHub (branch, PR, labels)
```

## Paths & Constants

```
KIRO_ACP_CLIENT = "/Users/kokayi/Dev/claude-agent-workflow/.opencode/skills/kiro-acp/client.py"
GITHUB_DEV      = "/Users/kokayi/Dev/claude-agent-workflow/.opencode/skills/github-dev/dev"
GITHUB_DEV_DIR  = "/Users/kokayi/Dev/claude-agent-workflow/.opencode/skills/github-dev"
LINEAR_HELPER   = "/Users/kokayi/Dev/claude-agent-workflow/.opencode/skills/kiro/linear_helper.py"
KIRO_AGENT      = "/Users/kokayi/Dev/claude-agent-workflow/.opencode/skills/kiro/kiro_agent.py"

DEFAULT_CWD     = "/Users/kokayi/Dev/consuelo_on_call_coaching"
DEFAULT_REPO    = "kokayicobb/consuelo_on_call_coaching"
```

## Full Workflow

### Step 1: Receive Task

Two entry points:

**Chat entry** — user says "build X" or "implement feature Y":
- Extract the coding task from the conversation
- Construct a detailed prompt for Kiro (more detail = better results)

**Linear spec entry** — task ID provided (e.g., CON-456):
- Fetch the spec: `python3 {GITHUB_DEV_DIR}/fetch_task.py CON-456`
- Read the saved spec file: `{GITHUB_DEV_DIR}/tasks/CON-456.md`
- The spec contains requirements, acceptance criteria, and context

### Step 2: Create Branch

Start a github-dev session to create the working branch:

```bash
# For Linear tasks:
python3 {GITHUB_DEV} task CON-456

# For chat tasks (no Linear):
python3 {GITHUB_DEV} create-branch "add user authentication flow"
```

This creates a remote branch on GitHub and saves session state. Note the branch name from the output.

### Step 3: Spawn Kiro ACP Session

Use the orchestrator to spawn and manage Kiro:

```python
import sys
sys.path.insert(0, "/Users/kokayi/Dev/claude-agent-workflow/.opencode/skills/kiro")
from kiro_agent import KiroSession

# Start a session
session = KiroSession(
    cwd="/Users/kokayi/Dev/consuelo_on_call_coaching",
    repo="kokayicobb/consuelo_on_call_coaching",
)
session.start()

# Send the task
result = session.run_task(
    task_description="Implement user authentication with JWT tokens",
    branch_name="remote/consuelo_on_call_coaching-a3f2--add-user-auth",
    linear_spec=None,  # or the spec text if from Linear
    linear_task_id=None,  # or "CON-456" if from Linear
)

# result contains: what Kiro did, whether it created specs or coded, files changed
```

### Step 4: What Kiro Does (You Don't Control This)

Kiro receives a prompt that instructs it to:

1. **Assess complexity** — is this a straightforward coding task or does it need specs?
2. **If complex** — create Linear issues tagged `kiro` for each piece of work, then STOP
3. **If straightforward** — code the solution using github-dev scripts:
   - Read files: `python3 {GITHUB_DEV} read src/file.tsx`
   - Explore: `python3 {GITHUB_DEV} ls src/` and `python3 {GITHUB_DEV} tree src/`
   - Write files: `echo 'content' | python3 {GITHUB_DEV} write src/new-file.tsx`
   - Or: `python3 {GITHUB_DEV} write src/file.tsx --content-file /tmp/edit.tsx`
   - Commit: `python3 {GITHUB_DEV} commit "feat: add user auth"`
   - Can do multiple write+commit cycles

### Step 5: Monitor Progress

While Kiro works, you monitor via streaming. The orchestrator (`kiro_agent.py`) handles this, but key things to watch for:

- **ToolCall events with "linear" mentions** — Kiro is creating specs → session will end without coding
- **ToolCall events with file operations** — Kiro is coding, relay significant updates to chat
- **Kiro saying "created specs" or "created issues"** — end session, report specs
- **TurnEnd** — Kiro's turn is complete, evaluate

Relay significant progress to Ko's chat:
- "Kiro is reading the codebase structure..."
- "Kiro is writing src/components/Auth.tsx..."
- "Kiro committed 3 files: feat: add auth component"
- "Kiro created Linear specs: CON-457, CON-458. Session ending."

### Step 6: After Kiro Finishes

**If Kiro created Linear specs (complex task):**
- Report the created specs to chat
- Tag the Linear issues with `kiro` label
- END — no PR, no coding. The specs will be picked up later.

**If Kiro coded (straightforward task):**
1. Check what was committed (the github-dev session tracks this)
2. Review the changes:
   ```bash
   # Check what's on the branch
   python3 {GITHUB_DEV} status
   ```
3. If satisfied, create PR:
   ```bash
   python3 {GITHUB_DEV} create-pr \
     --title "feat: add user authentication" \
     --label kiro \
     --label kiro-small
   ```
4. Determine PR size for labeling:
   - **kiro-small**: <10 files changed AND <500 total lines changed AND single concern
   - **kiro-big**: everything else
5. If Linear task exists, the `create_pr()` method auto-updates Linear status to "In Review"

### Step 7: Report Results

Tell Ko:
- PR URL and number
- What was changed (brief summary)
- Whether it was labeled `kiro-small` (auto-review) or `kiro-big` (manual review)
- Linear task status update (if applicable)

## Kiro Prompt Template

When sending the coding task to Kiro, use this template:

```
You are coding a feature for the Consuelo project (on-call coaching platform).

## Task
{task_description}

{linear_spec_section if applicable}

## Working Branch
You are working on branch: `{branch_name}`

## How to Read/Write Code

You MUST use the github-dev CLI for ALL file operations. Do NOT use your built-in
file tools — all code changes must go through the GitHub API.

### Read files
python3 {GITHUB_DEV} read <path>

### List directories
python3 {GITHUB_DEV} ls <path>

### View file tree
python3 {GITHUB_DEV} tree <optional_prefix>

### Write/edit a file
Write content to a temp file first, then stage it:
cat > /tmp/kiro-edit.tsx << 'KIROEOF'
... your code here ...
KIROEOF
python3 {GITHUB_DEV} write src/path/to/file.tsx --content-file /tmp/kiro-edit.tsx

### Commit your changes
python3 {GITHUB_DEV} commit "type: description of changes"

### Check status
python3 {GITHUB_DEV} status
python3 {GITHUB_DEV} staged

## Complexity Decision

If this task is complex (needs multiple PRs, architectural decisions, or a spec):
1. Create Linear issues for each piece of work using:
   python3 {LINEAR_HELPER} create --title "Issue title" --description "Full description" --label kiro
2. Report what specs you created
3. STOP — do not code anything

If this task is straightforward:
1. Read the relevant code to understand the codebase
2. Plan your changes
3. Write the code using github-dev commands
4. Commit with descriptive messages
5. Report what you changed and why

## Rules
- Use conventional commit messages (feat:, fix:, refactor:, etc.)
- Write clean, production-ready code
- Add comments for complex logic
- Do NOT delete files unless the task specifically requires it
- If you're unsure about something, implement the most reasonable approach
- When done, list all files you changed/created
```

## Error Handling

- **Kiro ACP process dies**: Report error, clean up session state
- **github-dev operations fail**: Report the error — Kiro can retry or work around it
- **Branch creation fails**: Report error, do NOT spawn Kiro
- **Timeout (4 hours)**: Graceful shutdown, report partial progress, save state
- **Deploy failure (retry from pr-watcher)**: Same flow but prompt includes error context:
  ```
  The previous deploy failed with this error:
  {error_details}

  Fix the issue on branch `{branch_name}` and commit the fix.
  ```

## Branch Naming

- **From Linear task**: Uses RemoteDev convention: `remote/{repo_name}-{hash}--{description}`
- **From chat**: `kiro/{kebab-description}` (we use create-branch which generates `remote/` prefix)

## PR Labeling

Always apply these labels:
- `kiro` — marks this PR as part of the automated Kiro pipeline
- `kiro-small` OR `kiro-big` — determines review automation behavior

If a Linear task is involved:
- Link the task in the PR body
- Update task status to "In Review"
- Add `kiro` label to the Linear task

## The Specs Watcher — Autonomous Kiro Pipeline

Kiro can run **autonomously** without OpenCode. The specs-watcher polls Linear and spawns fresh Kiro sessions.

### Files

```
.opencode/skills/kiro/
  specs-watcher.sh     # Main polling script
  config.sh            # Configuration (API keys, state IDs, paths)
  linear-api-kiro.sh   # Linear API wrapper
  kiro_agent.py        # Kiro session orchestrator
```

### How It Works

```
specs-watcher.sh (cron/launchd)
    │
    ├── polls linear every 30 min for issues with "kiro" label in "Open" state
    │
    ├── for each issue:
    │   ├── creates remote branch via github-dev
    │   ├── spawns FRESH kiro ACP session (no token bloat)
    │   ├── kiro codes via GitHub API
    │   ├── kiro commits
    │   ├── creates PR with "kiro" label
    │   ├── moves Linear issue to "In Review"
    │   └── sends Slack notification
    │
    └── pr-watcher.ts plugin (separate) picks up the PR for review/deploy

One task = One Kiro session = Fresh context
```

### Running the Specs Watcher

```bash
# Manual (run once)
.opencode/skills/kiro/specs-watcher.sh

# Setup Linear API first
.opencode/skills/kiro/specs-watcher.sh --setup

# Continuous mode (polls every 30 min)
.opencode/skills/kiro/specs-watcher.sh --daemon

# Via cron (every 30 minutes)
*/30 * * * * /Users/kokayi/Dev/claude-agent-workflow/.opencode/skills/kiro/specs-watcher.sh

# Via launchd (macOS)
# Create ~/Library/LaunchAgents/com.kiro.specs-watcher.plist
```

### Configuration

Set environment variables in `~/.zshrc`:

```bash
export LINEAR_API_KEY="..."
export LINEAR_TEAM_ID="..."
export SLACK_WEBHOOK_URL="..."
```

Or edit `config.sh` directly for:
- `LINEAR_LABEL_NAME` — default "kiro"
- `POLL_INTERVAL` — default 1800 seconds (30 min)
- `MAX_TASKS_PER_RUN` — default 0 (unlimited)

## Important Notes

- **Remote-only**: Kiro codes via GitHub API. No local file changes. Period.
- **Parallel sessions**: Multiple Kiro sessions can run on different branches simultaneously.
- **Fresh sessions**: Each Linear task spawns a new Kiro ACP session — no context bloat.
- **The pr-watcher plugin** checks every 30 min for PRs tagged `kiro` and triggers automated review.
- **kiro-small PRs** get auto-reviewed and deployed. **kiro-big PRs** get a Slack notification for manual review.
- **Linear specs created by Kiro** will be picked up by the next specs-watcher poll — don't try to code them in the same session.
