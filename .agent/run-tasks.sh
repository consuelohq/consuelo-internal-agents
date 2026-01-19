#!/bin/bash
#
# Autonomous Agent Task Runner
#
# Loops through all open Beads tasks and invokes an AI agent (Claude Code or OpenCode)
# to work on each task. Each task gets its own branch, tests, and PR.
#
# Usage:
#   .agent/run-tasks.sh                    # Process all open tasks with default agent
#   .agent/run-tasks.sh --max-tasks 3      # Process at most 3 tasks
#   .agent/run-tasks.sh --agent opencode   # Use OpenCode instead of Claude
#   .agent/run-tasks.sh --dry-run          # Preview tasks without processing
#
# Prerequisites:
#   - Beads installed (bd command available)
#   - Claude Code or OpenCode CLI installed
#   - GitHub CLI (gh) for PR creation
#   - Git configured with push access
#

# Don't use set -e - we want to continue processing tasks even if one fails
# Individual command failures are handled explicitly

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
else
  # Default configuration
  AGENT_CLI="claude"
  CLAUDE_CMD="claude --print"
  OPENCODE_CMD="opencode"
  BASE_BRANCH="main"
  BRANCH_PREFIX="agent"
  TEST_COMMAND="npm test"
fi

# Parse command line arguments
MAX_TASKS=0  # 0 means unlimited
DRY_RUN=false
AGENT_OVERRIDE=""

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
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --max-tasks N    Process at most N tasks (default: unlimited)"
      echo "  --agent NAME     Use specific agent CLI: claude or opencode"
      echo "  --dry-run        Preview tasks without processing"
      echo "  --help           Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Use override if provided
if [ -n "$AGENT_OVERRIDE" ]; then
  AGENT_CLI="$AGENT_OVERRIDE"
fi

# Get the agent command based on CLI choice
get_agent_cmd() {
  if [ "$AGENT_CLI" = "claude" ]; then
    echo "$CLAUDE_CMD"
  else
    echo "$OPENCODE_CMD"
  fi
}

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

# Check prerequisites
check_prerequisites() {
  log_info "Checking prerequisites..."

  # Check for Beads
  if ! command -v bd &> /dev/null; then
    log_error "Beads (bd) is not installed. Install from: https://github.com/steveyegge/beads"
    exit 1
  fi

  # Check for GitHub CLI
  if ! command -v gh &> /dev/null; then
    log_error "GitHub CLI (gh) is not installed. Install from: https://cli.github.com"
    exit 1
  fi

  # Check for agent CLI
  if [ "$AGENT_CLI" = "claude" ]; then
    if ! command -v claude &> /dev/null; then
      log_error "Claude Code CLI is not installed"
      exit 1
    fi
  else
    if ! command -v opencode &> /dev/null; then
      log_error "OpenCode CLI is not installed"
      exit 1
    fi
  fi

  # Check for git
  if ! command -v git &> /dev/null; then
    log_error "Git is not installed"
    exit 1
  fi

  log_success "All prerequisites satisfied"
}

# Get list of open tasks from Beads
get_open_tasks() {
  # bd list outputs tasks in format: ID [PRIORITY] [TYPE] STATUS - TITLE
  # Filter for open/pending tasks
  local tasks=$(bd list 2>/dev/null | grep -E "open|pending")

  # Ensure MAX_TASKS is a valid number (handles empty/malformed values)
  MAX_TASKS=${MAX_TASKS:-0}
  [[ "$MAX_TASKS" =~ ^[0-9]+$ ]] || MAX_TASKS=0

  if [ "$MAX_TASKS" -gt 0 ]; then
    echo "$tasks" | head -n "$MAX_TASKS"
  else
    echo "$tasks"
  fi
}

# Parse task ID from Beads list output
parse_task_id() {
  echo "$1" | awk '{print $1}'
}

# Parse task title from Beads list output
parse_task_title() {
  echo "$1" | sed 's/^[^ ]* \[[^]]*\] \[[^]]*\] [^ ]* - //'
}

