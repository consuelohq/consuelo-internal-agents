#!/bin/bash
#
# COO Agent Worker Orchestrator
#
# This script processes COO Beads tasks by invoking Claude to generate business
# outputs (emails, leads, tweets, etc.). It is the GENERATION phase of the
# Worker-QA two-session workflow.
#
# IMPORTANT: This worker does NOT:
#   - Send emails (QA does this)
#   - Post tweets (QA does this)
#   - Push to GitHub (QA does this)
#   - Validate outputs (QA does this)
#
# The worker generates outputs to staging, marks tasks as PENDING_QA, and exits.
# The QA session (run-qa.sh) then validates and executes external actions.
#
# Usage:
#   .coo/agent/run-tasks.sh                    # Process all open COO tasks
#   .coo/agent/run-tasks.sh --max-tasks 3      # Process at most 3 tasks
#   .coo/agent/run-tasks.sh --single-task      # Process exactly one task (for launchd)
#   .coo/agent/run-tasks.sh --dry-run          # Preview tasks without processing
#   .coo/agent/run-tasks.sh --task-id XYZ      # Process specific task ID
#
# Prerequisites:
#   - Beads installed (bd command available)
#   - Claude Code CLI installed
#   - Git configured with push access
#   - .coo/.beads/config.yaml exists
#

# Don't use set -e - we want to continue processing tasks even if one fails
# Individual command failures are handled explicitly

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COO_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$COO_DIR")"

# Load configuration
if [ -f "$SCRIPT_DIR/config.sh" ]; then
  source "$SCRIPT_DIR/config.sh"
else
  echo "[ERROR] config.sh not found at $SCRIPT_DIR/config.sh"
  exit 1
fi

# Load notification functions if available
if [ -f "$SCRIPT_DIR/notify.sh" ]; then
  source "$SCRIPT_DIR/notify.sh"
  NOTIFICATIONS_ENABLED=true
else
  NOTIFICATIONS_ENABLED=false
fi

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

MAX_TASKS=0  # 0 means unlimited
DRY_RUN=false
SINGLE_TASK=false
SPECIFIC_TASK_ID=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --max-tasks)
      MAX_TASKS="$2"
      shift 2
      ;;
    --single-task)
      SINGLE_TASK=true
      MAX_TASKS=1
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --task-id)
      SPECIFIC_TASK_ID="$2"
      shift 2
      ;;
    --help)
      echo "COO Agent Worker Orchestrator"
      echo ""
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --max-tasks N    Process at most N tasks (default: unlimited)"
      echo "  --single-task    Process exactly one task (for launchd triggers)"
      echo "  --task-id ID     Process a specific task by ID"
      echo "  --dry-run        Preview tasks without processing"
      echo "  --help           Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                      # Process all open COO tasks"
      echo "  $0 --single-task        # Process one task (for scheduled jobs)"
      echo "  $0 --dry-run            # Preview what would be processed"
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# =============================================================================
# INITIALIZATION
# =============================================================================

TIMESTAMP=$(get_timestamp)
TODAY=$(get_date)
STAGING_PATH=$(get_staging_dir "$TODAY")

# Session tracking
SESSION_START=$(date +%s)
TASKS_PROCESSED=0
TASKS_SUCCEEDED=0
TASKS_FAILED=0

log_info "=========================================="
log_info "COO Agent Worker Orchestrator"
log_info "=========================================="
log_info "Timestamp: $TIMESTAMP"
log_info "Staging: $STAGING_PATH"
log_info "Max tasks: ${MAX_TASKS:-unlimited}"
log_info "Dry run: $DRY_RUN"
log_info "Single task mode: $SINGLE_TASK"
log_info ""

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================

