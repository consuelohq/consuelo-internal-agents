#!/bin/bash
#
# Append research findings to current-task.md with proper structure
#
# Usage: ./append-research.sh <task_id> <task_title> [content_file]
#
# If content_file is provided, reads content from file.
# Otherwise reads from stdin.
#
# Example:
#   ./append-research.sh "abc123" "Fix login bug" findings.md
#   echo "My findings..." | ./append-research.sh "abc123" "Fix login bug"
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESEARCH_FILE="$SCRIPT_DIR/research/current-task.md"

# Parse arguments
TASK_ID="${1:-unknown}"
TASK_TITLE="${2:-Untitled Task}"
CONTENT_FILE="${3:-}"

# Get current timestamp
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DATE_SHORT=$(date -u +"%Y-%m-%d %H:%M")

# Read content
if [[ -n "$CONTENT_FILE" ]] && [[ -f "$CONTENT_FILE" ]]; then
  CONTENT=$(cat "$CONTENT_FILE")
elif [[ ! -t 0 ]]; then
  # Read from stdin
  CONTENT=$(cat)
else
  CONTENT="(No content provided)"
fi

# Create anchor-friendly ID (lowercase, dashes)
ANCHOR_ID=$(echo "$TASK_ID-${TASK_TITLE}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | head -c 60)

# Initialize research file if it doesn't exist or is empty
if [[ ! -f "$RESEARCH_FILE" ]] || [[ ! -s "$RESEARCH_FILE" ]]; then
  cat > "$RESEARCH_FILE" << 'EOF'
# Research Log

Organized research findings from agent task processing.

## Table of Contents

<!-- TOC entries will be added here -->

---

EOF
  echo "Created new research log: $RESEARCH_FILE"
fi

# Create the new entry
NEW_ENTRY="
## Task: $TASK_ID - $TASK_TITLE
**Date**: $TIMESTAMP
**Status**: In Progress

### Findings

$CONTENT

---
"

# Append entry to file
echo "$NEW_ENTRY" >> "$RESEARCH_FILE"

# Update TOC - insert new entry after "## Table of Contents" line
TOC_ENTRY="- [Task: $TASK_ID - $TASK_TITLE](#task-$ANCHOR_ID) ($DATE_SHORT)"

# Use sed to insert TOC entry (macOS compatible)
# Find the line "<!-- TOC entries will be added here -->" and insert before it
if grep -q "<!-- TOC entries" "$RESEARCH_FILE"; then
  # Insert new TOC entry before the comment marker
  sed -i '' "s|<!-- TOC entries will be added here -->|$TOC_ENTRY\n<!-- TOC entries will be added here -->|" "$RESEARCH_FILE" 2>/dev/null || \
  sed -i "s|<!-- TOC entries will be added here -->|$TOC_ENTRY\n<!-- TOC entries will be added here -->|" "$RESEARCH_FILE"
else
  # If no marker, add after "## Table of Contents"
  sed -i '' "/## Table of Contents/a\\
$TOC_ENTRY
" "$RESEARCH_FILE" 2>/dev/null || \
  sed -i "/## Table of Contents/a\\$TOC_ENTRY" "$RESEARCH_FILE"
fi

echo "Appended research for task $TASK_ID to $RESEARCH_FILE"
echo "Entry timestamp: $TIMESTAMP"
