#!/bin/bash
# Initialize development environment for agent sessions
# Run this at the start of each coding session

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load config
if [ -f "$SCRIPT_DIR/config.sh" ]; then
  source "$SCRIPT_DIR/config.sh"
else
  BASE_BRANCH="main"
fi

echo "=== Agent Workflow Init ==="
echo "Starting at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# Prune old progress entries (> 6 hours)
if [ -f "$SCRIPT_DIR/prune-progress.sh" ]; then
  echo "Pruning old progress entries..."
  bash "$SCRIPT_DIR/prune-progress.sh"
  echo ""
fi

# Check required tools
echo "Checking required tools..."
command -v node >/dev/null 2>&1 || { echo "ERROR: Node.js required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: Python3 required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required (install via: brew install jq / apt install jq)"; exit 1; }
command -v bd >/dev/null 2>&1 || { echo "WARNING: Beads (bd) not installed"; }

echo "  - Node.js: $(node --version)"
echo "  - Python: $(python3 --version)"
echo "  - npm: $(npm --version 2>/dev/null || echo 'N/A')"
echo "  - jq: $(jq --version)"
echo ""

# Verify we're in the right directory
if [ ! -f "$PROJECT_ROOT/package.json" ] && [ ! -f "$PROJECT_ROOT/setup.py" ] && [ ! -f "$PROJECT_ROOT/Makefile" ]; then
  echo "WARNING: No package.json, setup.py, or Makefile found in project root"
fi

# Sync with base branch (once per session)
echo "Syncing with $BASE_BRANCH branch..."
CURRENT_BRANCH=$(git branch --show-current)

# Stash any uncommitted changes
STASH_NEEDED=false
if [ -n "$(git status --porcelain)" ]; then
  echo "  Stashing uncommitted changes..."
  git stash push -m "agent-init-auto-stash"
  STASH_NEEDED=true
fi

# Fetch and merge base branch
git fetch origin "$BASE_BRANCH" 2>/dev/null || {
  echo "  WARNING: Could not fetch origin/$BASE_BRANCH"
}

BEHIND=$(git rev-list HEAD..origin/"$BASE_BRANCH" --count 2>/dev/null || echo "0")
if [ "$BEHIND" -gt 0 ]; then
  echo "  Merging $BEHIND commits from $BASE_BRANCH..."
  git merge origin/"$BASE_BRANCH" --no-edit || {
    echo "ERROR: Merge conflict. Resolve manually or run: git merge --abort"
    if [ "$STASH_NEEDED" = true ]; then
      git stash pop
    fi
    exit 1
  }
  echo "  ✓ Synced with $BASE_BRANCH"
else
  echo "  ✓ Already up-to-date with $BASE_BRANCH"
fi

# Restore stashed changes
if [ "$STASH_NEEDED" = true ]; then
  echo "  Restoring stashed changes..."
  git stash pop || echo "  WARNING: Could not restore stash (may have conflicts)"
fi
echo ""

# Check for uncommitted changes
echo "Git status:"
git status --short
echo ""

# Show recent commits
echo "Recent commits:"
git log --oneline -5
echo ""

# Check dependencies
if [ -f "$PROJECT_ROOT/package.json" ]; then
  if [ ! -d "$PROJECT_ROOT/node_modules" ]; then
    echo "Installing npm dependencies..."
    cd "$PROJECT_ROOT" && npm install
  else
    echo "npm dependencies already installed"
  fi
fi

# Check Python virtual environment
if [ -d "$PROJECT_ROOT/venv" ]; then
  echo "Python venv exists"
elif [ -f "$PROJECT_ROOT/requirements.txt" ]; then
  echo "No Python venv found (consider: python3 -m venv venv)"
fi

# Quick health checks
# TODO: Customize these for your project
echo ""
echo "Health checks:"

# Check if backend is running (common ports)
BACKEND_RUNNING=false
for PORT in 5000 8000 3001 8080; do
  if curl -s --max-time 2 -o /dev/null -w "%{http_code}" "http://localhost:$PORT/health" 2>/dev/null | grep -q "200"; then
    echo "  - Backend ($PORT): HEALTHY"
    BACKEND_RUNNING=true
    break
  elif curl -s --max-time 2 -o /dev/null -w "%{http_code}" "http://localhost:$PORT" 2>/dev/null | grep -q "200\|301\|302"; then
    echo "  - Backend ($PORT): RUNNING"
    BACKEND_RUNNING=true
    break
  fi
done

if [ "$BACKEND_RUNNING" = false ]; then
  echo "  - Backend: NOT RUNNING"
fi

# Check if frontend is running
if curl -s --max-time 2 -o /dev/null -w "%{http_code}" "http://localhost:3000" 2>/dev/null | grep -q "200\|301\|302"; then
  echo "  - Frontend (3000): RUNNING"
else
  echo "  - Frontend (3000): NOT RUNNING"
fi

echo ""
echo "=== Init Complete ==="
echo ""

# TODO: Update these help messages for your project
echo "To start dev servers, run: npm start"
echo "To add a task: bd create \"Task description\""
echo "To list tasks: bd list"
