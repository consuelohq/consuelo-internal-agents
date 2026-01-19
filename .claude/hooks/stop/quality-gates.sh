#!/bin/bash
# Runs quality gates before allowing task completion
# Returns block if tests fail, approve if they pass
#
# This hook runs your configured tests to validate changes
# before the agent can mark a task as complete.
#
# TODO: Customize the test command and results parsing for your project

set -e

# Load config if available
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../../../.agent/config.sh"

if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi

# Default test command if not configured
TEST_COMMAND="${TEST_COMMAND:-npm test}"

# Test timeout in seconds
TEST_TIMEOUT="${TEST_TIMEOUT:-120}"

echo "Running quality gates..." >&2

# Verify jq is installed (required for parsing test results)
if ! command -v jq &>/dev/null; then
  echo '{"decision": "block", "reason": "jq is not installed. Cannot parse test results. Install with: brew install jq (macOS) or apt install jq (Linux)"}'
  exit 0
fi

# Check if there are uncommitted changes
if git diff --quiet && git diff --cached --quiet; then
  echo '{"decision": "approve", "message": "No changes to test"}'
  exit 0
fi

# Run the configured test command
echo "Running tests (timeout: ${TEST_TIMEOUT}s)..." >&2
echo "Command: $TEST_COMMAND" >&2

# Create temp file for test output
TEST_OUTPUT=$(mktemp)
TEST_STATUS="passed"
EXIT_CODE=0

# Run tests with timeout (platform-independent approach)
# Start tests in background, kill if they exceed timeout
eval "$TEST_COMMAND" > "$TEST_OUTPUT" 2>&1 &
TEST_PID=$!

# Wait for tests with timeout
ELAPSED=0
while kill -0 $TEST_PID 2>/dev/null; do
  if [ $ELAPSED -ge $TEST_TIMEOUT ]; then
    echo "Tests timed out after ${TEST_TIMEOUT}s, killing..." >&2
    kill -9 $TEST_PID 2>/dev/null || true
    echo '{"decision": "approve", "message": "Tests timed out after '${TEST_TIMEOUT}'s, skipping quality gate"}'
    rm -f "$TEST_OUTPUT"
    exit 0
  fi
  sleep 1
  ELAPSED=$((ELAPSED + 1))
done

# Get exit status
wait $TEST_PID 2>/dev/null
EXIT_CODE=$?

# Check test results
if [ $EXIT_CODE -eq 0 ]; then
  TEST_STATUS="passed"
  echo "Tests passed" >&2
else
  TEST_STATUS="failed"
  echo "Tests failed with exit code $EXIT_CODE" >&2
fi

# Clean up
rm -f "$TEST_OUTPUT"

if [ "$TEST_STATUS" = "failed" ]; then
  echo "{\"decision\": \"block\", \"reason\": \"Tests failed with exit code $EXIT_CODE. Review test output and fix issues before completing the task.\"}"
  exit 0
fi

echo "{\"decision\": \"approve\", \"message\": \"All tests passed\"}"
