#!/bin/bash
#
# COO Agent Configuration
#
# This file configures the COO (Chief Operating Officer) agent for autonomous
# business/GTM task processing. It handles paths, environment variables,
# and settings specific to the COO agent workflow.
#
# Usage: source this file from other COO agent scripts
#   source "$(dirname "$0")/config.sh"
#

# =============================================================================
# PROJECT PATHS
# =============================================================================

# Root of the project (absolute path for launchd compatibility)
# TODO: Set this to your project root path
PROJECT_ROOT=""

if [ -z "$PROJECT_ROOT" ]; then
  echo "[ERROR] PROJECT_ROOT not set in config.sh"
  echo "Edit .coo/agent/config.sh and set PROJECT_ROOT to your project path"
  exit 1
fi

# COO directory structure
COO_DIR="$PROJECT_ROOT/.coo"
AGENT_DIR="$COO_DIR/agent"

# Staging directory - Worker outputs go here before QA validation
# Date-based subdirectories created automatically
STAGING_DIR="$AGENT_DIR/staging"

# Outputs directory - Final validated outputs after QA passes
OUTPUTS_DIR="$AGENT_DIR/outputs"

# State directory - Persistent state (warmup day counter, etc.)
STATE_DIR="$AGENT_DIR/state"

# Logs directory - launchd logs go to /tmp, but we can use this for internal logs
LOG_DIR="/tmp/coo-agent"

# Beads configuration for COO tasks (separate instance)
BEADS_CONFIG="$COO_DIR/.beads/config.yaml"

# Progress file for session continuity
PROGRESS_FILE="$AGENT_DIR/coo-progress.txt"

# Metrics file for tracking daily stats
METRICS_FILE="$AGENT_DIR/metrics.json"

# =============================================================================
# AGENT CLI SELECTION
# =============================================================================

# Choose your agent CLI: "claude" or "opencode"
COO_AGENT_CLI="claude"

# Claude Code invocation
# --print: Non-interactive mode, outputs to stdout
CLAUDE_CMD="claude --print"

# OpenCode invocation (adjust based on OpenCode's CLI interface)
OPENCODE_CMD="opencode"

# Get the appropriate command based on current CLI selection
get_agent_cmd() {
  if [ "$COO_AGENT_CLI" = "claude" ]; then
    echo "$CLAUDE_CMD"
  else
    echo "$OPENCODE_CMD"
  fi
}

# bd-coo command (uses separate Beads instance)
BD_COO="bd --config $BEADS_CONFIG"

# =============================================================================
# API KEY REFERENCES
# =============================================================================
# These should be set in ~/.zshrc or .coo/.env
# The config file references them but does NOT contain actual keys

# --- Core Keys (Required) ---
# RESEND_API_KEY      - Email sending via Resend
# GROQ_API_KEY        - LLM API for agent (if using Groq)

# --- Research Keys (At least one recommended) ---
# CLAY_API_KEY        - Lead enrichment (clay.com)
# APOLLO_API_KEY      - B2B contact data (apollo.io)

# --- Social Media Keys (Optional) ---
# TWITTER_API_KEY     - Twitter API key
# TWITTER_API_SECRET  - Twitter API secret
# TWITTER_BEARER_TOKEN - Twitter bearer token
# INSTAGRAM_ACCESS_TOKEN - Instagram Graph API

# --- Other Integrations ---
# GOOGLE_SHEETS_CREDENTIALS - Path to service account JSON
# BROWSE_AI_API_KEY   - Web scraping robots (browse.ai)
# SLACK_WEBHOOK_URL   - Notifications

# Helper function to check required API keys
check_api_keys() {
  local missing_keys=()

  # Core keys (required for basic operation)
  [ -z "$RESEND_API_KEY" ] && missing_keys+=("RESEND_API_KEY")

  # Optional but recommended
  [ -z "$SLACK_WEBHOOK_URL" ] && echo "WARNING: SLACK_WEBHOOK_URL not set - notifications disabled"

  if [ ${#missing_keys[@]} -gt 0 ]; then
    echo "ERROR: Missing required API keys: ${missing_keys[*]}"
    echo "Set these in ~/.zshrc or $COO_DIR/.env"
    return 1
  fi

  return 0
}

# Helper function to check integration-specific keys
check_integration_keys() {
  local integration="$1"

  case "$integration" in
    "email"|"outreach")
      [ -z "$RESEND_API_KEY" ] && { echo "ERROR: RESEND_API_KEY required for email"; return 1; }
      ;;
    "twitter")
      [ -z "$TWITTER_BEARER_TOKEN" ] && { echo "ERROR: TWITTER_BEARER_TOKEN required for Twitter"; return 1; }
      ;;
    "research"|"prospects")
      [ -z "$CLAY_API_KEY" ] && [ -z "$APOLLO_API_KEY" ] && {
        echo "ERROR: CLAY_API_KEY or APOLLO_API_KEY required for prospect research"; return 1;
      }
      ;;
    "instagram")
      [ -z "$INSTAGRAM_ACCESS_TOKEN" ] && { echo "ERROR: INSTAGRAM_ACCESS_TOKEN required"; return 1; }
      ;;
    "metrics"|"sheets")
      [ -z "$GOOGLE_SHEETS_CREDENTIALS" ] && { echo "ERROR: GOOGLE_SHEETS_CREDENTIALS required"; return 1; }
      ;;
    *)
      echo "Unknown integration: $integration"
      return 1
      ;;
  esac

  return 0
}

# =============================================================================
# TASK PROCESSING SETTINGS
# =============================================================================

