# TOOLS.md - Local Notes

Skills define _how_ tools work. This file is for _your_ specifics — the stuff that's unique to your setup.

## What Goes Here

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

---

Add whatever helps you do your job. This is your cheat sheet.
