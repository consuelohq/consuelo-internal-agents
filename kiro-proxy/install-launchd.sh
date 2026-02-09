#!/bin/bash
# Install kiro-proxy as a launchd agent (auto-start on login + auto-restart)

PLIST_NAME="com.consuelo.kiro-proxy"
PLIST_SRC="$(dirname "$0")/${PLIST_NAME}.plist"
PLIST_DST="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"

# Unload if already loaded
launchctl unload "$PLIST_DST" 2>/dev/null

# Copy plist to LaunchAgents
cp "$PLIST_SRC" "$PLIST_DST"
echo "copied plist to $PLIST_DST"

# Load it
launchctl load "$PLIST_DST"
echo "loaded $PLIST_NAME"

# Verify
sleep 2
if lsof -i :18794 >/dev/null 2>&1; then
    echo "✓ kiro-proxy is running on port 18794"
else
    echo "⚠ kiro-proxy may not have started — check /tmp/kiro-proxy-stderr.log"
fi
