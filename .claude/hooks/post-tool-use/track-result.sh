#!/bin/bash
# Track tool results to help loop detection
#
# This hook runs AFTER a Bash command completes.
# If the command succeeded (no error), it resets the failure counter
# so that successful commands break the loop detection pattern.
#
# This is a companion to loop-detection.sh in pre-tool-use/

STATE_FILE="${HOME}/.claude/hooks/loop-state.json"

# Ensure jq is available
if ! command -v jq &> /dev/null; then
  exit 0
fi

# Parse tool result from environment variable
TOOL_INPUT="${CLAUDE_TOOL_USE_INPUT:-}"
TOOL_RESULT="${CLAUDE_TOOL_USE_RESULT:-}"

if [[ -z "$TOOL_INPUT" ]]; then
  exit 0
fi

TOOL_NAME=$(echo "$TOOL_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Only track Bash commands
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

# Check if result contains an error
if [[ -n "$TOOL_RESULT" ]]; then
  HAS_ERROR=$(echo "$TOOL_RESULT" | jq -r '.error // empty' 2>/dev/null)

  # If command succeeded (no error), reset the failure counter
  if [[ -z "$HAS_ERROR" ]] && [[ -f "$STATE_FILE" ]]; then
    jq '.consecutive_failures = 0' "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null && mv "${STATE_FILE}.tmp" "$STATE_FILE"
  fi
fi

exit 0
