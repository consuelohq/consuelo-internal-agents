#!/bin/bash
#
# Autonomous Agent Task Runner (Multi-Source Edition)
#
# Processes tasks from GitHub Issues, GitHub Projects, or Linear in a SINGLE run.
# Creates ONE branch for the entire run, with separate commits per task,
# and ONE PR at the end containing all the work for easy review.
#
# Usage:
#   .agent/run-tasks.sh                    # Process all open issues with default agent
#   .agent/run-tasks.sh --max-tasks 3      # Process at most 3 issues
#   .agent/run-tasks.sh                    # Process all open issues with kiro
#   .agent/run-tasks.sh --dry-run          # Preview issues without processing
#   .agent/run-tasks.sh --label "bug"      # Use a different label filter
#   .agent/run-tasks.sh --linear           # Use Linear for issue tracking
#
# Prerequisites:
#   - GitHub CLI (gh) installed and authenticated
#   - Kiro CLI installed (kiro-cli)
#   - Git configured with push access
#
# Workflow:
#   1. Creates ONE branch for the entire run (e.g., agent/run-2025-01-19-abc123)
#   2. Processes each issue, creating a commit per task
#   3. Creates ONE PR at the end with all commits
#   4. You review ONE PR instead of many
#

# Don't use set -e - we want to continue processing tasks even if one fails
# Individual command failures are handled explicitly

# Trap to ensure we push changes even if script is interrupted
cleanup_and_push() {
  # Prevent infinite recursion: unset traps before exiting
  trap - EXIT INT TERM
  local exit_code=$?

  # Kill any background review processes
  for pid in "${REVIEW_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  rm -rf /tmp/oc-review-* 2>/dev/null || true

  if [ -n "$RUN_BRANCH" ]; then
    echo -e "\033[1;33m[CLEANUP]\033[0m Ensuring all changes are pushed before exit..."
    # cd into worktree if it exists
    local wt_path="${AGENT_WORKTREE:-${PROJECT_ROOT}/../opensaas-agent}"
    [ -d "$wt_path" ] && cd "$wt_path"
    # Check if we're on the run branch
    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ "$current_branch" = "$RUN_BRANCH" ]; then
      # Commit any uncommitted changes
      if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        git add -A 2>/dev/null
        git commit -m "chore: Auto-commit on exit (interrupted run)

Co-Authored-By: suelo-kiro[bot] <260422584+suelo-kiro[bot]@users.noreply.github.com>" 2>/dev/null || true
      fi
      # Push any unpushed commits
      HUSKY=0 git push origin "$RUN_BRANCH" 2>/dev/null || true
    fi
  fi
  exit $exit_code
}
trap cleanup_and_push EXIT INT TERM

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load agent configuration
if [ -f "$SCRIPT_DIR/config.sh" ]; then
  source "$SCRIPT_DIR/config.sh"
fi

# Load Linear API helper (if available)
if [ -f "$SCRIPT_DIR/linear-api.sh" ]; then
  source "$SCRIPT_DIR/linear-api.sh"
fi

# Set defaults if config.sh not found
if [ -z "$AGENT_CLI" ]; then
  # Default configuration
  AGENT_CLI="kiro"
  KIRO_CMD="kiro-cli chat --trust-all-tools --no-interactive"
  SOURCE_BRANCH="main"        # Branch to create run branch FROM (pull fresh code)
  PR_TARGET_BRANCH="staging"  # Branch to create PR TO (staging branch)
  BRANCH_PREFIX="agent"
  TASK_SOURCE="issues"
  ISSUE_LABEL_READY="agent-ready"
  ISSUE_LABEL_WORKING="agent-working"
  ISSUE_LABEL_REVIEW="agent-review"
  ISSUE_LABEL_TEST="agent-test"
  ISSUE_LABEL_COMPLETED="agent-completed"
fi

# Task source override from env
TASK_SOURCE="${TASK_SOURCE:-issues}"

# GitHub repo (auto-detected or override)
GITHUB_REPO="${GITHUB_REPO:-}"

# Run tracking
# Review tracking
REVIEW_PIDS=()
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true

RUN_ID=""
RUN_BRANCH=""
COMPLETED_ISSUES=()
FAILED_ISSUES=()
REVIEW_FAILED_ISSUES=()
TEST_FAILED_ISSUES=()

# Parse command line arguments
MAX_TASKS=0  # 0 means unlimited
DRY_RUN=false
AGENT_OVERRIDE=""
ISSUE_LABEL="${ISSUE_LABEL_READY:-agent-ready}"
TASK_SOURCE_OVERRIDE=""
SINGLE_ISSUE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --max-tasks)
      MAX_TASKS="$2"
      shift 2
      ;;
    --agent)
      AGENT_OVERRIDE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --label)
      ISSUE_LABEL="$2"
      shift 2
      ;;
    --issue)
      SINGLE_ISSUE="$2"
      TASK_SOURCE_OVERRIDE="linear"
      shift 2
      ;;
    --source)
      TASK_SOURCE_OVERRIDE="$2"
      shift 2
      ;;
    --projects|--mercury)
      TASK_SOURCE_OVERRIDE="projects"
      shift
      ;;
    --issues)
      TASK_SOURCE_OVERRIDE="issues"
      shift
      ;;
    --linear)
      TASK_SOURCE_OVERRIDE="linear"
      shift
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --max-tasks N    Process at most N tasks (default: unlimited)"
      echo "  --agent NAME     Use specific agent CLI (default: kiro)"
      echo "  --source SOURCE  Task source: 'issues', 'projects', or 'linear'"
      echo "  --projects       Shorthand for --source projects (use mercury board)"
      echo "  --mercury        Alias for --projects"
      echo "  --issues         Shorthand for --source issues (use GitHub Issues labels)"
      echo "  --linear         Shorthand for --source linear (use Linear.app)"
      echo "  --issue ID       Process a single Linear issue by identifier (e.g., DEV-1076)"
      echo "  --label LABEL    Filter issues by label (when using --issues)"
      echo "  --dry-run        Preview tasks without processing"
      echo "  --help           Show this help message"
      echo ""
      echo "Task Sources:"
      echo "  issues    - GitHub Issues with agent-ready label (default)"
      echo "  projects  - GitHub Projects board (mercury) with 'spec prepared' status"
      echo "  linear    - Linear.app issues with 'hero' label in 'Open' state"
      echo ""
      echo "Mercury Status Flow:"
      echo "  spec prepared → in progress → done (or in review)"
      echo ""
      echo "Linear Status Flow:"
      echo "  Open → In Progress → In Review (human approves) → Done"
      echo ""
      echo "Examples:"
      echo "  $0 --mercury              # Use mercury board"
      echo "  $0 --mercury --dry-run    # Preview mercury tasks"
      echo "  $0 --issues --max-tasks 3 # Process 3 issues with labels"
      echo "  $0 --linear               # Use Linear for issue tracking"
      echo "  $0 --linear --dry-run     # Preview Linear tasks"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Apply task source override if provided
if [ -n "$TASK_SOURCE_OVERRIDE" ]; then
  TASK_SOURCE="$TASK_SOURCE_OVERRIDE"
fi

# Use override if provided
if [ -n "$AGENT_OVERRIDE" ]; then
  AGENT_CLI="$AGENT_OVERRIDE"
fi

# Get the agent command based on CLI choice
get_agent_cmd() {
  echo "$KIRO_CMD"
}

# =============================================================================
# SUBPROCESS MODEL - Each task runs in a fresh agent session
# =============================================================================

