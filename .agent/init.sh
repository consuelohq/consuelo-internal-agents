#!/bin/bash
# Initialize development environment for agent sessions
# Run this at the start of each coding session

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Consuelo Agent Init ==="
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
command -v gh >/dev/null 2>&1 || { echo "WARNING: GitHub CLI (gh) not installed - needed for agent workflow"; }

echo "  - Node.js: $(node --version)"
echo "  - Python: $(python3 --version)"
echo "  - npm: $(npm --version)"
echo "  - jq: $(jq --version)"
echo ""

# Verify we're in the right directory
if [ ! -f "package.json" ]; then
  echo "ERROR: Not in project root (no package.json found)"
  exit 1
fi

# Sync with claudeee branch (once per session)
echo "Syncing with claudeee branch..."
CURRENT_BRANCH=$(git branch --show-current)

# Stash any uncommitted changes
STASH_NEEDED=false
if [ -n "$(git status --porcelain)" ]; then
  echo "  Stashing uncommitted changes..."
  git stash push -m "agent-init-auto-stash"
  STASH_NEEDED=true
fi

# Fetch and merge claudeee
git fetch origin claudeee
BEHIND=$(git rev-list HEAD..origin/claudeee --count 2>/dev/null || echo "0")
if [ "$BEHIND" -gt 0 ]; then
  echo "  Merging $BEHIND commits from claudeee..."
  git merge origin/claudeee --no-edit || {
    echo "ERROR: Merge conflict. Resolve manually or run: git merge --abort"
    if [ "$STASH_NEEDED" = true ]; then
      git stash pop
    fi
    exit 1
  }
  echo "  ✓ Synced with claudeee"
else
  echo "  ✓ Already up-to-date with claudeee"
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
if [ ! -d "node_modules" ]; then
  echo "Installing npm dependencies..."
  npm install
else
  echo "npm dependencies already installed"
fi

# Check Python virtual environment
if [ -d "venv" ]; then
  echo "Python venv exists"
else
  echo "No Python venv found (will use system Python)"
fi

# Quick health check (if servers are running)
echo ""
echo "Health checks:"

# Check backend
if curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/health 2>/dev/null | grep -q "200"; then
  echo "  - Backend (5000): HEALTHY"
else
  echo "  - Backend (5000): NOT RUNNING"
fi

# Check frontend
if curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null | grep -q "200"; then
  echo "  - Frontend (3000): HEALTHY"
else
  echo "  - Frontend (3000): NOT RUNNING"
fi

echo ""
echo "=== Init Complete ==="
echo ""
echo "To start dev servers, run: npm start"
echo "To create an agent task: gh issue create --label agent-ready --title \"Task description\""
echo "To list agent tasks: gh issue list --label agent-ready"
echo "To run agent workflow: .agent/run-tasks.sh"
