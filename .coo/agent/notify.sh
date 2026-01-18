#!/bin/bash
#
# COO Agent Slack Notification System
#
# Provides specialized notification functions for the COO agent workflow:
# - Task started/completed notifications
# - QA validation pass/fail alerts
# - Email send confirmations
# - Daily metrics summaries
#
# Usage:
#   source .coo/agent/notify.sh
#   notify_task_started "task-id" "task-title"
#   notify_qa_passed "task-id" "summary"
#   notify_qa_failed "task-id" "reason" "details"
#   notify_emails_sent 50 "Day 4" "75% AI-branded"
#   notify_daily_summary
#
# Requires SLACK_WEBHOOK_URL environment variable to be set.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METRICS_FILE="$SCRIPT_DIR/metrics.json"
RESET_HOUR_UTC=8  # 3 AM EST = 08:00 UTC

# Source config if available
if [ -f "$SCRIPT_DIR/config.sh" ]; then
  source "$SCRIPT_DIR/config.sh"
fi

# =============================================================================
# METRICS MANAGEMENT
# =============================================================================

# Initialize metrics file if it doesn't exist
init_metrics() {
  if [[ ! -f "$METRICS_FILE" ]]; then
    local today=$(date -u +%Y-%m-%d)
    cat > "$METRICS_FILE" << EOF
{
  "date": "$today",
  "reset_hour_utc": $RESET_HOUR_UTC,
  "tasks_started": 0,
  "tasks_completed": 0,
  "tasks_failed": 0,
  "qa_passed": 0,
  "qa_failed": 0,
  "emails_sent": 0,
  "tweets_posted": 0,
  "prospects_researched": 0,
  "leads_generated": 0,
  "total_duration_mins": 0,
  "warmup_day": 1,
  "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  fi
}

# Check if metrics should be reset (3 AM EST = 08:00 UTC)
should_reset_metrics() {
  init_metrics

  local current_hour=$(date -u +%H | sed 's/^0//')
  local current_date=$(date -u +%Y-%m-%d)
  local metrics_date=$(jq -r '.date // ""' "$METRICS_FILE" 2>/dev/null)

  # If no date in metrics, reset
  if [[ -z "$metrics_date" || "$metrics_date" == "null" ]]; then
    return 0
  fi

  # If current hour >= reset hour and metrics date is not today
  if [[ "$current_hour" -ge "$RESET_HOUR_UTC" ]] && [[ "$metrics_date" != "$current_date" ]]; then
    return 0
  fi

  return 1
}

# Reset metrics to zero (preserves warmup_day)
reset_metrics() {
  init_metrics

  local today=$(date -u +%Y-%m-%d)
  local warmup_day=$(jq -r '.warmup_day // 1' "$METRICS_FILE" 2>/dev/null)

  # Increment warmup day on daily reset
  warmup_day=$((warmup_day + 1))

  cat > "$METRICS_FILE" << EOF
{
  "date": "$today",
  "reset_hour_utc": $RESET_HOUR_UTC,
  "tasks_started": 0,
  "tasks_completed": 0,
  "tasks_failed": 0,
  "qa_passed": 0,
  "qa_failed": 0,
  "emails_sent": 0,
  "tweets_posted": 0,
  "prospects_researched": 0,
  "leads_generated": 0,
  "total_duration_mins": 0,
  "warmup_day": $warmup_day,
  "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  echo "COO metrics reset for $today (warm-up day $warmup_day)" >&2
}

# Update a specific metric
# Usage: update_metric "tasks_completed" 1  (increment by 1)
# Usage: update_metric "emails_sent" 50    (increment by 50)
update_metric() {
  local metric_name="$1"
  local increment="${2:-1}"

  init_metrics

  # Check if reset needed
  if should_reset_metrics; then
    reset_metrics
  fi

  # Read current value and increment
  local current_value=$(jq -r ".$metric_name // 0" "$METRICS_FILE")
  local new_value=$((current_value + increment))

  # Update the metric
  jq --arg metric "$metric_name" \
     --argjson value "$new_value" \
     --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '.[$metric] = $value | .last_updated = $updated' \
     "$METRICS_FILE" > "${METRICS_FILE}.tmp" && mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
}

# Get metrics summary for display
get_metrics_summary() {
  init_metrics

  if should_reset_metrics; then
    reset_metrics
  fi

  local completed=$(jq -r '.tasks_completed // 0' "$METRICS_FILE")
  local failed=$(jq -r '.tasks_failed // 0' "$METRICS_FILE")
  local emails=$(jq -r '.emails_sent // 0' "$METRICS_FILE")
  local tweets=$(jq -r '.tweets_posted // 0' "$METRICS_FILE")
  local prospects=$(jq -r '.prospects_researched // 0' "$METRICS_FILE")
  local leads=$(jq -r '.leads_generated // 0' "$METRICS_FILE")
  local warmup_day=$(jq -r '.warmup_day // 1' "$METRICS_FILE")

  echo "Tasks: $completed done, $failed failed | Emails: $emails | Tweets: $tweets | Prospects: $prospects | Leads: $leads | Warmup Day: $warmup_day"
}

# =============================================================================
# CORE SLACK NOTIFICATION FUNCTION
# =============================================================================

# Base Slack notification function
# Usage: send_slack_notification "title" "message" "status" ["extra_fields_json"]
send_slack_notification() {
  local title="$1"
  local message="$2"
  local status="${3:-info}"
  local extra_fields="${4:-[]}"

  # Check for webhook URL
  if [ -z "$SLACK_WEBHOOK_URL" ]; then
    echo "[COO] SLACK_WEBHOOK_URL not configured, skipping notification" >&2
    return 0
  fi

  # Color based on status
  local color="#0088ff"  # blue (info)
  case "$status" in
    success) color="#36a64f" ;;  # green
    failure) color="#ff0000" ;;  # red
    warning) color="#ffcc00" ;;  # yellow
  esac

  # Get repo name for context
  local repo_name
  repo_name=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" || echo "project")

  # Get current branch
  local branch
  branch=$(git branch --show-current 2>/dev/null || echo "unknown")

  # Get metrics summary
  local metrics_summary
  metrics_summary=$(get_metrics_summary)

  # Build base fields
  local base_fields='[
    {"title": "Repo", "value": "'"$repo_name"'", "short": true},
    {"title": "Branch", "value": "'"$branch"'", "short": true},
    {"title": "Today Stats", "value": "'"$metrics_summary"'", "short": false}
  ]'

  # Merge extra fields if provided
  local all_fields
  if [ "$extra_fields" != "[]" ]; then
    all_fields=$(echo "$base_fields" "$extra_fields" | jq -s 'add')
  else
    all_fields="$base_fields"
  fi

  # Build payload using jq for safe JSON construction
  local payload
  payload=$(jq -n \
    --arg color "$color" \
    --arg title "$title" \
    --arg text "$message" \
    --argjson fields "$all_fields" \
    --argjson ts "$(date +%s)" \
    '{
      attachments: [{
        color: $color,
        title: $title,
        text: $text,
        fields: $fields,
        footer: "COO Agent",
        footer_icon: "https://platform.slack-edge.com/img/default_application_icon.png",
        ts: $ts
      }]
    }')

  # Send to Slack
  curl -s -X POST "$SLACK_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null 2>&1

  local result=$?
  if [ $result -eq 0 ]; then
    echo "[COO] Slack notification sent: $title" >&2
  else
    echo "[COO] Failed to send Slack notification" >&2
  fi
  return $result
}

