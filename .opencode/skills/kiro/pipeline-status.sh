#!/bin/bash
# Pipeline Status — quick health check for the kiro automation pipeline
# Usage: ./pipeline-status.sh [--json]

set -uo pipefail
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/linear-api-kiro.sh"

JSON_MODE=false
[[ "${1:-}" == "--json" ]] && JSON_MODE=true

# Colors (skip in json mode)
if ! $JSON_MODE; then
    GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
fi

# --- Gather data ---

# 1. Active kiro-cli processes
KIRO_CHAT=$(pgrep -f "kiro-cli chat" 2>/dev/null | wc -l | tr -d ' ')
KIRO_ACP=$(pgrep -f "kiro-cli acp" 2>/dev/null | wc -l | tr -d ' ')
KIRO_PROCS=$((KIRO_CHAT + KIRO_ACP))

# 2. Linear queue
QUEUE_JSON=$(linear_get_kiro_issues 2>/dev/null || echo "")
QUEUE_COUNT=$(echo "$QUEUE_JSON" | grep -c '^{' 2>/dev/null || echo "0")

# 3. Open kiro PRs
KIRO_PRS=$(GH_TOKEN="${GH_TOKEN:-}" /opt/homebrew/bin/gh pr list --repo "$GITHUB_REPO" --label kiro --json number,title,state,url,createdAt 2>/dev/null || echo "[]")
PR_COUNT=$(echo "$KIRO_PRS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

# 4. Last cron run
LAST_RUN=$(grep "Last run:" /tmp/specs-watcher.log 2>/dev/null | tail -1 | sed 's/.*Last run: //' || echo "never")

# 5. Last processed task
LAST_TASK=$(grep "Processing DEV-" /tmp/specs-watcher.log 2>/dev/null | tail -1 | sed 's/.*Processing //' || echo "none")

# 6. Deploy failures pending
FAIL_DIR="$(dirname "$0")/deploy-failures"
DEPLOY_FAILS=$(find "$FAIL_DIR" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')

# 7. Cron status
CRON_LINE=$(crontab -l 2>/dev/null | grep specs-watcher || echo "")
CRON_ACTIVE=$([[ -n "$CRON_LINE" ]] && echo "true" || echo "false")
CRON_INTERVAL=$(echo "$CRON_LINE" | grep -o '^[^ ]*' || echo "n/a")

if $JSON_MODE; then
    # Build task list with linear links
    TASKS_JSON=$(echo "$QUEUE_JSON" | python3 -c "
import sys, json
out = []
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        t = json.loads(line)
        out.append({
            'id': t.get('identifier', ''),
            'title': t.get('title', ''),
            'url': 'https://linear.app/issue/' + t.get('identifier', ''),
            'state': 'Open'
        })
    except: pass
print(json.dumps(out))
" 2>/dev/null || echo "[]")

    cat <<EOF
{
  "kiro_agents_running": $KIRO_PROCS,
  "queue_size": $QUEUE_COUNT,
  "open_prs": $PR_COUNT,
  "deploy_failures_pending": $DEPLOY_FAILS,
  "cron_active": $CRON_ACTIVE,
  "cron_interval": "$CRON_INTERVAL",
  "last_cron_run": "$LAST_RUN",
  "last_task": "$LAST_TASK",
  "tasks": $TASKS_JSON,
  "prs": $KIRO_PRS
}
EOF
else
    echo ""
    echo -e "${BLUE}═══ Kiro Pipeline Status ═══${NC}"
    echo ""
    echo -e "  🤖 Kiro agents running:  ${GREEN}${KIRO_PROCS}${NC}"
    echo -e "  📋 Tasks in queue:       ${YELLOW}${QUEUE_COUNT}${NC}"
    echo -e "  🔀 Open kiro PRs:        ${YELLOW}${PR_COUNT}${NC}"
    echo -e "  💥 Deploy failures:      $([[ $DEPLOY_FAILS -gt 0 ]] && echo -e "${RED}${DEPLOY_FAILS}" || echo -e "${GREEN}${DEPLOY_FAILS}")${NC}"
    echo -e "  ⏰ Cron active:          $($CRON_ACTIVE && echo -e "${GREEN}yes ($CRON_INTERVAL)" || echo -e "${RED}no")${NC}"
    echo -e "  🕐 Last cron run:        ${LAST_RUN}"
    echo -e "  📝 Last task:            ${LAST_TASK}"
    echo ""

    if [[ $QUEUE_COUNT -gt 0 ]]; then
        echo -e "${BLUE}── Queue ──${NC}"
        echo "$QUEUE_JSON" | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        t = json.loads(line)
        ident = t.get('identifier', '?')
        title = t.get('title', '')[:60]
        print(f'  {ident}: {title}')
    except: pass
" 2>/dev/null
        echo ""
    fi

    if [[ $PR_COUNT -gt 0 ]]; then
        echo -e "${BLUE}── Open PRs ──${NC}"
        echo "$KIRO_PRS" | python3 -c "
import sys, json
prs = json.load(sys.stdin)
for p in prs:
    print(f'  #{p[\"number\"]}: {p[\"title\"][:60]}')
    print(f'         {p[\"url\"]}')
" 2>/dev/null
        echo ""
    fi
fi
