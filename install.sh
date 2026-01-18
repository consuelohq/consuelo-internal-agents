#!/bin/bash
#
# Claude Agent Workflow Installer
#
# This script sets up the autonomous agent workflow in your project.
# It checks prerequisites, creates directories, and configures hooks.
#
# Usage:
#   ./install.sh                  # Interactive setup
#   ./install.sh --non-interactive # Use defaults
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory (where template files are)
TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Target directory (current working directory)
TARGET_DIR="$(pwd)"

# Parse arguments
INTERACTIVE=true
while [[ $# -gt 0 ]]; do
  case $1 in
    --non-interactive)
      INTERACTIVE=false
      shift
      ;;
    --help|-h)
      echo "Claude Agent Workflow Installer"
      echo ""
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --non-interactive  Use default values without prompting"
      echo "  --help, -h         Show this help message"
      echo ""
      echo "This script will set up the agent workflow in the current directory."
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

prompt_with_default() {
  local prompt="$1"
  local default="$2"
  local result=""

  if [ "$INTERACTIVE" = true ]; then
    read -p "$prompt [$default]: " result
    result="${result:-$default}"
  else
    result="$default"
  fi

  echo "$result"
}

# Header
echo ""
echo "========================================"
echo "  Claude Agent Workflow Installer"
echo "========================================"
echo ""

# Check if we're in a git repository
if [ ! -d "$TARGET_DIR/.git" ]; then
  log_error "Not in a git repository. Please run from your project root."
  exit 1
fi

log_success "Git repository detected"

# Check prerequisites
log_info "Checking prerequisites..."
MISSING_DEPS=""

# Node.js
if command -v node &> /dev/null; then
  log_success "Node.js: $(node --version)"
else
  MISSING_DEPS="$MISSING_DEPS node"
  log_warning "Node.js: NOT FOUND"
fi

# Python
if command -v python3 &> /dev/null; then
  log_success "Python: $(python3 --version)"
else
  MISSING_DEPS="$MISSING_DEPS python3"
  log_warning "Python: NOT FOUND"
fi

# jq
if command -v jq &> /dev/null; then
  log_success "jq: $(jq --version)"
else
  MISSING_DEPS="$MISSING_DEPS jq"
  log_warning "jq: NOT FOUND (install with: brew install jq)"
fi

# GitHub CLI
if command -v gh &> /dev/null; then
  log_success "GitHub CLI: $(gh --version | head -1)"
else
  MISSING_DEPS="$MISSING_DEPS gh"
  log_warning "GitHub CLI: NOT FOUND (install from: https://cli.github.com)"
fi

# Claude Code or OpenCode
AGENT_CLI="claude"
if command -v claude &> /dev/null; then
  log_success "Claude Code: installed"
elif command -v opencode &> /dev/null; then
  AGENT_CLI="opencode"
  log_success "OpenCode: installed"
else
  MISSING_DEPS="$MISSING_DEPS claude/opencode"
  log_warning "Claude Code / OpenCode: NOT FOUND"
fi

# Beads
if command -v bd &> /dev/null; then
  log_success "Beads: installed"
else
  MISSING_DEPS="$MISSING_DEPS beads"
  log_warning "Beads: NOT FOUND (install from: https://github.com/steveyegge/beads)"
fi

echo ""

# Warn about missing dependencies
if [ -n "$MISSING_DEPS" ]; then
  log_warning "Missing dependencies:$MISSING_DEPS"
  echo ""
  if [ "$INTERACTIVE" = true ]; then
    read -p "Continue anyway? (y/N): " CONTINUE
    if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
      log_info "Installation cancelled. Install dependencies and try again."
      exit 1
    fi
  else
    log_info "Continuing with missing dependencies (--non-interactive mode)"
  fi
fi

# Gather configuration
echo ""
log_info "Configuration"
echo "-------------"

# Base branch
DEFAULT_BRANCH=$(git branch --show-current)
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH="main"
fi
BASE_BRANCH=$(prompt_with_default "Base branch for PRs" "$DEFAULT_BRANCH")