# =============================================================================
# SPECIALIZED NOTIFICATION FUNCTIONS
# =============================================================================

# Notify when a task starts
notify_task_started() {
  local task_id="$1"
  local task_title="$2"

  update_metric "tasks_started" 1

  local extra_fields='[
    {"title": "Task ID", "value": "'"$task_id"'", "short": true},
    {"title": "Status", "value": "Started by scheduler", "short": true}
  ]'

  send_slack_notification \
    ":rocket: Task Started" \
    "$task_title" \
    "info" \
    "$extra_fields"
}

# Notify when worker generates output (staging)
notify_worker_output() {
  local task_id="$1"
  local output_summary="$2"

  local staging_dir=$(get_staging_dir 2>/dev/null || echo ".coo/agent/staging/$(date +%Y-%m-%d)")

  local extra_fields='[
    {"title": "Task ID", "value": "'"$task_id"'", "short": true},
    {"title": "Stage", "value": "Pending QA validation", "short": true},
    {"title": "Staging", "value": "'"$staging_dir"'", "short": false}
  ]'

  send_slack_notification \
    ":package: Worker Output Generated" \
    "$output_summary" \
    "info" \
    "$extra_fields"
}

# Notify when QA validation passes
notify_qa_passed() {
  local task_id="$1"
  local summary="$2"

  update_metric "qa_passed" 1

  local extra_fields='[
    {"title": "Task ID", "value": "'"$task_id"'", "short": true},
    {"title": "QA Status", "value": ":white_check_mark: PASSED", "short": true}
  ]'

  send_slack_notification \
    ":white_check_mark: QA Validation Passed" \
    "$summary\n\nProceeding with: Send emails, post content, push to GitHub" \
    "success" \
    "$extra_fields"
}

