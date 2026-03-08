# openengineer

battle-tested autonomous ai agent infrastructure. this is the actual .agent/ directory from a production monorepo — extracted, cleaned, and shared so you can run your own coding agents.

the setup: linear webhooks → webhook-receiver.py → kiro-cli or opencode → commits, prs, and code review, all autonomous.

## how it works

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           LINEAR (TASK SOURCE)                              │
│  issues tagged with "kiro" label → picked up by webhook                     │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼ webhook (mention, assign, delegate)
┌─────────────────────────────────────────────────────────────────────────────┐
│                        WEBHOOK-RECEIVER.PY                                  │
│  listens on port 8848, authenticates linear webhooks, dispatches tasks      │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐          │
│  │ @mention        │    │ assign/delegate │    │ comment created │          │
│  │ → kiro-cli chat │    │ → run-tasks.sh  │    │ → context sync  │          │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘          │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         RUN-TASKS.SH                                        │
│  orchestrates the full loop: fetch task → create branch → implement → pr    │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │ 1. fetch issues from linear (kiro label + open state)                 │  │
│  │ 2. create worktree branch (agent/run-YYYY-MM-DD-<hash>)               │  │
│  │ 3. for each issue:                                                     │  │
│  │    - kiro-cli implements (or opencode if configured)                   │  │
│  │    - commit with co-authored-by suelo-kiro[bot]                        │  │
│  │    - optional: opencode code review (posts gh pr comment)              │  │
│  │ 4. create single pr with all commits                                   │  │
│  │ 5. update linear issue status (in progress → in review)                │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         KIRO-CLI / OPENCODE                                 │
│  kiro: orchestrator (plans, reviews, coordinates)                           │
│  opencode: executor (implements features, does heavy lifting)               │
└─────────────────────────────────────────────────────────────────────────────┘
```

## file structure

```
.agent/
├── config.sh              # configuration (agent cli, git branches, linear settings)
├── run-tasks.sh           # main orchestrator — fetches issues, runs agents, creates prs
├── webhook-receiver.py    # flask server — listens for linear webhooks, dispatches tasks
├── linear-api.sh          # graphql helper — queries and mutates linear issues
├── linear-comment.sh      # post comments to linear issues (as kiro bot)
├── linear-setup.sh        # one-time linear oauth setup
├── manage-labels.sh       # sync linear labels with expected set
├── init.sh                # session startup — health checks, git sync
├── notify.sh              # slack notifications + metrics
├── label-pr.sh            # auto-label prs by changed files
├── watch.sh               # file watcher for triggering agent runs
├── append-research.sh     # append notes to research files
├── prune-progress.sh      # clean old progress logs
├── human.md               # user guide (copy to your project)
├── webhook-relay/         # docker relay for public webhook endpoint
│   ├── Dockerfile
│   └── server.py
├── research/              # research notes (auto-generated)
└── scenarios/             # test scenario definitions
```

## quick start

### prerequisites

- **node.js** 18+ 
- **python** 3.9+
- **jq** — `brew install jq`
- **github cli** — `brew install gh` + `gh auth login`
- **kiro-cli** or **opencode** — the ai agent cli
- **linear account** — for task management

### setup

1. **copy the .agent/ directory to your project:**
   ```bash
   cp -r .agent /path/to/your/project/
   cd /path/to/your/project
   ```

2. **configure environment variables:**
   ```bash
   # add to ~/.zshrc or ~/.bashrc
   export LINEAR_API_KEY="your-linear-api-key"
   export SLACK_WEBHOOK_URL="https://hooks.slack.com/..."  # optional
   ```

3. **edit .agent/config.sh for your project:**
   ```bash
   AGENT_CLI="kiro"                    # or "opencode"
   BASE_BRANCH="main"                  # your main branch
   GITHUB_REPO="your-org/your-repo"    # github repo
   TASK_SOURCE="linear"                # use linear for issues
   LINEAR_TEAM_ID="your-team-uuid"     # from linear settings
   ```

4. **run the webhook receiver:**
   ```bash
   python3 .agent/webhook-receiver.py
   # listens on http://localhost:8848
   ```

5. **(optional) expose webhook publicly:**
   ```bash
   cd .agent/webhook-relay
   docker build -t webhook-relay .
   docker run -p 8848:8848 webhook-relay
   ```

6. **configure linear webhook:**
   - go to linear settings → api → webhooks
   - add webhook: `https://your-domain.com/webhook/linear`
   - select triggers: issue created, comment created, issue assigned