# Test command
DEFAULT_TEST="npm test"
if [ -f "package.json" ] && grep -q "\"test\"" package.json; then
  DEFAULT_TEST="npm test"
elif [ -f "pytest.ini" ] || [ -f "setup.py" ]; then
  DEFAULT_TEST="pytest"
elif [ -f "Makefile" ] && grep -q "^test:" Makefile; then
  DEFAULT_TEST="make test"
fi
TEST_COMMAND=$(prompt_with_default "Test command" "$DEFAULT_TEST")

# Slack webhook (optional)
SLACK_WEBHOOK=""
if [ "$INTERACTIVE" = true ]; then
  read -p "Slack webhook URL (optional, press Enter to skip): " SLACK_WEBHOOK
fi

echo ""
log_info "Installing agent workflow..."

# Create .agent directory
log_info "Creating .agent/ directory..."
mkdir -p "$TARGET_DIR/.agent/research"

# Copy agent scripts
if [ -d "$TEMPLATE_DIR/.agent" ]; then
  cp "$TEMPLATE_DIR/.agent/init.sh" "$TARGET_DIR/.agent/" 2>/dev/null || true
  cp "$TEMPLATE_DIR/.agent/run-tasks.sh" "$TARGET_DIR/.agent/" 2>/dev/null || true
  cp "$TEMPLATE_DIR/.agent/append-research.sh" "$TARGET_DIR/.agent/" 2>/dev/null || true
  cp "$TEMPLATE_DIR/.agent/label-pr.sh" "$TARGET_DIR/.agent/" 2>/dev/null || true
  cp "$TEMPLATE_DIR/.agent/notify.sh" "$TARGET_DIR/.agent/" 2>/dev/null || true
  cp "$TEMPLATE_DIR/.agent/prune-progress.sh" "$TARGET_DIR/.agent/" 2>/dev/null || true
  cp "$TEMPLATE_DIR/.agent/human.md" "$TARGET_DIR/.agent/" 2>/dev/null || true
fi

# Create config.sh with user values
cat > "$TARGET_DIR/.agent/config.sh" << EOF
#!/bin/bash
#
# Agent Configuration
#
# Edit this file to customize the agent workflow for your project.
#

# =============================================================================
# AGENT CLI SELECTION
# =============================================================================

# Choose your agent CLI: "claude" or "opencode"
AGENT_CLI="$AGENT_CLI"

# CLI invocation patterns
CLAUDE_CMD="claude --print"
OPENCODE_CMD="opencode"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

get_agent_cmd() {
  if [ "\$AGENT_CLI" = "claude" ]; then
    echo "\$CLAUDE_CMD"
  else
    echo "\$OPENCODE_CMD"
  fi
}

# =============================================================================
# TASK PROCESSING SETTINGS
# =============================================================================

# Maximum retries for failed tasks before flagging for review
MAX_RETRIES=1

# Timeout for agent execution (in seconds, 0 = no timeout)
AGENT_TIMEOUT=0

# Whether to run tests after each task (true/false)
RUN_TESTS_AFTER_TASK=true

# Which tests to run for validation
# TODO: Update this for your project's test command
TEST_COMMAND="$TEST_COMMAND"

# =============================================================================
# GIT SETTINGS
# =============================================================================

# Base branch for agent work (PRs target this branch)
BASE_BRANCH="$BASE_BRANCH"

# Branch prefix for agent-created branches
BRANCH_PREFIX="agent"

# =============================================================================
# NOTIFICATION SETTINGS
# =============================================================================

# Slack webhook for notifications
# Set via environment variable in ~/.zshrc:
#   export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T.../B.../..."
SLACK_WEBHOOK_URL="\${SLACK_WEBHOOK_URL:-$SLACK_WEBHOOK}"
EOF

log_success "Created .agent/config.sh"

# Create empty progress file
touch "$TARGET_DIR/.agent/claude-progress.txt"

# Create empty research template
cat > "$TARGET_DIR/.agent/research/current-task.md" << 'EOF'
# Research Log