# Create branch name from task
create_branch_name() {
  local task_id="$1"
  local task_title="$2"

  # Sanitize title for branch name: lowercase, replace spaces/special chars with dashes
  local sanitized_title=$(echo "$task_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | head -c 50)

  echo "${BRANCH_PREFIX}/${task_id}-${sanitized_title}"
}

# Run code review on current changes
# Returns 0 if passed, 1 if issues found (issues written to temp file)
run_code_review() {
  local task_id="$1"
  local issues_file="$2"

  log_info "Running code review..."

  # Get the diff to review (compare to parent commit or staged changes)
  local diff_content=$(git diff HEAD~1 2>/dev/null || git diff --cached)

  if [ -z "$diff_content" ]; then
    log_warning "No changes to review"
    return 0
  fi

  # Truncate diff if too large (Claude has context limits)
  local diff_lines=$(echo "$diff_content" | wc -l | tr -d ' ')
  # Ensure diff_lines is a valid number (handles empty/malformed values)
  diff_lines=${diff_lines:-0}
  [[ "$diff_lines" =~ ^[0-9]+$ ]] || diff_lines=0

  if [ "$diff_lines" -gt 500 ]; then
    log_warning "Diff too large ($diff_lines lines), truncating to 500 lines"
    diff_content=$(echo "$diff_content" | head -n 500)
    diff_content="$diff_content

... [TRUNCATED - $diff_lines total lines] ..."
  fi

  # Create review prompt
  # TODO: Customize this prompt for your project's code review requirements
  local review_prompt="Review this code change for quality and issues.

CRITICAL INSTRUCTION: Do NOT just pass to pass. If there are REAL blocking issues, you MUST report them. This is a quality gate.

After reviewing, output your findings in this EXACT format (this format is parsed by automation):

REVIEW_STATUS: PASS
(or)
REVIEW_STATUS: FAIL

BLOCKING_ISSUES:
- None
(or list each issue on its own line with a leading dash)

=== DIFF TO REVIEW ===
\`\`\`diff
$diff_content
\`\`\`
=== END DIFF ===

WHAT TO FLAG (blocking):
- Security vulnerabilities (SQL injection, XSS, hardcoded secrets)
- Missing error handling for critical paths
- Breaking API changes without migration
- Obvious bugs or logic errors

WHAT NOT TO FLAG:
- Minor style preferences (linters handle this)
- Nitpicks that don't affect functionality
- Suggestions for improvement (save for PR comments)

Remember: Output REVIEW_STATUS: PASS or REVIEW_STATUS: FAIL followed by BLOCKING_ISSUES section."

  # Write prompt to temp file
  local prompt_file=$(mktemp)
  echo "$review_prompt" > "$prompt_file"

  # Run Claude with review prompt
  log_info "Invoking Claude for code review..."
  local review_output=$(claude --print "$(cat "$prompt_file")" 2>&1)
  local review_exit_code=$?

  rm -f "$prompt_file"

  if [ $review_exit_code -ne 0 ]; then
    log_warning "Code review agent exited with code $review_exit_code"
  fi

  # Parse output for REVIEW_STATUS
  if echo "$review_output" | grep -q "REVIEW_STATUS: PASS"; then
    log_success "Code review passed"
    return 0
  else
    log_warning "Code review found issues"

    # Extract blocking issues section and write to file
    echo "$review_output" | sed -n '/BLOCKING_ISSUES:/,/^$/p' > "$issues_file"

    # Also save full output for debugging
    echo "$review_output" > "${issues_file}.full"

    return 1
  fi
}

# Create Beads issues from review findings
create_beads_issues() {
  local issues_file="$1"
  local parent_task_id="$2"

  log_info "Creating Beads issues for review findings..."

  # Read issues and create Beads tasks for each
  while IFS= read -r line; do
    # Skip empty lines, header, and "None"
    if [[ -n "$line" && "$line" != "BLOCKING_ISSUES:" && "$line" != "- None" && "$line" != "None" ]]; then
      # Remove leading "- " if present
      local issue_text="${line#- }"
      # Remove leading whitespace
      issue_text="${issue_text#"${issue_text%%[![:space:]]*}"}"

      if [ -n "$issue_text" ] && [ "$issue_text" != "None" ]; then
        log_info "  Creating issue: $issue_text"
        bd create "[REVIEW] $issue_text" 2>/dev/null || true
      fi
    fi
  done < "$issues_file"
}

# Re-prompt agent to fix review issues
fix_review_issues() {
  local task_id="$1"
  local issues_file="$2"

  local issues_content=$(cat "$issues_file")

  local fix_prompt="The automated code review for task $task_id found BLOCKING issues that MUST be fixed before merge.

ISSUES TO FIX:
$issues_content

Instructions:
1. Fix ALL of these issues in the code
2. Stage and commit your fixes with a message like 'fix: address code review feedback'
3. Do NOT push - the review will run again automatically

Be thorough - the code review will run again after your fixes."

  log_info "Re-prompting agent to fix review issues..."

  local prompt_file=$(mktemp)
  echo "$fix_prompt" > "$prompt_file"

  if [ "$AGENT_CLI" = "claude" ]; then
    claude --print "$(cat "$prompt_file")"
    local exit_code=$?
  else
    opencode "$(cat "$prompt_file")"
    local exit_code=$?
  fi

  rm -f "$prompt_file"
  return $exit_code
}

# Process a single task
process_task() {
  local task_line="$1"
  local task_id=$(parse_task_id "$task_line")
  local task_title=$(parse_task_title "$task_line")
  local branch_name=$(create_branch_name "$task_id" "$task_title")

  log_info "=========================================="
  log_info "Processing task: $task_id"
  log_info "Title: $task_title"
  log_info "Branch: $branch_name"
  log_info "=========================================="

  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY RUN] Would process task $task_id"
    return 0
  fi

  # Create and checkout new branch from base branch
  log_info "Creating branch from $BASE_BRANCH..."
  git fetch origin "$BASE_BRANCH" 2>/dev/null || true
  git checkout "$BASE_BRANCH" 2>/dev/null || git checkout -b "$BASE_BRANCH" origin/"$BASE_BRANCH"
  git pull origin "$BASE_BRANCH" 2>/dev/null || true
  git checkout -b "$branch_name" 2>/dev/null || git checkout "$branch_name"

  # Create the agent prompt
  # TODO: Customize this prompt for your project
  local agent_prompt="You are working on task $task_id from the Beads task queue.

Task: $task_title

Follow the RPI (Research-Plan-Implement) workflow:
1. RESEARCH: Explore the codebase to understand the relevant files and patterns
2. PLAN: Create a clear implementation plan with file paths and steps
3. IMPLEMENT: Execute the plan, making the necessary changes

After implementation:
1. Run any relevant tests to verify your changes work
2. Commit your changes with a descriptive message
3. If tests pass, you can mark the task complete

Important:
- Read CLAUDE.md or README.md for project guidelines
- Test your changes before marking complete

Begin by researching the codebase for: $task_title"

  # Invoke the agent
  log_info "Invoking $AGENT_CLI agent..."

  # Write prompt to temp file to handle multiline content safely
  local prompt_file=$(mktemp)
  echo "$agent_prompt" > "$prompt_file"

  if [ "$AGENT_CLI" = "claude" ]; then
    # Claude Code: pass prompt as argument with --print for non-interactive
    claude --print "$(cat "$prompt_file")"
    local agent_exit_code=$?
  else
    # OpenCode: similar invocation
    opencode "$(cat "$prompt_file")"
    local agent_exit_code=$?
  fi

  rm -f "$prompt_file"

  if [ $agent_exit_code -ne 0 ]; then
    log_warning "Agent exited with code $agent_exit_code"
  fi

  # Check if there are changes to commit and push
  if git diff --quiet && git diff --cached --quiet; then
    log_warning "No changes made by agent for task $task_id"
    return 1
  fi

  # Code review loop
  local max_review_attempts=3
  local review_attempt=0
  local issues_file=$(mktemp)
  local review_passed=false

  while [ $review_attempt -lt $max_review_attempts ]; do
    review_attempt=$((review_attempt + 1))
    log_info "Code review attempt $review_attempt of $max_review_attempts..."

    if run_code_review "$task_id" "$issues_file"; then
      review_passed=true
      break
    else
      # Create Beads issues for tracking
      create_beads_issues "$issues_file" "$task_id"

      if [ $review_attempt -lt $max_review_attempts ]; then
        # Re-prompt agent to fix issues
        fix_review_issues "$task_id" "$issues_file"
      else
        log_error "Max review attempts reached ($max_review_attempts). Issues remain unfixed."
      fi
    fi
  done

  # Clean up issues file
  rm -f "$issues_file" "${issues_file}.full"

  # Run tests
  # TODO: Customize this test command for your project
  log_info "Running tests..."
  local tests_passed=false
  if eval "$TEST_COMMAND" 2>&1; then
    log_success "Tests passed"
    tests_passed=true
  else
    log_error "Tests failed for task $task_id"
  fi

  # Determine PR status and body based on review and test results
  local pr_title=""
  local pr_body=""
  local should_close_task=false

  if [ "$review_passed" = true ] && [ "$tests_passed" = true ]; then
    # Everything passed - clean PR
    pr_title="Agent: $task_title"
    pr_body="## Task
$task_title

## Changes
This PR was created by an AI agent working on Beads task \`$task_id\`.

## Quality Gates
- [x] Automated code review passed (attempt $review_attempt of $max_review_attempts)
- [x] Tests passed

---
*Created by autonomous agent workflow*"
    should_close_task=true

  elif [ "$review_passed" = true ] && [ "$tests_passed" = false ]; then
    # Review passed but tests failed
    pr_title="[TESTS FAILED] Agent: $task_title"
    pr_body="## Task
$task_title

## Status
:warning: **Tests failed** - This PR needs human review.

## Quality Gates
- [x] Automated code review passed
- [ ] Tests **FAILED**

## Changes
This PR was created by an AI agent working on Beads task \`$task_id\`.

---
*Created by autonomous agent workflow*"

  elif [ "$review_passed" = false ] && [ "$tests_passed" = true ]; then
    # Tests passed but review failed
    pr_title="[REVIEW ISSUES] Agent: $task_title"
    pr_body="## Task
$task_title

## Status
:warning: **Code review found issues** - This PR needs human review.

## Quality Gates
- [ ] Automated code review **FAILED** (attempted $review_attempt times)
- [x] Tests passed

## Changes
This PR was created by an AI agent working on Beads task \`$task_id\`.

---
*Created by autonomous agent workflow*"

  else
    # Both failed
    pr_title="[NEEDS REVIEW] Agent: $task_title"
    pr_body="## Task
$task_title

## Status
:x: **Multiple issues** - This PR needs human review.

## Quality Gates
- [ ] Automated code review **FAILED** (attempted $review_attempt times)
- [ ] Tests **FAILED**

## Changes
This PR was created by an AI agent working on Beads task \`$task_id\`.

---
*Created by autonomous agent workflow*"
  fi

  # Push and create PR
  log_info "Pushing to GitHub..."
  git push -u origin "$branch_name"

  log_info "Creating pull request..."
  local pr_url=$(gh pr create \
    --base "$BASE_BRANCH" \
    --head "$branch_name" \
    --title "$pr_title" \
    --body "$pr_body" 2>&1)

  log_success "PR created: $pr_url"

  # Extract PR number from URL for labeling
  local pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')

  # Apply comprehensive labels to the PR
  if [ -n "$pr_number" ] && [ -f "$SCRIPT_DIR/label-pr.sh" ]; then
    log_info "Applying labels to PR #$pr_number..."
    bash "$SCRIPT_DIR/label-pr.sh" "$pr_number" "$task_title" "$review_passed" "$tests_passed" || {
      log_warning "Failed to apply some labels (non-fatal)"
    }
  fi

  # Update metrics and send Slack notification
  if [ -f "$SCRIPT_DIR/notify.sh" ]; then
    source "$SCRIPT_DIR/notify.sh"
    local status_emoji="success"
    local metrics_status="success"
    if [ "$should_close_task" = false ]; then
      status_emoji="warning"
      metrics_status="failure"
    fi
    # Update metrics (duration tracking would require start time)
    update_metrics "$metrics_status" 0
    send_slack_notification \
      "Agent Task Complete" \
      "Task: $task_title\nPR: $pr_url" \
      "$status_emoji"
  fi

  # Only mark task as complete if everything passed
  if [ "$should_close_task" = true ]; then
    log_info "Marking task complete in Beads..."
    bd close "$task_id" --reason "Completed by agent. PR: $pr_url" 2>/dev/null || true
    return 0
  else
    log_warning "Task not closed due to quality gate failures"
    return 1
  fi
}

# Main execution
main() {
  log_info "Autonomous Agent Task Runner"
  log_info "Using agent: $AGENT_CLI"
  log_info "Max tasks: ${MAX_TASKS:-unlimited}"

  check_prerequisites

  cd "$PROJECT_ROOT"

  # Get open tasks
  local tasks=$(get_open_tasks)

  if [ -z "$tasks" ]; then
    log_success "No open tasks to process"
    exit 0
  fi

  log_info "Found tasks to process:"
  echo "$tasks" | while read -r line; do
    echo "  - $line"
  done
  echo ""

  # Process each task
  local processed=0
  local succeeded=0
  local failed=0

  # Save tasks to a temp file to avoid stdin interference from claude command
  local tasks_file=$(mktemp)
  echo "$tasks" > "$tasks_file"

  # Read task count for indexed loop (avoids stdin issues with claude)
  local task_count=$(wc -l < "$tasks_file" | tr -d ' ')

  for i in $(seq 1 "$task_count"); do
    local task_line=$(sed -n "${i}p" "$tasks_file")

    if [ -n "$task_line" ]; then
      processed=$((processed + 1))

      if process_task "$task_line"; then
        succeeded=$((succeeded + 1))
      else
        failed=$((failed + 1))
      fi

      # Return to base branch for next task
      git checkout "$BASE_BRANCH" 2>/dev/null || true

      echo ""
    fi
  done

  rm -f "$tasks_file"

  log_info "=========================================="
  log_info "Task processing complete"
  log_info "Processed: $processed"
  log_info "Succeeded: $succeeded"
  log_info "Failed: $failed"
  log_info "=========================================="
}

main "$@"
