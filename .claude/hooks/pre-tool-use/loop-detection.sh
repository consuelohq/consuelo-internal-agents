#!/bin/bash
# Loop detection - prevents agent from getting stuck retrying blocked commands
#
# This hook tracks consecutive attempts of the same Bash command.
# If a command is attempted 3+ times in a row (regardless of why it fails),
# the hook blocks with explicit "SKIP this task" guidance and sends a Slack notification.
#
# This catches:
# - Commands that require approval but agent keeps retrying
# - Commands that fail with the same error repeatedly
# - Any runaway loop behavior

STATE_FILE="${HOME}/.claude/hooks/loop-state.json"
MAX_CONSECUTIVE_FAILURES=3
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"

# Ensure jq is available
if ! command -v jq &> /dev/null; then
  echo '{"decision": "approve", "reason": "jq not installed - loop detection disabled"}'
  exit 0
fi

# Parse incoming tool use from environment variable
TOOL_INPUT="${CLAUDE_TOOL_USE_INPUT:-}"
if [[ -z "$TOOL_INPUT" ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi

TOOL_NAME=$(echo "$TOOL_INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$TOOL_INPUT" | jq -r '.input.command // empty')

# Only track Bash commands
if [[ "$TOOL_NAME" != "Bash" ]] || [[ -z "$COMMAND" ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Generate command signature (hash of the command string)
# Using md5 on macOS, md5sum on Linux
if command -v md5 &> /dev/null; then
  CMD_HASH=$(echo "$COMMAND" | md5 | head -c 8)
elif command -v md5sum &> /dev/null; then
  CMD_HASH=$(echo "$COMMAND" | md5sum | head -c 8)
else
  # Fallback: use first 50 chars of command as signature
  CMD_HASH=$(echo "$COMMAND" | head -c 50 | tr -d '\n' | sed 's/[^a-zA-Z0-9]/_/g')
fi

# Ensure parent directory exists
mkdir -p "$(dirname "$STATE_FILE")"

# Initialize state file if needed
if [[ ! -f "$STATE_FILE" ]]; then
  echo '{"consecutive_failures":0,"last_command_hash":"","last_command":""}' > "$STATE_FILE"
fi

# Read current state
LAST_HASH=$(jq -r '.last_command_hash // ""' "$STATE_FILE" 2>/dev/null || echo "")
FAILURES=$(jq -r '.consecutive_failures // 0' "$STATE_FILE" 2>/dev/null || echo "0")

# Ensure FAILURES is a number
if ! [[ "$FAILURES" =~ ^[0-9]+$ ]]; then
  FAILURES=0
fi

# Check if same command being retried
if [[ "$CMD_HASH" == "$LAST_HASH" ]]; then
  FAILURES=$((FAILURES + 1))
else
  # Different command, reset counter
  FAILURES=1
fi

# Truncate command for storage (first 200 chars)
TRUNCATED_CMD=$(echo "$COMMAND" | head -c 200)

# Update state file
jq --arg hash "$CMD_HASH" \
   --argjson failures "$FAILURES" \
   --arg cmd "$TRUNCATED_CMD" \
   '.last_command_hash = $hash | .consecutive_failures = $failures | .last_command = $cmd' \
   "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null && mv "${STATE_FILE}.tmp" "$STATE_FILE"

# If too many consecutive attempts, block and notify
if [[ $FAILURES -ge $MAX_CONSECUTIVE_FAILURES ]]; then
  # Send Slack notification if webhook configured
  if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
    # Escape the command for JSON
    ESCAPED_CMD=$(echo "${COMMAND:0:100}" | sed 's/"/\\"/g' | tr '\n' ' ')

    curl -s -X POST "$SLACK_WEBHOOK_URL" \
      -H 'Content-Type: application/json' \
      -d "{\"text\":\"Agent stuck in loop! Command attempted $FAILURES times:\\n\\\`${ESCAPED_CMD}...\\\`\\n\\nLoop detection triggered - agent instructed to skip.\"}" \
      > /dev/null 2>&1 &
  fi

  # Reset counter so next different command can proceed
  jq '.consecutive_failures = 0' "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null && mv "${STATE_FILE}.tmp" "$STATE_FILE"

  # Block with explicit skip guidance
  cat << EOF
{"decision": "block", "reason": "LOOP DETECTED: This command has been attempted $FAILURES times consecutively without success. STOP retrying this command immediately. You MUST: 1) Mark the current task as BLOCKED with reason 'Command requires approval or repeatedly fails', 2) Move to the NEXT task in your todo list, 3) Do NOT attempt this same command again. The command was: ${TRUNCATED_CMD:0:80}..."}
EOF
  exit 0
fi

# Allow the command to proceed
echo '{"decision": "approve"}'
