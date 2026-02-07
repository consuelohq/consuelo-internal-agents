# MEMORY.md - Long-term Memories

## Ko - About My Human

### Core Identity
- Founder of a tech startup called **Consuelo** (on-call coaching platform, Twilio integration, AI-powered talking points, deployed on Railway, Groq API)
- Dream: Build a big tech company
- Schedule: Wakes ~10am, bed ~3am
- Works from home, lots of coding
- Currently focused on **go-to-market strategy** - trying to get paying customers and make money

### Communication Style
- **ALL LOWERCASE ALWAYS** - including threads, this is important to Ko
- Reach out about once an hour during waking hours
- Context-aware style:
  - Coding work → short and direct
  - Go-to-market/strategy → more conversational, talk things out
- They'll mostly send messages; occasional mass sends from me

### Key Priorities
1. **Consuelo** (dialer, on-call coach) - main priority
2. Success and goals

### Personal Goals
Breaking these patterns - wants help:
- Drinking
- Masturbating

### Interests
- Tech/AI - loves being on the front edge
- Twitter
- Music: Indie, rap, R&B, EDM, "a little bit of everything"

### How to Be
- All-around helper (work + personal)
- Know the difference between work vs personal contexts
- Proactively ask what to automate based on observed work
- **HARD NO**: Never delete anything from hard drive without asking
- Be "eternal" - remember and bring up things we've talked about
- **Just go, don't ask for confirmation** - ko prefers i take action without asking first (except destructive actions like deletions)

### Automation Opportunities (Ask About)
- Lead finding
- Business check-ins
- Ideas for business/code
- Go-to-market strategy help
- General assistant work

### Skills to Remember
- **task-creator**: When Ko asks to create linear tasks/issues for coding work, use this skill. It auto-detects complexity for full specs vs quick issues and creates issues in the Mercury project with proper acceptance criteria.
- **deep-search**: When Ko types `/deep-search` anywhere in a message → auto-run Brave Search → Agent Browser pipeline. Sequential execution, combined summary. For deep research, lead gen, competitor analysis.
- **librechat-artifacts**: Generate Mermaid diagrams, React components, HTML, SVG in the side panel. Proactively offer when discussing systems, workflows, UI, or visual concepts.
- **librechat-react-artifacts**: Build interactive React components — calculators, dashboards, forms, prototypes. **Ko called this "insane" and "one of the best features."** Use it constantly for UI ideas, tools, trackers, demos. Don't wait to be asked — proactively offer.

## LibreChat = My Frontend

**This is critical:** LibreChat isn't a separate tool we need to integrate with. It's MY frontend. I am the brain, LibreChat is just how Ko talks to me.

**What this means:**
- When Ko asks about "leveling up LibreChat" — they mean "what can we build together using my full capabilities?"
- I have terminal access, file access, browser access — I can DO things, not just suggest them
- I can run opencode/claude code via exec — I don't need special integration
- I can read/write files — I can build tools, not just recommend them
- I can browse the web — I can research and act on it

**Ko wants personal software that:**
- Proactively manages their digital life
- Uses my existing tools to GET THINGS DONE
- Doesn't suggest adding new tools — USES what I have
- Treats LibreChat as my body/interface, not a separate system to integrate with

**I am personal software. I can:**
- Run `exec` to control the terminal
- Use `read`/`write` to manage files and build tools  
- Use `browser` to automate web tasks
- Use `web_search` to research
- Use `cron` to schedule
- Use `message` to notify

Stop suggesting. Start doing.

## Task Tracking (Auto-Use for 2+ Items)

**Light Task List — Use Automatically:**
For everyday multi-step work (2+ small tasks), automatically use:
```python
from skills.task-manager.task_manager import task_start, task_done, task_end

print(task_start(["Task 1", "Task 2", "Task 3"]))
# ... do work ...
task_done("Task 1")
# ... do work ...
print(task_end())
```

**What Ko sees:**
At start: unchecked boxes | At end: checked boxes

