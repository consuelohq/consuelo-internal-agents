#!/bin/bash
#
# Prune claude-progress.txt entries older than 6 hours
#
# This script preserves the file header and removes session entries
# with timestamps older than the configured threshold.
#
# Usage: ./prune-progress.sh [--dry-run]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROGRESS_FILE="$SCRIPT_DIR/claude-progress.txt"
HOURS_THRESHOLD=6

# Parse args
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
  DRY_RUN=true
fi

# Check if progress file exists
if [[ ! -f "$PROGRESS_FILE" ]]; then
  echo "Progress file not found: $PROGRESS_FILE"
  exit 0
fi

# Get current timestamp in seconds since epoch
CURRENT_TIME=$(date +%s)
THRESHOLD_SECONDS=$((HOURS_THRESHOLD * 3600))
CUTOFF_TIME=$((CURRENT_TIME - THRESHOLD_SECONDS))

# Create temp file
TEMP_FILE=$(mktemp)

# State machine for parsing
IN_HEADER=true
CURRENT_BLOCK=""
CURRENT_TIMESTAMP=""
BLOCKS_KEPT=0
BLOCKS_PRUNED=0

# Read file line by line
while IFS= read -r line || [[ -n "$line" ]]; do
  if $IN_HEADER; then
    # Header ends at "## Session History" or first "## Session 20"
    echo "$line" >> "$TEMP_FILE"
    if [[ "$line" == "## Session History" ]] || [[ "$line" == "(Most recent first)" ]]; then
      continue
    fi
    if [[ "$line" =~ ^##\ Session\ 20[0-9]{2}-[0-9]{2}-[0-9]{2} ]]; then
      IN_HEADER=false
      # Start of first session block - extract timestamp
      CURRENT_TIMESTAMP=$(echo "$line" | grep -oE '20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z?' || echo "")
      CURRENT_BLOCK="$line"
    fi
  else
    # Check if this is a new session block
    if [[ "$line" =~ ^##\ Session\ 20[0-9]{2}-[0-9]{2}-[0-9]{2} ]]; then
      # Process previous block
      if [[ -n "$CURRENT_BLOCK" ]] && [[ -n "$CURRENT_TIMESTAMP" ]]; then
        # Convert timestamp to epoch seconds
        # Handle both "2026-01-04T10:30:00Z" and "2026-01-04T10:30:00" formats
        CLEAN_TS=$(echo "$CURRENT_TIMESTAMP" | sed 's/Z$//')
        if BLOCK_TIME=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$CLEAN_TS" +%s 2>/dev/null); then
          if [[ $BLOCK_TIME -ge $CUTOFF_TIME ]]; then
            echo "$CURRENT_BLOCK" >> "$TEMP_FILE"
            ((BLOCKS_KEPT++)) || true
          else
            ((BLOCKS_PRUNED++)) || true
          fi
        else
          # If we can't parse the timestamp, keep the block
          echo "$CURRENT_BLOCK" >> "$TEMP_FILE"
          ((BLOCKS_KEPT++)) || true
        fi
      fi

      # Start new block
      CURRENT_TIMESTAMP=$(echo "$line" | grep -oE '20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z?' || echo "")
      CURRENT_BLOCK="$line"
    else
      # Continue building current block
      CURRENT_BLOCK="$CURRENT_BLOCK
$line"
    fi
  fi
done < "$PROGRESS_FILE"

# Process final block
if [[ -n "$CURRENT_BLOCK" ]] && [[ -n "$CURRENT_TIMESTAMP" ]]; then
  CLEAN_TS=$(echo "$CURRENT_TIMESTAMP" | sed 's/Z$//')
  if BLOCK_TIME=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$CLEAN_TS" +%s 2>/dev/null); then
    if [[ $BLOCK_TIME -ge $CUTOFF_TIME ]]; then
      echo "$CURRENT_BLOCK" >> "$TEMP_FILE"
      ((BLOCKS_KEPT++)) || true
    else
      ((BLOCKS_PRUNED++)) || true
    fi
  else
    echo "$CURRENT_BLOCK" >> "$TEMP_FILE"
    ((BLOCKS_KEPT++)) || true
  fi
fi

# Report
echo "Progress file pruning (threshold: ${HOURS_THRESHOLD}h):"
echo "  - Kept: $BLOCKS_KEPT entries"
echo "  - Pruned: $BLOCKS_PRUNED entries"

if $DRY_RUN; then
  echo "[DRY RUN] Would update $PROGRESS_FILE"
  rm -f "$TEMP_FILE"
else
  # Replace original file
  mv "$TEMP_FILE" "$PROGRESS_FILE"
  echo "Updated: $PROGRESS_FILE"
fi
