#!/bin/bash
# .agent/watch.sh — poll linear for kiro-assigned tasks, run one at a time
# Usage: .agent/watch.sh [--interval 30]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERVAL=${1:-30}
LOCKFILE="/tmp/kiro-watch.lock"

# prevent double-runs
if [ -f "$LOCKFILE" ] && kill -0 "$(cat "$LOCKFILE")" 2>/dev/null; then
  echo "already running (pid $(cat "$LOCKFILE"))"
  exit 1
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

echo "watching linear every ${INTERVAL}s..."

while true; do
  "$SCRIPT_DIR/run-tasks.sh" --linear --max-tasks 1 2>&1 | tail -20
  sleep "$INTERVAL"
done
