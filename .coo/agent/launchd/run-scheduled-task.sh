#!/bin/bash
# COO Agent Scheduled Task Wrapper
# This script is called by launchd plist files to run scheduled COO tasks
# It creates a Beads task and triggers the worker + QA workflow

set -e
set -o pipefail  # Capture exit codes from piped commands (not just tee)

TASK_TYPE=$1

# TODO: Update this path to your project root
PROJECT_DIR="/path/to/your/project"  # TODO: Set your project path

LOG_DIR="/tmp/coo-agent"
DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S%z)

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Log function
log() {
    echo "[$TIMESTAMP] $1" >> "$LOG_DIR/scheduler.log"
    echo "[$TIMESTAMP] $1"
}

log "Starting scheduled task: $TASK_TYPE"

# Validate PROJECT_DIR is set
if [ "$PROJECT_DIR" = "/path/to/your/project" ] || [ -z "$PROJECT_DIR" ]; then
    log "ERROR: PROJECT_DIR not configured in run-scheduled-task.sh"
    log "Edit this file and set PROJECT_DIR to your project path"
    exit 1
fi

# Change to project directory
cd "$PROJECT_DIR"

# Load environment variables if .env exists
if [ -f ".coo/.env" ]; then
    source ".coo/.env"
fi

# Alias for bd-coo (using separate Beads instance)
BD_COO="bd --config $PROJECT_DIR/.coo/.beads/config.yaml"

# Map task type to Beads task creation
case $TASK_TYPE in
    "morning-research")
        log "Creating morning research task"
        $BD_COO create "[RESEARCH]: Research 100 prospects - $DATE" \
            --description "Research and enrich prospects using Clay, Apollo, YouSearch. Output to staging directory." \
            2>&1 | tee -a "$LOG_DIR/scheduler.log"
        ;;

    "generate-emails")
        log "Creating email generation task"
        $BD_COO create "[OUTREACH]: Generate daily emails - $DATE" \
            --description "Generate personalized cold emails based on warm-up day. Do NOT send - QA session will validate and send." \
            2>&1 | tee -a "$LOG_DIR/scheduler.log"
        ;;

    "twitter-post-1")
        log "Creating Twitter morning post task"
        $BD_COO create "[CONTENT]: Twitter morning post - $DATE" \
            --description "Create morning Twitter post (8 AM slot). Focus on industry insights." \
            2>&1 | tee -a "$LOG_DIR/scheduler.log"
        ;;

    "twitter-post-2")
        log "Creating Twitter midday post task"
        $BD_COO create "[CONTENT]: Twitter midday post - $DATE" \
            --description "Create midday Twitter post (12 PM slot). Focus on product value or customer success." \
            2>&1 | tee -a "$LOG_DIR/scheduler.log"
        ;;

    "twitter-post-3")
        log "Creating Twitter evening post task"
        $BD_COO create "[CONTENT]: Twitter evening post - $DATE" \
            --description "Create evening Twitter post (5 PM slot). Focus on community engagement or thought leadership." \
            2>&1 | tee -a "$LOG_DIR/scheduler.log"
        ;;

    "twitter-thread")
        log "Creating Twitter thread task"
        $BD_COO create "[CONTENT]: Twitter thread - $DATE" \
            --description "Create Twitter thread (Tuesday/Thursday). Deep dive on industry topic." \
            2>&1 | tee -a "$LOG_DIR/scheduler.log"
        ;;

    "instagram-prospects")
        log "Creating Instagram prospects task"
        $BD_COO create "[RESEARCH]: Instagram prospect list - $DATE" \
            --description "Generate list of Instagram accounts to engage with for DM outreach. Include company context." \
            2>&1 | tee -a "$LOG_DIR/scheduler.log"
        ;;

    "dialer-leads")
        log "Creating dialer leads task"
        $BD_COO create "[RESEARCH]: Dialer leads CSV - $DATE" \
            --description "Generate CSV of leads with valid phone numbers for dialer system. Format: name, phone, company, source." \
            2>&1 | tee -a "$LOG_DIR/scheduler.log"
        ;;

    "update-metrics")
        log "Creating metrics update task"
        $BD_COO create "[METRICS]: Update daily metrics - $DATE" \
            --description "Update Google Sheets with daily engagement metrics: emails sent, opens, clicks, Twitter engagement, leads." \
            2>&1 | tee -a "$LOG_DIR/scheduler.log"
        ;;

    *)
        log "ERROR: Unknown task type: $TASK_TYPE"
        exit 1
        ;;
esac

# Run the worker session (generates outputs to staging)
log "Running worker session for $TASK_TYPE"
WORKER_STATUS=0
if [ -f "$PROJECT_DIR/.coo/agent/run-tasks.sh" ]; then
    # Disable errexit temporarily to capture exit code from pipeline
    set +e
    "$PROJECT_DIR/.coo/agent/run-tasks.sh" --single-task 2>&1 | tee -a "$LOG_DIR/$TASK_TYPE-worker.log"
    WORKER_STATUS=${PIPESTATUS[0]}  # Capture script's exit code, not tee's
    set -e

    if [ $WORKER_STATUS -ne 0 ]; then
        log "WARNING: Worker session failed with exit code $WORKER_STATUS"
    else
        log "Worker session completed successfully"
    fi
else
    log "WARNING: run-tasks.sh not found, skipping worker session"
fi

# Run the QA session (validates and sends/pushes if valid)
log "Running QA session for $TASK_TYPE"
QA_STATUS=0
if [ -f "$PROJECT_DIR/.coo/agent/run-qa.sh" ]; then
    # Disable errexit temporarily to capture exit code from pipeline
    set +e
    "$PROJECT_DIR/.coo/agent/run-qa.sh" 2>&1 | tee -a "$LOG_DIR/$TASK_TYPE-qa.log"
    QA_STATUS=${PIPESTATUS[0]}  # Capture script's exit code, not tee's
    set -e

    if [ $QA_STATUS -ne 0 ]; then
        log "ERROR: QA session failed with exit code $QA_STATUS"
    else
        log "QA session completed successfully"
    fi
else
    log "WARNING: run-qa.sh not found, skipping QA session"
fi

# Final status
if [ $WORKER_STATUS -ne 0 ] || [ $QA_STATUS -ne 0 ]; then
    log "FAILED: Scheduled task $TASK_TYPE completed with errors (worker=$WORKER_STATUS, qa=$QA_STATUS)"
    exit 1
else
    log "SUCCESS: Completed scheduled task: $TASK_TYPE"
fi
