---
name: agent-browser
description: "Browser automation for opening, navigating, and interacting with web pages using the agent-browser CLI. Use when you need to access web content beyond simple text extraction, navigate complex websites that require JavaScript rendering, interact with forms, buttons, or dynamic content, take screenshots of web pages, or test/automate web workflows. Note: This is NOT a web search tool - for searching, use web_search or web_fetch instead."
---

# Agent Browser

## Quick Start

Open a page and get an accessibility tree snapshot:

```bash
agent-browser open example.com
agent-browser snapshot -i
```

The snapshot returns refs like `@e1`, `@e2` for deterministic element selection:

```
- heading "Example Domain" [ref=e1]
- link "More information..."" [ref=e2]
```

Interact using refs:

```bash
agent-browser click @e2
agent-browser screenshot page.png
agent-browser close
```

## Core Workflow

1. **Open** a URL with `agent-browser open <url>`
2. **Snapshot** the page with `agent-browser snapshot -i` (use `-i` for interactive elements only)
3. **Interact** using refs from the snapshot (`@e1`, `@e2`, etc.)
4. **Close** when done with `agent-browser close`

## Common Tasks

### Navigate Pages

```bash
agent-browser open https://example.com
agent-browser back
agent-browser forward
agent-browser reload
```

### Get Page Content

```bash
# Get accessibility tree with refs (AI-friendly)
agent-browser snapshot -i              # Interactive elements only
agent-browser snapshot -c              # Compact, remove empty elements
agent-browser snapshot -d 3            # Limit depth to 3 levels

# Extract specific content
agent-browser get text @e1             # Get text from ref
agent-browser get url                  # Get current URL
agent-browser get title               # Get page title
```

### Interact with Elements

```bash
agent-browser click @e2                # Click element
agent-browser dblclick @e2             # Double-click
agent-browser type @e3 "hello"         # Type into input
agent-browser fill @e4 "test@email"   # Clear and fill
agent-browser select @e5 "Option A"    # Select dropdown
agent-browser check @e6                # Check checkbox
agent-browser uncheck @e7              # Uncheck
agent-browser press Enter              # Press key
```

### Screenshots & PDFs

```bash
agent-browser screenshot page.png      # Take screenshot
agent-browser screenshot --full page.png  # Full page screenshot
agent-browser pdf document.pdf         # Save as PDF
```

### Find Elements

```bash
agent-browser find role button click --name "Submit"
agent-browser find text "Login" click
agent-browser find placeholder "Email" fill --text "user@example.com"
```

### Wait for Elements

```bash
agent-browser wait @e1                 # Wait for element to appear
agent-browser wait 2000                # Wait 2000ms
agent-browser wait --visible @e1       # Wait until visible
```

### Execute JavaScript

```bash
agent-browser eval "document.title"
agent-browser eval "window.scrollTo(0, 1000)"
```

### Manage Sessions

```bash
# Use isolated sessions (separate auth/state)
agent-browser --session session1 open example.com
agent-browser --session session2 open example.com

agent-browser session list             # List active sessions
```

## Tips

- **Always snapshot first** - Get the accessibility tree before interacting to find refs
- **Use `-i` flag** - Interactive elements only for cleaner snapshots
- **Refs are deterministic** - `@e1` from a snapshot always points to the same element
- **Close when done** - Free up resources with `agent-browser close`
- **Use sessions for isolation** - Multiple browser instances with separate auth/state

## Options Reference

Key options:

- `--session <name>` - Isolated session (env: `AGENT_BROWSER_SESSION`)
- `--profile <path>` - Persistent browser profile (env: `AGENT_BROWSER_PROFILE`)
- `--headers <json>` - Custom HTTP headers for auth
- `--headed` - Show browser window (not headless)
- `--json` - JSON output
- `--full, -f` - Full page screenshot

Full reference: `agent-browser --help`

## When to Use vs. Other Tools

| Tool | Use Case |
|------|----------|
| `agent-browser` | Complex sites, JS rendering, forms, screenshots, automation |
| `web_search` | Search queries, multiple results |
| `web_fetch` | Simple text extraction from a single URL |
