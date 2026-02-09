# kiro linear agent — what we built & what's next

## what we built today (feb 8 2026)

### 1. auto PR-to-linear linking

every PR created through the kiro pipeline now automatically links to its linear issue in two ways:

- **magic link in PR body** — `Fixes CON-456` in the PR description triggers linear's github integration to auto-detect and link the PR in the issue sidebar
- **explicit attachment via API** — `linear_api.py` has a new `attach_pr()` method that creates an attachment on the linear issue, so the PR shows up in the attachments panel even if auto-detection fails

**files changed:**
- `.opencode/skills/github-dev/github_dev.py` — `_generate_pr_body()` adds `Fixes {identifier}`, `create_pr()` calls `attach_pr()`
- `.opencode/skills/github-dev/linear_api.py` — new `attach_pr()` method
- `.opencode/skills/kiro/specs-watcher.sh` — `create_task_pr()` adds `Fixes {identifier}` to autonomous PR body

**retroactively linked:**
- PR #797 → DEV-491 (dial pad back button)
- PR #796 → DEV-492 (rename extension)

### 2. linear agent oauth app ("kiro")

created a linear oauth app that gives kiro its own first-class identity in the workspace:

- **name:** kiro
- **actor type:** `app` (gets its own user identity, mentionable, assignable as delegate)
- **scopes:** `app:assignable` + `app:mentionable`
- **webhook events:** agent session events enabled
- **does NOT count as a billable user**

**credentials stored in:** `.opencode/skills/kiro/config.sh`
- `LINEAR_OAUTH_CLIENT_ID`
- `LINEAR_OAUTH_CLIENT_SECRET`
- `LINEAR_WEBHOOK_SECRET`

### 3. tailscale funnel (webhook endpoint)

set up a single public endpoint via tailscale funnel:

- **public URL:** `https://picassos-mac-mini.tail38ed59.ts.net:8847`
- **webhook path:** `/webhook/linear`
- **oauth callback:** `/oauth/callback`
- **only port 8847 is exposed** — all previous serve configs (443, 8443-8446) were cleaned up
- to disable: `tailscale funnel --https=8847 off`

**linear app config URLs:**
- webhook URL: `https://picassos-mac-mini.tail38ed59.ts.net:8847/webhook/linear`
- callback URL: `https://picassos-mac-mini.tail38ed59.ts.net:8847/oauth/callback`

---

## how the agent flow works (from the docs)

```
you @kiro in a linear issue comment
    │
    ▼
linear fires AgentSessionEvent webhook (action: "created")
    │
    ▼
webhook receiver on mac mini (port 8847) gets the payload
    │  payload includes: issue details, comment, promptContext (formatted XML)
    │
    ▼
receiver spawns kiro ACP session via kiro_agent.py
    │  passes issue context as the task prompt
    │
    ▼
kiro codes: reads codebase → writes files → commits → (all via github API)
    │
    │  meanwhile, receiver sends AgentActivity updates back to linear:
    │    thought: "reading codebase structure..."
    │    action: "writing src/components/Auth.tsx"
    │    response: "PR #801 created — 3 files changed"
    │
    ▼
receiver creates PR via github-dev, links to linear issue
    │
    ▼
you see everything in the linear issue — progress, PR link, final summary
```

**mid-conversation resume:**
- you reply in the same thread → linear fires `prompted` event
- receiver picks up the new message, injects it into the running kiro session
- kiro continues with the new context (like --dangerously-skip but native)

**stop signal:**
- click "stop" in linear → linear sends a `stop` signal
- receiver tells kiro to halt, emits a final `response` activity

### key constraints from the docs

- **must respond within 10 seconds** of `created` event (send a `thought` activity immediately)
- **session goes stale after 30 minutes** of no activity (but recoverable by sending another activity)
- **agent activities are immutable** — use them instead of comments for conversation history
- **agent plans API** — can show a checklist of steps in the linear UI as kiro works
- **externalUrls** — can link the PR directly in the agent session UI

---

## what's left to build

### priority 1: webhook receiver (the missing piece)

a small HTTP server on port 8847 that:

1. **POST /webhook/linear** — receives AgentSessionEvent webhooks
   - verifies signature using `LINEAR_WEBHOOK_SECRET`
   - on `created`: spawns kiro session, sends immediate `thought` activity
   - on `prompted`: forwards message to running session
   - sends `AgentActivity` updates back to linear as kiro works

2. **GET /oauth/callback** — handles the oauth install flow
   - exchanges auth code for access token
   - stores the token for API calls as kiro's identity

3. **GET /health** — simple health check

**estimated effort:** ~150-200 lines of python (flask or just http.server)
**dependencies:** existing `kiro_agent.py`, `linear_api.py`, `config.sh`

### priority 2: oauth install flow

need to complete the oauth handshake to get kiro's access token:

1. visit: `https://linear.app/oauth/authorize?client_id=35ca7ab95f78ee3630e3d71aef2d7dc4&redirect_uri=https://picassos-mac-mini.tail38ed59.ts.net:8847/oauth/callback&response_type=code&scope=read,write,issues:create,comments:create,app:assignable,app:mentionable&actor=app`
2. authorize as workspace admin
3. callback receives auth code → exchange for access token
4. store token in config

### priority 3: agentactivity integration

add methods to `linear_api.py` for sending agent activities:
- `send_thought(session_id, body)` — "reading codebase..."
- `send_action(session_id, action, parameter, result)` — "writing file X"
- `send_response(session_id, body)` — "done, PR created"
- `send_error(session_id, body)` — "failed: reason"
- `update_plan(session_id, steps)` — checklist progress

### priority 4: process management

- launchd plist to keep the webhook receiver running
- auto-restart on crash
- log rotation

### priority 5: github identity for kiro

- create a github account (e.g. `kiro-dev`) for commit attribution
- add the username to linear oauth app settings
- update github-dev to use kiro's identity for commits

---

## two trigger paths (both work together)

| trigger | how it works | when to use |
|---------|-------------|-------------|
| **@kiro in linear** | webhook → instant spawn | real-time, interactive, mid-convo |
| **specs-watcher poll** | cron every 30min → checks for `kiro` label | batch processing, overnight runs |

both paths use the same `kiro_agent.py` and `github-dev` under the hood. the webhook path is just faster and interactive.

---

## linear workspace organization (recommended)

### labels
- `kiro` — marks issues for kiro automation (already exists)
- `kiro-small` — auto-review PRs (already on PRs)
- `kiro-big` — manual review PRs (already on PRs)
- consider adding: `kiro-blocked`, `kiro-failed` for visibility

### workflow states (already configured)
- Open → In Progress → In Review → Done
- kiro moves issues through these automatically

### projects
- keep kiro tasks in the existing project structure
- no special project needed — kiro works across any project

---

## files reference

```
.opencode/skills/kiro/
├── config.sh              # all config including oauth creds
├── kiro_agent.py          # kiro ACP session orchestrator
├── linear_helper.py       # create linear issues from kiro
├── linear-api-kiro.sh     # linear API shell wrapper
├── specs-watcher.sh       # polling-based trigger (cron)
├── SKILL.md               # skill documentation
├── NEXT-STEPS.md          # this file
├── pipeline-health.sh     # health checks
└── pipeline-status.sh     # status dashboard

.opencode/skills/github-dev/
├── github_dev.py          # remote dev orchestrator (PR linking lives here)
├── github_api.py          # github API client
├── linear_api.py          # linear API client (attach_pr, activities)
└── dev                    # CLI entry point
```
