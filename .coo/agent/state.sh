#!/bin/bash
# COO Agent Email Warm-up State Tracker
# Manages warm-up day counter and daily email limits
#
# Email Warm-up Schedule:
#   Day 1-3:   10 emails/day
#   Day 4-7:   25 emails/day
#   Day 8-14:  50 emails/day
#   Day 15+:   100 emails/day
#
# State Files:
#   warmup-day.txt        - Current warm-up day (1-based)
#   emails-sent-today.txt - Emails sent today
#   last-reset-date.txt   - Date of last daily reset
#
# Usage:
#   source .coo/agent/state.sh
#   get_warmup_day         # Returns current warm-up day
#   get_daily_limit        # Returns max emails for today
#   get_emails_sent        # Returns emails sent today
#   can_send_email         # Returns 0 if under limit, 1 if at limit
#   record_email_sent      # Increment emails sent counter
#   daily_reset            # Reset daily counter, increment warm-up day

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${STATE_DIR:-$SCRIPT_DIR/state}"
WARMUP_DAY_FILE="$STATE_DIR/warmup-day.txt"
EMAILS_SENT_FILE="$STATE_DIR/emails-sent-today.txt"
LAST_RESET_FILE="$STATE_DIR/last-reset-date.txt"

# Initialize state files if they don't exist
init_state() {
    mkdir -p "$STATE_DIR"

    if [ ! -f "$WARMUP_DAY_FILE" ]; then
        echo "1" > "$WARMUP_DAY_FILE"
        echo "[state.sh] Initialized warmup-day.txt to 1"
    fi

    if [ ! -f "$EMAILS_SENT_FILE" ]; then
        echo "0" > "$EMAILS_SENT_FILE"
        echo "[state.sh] Initialized emails-sent-today.txt to 0"
    fi

    if [ ! -f "$LAST_RESET_FILE" ]; then
        date +%Y-%m-%d > "$LAST_RESET_FILE"
        echo "[state.sh] Initialized last-reset-date.txt to $(cat "$LAST_RESET_FILE")"
    fi
}

# Get current warm-up day (1-based)
get_warmup_day() {
    init_state
    cat "$WARMUP_DAY_FILE" | tr -d '[:space:]'
}

# Get daily email limit based on warm-up day
get_daily_limit() {
    local day
    day=$(get_warmup_day)

    if [ "$day" -le 3 ]; then
        echo "10"
    elif [ "$day" -le 7 ]; then
        echo "25"
    elif [ "$day" -le 14 ]; then
        echo "50"
    else
        echo "100"
    fi
}

# Get emails sent today
get_emails_sent() {
    init_state
    cat "$EMAILS_SENT_FILE" | tr -d '[:space:]'
}

# Get remaining emails for today
get_remaining_emails() {
    local limit sent
    limit=$(get_daily_limit)
    sent=$(get_emails_sent)
    echo $((limit - sent))
}

# Check if we can send more emails today
# Returns 0 (success) if under limit, 1 (failure) if at/over limit
can_send_email() {
    local remaining
    remaining=$(get_remaining_emails)

    if [ "$remaining" -gt 0 ]; then
        return 0
    else
        return 1
    fi
}

# Record an email was sent (increment counter)
record_email_sent() {
    local count="${1:-1}"
    init_state

    local current
    current=$(get_emails_sent)
    local new_count=$((current + count))
    echo "$new_count" > "$EMAILS_SENT_FILE"

    echo "[state.sh] Recorded $count email(s) sent. Total today: $new_count"
}

# Check if daily reset is needed (new calendar day)
needs_daily_reset() {
    init_state

    local last_reset today
    last_reset=$(cat "$LAST_RESET_FILE" | tr -d '[:space:]')
    today=$(date +%Y-%m-%d)

    if [ "$last_reset" != "$today" ]; then
        return 0  # Needs reset
    else
        return 1  # No reset needed
    fi
}

