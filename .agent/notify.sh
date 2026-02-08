#!/bin/bash
#
# Slack Notification Helper with Metrics Tracking
#
# Usage: ./notify.sh "Title" "Message" [status: success|failure|info]
#
# Metrics are tracked in metrics.json and reset daily at 3 AM EST (08:00 UTC).
#
# Requires SLACK_WEBHOOK_URL environment variable to be set.
# Add to ~/.zshrc: export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METRICS_FILE="$SCRIPT_DIR/metrics.json"
RESET_HOUR_UTC=8  # 3 AM EST = 08:00 UTC

# Source config if available (for any additional settings)
if [ -f "$SCRIPT_DIR/config.sh" ]; then
  source "$SCRIPT_DIR/config.sh"
fi

# Initialize metrics file if it doesn't exist
init_metrics() {
  if [[ ! -f "$METRICS_FILE" ]]; then
    local today=$(date -u +%Y-%m-%d)
    cat > "$METRICS_FILE" << EOF
{
  "date": "$today",
  "reset_hour_utc": $RESET_HOUR_UTC,
  "tasks_completed": 0,
  "tasks_needs_review": 0,
  "total_duration_mins": 0,
  "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  fi
}

# Check if metrics should be reset (3 AM EST = 08:00 UTC)
should_reset_metrics() {
  local current_hour=$(date -u +%H | sed 's/^0//')
  local current_date=$(date -u +%Y-%m-%d)
  local metrics_date=$(jq -r '.date' "$METRICS_FILE" 2>/dev/null || echo "")

  # If no date in metrics, reset
  if [[ -z "$metrics_date" ]]; then
    return 0  # true, should reset
  fi

  # If current hour >= reset hour and metrics date is not today
  if [[ "$current_hour" -ge "$RESET_HOUR_UTC" ]] && [[ "$metrics_date" != "$current_date" ]]; then
    return 0  # true, should reset
  fi

  # If current hour < reset hour but metrics date is 2+ days ago
  if [[ "$current_hour" -lt "$RESET_HOUR_UTC" ]]; then
    local yesterday=$(date -u -v-1d +%Y-%m-%d 2>/dev/null || date -u -d "yesterday" +%Y-%m-%d)
    if [[ "$metrics_date" != "$current_date" ]] && [[ "$metrics_date" != "$yesterday" ]]; then
      return 0  # true, should reset
    fi
  fi

  return 1  # false, don't reset
}

# Reset metrics to zero
reset_metrics() {
  local today=$(date -u +%Y-%m-%d)
  cat > "$METRICS_FILE" << EOF
{
  "date": "$today",
  "reset_hour_utc": $RESET_HOUR_UTC,
  "tasks_completed": 0,
  "tasks_needs_review": 0,
  "total_duration_mins": 0,
  "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  echo "Metrics reset for $today" >&2
}

# Update metrics (call after task completion)
# Usage: update_metrics "success|needs_review" [duration_mins]
update_metrics() {
  local status="${1:-success}"
  local duration="${2:-0}"

  init_metrics

  # Check if reset needed
  if should_reset_metrics; then
    reset_metrics
  fi

  # Read current values
  local completed=$(jq -r '.tasks_completed' "$METRICS_FILE")
  local failed=$(jq -r '.tasks_needs_review' "$METRICS_FILE")
  local total_duration=$(jq -r '.total_duration_mins' "$METRICS_FILE")

  # Update based on status
  if [[ "$status" == "success" ]]; then
    completed=$((completed + 1))
  else
    failed=$((failed + 1))
  fi
  total_duration=$((total_duration + duration))

  # Write updated metrics
  local today=$(date -u +%Y-%m-%d)
  jq --arg date "$today" \
     --argjson completed "$completed" \
     --argjson failed "$failed" \
     --argjson duration "$total_duration" \
     --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '.date = $date | .tasks_completed = $completed | .tasks_needs_review = $failed | .total_duration_mins = $duration | .last_updated = $updated' \
     "$METRICS_FILE" > "${METRICS_FILE}.tmp" && mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
}

# Get metrics summary for display
get_metrics_summary() {
  init_metrics

  # Check if reset needed
  if should_reset_metrics; then
    reset_metrics
  fi

  local completed=$(jq -r '.tasks_completed' "$METRICS_FILE")
  local failed=$(jq -r '.tasks_needs_review' "$METRICS_FILE")
  local total_duration=$(jq -r '.total_duration_mins' "$METRICS_FILE")

  local total=$((completed + failed))
  local avg_duration=0
  if [[ $total -gt 0 ]]; then
    avg_duration=$((total_duration / total))
  fi

  echo "$completed completed, $failed needs review, avg ${avg_duration}min/task"
}

send_slack_notification() {
  local title="$1"
  local message="$2"
  local status="${3:-info}"

  # Check for webhook URL
  if [ -z "$SLACK_WEBHOOK_URL" ]; then
    echo "SLACK_WEBHOOK_URL not configured, skipping notification" >&2
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
  repo_name=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" || echo "unknown")

  # Get current branch
  local branch
  branch=$(git branch --show-current 2>/dev/null || echo "unknown")

  # Get metrics summary
  local metrics_summary
  metrics_summary=$(get_metrics_summary)

  # Send notification using jq to safely construct JSON payload
  # This prevents command injection from special characters in variables
  local payload
  payload=$(jq -n \
    --arg color "$color" \
    --arg title "$title" \
    --arg text "$message" \
    --arg repo_branch "${repo_name} → ${branch}" \
    --arg metrics "$metrics_summary" \
    --argjson ts "$(date +%s)" \
    '{
      attachments: [{
        color: $color,
        title: $title,
        text: $text,
        fields: [
          {title: "Today\u0027s Totals", value: $metrics, short: false},
          {title: "Repo/Branch", value: $repo_branch, short: false}
        ],
        footer: "Consuelo Agent",
        ts: $ts
      }]
    }')

  curl -s -X POST "$SLACK_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null 2>&1

  local result=$?
  if [ $result -eq 0 ]; then
    echo "Slack notification sent: $title" >&2
  else
    echo "Failed to send Slack notification" >&2
  fi
  return $result
}

# Allow direct invocation
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  # Handle special commands first
  case "$1" in
    --update-metrics)
      update_metrics "$2" "$3"
      exit 0
      ;;
    --show-metrics)
      init_metrics
      echo "Metrics: $(get_metrics_summary)"
      jq '.' "$METRICS_FILE"
      exit 0
      ;;
    --reset-metrics)
      reset_metrics
      exit 0
      ;;
    --help|-h|"")
      echo "Usage: $0 \"Title\" \"Message\" [status: success|failure|info|warning]"
      echo ""
      echo "Additional commands:"
      echo "  $0 --update-metrics success [duration_mins]  - Update metrics"
      echo "  $0 --show-metrics                            - Show current metrics"
      echo "  $0 --reset-metrics                           - Force reset metrics"
      echo ""
      echo "Requires SLACK_WEBHOOK_URL environment variable."
      exit 1
      ;;
    *)
      if [ $# -lt 2 ]; then
        echo "Error: Requires at least 2 arguments (title and message)"
        echo "Run '$0 --help' for usage"
        exit 1
      fi
      send_slack_notification "$@"
      ;;
  esac
fi
