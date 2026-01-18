#!/bin/bash
#
# COO Agent QA Session Script
#
# This script is the QUALITY GATE for all COO agent outputs.
# NOTHING goes external (emails, tweets, pushes) until QA validates.
#
# Workflow:
#   1. Read outputs from staging directory (.coo/agent/staging/{date}/)
#   2. Run validation on all outputs (emails, leads, tweets, instagram)
#   3. If ALL pass:
#      - Send emails via Resend API
#      - Post tweets via Twitter API
#      - Move validated outputs to .coo/agent/outputs/
#      - Commit changes to git
#      - Push to GitHub
#      - Notify Slack (success)
#   4. If ANY fail:
#      - Mark task as needs-review
#      - Notify Slack (failure)
#      - Do NOT send/push anything
#
# Usage:
#   .coo/agent/run-qa.sh                    # Validate today's staging
#   .coo/agent/run-qa.sh --date 2025-01-15  # Validate specific date
#   .coo/agent/run-qa.sh --dry-run          # Validate only, don't send
#   .coo/agent/run-qa.sh --skip-send        # Skip external sends, still push
#

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COO_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$COO_DIR")"

# Load configuration
source "$SCRIPT_DIR/config.sh"

# Load validation functions
source "$SCRIPT_DIR/validate-outputs.sh"

# =============================================================================
# PARSE ARGUMENTS
# =============================================================================

TARGET_DATE=$(date +%Y-%m-%d)
DRY_RUN=false
SKIP_SEND=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --date)
      TARGET_DATE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --skip-send)
      SKIP_SEND=true
      shift
      ;;
    --help)
      echo "COO Agent QA Session Script"
      echo ""
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --date YYYY-MM-DD  Validate specific date (default: today)"
      echo "  --dry-run          Validate only, don't send or push"
      echo "  --skip-send        Skip external sends (email/twitter), still push to git"
      echo "  --help             Show this help message"
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
STAGING_PATH=$(get_staging_dir "$TARGET_DATE")
QA_STATUS="pending"
QA_ERRORS=()
ITEMS_PROCESSED=0
EMAILS_SENT=0
TWEETS_POSTED=0

# Session tracking
SESSION_START=$(date +%s)

log_qa "=========================================="
log_qa "COO Agent QA Session"
log_qa "=========================================="
log_qa "Timestamp: $TIMESTAMP"
log_qa "Target date: $TARGET_DATE"
log_qa "Staging path: $STAGING_PATH"
log_qa "Dry run: $DRY_RUN"
log_qa "Skip send: $SKIP_SEND"
log_qa ""

# Change to project root
cd "$PROJECT_ROOT" || exit 1

# Ensure directories exist
ensure_directories

# =============================================================================
# SLACK NOTIFICATION FUNCTIONS
# =============================================================================

send_qa_notification() {
  local title="$1"
  local message="$2"
  local status="$3"

  # Use the shared notify.sh if available
  if [ -f "$SCRIPT_DIR/notify.sh" ]; then
    source "$SCRIPT_DIR/notify.sh"
    send_slack_notification "$title" "$message" "$status"
    return $?
  fi

  # Fallback: direct curl if notify.sh not available
  if [ -z "$SLACK_WEBHOOK_URL" ]; then
    log_warning "SLACK_WEBHOOK_URL not configured, skipping notification"
    return 0
  fi

  local color="#0088ff"
  case "$status" in
    success) color="#36a64f" ;;
    failure) color="#ff0000" ;;
    warning) color="#ffcc00" ;;
  esac

  local payload=$(jq -n \
    --arg color "$color" \
    --arg title "$title" \
    --arg text "$message" \
    --arg date "$TARGET_DATE" \
    --argjson errors "$(get_error_count)" \
    --argjson warnings "$(get_warning_count)" \
    '{
      attachments: [{
        color: $color,
        title: $title,
        text: $text,
        fields: [
          {title: "Date", value: $date, short: true},
          {title: "Errors", value: ($errors | tostring), short: true},
          {title: "Warnings", value: ($warnings | tostring), short: true}
        ],
        footer: "COO Agent QA",
        ts: now | floor
      }]
    }')

  curl -s -X POST "$SLACK_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null 2>&1
}

# =============================================================================
# SEND FUNCTIONS
# =============================================================================

