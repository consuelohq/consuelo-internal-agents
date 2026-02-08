#!/bin/bash
#
# Kiro Specs Watcher Configuration
#
# This file configures the specs-watcher.sh script that polls Linear for
# kiro-tagged tasks and spawns Kiro sessions to code them.
#

# =============================================================================
# PATHS
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(dirname "$SCRIPT_DIR")"
WORKFLOW_ROOT="$(dirname "$SKILLS_ROOT")"

KIRO_AGENT="$SCRIPT_DIR/kiro_agent.py"
GITHUB_DEV="$SKILLS_ROOT/github-dev/dev"
LINEAR_API="$SCRIPT_DIR/linear-api-kiro.sh"
STATE_FILE="$SCRIPT_DIR/.specs-watcher-state.json"

# =============================================================================
# LINEAR SETTINGS
# =============================================================================

# Linear API key (set via environment variable)
LINEAR_API_KEY="${LINEAR_API_KEY:-}"

# Team: development
LINEAR_TEAM_ID="${LINEAR_TEAM_ID:-29f5c661-da6c-4bfb-bd48-815a006ccaac}"

# Label name to filter issues
LINEAR_LABEL_NAME="kiro"
LINEAR_LABEL_KIRO_ID="04de73b2-9801-4690-8e9d-5890e5e14d6a"

# Workflow state names + IDs
LINEAR_STATE_OPEN="Open"
LINEAR_STATE_OPEN_ID="1160621c-7a00-4945-9093-47ba33862b7e"

LINEAR_STATE_IN_PROGRESS="In Progress"
LINEAR_STATE_IN_PROGRESS_ID="d8f29981-a8ce-451d-8910-ca8c04af01b2"

LINEAR_STATE_IN_REVIEW="In Review"
LINEAR_STATE_IN_REVIEW_ID="9646d767-0fa0-4163-8315-1c2a4fa9fad0"

LINEAR_STATE_DONE="Done"
LINEAR_STATE_DONE_ID="3dce5724-2643-4151-a66b-7f7b8d152bd2"

# =============================================================================
# GITHUB SETTINGS
# =============================================================================

# Repo for kiro work
GITHUB_REPO="${GITHUB_REPO:-kokayicobb/consuelo_on_call_coaching}"

# Branch settings
BASE_BRANCH="main"
BRANCH_PREFIX="kiro"

# =============================================================================
# KIRO SETTINGS
# =============================================================================

# Working directory for kiro (for local file reads)
KIRO_CWD="/Users/kokayi/Dev/consuelo_on_call_coaching"

# =============================================================================
# SLACK NOTIFICATIONS
# =============================================================================

SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"

# =============================================================================
# POLLING SETTINGS
# =============================================================================

# How often to poll (in seconds) - typically 1800 (30 min) for cron
POLL_INTERVAL="${POLL_INTERVAL:-1800}"

# Maximum tasks per run (0 = unlimited)
MAX_TASKS_PER_RUN="${MAX_TASKS_PER_RUN:-1}"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

get_github_repo() {
    if [ -n "$GITHUB_REPO" ]; then
        echo "$GITHUB_REPO"
    else
        cd "$KIRO_CWD" && gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null
    fi
}

send_slack() {
    local message="$1"
    local color="${2:-#36a64f}"  # green by default

    if [ -z "$SLACK_WEBHOOK_URL" ]; then
        echo "[SLACK] $message"
        return
    fi

    curl -s -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"$message\", \"attachments\":[{\"color\":\"$color\"}]}" \
        "$SLACK_WEBHOOK_URL" 2>/dev/null || echo "[SLACK ERROR] Failed to send"
}