# Spawn a fresh agent subprocess for a single task (isolated context)
spawn_task_subprocess() {
  local issue_number="$1"
  local issue_title="$2"
  local issue_body="$3"

  # Determine issue reference format based on task source
  local issue_ref=""
  local commit_prefix=""
  if [ "$TASK_SOURCE" = "linear" ]; then
    issue_ref="Linear issue $issue_number"
    commit_prefix="$issue_number"
  else
    issue_ref="GitHub issue #$issue_number"
    commit_prefix="#$issue_number"
  fi

  # --- Workpad: per-task scratch file for acceptance criteria + agent notes ---
  local workpad_dir="$SCRIPT_DIR/workpads"
  mkdir -p "$workpad_dir"
  local workpad_file="$workpad_dir/${issue_number}.md"

  # Extract acceptance criteria from task body (looks for common header patterns)
  local acceptance_criteria=""
  acceptance_criteria=$(echo "$issue_body" | sed -n '/^##\? *[Aa]cceptance [Cc]riteria/,/^##\? /{ /^##\? *[Aa]cceptance/d; /^##\? /d; p; }' | sed '/^$/d')
  if [ -z "$acceptance_criteria" ]; then
    # Fallback: look for checkbox-style criteria anywhere
    acceptance_criteria=$(echo "$issue_body" | grep -E '^\s*[-*] \[[ x]\]' || true)
  fi

  cat > "$workpad_file" << WORKPAD_EOF
# workpad: $issue_number — $issue_title
# created: $(date -u +%Y-%m-%dT%H:%M:%SZ)

## acceptance criteria

$( [ -n "$acceptance_criteria" ] && echo "$acceptance_criteria" || echo "_no acceptance criteria found in task body — read the full description carefully_" )

## implementation notes

_write your research findings, approach decisions, and anything useful here as you work_

## improvements noticed

_if you spot workflow issues, missing scripts, broken patterns — note them here. don't fix infrastructure during a feature task._

WORKPAD_EOF
  log_info "Workpad created: $workpad_file"

  # --- Build the task prompt (agent personality loaded by kiro-cli --agent) ---
  local prompt_file=$(mktemp)
  cat > "$prompt_file" << PROMPT_EOF
you are working on $issue_ref.

**title:** $issue_title

**workpad file:** $workpad_file
read this file first. write your notes to it as you work. check every acceptance criterion before committing.

**description:**
$issue_body

commit with message: 'fix($commit_prefix): brief description'
do NOT push — we push all commits together at the end of the run.
PROMPT_EOF

  # Spawn agent subprocess
  log_info "Starting $AGENT_CLI subprocess for $issue_ref (agent: $agent_type)..."

  local agent_cmd=$(get_agent_cmd)
  local task_log="$LOG_DIR/task-${issue_number}.log"
  $agent_cmd "$(cat "$prompt_file")" < /dev/null 2>&1 | tee "$task_log"
  local exit_code=${PIPESTATUS[0]}

  rm -f "$prompt_file"

  if [ $exit_code -eq 0 ]; then
    log_success "Subprocess completed for $issue_number"
  else
    log_warning "Subprocess for $issue_number exited with code $exit_code"
  fi

  return $exit_code
}

# =============================================================================
# RUN STATE PERSISTENCE - Enables resume if interrupted
# =============================================================================