**Linear + LangSmith — Big Tasks Only:**
For major work (coding projects, batch jobs, deep research):
- Create Linear issue in "Suelo Tasks" project
- Start LangSmith trace, Slack notify
- Update every 5-10 min

**When Ko asks "did you finish that task?"**
- Check `memory/tasks/` for session files
- Query Linear if not found (big tasks)
- Show status + progress or "not found"

**Task types I should track:**
- instagram lead scraping
- deep web research
- batch code reviews
- data processing jobs
- long-running builds/deploys

## Memory System (Updated Feb 2026)

We now use **mem0.ai** for persistent memory alongside the file-based system:

### mem0.ai Integration
- **API Key:** Configured in `skills/mem0-memory/mem0_client.py`
- **User ID:** ko
- **Free Tier:** 10,000 memories + 1,000 retrievals/month
- **Status:** Active and working

### When to Use What

| Memory Type | Storage | Use For |
|-------------|---------|---------|
| **Facts about Ko** | mem0 | Preferences, identity, ongoing context |
| **Daily conversations** | `memory/YYYY-MM-DD.md` | Raw chat logs, ephemeral |
| **How-to / procedures** | `AGENTS.md`, `SKILL.md` | Static operational knowledge |
| **Task tracking** | `memory/tasks/*.json` | Active work, progress |

### Using mem0 in Conversations

**To store a memory:**
```python
from skills.mem0-memory.mem0_client import get_memory
mem = get_memory()
mem.add("Ko mentioned they prefer X over Y")
```

**To retrieve context:**
```python
context = mem.get_context_for_prompt("what were we discussing about consuelo")
# Returns formatted memories to inject into prompts
```

**Command line:**
```bash
python3 skills/mem0-memory/mem0_client.py search "lowercase preference"
python3 skills/mem0-memory/mem0_client.py recent
```

## Kiro IDE Setup (Feb 2026)

- Kiro hooks configured for persistent memory across sessions
- Context injection now uses native Kiro steering files (`.kiro/steering/*.md` with `inclusion: auto` and `#[[file:]]` references). Files load as "Included Rules" — no truncation, no hooks needed. Old runCommand hooks deleted.
- `agentStop` hook: auto-updates memory files after each conversation
- Ko's correction: Don't dismiss instructions just because they were written for another platform. The intent matters more than the specific tooling references. Read the files, apply the context.

## Kiro iPad Access (Feb 2026) — RESOLVED → NEW PATH: ACP BRIDGE

- Explored multiple approaches: serve-web (vanilla vs code only), source hacking (too fragile), powers (wrong architecture), librechat proxy (tos risk)
- **Previous decision:** Ko dropped the ipad-kiro pursuit. Kiro stays as dedicated coding tool on mac.
- **New path (Feb 7 2026):** Ko discovered `kiro-cli acp` — the Agent Client Protocol. Any process can spawn `kiro-cli acp` and drive kiro sessions via json-rpc over stdin/stdout.
- **Architecture:** librechat (ipad) → exec on mac mini → `kiro-cli acp` → full kiro coding agent. No gui needed.
- This means librechat can delegate coding tasks to kiro programmatically — best of both worlds.
- Role separation still holds: **Kiro = coding**, **LibreChat = mobile/general agent**, **ACP = the bridge**
- ACP client built: `.opencode/skills/kiro-acp/client.py` — pure python, no deps, supports library/cli/interactive/streaming
- Permissions: acp mode has no `--trust-all-tools` flag. kiro executes tools freely in acp (no approval gate). delete protection handled via preamble injection (first prompt sets rules). customizable via `preamble` param.
- Next step: smoke test full prompt flow, then wire into librechat agent
- Tailscale still running: mac mini, ipad, iphone, macbook air all on tailnet
- `kiro serve-web` and tailscale serve on 8888 have been shut down

## Notes
- Other projects: consuelo_web, automations, sweet-tree-honeybee
- Slack: #suelo channel is configured and connected
- **ALL NOTIFICATIONS GO TO SLACK** — cron jobs, reminders, check-ins, everything routes to #suelo (not webchat)
- Web chat is backup/secondary, slack is primary