check_prerequisites() {
  log_info "Checking prerequisites..."
  local missing=()

  # Check for Beads
  if ! command -v bd &> /dev/null; then
    missing+=("bd (Beads CLI)")
  fi

  # Check for Claude CLI
  if ! command -v claude &> /dev/null; then
    missing+=("claude (Claude Code CLI)")
  fi

  # Check for jq
  if ! command -v jq &> /dev/null; then
    missing+=("jq (JSON processor)")
  fi

  # Check for git
  if ! command -v git &> /dev/null; then
    missing+=("git")
  fi

  # Check for COO Beads config
  if [ ! -f "$COO_DIR/.beads/config.yaml" ]; then
    missing+=(".coo/.beads/config.yaml")
  fi

  # Check for COO CLAUDE.md
  if [ ! -f "$COO_DIR/CLAUDE.md" ]; then
    missing+=(".coo/CLAUDE.md")
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    log_error "Missing prerequisites:"
    for item in "${missing[@]}"; do
      log_error "  - $item"
    done
    exit 1
  fi

  log_success "All prerequisites satisfied"
}

# =============================================================================
# BEADS TASK FUNCTIONS
# =============================================================================

# Get list of open tasks from COO Beads instance
get_open_tasks() {
  # Use BD_COO which points to COO beads config
  local tasks=$($BD_COO list 2>/dev/null | grep -E "open|pending" || true)

  # Ensure MAX_TASKS is a valid number
  MAX_TASKS=${MAX_TASKS:-0}
  [[ "$MAX_TASKS" =~ ^[0-9]+$ ]] || MAX_TASKS=0

  if [ "$MAX_TASKS" -gt 0 ]; then
    echo "$tasks" | head -n "$MAX_TASKS"
  else
    echo "$tasks"
  fi
}

# Get specific task by ID
get_task_by_id() {
  local task_id="$1"
  $BD_COO show "$task_id" 2>/dev/null
}

# Parse task ID from Beads list output
# Format: ID [PRIORITY] [TYPE] STATUS - TITLE
parse_task_id() {
  echo "$1" | awk '{print $1}'
}

# Parse task title from Beads list output
parse_task_title() {
  # Remove ID, priority bracket, type bracket, and status to get title
  echo "$1" | sed 's/^[^ ]* \[[^]]*\] \[[^]]*\] [^ ]* - //'
}

# Parse task type from Beads list output
parse_task_type() {
  # Extract [TYPE] portion
  echo "$1" | grep -oE '\[[A-Z]+\]' | head -1 | tr -d '[]'
}

# Mark task as pending QA review
mark_pending_qa() {
  local task_id="$1"

  log_info "Marking task $task_id as PENDING_QA..."

  # Add a note to the task (Beads doesn't have built-in status beyond open/closed)
  # We'll use a comment/note to track QA status
  $BD_COO comment "$task_id" "Status: PENDING_QA - Outputs generated to staging, awaiting QA validation" 2>/dev/null || {
    log_warning "Could not add comment to task (bd comment may not be available)"
  }
}

# Mark task as completed by worker
mark_worker_complete() {
  local task_id="$1"
  local output_summary="$2"

  $BD_COO comment "$task_id" "Worker completed: $output_summary" 2>/dev/null || true
}

# =============================================================================
# BRANCH MANAGEMENT
# =============================================================================