# Notify when QA validation fails (CRITICAL - requires manual review)
notify_qa_failed() {
  local task_id="$1"
  local reason="$2"
  local details="${3:-No additional details}"

  update_metric "qa_failed" 1
  update_metric "tasks_failed" 1

  local staging_dir=$(get_staging_dir 2>/dev/null || echo ".coo/agent/staging/$(date +%Y-%m-%d)")

  local extra_fields='[
    {"title": "Task ID", "value": "'"$task_id"'", "short": true},
    {"title": "QA Status", "value": ":x: FAILED", "short": true},
    {"title": "Failure Reason", "value": "'"$reason"'", "short": false},
    {"title": "Details", "value": "'"$details"'", "short": false},
    {"title": "Review Required", "value": "'"$staging_dir"'", "short": false}
  ]'

  send_slack_notification \
    ":x: QA FAILED - Manual Review Required" \
    "*Action:* Task marked needs-review. NO emails sent, NO tweets posted, NO GitHub push.\n*Next:* Review staging outputs and re-run or fix manually." \
    "failure" \
    "$extra_fields"
}

# Notify when emails are sent
notify_emails_sent() {
  local count="$1"
  local warmup_info="${2:-Day $(jq -r '.warmup_day // 1' "$METRICS_FILE" 2>/dev/null)}"
  local variant_info="${3:-}"

  update_metric "emails_sent" "$count"

  local limit=100
  if [ -f "$METRICS_FILE" ]; then
    local day=$(jq -r '.warmup_day // 1' "$METRICS_FILE" 2>/dev/null)
    if [ "$day" -le 3 ]; then limit=10
    elif [ "$day" -le 7 ]; then limit=25
    elif [ "$day" -le 14 ]; then limit=50
    fi
  fi

  local message="*Emails sent:* $count\n*Warm-up day:* $warmup_info (limit: $limit/day)"

  if [ -n "$variant_info" ]; then
    message="$message\n*A/B variant:* $variant_info"
  fi

  local extra_fields='[
    {"title": "Emails Sent", "value": "'"$count"'", "short": true},
    {"title": "Warm-up Limit", "value": "'"$limit"'/day", "short": true}
  ]'

  send_slack_notification \
    ":email: Emails Sent via Resend" \
    "$message" \
    "success" \
    "$extra_fields"
}

