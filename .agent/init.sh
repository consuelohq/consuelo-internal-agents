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
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required (install via: brew install jq / apt install jq)"; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "WARNING: GitHub CLI (gh) not installed - needed for agent workflow"; }
command -v kiro-cli >/dev/null 2>&1 || { echo "WARNING: kiro-cli not installed - needed for agent workflow"; }

echo "  - Node.js: $(node --version)"
echo "  - Yarn: $(yarn --version 2>/dev/null || echo 'not found')"
echo "  - jq: $(jq --version)"
echo ""

# Verify we're in the right directory
if [ ! -f "package.json" ]; then
  echo "ERROR: Not in project root (no package.json found)"
  exit 1
fi

# Sync with staging branch (once per session)
echo "Syncing with staging branch..."
CURRENT_BRANCH=$(git branch --show-current)

# Stash any uncommitted changes
STASH_NEEDED=false
if [ -n "$(git status --porcelain)" ]; then
  echo "  Stashing uncommitted changes..."
  git stash push -m "agent-init-auto-stash"
  STASH_NEEDED=true
fi

# Fetch and merge staging
git fetch origin staging
BEHIND=$(git rev-list HEAD..origin/staging --count 2>/dev/null || echo "0")
if [ "$BEHIND" -gt 0 ]; then
  echo "  Merging $BEHIND commits from staging..."
  git merge origin/staging --no-edit || {
    echo "ERROR: Merge conflict. Resolve manually or run: git merge --abort"
    if [ "$STASH_NEEDED" = true ]; then
      git stash pop
    fi
    exit 1
  }
  echo "  ✓ Synced with staging"
else
  echo "  ✓ Already up-to-date with staging"
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
  echo "Installing dependencies..."
  yarn install
else
  echo "Dependencies already installed"
fi

# Quick health check (if servers are running)
echo ""
echo "Health checks:"

# Check backend (twenty-server on port 3000)
if curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health 2>/dev/null | grep -q "200"; then
  echo "  - Backend (3000): HEALTHY"
else
  echo "  - Backend (3000): NOT RUNNING"
fi

# Check frontend (twenty-front on port 3001)
if curl -s -o /dev/null -w "%{http_code}" http://localhost:3001 2>/dev/null | grep -q "200"; then
  echo "  - Frontend (3001): HEALTHY"
else
  echo "  - Frontend (3001): NOT RUNNING"
fi

echo ""
echo "=== Init Complete ==="
echo ""
echo "To start dev servers, run: yarn start"
echo "To run agent workflow: .agent/run-tasks.sh --linear"
echo "To dry-run agent workflow: .agent/run-tasks.sh --linear --dry-run"