# Save state after each task (enables resume if interrupted)
save_run_state() {
  local processed_count="$1"
  local state_file="$SCRIPT_DIR/run-state.json"

  # Get array lengths (Bash 3.x compatible)
  local completed_count=${#COMPLETED_ISSUES[@]}
  local failed_count=${#FAILED_ISSUES[@]}
  local review_failed_count=${#REVIEW_FAILED_ISSUES[@]}
  local test_failed_count=${#TEST_FAILED_ISSUES[@]}

  cat > "$state_file" << EOF
{
  "run_id": "$RUN_ID",
  "branch": "$RUN_BRANCH",
  "processed": $processed_count,
  "completed": $completed_count,
  "failed": $failed_count,
  "review_failed": $review_failed_count,
  "test_failed": $test_failed_count,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  log_info "Run state saved to $state_file"
}

# Clear state when run completes successfully
clear_run_state() {
  local state_file="$SCRIPT_DIR/run-state.json"
  if [ -f "$state_file" ]; then
    rm -f "$state_file"
    log_info "Run state cleared"
  fi
}

# Check for existing run state (resume capability)
check_run_state() {
  local state_file="$SCRIPT_DIR/run-state.json"
  if [ -f "$state_file" ]; then
    log_warning "Found existing run state from previous interrupted run:"
    cat "$state_file"
    echo ""
    log_info "Delete $state_file to start fresh, or the run will continue"
    return 0
  fi
  return 1
}

# =============================================================================

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

# Generate a unique run ID
generate_run_id() {
  local date_part=$(date +%Y-%m-%d)
  local random_part=$(head -c 4 /dev/urandom | xxd -p | head -c 6)
  echo "${date_part}-${random_part}"
}

# Check prerequisites
check_prerequisites() {
  log_info "Checking prerequisites..."

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

  # Check for agent CLI
  if ! command -v kiro-cli &> /dev/null; then
    log_error "Kiro CLI is not installed"
    exit 1
  fi

  # Check for git
  if ! command -v git &> /dev/null; then
    log_error "Git is not installed"
    exit 1
  fi

  # Auto-detect GitHub repo if not set
  if [ -z "$GITHUB_REPO" ]; then
    GITHUB_REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null)
    if [ -z "$GITHUB_REPO" ]; then
      log_error "Could not detect GitHub repo. Set GITHUB_REPO env var or run from a git repo."
      exit 1
    fi
  fi

  log_success "All prerequisites satisfied (repo: $GITHUB_REPO)"
}

# Ensure required labels exist
ensure_labels_exist() {
  log_info "Ensuring GitHub labels exist..."

  # Create labels if they don't exist (ignore errors if they already exist)
  gh label create "agent-ready" --description "Issue ready for AI agent to work on" --color "0E8A16" 2>/dev/null || true
  gh label create "agent-working" --description "AI agent is currently working on this" --color "FBCA04" 2>/dev/null || true
  gh label create "agent-review" --description "Agent completed, code review failed" --color "D93F0B" 2>/dev/null || true
  gh label create "agent-test" --description "Agent completed, tests failed" --color "E99695" 2>/dev/null || true
  gh label create "agent-completed" --description "Agent successfully completed this issue" --color "1D76DB" 2>/dev/null || true
}

# Get list of open tasks (from Issues, Projects, or Linear based on TASK_SOURCE)
get_open_issues() {
  local tasks=""

  if [ "$TASK_SOURCE" = "projects" ]; then
    log_info "Fetching tasks from GitHub Projects (mercury)..."
    tasks=$(get_project_tasks)
  elif [ "$TASK_SOURCE" = "linear" ]; then
    log_info "Fetching tasks from Linear..."
    tasks=$(get_linear_tasks)
  else
    # Get issues with the specified label
    log_info "Fetching tasks from GitHub Issues..."
    local issues_json=$(gh issue list \
      --label "$ISSUE_LABEL" \
      --state open \
      --limit 50 \
      --json number,title,body \
      2>/dev/null)

    if [ -z "$issues_json" ] || [ "$issues_json" = "[]" ]; then
      echo ""
      return
    fi

    tasks=$(echo "$issues_json" | jq -c '.[]')
  fi

  if [ -z "$tasks" ]; then
    echo ""
    return
  fi

  # Ensure MAX_TASKS is a valid number
  MAX_TASKS=${MAX_TASKS:-0}
  [[ "$MAX_TASKS" =~ ^[0-9]+$ ]] || MAX_TASKS=0

  if [ "$MAX_TASKS" -gt 0 ]; then
    echo "$tasks" | head -n "$MAX_TASKS"
  else
    echo "$tasks"
  fi
}

# Parse issue number from JSON
parse_issue_number() {
  echo "$1" | jq -r '.number'
}

# Parse issue title from JSON
parse_issue_title() {
  echo "$1" | jq -r '.title'
}

# Parse issue body from JSON
parse_issue_body() {
  echo "$1" | jq -r '.body // ""'
}

# Parse Linear ID from JSON (only present for Linear tasks)
parse_linear_id() {
  echo "$1" | jq -r '.linear_id // ""'
}

# =============================================================================
# GITHUB PROJECTS SUPPORT (Mercury integration)
# =============================================================================

# Get project item ID for an issue
get_project_item_id() {
  local issue_number="$1"
  local project_number="${GITHUB_PROJECT_NUMBER:-}"
  local project_owner="${GITHUB_PROJECT_OWNER:-${GITHUB_REPO%%/*}}"

  if [ -z "$project_number" ]; then
    return 1
  fi

  # Get the project item ID for this issue
  gh api graphql -f query='
    query($owner: String!, $repo: String!, $issue: Int!, $project: Int!) {
      repository(owner: $owner, name: $repo) {
        issue(number: $issue) {
          projectItems(first: 10) {
            nodes {
              id
              project {
                number
              }
            }
          }
        }
      }
    }
  ' -f owner="$project_owner" -f repo="${GITHUB_REPO##*/}" -F issue="$issue_number" -F project="$project_number" \
    --jq ".data.repository.issue.projectItems.nodes[] | select(.project.number == $project_number) | .id" 2>/dev/null
}

# Get the Status field ID for a project
get_project_status_field_id() {
  local project_number="${GITHUB_PROJECT_NUMBER:-}"
  local project_owner="${GITHUB_PROJECT_OWNER:-${GITHUB_REPO%%/*}}"

  if [ -z "$project_number" ]; then
    return 1
  fi

  gh api graphql -f query='
    query($owner: String!, $project: Int!) {
      user(login: $owner) {
        projectV2(number: $project) {
          id
          field(name: "Status") {
            ... on ProjectV2SingleSelectField {
              id
              options {
                id
                name
              }
            }
          }
        }
      }
    }
  ' -f owner="$project_owner" -F project="$project_number" 2>/dev/null
}

# Update project item status
update_project_item_status() {
  local issue_number="$1"
  local new_status="$2"

  local item_id=$(get_project_item_id "$issue_number")
  if [ -z "$item_id" ]; then
    log_warning "Could not find project item for issue #$issue_number"
    return 1
  fi

  # Get project and field info
  local project_info=$(get_project_status_field_id)
  local project_id=$(echo "$project_info" | jq -r '.data.user.projectV2.id')
  local field_id=$(echo "$project_info" | jq -r '.data.user.projectV2.field.id')
  local option_id=$(echo "$project_info" | jq -r ".data.user.projectV2.field.options[] | select(.name == \"$new_status\") | .id")

  if [ -z "$option_id" ]; then
    log_warning "Could not find status option '$new_status' in project"
    return 1
  fi

  # Update the item status
  gh api graphql -f query='
    mutation($project: ID!, $item: ID!, $field: ID!, $value: String!) {
      updateProjectV2ItemFieldValue(
        input: {projectId: $project, itemId: $item, fieldId: $field, value: {singleSelectOptionId: $value}}
      ) {
        projectV2Item {
          id
        }
      }
    }
  ' -f project="$project_id" -f item="$item_id" -f field="$field_id" -f value="$option_id" 2>/dev/null

  return $?
}

# Get open tasks from GitHub Projects
get_project_tasks() {
  local project_number="${GITHUB_PROJECT_NUMBER:-}"
  local project_owner="${GITHUB_PROJECT_OWNER:-${GITHUB_REPO%%/*}}"
  local ready_status="${PROJECT_STATUS_READY:-spec prepared}"

  if [ -z "$project_number" ]; then
    log_error "GITHUB_PROJECT_NUMBER not set in config.sh"
    return 1
  fi

  # Query project items with ready status that are issues
  local tasks_json=$(gh api graphql -f query='
    query($owner: String!, $project: Int!) {
      user(login: $owner) {
        projectV2(number: $project) {
          items(first: 50) {
            nodes {
              id
              fieldValueByName(name: "Status") {
                ... on ProjectV2ItemFieldSingleSelectValue {
                  name
                }
              }
              content {
                ... on Issue {
                  number
                  title
                  body
                }
              }
            }
          }
        }
      }
    }
  ' -f owner="$project_owner" -F project="$project_number" 2>/dev/null)

  if [ -z "$tasks_json" ]; then
    echo ""
    return
  fi

  # Filter to only items with Ready status and valid issue content
  echo "$tasks_json" | jq -c --arg status "$ready_status" '
    .data.user.projectV2.items.nodes[]
    | select(.fieldValueByName.name == $status)
    | select(.content.number != null)
    | {number: .content.number, title: .content.title, body: .content.body}
  ' 2>/dev/null
}

# =============================================================================
# LINEAR SUPPORT
# =============================================================================

# Get open tasks from Linear (hero label + Open state, oldest first)
get_linear_tasks() {
  if [ -z "$LINEAR_API_KEY" ]; then
    log_error "LINEAR_API_KEY environment variable not set"
    log_info "Run: export LINEAR_API_KEY=\"lin_api_your_key_here\""
    return 1
  fi

  if [ -z "$LINEAR_TEAM_ID" ]; then
    log_error "LINEAR_TEAM_ID not set in config.sh"
    log_info "Run: .agent/linear-setup.sh to get your team ID"
    return 1
  fi

  # Use the linear_get_ready_issues function from linear-api.sh
  # It returns JSON objects with: id, identifier, title, description, createdAt
  # We need to transform to match the expected format: number, title, body
  local linear_issues=$(linear_get_ready_issues 2>/dev/null)

  if [ -z "$linear_issues" ]; then
    echo ""
    return
  fi

  # Transform Linear format to match GitHub Issues format
  # For Linear: number = identifier (e.g., "CON-123"), use id for API calls
  # Merge description + comments so the agent sees full context
  echo "$linear_issues" | jq -c '{
    number: .identifier,
    title: .title,
    body: ((.description // "") + (
      if (.comments.nodes | length) > 0 then
        "

---
## Comments

" + ([.comments.nodes[] | "**" + .user.name + "** (" + .createdAt + "):
" + .body + "
"] | join("
---
"))
      else "" end
    )),
    linear_id: .id
  }' 2>/dev/null
}

# Update Linear issue state
update_linear_task_status() {
  local issue_identifier="$1"
  local issue_linear_id="$2"
  local to_status="$3"

  local state_id=""
  case "$to_status" in
    "ready"|"open"|"Open")
      state_id="$LINEAR_STATE_OPEN_ID"
      ;;
    "working"|"in_progress"|"In Progress")
      state_id="$LINEAR_STATE_IN_PROGRESS_ID"
      ;;
    "review"|"in_review"|"In Review")
      state_id="$LINEAR_STATE_IN_REVIEW_ID"
      ;;
    "staging"|"Staging")
      state_id="$LINEAR_STATE_STAGING_ID"
      ;;
    "completed"|"done"|"Done")
      state_id="$LINEAR_STATE_DONE_ID"
      ;;
    *)
      log_warning "Unknown Linear status: $to_status"
      return 1
      ;;
  esac

  if [ -z "$state_id" ]; then
    log_warning "Linear state ID for '$to_status' not configured. Run .agent/linear-setup.sh"
    return 1
  fi

  log_info "Updating Linear issue $issue_identifier to status: $to_status"
  local result=$(linear_update_state "$issue_linear_id" "$state_id")

  if echo "$result" | jq -e '.data.issueUpdate.success' > /dev/null 2>&1; then
    log_success "Updated $issue_identifier to $to_status"
    return 0
  else
    log_warning "Failed to update Linear issue status"
    echo "$result" | jq -r '.errors[0].message // "Unknown error"' 2>/dev/null
    return 1
  fi
}

# Add comment to Linear issue
add_linear_comment() {
  local issue_linear_id="$1"
  local body="$2"

  local result=$(linear_add_comment "$issue_linear_id" "$body")

  if echo "$result" | jq -e '.data.commentCreate.success' > /dev/null 2>&1; then
    return 0
  else
    log_warning "Failed to add comment to Linear issue"
    return 1
  fi
}

