# openengineer

bash is all you need.

orchestration layer for autonomous ai agents — using linear or github issues as your control plane. battle tested, peak production at 160+ tasks/night in production.

your job becomes: write good specs, enrich them with comments, chain 10-15 issues, run one bash command, and go to sleep. the agents do the rest.

we use [kiro-cli](https://kiro.dev) and [opencode](https://opencode.ai) — but the whole system is agent-swappable. use claude code, aider, cursor, or anything that accepts a prompt.

```
┌──────────────────────────────────────────────────────────────────────────┐
│                 YOUR ISSUES (linear or github — your control plane)       │
│                                                                          │
│  the full issue (title + description + every comment) becomes your       │
│  agent's prompt. every comment you add makes the agent smarter.          │
└──────────────────────────────────────────────────────────────────────────┘
       │                    │                         │
       │ @mention           │ assign / label          │ you run it yourself
       ▼                    ▼                         ▼
┌──────────────┐  ┌──────────────────┐  ┌──────────────────────────────┐
│  enrichment  │  │  terminal        │  │  .agent/run-tasks.sh         │
│              │  │  dispatch         │  │                              │
│  @mention a  │  │                  │  │  chains 10-15 issues,        │
│  research    │  │  webhook opens   │  │  runs for hours unattended,  │
│  agent in    │  │  a tmux session  │  │  entire epic in one command  │
│  the issue   │  │  in the correct  │  │                              │
│  → it reads  │  │  repo, runs the  │  │  each task = fresh agent     │
│  your code   │  │  full pipeline   │  │  session, no context bleed   │
│  → enriches  │  │  for that issue  │  │                              │
│  the spec    │  │                  │  │  you just run it straight    │
│  → posts     │  │                  │  │  in your terminal:           │
│  back to     │  │                  │  │  .agent/run-tasks.sh         │
│  the issue   │  │                  │  │                              │
└──────────────┘  └──────────────────┘  └──────────────────────────────┘
       │                    │                         │
       ▼                    ▼                         ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                       YOUR AGENT (swappable)                             │
│                                                                          │
│  kiro-cli • opencode • claude code • aider • cursor • anything           │
│  set AGENT_CLI in config.sh — run-tasks.sh doesn't care which            │
└──────────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                     THE ENRICHMENT WORKFLOW                               │
│                                                                          │
│  1. you write your expected outcome (a few lines — what should happen)   │
│  2. @mention a research agent in the issue → it explores the codebase,   │
│     reads patterns, finds the right files, and enriches your spec with   │
│     implementation details, file:line references, and architecture       │
│     context — all posted back as comments on the issue                   │
│  3. the enriched spec goes to a worker agent → it doesn't research,     │
│     it just works. every file, every line, every acceptance criterion    │
│     is already in the prompt.                                            │
│  4. chain 10-15 enriched issues → .agent/run-tasks.sh → epic in hours   │
└──────────────────────────────────────────────────────────────────────────┘
```

## your issues are your orchestration layer

linear (or github issues) isn't just your task tracker — it's your whole control plane. the entire issue becomes your agent's prompt:

- **title** → what to do
- **description** → your full spec (acceptance criteria, file references, architecture notes)
- **comments** → your enrichment context (all comments get concatenated into the prompt)
- **labels** → routing (`kiro` label → kiro-cli, `opencode` label → opencode CLI, add your own)
- **workflow states** → your automated pipeline (open → in progress → in review → done)

issues run oldest-first, so multi-part specs execute in order. write part 1, part 2, part 3 as separate issues — they chain sequentially.

```bash
# what your agent actually sees (simplified):
# title: implement password reset flow
# description: <your full spec with acceptance criteria>
# comments:
#   you (2026-03-08): the reset token should expire after 1 hour
#   you (2026-03-08): use the existing email service, don't create a new one
#   research-agent (2026-03-08): found AuthService at src/auth/auth.service.ts:84,
#     uses JWT with 30m expiry. reset flow should follow the same pattern.
#     existing EmailService at src/email/email.service.ts — use sendTemplate().
```

every comment you add makes the agent smarter about that task. this is the leverage — you're not writing code, you're writing context. the research agent enriches your specs so the worker agent doesn't waste cycles exploring — it just builds.

## run-tasks.sh — the full pipeline

~2000 lines of battle-tested orchestration. here's what happens when it runs:

### 1. fetch issues
queries linear for issues matching your label + open state. supports linear, github issues, and github projects as task sources. oldest-first ordering for sequential multi-part specs.

```bash
.agent/run-tasks.sh --linear              # all open issues with your label
.agent/run-tasks.sh --linear --max-tasks 5 # cap at 5
.agent/run-tasks.sh --issue DEV-1076       # single issue
.agent/run-tasks.sh --dry-run              # preview without running
```

### 2. create staging branch + PR
creates (or reuses) a staging → main PR. all task commits land on one branch, one PR. you review one diff, not twenty.

### 3. for each issue: spawn agent subprocess

each task gets a fresh, isolated agent session. no context bleed between tasks.

**workpad creation** — extracts acceptance criteria from the issue body into a per-task scratch file. the agent writes implementation notes here as it works. institutional memory that persists after the run.

**prompt construction** — the agent gets:
- the full linear issue (title + description + all comments merged)
- path to its workpad file
- behavioral instructions (read standards first, implement, self-review, check acceptance criteria)

```bash
# the actual prompt template (simplified):
# you are working on Linear issue DEV-1076.
# title: implement password reset flow
# workpad file: .agent/workpads/DEV-1076.md
# description: <full spec + all comments>
# commit with message: 'fix(DEV-1076): brief description'
```

### 4. quality gates
after the agent finishes, the system checks:
- did the agent actually make commits? (no-op detection)
- did it leave uncommitted changes? (auto-commits them)

### 5. push + update linear
pushes commits immediately (crash-safe — work is never lost). posts the agent's output summary back to linear as a comment. moves the issue to "in review."

### 6. finalize PR
updates the PR description with a full summary:
- ✅ completed issues
- ⚠️ review-needed issues (code review or test failures)
- ❌ no-changes issues
- quality gates table (per-issue pass/fail)

marks the PR as ready for review.

### 7. post-run: deploy → fix loop → scenario tests

after all tasks complete:
- **merge PR** into staging (squash merge)
- **wait for deploy** (polls staging URL health check, 5-min timeout)
- **deploy-fix loop** — if staging is unhealthy, it pulls railway logs, feeds them to the agent as a fix prompt, pushes the fix, and waits for redeploy. up to 3 attempts.
- **scenario testing** — runs YAML-defined browser scenarios against staging (via agent-browser). creates a linear issue with pass/fail results regardless of outcome.
- **slack notifications** at every stage (start, complete, deploy fail, scenario results)

### 8. state persistence
saves run state to `run-state.json` after each task. if the script crashes or gets interrupted, the next run can resume where it left off. cleanup trap ensures uncommitted changes get pushed even on `ctrl+c`.

## agent-swappable architecture

the system doesn't care which agent you use. `config.sh` controls everything:

```bash
# config.sh — pick your agent
AGENT_CLI="kiro"                    # or "opencode", "claude", or your own

# CLI invocation patterns
KIRO_CMD="kiro-cli chat --trust-all-tools --no-interactive --agent worker"
OPENCODE_CMD="/opt/homebrew/bin/opencode run -m opencode-go/glm-5"
```

`get_agent_cmd()` returns the right command. run-tasks.sh calls it generically — swap agents by changing one line.

**to bring your own agent:**
1. set `AGENT_CLI="myagent"` in config.sh
2. add `MYAGENT_CMD="myagent-cli run"` 
3. update `get_agent_cmd()` to return it
4. your agent receives the prompt on stdin and works in the current directory

works with anything that accepts a prompt and writes to the filesystem: claude code, aider, cursor CLI, codex, or a custom wrapper. the orchestration layer doesn't care — it just needs something that reads a prompt and makes commits.

## webhook-receiver.py — real-time single sessions

stdlib-only python server (no flask, no deps). listens on port 8848. this is how your agents respond in real-time.

### @mention → single session, answer flows back to linear
```
# in a linear comment:
@kiro why is the auth middleware rejecting valid tokens?
```
your agent gets a tmux session, investigates, and posts the answer back to linear as a comment. supports multi-turn — follow-up comments continue the conversation with full history. you never leave linear.

### assign → full pipeline
assigning an issue to your agent triggers `run-tasks.sh --issue DEV-1076` in a tmux session. the full pipeline runs: branch, implement, PR, linear update.

### github PR reviews → automatic triage
when coderabbit or qodo posts a PR review:
1. webhook-receiver catches the github webhook
2. waits for the bot to finish all review passes
3. collects all inline comments, review summaries, and PR comments
4. creates (or updates) a linear issue with `[review]` label and all findings
5. your agent can then pick up those triage issues and fix them automatically

```
coderabbit reviews your PR → webhook creates "[review] CodeRabbit: PR #42" in linear
→ your agent picks it up → fixes the findings → new PR
```

### oauth token management
handles linear oauth code exchange and automatic token refresh. your agent's comments post under the bot's identity, not yours — so you always know what came from you vs what came from the agent.

## quality gates

your agents are only safe when they have guardrails. the system enforces quality at multiple levels:

**agent behavioral prompt** — every agent session starts with instructions to:
1. read your project's coding standards first
2. read the workpad (acceptance criteria extracted from the issue)
3. implement, then self-review every changed file
4. run your quality checks — all must pass
5. commit only after checks pass

**13 automated checks** (`scripts/code-review.sh`) — these are ours, swap them for yours:

| # | check | what it catches |
|---|-------|-----------------|
| 1 | LOGGING | `console.log/error/warn` (use structured logger) |
| 2 | SENTRY | HTTP errors missing error tracking |
| 3 | PHONE_NORM | phone comparisons without `normalizePhone()` |
| 4 | SQL_PARAM | template literals in `.query()` calls (SQL injection) |
| 5 | ERROR_HANDLING | async+await without try/catch within 30 lines |
| 6 | TYPE_SAFETY | `any` without `// HACK:` comment |
| 7 | SECRETS | hardcoded keys/tokens/passwords |
| 8 | TODO_FIXME | TODOs without ticket reference |
| 9 | IMPORT_SAFETY | wildcard imports |
| 10 | ROUTE_ORDER | param routes before literal routes |
| 11 | CATCH_TYPING | `catch (err: any)` instead of `catch (err: unknown)` |
| 12 | OPTIONAL_IMPORT | peer deps without lazy `await import()` |
| 13 | STUB_HANDLER | fake data without `// STUB:` comment |

these checks are project-specific — swap them for your own linting, type checking, or test suite. the pattern is what matters: the agent is told to run them, and the system verifies.

**the 14th gate — only the agent sees this.** after all 13 checks pass and the agent thinks it's done, the system forces it to re-read the original task (title + description + acceptance criteria) one more time and update the workpad with what it actually did. this catches drift — agents that "finished" but silently skipped an acceptance criterion. the agent can't say it's done until the workpad confirms every criterion was addressed.

**the nag hook — every 7 tool calls.** the agent gets interrupted with a checkpoint: "re-read the original requirements. what haven't you addressed yet? are you on track or drifting?" this prevents the most common agent failure mode — getting deep into implementation and forgetting what was actually asked for. it's a forced context refresh that costs almost nothing but catches expensive drift early.

## file structure

```
.agent/
├── config.sh              # agent selection, git branches, linear IDs, all settings
├── run-tasks.sh           # THE STAR — full pipeline orchestrator (~2000 lines)
├── webhook-receiver.py    # real-time dispatch (linear webhooks + github PR reviews)
├── linear-api.sh          # graphql helper (queries, mutations, state management)
├── linear-comment.sh      # post comments as bot identity (oauth, not personal key)
├── linear-setup.sh        # one-time setup (discovers team IDs, label IDs, state IDs)
├── init.sh                # session startup (health checks, git sync, dependency check)
├── notify.sh              # slack notifications + metrics tracking
├── workpads/              # per-task scratch files (acceptance criteria + agent notes)
├── logs/                  # per-task agent output logs
├── scenarios/             # YAML browser test scenarios (per-phase)
└── webhook-relay/         # docker relay for public webhook endpoint
```

## setup

### prerequisites

- **node.js** 18+
- **python** 3.9+ (stdlib only — no pip install needed)
- **jq** — `brew install jq`
- **github cli** — `brew install gh && gh auth login`
- **tmux** — `brew install tmux` (for webhook dispatch)
- **an agent CLI** — kiro-cli, opencode, claude code, aider, or your own
- **linear account** with API key

### install

```bash
git clone https://github.com/consuelohq/openengineer.git
cp -r openengineer/.agent /path/to/your/project/
cd /path/to/your/project
```

### configure

```bash
# 1. environment variables (~/.zshrc)
export LINEAR_API_KEY="lin_api_..."
export SLACK_WEBHOOK_URL="https://hooks.slack.com/..."  # optional

# 2. edit .agent/config.sh
AGENT_CLI="kiro"                          # your agent
GITHUB_REPO="your-org/your-repo"          # your repo
LINEAR_TEAM_ID="your-team-uuid"           # from linear settings → API
LINEAR_LABEL_NAME="kiro"                  # label that triggers pickup
SOURCE_BRANCH="main"                      # branch to create runs from
PR_TARGET_BRANCH="main"                   # branch PRs target

# 3. discover linear IDs (one-time)
source .agent/linear-api.sh
linear_setup_cache
# copy the output into config.sh
```

### run

```bash
# start the webhook receiver (background)
python3 .agent/webhook-receiver.py &

# manual batch run
.agent/run-tasks.sh --linear

# single issue
.agent/run-tasks.sh --issue DEV-123

# preview
.agent/run-tasks.sh --linear --dry-run
```

### linear webhook setup

1. linear settings → API → webhooks
2. URL: `https://your-domain.com/webhook/linear`
3. select: issue updates, comments, assignments
4. (optional) github webhook for PR review triage: `https://your-domain.com/webhook/github`

## how we use it

this runs in production on [consuelohq/opensaas](https://github.com/consuelohq/opensaas) — a monorepo with 9+ packages. agents process 150-200 linear tasks overnight. the workflow:

1. write a few lines — your expected outcome for each task
2. tag a research agent to explore the codebase and enrich your specs
3. review the enriched specs — add comments, tweak acceptance criteria (this is where your taste matters)
4. label 10-15 issues, run `.agent/run-tasks.sh --linear`
5. go to sleep
6. wake up to PRs with linked issues, slack notifications, and scenario test results

the agents handle: branching, implementation, self-review, quality checks, PR creation, status updates, deploy verification, and failure recovery. your job is good specs and good taste — the bash handles everything else.

## license

mit — use it, fork it, make it yours.
