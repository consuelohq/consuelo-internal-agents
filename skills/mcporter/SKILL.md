---
name: mcporter
description: Call MCP servers via MCPorter - browser automation, vision, and other MCP tools
homepage: https://github.com/steipete/mcporter
metadata:
  {
    "openclaw":
      {
        "emoji": "🧳",
        "requires": { "bins": ["npx"] }
      }
  }

# MCPorter

MCPorter is a TypeScript runtime and CLI that bridges OpenClaw to Model Context Protocol (MCP) servers. Use this skill to:
- **Browser automation** via chrome-devtools MCP (snapshots, clicks, forms, navigation, screenshots)
- **Vision analysis** via Z.AI MCP server (images, videos)
- **Code automation** via Playwright MCP
- Any other MCP server configured in MCPorter

## Quick Start

### List available MCP servers and tools
```bash
npx mcporter list
```

### Call a specific MCP tool
```bash
# Chrome DevTools examples (✅ working - tested with GitHub.com)
npx mcporter call chrome-devtools.take_snapshot
npx mcporter call chrome-devtools.navigate_page type:url url:"https://example.com"
npx mcporter call chrome-devtools.take_screenshot format:png
npx mcporter call chrome-devtools.click uid:"element-id"
npx mcporter call chrome-devtools.fill uid:"input-id" value:"hello world"
npx mcporter call chrome-devtools.evaluate_script function:"() => document.title"
npx mcporter call chrome-devtools.list_pages
npx mcporter call chrome-devtools.list_console_messages
npx mcporter call chrome-devtools.list_network_requests

# Z.AI Vision examples (⚠️ requires Z_AI_API_KEY)
npx mcporter call zai-vision.image_analysis filePath:"/path/to/image.png"
npx mcporter call zai-vision.video_analysis filePath:"/path/to/video.mp4"
```

## Key MCP Servers

### chrome-devtools (26 tools)
**Browser automation and inspection:**
- `take_snapshot` — Page snapshot (a11y tree with element UIDs)
- `click` — Click element by UID
- `hover` — Hover over element
- `drag` — Drag element to drop target
- `fill` — Fill form input
- `fill_form` — Fill multiple form elements
- `navigate_page` — Navigate (url/back/forward/reload)
- `new_page` — Open new page
- `select_page` — Select page context
- `close_page` — Close page
- `take_screenshot` — Screenshot (PNG/JPEG/WebP)
- `evaluate_script` — Run JavaScript
- `press_key` — Keyboard input
- `resize_page` — Resize viewport
- `emulate` — Network/CPU/geolocation/user agent emulation
- `list_console_messages` — Console logs
- `list_network_requests` — Network logs
- `get_console_message` — Get specific console message
- `get_network_request` — Get specific network request
- `upload_file` — Upload via file input
- `handle_dialog` — Handle browser dialogs
- `wait_for` — Wait for text/element
- `performance_start_trace` / `performance_stop_trace` — Performance tracing
- `performance_analyze_insight` — Analyze performance insights

### microsoft/playwright-mcp (22 tools)
Browser automation via Playwright (currently has connection issues).

### zai-vision (requires Z_AI_API_KEY)
**Image and video analysis:**
- `ui_to_artifact` — UI screenshots to code/specs/prompts
- `extract_text_from_screenshot` — OCR and text extraction from screenshots
- `diagnose_error_screenshot` — Analyze error screenshots and provide solutions
- `understand_technical_diagram` — Diagram interpretation (architecture, flow, UML, ER)
- `analyze_data_visualization` — Charts and dashboard analysis
- `ui_diff_check` — Compare two UIs to identify differences
- `image_analysis` — General-purpose image understanding (fallback)
- `video_analysis` — Video understanding (≤8MB, MP4/MOV/M4V)

### upstash/context7 (2 tools)
Library documentation:
- `resolve_library_id` — Get library ID
- `get_library_docs` — Fetch library docs

## Configuration

### View current MCP servers
```bash
npx mcporter list
```

### Add a new MCP server
```bash
npx mcporter config add <name> <target>

# Examples:
npx mcporter config add zai-vision "npx -y @z_ai/mcp-server"
npx mcporter config add chrome-devtools "npx -y chrome-devtools-mcp@latest"
```

### Set API keys for MCP servers that need them
```bash
export Z_AI_API_KEY=your-key-here

# Or add to shell profile (~/.zshrc, ~/.bashrc, ~/.config/fish/config.fish)
echo 'export Z_AI_API_KEY=your-key-here' >> ~/.zshrc
```

## Notes

### MCPorter auto-discovers MCP servers from:
- Cursor (~/.cursor/mcp.json)
- Claude Desktop (~/.claude.json)
- Claude Code (~/.claude-desktop/mcp.json)
- Codex (~/Library/Application Support/Code/User/mcp.json)
- VS Code
- Windsurf
- OpenCode

### Workspace config
OpenClaw's MCPorter config lives at: `/Users/kokayi/.openclaw/workspace/config/mcporter.json`

Current configured servers:
- `chrome-devtools` (26 tools) — ✅ Working (via stdio)
- `zai-vision` (8 tools) — ⚠️ Needs Z_AI_API_KEY

### Auto-discovered servers
The following MCP servers are auto-discovered from ~/.claude.json:
- `chrome-devtools` (from Claude Desktop) — 26 tools, browser automation
- `upstash/context7` (from Code) — 2 tools, library docs

**Note:** Auto-discovered servers are available via their source tools (e.g., Claude Desktop, VS Code) but may not be directly accessible through MCPorter CLI without importing them to the workspace config.

### When to use MCP tools
- **Browser automation** — Use `chrome-devtools` MCP tools
- **Vision/OCR** — Use `zai-vision` MCP tools (requires API key)
- **Complex workflows** — Combine multiple MCP calls

### Syntax variations (all work)
```bash
# Function-call style (recommended)
npx mcporter call 'chrome-devtools.click(uid: "element-id")'

# Flag style
npx mcporter call chrome-devtools.click uid:"element-id"

# Colon-delimited
npx mcporter call chrome-devtools.click uid:"element-id"
```

## Troubleshooting

### "tools unavailable" error
If you see "tools unavailable" for a server, it means:
- MCP server is not running (for stdio)
- Connection failed (for HTTP)
- Missing API keys or auth

### Fix for microsoft/playwright-mcp
Currently shows SSE/connection errors. This is a known issue with the MCP server.

### Z.AI MCP requires API key
Set environment variable:
```bash
export Z_AI_API_KEY=your-zai-api-key
```
Or add to MCPorter config (already configured ✅):
```json
{
  "mcpServers": {
    "zai-vision": {
      "command": "npx -y @z_ai/mcp-server",
      "env": {
        "Z_AI_API_KEY": "your-zai-api-key"
      }
    }
  }
}
```

**✅ Configured:** Z.AI API key is set in MCPorter config. Vision tools are ready to use!

## Resources

- MCPorter docs: https://github.com/steipete/mcporter
- MCP spec: https://modelcontextprotocol.io/
