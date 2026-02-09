#!/usr/bin/env bash
# serve-artifact.sh — wrap a jsx file in html and serve on tailscale port 8445
set -euo pipefail

ARTIFACTS_DIR="$HOME/.openclaw/workspace/artifacts"
PORT=8445
TS_HOST="picassos-mac-mini.tail38ed59.ts.net"

usage() { echo "usage: $0 <name> <path-to-jsx>"; exit 1; }
[[ $# -lt 2 ]] && usage

NAME="$1"
JSX_FILE="$2"
HTML_FILE="$ARTIFACTS_DIR/${NAME}.html"

[[ ! -f "$JSX_FILE" ]] && echo "error: $JSX_FILE not found" && exit 1

# detect the exported component name
COMPONENT=$(grep -oE 'export default function (\w+)' "$JSX_FILE" | awk '{print $NF}')
[[ -z "$COMPONENT" ]] && COMPONENT=$(grep -oE 'function (\w+)' "$JSX_FILE" | head -1 | awk '{print $NF}')
[[ -z "$COMPONENT" ]] && echo "error: couldn't detect component name" && exit 1

# extract title from first comment or use name
TITLE=$(grep -m1 '// Artifact:' "$JSX_FILE" | sed 's/\/\/ Artifact: //' || echo "$NAME")
[[ -z "$TITLE" ]] && TITLE="$NAME"

# build html
cat > "$HTML_FILE" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${TITLE}</title>
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

HTMLEOF

# append component code: strip imports and export keyword
sed '/^import /d; s/^export default function/function/' "$JSX_FILE" >> "$HTML_FILE"

cat >> "$HTML_FILE" << HTMLEOF

ReactDOM.createRoot(document.getElementById('root')).render(
  React.createElement(${COMPONENT})
);
</script>
</body>
</html>
HTMLEOF

# ensure server is running
if ! curl -s -o /dev/null -w '' "http://127.0.0.1:${PORT}/" 2>/dev/null; then
  cd "$ARTIFACTS_DIR"
  nohup python3 -m http.server "$PORT" --bind 127.0.0.1 > /tmp/artifact-server.log 2>&1 &
  sleep 1
  echo "started artifact server on port $PORT (pid $!)"
fi

# ensure tailscale serve is configured
if ! tailscale serve status 2>/dev/null | grep -q ":${PORT}"; then
  tailscale serve --bg --https "$PORT" "http://127.0.0.1:${PORT}"
fi

echo ""
echo "✓ artifact ready: https://${TS_HOST}:${PORT}/${NAME}.html"
