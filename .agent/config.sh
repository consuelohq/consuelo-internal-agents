#!/bin/bash
#
# Agent Configuration
#
# Edit this file to customize the agent workflow for your project.
# This is a TEMPLATE - update the values below for your specific project.
#

# =============================================================================
# AGENT CLI SELECTION
# =============================================================================

# Choose your agent CLI: "claude" or "opencode"
# TODO: Change if using OpenCode instead of Claude Code
AGENT_CLI="claude"

# CLI invocation patterns
CLAUDE_CMD="claude --print"
OPENCODE_CMD="opencode"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

get_agent_cmd() {
  if [ "$AGENT_CLI" = "claude" ]; then
    echo "$CLAUDE_CMD"
  else
    echo "$OPENCODE_CMD"
  fi
}

# =============================================================================
# TASK PROCESSING SETTINGS
# =============================================================================

# Maximum retries for failed tasks before flagging for review
MAX_RETRIES=1

# Timeout for agent execution (in seconds, 0 = no timeout)
AGENT_TIMEOUT=0

# Whether to run tests after each task (true/false)
RUN_TESTS_AFTER_TASK=true

# Which tests to run for validation
# TODO: Update this for your project's test command
# Examples:
#   - npm test
#   - pytest
#   - make test
#   - npx playwright test e2e/tests/
TEST_COMMAND="npm test"

# =============================================================================
# GIT SETTINGS
# =============================================================================

# Base branch for agent work (PRs target this branch)
# TODO: Update to your main development branch (e.g., "main", "develop")
BASE_BRANCH="main"

# Branch prefix for agent-created branches
BRANCH_PREFIX="agent"

# =============================================================================
# NOTIFICATION SETTINGS
# =============================================================================

# Slack webhook for notifications (optional)
# Set via environment variable in ~/.zshrc or ~/.bashrc:
#   export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T.../B.../..."
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"

# =============================================================================
# PROJECT-SPECIFIC SETTINGS
# TODO: Add any project-specific configuration below
# =============================================================================

# Example: Custom test timeout
# TEST_TIMEOUT=180

# Example: Additional environment setup
# export NODE_ENV=test
