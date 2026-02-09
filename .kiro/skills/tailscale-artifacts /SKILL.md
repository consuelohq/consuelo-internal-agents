# tailscale artifacts

serve interactive react artifacts to ko's tailnet on a persistent port. when ko says "artifact" or "tailscale artifact", follow this process.

## how it works

- all artifacts live in `~/.openclaw/workspace/artifacts/`
- port **8445** is the dedicated artifact port — always on, always serving that directory
- tailscale serve proxies `https://picassos-mac-mini.tail38ed59.ts.net:8445/` → `http://127.0.0.1:8445`
- ko accesses from any device on the tailnet (ipad, iphone, macbook air)
- the last artifact served is always available — just swap the html file

## url pattern

```
https://picassos-mac-mini.tail38ed59.ts.net:8445/<filename>.html
```

## creating an artifact

### option 1: use the script (preferred)

```bash
~/.openclaw/workspace/skills/tailscale-artifacts/serve-artifact.sh <name> <path-to-jsx>
```

example:
```bash
~/.openclaw/workspace/skills/tailscale-artifacts/serve-artifact.sh my-dashboard /tmp/dashboard.jsx
```

this will:
1. wrap the jsx in the html template (react 18 + babel standalone + tailwind cdn)
2. copy to `~/.openclaw/workspace/artifacts/<name>.html`
3. ensure the server is running on port 8445
4. print the tailscale url

### option 2: manual process

1. write your react component as a `.jsx` file
2. create an html wrapper:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>ARTIFACT_TITLE</title>
<script src="https://unpkg.com/react@18/umd/react.production.min.js"></script>
<script src="https://unpkg.com/react-dom@18/umd/react-dom.production.min.js"></script>
<script src="https://unpkg.com/@babel/standalone/babel.min.js"></script>
<script src="https://cdn.tailwindcss.com"></script>
<style>body{margin:0;background:#000;}</style>
</head>
<body>
<div id="root"></div>
<script type="text/babel">
const { useState, useEffect, useRef, useMemo, useCallback } = React;

// PASTE COMPONENT CODE HERE (remove import/export lines)

ReactDOM.createRoot(document.getElementById('root')).render(
  React.createElement(COMPONENT_NAME)
);
</script>
</body>
</html>
```

3. save to `~/.openclaw/workspace/artifacts/<name>.html`

### jsx conversion rules

when converting a react artifact to standalone html:
- remove all `import` lines
- replace `export default function` with `function`
- destructure react hooks from `React` at the top: `const { useState, useEffect } = React;`
- replace any `@/components/ui` imports with inline implementations or remove them
- the component renders inside `<div id="root">` with tailwind available

## server management

### server runs on boot (launchd)

the artifact server auto-starts on login via launchd (`com.openclaw.artifact-server`). no manual start needed.

plist: `~/Library/LaunchAgents/com.openclaw.artifact-server.plist`

```bash
# check status
launchctl list | grep artifact

# restart if needed
launchctl unload ~/Library/LaunchAgents/com.openclaw.artifact-server.plist
launchctl load ~/Library/LaunchAgents/com.openclaw.artifact-server.plist
```

### index page

the root url `https://picassos-mac-mini.tail38ed59.ts.net:8445/` shows a directory of all artifacts. ko can bookmark this one url forever. auto-refreshes every 30s.

### tailscale serve setup (one-time, already done)
```bash
tailscale serve --bg --https 8445 http://127.0.0.1:8445
```

### stop tailscale serve
```bash
tailscale serve --https=8445 off
```

### check tailscale serve status
```bash
tailscale serve status
```

## swapping artifacts

just overwrite the html file in the artifacts directory. the python http server serves files live — no restart needed. ko can refresh the browser and see the new artifact instantly.

## when ko says "close the artifact" or "shut down tailscale artifact"

```bash
tailscale serve --https=8445 off
pkill -f "python3 -m http.server 8445"
```

## existing artifacts

check what's available:
```bash
ls ~/.openclaw/workspace/artifacts/*.html
```

## notes

- the server binds to 127.0.0.1 only — not exposed to lan, only via tailscale
- tailwind cdn + babel standalone means no build step needed
- works for any react component, mermaid diagrams, plain html, etc.
- if the server dies, just restart it — tailscale serve config persists