# Maximum retries for failed tasks before flagging for review
MAX_RETRIES=1

# Timeout for agent execution (in seconds, 0 = no timeout)
AGENT_TIMEOUT=300

# Whether to run QA validation after task completion
RUN_QA_AFTER_TASK=true

# =============================================================================
# EMAIL WARM-UP SETTINGS
# =============================================================================

# Email warm-up schedule (daily limits based on warmup day)
# Day 1-3:  10 emails/day
# Day 4-7:  25 emails/day
# Day 8-14: 50 emails/day
# Day 15+:  100 emails/day

get_email_limit() {
  local warmup_day="${1:-1}"

  if [ "$warmup_day" -le 3 ]; then
    echo 10
  elif [ "$warmup_day" -le 7 ]; then
    echo 25
  elif [ "$warmup_day" -le 14 ]; then
    echo 50
  else
    echo 100
  fi
}

# Read current warmup day from state
get_warmup_day() {
  local warmup_file="$STATE_DIR/warmup-day.txt"
  if [ -f "$warmup_file" ]; then
    cat "$warmup_file"
  else
    echo 1
  fi
}

# Increment warmup day (call daily)
increment_warmup_day() {
  local warmup_file="$STATE_DIR/warmup-day.txt"
  local current_day
  current_day=$(get_warmup_day)
  echo $((current_day + 1)) > "$warmup_file"
}

# =============================================================================
# VALIDATION SETTINGS
# =============================================================================

# Required fields for email CSV validation
EMAIL_CSV_REQUIRED_FIELDS="email,first_name,subject,body"

# Required fields for leads CSV validation
LEADS_CSV_REQUIRED_FIELDS="name,email"

# Email regex pattern (basic validation)
EMAIL_REGEX="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"

# Phone regex pattern (E.164 format)
PHONE_REGEX="^\+1[0-9]{10}$"

# Instagram handle regex
INSTAGRAM_REGEX="^[a-zA-Z0-9._]{1,30}$"

# Twitter max characters
TWITTER_MAX_CHARS=280

# Twitter minimum hashtags per post
TWITTER_MIN_HASHTAGS=1

# =============================================================================
# GIT SETTINGS
# =============================================================================

# Base branch for COO agent work (no PR required, just push)
COO_BASE_BRANCH="main"

# Branch prefix for COO agent-created branches
COO_BRANCH_PREFIX="coo-agent"

# Create branch name for a task
get_branch_name() {
  local task_id="$1"
  local task_title="$2"

  # Sanitize title: lowercase, replace spaces with dashes, remove special chars
  local sanitized
  sanitized=$(echo "$task_title" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')

  echo "${COO_BRANCH_PREFIX}/${task_id}-${sanitized}"
}

# =============================================================================
# NOTIFICATION SETTINGS
# =============================================================================

# Slack webhook for notifications (from environment)
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"

# Send Slack notification
send_slack_notification() {
  local message="$1"
  local emoji="${2:-:robot_face:}"

  if [ -z "$SLACK_WEBHOOK_URL" ]; then
    echo "WARNING: Slack notification skipped - SLACK_WEBHOOK_URL not set"
    return 0
  fi

  curl -s -X POST -H 'Content-type: application/json' \
    --data "{\"text\": \"$emoji $message\"}" \
    "$SLACK_WEBHOOK_URL" > /dev/null 2>&1
}

# =============================================================================
# OUTPUT DIRECTORY HELPERS
# =============================================================================

# Get today's staging directory (creates if needed)
get_staging_dir() {
  local date_arg="${1:-$(date +%Y-%m-%d)}"
  local date_dir="$STAGING_DIR/$date_arg"
  mkdir -p "$date_dir"
  echo "$date_dir"
}

# Get output directory for a specific type (emails, leads, twitter, instagram)
get_output_dir() {
  local output_type="$1"
  local output_dir="$OUTPUTS_DIR/$output_type"
  mkdir -p "$output_dir"
  echo "$output_dir"
}

# Ensure all required directories exist
ensure_directories() {
  mkdir -p "$STAGING_DIR"
  mkdir -p "$OUTPUTS_DIR/emails"
  mkdir -p "$OUTPUTS_DIR/leads"
  mkdir -p "$OUTPUTS_DIR/twitter"
  mkdir -p "$OUTPUTS_DIR/instagram"
  mkdir -p "$STATE_DIR"
  mkdir -p "$LOG_DIR"
}

# =============================================================================
# TIMESTAMP HELPERS
# =============================================================================

get_timestamp() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

get_date() {
  date +%Y-%m-%d
}

# =============================================================================
# LOGGING HELPERS
# =============================================================================

# Log with timestamp
log_coo() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp=$(date +%Y-%m-%dT%H:%M:%SZ)
  echo "[$timestamp] [$level] $message" >> "$LOG_DIR/coo-agent.log"
}

log_info() {
  log_coo "INFO" "$1"
  echo "[INFO] $1"
}

log_error() {
  log_coo "ERROR" "$1"
  echo "[ERROR] $1" >&2
}

log_warning() {
  log_coo "WARN" "$1"
  echo "[WARN] $1"
}

log_success() {
  log_coo "INFO" "$1"
  echo "[SUCCESS] $1"
}

log_qa() {
  log_coo "QA" "$1"
  echo "[QA] $1"
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Source .env file if it exists (for API keys)
if [ -f "$COO_DIR/.env" ]; then
  # shellcheck disable=SC1091
  source "$COO_DIR/.env"
fi

# Ensure directories exist when config is sourced
ensure_directories