create_branch_name() {
  local task_id="$1"
  local task_title="$2"

  # Sanitize title for branch name: lowercase, replace spaces/special chars with dashes
  local sanitized_title=$(echo "$task_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | head -c 40)

  # Remove trailing dashes
  sanitized_title=$(echo "$sanitized_title" | sed 's/-*$//')

  echo "coo/${task_id}-${sanitized_title}"
}

setup_branch() {
  local branch_name="$1"

  log_info "Setting up branch: $branch_name"

  # Fetch and checkout main (or coo-main if exists)
  git fetch origin main 2>/dev/null || true

  # Checkout main
  git checkout main 2>/dev/null || true
  git pull origin main 2>/dev/null || true

  # Create new branch for this task
  git checkout -b "$branch_name" 2>/dev/null || git checkout "$branch_name" 2>/dev/null || {
    log_warning "Could not create branch $branch_name"
  }
}

# =============================================================================
# OUTPUT GENERATION
# =============================================================================

# Get task-specific instructions based on task type
get_task_instructions() {
  local task_type="$1"
  local task_title="$2"
  local staging_path="$3"

  case "$task_type" in
    "RESEARCH")
      # Sub-cases for RESEARCH type based on title keywords
      if echo "$task_title" | grep -qi "prospect"; then
        cat << RESEARCH_PROSPECT_EOF
## Research Task Instructions

You are conducting prospect research for sales outreach.

**Output Requirements:**
1. Create a CSV file at: $staging_path/leads.csv
2. Required columns: name,email,phone,company,title,source,notes
3. Phone numbers MUST be in E.164 format (+1XXXXXXXXXX)
4. Include 50-100 prospects per research session
5. Focus on your target customer segment

**Research Sources to Use:**
- LinkedIn (via search patterns)
- Company directories
- Industry associations
- Public databases

**Quality Guidelines:**
- Verify email patterns match company domains
- Include job title for targeting
- Note the source for each lead
- Flag any uncertain data with [UNVERIFIED]

Save your output to: $staging_path/leads.csv
RESEARCH_PROSPECT_EOF
      elif echo "$task_title" | grep -qi "instagram"; then
        cat << RESEARCH_INSTAGRAM_EOF
## Instagram Prospect Research

Find Instagram profiles for target customer professionals and companies.

**Output Requirements:**
1. Create JSON file at: $staging_path/instagram.json
2. Format: [{"handle": "@username", "name": "Full Name", "company": "Company", "follower_count": 1000, "context": "Why they're relevant"}]
3. Include 20-30 profiles per session
4. Focus on active accounts with engagement

Save your output to: $staging_path/instagram.json
RESEARCH_INSTAGRAM_EOF
      else
        cat << RESEARCH_GENERAL_EOF
## Research Task

Conduct research as specified in the task description.
Save all outputs to: $staging_path/

Use appropriate file formats:
- CSV for structured data (leads, contacts)
- JSON for nested/complex data
- TXT for notes and summaries
RESEARCH_GENERAL_EOF
      fi
      ;;

    "OUTREACH")
      local email_limit=$(get_email_limit)
      local warmup_day=$(get_warmup_day)
      cat << OUTREACH_EOF
## Email Outreach Task Instructions

You are generating cold outreach emails.

**Email Warm-up Status:**
- Current day: $warmup_day
- Maximum emails: $email_limit

**Output Requirements:**
1. Create CSV file at: $staging_path/emails.csv
2. Required columns: email,first_name,company,subject,body,variant
3. Generate EXACTLY $email_limit emails (warm-up limit)
4. Include A/B variants (variant column: A or B)

**Email Guidelines:**
- Subject lines: Personalized, curiosity-driven, under 50 chars
- Body: Short (3-4 sentences), benefit-focused, clear CTA
- Personalization: Use {first_name} and company context
- Tone: Professional but conversational, not salesy

**A/B Testing:**
- Variant A: Lead with pain point
- Variant B: Lead with benefit/outcome

Save your output to: $staging_path/emails.csv
OUTREACH_EOF
      ;;

    "CONTENT")
      # Sub-cases for CONTENT type based on title keywords
      if echo "$task_title" | grep -qi "thread"; then
        cat << CONTENT_THREAD_EOF
## Twitter Thread Task

Create an educational Twitter thread about your industry topic.

**Output Requirements:**
1. Create JSON file at: $staging_path/twitter-thread.json
2. Format: {"thread": [{"tweet": "Tweet 1 content", "position": 1}, ...]}
3. Thread length: 5-8 tweets
4. Each tweet under 280 characters
5. Include 1-2 relevant hashtags per tweet

**Content Guidelines:**
- Hook: Strong opening that creates curiosity
- Value: Each tweet should provide standalone insight
- CTA: Final tweet should drive engagement or visit

Save your output to: $staging_path/twitter-thread.json
CONTENT_THREAD_EOF
      else
        cat << CONTENT_POST_EOF
## Twitter Post Task

Create a single Twitter post.

**Output Requirements:**
1. Create JSON file at: $staging_path/tweets.json
2. Format: [{"content": "Tweet text here", "scheduled_time": "HH:MM"}]
3. Tweet must be under 280 characters
4. Include 1-2 relevant hashtags

**Content Guidelines:**
- Be insightful, not promotional
- Focus on your expertise area
- Drive engagement with questions or takes
- Avoid generic B2B speak

Save your output to: $staging_path/tweets.json
CONTENT_POST_EOF
      fi
      ;;

    "METRICS")
      cat << METRICS_EOF
## Metrics Update Task

Update the tracking metrics for COO operations.