# Perform daily reset (reset email count, increment warm-up day)
daily_reset() {
    init_state

    local today
    today=$(date +%Y-%m-%d)

    # Check if reset already done today
    local last_reset
    last_reset=$(cat "$LAST_RESET_FILE" | tr -d '[:space:]')

    if [ "$last_reset" = "$today" ]; then
        echo "[state.sh] Daily reset already done for $today"
        return 0
    fi

    # Increment warm-up day
    local current_day new_day
    current_day=$(get_warmup_day)
    new_day=$((current_day + 1))
    echo "$new_day" > "$WARMUP_DAY_FILE"

    # Reset emails sent counter
    echo "0" > "$EMAILS_SENT_FILE"

    # Update last reset date
    echo "$today" > "$LAST_RESET_FILE"

    local new_limit
    new_limit=$(get_daily_limit)

    echo "[state.sh] Daily reset complete:"
    echo "  - Warm-up day: $current_day -> $new_day"
    echo "  - Emails sent reset to 0"
    echo "  - New daily limit: $new_limit"
    echo "  - Last reset: $today"
}

# Print current state summary
print_state() {
    init_state

    local day limit sent remaining
    day=$(get_warmup_day)
    limit=$(get_daily_limit)
    sent=$(get_emails_sent)
    remaining=$(get_remaining_emails)

    echo "=== Email Warm-up State ==="
    echo "Warm-up Day:     $day"
    echo "Daily Limit:     $limit emails"
    echo "Sent Today:      $sent"
    echo "Remaining:       $remaining"
    echo "Last Reset:      $(cat "$LAST_RESET_FILE" | tr -d '[:space:]')"
    echo "=========================="
}

# Get state as JSON (for integration with other scripts)
get_state_json() {
    init_state

    local day limit sent remaining last_reset
    day=$(get_warmup_day)
    limit=$(get_daily_limit)
    sent=$(get_emails_sent)
    remaining=$(get_remaining_emails)
    last_reset=$(cat "$LAST_RESET_FILE" | tr -d '[:space:]')

    cat <<EOF
{
  "warmup_day": $day,
  "daily_limit": $limit,
  "emails_sent_today": $sent,
  "remaining": $remaining,
  "last_reset": "$last_reset",
  "can_send": $([ "$remaining" -gt 0 ] && echo "true" || echo "false")
}
EOF
}

# Reset warm-up to day 1 (for testing or restart)
reset_warmup() {
    init_state

    echo "1" > "$WARMUP_DAY_FILE"
    echo "0" > "$EMAILS_SENT_FILE"
    date +%Y-%m-%d > "$LAST_RESET_FILE"

    echo "[state.sh] Warm-up reset to Day 1"
    print_state
}

# CLI interface when run directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-status}" in
        status|state)
            print_state
            ;;
        json)
            get_state_json
            ;;
        day)
            get_warmup_day
            ;;
        limit)
            get_daily_limit
            ;;
        sent)
            get_emails_sent
            ;;
        remaining)
            get_remaining_emails
            ;;
        can-send)
            if can_send_email; then
                echo "yes"
                exit 0
            else
                echo "no (at daily limit)"
                exit 1
            fi
            ;;
        record)
            record_email_sent "${2:-1}"
            ;;
        reset)
            daily_reset
            ;;
        reset-warmup)
            reset_warmup
            ;;
        help|--help|-h)
            echo "Usage: state.sh [command]"
            echo ""
            echo "Commands:"
            echo "  status        Show current state (default)"
            echo "  json          Output state as JSON"
            echo "  day           Get current warm-up day"
            echo "  limit         Get today's email limit"
            echo "  sent          Get emails sent today"
            echo "  remaining     Get remaining emails for today"
            echo "  can-send      Check if can send more emails (exit 0=yes, 1=no)"
            echo "  record [n]    Record n emails sent (default: 1)"
            echo "  reset         Perform daily reset"
            echo "  reset-warmup  Reset warm-up to Day 1"
            echo ""
            echo "Warm-up Schedule:"
            echo "  Day 1-3:   10 emails/day"
            echo "  Day 4-7:   25 emails/day"
            echo "  Day 8-14:  50 emails/day"
            echo "  Day 15+:   100 emails/day"
            ;;
        *)
            echo "Unknown command: $1"
            echo "Run 'state.sh help' for usage"
            exit 1
            ;;
    esac
fi