Organized research findings from agent task processing.

## Table of Contents

<!-- TOC entries will be added here -->

---
EOF

log_success "Created .agent/ directory with scripts"

# Create .claude/hooks directories
log_info "Creating .claude/hooks/ directory..."
mkdir -p "$TARGET_DIR/.claude/hooks/pre-tool-use"
mkdir -p "$TARGET_DIR/.claude/hooks/post-tool-use"
mkdir -p "$TARGET_DIR/.claude/hooks/session-end"
mkdir -p "$TARGET_DIR/.claude/hooks/stop"

# Copy hook scripts
if [ -d "$TEMPLATE_DIR/.claude" ]; then
  cp "$TEMPLATE_DIR/.claude/hooks/pre-tool-use/"*.sh "$TARGET_DIR/.claude/hooks/pre-tool-use/" 2>/dev/null || true
  cp "$TEMPLATE_DIR/.claude/hooks/post-tool-use/"*.sh "$TARGET_DIR/.claude/hooks/post-tool-use/" 2>/dev/null || true
  cp "$TEMPLATE_DIR/.claude/hooks/session-end/"*.sh "$TARGET_DIR/.claude/hooks/session-end/" 2>/dev/null || true
  cp "$TEMPLATE_DIR/.claude/hooks/stop/"*.sh "$TARGET_DIR/.claude/hooks/stop/" 2>/dev/null || true
fi

log_success "Created .claude/hooks/ with quality gate scripts"

# Make scripts executable
log_info "Setting executable permissions..."
find "$TARGET_DIR/.agent" -name "*.sh" -exec chmod +x {} \;
find "$TARGET_DIR/.claude/hooks" -name "*.sh" -exec chmod +x {} \;
log_success "Scripts are now executable"

# Initialize Beads if available
if command -v bd &> /dev/null; then
  if [ ! -d "$TARGET_DIR/.beads" ]; then
    log_info "Initializing Beads task queue..."
    cd "$TARGET_DIR" && bd init 2>/dev/null || log_warning "Beads init failed (may already be initialized)"
  fi
  log_success "Beads task queue ready"
fi

# Update .gitignore
log_info "Updating .gitignore..."
GITIGNORE="$TARGET_DIR/.gitignore"

# Entries to add
IGNORE_ENTRIES=(
  "# Agent workflow files"
  ".agent/claude-progress.txt"
  ".agent/metrics.json"
  ".agent/research/*.md"
  "!.agent/research/.gitkeep"
  ".agent/.sentry-imported-ids"
  ".claude/hooks/loop-state.json"
)

# Create .gitignore if it doesn't exist
touch "$GITIGNORE"

# Add entries if not already present
for entry in "${IGNORE_ENTRIES[@]}"; do
  if ! grep -qxF "$entry" "$GITIGNORE" 2>/dev/null; then
    echo "$entry" >> "$GITIGNORE"
  fi
done

# Create .gitkeep to preserve research directory
touch "$TARGET_DIR/.agent/research/.gitkeep"

log_success "Updated .gitignore"

# Summary
echo ""
echo "========================================"
echo "  Installation Complete!"
echo "========================================"
echo ""
log_success "Agent workflow installed successfully"
echo ""
echo "Configuration:"
echo "  Base branch: $BASE_BRANCH"
echo "  Test command: $TEST_COMMAND"
echo "  Agent CLI: $AGENT_CLI"
if [ -n "$SLACK_WEBHOOK" ]; then
  echo "  Slack: Configured"
else
  echo "  Slack: Not configured (optional)"
fi
echo ""
echo "Next steps:"
echo "  1. Review and customize .agent/config.sh"
echo "  2. Customize .claude/hooks/pre-tool-use/code-rules.sh for your project"
echo "  3. Run .agent/init.sh to verify the setup"
echo "  4. Create your first task: bd create \"Test task\""
echo "  5. Run the agent: .agent/run-tasks.sh --max-tasks 1"
echo ""
echo "For help, see: .agent/human.md or README.md"
echo ""
