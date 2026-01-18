#!/bin/bash
# Install COO Agent launchd scheduled tasks
# This script copies plist files to ~/Library/LaunchAgents and loads them
#
# Usage:
#   ./install-launchd.sh              # Install and load all plist files
#   ./install-launchd.sh --dry-run    # Preview what would be done
#   ./install-launchd.sh --force      # Force reload even if already loaded
#
# Requirements:
#   - macOS (launchd is macOS-specific)
#   - plist files in .coo/agent/launchd/*.plist

set -e

# Script directory (where plist files are stored)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Configuration
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
# TODO: Update this prefix to match your plist file labels
PLIST_PREFIX="com.yourcompany.coo"

# Parse arguments
DRY_RUN=false
FORCE=false

for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            ;;
        --force)
            FORCE=true
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run    Preview what would be done without making changes"
            echo "  --force      Force reload even if jobs are already loaded"
            echo "  --help, -h   Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown argument: $arg"
            exit 1
            ;;
    esac
done

# Header
echo "=== COO Agent launchd Installer ==="
echo "Started at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

if [ "$DRY_RUN" = true ]; then
    log_warning "DRY RUN MODE - No changes will be made"
    echo ""
fi

# Check we're on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    log_error "This script requires macOS (launchd is macOS-specific)"
    exit 1
fi

# Check launchctl is available
if ! command -v launchctl &> /dev/null; then
    log_error "launchctl command not found (should be present on macOS)"
    exit 1
fi

log_success "Platform check passed: macOS detected"

# Create LaunchAgents directory if it doesn't exist
if [ ! -d "$LAUNCH_AGENTS_DIR" ]; then
    log_info "Creating $LAUNCH_AGENTS_DIR directory..."
    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$LAUNCH_AGENTS_DIR"
    fi
fi

# Find plist files
PLIST_FILES=("$SCRIPT_DIR"/*.plist)

# Check if any plist files exist
if [ ! -e "${PLIST_FILES[0]}" ]; then
    log_warning "No .plist files found in $SCRIPT_DIR"
    log_info "Expected plist files like:"
    log_info "  - $PLIST_PREFIX.morning-research.plist"
    log_info "  - $PLIST_PREFIX.generate-emails.plist"
    log_info "  - $PLIST_PREFIX.twitter-post-1.plist"
    log_info ""
    log_info "Create plist files from the templates in this directory."
    exit 1
fi

# Count files
PLIST_COUNT=$(ls -1 "$SCRIPT_DIR"/*.plist 2>/dev/null | wc -l | tr -d ' ')
log_info "Found $PLIST_COUNT plist file(s) to install"
echo ""

# Track results
INSTALLED=0
SKIPPED=0
FAILED=0

# Copy and load each plist file
for plist_file in "$SCRIPT_DIR"/*.plist; do
    [ -e "$plist_file" ] || continue

    filename=$(basename "$plist_file")
    label="${filename%.plist}"
    dest_file="$LAUNCH_AGENTS_DIR/$filename"

    echo "----------------------------------------"
    log_info "Processing: $filename"

    # Check if already loaded
    if launchctl list | grep -q "$label" 2>/dev/null; then
        if [ "$FORCE" = true ]; then
            log_info "  Job already loaded, unloading first (--force)..."
            if [ "$DRY_RUN" = false ]; then
                launchctl unload "$dest_file" 2>/dev/null || true
            fi
        else
            log_warning "  Job already loaded. Use --force to reload."
            ((SKIPPED++))
            continue
        fi
    fi

    # Copy plist file
    log_info "  Copying to $dest_file..."
    if [ "$DRY_RUN" = false ]; then
        cp "$plist_file" "$dest_file"

        # Ensure correct permissions (owner read/write, group/other read)
        chmod 644 "$dest_file"
    fi

    # Load the job
    log_info "  Loading job..."
    if [ "$DRY_RUN" = false ]; then
        if launchctl load "$dest_file" 2>&1; then
            log_success "  Loaded: $label"
            ((INSTALLED++))
        else
            log_error "  Failed to load: $label"
            ((FAILED++))
        fi
    else
        log_info "  Would load: $label"
        ((INSTALLED++))
    fi
done

echo ""
echo "=========================================="
echo ""

# Summary
log_info "Installation Summary:"
echo "  - Installed/Loaded: $INSTALLED"
echo "  - Skipped (already loaded): $SKIPPED"
echo "  - Failed: $FAILED"
echo ""

# Verify installation
if [ "$DRY_RUN" = false ] && [ $INSTALLED -gt 0 ]; then
    log_info "Verifying installed jobs..."
    echo ""

    LOADED_JOBS=$(launchctl list 2>/dev/null | grep "$PLIST_PREFIX" || echo "")

    if [ -n "$LOADED_JOBS" ]; then
        log_success "Loaded COO Agent jobs:"
        echo "$LOADED_JOBS" | while read -r line; do
            echo "  $line"
        done
        echo ""
    else
        log_warning "No COO Agent jobs found in launchctl list"
    fi
fi

# Exit status
if [ $FAILED -gt 0 ]; then
    log_error "Installation completed with errors"
    exit 1
elif [ "$DRY_RUN" = true ]; then
    log_success "Dry run completed - no changes made"
    exit 0
else
    log_success "Installation completed successfully!"
    echo ""
    log_info "To check job status: launchctl list | grep $PLIST_PREFIX"
    log_info "To view logs: tail -f /tmp/coo-agent/*.log"
    log_info "To uninstall: .coo/agent/launchd/uninstall-launchd.sh"
    exit 0
fi