# Get a single Linear issue by identifier (e.g., "DEV-1076") with full comments
get_single_linear_issue() {
  local identifier="$1"
  local team_id="${LINEAR_TEAM_ID:-}"

  if [ -z "$LINEAR_API_KEY" ]; then
    log_error "LINEAR_API_KEY environment variable not set"
    return 1
  fi

  if [ -z "$team_id" ]; then
    log_error "LINEAR_TEAM_ID not set in config.sh"
    return 1
  fi

  # Extract number from identifier (e.g., "DEV-1076" -> 1076)
  local issue_number="${identifier##*-}"

  local query="
    query {
      issues(
        filter: {
          team: { id: { eq: \"$team_id\" } }
          number: { eq: $issue_number }
        }
        first: 1
      ) {
        nodes {
          id
          identifier
          title
          description
          createdAt
          comments {
            nodes {
              body
              user { name }
              createdAt
            }
          }
        }
      }
    }
  "

  # Fetch and transform to match get_linear_tasks format (merges comments into body)
  linear_graphql "$query" | jq -c '.data.issues.nodes[0] // empty | {
    number: .identifier,
    title: .title,
    body: ((.description // "") + (
      if (.comments.nodes | length) > 0 then
        "\n\n---\n## Comments\n\n" + ([.comments.nodes[] | "**" + .user.name + "** (" + .createdAt + "):\n" + .body + "\n"] | join("\n---\n"))
      else "" end
    )),
    linear_id: .id
  }' 2>/dev/null
}

# Update task status based on task source
# For Linear: issue_number is the identifier (CON-123), issue_linear_id is the UUID
update_task_status() {
  local issue_number="$1"
  local from_status="$2"
  local to_status="$3"
  local issue_linear_id="${4:-}"  # Optional: Linear UUID (needed for API calls)

  if [ "$TASK_SOURCE" = "projects" ]; then
    update_project_item_status "$issue_number" "$to_status"
  elif [ "$TASK_SOURCE" = "linear" ]; then
    if [ -n "$issue_linear_id" ]; then
      update_linear_task_status "$issue_number" "$issue_linear_id" "$to_status"
    else
      log_warning "Missing Linear ID for issue $issue_number, cannot update status"
    fi
  else
    # Use label-based status for GitHub issues
    local from_label=""
    local to_label=""

    case "$from_status" in
      "ready") from_label="${ISSUE_LABEL_READY:-agent-ready}" ;;
      "working") from_label="${ISSUE_LABEL_WORKING:-agent-working}" ;;
      "review") from_label="${ISSUE_LABEL_REVIEW:-agent-review}" ;;
      "test") from_label="${ISSUE_LABEL_TEST:-agent-test}" ;;
      "completed") from_label="${ISSUE_LABEL_COMPLETED:-agent-completed}" ;;
    esac

    case "$to_status" in
      "ready") to_label="${ISSUE_LABEL_READY:-agent-ready}" ;;
      "working") to_label="${ISSUE_LABEL_WORKING:-agent-working}" ;;
      "review") to_label="${ISSUE_LABEL_REVIEW:-agent-review}" ;;
      "test") to_label="${ISSUE_LABEL_TEST:-agent-test}" ;;
      "completed") to_label="${ISSUE_LABEL_COMPLETED:-agent-completed}" ;;
    esac

    if [ -n "$from_label" ] && [ -n "$to_label" ]; then
      gh issue edit "$issue_number" --remove-label "$from_label" --add-label "$to_label" 2>/dev/null || true
    elif [ -n "$to_label" ]; then
      gh issue edit "$issue_number" --add-label "$to_label" 2>/dev/null || true
    fi
  fi
}

# Create the run branch

# =============================================================================
# PERSISTENT WORKTREE — one worktree, stays alive across runs
# =============================================================================

setup_workspace() {
  cd "$PROJECT_ROOT" || { log_error "Cannot cd to $PROJECT_ROOT"; exit 1; }

  git fetch origin 2>/dev/null || true

  # Remove any worktree holding staging so we can checkout here
  local wt
  wt=$(git worktree list --porcelain 2>/dev/null | grep -B1 'branch refs/heads/staging' | head -1 | sed 's/worktree //')
  if [[ -n "$wt" && "$wt" != "$PROJECT_ROOT" ]]; then
    git worktree remove "$wt" --force 2>/dev/null || true
  fi

  # Checkout staging (create from origin if needed)
  git checkout staging 2>/dev/null || git checkout -b staging "origin/staging" || {
    log_error "Cannot checkout staging branch"
    exit 1
  }

  # Sync with remote staging first (avoids non-fast-forward on push later)
  git pull --rebase origin staging 2>/dev/null || {
    git rebase --abort 2>/dev/null
    log_warning "Pull --rebase from origin/staging failed — continuing with current state"
  }

  # Merge main to pick up any new commits (preserves staging history)
  git merge "origin/$SOURCE_BRANCH" --no-edit 2>/dev/null || {
    git merge --abort 2>/dev/null
    log_warning "Merge from origin/$SOURCE_BRANCH conflict — continuing with current staging state"
  }

  rm -rf /tmp/oc-review-* 2>/dev/null || true
  log_info "Workspace ready at $PROJECT_ROOT (staging)"
}

# =============================================================================
# POST-RUN: DEPLOY → FIX LOOP → SCENARIO TESTS → LINEAR TASK
# =============================================================================

STAGING_URL="${STAGING_URL:-https://staging.consuelohq.com}"
MAX_DEPLOY_FIX_ATTEMPTS=3

# Check if staging is healthy
check_staging_health() {
  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$STAGING_URL" 2>/dev/null)
  [ "$status" = "200" ] || [ "$status" = "301" ] || [ "$status" = "302" ]
}

# Wait for Railway deploy + health check
wait_for_deploy() {
  local max_wait=300  # 5 minutes
  local interval=30
  local elapsed=0

  log_info "Waiting for Railway deploy at $STAGING_URL..."
  while [ $elapsed -lt $max_wait ]; do
    sleep "$interval"
    elapsed=$((elapsed + interval))
    if check_staging_health; then
      log_success "Staging is healthy after ${elapsed}s"
      return 0
    fi
    log_info "Health check failed, waiting... (${elapsed}/${max_wait}s)"
  done
  log_warning "Staging not healthy after ${max_wait}s"
  return 1
}

# Kiro fix loop for deploy failures
deploy_fix_loop() {
  local attempt=0
  while [ $attempt -lt $MAX_DEPLOY_FIX_ATTEMPTS ]; do
    attempt=$((attempt + 1))
    log_info "Deploy fix attempt $attempt/$MAX_DEPLOY_FIX_ATTEMPTS"

    # Get the error from railway logs
    local error_log
    error_log=$(railway logs --service opensaas 2>&1 | tail -50)

    local fix_prompt="the staging deploy at $STAGING_URL is failing. here are the last 50 lines of railway logs:

$error_log

fix the issue. commit and push to the current branch. do NOT create a new branch."

    # Run kiro to fix
    echo "$fix_prompt" | $KIRO_CMD 2>&1 | tee "$LOG_DIR/deploy-fix-$attempt.log" || true

    # Push fixes
    HUSKY=0 git push origin "$RUN_BRANCH" 2>/dev/null || true

    # Wait for redeploy
    if wait_for_deploy; then
      log_success "Deploy fixed on attempt $attempt"
      return 0
    fi
  done

  log_warning "Deploy still failing after $MAX_DEPLOY_FIX_ATTEMPTS attempts"
  return 1
}

# Run agent-browser scenarios for the current phase
run_scenarios() {
  local phase_number="$1"
  local scenario_file="$SCRIPT_DIR/scenarios/phase-${phase_number}.yml"
  local results_dir="/tmp/scenario-results/$RUN_ID"
  mkdir -p "$results_dir"

  if [ ! -f "$scenario_file" ]; then
    log_info "No scenario file for phase $phase_number, skipping"
    return 0
  fi

  log_info "Running scenarios from $scenario_file against $STAGING_URL"

  local scenario_prompt="invoke the agent-browser skill.

read the scenario file at $scenario_file. run every scenario against $STAGING_URL.
save screenshots to $results_dir/.

for each scenario, drive agent-browser step by step:
- open: agent-browser open <url>
- click: agent-browser click <selector>
- fill: agent-browser fill <selector> <text>
- wait: agent-browser wait <selector|ms>
- snapshot: agent-browser screenshot <path>
- assert visible: agent-browser snapshot --json, check element exists
- assert text: agent-browser get text <selector>, compare

track results: scenario name, pass/fail, duration, failure details if any.

when done, output a JSON summary to $results_dir/results.json:
{
  \"phase\": $phase_number,
  \"scenarios\": [
    {\"name\": \"...\", \"status\": \"pass|fail|blocked\", \"duration_ms\": N, \"error\": \"...\"}
  ]
}"

  echo "$scenario_prompt" | $KIRO_CMD 2>&1 | tee "$LOG_DIR/scenarios-phase-$phase_number.log" || true

  # Check if results were produced
  if [ -f "$results_dir/results.json" ]; then
    return 0
  else
    log_warning "No scenario results produced"
    return 1
  fi
}

