#!/bin/bash
# Validates code changes against project rules
# Input: JSON with tool_input containing file content
#
# Rules enforced (customize for your project):
# 1. No hardcoded secrets/API keys (JS/TS/Python)
# 2. Use logging instead of print() in Python
# 3. No importing deprecated modules
#
# TODO: Add your project-specific rules here
#
# Output: JSON with decision (approve/block) and optional reason

set -e

# Check for jq dependency - approve if not available (fail open, not closed)
if ! command -v jq &> /dev/null; then
  echo '{"decision": "approve", "reason": "jq not installed - skipping code rules validation"}' >&2
  echo '{"decision": "approve"}'
  exit 0
fi

# Read the tool input from stdin
INPUT=$(cat)

# Extract file path and content from tool input (with fallbacks for jq errors)
# NOTE: Use printf '%s' instead of echo to avoid issues with special characters in JSON
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null || echo "")
NEW_CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // .tool_input.newString // .tool_input.content // empty' 2>/dev/null || echo "")

# Skip if no file path or content
if [ -z "$FILE_PATH" ] || [ -z "$NEW_CONTENT" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Skip files that aren't code files
# TODO: Add or remove file extensions for your project
if [[ ! "$FILE_PATH" =~ \.(ts|tsx|js|jsx|py|go|rs|rb)$ ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Skip test files - they may legitimately use console for debugging
if [[ "$FILE_PATH" =~ (\.test\.|\.spec\.|__tests__|e2e/|tests/) ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi

ERRORS=""

# =============================================================================
# Rule 1: Check for hardcoded secrets (API keys, tokens, passwords)
# Common API key patterns - skip if referencing env vars
# =============================================================================
if echo "$NEW_CONTENT" | grep -qE "(sk_live_|sk_test_|gsk_[a-zA-Z0-9]|phc_[a-zA-Z0-9]|AKIA[A-Z0-9]{16})" && \
   ! echo "$NEW_CONTENT" | grep -qE "(process\.env|os\.environ|os\.getenv|\.env|getenv)"; then
  ERRORS="$ERRORS\n- Hardcoded API key detected. Use environment variables instead."
fi

# MongoDB connection strings with embedded credentials
if echo "$NEW_CONTENT" | grep -qE "mongodb(\+srv)?://[^@]+:[^@]+@" && \
   ! echo "$NEW_CONTENT" | grep -qE "(process\.env|os\.environ|os\.getenv|MONGODB_URI|getenv)"; then
  ERRORS="$ERRORS\n- Hardcoded MongoDB credentials detected. Use environment variable."
fi

# Generic password/secret assignments (not in comments, min 8 chars to avoid false positives)
if echo "$NEW_CONTENT" | grep -qE "^[^#/]*(password|secret|auth_token)\s*[:=]\s*['\"][^'\"]{8,}['\"]" && \
   ! echo "$NEW_CONTENT" | grep -qE "(process\.env|os\.environ|os\.getenv|example|placeholder|xxx|your_)"; then
  ERRORS="$ERRORS\n- Possible hardcoded secret detected. Use environment variables."
fi

# =============================================================================
# Rule 2: Check for print() in Python files (should use logging)
# TODO: Customize if you have a specific logging pattern
# =============================================================================
if [[ "$FILE_PATH" =~ \.py$ ]]; then
  # Match print( but not in comments - skip f-string debugging which is common in dev
  if echo "$NEW_CONTENT" | grep -qE "^[^#]*\bprint\s*\(" && \
     ! echo "$NEW_CONTENT" | grep -qE "(# print|#print|debug_print)"; then
    ERRORS="$ERRORS\n- Use logging instead of print() in Python files"
  fi
fi

# =============================================================================
# Rule 3: Check for console.log in JS/TS files (should use logger)
# TODO: Enable if you want to enforce logger usage
# =============================================================================
# Uncomment to enable:
# if [[ "$FILE_PATH" =~ \.(js|jsx|ts|tsx)$ ]]; then
#   if echo "$NEW_CONTENT" | grep -qE "^[^/]*console\.(log|error|warn)\("; then
#     ERRORS="$ERRORS\n- Use logger instead of console.log/error/warn"
#   fi
# fi

# =============================================================================
# TODO: Add your project-specific rules below
# =============================================================================

# Example: Enforce API URL patterns
# if echo "$NEW_CONTENT" | grep -qE "fetch\(['\"][[:space:]]*/api/"; then
#   ERRORS="$ERRORS\n- Use \${API_BASE_URL}/api/... instead of relative /api/ URLs"
# fi

# Example: Block deprecated module imports
# if echo "$NEW_CONTENT" | grep -qE "(from deprecated_module import|import deprecated_module)"; then
#   ERRORS="$ERRORS\n- deprecated_module is deprecated. Use new_module instead."
# fi

# =============================================================================
# Return result
# =============================================================================
if [ -n "$ERRORS" ]; then
  # Escape the errors for JSON
  ESCAPED_ERRORS=$(echo -e "$ERRORS" | sed 's/"/\\"/g' | tr '\n' ' ')
  echo "{\"decision\": \"block\", \"reason\": \"Code rule violations detected:$ESCAPED_ERRORS\"}"
  exit 0
fi

echo '{"decision": "approve"}'