**Output Requirements:**
1. Review existing metrics in $SCRIPT_DIR/metrics.json
2. Create summary report at: $staging_path/metrics-summary.txt
3. Include: tasks completed, emails sent, engagement rates

**Guidelines:**
- Calculate week-over-week changes
- Flag any anomalies or concerns
- Suggest optimizations based on data

Save your output to: $staging_path/metrics-summary.txt
METRICS_EOF
      ;;

    *)
      cat << GENERAL_EOF
## General Task

Complete the task as described. Save all outputs to: $staging_path/

Use appropriate file formats based on output type.
GENERAL_EOF
      ;;
  esac
}

# =============================================================================
# TASK PROCESSING
# =============================================================================

process_task() {
  local task_line="$1"
  local task_id=$(parse_task_id "$task_line")
  local task_title=$(parse_task_title "$task_line")
  local task_type=$(parse_task_type "$task_line")
  local branch_name=$(create_branch_name "$task_id" "$task_title")

  log_info "=========================================="
  log_info "Processing task: $task_id"
  log_info "Type: $task_type"
  log_info "Title: $task_title"
  log_info "Branch: $branch_name"
  log_info "=========================================="

  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY RUN] Would process task $task_id"
    log_info "[DRY RUN] Would create branch: $branch_name"
    log_info "[DRY RUN] Would generate outputs to: $STAGING_PATH"
    return 0
  fi

  # Create staging directory for today
  mkdir -p "$STAGING_PATH"

  # Setup branch (COO agent works on main)
  setup_branch "$branch_name"

  # Get task-specific instructions
  local task_instructions=$(get_task_instructions "$task_type" "$task_title" "$STAGING_PATH")

  # Build the agent prompt
  local agent_prompt="You are working as the COO Agent, processing task $task_id.

## Task Details
- **ID:** $task_id
- **Type:** $task_type
- **Title:** $task_title
- **Staging Directory:** $STAGING_PATH

## COO Context
Read and follow the instructions in .coo/CLAUDE.md for business context and voice guidelines.

$task_instructions

## Important Notes
1. All outputs go to the staging directory: $STAGING_PATH
2. Do NOT send emails, post tweets, or make external API calls
3. Do NOT push to GitHub - the QA session handles this
4. Focus on generating high-quality outputs for QA validation

## Workflow
1. Read .coo/CLAUDE.md for context
2. Research if needed (for prospect research tasks)
3. Generate the required outputs
4. Save files to the staging directory
5. Provide a summary of what you created

Begin by reading .coo/CLAUDE.md, then execute the task."

  # Write prompt to temp file for safe handling
  local prompt_file=$(mktemp)
  echo "$agent_prompt" > "$prompt_file"

  # Invoke Claude
  log_info "Invoking Claude Code agent..."

  local start_time=$(date +%s)

  # Use --print for non-interactive mode
  $CLAUDE_CMD "$(cat "$prompt_file")"
  local agent_exit_code=$?

  local end_time=$(date +%s)
  local duration=$((end_time - start_time))

  rm -f "$prompt_file"

  if [ $agent_exit_code -ne 0 ]; then
    log_warning "Agent exited with code $agent_exit_code"
  fi

  # Check if outputs were generated
  local output_count=$(ls -1 "$STAGING_PATH" 2>/dev/null | wc -l | tr -d ' ')

  if [ "$output_count" -gt 0 ]; then
    log_success "Generated $output_count output file(s) in staging"

    # List generated files
    log_info "Generated files:"
    ls -la "$STAGING_PATH" | tail -n +2 | while read -r line; do
      log_info "  $line"
    done

    # Mark task as pending QA
    mark_pending_qa "$task_id"
    mark_worker_complete "$task_id" "Generated $output_count files in staging ($duration seconds)"

    # Update metrics
    if [ "$NOTIFICATIONS_ENABLED" = true ]; then
      update_metric "tasks_completed" 1
      update_metric "total_duration_mins" $((duration / 60))
    fi

    # Log to progress file
    update_progress_log "$task_id" "$task_title" "$task_type" "completed" "$output_count" "$duration"

    return 0
  else
    log_warning "No output files generated for task $task_id"

    if [ "$NOTIFICATIONS_ENABLED" = true ]; then
      update_metric "tasks_failed" 1
    fi

    update_progress_log "$task_id" "$task_title" "$task_type" "no_output" "0" "$duration"

    return 1
  fi
}

