#!/bin/bash
# Weekly Shipping Report Automation
# Runs every Thursday at 8 PM EST via launchd
# Generates shipping report, updates changelog, and creates PR

set -e  # Exit on error

# ============================================================================
# Configuration
# ============================================================================

REPO_DIR="/Users/kokayi/Dev/consuelo_on_call_coaching"
LOG_FILE="${REPO_DIR}/.agent/cron-log.txt"
REPORTS_DIR="${REPO_DIR}/.agent/weekly-reports"
TEMP_OUTPUT="/tmp/shipping-report-output-$$.txt"

# Ensure PATH includes common tool locations
export PATH="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:$PATH"

# ============================================================================
# Helper Functions
# ============================================================================

log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

cleanup() {
    rm -f "$TEMP_OUTPUT"
}
trap cleanup EXIT

get_ordinal_suffix() {
    local day=$1
    case $day in
        1|21|31) echo "st" ;;
        2|22) echo "nd" ;;
        3|23) echo "rd" ;;
        *) echo "th" ;;
    esac
}

# ============================================================================
# Main Script
# ============================================================================

log "=========================================="
log "Starting Weekly Shipping Report Generation"
log "=========================================="

# Change to repo directory
cd "$REPO_DIR"
log "Working directory: $(pwd)"

# ============================================================================
# Step 1: Generate date formatting for report title
# ============================================================================

DATE_ISO=$(date +%Y-%m-%d)
MONTH=$(date +%b)
DAY=$(date +%-d)
YEAR=$(date +%Y)
SUFFIX=$(get_ordinal_suffix "$DAY")
REPORT_TITLE="${MONTH} ${DAY}${SUFFIX}, ${YEAR} Weekly Shipping Report"
REPORT_FILENAME="${REPORT_TITLE}.md"

log "Report title: $REPORT_TITLE"
log "Report filename: $REPORT_FILENAME"

# ============================================================================
# Step 2: Ensure clean git state and create branch
# ============================================================================

log "Checking git status..."

# Stash any uncommitted changes
if ! git diff --quiet || ! git diff --cached --quiet; then
    log "Stashing uncommitted changes..."
    git stash push -m "Auto-stash before weekly report $(date +%Y%m%d_%H%M%S)"
fi

# Checkout main and pull latest
log "Checking out main branch..."
git checkout main
git pull origin main

# Create weekly report branch
BRANCH_NAME="weekly-report/${DATE_ISO}"
log "Creating branch: $BRANCH_NAME"

# Check if branch exists and delete if so
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    log "Branch $BRANCH_NAME exists, deleting..."
    git branch -D "$BRANCH_NAME"
fi

git checkout -b "$BRANCH_NAME"

# ============================================================================
# Step 3: Create reports directory if needed
# ============================================================================

mkdir -p "$REPORTS_DIR"
log "Reports directory ready: $REPORTS_DIR"

# ============================================================================
# Step 4: Invoke Claude Code with the weekly-shipping-report skill
# ============================================================================

log "Invoking Claude Code with weekly-shipping-report skill..."

# Use claude with --print flag to capture output
# The skill will update src/data/changelog.json automatically
if claude --print "/weekly-shipping-report" > "$TEMP_OUTPUT" 2>&1; then
    log "Claude Code completed successfully"
else
    log "ERROR: Claude Code failed with exit code $?"
    log "Output: $(cat "$TEMP_OUTPUT")"
    exit 1
fi

# ============================================================================
# Step 5: Save the report to weekly-reports directory
# ============================================================================

REPORT_PATH="${REPORTS_DIR}/${REPORT_FILENAME}"
log "Saving report to: $REPORT_PATH"

# Copy the output to the reports directory
cp "$TEMP_OUTPUT" "$REPORT_PATH"

log "Report saved successfully"

# ============================================================================
# Step 6: Commit changes
# ============================================================================

log "Staging changes..."
git add src/data/changelog.json .agent/weekly-reports/

# Check if there are changes to commit
if git diff --cached --quiet; then
    log "No changes to commit"
else
    log "Committing changes..."
    git commit -m "$(cat <<EOF
chore: ${REPORT_TITLE}

Automated weekly shipping report generated on $(date).

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
    log "Changes committed"
fi

# ============================================================================
# Step 7: Push branch and create PR
# ============================================================================

log "Pushing branch to origin..."
git push -u origin "$BRANCH_NAME"

log "Creating pull request..."
PR_URL=$(gh pr create \
    --title "${REPORT_TITLE}" \
    --body "$(cat <<EOF
## Summary

Automated weekly shipping report generated on $(date).

This PR includes:
- Updated changelog.json with this week's shipping updates
- Saved report in .agent/weekly-reports/

## View the Report

The full shipping report is available at:
.agent/weekly-reports/${REPORT_FILENAME}

## Changelog Preview

Once merged, view the updated changelog at:
https://www.consuelohq.com/calls/changelog

---
Generated automatically by the weekly-shipping-report launchd agent.
EOF
)" 2>&1)

log "Pull request created: $PR_URL"

# ============================================================================
# Step 8: Return to main branch
# ============================================================================

log "Returning to main branch..."
git checkout main

# ============================================================================
# Done!
# ============================================================================

log "=========================================="
log "Weekly Shipping Report Complete!"
log "PR: $PR_URL"
log "Report: $REPORT_PATH"
log "=========================================="

exit 0
