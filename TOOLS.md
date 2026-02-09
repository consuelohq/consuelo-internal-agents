# TOOLS.md - Local Notes

Skills define _how_ tools work. This file is for _your_ specifics — the stuff that's unique to your setup.

Visual Structure with LaTeX

use latex styling cards, badges, and callouts early and often when they add clarity. think visually — if you're presenting tasks, leads, metrics, priorities, or anything that would benefit from structure, throw it in a card or badge. don't overthink it: task cards for work items, priority badges for urgency, callout boxes for ideas, metric tables for summaries. if it helps ko scan and understand faster, style it. it should feel natural, not forced — if it doesn't add value, skip it.

## CLI Tools Available

### Project-Specific CLIs
- `stripe` — webhooks, test events, customer data, subscription management
- `twilio` — call logs, phone numbers, SMS, voice config
- `gh` — PRs, issues, CI runs, repo management
- `railway` — logs, status, env vars, deploy, rollback

### Dev Toolchain
- `git` — version control (see pre-push checklist in AGENTS.md)
- `npm` / `npx` — frontend deps, scripts (do NOT run `npm run build`)
- `pip` / `python` — backend deps, migrations, scripts
- `docker` / `docker-compose` — local dev environment
- `make` — build automation
- `jq` — JSON processing in shell

### Modern CLI Replacements (aliased)

ko has modern rust/go replacements installed and aliased over the defaults. use the modern versions — they're what the aliases point to.

| classic command | replaced by | alias active | notes |
|----------------|-------------|:------------:|-------|
| `grep` | `rg` (ripgrep) | ✅ `grep=rg` | faster, respects .gitignore, better output |
| `cat` | `bat` | ✅ `cat=bat` | syntax highlighting, line numbers, git integration |
| `ls` | `eza` | ✅ `ls=eza` | git status, icons, color, tree view |
| `ll` | `eza -alh` | ✅ `ll=eza -alh --git --icons` | long listing with git info |
| `tree` | `eza --tree` | ✅ `tree=eza --tree` | better tree output |
| `find` | `fd` | ✅ `find=fd` | faster, simpler syntax, respects .gitignore |
| `du` | `dust` | ✅ `du=dust` | visual disk usage |
| `df` | `duf` | ✅ `df=duf` | cleaner disk free output |
| `diff` | `delta` | ✅ `diff=delta` | syntax-highlighted diffs, git integration |
| `ps` | `procs` | ✅ `ps=procs` | better process viewer |
| `top` | `btm` (bottom) | ✅ `top=btm` | modern system monitor |
| `rm` | `trash` | use `trash` manually | moves to trash instead of permanent delete — ALWAYS prefer over `rm` |

### HTTP & API Testing
- `xh` — primary HTTP client. rust rewrite of httpie, same syntax but faster. use for quick API testing
- `curl` — fallback for scripting, piping, or when you need raw control

### Shell Utilities
- `sed` / `awk` — text processing (system defaults)
- `rg` (ripgrep) — use directly or via `grep` alias for fast code search

Things like:

- Camera names and locations
- SSH hosts and aliases
- Preferred voices for TTS
- Speaker/room names
- Device nicknames
- Anything environment-specific

## Examples

```markdown
### Cameras

- living-room → Main area, 180° wide angle
- front-door → Entrance, motion-triggered

### SSH

- home-server → 192.168.1.100, user: admin

### TTS

- Preferred voice: "Nova" (warm, slightly British)
- Default speaker: Kitchen HomePod
```

## Why Separate?

Skills are shared. Your setup is yours. Keeping them apart means you can update skills without losing your notes, and share skills without leaking your infrastructure.

---

## Search

- **Default:** Agent-Browser or zai search mcp via mcporter (built-in `web_search` tool)
- **API Key:** Set in config (`tools.web.search.apiKey`)
- **Status:** Active and ready to use

---

## qmd — Local Document Search

local-first semantic search over ko's workspace documents. no api calls, no costs. hybrid search combining bm25 (keyword) + vector (semantic) + reranking.

- data: `~/.cache/qmd/index.sqlite`
- models: embeddinggemma-300m-q8 + qwen3-reranker-0.6b-q8 (~1.5gb total)
- workspace: `/users/kokayi/.openclaw/workspace`

### collections
- `memory-root` — default workspace memory (memory.md + memory/**/*.md)

### commands

```bash
# hybrid search (default, best results)
qmd query "search term" --json

# list collections
qmd collection list

# get full document
qmd get "path/to/file.md"
qmd get "memory.md#42"  # specific line

# get multiple docs by pattern
qmd multi-get "*.md" -l 50

# pure vector search (semantic)
qmd vsearch "semantic concepts" -n 10

# pure text search (keyword)
qmd search "exact phrase" -n 10
```

### when to use
- searching ko's notes/memory for context
- finding related documents across the workspace
- json output includes file path, score (0-1), snippet, line numbers
- system-wide install — all agents can use it, just run `qmd`

---

Add whatever helps you do your job. This is your cheat sheet.
