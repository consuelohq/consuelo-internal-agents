#!/bin/bash
# Updates Beads with session results when agent finishes
#
# This hook is called at the end of a Claude Code session.
# It updates the current task in Beads and appends to claude-progress.txt

set -e

# Get the current task from environment (set during session)
CURRENT_TASK_ID="${BEADS_CURRENT_TASK:-}"
PROGRESS_FILE=".agent/claude-progress.txt"

# Function to get current timestamp in ISO format
get_timestamp() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# Function to append to progress file
append_progress() {
  local task="$1"
  local status="$2"
  local summary="$3"
  local blockers="$4"

  # Get changed files from git
  local files_changed
  files_changed=$(git diff --name-only HEAD~1 2>/dev/null | head -10 | tr '\n' ', ' | sed 's/,$//' || echo "None")

  cat >> "$PROGRESS_FILE" << EOF

---

## Session $(get_timestamp)

**Task**: $task
**Status**: $status
**Files Changed**: $files_changed

**Summary**: $summary

**Blockers**: $blockers

EOF
}

# Check if Beads is available
if ! command -v bd &> /dev/null; then
  echo "Beads (bd) not found, skipping Beads update" >&2
  exit 0
fi

# Update progress file if it exists
if [ -f "$PROGRESS_FILE" ]; then
  # Default values
  TASK_DESC="Session work"
  STATUS="Completed"
  SUMMARY="Session completed"
  BLOCKERS="None"

  # Get current task description from Beads if available
  if [ -n "$CURRENT_TASK_ID" ]; then
    TASK_DESC=$(bd show "$CURRENT_TASK_ID" --json 2>/dev/null | jq -r '.title // "Session work"' || echo "Session work")
  fi

  append_progress "$TASK_DESC" "$STATUS" "$SUMMARY" "$BLOCKERS"
fi

# Update Beads task if we have a current task
if [ -n "$CURRENT_TASK_ID" ]; then
  # Mark task as completed in Beads
  bd close "$CURRENT_TASK_ID" --reason "Session completed" 2>/dev/null || true
  echo "Task $CURRENT_TASK_ID marked as completed" >&2
else
  echo "No active Beads task to update" >&2
fi

# Sync Beads
bd sync 2>/dev/null || true

# Send Slack notification on session end (if notify.sh exists)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NOTIFY_SCRIPT="$SCRIPT_DIR/../../../.agent/notify.sh"

if [ -f "$NOTIFY_SCRIPT" ]; then
  source "$NOTIFY_SCRIPT"

  # Get files changed for notification
  notify_files=$(git diff --name-only HEAD~1 2>/dev/null | head -5 | tr '\n' ', ' | sed 's/,$//' || echo "None")

  send_slack_notification \
    "Agent Session Ended" \
    "*Task:* $TASK_DESC\n*Status:* $STATUS\n*Files:* $notify_files" \
    "success" 2>/dev/null || true
fi

exit 0