# Notify when tweets are posted
notify_tweet_posted() {
  local content_preview="$1"
  local post_type="${2:-post}"

  update_metric "tweets_posted" 1

  # Truncate preview if too long
  if [ ${#content_preview} -gt 100 ]; then
    content_preview="${content_preview:0:100}..."
  fi

  local type_emoji=":bird:"
  case "$post_type" in
    morning) type_emoji=":sunrise:" ;;
    midday) type_emoji=":sun_with_face:" ;;
    evening) type_emoji=":city_sunset:" ;;
    thread) type_emoji=":thread:" ;;
  esac

  local extra_fields='[
    {"title": "Post Type", "value": "'"$post_type"'", "short": true},
    {"title": "Posted", "value": ":white_check_mark:", "short": true}
  ]'

  send_slack_notification \
    "$type_emoji Twitter $post_type Posted" \
    "$content_preview" \
    "success" \
    "$extra_fields"
}

# Notify when task completes successfully
notify_task_completed() {
  local task_id="$1"
  local task_title="$2"
  local duration="${3:-0}"

  update_metric "tasks_completed" 1
  update_metric "total_duration_mins" "$duration"

  local extra_fields='[
    {"title": "Task ID", "value": "'"$task_id"'", "short": true},
    {"title": "Duration", "value": "'"$duration"' mins", "short": true}
  ]'

  send_slack_notification \
    ":white_check_mark: Task Completed" \
    "$task_title" \
    "success" \
    "$extra_fields"
}

# Notify when leads/prospects are generated
notify_leads_generated() {
  local count="$1"
  local lead_type="${2:-leads}"
  local source="${3:-}"

  if [ "$lead_type" == "prospects" ]; then
    update_metric "prospects_researched" "$count"
  else
    update_metric "leads_generated" "$count"
  fi

  local message="*Generated:* $count $lead_type"
  if [ -n "$source" ]; then
    message="$message\n*Source:* $source"
  fi

  local extra_fields='[
    {"title": "Count", "value": "'"$count"'", "short": true},
    {"title": "Type", "value": "'"$lead_type"'", "short": true}
  ]'

  send_slack_notification \
    ":mag: $lead_type Generated" \
    "$message" \
    "success" \
    "$extra_fields"
}

# Notify GitHub push completed
notify_github_push() {
  local branch="$1"
  local commit_msg="$2"

  # Truncate commit message if too long
  if [ ${#commit_msg} -gt 200 ]; then
    commit_msg="${commit_msg:0:200}..."
  fi

  local extra_fields='[
    {"title": "Branch", "value": "'"$branch"'", "short": true},
    {"title": "Pushed", "value": ":white_check_mark:", "short": true}
  ]'

  send_slack_notification \
    ":github: Pushed to GitHub" \
    "$commit_msg" \
    "success" \
    "$extra_fields"
}

# Daily summary notification (call at end of day)
notify_daily_summary() {
  init_metrics

  local date=$(jq -r '.date // "unknown"' "$METRICS_FILE")
  local completed=$(jq -r '.tasks_completed // 0' "$METRICS_FILE")
  local failed=$(jq -r '.tasks_failed // 0' "$METRICS_FILE")
  local qa_passed=$(jq -r '.qa_passed // 0' "$METRICS_FILE")
  local qa_failed=$(jq -r '.qa_failed // 0' "$METRICS_FILE")
  local emails=$(jq -r '.emails_sent // 0' "$METRICS_FILE")
  local tweets=$(jq -r '.tweets_posted // 0' "$METRICS_FILE")
  local prospects=$(jq -r '.prospects_researched // 0' "$METRICS_FILE")
  local leads=$(jq -r '.leads_generated // 0' "$METRICS_FILE")
  local warmup_day=$(jq -r '.warmup_day // 1' "$METRICS_FILE")
  local total_duration=$(jq -r '.total_duration_mins // 0' "$METRICS_FILE")

  local total_tasks=$((completed + failed))
  local completion_rate=0
  if [ $total_tasks -gt 0 ]; then
    completion_rate=$((completed * 100 / total_tasks))
  fi

  local summary="*Date:* $date\n"
  summary="$summary\n:chart_with_upwards_trend: *Metrics:*\n"
  summary="$summary- Tasks: $completed completed, $failed failed ($completion_rate% success)\n"
  summary="$summary- QA: $qa_passed passed, $qa_failed failed\n"
  summary="$summary- Prospects researched: $prospects\n"
  summary="$summary- Leads generated: $leads\n"
  summary="$summary- Emails sent: $emails (warm-up day $warmup_day)\n"
  summary="$summary- Tweets posted: $tweets\n"
  summary="$summary- Total time: ${total_duration}min"

  local extra_fields='[
    {"title": "Tasks Done", "value": "'"$completed"'", "short": true},
    {"title": "Tasks Failed", "value": "'"$failed"'", "short": true},
    {"title": "Emails Sent", "value": "'"$emails"'", "short": true},
    {"title": "Tweets Posted", "value": "'"$tweets"'", "short": true}
  ]'

  send_slack_notification \
    ":bar_chart: Daily COO Agent Summary" \
    "$summary" \
    "info" \
    "$extra_fields"
}

