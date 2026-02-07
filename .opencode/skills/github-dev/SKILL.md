---
name: github-dev
description: Remote development via GitHub API. Write code, create branches, commit files, and create PRs — all without a local clone. Pull tasks from Linear and implement them entirely through GitHub. Use when Ko wants features built remotely while working locally on other things.
---

# GitHub Remote Development

Build features entirely through GitHub's API — no local clone needed. Pull tasks from Linear, create branches, write code, batch commit, create PRs, and auto-sync task status.

**Why this exists:** Ko works on multiple things at once. When coming to this project, he's already working on something locally. This skill lets the agent develop features in parallel without touching the local machine. You could have 10 sessions each working on different features simultaneously.

## Default Repo

`kokayicobb/consuelo_on_call_coaching`

Override with `--repo owner/name` on any command.

## Prerequisites

- `gh` CLI installed at `/opt/homebrew/bin/gh` and authenticated
- `LINEAR_API_KEY` set as env var (or available in `.agent/linear-api.sh`)
- `requests` Python library (for Linear API calls)

## Two Workflows

### Workflow 1: From Linear Task (default)

Ko says something like "pull task CON-456 and implement it" or "work on the auth feature from Linear."

**Steps:**

1. **Fetch the task spec** — run `fetch_task.py` to pull the task from Linear and save as markdown
2. **Read the markdown spec** — understand requirements, acceptance criteria, comments
3. **Start the dev session** — this creates a branch and updates Linear status
4. **Write code** — use the GitHub API to read existing files, write new files, update files
5. **Commit** — batch commit all changes atomically
6. **Create PR** — auto-generates body with Linear linking, moves task to "In Review"

**Python usage (in agent context):**

```python
import sys
sys.path.insert(0, "/Users/kokayi/Dev/claude-agent-workflow/.opencode/skills/github-dev")
from github_dev import RemoteDev

dev = RemoteDev()

# Start from a Linear task
summary = dev.start_task("CON-456")
# This: fetches task → saves spec → creates branch → updates Linear

# Read the saved spec to understand what to build
# The spec file is at: .opencode/skills/github-dev/tasks/CON-456.md

# Read existing code to understand the codebase
content = dev.read_file("src/components/Auth.tsx")
tree = dev.get_repo_structure("src/components/")

# Write new code (staged for batch commit)
dev.write_file("src/components/NewFeature.tsx", new_component_code)
dev.write_file("src/utils/helper.ts", helper_code)
dev.write_file("src/tests/NewFeature.test.tsx", test_code)

# Commit all staged files atomically
dev.commit("feat: implement new feature with helper utils and tests")

# Maybe write more code and commit again
dev.write_file("src/styles/NewFeature.css", css_code)
dev.commit("style: add styling for new feature")

# Create PR when done (auto-links to Linear, moves task to "In Review")
pr = dev.create_pr()
```

**CLI usage:**

```bash
# Fetch task spec (saves to tasks/CON-456.md)
python3 .opencode/skills/github-dev/fetch_task.py CON-456

# Start a dev session
python3 .opencode/skills/github-dev/dev task CON-456

# Create a branch without a Linear task
python3 .opencode/skills/github-dev/dev create-branch "add user auth flow"

# Read files, list directories
python3 .opencode/skills/github-dev/dev read src/file.tsx
python3 .opencode/skills/github-dev/dev ls src/components/
python3 .opencode/skills/github-dev/dev tree src/

# Write/stage files for commit
echo 'file content' | python3 .opencode/skills/github-dev/dev write src/new.tsx
python3 .opencode/skills/github-dev/dev write src/file.tsx --content-file /tmp/code.tsx
python3 .opencode/skills/github-dev/dev write src/quick.tsx --content "const x = 1;" --immediate

# See what's staged
python3 .opencode/skills/github-dev/dev staged

# Commit all staged files (atomic batch via Git Trees API)
python3 .opencode/skills/github-dev/dev commit "feat: add new component"

# Create a PR for the current branch
python3 .opencode/skills/github-dev/dev create-pr --label kiro --label enhancement
python3 .opencode/skills/github-dev/dev create-pr --title "feat: user auth" --label kiro

# Check session status
python3 .opencode/skills/github-dev/dev status

# Resume a previous session
python3 .opencode/skills/github-dev/dev resume
```

### Workflow 2: From Existing PR

Ko says something like "work on PR #789, fix the review comments" or "push changes to that PR."

**Steps:**

1. **Attach to the PR** — fetches PR info, sets the branch
2. **Read the PR diff** — understand what's already changed
3. **Make changes** — read/write files on the PR's branch
4. **Commit** — push changes to the PR

```python
dev = RemoteDev()

# Attach to existing PR
dev.work_on_pr(789)

# Read the current state
content = dev.read_file("src/fix-me.tsx")

# Make changes
dev.write_file("src/fix-me.tsx", fixed_content)
dev.commit("fix: address review comments")
```

