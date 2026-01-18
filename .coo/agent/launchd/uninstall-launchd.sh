#!/bin/bash
#
# Uninstall COO Agent launchd Jobs
#
# This script unloads and removes all COO agent scheduled tasks from launchd.
# Run this when you want to stop all scheduled COO tasks.
#
# Usage:
#   .coo/agent/launchd/uninstall-launchd.sh              # Unload and remove plists
#   .coo/agent/launchd/uninstall-launchd.sh --dry-run    # Preview without changes
#   .coo/agent/launchd/uninstall-launchd.sh --keep-files # Unload only, keep plist files
#
# After uninstalling, COO scheduled tasks will no longer run automatically.
# Re-run install-launchd.sh to restore scheduling.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
# TODO: Update this prefix to match your plist file labels
LAUNCHD_PREFIX="com.yourcompany.coo"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

# Parse command line arguments
DRY_RUN=false
KEEP_FILES=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --keep-files)
      KEEP_FILES=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Uninstall COO Agent launchd scheduled tasks."
      echo ""
      echo "Options:"
      echo "  --dry-run     Preview changes without unloading or removing files"
      echo "  --keep-files  Unload jobs but keep plist files in LaunchAgents"
      echo "  --help        Show this help message"
      echo ""
      echo "This script will:"
      echo "  1. Unload all ${LAUNCHD_PREFIX}.* launchd jobs"
      echo "  2. Remove plist files from ${LAUNCH_AGENTS_DIR}/ (unless --keep-files)"
      echo "  3. Clean up log files from /tmp/coo-agent-*.log"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      echo "Run '$0 --help' for usage"
      exit 1
      ;;
  esac
done

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

# Get list of loaded COO jobs
get_loaded_jobs() {
  launchctl list 2>/dev/null | grep "$LAUNCHD_PREFIX" | awk '{print $3}' || true
}

# Get list of COO plist files in LaunchAgents
get_plist_files() {
  ls "$LAUNCH_AGENTS_DIR"/${LAUNCHD_PREFIX}.*.plist 2>/dev/null || true
}

# Unload a single launchd job
unload_job() {
  local job_label="$1"
  local plist_path="$LAUNCH_AGENTS_DIR/${job_label}.plist"

  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY RUN] Would unload: $job_label"
    return 0
  fi

  # Try to unload using the plist file if it exists
  if [ -f "$plist_path" ]; then
    if launchctl unload "$plist_path" 2>/dev/null; then
      log_success "Unloaded: $job_label"
      return 0
    fi
  fi

  # Fall back to bootout (macOS 10.10+) if unload fails
  if launchctl bootout "gui/$(id -u)/$job_label" 2>/dev/null; then
    log_success "Unloaded (bootout): $job_label"
    return 0
  fi

  log_warning "Job not running or already unloaded: $job_label"
  return 0
}

# Remove plist file
remove_plist() {
  local plist_path="$1"
  local filename=$(basename "$plist_path")

  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY RUN] Would remove: $filename"
    return 0
  fi

  if [ -f "$plist_path" ]; then
    rm -f "$plist_path"
    log_success "Removed: $filename"
  else
    log_warning "File not found: $filename"
  fi
}

# Clean up log files
cleanup_logs() {
  local log_pattern="/tmp/coo-agent-*.log"
  local log_files=$(ls $log_pattern 2>/dev/null || true)

  if [ -z "$log_files" ]; then
    log_info "No log files to clean up"
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY RUN] Would remove log files:"
    echo "$log_files" | while read -r f; do
      echo "  - $(basename "$f")"
    done
    return 0
  fi

  rm -f $log_pattern 2>/dev/null || true
  log_success "Cleaned up log files from /tmp/"
}

main() {
  echo "=========================================="
  echo "  COO Agent launchd Uninstaller"
  echo "=========================================="
  echo ""

  if [ "$DRY_RUN" = true ]; then
    log_warning "DRY RUN MODE - No changes will be made"
    echo ""
  fi

  # Step 1: Get currently loaded jobs
  log_info "Checking for loaded COO agent jobs..."
  local loaded_jobs=$(get_loaded_jobs)

  if [ -z "$loaded_jobs" ]; then
    log_info "No COO agent jobs currently loaded"
  else
    echo ""
    log_info "Found loaded jobs:"
    echo "$loaded_jobs" | while read -r job; do
      echo "  - $job"
    done
    echo ""

    # Unload each job
    log_info "Unloading jobs..."
    echo "$loaded_jobs" | while read -r job; do
      if [ -n "$job" ]; then
        unload_job "$job"
      fi
    done
  fi

  echo ""

  # Step 2: Remove plist files (unless --keep-files)
  if [ "$KEEP_FILES" = false ]; then
    log_info "Checking for plist files in $LAUNCH_AGENTS_DIR..."
    local plist_files=$(get_plist_files)

    if [ -z "$plist_files" ]; then
      log_info "No COO plist files found"
    else
      echo ""
      log_info "Found plist files:"
      echo "$plist_files" | while read -r f; do
        echo "  - $(basename "$f")"
      done
      echo ""

      log_info "Removing plist files..."
      echo "$plist_files" | while read -r plist; do
        if [ -n "$plist" ]; then
          remove_plist "$plist"
        fi
      done
    fi
  else
    log_info "Keeping plist files (--keep-files specified)"
  fi

  echo ""

  # Step 3: Clean up log files
  log_info "Cleaning up log files..."
  cleanup_logs

  echo ""
  echo "=========================================="

  if [ "$DRY_RUN" = true ]; then
    log_warning "DRY RUN COMPLETE - No changes were made"
    echo "Run without --dry-run to apply changes"
  else
    log_success "COO Agent launchd jobs uninstalled"
    echo ""
    echo "To reinstall, run:"
    echo "  .coo/agent/launchd/install-launchd.sh"
  fi

  echo "=========================================="
}

main "$@"