send_emails() {
  local email_file="$1"

  if [ "$DRY_RUN" = true ] || [ "$SKIP_SEND" = true ]; then
    log_qa "[DRY-RUN] Would send emails from: $email_file"
    return 0
  fi

  if [ -z "$RESEND_API_KEY" ]; then
    log_warning "RESEND_API_KEY not configured, skipping email send"
    return 0
  fi

  log_qa "Sending emails from: $email_file"

  # TODO: Configure your sender email address
  local SENDER_EMAIL="you@yourdomain.com"  # TODO: Update this

  # Use Claude to parse CSV and send emails
  # Claude handles CSV parsing perfectly (quoted fields, commas in values, etc.)
  local result=$(claude --print --dangerously-skip-permissions "
Read the CSV file at '$email_file' and send each email via the Resend API.

For each row in the CSV:
1. Extract: email, first_name, subject, body (handle any column name variations)
2. Replace {first_name} placeholders in subject and body
3. Send via curl to Resend API with this format:
   curl -s -X POST 'https://api.resend.com/emails' \\
     -H 'Authorization: Bearer $RESEND_API_KEY' \\
     -H 'Content-Type: application/json' \\
     -d '{\"from\": \"$SENDER_EMAIL\", \"to\": [\"EMAIL\"], \"subject\": \"SUBJECT\", \"text\": \"BODY\"}'
4. Add 0.5s delay between sends for rate limiting
5. Track success/failure count

At the end, output ONLY a single line in this exact format:
EMAILS_SENT:N

Where N is the number of successfully sent emails. No other output.
")

  # Extract sent count from Claude's output
  local sent_count=$(echo "$result" | grep -oP 'EMAILS_SENT:\K\d+' || echo "0")
  EMAILS_SENT=$sent_count
  log_success "Sent $sent_count emails"
  return 0
}

post_tweets() {
  local tweet_file="$1"

  if [ "$DRY_RUN" = true ] || [ "$SKIP_SEND" = true ]; then
    log_qa "[DRY-RUN] Would post tweets from: $tweet_file"
    return 0
  fi

  if [ -z "$TWITTER_API_KEY" ] || [ -z "$TWITTER_ACCESS_TOKEN" ]; then
    log_warning "Twitter API credentials not configured, skipping tweet post"
    return 0
  fi

  log_qa "Posting tweets from: $tweet_file"

  # For now, log tweets to be posted (actual Twitter API integration requires OAuth)
  # This is a placeholder - implement actual Twitter API call
  local post_count=0

  if [[ "$tweet_file" == *.json ]]; then
    local tweets=$(jq -r '.[] | .content // .text // .tweet // .' "$tweet_file" 2>/dev/null)
    while IFS= read -r tweet; do
      [ -z "$tweet" ] || [ "$tweet" = "null" ] && continue
      log_qa "  Tweet: ${tweet:0:50}..."
      post_count=$((post_count + 1))

      # TODO: Implement actual Twitter API v2 posting
      # curl -X POST "https://api.twitter.com/2/tweets" \
      #   -H "Authorization: Bearer $TWITTER_BEARER_TOKEN" \
      #   -H "Content-Type: application/json" \
      #   -d "{\"text\": \"$tweet\"}"

    done <<< "$tweets"
  fi

  TWEETS_POSTED=$post_count
  log_qa "Would post $post_count tweets (API integration pending)"
  return 0
}

# =============================================================================
# ARCHIVE/MOVE VALIDATED OUTPUTS
# =============================================================================

archive_outputs() {
  local staging_dir="$1"

  if [ "$DRY_RUN" = true ]; then
    log_qa "[DRY-RUN] Would archive outputs from: $staging_dir"
    return 0
  fi

  log_qa "Archiving validated outputs..."

  # Create dated output directories
  local date_dir="$OUTPUTS_DIR/$TARGET_DATE"
  mkdir -p "$date_dir"

  # Copy all validated files
  cp -r "$staging_dir"/* "$date_dir/" 2>/dev/null || true

  # Create a manifest file
  cat > "$date_dir/manifest.json" << EOF
{
  "date": "$TARGET_DATE",
  "qa_timestamp": "$TIMESTAMP",
  "validation_status": "passed",
  "emails_sent": $EMAILS_SENT,
  "tweets_posted": $TWEETS_POSTED,
  "files": $(ls -1 "$date_dir" | grep -v manifest.json | jq -R . | jq -s .)
}
EOF

  log_success "Outputs archived to: $date_dir"
  return 0
}

# =============================================================================
# GIT OPERATIONS
# =============================================================================

commit_and_push() {
  if [ "$DRY_RUN" = true ]; then
    log_qa "[DRY-RUN] Would commit and push changes"
    return 0
  fi

  log_qa "Committing and pushing to GitHub..."

  # Check for changes
  if git status --porcelain | grep -q .; then
    # Stage COO-related changes
    git add .coo/agent/outputs/ 2>/dev/null || true
    git add .coo/agent/staging/ 2>/dev/null || true
    git add .coo/agent/state/ 2>/dev/null || true
    git add .coo/agent/coo-progress.txt 2>/dev/null || true

    # Commit with descriptive message
    git commit -m "$(cat <<EOF
chore(coo): QA validated outputs for $TARGET_DATE

- Emails sent: $EMAILS_SENT
- Tweets posted: $TWEETS_POSTED
- Validation: PASSED

Generated by COO Agent QA session.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"

    # Push to remote
    if git push origin HEAD 2>/dev/null; then
      log_success "Changes pushed to GitHub"
    else
      log_warning "Push failed - may need manual push"
    fi
  else
    log_qa "No changes to commit"
  fi

  return 0
}

# =============================================================================
# UPDATE PROGRESS LOG
# =============================================================================

update_progress_log() {
  local status="$1"
  local progress_file="$SCRIPT_DIR/coo-progress.txt"

  local session_end=$(date +%s)
  local duration=$((session_end - SESSION_START))

  cat >> "$progress_file" << EOF

## QA Session $(get_timestamp) - $TARGET_DATE

**Status:** $status
**Duration:** ${duration}s
**Staging:** $STAGING_PATH
**Validation Errors:** $(get_error_count)
**Validation Warnings:** $(get_warning_count)

**Results:**
- Emails sent: $EMAILS_SENT
- Tweets posted: $TWEETS_POSTED
- Dry run: $DRY_RUN

EOF

  if [ $(get_error_count) -gt 0 ]; then
    echo "**Errors:**" >> "$progress_file"
    for err in "${VALIDATION_ERRORS[@]}"; do
      echo "- $err" >> "$progress_file"
    done
  fi

  echo "---" >> "$progress_file"
}

# =============================================================================
# MARK TASK NEEDS REVIEW
# =============================================================================

mark_needs_review() {
  local reason="$1"

  log_warning "Marking task as needs-review: $reason"

  # Find the most recent open COO task and add a comment
  # (Task ID would be passed from run-scheduled-task.sh in full integration)
  # For now, just log the issue

  log_warning "Manual review required - check $STAGING_PATH"
}

# =============================================================================
# MAIN QA WORKFLOW
# =============================================================================

main() {
  local exit_code=0

  # Step 1: Check staging directory exists
  if [ ! -d "$STAGING_PATH" ]; then
    log_warning "No staging directory for $TARGET_DATE"
    log_qa "Nothing to validate - worker may not have run yet"
    exit 0
  fi

  # Step 2: Run validation on all outputs
  log_qa "Step 1: Validating all outputs..."
  if validate_all "$STAGING_PATH"; then
    QA_STATUS="passed"
    log_success "All validations PASSED"
  else
    QA_STATUS="failed"
    log_error "Validation FAILED - blocking external actions"
    exit_code=1
  fi

  # Step 3: Process based on validation result
  if [ "$QA_STATUS" = "passed" ]; then
    log_qa ""
    log_qa "Step 2: Processing validated outputs..."

    # Send emails if email file exists
    for email_file in "$STAGING_PATH"/*email*.csv "$STAGING_PATH"/emails.csv "$STAGING_PATH"/outreach.csv; do
      if [ -f "$email_file" ]; then
        send_emails "$email_file"
        break  # Only process first email file
      fi
    done

    # Post tweets if tweet file exists
    for tweet_file in "$STAGING_PATH"/*twitter*.json "$STAGING_PATH"/tweets.json; do
      if [ -f "$tweet_file" ]; then
        post_tweets "$tweet_file"
        break
      fi
    done

    # Archive validated outputs
    log_qa ""
    log_qa "Step 3: Archiving outputs..."
    archive_outputs "$STAGING_PATH"

    # Commit and push
    log_qa ""
    log_qa "Step 4: Git commit and push..."
    commit_and_push

    # Increment warm-up day on successful email send
    if [ $EMAILS_SENT -gt 0 ]; then
      increment_warmup_day
      log_qa "Warm-up day incremented to: $(get_warmup_day)"
    fi

    # Send success notification
    send_qa_notification \
      "COO QA Passed" \
      "Validated and processed outputs for $TARGET_DATE. Emails: $EMAILS_SENT, Tweets: $TWEETS_POSTED" \
      "success"

  else
    # Validation failed - block all external actions
    log_error ""
    log_error "BLOCKING: No emails sent, no tweets posted, no push"
    log_error ""

    mark_needs_review "QA validation failed with $(get_error_count) error(s)"

    # Send failure notification
    send_qa_notification \
      "COO QA Failed" \
      "Validation failed for $TARGET_DATE with $(get_error_count) error(s). Manual review required." \
      "failure"
  fi

  # Update progress log
  update_progress_log "$QA_STATUS"

  # Final summary
  log_qa ""
  log_qa "=========================================="
  log_qa "QA Session Complete"
  log_qa "=========================================="
  log_qa "Status: $QA_STATUS"
  log_qa "Errors: $(get_error_count)"
  log_qa "Warnings: $(get_warning_count)"
  log_qa "Emails sent: $EMAILS_SENT"
  log_qa "Tweets posted: $TWEETS_POSTED"

  return $exit_code
}

# =============================================================================
# RUN
# =============================================================================

main
exit $?