# =============================================================================
# PROGRESS LOGGING
# =============================================================================

update_progress_log() {
  local task_id="$1"
  local task_title="$2"
  local task_type="$3"
  local status="$4"
  local output_count="$5"
  local duration="$6"

  local progress_file="$SCRIPT_DIR/coo-progress.txt"

  cat >> "$progress_file" << EOF

## Worker Session $TIMESTAMP - Task $task_id

**Task:** $task_title
**Type:** $task_type
**Status:** $status
**Outputs:** $output_count files
**Duration:** ${duration}s
**Staging:** $STAGING_PATH

---
EOF
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
  check_prerequisites

  cd "$PROJECT_ROOT" || exit 1

  # Ensure directories exist
  ensure_directories

  # Get tasks to process
  local tasks=""

  if [ -n "$SPECIFIC_TASK_ID" ]; then
    # Process specific task
    log_info "Processing specific task: $SPECIFIC_TASK_ID"
    tasks=$(get_task_by_id "$SPECIFIC_TASK_ID")
  else
    # Get open tasks from COO Beads
    tasks=$(get_open_tasks)
  fi

  if [ -z "$tasks" ]; then
    log_success "No open COO tasks to process"

    if [ "$NOTIFICATIONS_ENABLED" = true ]; then
      send_slack_notification \
        "COO Worker: No Tasks" \
        "No open tasks in COO queue" \
        "info"
    fi

    exit 0
  fi

  log_info "Found tasks to process:"
  echo "$tasks" | while read -r line; do
    [ -n "$line" ] && echo "  - $line"
  done
  echo ""

  # Notify task run started
  if [ "$NOTIFICATIONS_ENABLED" = true ] && [ "$DRY_RUN" = false ]; then
    local task_count=$(echo "$tasks" | grep -c .)
    send_slack_notification \
      "COO Worker Started" \
      "Processing $task_count task(s)" \
      "info"
    update_metric "tasks_started" "$task_count"
  fi

  # Save tasks to temp file to avoid stdin issues
  local tasks_file=$(mktemp)
  echo "$tasks" > "$tasks_file"

  local task_count=$(wc -l < "$tasks_file" | tr -d ' ')

  # Process each task
  for i in $(seq 1 "$task_count"); do
    local task_line=$(sed -n "${i}p" "$tasks_file")

    if [ -n "$task_line" ]; then
      TASKS_PROCESSED=$((TASKS_PROCESSED + 1))

      if process_task "$task_line"; then
        TASKS_SUCCEEDED=$((TASKS_SUCCEEDED + 1))
      else
        TASKS_FAILED=$((TASKS_FAILED + 1))
      fi

      # Return to base branch for next task
      git checkout main 2>/dev/null || true

      echo ""
    fi
  done

  rm -f "$tasks_file"

  # Calculate session duration
  local session_end=$(date +%s)
  local session_duration=$((session_end - SESSION_START))

  # Final summary
  log_info "=========================================="
  log_info "COO Worker Session Complete"
  log_info "=========================================="
  log_info "Duration: ${session_duration}s"
  log_info "Processed: $TASKS_PROCESSED"
  log_info "Succeeded: $TASKS_SUCCEEDED"
  log_info "Failed: $TASKS_FAILED"
  log_info "Staging: $STAGING_PATH"

  # Send completion notification
  if [ "$NOTIFICATIONS_ENABLED" = true ] && [ "$DRY_RUN" = false ]; then
    local status_type="success"
    [ "$TASKS_FAILED" -gt 0 ] && status_type="warning"

    send_slack_notification \
      "COO Worker Complete" \
      "Processed: $TASKS_PROCESSED | Succeeded: $TASKS_SUCCEEDED | Failed: $TASKS_FAILED | Duration: ${session_duration}s" \
      "$status_type"
  fi

  # Exit with failure code if any tasks failed
  [ "$TASKS_FAILED" -gt 0 ] && exit 1
  exit 0
}

# =============================================================================
# RUN
# =============================================================================

main "$@"
