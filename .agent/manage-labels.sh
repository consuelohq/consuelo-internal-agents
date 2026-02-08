#!/bin/bash
#
# Label Management Script
#
# Creates the simplified label set for the agent workflow and
# optionally deletes unused labels.
#
# Usage:
#   .agent/manage-labels.sh              # Create labels only
#   .agent/manage-labels.sh --cleanup    # Create labels AND delete unused ones
#   .agent/manage-labels.sh --dry-run    # Preview changes without making them
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Parse arguments
CLEANUP=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --cleanup)
      CLEANUP=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --cleanup    Delete unused labels (in addition to creating required ones)"
      echo "  --dry-run    Preview changes without making them"
      echo "  --help       Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Check for GitHub CLI
if ! command -v gh &> /dev/null; then
  log_error "GitHub CLI (gh) is not installed. Install from: https://cli.github.com"
  exit 1
fi

# Check if gh is authenticated
if ! gh auth status &> /dev/null; then
  log_error "GitHub CLI is not authenticated. Run: gh auth login"
  exit 1
fi

log_info "Label Management Script"
log_info "Cleanup mode: $CLEANUP"
log_info "Dry run: $DRY_RUN"
echo ""

# ============================================
# LABELS TO CREATE (8 total)
# ============================================

log_info "Creating required labels..."

# Workflow labels
LABELS_TO_CREATE=(
  "claude|Ready for Claude agent|FFA500"
  "agent-working|Agent is processing|FBCA04"
  "agent-review|Needs human review|D93F0B"
  "agent-completed|Agent completed|1D76DB"
  "tests-passed|All tests green|0E8A16"
  "tests-failed|Tests failing|B60205"
  "size/s|Small PR (<100 lines)|EDEDED"
  "size/l|Large PR (>500 lines)|EDEDED"
)

for label_entry in "${LABELS_TO_CREATE[@]}"; do
  IFS='|' read -r name description color <<< "$label_entry"
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY RUN] Would create label: $name"
  else
    if gh label create "$name" --description "$description" --color "$color" --force 2>/dev/null; then
      log_success "Created/updated label: $name"
    else
      log_warning "Label may already exist or error: $name"
    fi
  fi
done

# ============================================
# LABELS TO DELETE (44 total)
# ============================================

if [ "$CLEANUP" = true ]; then
  echo ""
  log_info "Deleting unused labels..."

  LABELS_TO_DELETE=(
    # Agent labels being replaced
    "agent-ready"
    "agent-generated"

    # Size labels (keeping only s/l)
    "size/xs"
    "size/m"
    "size/xl"

    # Type labels (not useful - can see from PR title)
    "type/bugfix"
    "type/feature"
    "type/refactor"
    "type/security"
    "type/perf"
    "type/docs"
    "type/test"
    "type/chore"
    "type/deps"

    # Source labels (not useful)
    "source/beads"
    "source/sentry"
    "source/review"

    # Area labels (can infer from file list)
    "area/frontend"
    "area/backend"
    "area/api"
    "area/tests"
    "area/infra"
    "area/auth"
    "area/twilio"
    "area/ai"

    # Review complexity labels (confusing)
    "review/quick"
    "review/standard"
    "review/complex"

    # Review status labels (redundant with tests-*)
    "review-passed"
    "review-failed"

    # Other unused labels
    "breaking-change"
    "priority/critical"
    "priority/high"
    "needs-review"
    "needs-triage"
    "urgent-review"
    "automated-review"
    "code-quality"
    "low"
    "important"
    "billing"
    "pricing"
    "spec"
    "stripe"
    "test"
    "Review effort 1/5"
    "Review effort 4/5"
  )

  deleted_count=0
  for label in "${LABELS_TO_DELETE[@]}"; do
    if [ "$DRY_RUN" = true ]; then
      echo "  [DRY RUN] Would delete label: $label"
    else
      if gh label delete "$label" --yes 2>/dev/null; then
        log_success "Deleted label: $label"
        deleted_count=$((deleted_count + 1))
      else
        # Label might not exist - that's fine
        true
      fi
    fi
  done

  if [ "$DRY_RUN" = false ]; then
    log_info "Deleted $deleted_count labels"
  fi
fi

echo ""
log_success "Label management complete!"
echo ""
log_info "Required labels (8):"
echo "  - claude (orange)        - Issues for agent pickup"
echo "  - agent-working (yellow) - Agent is processing"
echo "  - agent-review (red)     - Needs human review"
echo "  - agent-completed (blue) - Successfully done"
echo "  - tests-passed (green)   - All tests green"
echo "  - tests-failed (red)     - Tests failing"
echo "  - size/s (gray)          - Small PR"
echo "  - size/l (gray)          - Large PR"