### usage

**run tasks manually:**
```bash
# process all issues with kiro label
.agent/run-tasks.sh

# process at most 3 issues
.agent/run-tasks.sh --max-tasks 3

# process a single issue by id
.agent/run-tasks.sh --issue DEV-123

# preview without processing
.agent/run-tasks.sh --dry-run
```

**mention the agent in a linear comment:**
```
@kiro implement the password reset flow
```

**delegate an issue to the agent:**
- assign the issue to "kiro" in linear
- the agent picks it up automatically

## key scripts explained

### run-tasks.sh

the main orchestrator. fetches issues from linear (or github issues/projects), creates a worktree, runs the agent cli for each issue, commits with proper attribution, and creates a single pr at the end.

features:
- multi-source: linear, github issues, github projects
- worktree isolation: each run in its own git worktree
- single pr per run: easy review of batch work
- opencode review: optional second-pass code review
- cleanup on exit: traps signals, ensures changes are pushed

### webhook-receiver.py

flask server that listens for linear webhooks. handles three triggers:

1. **@mention in comment** → runs kiro-cli chat (multi-turn conversation)
2. **assign/delegate** → launches run-tasks.sh in tmux session
3. **comment created** → syncs context for ongoing agent sessions

authenticates webhooks with hmac-sha256, refreshes oauth tokens automatically.

### linear-api.sh

bash wrapper for linear's graphql api. provides:
- `linear_graphql` — raw query execution
- `linear_get_ready_issues` — fetch issues with kiro label
- `linear_update_state` — change issue status

### linear-comment.sh

posts comments to linear issues as the kiro bot (uses oauth token, not personal api key). used by agents to report progress and results.

## multi-agent architecture

this system uses two agents in concert:

- **kiro (orchestrator)** — plans, coordinates, reviews, posts to linear
- **opencode (executor)** — implements features, does heavy code changes

the pattern: kiro decides what needs to happen, opencode does the actual coding, kiro reviews the result and posts back to linear. this separation keeps the orchestrator focused on coordination while the executor handles the mechanical work.

## configuration reference

| variable | description | default |
|----------|-------------|---------|
| `AGENT_CLI` | which ai cli to use | `kiro` |
| `BASE_BRANCH` | branch to create prs from | `main` |
| `GITHUB_REPO` | github repo (org/repo) | auto-detected |
| `TASK_SOURCE` | where to get tasks | `linear` |
| `LINEAR_TEAM_ID` | linear team uuid | (required) |
| `LINEAR_LABEL_NAME` | label to filter issues | `kiro` |
| `MAX_RETRIES` | retries per failed task | `1` |
| `AGENT_TIMEOUT` | timeout in seconds (0=none) | `0` |
| `RUN_TESTS_AFTER_TASK` | run tests after each task | `true` |

see `.agent/config.sh` for the full list.

## what's different from the old version

this repo is a **cleaned-up extract** from a production monorepo. the original used beads for task management and claude code as the agent. this version:

- uses **linear** as the task source (not beads)
- uses **kiro-cli** or **opencode** as the agent (not claude code)
- includes **webhook receiver** for real-time triggers
- adds **opencode review** as a second-pass quality gate
- supports **multiple task sources** (linear, github issues, github projects)

the old `beads` references have been removed. the hooks in `.claude/` still exist for backward compatibility but aren't used by the current setup.

## license

mit — use it, fork it, make it yours.

## credits

extracted from [consuelohq/opensaas](https://github.com/consuelohq/opensaas) — the real monorepo where this runs in production.