## Branch Naming Convention

`remote/{repo_name}-{4char_hash}--{kebab-description}`

Example: `remote/consuelo_on_call_coaching-a3f2--implement-user-auth-flow`

The `remote/` prefix distinguishes these from the `agent/` prefix used by the local agent workflow.

## File Operations

### Reading Files

```python
# Single file
content = dev.read_file("src/components/Auth.tsx")

# Directory listing
items = dev.list_files("src/components/")
# Returns: [{"name": "Auth.tsx", "type": "file", "size": 1234}, ...]

# Full repo tree (filtered)
files = dev.get_repo_structure("src/")
# Returns: ["src/app.tsx", "src/index.tsx", ...]
```

### Writing Files (Staging)

Files are staged by default and committed as a batch:

```python
# Stage files
dev.write_file("src/new.tsx", code)
dev.write_file("src/utils.ts", utils)

# Check what's staged
dev.staged_files()  # ["src/new.tsx", "src/utils.ts"]

# Unstage a file
dev.unstage("src/utils.ts")

# Commit all staged files
dev.commit("feat: add new component")
```

For single-file immediate commits:

```python
dev.write_file("src/quick-fix.tsx", code, stage=False)
# Committed immediately
```

### Deleting Files

```python
dev.delete_file("src/old-file.tsx")  # Staged
dev.commit("chore: remove old file")

dev.delete_file("src/old-file.tsx", stage=False)  # Immediate
```

## Batch Commits (Git Trees API)

The `commit()` method uses the Git Trees API for atomic multi-file commits. This means:

- All files are committed in a single operation (no partial commits)
- Much more efficient than one-file-at-a-time for real coding work
- Creates proper git history (one commit per logical change)

## Linear Integration

### Auto-Status Sync

| Event | Linear Status | Action |
|-------|---------------|--------|
| `start_task()` called | In Progress | Adds comment with branch name |
| `create_pr()` called | In Review | Adds comment with PR link |

### Task Spec Files

Fetched tasks are saved as markdown in `tasks/`:

```
.opencode/skills/github-dev/tasks/
├── CON-456.md      # Full spec with description, criteria, comments
├── CON-789.md
└── .session-state.json  # Current session state for resumption
```

Each task file includes:
- Metadata (priority, state, labels, dates)
- Full description from Linear
- Acceptance criteria
- All comments (with authors and dates)
- Subtasks (if any)
- Attachments/links

## Session Persistence

The skill saves session state to `.session-state.json` so you can resume:

```python
dev = RemoteDev()
if dev.resume():
    # Picks up where you left off (same branch, task, PR)
    dev.write_file("src/more-code.tsx", code)
    dev.commit("feat: continue implementation")
```

## Important Notes

### When to Ask Ko

If Ko's instructions are ambiguous about which workflow to use:

- **"Work on CON-456"** → Workflow 1 (Linear task)
- **"Fix PR #789"** → Workflow 2 (existing PR)
- **"Implement the auth feature"** → Ask: "should I pull from a specific Linear task or create a fresh branch?"
- **"Push changes to the feature branch"** → Ask: "which PR or branch?"

### Rate Limits

GitHub API has rate limits (5,000 requests/hour for authenticated users). Each file read/write is 1-2 API calls. Batch commits are more efficient (1 call per file for blobs + 3 fixed calls). For a typical feature (reading 10 files, writing 5), that's ~25 API calls — well within limits.

### File Size Limits

The Contents API has a 100MB limit per file. Normal source code files are well within this. If you need to handle binary files or very large files, use the Git Blobs API directly (already used in batch_commit).

### Error Handling

- If a branch creation fails (name conflict), the error is printed and `start_task()` raises
- If a file write fails, the error is printed but other staged files can still be committed
- If Linear API is unavailable, the GitHub operations still work (just no status sync)

## Architecture

```
github-dev/
├── SKILL.md            # This file — instructions for the agent
├── github_api.py       # GitHub API client (gh CLI + gh api hybrid)
├── linear_api.py       # Linear GraphQL client
├── fetch_task.py       # CLI: pull task → markdown
├── github_dev.py       # Main orchestrator (RemoteDev class)
├── dev                 # Entry point script
└── tasks/              # Saved task specs and session state
```

### Component Responsibilities

- **github_api.py** — All GitHub operations. Uses `gh` CLI for PRs/reviews and `gh api` for file CRUD, branches, and batch commits. No Linear awareness.
- **linear_api.py** — All Linear operations. Fetches tasks by ID, updates status, adds comments. No GitHub awareness.
- **fetch_task.py** — Standalone CLI script. Pulls a task and writes a markdown file. Designed to be called before the agent starts reading (saves context window).
- **github_dev.py** — The brain. Ties GitHub + Linear together. Manages staging, session state, and the two workflows.
