#!/bin/bash
# COO Agent Environment Initialization Script
# Run this at the start of each COO agent session
#
# Usage: .coo/agent/init.sh [--quiet]
#
# Checks:
#   1. Required CLI tools (jq, claude, bd)
#   2. bd-coo alias configuration
#   3. COO directory structure
#   4. Required API keys
#   5. launchd jobs status
#   6. Daily metrics status

set -e

# Script directory (used for relative paths)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COO_DIR="$PROJECT_ROOT/.coo"

# Parse arguments
QUIET=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --quiet|-q) QUIET=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    [[ "$QUIET" == true ]] || echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    [[ "$QUIET" == true ]] || echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Track check results
ERRORS=0
WARNINGS=0

echo ""
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}   COO Agent Environment Check${NC}"
echo -e "${BOLD}========================================${NC}"
echo -e "Started at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# ============================================
# Section 1: Required Tools
# ============================================
echo -e "${BOLD}1. Checking Required Tools${NC}"
echo "--------------------------------------------"

# Check jq
if command -v jq >/dev/null 2>&1; then
    log_success "jq: $(jq --version)"
else
    log_error "jq not installed (required for JSON parsing)"
    log_info "Install via: brew install jq"
    ((ERRORS++))
fi

# Check claude CLI
if command -v claude >/dev/null 2>&1; then
    log_success "claude CLI: available"
else
    log_error "claude CLI not installed"
    log_info "Install via: npm install -g @anthropic-ai/claude-code"
    ((ERRORS++))
fi

# Check bd (Beads)
if command -v bd >/dev/null 2>&1; then
    log_success "bd (Beads): $(bd --version 2>/dev/null || echo 'available')"
else
    log_warn "bd (Beads) not installed (optional but recommended)"
    log_info "Visit: https://beads.dev for installation"
    ((WARNINGS++))
fi

# Check python3
if command -v python3 >/dev/null 2>&1; then
    log_success "python3: $(python3 --version 2>&1 | cut -d' ' -f2)"
else
    log_warn "python3 not installed (needed for some skills)"
    ((WARNINGS++))
fi

# Check node
if command -v node >/dev/null 2>&1; then
    log_success "node: $(node --version)"
else
    log_warn "node not installed (needed for some integrations)"
    ((WARNINGS++))
fi

echo ""

# ============================================
# Section 2: bd-coo Alias Check
# ============================================
echo -e "${BOLD}2. Checking bd-coo Alias${NC}"
echo "--------------------------------------------"

BD_COO_CONFIG="$COO_DIR/.beads/config.yaml"

# Check if bd-coo alias works
if command -v bd >/dev/null 2>&1; then
    # Try using the alias
    if alias bd-coo 2>/dev/null | grep -q "bd --config"; then
        log_success "bd-coo alias: configured"
    elif [ -f "$BD_COO_CONFIG" ]; then
        # Alias not set but config exists
        log_warn "bd-coo alias not set (config exists at $BD_COO_CONFIG)"
        log_info "Add to ~/.zshrc or ~/.bashrc:"
        echo ""
        echo "    alias bd-coo=\"bd --config $BD_COO_CONFIG\""
        echo ""
        ((WARNINGS++))
    else
        log_warn "COO Beads not initialized"
        log_info "Config expected at: $BD_COO_CONFIG"
        ((WARNINGS++))
    fi
else
    log_info "Skipping bd-coo check (bd not installed)"
fi

echo ""

# ============================================
# Section 3: Directory Structure
# ============================================
echo -e "${BOLD}3. Checking Directory Structure${NC}"
echo "--------------------------------------------"

# Required directories
REQUIRED_DIRS=(
    "$COO_DIR/agent"
    "$COO_DIR/agent/launchd"
    "$COO_DIR/agent/staging"
    "$COO_DIR/agent/outputs"
    "$COO_DIR/agent/outputs/emails"
    "$COO_DIR/agent/outputs/leads"
    "$COO_DIR/agent/outputs/instagram"
    "$COO_DIR/agent/outputs/twitter"
    "$COO_DIR/agent/state"
    "$COO_DIR/docs"
)