# =============================================================================
# CLI INTERFACE
# =============================================================================

# Allow direct invocation
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "$1" in
    # Metric commands
    --show-metrics)
      init_metrics
      echo "COO Agent Metrics:"
      echo "=================="
      get_metrics_summary
      echo ""
      echo "Full metrics:"
      jq '.' "$METRICS_FILE"
      ;;
    --reset-metrics)
      reset_metrics
      ;;
    --daily-summary)
      notify_daily_summary
      ;;

    # Notification commands
    --task-started)
      notify_task_started "$2" "$3"
      ;;
    --worker-output)
      notify_worker_output "$2" "$3"
      ;;
    --qa-passed)
      notify_qa_passed "$2" "$3"
      ;;
    --qa-failed)
      notify_qa_failed "$2" "$3" "$4"
      ;;
    --emails-sent)
      notify_emails_sent "$2" "$3" "$4"
      ;;
    --tweet-posted)
      notify_tweet_posted "$2" "$3"
      ;;
    --task-completed)
      notify_task_completed "$2" "$3" "$4"
      ;;
    --leads-generated)
      notify_leads_generated "$2" "$3" "$4"
      ;;
    --github-push)
      notify_github_push "$2" "$3"
      ;;

    # Generic notification
    --notify)
      send_slack_notification "$2" "$3" "$4"
      ;;

    # Help
    --help|-h|"")
      echo "COO Agent Slack Notification System"
      echo ""
      echo "Usage: $0 <command> [args...]"
      echo ""
      echo "Notification Commands:"
      echo "  --task-started <task-id> <title>          Notify task started"
      echo "  --worker-output <task-id> <summary>       Notify worker output generated"
      echo "  --qa-passed <task-id> <summary>           Notify QA validation passed"
      echo "  --qa-failed <task-id> <reason> [details]  Notify QA failed (CRITICAL)"
      echo "  --emails-sent <count> [warmup-info] [variant] Notify emails sent"
      echo "  --tweet-posted <preview> [type]           Notify tweet posted"
      echo "  --task-completed <task-id> <title> [mins] Notify task completed"
      echo "  --leads-generated <count> [type] [source] Notify leads generated"
      echo "  --github-push <branch> <commit-msg>       Notify GitHub push"
      echo "  --daily-summary                           Send daily summary"
      echo "  --notify <title> <message> [status]       Generic notification"
      echo ""
      echo "Metrics Commands:"
      echo "  --show-metrics   Show current metrics"
      echo "  --reset-metrics  Force reset metrics"
      echo ""
      echo "Status values: info, success, failure, warning"
      echo ""
      echo "Environment: SLACK_WEBHOOK_URL must be set"
      ;;
    *)
      echo "Unknown command: $1"
      echo "Run '$0 --help' for usage"
      exit 1
      ;;
  esac
fi
