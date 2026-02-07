---
name: repo-researcher
description: Research GitHub repositories to find trending tools, MCP servers, and CLI utilities that could expand AI assistant capabilities. Use when the user wants to discover new repos, research a specific repo, or find trending tools for their stack (LibreChat, OpenClaw, MCP servers, CLI tools, etc.). Triggers on phrases like "find repos", "research repo", "what's trending", "suggest tools", or when asked about GitHub repositories.
---

# Repo Researcher

Find and research GitHub repositories that expand AI assistant capabilities.

## When to Use

- User wants to discover new tools/MCP servers/CLIs
- User asks "what's trending" or "find me repos"
- User provides a specific repo to research
- Looking for integrations with specific services (Twilio, Linear, Slack, etc.)

## Workflow

### If User Provided a Repo (owner/repo format):

1. Use deepwiki skill to research it:
```bash
node /Users/kokayi/.openclaw/workspace/skills/deepwiki/scripts/deepwiki.js ask <owner/repo> "what does this project do, what are its key features, and how might it be useful for expanding an ai assistant's capabilities?"
```

2. Format output as:
- **What it is** — plain english summary
- **Key capabilities** — tools/features exposed
- **Integration potential** — how it plugs into LibreChat/OpenClaw/opencode
- **Quickstart** — how to actually use it
- **Link** — https://github.com/<owner/repo>

### If No Repo Provided (Discovery Mode):

1. Search for trending repos:
```bash
python3 /Users/kokayi/.openclaw/workspace/skills/repo-researcher/scripts/find_trending.py
```

2. Filter results by relevance to user's stack:
   - MCP servers (high priority — expands tool ecosystem)
   - CLI tools that could become OpenClaw skills
   - Browser automation tools
   - Integrations with services they use (Twilio, Linear, Slack, etc.)
   - AI/LLM utilities

3. Check what skills already exist to avoid duplicates:
```bash
ls /Users/kokayi/.openclaw/workspace/skills/
```

4. Present 3-4 suggestions with:
   - Repo name (linked: https://github.com/owner/repo)
   - Why it matters for their setup
   - Brief description

5. Ask which to deep-dive, then use deepwiki skill.

## User Context (for relevance filtering)

- Uses LibreChat as frontend with multiple endpoints
- Has opencode for coding tasks
- Runs OpenClaw locally with skills (check which exist)
- Main project: Consuelo (Twilio-based AI sales coaching)
- Always wants to expand AI capabilities

## Output Format

Always include full GitHub links in suggestions:
- `[owner/repo](https://github.com/owner/repo)`

Discovery mode table columns:
| repo | why it matters |
|------|----------------|
| [owner/repo](link) | description |

## Examples

**Good suggestion:**
> | [browser-use/browser-use](https://github.com/browser-use/browser-use) | AI browser automation — lets me actually interact with sites (click, type) vs just reading them |

**Bad suggestion (missing link):**
> browser-use/browser-use — AI browser automation tool

## Discovery Priority

1. MCP servers (modelcontextprotocol/*, awesome-mcp-servers list)
2. CLI tools that wrap APIs (twilio-cli, linear-cli, etc.)
3. Browser automation (playwright-mcp, browser-use, etc.)
4. AI agent frameworks
5. Productivity integrations (notion, slack, github mcp servers)