MISSING_DIRS=()
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        log_success "$(basename "$dir")/"
    else
        MISSING_DIRS+=("$dir")
    fi
done

if [ ${#MISSING_DIRS[@]} -gt 0 ]; then
    log_warn "Creating missing directories..."
    for dir in "${MISSING_DIRS[@]}"; do
        mkdir -p "$dir"
        log_info "Created: $dir"
    done
fi

echo ""

# ============================================
# Section 4: API Keys Check
# ============================================
echo -e "${BOLD}4. Checking API Keys${NC}"
echo "--------------------------------------------"

# Required API keys for COO tasks
check_api_key() {
    local key_name=$1
    local required=$2
    local value="${!key_name}"

    if [ -n "$value" ]; then
        # Mask the key value for display
        local masked="${value:0:4}...${value: -4}"
        log_success "$key_name: $masked"
        return 0
    else
        if [ "$required" == "required" ]; then
            log_error "$key_name: not set"
            ((ERRORS++))
        else
            log_warn "$key_name: not set (optional)"
            ((WARNINGS++))
        fi
        return 1
    fi
}

# Required keys
check_api_key "RESEND_API_KEY" "required" || true

# Optional but recommended keys (|| true prevents set -e from exiting)
check_api_key "SLACK_WEBHOOK_URL" "optional" || true
check_api_key "CLAY_API_KEY" "optional" || true
check_api_key "APOLLO_API_KEY" "optional" || true
check_api_key "TWITTER_BEARER_TOKEN" "optional" || true
check_api_key "TWITTER_API_KEY" "optional" || true
check_api_key "GOOGLE_SHEETS_CREDENTIALS" "optional" || true
check_api_key "BROWSE_AI_API_KEY" "optional" || true
check_api_key "INSTAGRAM_ACCESS_TOKEN" "optional" || true

echo ""

# ============================================
# Section 5: launchd Jobs Status
# ============================================
echo -e "${BOLD}5. Checking launchd Jobs${NC}"
echo "--------------------------------------------"

# TODO: Update this list to match your plist label prefix
LAUNCHD_PREFIX="com.yourcompany.coo"

# Get all loaded jobs matching prefix
LOADED_JOBS=$(launchctl list 2>/dev/null | grep "$LAUNCHD_PREFIX" || true)

if [ -z "$LOADED_JOBS" ]; then
    log_warn "No launchd jobs loaded with prefix: $LAUNCHD_PREFIX"
    log_info "To install, run:"
    echo ""
    echo "    $COO_DIR/agent/launchd/install-launchd.sh"
    echo ""
else
    LOADED_COUNT=$(echo "$LOADED_JOBS" | wc -l | tr -d ' ')
    log_success "$LOADED_COUNT launchd jobs loaded"
    echo "$LOADED_JOBS" | while read -r line; do
        log_info "  $line"
    done
fi

echo ""

# ============================================
# Section 6: Metrics & Status
# ============================================
echo -e "${BOLD}6. Daily Metrics & Status${NC}"
echo "--------------------------------------------"

METRICS_FILE="$COO_DIR/agent/metrics.json"
TODAY=$(date +%Y-%m-%d)

if [ -f "$METRICS_FILE" ]; then
    METRICS_DATE=$(jq -r '.date // empty' "$METRICS_FILE" 2>/dev/null)

    if [ "$METRICS_DATE" == "$TODAY" ]; then
        log_success "Metrics file: current ($TODAY)"

        # Display today's stats
        TASKS_COMPLETED=$(jq -r '.tasks_completed // 0' "$METRICS_FILE")
        TASKS_FAILED=$(jq -r '.tasks_failed // 0' "$METRICS_FILE")
        QA_PASSED=$(jq -r '.qa_passed // 0' "$METRICS_FILE")
        QA_FAILED=$(jq -r '.qa_failed // 0' "$METRICS_FILE")
        EMAILS_SENT=$(jq -r '.emails_sent // 0' "$METRICS_FILE")
        WARMUP_DAY=$(jq -r '.warmup_day // 1' "$METRICS_FILE")

        echo ""
        echo -e "  ${BOLD}Today's Stats:${NC}"
        echo "    Tasks completed: $TASKS_COMPLETED"
        echo "    Tasks failed: $TASKS_FAILED"
        echo "    QA passed: $QA_PASSED"
        echo "    QA failed: $QA_FAILED"
        echo "    Emails sent: $EMAILS_SENT"
        echo "    Email warmup day: $WARMUP_DAY"

        # Calculate email limit based on warmup day
        if [ "$WARMUP_DAY" -le 3 ]; then
            EMAIL_LIMIT=10
        elif [ "$WARMUP_DAY" -le 7 ]; then
            EMAIL_LIMIT=25
        elif [ "$WARMUP_DAY" -le 14 ]; then
            EMAIL_LIMIT=50
        else
            EMAIL_LIMIT=100
        fi
        echo "    Email limit today: $EMAIL_LIMIT"
    else
        log_warn "Metrics file outdated (last: $METRICS_DATE, today: $TODAY)"
        log_info "Metrics will be reset on next task execution"
    fi
else
    log_warn "Metrics file not found"
    log_info "Creating default metrics file..."

    # Create default metrics file
    cat > "$METRICS_FILE" << EOF
{
  "date": "$TODAY",
  "reset_hour_utc": 8,
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
    log_success "Created metrics file"
fi

# Check warmup state file
WARMUP_STATE="$COO_DIR/agent/state/warmup-day.txt"
if [ -f "$WARMUP_STATE" ]; then
    log_success "Warmup state file: exists"
else
    log_info "Creating warmup state file..."
    mkdir -p "$(dirname "$WARMUP_STATE")"
    echo "1" > "$WARMUP_STATE"
    log_success "Created warmup state (day 1)"
fi

echo ""

# ============================================
# Section 7: Recent Progress
# ============================================
echo -e "${BOLD}7. Recent Progress${NC}"
echo "--------------------------------------------"

PROGRESS_FILE="$COO_DIR/agent/coo-progress.txt"
if [ -f "$PROGRESS_FILE" ]; then
    # Show last session info if available
    LAST_SESSION=$(grep -E "^## Session" "$PROGRESS_FILE" | tail -1 2>/dev/null || echo "")
    if [ -n "$LAST_SESSION" ]; then
        log_success "Progress file: exists"
        echo ""
        echo -e "  ${BOLD}Last Session:${NC}"
        echo "    $LAST_SESSION"
    else
        log_success "Progress file: exists (no sessions logged yet)"
    fi
else
    log_warn "Progress file not found"
    log_info "Expected at: $PROGRESS_FILE"
fi

echo ""

# ============================================
# Summary
# ============================================
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}   Summary${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""

if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}[FAILED]${NC} $ERRORS error(s), $WARNINGS warning(s)"
    echo ""
    echo "Fix the errors above before running COO agent tasks."
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}[READY with warnings]${NC} $WARNINGS warning(s)"
    echo ""
    echo "COO agent can run, but some features may be limited."
    echo "Address warnings above for full functionality."
else
    echo -e "${GREEN}[READY]${NC} All checks passed!"
fi

echo ""
echo -e "${BOLD}Quick Commands:${NC}"
echo "  Run a task:      .coo/agent/launchd/run-scheduled-task.sh <task-type>"
echo "  Install jobs:    .coo/agent/launchd/install-launchd.sh"
echo "  View logs:       tail -f /tmp/coo-agent/*.log"
echo "  Check metrics:   cat .coo/agent/metrics.json | jq"
echo ""

exit 0
