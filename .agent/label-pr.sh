#!/bin/bash
#
# Label PR Script
# ===============
# Applies comprehensive labels to agent-generated PRs based on:
# - Task type (from Beads task title)
# - PR size (lines changed)
# - Areas affected (frontend/backend/tests/infra)
# - Review complexity (based on size + quality gate status)
# - Quality gate status (tests/review passed/failed)
#
# Usage:
#   .agent/label-pr.sh <pr_number> <task_title> [review_passed] [tests_passed]
#
# Example:
#   .agent/label-pr.sh 123 "[BUG] Fix login button not working" true true
#
# TODO: Customize the area patterns for your project structure

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${BLUE}[LABEL]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[LABEL]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[LABEL]${NC} $1"
}

# Ensure labels exist before adding them
ensure_label_exists() {
  local label_name="$1"
  local label_color="${2:-EDEDED}"
  local label_description="${3:-}"

  # Check if label exists
  if ! gh label list --search "$label_name" --json name -q '.[].name' 2>/dev/null | grep -qx "$label_name"; then
    log_info "Creating label: $label_name"
    gh label create "$label_name" --color "$label_color" --description "$label_description" 2>/dev/null || true
  fi
}

# Main function
main() {
  local pr_number="$1"
  local task_title="$2"
  local review_passed="${3:-true}"
  local tests_passed="${4:-true}"

  if [ -z "$pr_number" ]; then
    echo "Usage: $0 <pr_number> <task_title> [review_passed] [tests_passed]"
    exit 1
  fi

  log_info "Labeling PR #$pr_number"

  # Get PR stats
  local pr_stats
  pr_stats=$(gh pr view "$pr_number" --json additions,deletions,files,headRefName 2>/dev/null)

  if [ -z "$pr_stats" ]; then
    log_warning "Could not fetch PR stats for #$pr_number"
    return 1
  fi

  local additions deletions total_lines files_json branch_name
  additions=$(echo "$pr_stats" | jq -r '.additions // 0')
  deletions=$(echo "$pr_stats" | jq -r '.deletions // 0')
  total_lines=$((additions + deletions))
  files_json=$(echo "$pr_stats" | jq -r '.files // []')
  branch_name=$(echo "$pr_stats" | jq -r '.headRefName // ""')

  log_info "PR stats: +$additions/-$deletions = $total_lines lines"

  # Initialize labels array
  local labels=()

  # ==========================================================================
  # 1. AGENT LABEL (always applied)
  # ==========================================================================
  labels+=("agent-generated")

  # ==========================================================================
  # 2. SIZE LABELS
  # ==========================================================================
  if [ "$total_lines" -le 10 ]; then
    labels+=("size/xs")
  elif [ "$total_lines" -le 100 ]; then
    labels+=("size/s")
  elif [ "$total_lines" -le 500 ]; then
    labels+=("size/m")
  elif [ "$total_lines" -le 1000 ]; then
    labels+=("size/l")
  else
    labels+=("size/xl")
  fi

  # ==========================================================================
  # 3. TYPE LABELS (from task title prefixes)
  # ==========================================================================
  local task_lower
  task_lower=$(echo "$task_title" | tr '[:upper:]' '[:lower:]')

  if echo "$task_lower" | grep -qE '\[bug\]|\[fix\]|bugfix|fix:'; then
    labels+=("type/bugfix")
  fi

  if echo "$task_lower" | grep -qE '\[feature\]|\[feat\]|feat:'; then
    labels+=("type/feature")
  fi

  if echo "$task_lower" | grep -qE '\[refactor\]|refactor:'; then
    labels+=("type/refactor")
  fi

  if echo "$task_lower" | grep -qE '\[security\]|security:|vulnerability'; then
    labels+=("type/security")
  fi

  if echo "$task_lower" | grep -qE '\[perf\]|perf:|performance'; then
    labels+=("type/perf")
  fi

  if echo "$task_lower" | grep -qE '\[docs\]|docs:|documentation'; then
    labels+=("type/docs")
  fi

  if echo "$task_lower" | grep -qE '\[test\]|test:|tests'; then
    labels+=("type/test")
  fi

  if echo "$task_lower" | grep -qE '\[chore\]|chore:'; then
    labels+=("type/chore")
  fi

  if echo "$task_lower" | grep -qE '\[deps\]|deps:|dependencies'; then
    labels+=("type/deps")
  fi

  # ==========================================================================
  # 4. SOURCE LABELS (where the task came from)
  # ==========================================================================
  if echo "$task_lower" | grep -qE '\[sentry'; then
    labels+=("source/sentry")
  fi

  if echo "$task_lower" | grep -qE '\[review\]'; then
    labels+=("source/review")
  fi

  # Default to Beads if it's an agent branch
  if echo "$branch_name" | grep -qE '^agent/'; then
    labels+=("source/beads")
  fi

  # ==========================================================================
  # 5. AREA LABELS (based on files changed)
  # TODO: Customize these patterns for your project structure
  # ==========================================================================
  local files_list
  files_list=$(echo "$files_json" | jq -r '.[].path // empty' 2>/dev/null || echo "")

  # Check for frontend changes
  # TODO: Update pattern for your frontend directory (e.g., client/, web/, frontend/)
  if echo "$files_list" | grep -qE '^src/'; then
    labels+=("area/frontend")
  fi

  # Check for backend changes
  # TODO: Update pattern for your backend directory (e.g., server/, api/, backend/)
  if echo "$files_list" | grep -qE '^app/|^server/|^api/'; then
    labels+=("area/backend")
  fi

  # Check for API changes
  if echo "$files_list" | grep -qE 'routes|api|endpoint'; then
    labels+=("area/api")
  fi

  # Check for test changes
  if echo "$files_list" | grep -qE '^e2e/|^tests/|^test/|\.spec\.|\.test\.'; then
    labels+=("area/tests")
  fi

  # Check for infrastructure changes
  if echo "$files_list" | grep -qE 'Dockerfile|docker-compose|\.github/|\.yml$|\.yaml$'; then
    labels+=("area/infra")
  fi

  # Check for auth changes
  if echo "$files_list" | grep -qE 'auth|login|session|jwt|middleware'; then
    labels+=("area/auth")
  fi

  # ==========================================================================
  # 6. QUALITY GATE LABELS
  # ==========================================================================
  if [ "$tests_passed" = "true" ]; then
    labels+=("tests-passed")
  else
    labels+=("tests-failed")
  fi

  if [ "$review_passed" = "true" ]; then
    labels+=("review-passed")
  else
    labels+=("review-failed")
  fi

  # ==========================================================================
  # 7. REVIEW COMPLEXITY LABELS
  # ==========================================================================
  if [ "$review_passed" = "true" ] && [ "$tests_passed" = "true" ]; then
    if [ "$total_lines" -le 100 ]; then
      labels+=("review/quick")
    elif [ "$total_lines" -le 500 ]; then
      labels+=("review/standard")
    else
      labels+=("review/complex")
    fi
  else
    # Quality gates failed = always complex review
    labels+=("review/complex")
    labels+=("needs-review")
  fi

  # ==========================================================================
  # 8. PRIORITY LABELS (based on type and source)
  # ==========================================================================
  if echo "$task_lower" | grep -qE '\[critical\]|critical|production|hotfix'; then
    labels+=("priority/critical")
  elif echo "$task_lower" | grep -qE '\[sentry.*error\]|security|urgent'; then
    labels+=("priority/high")
  fi

  # ==========================================================================
  # 9. BREAKING CHANGE DETECTION
  # ==========================================================================
  if echo "$task_lower" | grep -qE 'breaking|migrate|migration'; then
    labels+=("breaking-change")
  fi

  # ==========================================================================
  # APPLY LABELS
  # ==========================================================================

  # Remove duplicates
  local unique_labels
  unique_labels=$(printf '%s\n' "${labels[@]}" | sort -u | tr '\n' ',' | sed 's/,$//')

  log_info "Applying labels: $unique_labels"

  # Add labels to PR
  if [ -n "$unique_labels" ]; then
    # Split by comma and add each label
    IFS=',' read -ra LABEL_ARRAY <<< "$unique_labels"
    for label in "${LABEL_ARRAY[@]}"; do
      gh pr edit "$pr_number" --add-label "$label" 2>/dev/null || {
        # Label might not exist, try to create it
        ensure_label_exists "$label"
        gh pr edit "$pr_number" --add-label "$label" 2>/dev/null || true
      }
    done
    log_success "Labels applied to PR #$pr_number"
  else
    log_warning "No labels to apply"
  fi
}

# Run main function
main "$@"