# Create linear task with scenario results (ALWAYS — pass or fail)
create_scenario_linear_task() {
  local phase_number="$1"
  local results_dir="/tmp/scenario-results/$RUN_ID"
  local results_file="$results_dir/results.json"

  # Build the task body from results
  local task_body=""
  local task_title=""
  local task_state=""
  local total=0 passed=0 failed=0 blocked=0

  if [ -f "$results_file" ]; then
    total=$(jq '.scenarios | length' "$results_file" 2>/dev/null || echo 0)
    passed=$(jq '[.scenarios[] | select(.status == "pass")] | length' "$results_file" 2>/dev/null || echo 0)
    failed=$(jq '[.scenarios[] | select(.status == "fail")] | length' "$results_file" 2>/dev/null || echo 0)
    blocked=$(jq '[.scenarios[] | select(.status == "blocked")] | length' "$results_file" 2>/dev/null || echo 0)

    # Build results table
    local table
    table=$(jq -r '.scenarios[] | "| \(.name) | \(if .status == "pass" then "✅ PASS" elif .status == "fail" then "❌ FAIL" else "⏭️ BLOCKED" end) | \(.duration_ms // 0)ms | \(.error // "") |"' "$results_file" 2>/dev/null)

    task_body="## Scenario Results — Phase $phase_number
**Staging URL:** $STAGING_URL
**Run ID:** $RUN_ID
**Date:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

### Results
| Scenario | Status | Duration | Notes |
|----------|--------|----------|-------|
$table

### Summary
$passed/$total passed, $failed failed, $blocked blocked."
  else
    task_body="## Scenario Results — Phase $phase_number
**Staging URL:** $STAGING_URL
**Run ID:** $RUN_ID

Scenario runner did not produce results. Check logs at $LOG_DIR/scenarios-phase-$phase_number.log"
    failed=1
  fi

  if [ "$failed" -gt 0 ]; then
    task_title="[test] Phase $phase_number: $failed scenario(s) failed ❌"
    task_state="$LINEAR_STATE_OPEN"
  else
    task_title="[test] Phase $phase_number: all scenarios passed ✅"
    task_state="$LINEAR_STATE_DONE"
  fi

  # Create the linear task
  local query='mutation($input: IssueCreateInput!) { issueCreate(input: $input) { success issue { id identifier url } } }'
  local variables
  variables=$(jq -n \
    --arg title "$task_title" \
    --arg desc "$task_body" \
    --arg teamId "$LINEAR_TEAM_ID" \
    --arg stateId "$task_state" \
    --arg labelId "$LINEAR_LABEL_KIRO_ID" \
    '{
      "input": {
        "title": $title,
        "description": $desc,
        "teamId": $teamId,
        "stateId": $stateId,
        "labelIds": [$labelId]
      }
    }')

  local result
  result=$(linear_graphql "$query" "$variables")
  local issue_url
  issue_url=$(echo "$result" | jq -r '.data.issueCreate.issue.url // empty')

  if [ -n "$issue_url" ]; then
    log_success "Created scenario task: $issue_url"
  else
    log_warning "Failed to create scenario task: $result"
  fi

  # Cleanup screenshots
  rm -rf "$results_dir" 2>/dev/null || true
}

# Main post-run orchestrator
post_run_deploy_and_test() {
  log_info "=========================================="
  log_info "POST-RUN: Deploy + Scenario Testing"
  log_info "=========================================="

  # Merge PR into staging (squash merge)
  if [ -n "$PR_URL" ]; then
    local pr_number
    pr_number=$(echo "$PR_URL" | grep -oE '[0-9]+$')
    log_info "Merging PR #$pr_number into staging..."
    gh pr merge "$pr_number" --squash --repo consuelohq/opensaas 2>&1 || {
      log_warning "PR merge failed — may need manual merge"
      return 1
    }
  fi

  # Wait for Railway to deploy
  if ! wait_for_deploy; then
    log_warning "Staging deploy failed, starting fix loop..."
    if ! deploy_fix_loop; then
      # Create linear task for deploy failure
      create_scenario_linear_task "deploy-failure"
      if [ -f "$SCRIPT_DIR/notify.sh" ]; then
        source "$SCRIPT_DIR/notify.sh"
        send_slack_notification "Deploy Failed" "Staging deploy failed after $MAX_DEPLOY_FIX_ATTEMPTS fix attempts. Manual intervention needed." "failure"
      fi
      return 1
    fi
  fi

  # Detect phase number from the issues we processed
  local phase_number=""
  for scenario_file in "$SCRIPT_DIR"/scenarios/phase-*.yml; do
    [ -f "$scenario_file" ] || continue
    local pnum
    pnum=$(basename "$scenario_file" | sed 's/phase-\([0-9]*\)\.yml/\1/')
    phase_number="$pnum"
    break  # run first matching phase for now
  done

  if [ -z "$phase_number" ]; then
    log_info "No scenario files found, skipping scenario testing"
    return 0
  fi

  # Run scenarios
  run_scenarios "$phase_number"

  # Always create linear task with results
  create_scenario_linear_task "$phase_number"

  # Slack notification
  if [ -f "$SCRIPT_DIR/notify.sh" ]; then
    source "$SCRIPT_DIR/notify.sh"
    local results_file="/tmp/scenario-results/$RUN_ID/results.json"
    if [ -f "$results_file" ]; then
      local passed failed
      passed=$(jq '[.scenarios[] | select(.status == "pass")] | length' "$results_file" 2>/dev/null || echo 0)
      failed=$(jq '[.scenarios[] | select(.status == "fail")] | length' "$results_file" 2>/dev/null || echo 0)
      if [ "$failed" -gt 0 ]; then
        send_slack_notification "Scenarios: $failed failed" "Phase $phase_number: $passed passed, $failed failed" "failure"
      else
        send_slack_notification "Scenarios: all passed ✅" "Phase $phase_number: $passed/$passed scenarios passed" "success"
      fi
    fi
  fi
}

create_run_branch() {
  RUN_ID=$(generate_run_id)
  RUN_BRANCH="staging"

  log_info "Using staging branch (run $RUN_ID, up to date from $SOURCE_BRANCH)"

  # Work directly in main repo on staging (kiro-cli resolves project root from .kiro)
  setup_workspace

  log_success "Staging branch ready (run $RUN_ID)"
}

# Global variable to store PR URL once created
PR_URL=""
# Reuse existing staging→main PR or create one
create_draft_pr() {
  local issue_count="$1"
  local issue_list="$2"

  HUSKY=0 git push -u origin staging 2>/dev/null || {
    log_warning "Initial push failed (non-fast-forward?) — pulling and retrying..."
    git pull --rebase origin staging 2>/dev/null || {
      git rebase --abort 2>/dev/null
      log_warning "Pull --rebase failed — continuing anyway"
    }
    HUSKY=0 git push -u origin staging 2>/dev/null || log_warning "Push still failing — PR creation may fail"
  }

  # Check for existing open PR from staging → main
  PR_URL=$(gh pr list --base "$PR_TARGET_BRANCH" --head staging --state open --json url --jq '.[0].url' 2>/dev/null)

  if [ -n "$PR_URL" ]; then
    log_success "Reusing existing staging PR: $PR_URL"
    gh pr comment "$PR_URL" --body "## Run $RUN_ID started

Processing $issue_count issue(s):
$issue_list" 2>/dev/null || true
    return
  fi

  log_info "Creating staging → $PR_TARGET_BRANCH PR..."
  git commit --allow-empty -m "chore: Start agent run $RUN_ID

Co-Authored-By: suelo-kiro[bot] <260422584+suelo-kiro[bot]@users.noreply.github.com>"
  HUSKY=0 git push origin staging

  PR_URL=$(gh pr create \
    --base "$PR_TARGET_BRANCH" \
    --head staging \
    --title "staging" \
    --body "Persistent PR for agent work. Merges staging → $PR_TARGET_BRANCH.

### Current Run: $RUN_ID ($issue_count issues)

$issue_list" \
    --draft 2>&1)

  if [ $? -eq 0 ] && [ -n "$PR_URL" ]; then
    log_success "Staging PR created: $PR_URL"
  else
    log_warning "Failed to create staging PR (non-fatal)"
    PR_URL=""
  fi
}

# Push commits after each task completes
push_task_commits() {
  local issue_number="$1"

  log_info "Pushing commits for issue #$issue_number..."
  HUSKY=0 git push origin "$RUN_BRANCH"

  if [ $? -eq 0 ]; then
    log_success "Pushed to PR"
  else
    log_warning "Push failed for issue #$issue_number — pulling and retrying..."
    git pull --rebase origin "$RUN_BRANCH" 2>/dev/null || {
      git rebase --abort 2>/dev/null
      log_warning "Pull --rebase failed"
    }
    HUSKY=0 git push origin "$RUN_BRANCH" || log_warning "Push still failing for #$issue_number"
  fi
}

# CRITICAL: Final push to ensure ALL changes are on GitHub
# This catches uncommitted files (like metrics.json) and any commits not yet pushed
final_push_all_changes() {
  log_info "Final push: ensuring all changes are on GitHub..."

  # Check for uncommitted changes
  if ! git diff --quiet || ! git diff --cached --quiet; then
    log_info "Found uncommitted changes, creating final commit..."
    git add -A
    git commit -m "chore: Update agent metrics and state

Run ID: $RUN_ID
Completed: ${#COMPLETED_ISSUES[@]}
Needs Review: $((${#REVIEW_FAILED_ISSUES[@]} + ${#TEST_FAILED_ISSUES[@]}))

Co-Authored-By: suelo-kiro[bot] <260422584+suelo-kiro[bot]@users.noreply.github.com>" || true
  fi

  # Check for unpushed commits
  local unpushed=$(git rev-list --count "origin/$RUN_BRANCH".."$RUN_BRANCH" 2>/dev/null || echo "0")
  if [ "$unpushed" -gt 0 ]; then
    log_info "Pushing $unpushed unpushed commit(s)..."
    HUSKY=0 git push origin "$RUN_BRANCH"
    if [ $? -eq 0 ]; then
      log_success "All changes pushed to GitHub"
    else
      log_error "Failed to push final changes! Manual push required: HUSKY=0 git push origin $RUN_BRANCH"
    fi
  else
    log_info "All commits already pushed to GitHub"
  fi
}

# Send notification at START of run
send_start_notification() {
  local issue_count="$1"
  local issue_list="$2"

  if [ -f "$SCRIPT_DIR/notify.sh" ]; then
    source "$SCRIPT_DIR/notify.sh"
    send_slack_notification \
      "Agent Run Started" \
      "*Run ID:* \`$RUN_ID\`\n*Issues:* $issue_count\n\n$issue_list" \
      "info"
  fi
}

# Run code review on current changes
# Returns 0 if passed, 1 if issues found (issues written to temp file)

# Import Sentry bot issues from GitHub PR comments as GitHub issues
import_sentry_issues() {
  log_info "Checking for Sentry issues from GitHub PRs..."

  # Track file for already-imported comment IDs (persist across runs)
  local imported_file="$SCRIPT_DIR/.sentry-imported-ids"
  touch "$imported_file"

  local imported_count=0

  # Check both merged and open PRs
  for pr_state in merged open; do
    local prs=$(gh pr list --state "$pr_state" --limit 20 --json number 2>/dev/null)

    if [ -z "$prs" ] || [ "$prs" = "[]" ]; then
      continue
    fi

    # Process each PR - use temp file to avoid subshell variable scope issues
    local pr_numbers_file=$(mktemp)
    printf '%s' "$prs" | jq -r '.[].number' > "$pr_numbers_file"

    while read -r pr_number; do
      # Get Sentry bot comments for this PR
      local sentry_comments=$(gh api "repos/${GITHUB_REPO}/pulls/$pr_number/comments" \
        --jq '.[] | select(.user.login == "sentry[bot]") | {id, path, body}' 2>/dev/null)

      if [ -z "$sentry_comments" ]; then
        continue
      fi

      # Process each Sentry comment - use temp file approach
      local comments_file=$(mktemp)
      printf '%s' "$sentry_comments" | jq -c '.' > "$comments_file"

      while read -r comment; do
        [ -z "$comment" ] && continue

        local comment_id=$(printf '%s' "$comment" | jq -r '.id')
        local file_path=$(printf '%s' "$comment" | jq -r '.path')
        local body=$(printf '%s' "$comment" | jq -r '.body')

        # Skip if already imported
        if grep -q "^$comment_id$" "$imported_file" 2>/dev/null; then
          continue
        fi

        # Extract bug description from body (macOS compatible)
        local bug_desc=$(echo "$body" | grep -E '^Bug: ' | sed 's/^Bug: //' | head -1)
        local severity=$(echo "$body" | grep -E '^Severity: ' | sed 's/^Severity: //' | cut -d'|' -f1 | tr -d ' ')

        # Extract the AI prompt section for task description
        local ai_prompt=$(echo "$body" | sed -n '/AI Agent/,/^$/p')

        if [ -n "$bug_desc" ]; then
          # Create GitHub issue with Sentry context and AI prompt
          local issue_title="[SENTRY/$severity] $bug_desc"
          local issue_body="**File:** \`$file_path\`

$ai_prompt

---
**Source:** PR #$pr_number ($pr_state)
**Sentry Comment ID:** $comment_id"

          log_info "  Creating GitHub issue: $issue_title"

          if gh issue create \
            --title "$issue_title" \
            --body "$issue_body" \
            --label "agent-ready" \
            --label "bug" \
            2>/dev/null; then
            # Mark as imported
            echo "$comment_id" >> "$imported_file"
            imported_count=$((imported_count + 1))
          fi
        fi
      done < "$comments_file"

      rm -f "$comments_file"
    done < "$pr_numbers_file"

    rm -f "$pr_numbers_file"
  done

  imported_count=${imported_count:-0}
  [[ "$imported_count" =~ ^[0-9]+$ ]] || imported_count=0

  if [ "$imported_count" -gt 0 ]; then
    log_success "Imported $imported_count Sentry issues as GitHub issues"
  else
    log_info "No new Sentry issues to import"
  fi
}

# Re-prompt agent to fix review issues

# Process a single issue using fresh subprocess (commits to the shared run branch)
process_issue() {
  local issue_json="$1"
  local issue_number=$(parse_issue_number "$issue_json")
  local issue_title=$(parse_issue_title "$issue_json")
  local issue_body=$(parse_issue_body "$issue_json")
  local linear_id=$(parse_linear_id "$issue_json")  # Only present for Linear tasks

  # Determine display format based on task source
  local issue_display=""
  local commit_ref=""
  if [ "$TASK_SOURCE" = "linear" ]; then
    issue_display="$issue_number"  # e.g., CON-123
    commit_ref="$issue_number"     # e.g., CON-123
  else
    issue_display="#$issue_number"
    commit_ref="#$issue_number"
  fi

  log_info "=========================================="
  log_info "Spawning fresh subprocess for issue $issue_display"
  log_info "Title: $issue_title"
  log_info "=========================================="

  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY RUN] Would process issue $issue_display"
    return 0
  fi

  # Update task status to working
  log_info "Marking task as in-progress..."
  if [ "$TASK_SOURCE" = "projects" ]; then
    update_project_item_status "$issue_number" "${PROJECT_STATUS_WORKING:-In Progress}"
  elif [ "$TASK_SOURCE" = "linear" ]; then
    update_linear_task_status "$issue_number" "$linear_id" "In Progress"
  else
    # Remove all status labels before adding working label (issue may have ready, review, or test labels)
    gh issue edit "$issue_number" \
      --remove-label "${ISSUE_LABEL_READY:-agent-ready}" \
      --remove-label "${ISSUE_LABEL_REVIEW:-agent-review}" \
      --remove-label "${ISSUE_LABEL_TEST:-agent-test}" \
      --add-label "${ISSUE_LABEL_WORKING:-agent-working}" 2>/dev/null || true
  fi

  # Capture HEAD before subprocess (to detect new commits)
  local head_before=$(git rev-parse HEAD)

  # Spawn fresh $AGENT_CLI subprocess (isolated context)
  spawn_task_subprocess "$issue_number" "$issue_title" "$issue_body"
  local subprocess_exit=$?

  # Post output summary to Linear
  if [ "$TASK_SOURCE" = "linear" ] && [ -n "$linear_id" ]; then
    local task_log="$LOG_DIR/task-${issue_number}.log"
    if [ -f "$task_log" ]; then
      local summary
      summary=$(tail -50 "$task_log" | head -c 4000)
      add_linear_comment "$linear_id" "$(printf '**kiro output (last 50 lines):**\n```\n%s\n```' "$summary")"
    fi
  fi

  # Capture HEAD after subprocess
  local head_after=$(git rev-parse HEAD)
  local has_new_commits=false
  local has_uncommitted_changes=false

  # Check if $AGENT_CLI made new commits
  if [ "$head_before" != "$head_after" ]; then
    has_new_commits=true
    local new_commit_count=$(git rev-list --count "$head_before".."$head_after")
    log_info "$AGENT_CLI made $new_commit_count new commit(s)"
  fi

  # Check if there are uncommitted changes (agent started work but didn't commit)
  if ! git diff --quiet || ! git diff --cached --quiet; then
    has_uncommitted_changes=true
  fi

  # If no new commits AND no uncommitted changes, nothing happened
  if [ "$has_new_commits" = false ] && [ "$has_uncommitted_changes" = false ]; then
    log_warning "No changes made by subprocess for issue $issue_display"
    # Reset status back to ready
    if [ "$TASK_SOURCE" = "projects" ]; then
      update_project_item_status "$issue_number" "${PROJECT_STATUS_READY:-Ready}"
    elif [ "$TASK_SOURCE" = "linear" ]; then
      update_linear_task_status "$issue_number" "$linear_id" "Open"
    else
      # Remove all status labels before resetting to ready
      gh issue edit "$issue_number" \
        --remove-label "${ISSUE_LABEL_WORKING:-agent-working}" \
        --remove-label "${ISSUE_LABEL_REVIEW:-agent-review}" \
        --remove-label "${ISSUE_LABEL_TEST:-agent-test}" \
        --add-label "${ISSUE_LABEL_READY:-agent-ready}" 2>/dev/null || true
    fi
    FAILED_ISSUES+=("$issue_number:$issue_title:no_changes")
    return 1
  fi

  # Ensure any uncommitted changes are committed (if agent didn't commit them)
  if [ "$has_uncommitted_changes" = true ]; then
    log_info "Found uncommitted changes, creating commit for issue $issue_display..."
    git add -A
    git commit -m "fix($commit_ref): ${issue_title}

Automated commit by agent workflow.

Co-Authored-By: suelo-kiro[bot] <260422584+suelo-kiro[bot]@users.noreply.github.com>" || true
  fi

  # Run quality gates (code review + tests) - pass linear_id for status updates
  # Coderabbit reviews on PR — no local review gate needed
  COMPLETED_ISSUES+=("$issue_number:$issue_title:$linear_id")

  # Push commits immediately (so work is saved even if script crashes)
  push_task_commits "$issue_number"

  return 0
}

# Finalize the PR (update description and mark ready for review)
finalize_pr() {
  local total_issues=${#COMPLETED_ISSUES[@]}
  local review_issues=${#REVIEW_FAILED_ISSUES[@]}
  local test_issues=${#TEST_FAILED_ISSUES[@]}
  local failed_count=${#FAILED_ISSUES[@]}

  # Get commit count
  local commit_count=$(git rev-list --count "$PR_TARGET_BRANCH".."$RUN_BRANCH" 2>/dev/null || echo "0")

  log_info "=========================================="
  log_info "Finalizing PR with $commit_count commit(s)"
  log_info "=========================================="

  # Build PR title
  local pr_title=""
  local total_processed=$((total_issues + review_issues + test_issues))

  if [ $review_issues -eq 0 ] && [ $test_issues -eq 0 ]; then
    pr_title="Agent Run: $total_issues issue(s) completed"
  else
    pr_title="[REVIEW NEEDED] Agent Run: $total_processed issue(s) processed"
  fi

  # Build PR body
  local pr_body="## Agent Run Summary

**Run ID:** \`$RUN_ID\`
**Branch:** \`$RUN_BRANCH\`
**Commits:** $commit_count

---

"

  # Helper function to format issue reference based on task source
  # Entry format: "number:title:linear_id" (linear_id is optional)
  format_issue_ref() {
    local num="$1"
    if [ "$TASK_SOURCE" = "linear" ]; then
      echo "$num"  # Linear: CON-123 (no #)
    else
      echo "#$num"  # GitHub: #123
    fi
  }

  # Add completed issues section
  # NOTE: Using "Related to" instead of "Closes" to avoid auto-closing issues on merge.
  # Human review is required before closing issues.
  if [ ${#COMPLETED_ISSUES[@]} -gt 0 ]; then
    pr_body+="### ✅ Completed Issues (requires human approval to close)

"
    for entry in "${COMPLETED_ISSUES[@]}"; do
      local num="${entry%%:*}"
      local rest="${entry#*:}"
      local title="${rest%%:*}"
      local ref=$(format_issue_ref "$num")
      if [ "$TASK_SOURCE" = "linear" ]; then
        # Linear auto-links with identifier, no need for "Related to"
        pr_body+="- $ref - $title
"
      else
        pr_body+="- Related to $ref - $title
"
      fi
    done
    pr_body+="
"
  fi

  # Add review-needed issues section
  if [ ${#REVIEW_FAILED_ISSUES[@]} -gt 0 ]; then
    pr_body+="### ⚠️ Code Review Failed (needs human review)

"
    for entry in "${REVIEW_FAILED_ISSUES[@]}"; do
      local num="${entry%%:*}"
      local rest="${entry#*:}"
      local title="${rest%%:*}"
      local ref=$(format_issue_ref "$num")
      pr_body+="- $ref - $title
"
    done
    pr_body+="
"
  fi

  # Add test-failed issues section
  if [ ${#TEST_FAILED_ISSUES[@]} -gt 0 ]; then
    pr_body+="### ⚠️ Tests Failed (needs human review)

"
    for entry in "${TEST_FAILED_ISSUES[@]}"; do
      local num="${entry%%:*}"
      local rest="${entry#*:}"
      local title="${rest%%:*}"
      local ref=$(format_issue_ref "$num")
      pr_body+="- $ref - $title
"
    done
    pr_body+="
"
  fi

  # Add no-changes issues section
  if [ ${#FAILED_ISSUES[@]} -gt 0 ]; then
    pr_body+="### ❌ No Changes Made

"
    for entry in "${FAILED_ISSUES[@]}"; do
      local num="${entry%%:*}"
      local rest="${entry#*:}"
      local title="${rest%%:*}"
      local ref=$(format_issue_ref "$num")
      pr_body+="- $ref - $title (agent made no changes)
"
    done
    pr_body+="
"
  fi

  # Add quality gates summary
  pr_body+="---

## Quality Gates

| Issue | Code Review | Tests |
|-------|-------------|-------|
"

  # Add rows for each processed issue
  for entry in "${COMPLETED_ISSUES[@]}"; do
    local num="${entry%%:*}"
    local ref=$(format_issue_ref "$num")
    pr_body+="| $ref | ✅ Passed | ✅ Passed |
"
  done

  for entry in "${REVIEW_FAILED_ISSUES[@]}"; do
    local num="${entry%%:*}"
    local ref=$(format_issue_ref "$num")
    local in_test_failed=false
    for test_entry in "${TEST_FAILED_ISSUES[@]}"; do
      if [[ "$test_entry" == "$num:"* ]]; then
        in_test_failed=true
        break
      fi
    done
    if [ "$in_test_failed" = true ]; then
      pr_body+="| $ref | ❌ Failed | ❌ Failed |
"
    else
      pr_body+="| $ref | ❌ Failed | ✅ Passed |
"
    fi
  done

  for entry in "${TEST_FAILED_ISSUES[@]}"; do
    local num="${entry%%:*}"
    local ref=$(format_issue_ref "$num")
    local in_review_failed=false
    for review_entry in "${REVIEW_FAILED_ISSUES[@]}"; do
      if [[ "$review_entry" == "$num:"* ]]; then
        in_review_failed=true
        break
      fi
    done
    if [ "$in_review_failed" = false ]; then
      pr_body+="| $ref | ✅ Passed | ❌ Failed |
"
    fi
  done

  pr_body+="
---
*Created by autonomous agent workflow*
*Task Source: $TASK_SOURCE*"

  # Move completed Linear issues to "In Review"
  if [ "$TASK_SOURCE" = "linear" ]; then
    for entry in "${COMPLETED_ISSUES[@]}"; do
      local num="${entry%%:*}"
      local rest="${entry#*:}"
      local lid="${rest##*:}"
      if [ -n "$lid" ] && [ "$lid" != "$num" ]; then
        update_linear_task_status "$num" "$lid" "In Review"
      fi
    done
  fi

  # Update PR title and body
  if [ -n "$PR_URL" ]; then
    log_info "Updating PR description..."
    gh pr edit "$RUN_BRANCH" --title "$pr_title" --body "$pr_body" 2>/dev/null || true

    # Mark PR as ready for review (remove draft status)
    log_info "Marking PR as ready for review..."
    gh pr ready "$RUN_BRANCH" 2>/dev/null || true

    log_success "PR updated and ready for review: $PR_URL"
  else
    # Fallback: create PR if draft creation failed earlier
    log_info "Creating PR (draft creation may have failed earlier)..."
    HUSKY=0 git push -u origin "$RUN_BRANCH" 2>/dev/null || true

    PR_URL=$(gh pr create \
      --base "$PR_TARGET_BRANCH" \
      --head "$RUN_BRANCH" \
      --title "$pr_title" \
      --body "$pr_body" 2>&1)

    if [ $? -eq 0 ] && [ -n "$PR_URL" ]; then
      log_success "PR created: $PR_URL"
    else
      log_warning "Failed to create PR: $PR_URL"
      PR_URL=""
    fi
  fi

  # Send Slack notification with session results
  if [ -f "$SCRIPT_DIR/notify.sh" ]; then
    source "$SCRIPT_DIR/notify.sh"
    local status_emoji="success"
    local needs_review=$((review_issues + test_issues))
    if [ $needs_review -gt 0 ]; then
      status_emoji="warning"
    fi

    # Build session summary message
    local session_msg="*This Session*\n"
    session_msg+="• Run ID: \`$RUN_ID\`\n"
    session_msg+="• Processed: $((total_issues + needs_review)) tasks\n"
    session_msg+="• ✅ Completed: $total_issues\n"
    session_msg+="• ⚠️ Needs Review: $needs_review\n"
    session_msg+="• PR: $PR_URL"

    send_slack_notification \
      "Agent Run Complete" \
      "$session_msg" \
      "$status_emoji"
  fi

  echo ""
  log_success "=========================================="
  log_success "PR URL: $PR_URL"
  log_success "=========================================="
}

# Main execution
main() {
  # Display task source info
  if [ "$TASK_SOURCE" = "projects" ]; then
    log_info "Autonomous Agent Task Runner (mercury Projects)"
    log_info "Project: #${GITHUB_PROJECT_NUMBER} (owner: ${GITHUB_PROJECT_OWNER})"
    log_info "Ready status: ${PROJECT_STATUS_READY}"
  elif [ "$TASK_SOURCE" = "linear" ]; then
    log_info "Autonomous Agent Task Runner (Linear)"
    log_info "Team ID: ${LINEAR_TEAM_ID}"
    log_info "Label: ${LINEAR_LABEL_NAME:-hero}"
    log_info "Ready state: ${LINEAR_STATE_OPEN:-Open}"
  else
    log_info "Autonomous Agent Task Runner (GitHub Issues)"
    log_info "Issue label: $ISSUE_LABEL"
  fi
  log_info "Using agent: $AGENT_CLI"
  log_info "Max tasks: ${MAX_TASKS:-unlimited}"
  log_info "Mode: Fresh subprocess per task (isolated sessions)"

  # Check for previous interrupted run
  if check_run_state; then
    log_info "Continuing from previous run state..."
  fi

  check_prerequisites

  # Only ensure GitHub labels when using GitHub Issues
  if [ "$TASK_SOURCE" = "issues" ]; then
    ensure_labels_exist
  fi

  cd "$PROJECT_ROOT"

  # Import any new Sentry issues from GitHub PRs (only when using GitHub issues mode)
  # Skip for Linear and Projects - Sentry import is GitHub-specific
  if [ "$TASK_SOURCE" = "issues" ]; then
    import_sentry_issues
  fi

  # Get open tasks
  local issues=""
  if [ -n "$SINGLE_ISSUE" ]; then
    log_info "Fetching single issue: $SINGLE_ISSUE"
    issues=$(get_single_linear_issue "$SINGLE_ISSUE")
  else
    issues=$(get_open_issues)
  fi

  # Handle empty results properly
  if [ -z "$issues" ] || [ "$issues" = "" ]; then
    if [ -n "$SINGLE_ISSUE" ]; then
      log_error "Issue $SINGLE_ISSUE not found in Linear"
    elif [ "$TASK_SOURCE" = "projects" ]; then
      log_success "No tasks with status '${PROJECT_STATUS_READY}' in mercury project"
    elif [ "$TASK_SOURCE" = "linear" ]; then
      log_success "No Linear issues with '${LINEAR_LABEL_NAME:-hero}' label in '${LINEAR_STATE_OPEN:-Open}' state"
    else
      log_success "No open issues with label '$ISSUE_LABEL' to process"
    fi
    exit 0
  fi

  # Count tasks (filter out empty lines that start with {)
  local issue_count=0
  while IFS= read -r line; do
    [[ "$line" == "{"* ]] && ((issue_count++))
  done <<< "$issues"

  if [ "$issue_count" -eq 0 ]; then
    if [ "$TASK_SOURCE" = "projects" ]; then
      log_success "No tasks with status '${PROJECT_STATUS_READY}' in mercury project"
    elif [ "$TASK_SOURCE" = "linear" ]; then
      log_success "No Linear issues with '${LINEAR_LABEL_NAME:-hero}' label in '${LINEAR_STATE_OPEN:-Open}' state"
    else
      log_success "No open issues with label '$ISSUE_LABEL' to process"
    fi
    exit 0
  fi

  log_info "Found $issue_count task(s) to process"

  # Preview tasks (use appropriate format for Linear vs GitHub)
  echo "$issues" | while read -r issue_json; do
    [ -z "$issue_json" ] && continue
    local num=$(echo "$issue_json" | jq -r '.number' 2>/dev/null)
    local title=$(echo "$issue_json" | jq -r '.title' 2>/dev/null)
    if [ -n "$num" ] && [ "$num" != "null" ]; then
      if [ "$TASK_SOURCE" = "linear" ]; then
        echo "  - $num: $title"  # Linear: CON-123
      else
        echo "  - #$num: $title"  # GitHub: #123
      fi
    fi
  done
  echo ""

  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY RUN] Would create a single branch and PR for all $issue_count tasks"
    exit 0
  fi

  # Create the run branch (ONE branch for all tasks)
  create_run_branch

  # Build issue list for notification (use appropriate format)
  local issue_list=""
  while read -r issue_json; do
    # Skip empty lines and non-JSON content
    [[ -z "$issue_json" || "$issue_json" != "{"* ]] && continue
    local num=$(echo "$issue_json" | jq -r '.number' 2>/dev/null)
    local title=$(echo "$issue_json" | jq -r '.title' 2>/dev/null)
    if [[ -n "$num" && "$num" != "null" ]]; then
      if [ "$TASK_SOURCE" = "linear" ]; then
        issue_list+="• $num: $title\n"  # Linear: CON-123
      else
        issue_list+="• #$num: $title\n"  # GitHub: #123
      fi
    fi
  done <<< "$issues"

  # Send START notification
  send_start_notification "$issue_count" "$issue_list"

  # Create draft PR immediately (so commits are pushed to an existing PR)
  create_draft_pr "$issue_count" "$issue_list"

  # Process each issue in a fresh subprocess
  local processed=0
  local total_count=$issue_count

  # Save issues to a temp file to avoid stdin interference from agent command
  local issues_file=$(mktemp)
  echo "$issues" > "$issues_file"

  while read -r issue_json <&3; do
    # Skip empty lines and non-JSON content
    [[ -z "$issue_json" || "$issue_json" != "{"* ]] && continue

    processed=$((processed + 1))

    log_info "=========================================="
    log_info "Task $processed of $total_count"
    log_info "=========================================="

    process_issue "$issue_json"

    # Save state after each task (enables resume if interrupted)
    save_run_state "$processed"

    echo ""
  done 3< "$issues_file"

  rm -f "$issues_file"

  # Clear run state on successful completion
  clear_run_state

  # Finalize the PR (update description and mark ready for review)
  finalize_pr

  # CRITICAL: Final push to ensure ALL changes are on GitHub
  # This catches any uncommitted changes (like metrics.json) that weren't part of task commits
  final_push_all_changes

  log_info "=========================================="
  log_info "Run complete!"
  log_info "Run ID: $RUN_ID"
  log_info "Processed: $processed"
  log_info "Completed: ${#COMPLETED_ISSUES[@]}"
  log_info "Needs Review: $((${#REVIEW_FAILED_ISSUES[@]} + ${#TEST_FAILED_ISSUES[@]}))"
  log_info "No Changes: ${#FAILED_ISSUES[@]}"
  log_info "=========================================="
}

main "$@"