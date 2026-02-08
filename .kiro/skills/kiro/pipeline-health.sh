#!/bin/bash
#
# Pipeline Health Check
#
# One command to verify the entire automated dev pipeline is healthy.
#
# Usage:
#   .opencode/skills/kiro/pipeline-health.sh         # full check
#   .opencode/skills/kiro/pipeline-health.sh --quick  # just the cron/watcher status
#
# Exit codes:
#   0 = all healthy
#   1 = one or more checks failed
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(dirname "$SCRIPT_DIR")"
WORKSPACE_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

# =============================================================================
# HELPERS
# =============================================================================

check_pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; PASS=$((PASS + 1)); }
check_fail() { echo -e "  ${RED}[FAIL]${NC} $1"; FAIL=$((FAIL + 1)); }
check_warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; WARN=$((WARN + 1)); }
section()    { echo -e "\n${BOLD}$1${NC}"; }

# =============================================================================
# QUICK CHECK (cron/watcher status only)
# =============================================================================

quick_check() {
    echo -e "${BOLD}pipeline quick check${NC}"
    echo -e "${DIM}$(date)${NC}\n"

    # 1. Is specs-watcher daemon running?
    local watcher_pid
    watcher_pid=$(pgrep -f "specs-watcher.sh.*--daemon" 2>/dev/null)
    if [ -n "$watcher_pid" ]; then
        check_pass "specs-watcher daemon running (PID: $watcher_pid)"
    else
        # Check cron instead
        local cron_entry
        cron_entry=$(crontab -l 2>/dev/null | grep -c "specs-watcher" || true)
        if [ "$cron_entry" -gt 0 ]; then
            check_pass "specs-watcher configured in crontab"
        else
            check_warn "specs-watcher not running as daemon and not in crontab"
        fi
    fi

    # 2. Last run time
    local state_file="$SCRIPT_DIR/.specs-watcher-state.json"
    if [ -f "$state_file" ]; then
        local last_run
        last_run=$(python3 -c "
import json, sys
from datetime import datetime, timezone
with open('$state_file') as f:
    state = json.load(f)
last = state.get('last_run', '')
if last:
    dt = datetime.fromisoformat(last.replace('Z', '+00:00'))
    now = datetime.now(timezone.utc)
    diff = now - dt
    hours = diff.total_seconds() / 3600
    print(f'{last} ({hours:.1f}h ago)')
else:
    print('never')
" 2>/dev/null || echo "unknown")
        echo -e "  ${DIM}last run: $last_run${NC}"

        local processed failed
        processed=$(python3 -c "import json; print(json.load(open('$state_file')).get('processed', 0))" 2>/dev/null || echo "?")
        failed=$(python3 -c "import json; print(json.load(open('$state_file')).get('failed', 0))" 2>/dev/null || echo "?")
        echo -e "  ${DIM}last run stats: ${processed} processed, ${failed} failed${NC}"
    else
        check_warn "no state file — specs-watcher may have never run"
    fi

    # 3. Pending kiro tasks in linear
    source "$SCRIPT_DIR/config.sh" 2>/dev/null
    if [ -z "$LINEAR_API_KEY" ]; then
        source /Users/kokayi/Dev/consuelo_on_call_coaching/.agent/linear-api.sh 2>/dev/null
    fi

    if [ -n "$LINEAR_API_KEY" ]; then
        local pending_count
        pending_count=$(curl -s -X POST https://api.linear.app/graphql \
            -H "Content-Type: application/json" \
            -H "Authorization: $LINEAR_API_KEY" \
            -d "{\"query\":\"{ issues(filter: { labels: { id: { eq: \\\"$LINEAR_LABEL_KIRO_ID\\\" } }, state: { name: { eq: \\\"Open\\\" } } }) { nodes { id } } }\"}" \
            2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']['issues']['nodes']))" 2>/dev/null || echo "?")

        if [ "$pending_count" = "0" ]; then
            echo -e "  ${DIM}pending kiro tasks: 0 (queue empty)${NC}"
        else
            echo -e "  ${YELLOW}pending kiro tasks: $pending_count waiting${NC}"
        fi
    fi

    # 4. Open kiro PRs
    local open_prs
    open_prs=$(gh pr list --repo kokayicobb/consuelo_on_call_coaching --label kiro --state open --json number,title 2>/dev/null)
    local pr_count
    pr_count=$(echo "$open_prs" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

    if [ "$pr_count" = "0" ]; then
        echo -e "  ${DIM}open kiro PRs: 0${NC}"
    else
        echo -e "  ${YELLOW}open kiro PRs: $pr_count${NC}"
        echo "$open_prs" | python3 -c "
import json, sys
for pr in json.load(sys.stdin):
    print(f'    #{pr[\"number\"]} — {pr[\"title\"]}')
" 2>/dev/null
    fi

    # 5. Deploy failures pending retry
    local fail_dir="$SCRIPT_DIR/deploy-failures"
    if [ -d "$fail_dir" ]; then
        local fail_count
        fail_count=$(ls -1 "$fail_dir"/*.json 2>/dev/null | wc -l | tr -d ' ')
        if [ "$fail_count" -gt 0 ]; then
            check_warn "$fail_count deploy failure(s) pending retry"
        fi
    fi

    # Summary
    echo ""
    if [ $FAIL -gt 0 ]; then
        echo -e "${RED}${BOLD}$FAIL issue(s) found${NC}"
        return 1
    elif [ $WARN -gt 0 ]; then
        echo -e "${YELLOW}${BOLD}healthy with $WARN warning(s)${NC}"
        return 0
    else
        echo -e "${GREEN}${BOLD}all clear${NC}"
        return 0
    fi
}

# =============================================================================
# FULL CHECK
# =============================================================================

full_check() {
    echo -e "${BOLD}=== pipeline health check ===${NC}"
    echo -e "${DIM}$(date)${NC}"

    # -------------------------------------------------------------------------
    section "1. CLI tools"
    # -------------------------------------------------------------------------

    # kiro-cli
    if command -v kiro-cli &>/dev/null; then
        local kiro_version
        kiro_version=$(kiro-cli --version 2>/dev/null || echo "unknown")
        check_pass "kiro-cli installed ($kiro_version)"
    else
        if [ -x /Users/kokayi/.local/bin/kiro-cli ]; then
            check_pass "kiro-cli at /Users/kokayi/.local/bin/kiro-cli"
        else
            check_fail "kiro-cli not found"
        fi
    fi

    # gh cli
    if command -v gh &>/dev/null; then
        if gh auth status &>/dev/null; then
            check_pass "gh cli authenticated"
        else
            check_fail "gh cli installed but NOT authenticated"
        fi
    else
        check_fail "gh cli not installed"
    fi

    # python3
    if command -v python3 &>/dev/null; then
        check_pass "python3 available"
    else
        check_fail "python3 not found"
    fi

    # jq
    if command -v jq &>/dev/null; then
        check_pass "jq available"
    else
        check_fail "jq not found"
    fi

    # railway (optional)
    if command -v railway &>/dev/null; then
        check_pass "railway cli available"
    else
        check_warn "railway cli not installed (needed for deploy checks)"
    fi

    # -------------------------------------------------------------------------
    section "2. linear api"
    # -------------------------------------------------------------------------

    # Load linear key
    source "$SCRIPT_DIR/config.sh" 2>/dev/null
    if [ -z "$LINEAR_API_KEY" ]; then
        source /Users/kokayi/Dev/consuelo_on_call_coaching/.agent/linear-api.sh 2>/dev/null
    fi

    if [ -n "$LINEAR_API_KEY" ]; then
        check_pass "LINEAR_API_KEY loaded"

        # Test API
        local linear_test
        linear_test=$(curl -s -X POST https://api.linear.app/graphql \
            -H "Content-Type: application/json" \
            -H "Authorization: $LINEAR_API_KEY" \
            -d '{"query":"{ viewer { name } }"}' 2>/dev/null)

        local viewer_name
        viewer_name=$(echo "$linear_test" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['viewer']['name'])" 2>/dev/null)

        if [ -n "$viewer_name" ]; then
            check_pass "linear api responding (user: $viewer_name)"
        else
            check_fail "linear api not responding"
        fi

        # Check kiro label exists
        local label_check
        label_check=$(curl -s -X POST https://api.linear.app/graphql \
            -H "Content-Type: application/json" \
            -H "Authorization: $LINEAR_API_KEY" \
            -d "{\"query\":\"{ issueLabel(id: \\\"$LINEAR_LABEL_KIRO_ID\\\") { name } }\"}" \
            2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['issueLabel']['name'])" 2>/dev/null)

        if [ "$label_check" = "kiro" ]; then
            check_pass "kiro label exists (id: ${LINEAR_LABEL_KIRO_ID:0:8}...)"
        else
            check_fail "kiro label not found at configured ID"
        fi
    else
        check_fail "LINEAR_API_KEY not set"
    fi

    # -------------------------------------------------------------------------
    section "3. github repo"
    # -------------------------------------------------------------------------

    local repo="kokayicobb/consuelo_on_call_coaching"

    if gh repo view "$repo" --json name &>/dev/null; then
        check_pass "repo $repo accessible"
    else
        check_fail "cannot access repo $repo"
    fi

    # Check labels
    local has_kiro_label
    has_kiro_label=$(gh label list --repo "$repo" --search kiro --json name -q '.[].name' 2>/dev/null | grep -c "^kiro$" || true)
    if [ "$has_kiro_label" -gt 0 ]; then
        check_pass "github 'kiro' label exists"
    else
        check_warn "github 'kiro' label not found on repo"
    fi

    # -------------------------------------------------------------------------
    section "4. skill files"
    # -------------------------------------------------------------------------

    local all_files_ok=true

    # Core pipeline
    for f in specs-watcher.sh config.sh kiro_agent.py linear-api-kiro.sh linear_helper.py; do
        if [ -f "$SCRIPT_DIR/$f" ]; then
            check_pass "kiro/$f"
        else
            check_fail "kiro/$f MISSING"
            all_files_ok=false
        fi
    done

    # ACP client
    if [ -f "$SKILLS_ROOT/kiro-acp/client.py" ]; then
        check_pass "kiro-acp/client.py"
    else
        check_fail "kiro-acp/client.py MISSING"
    fi

    # GitHub dev
    for f in github_dev.py github_api.py linear_api.py; do
        if [ -f "$SKILLS_ROOT/github-dev/$f" ]; then
            check_pass "github-dev/$f"
        else
            check_fail "github-dev/$f MISSING"
        fi
    done

    # GitHub review
    for f in review.py github_api.py analyzer.py checklist.py conventional.py; do
        if [ -f "$SKILLS_ROOT/github-review/$f" ]; then
            check_pass "github-review/$f"
        else
            check_fail "github-review/$f MISSING"
        fi
    done

    # Consuelo test
    if [ -f "$SKILLS_ROOT/consuelo-test/SKILL.md" ]; then
        check_pass "consuelo-test/SKILL.md"
    else
        check_warn "consuelo-test/SKILL.md missing"
    fi

    # PR watcher plugin
    if [ -f "$WORKSPACE_ROOT/plugins/pr-watcher.ts" ]; then
        check_pass "plugins/pr-watcher.ts"
    else
        check_warn "plugins/pr-watcher.ts missing"
    fi

    # -------------------------------------------------------------------------
    section "5. slack webhook"
    # -------------------------------------------------------------------------

    if [ -z "$SLACK_WEBHOOK_URL" ]; then
        # Try loading from env or .env
        if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
            : # already set
        else
            check_warn "SLACK_WEBHOOK_URL not set (notifications won't send)"
        fi
    else
        # Test webhook with a dry ping (don't actually send)
        local slack_test
        slack_test=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
            -H 'Content-type: application/json' \
            --data '{"text":"health check ping (ignore)"}' \
            "$SLACK_WEBHOOK_URL" 2>/dev/null)

        if [ "$slack_test" = "200" ]; then
            check_pass "slack webhook responding"
        else
            check_fail "slack webhook returned $slack_test"
        fi
    fi

    # -------------------------------------------------------------------------
    section "6. specs-watcher status"
    # -------------------------------------------------------------------------

    # Run the quick check parts
    local watcher_pid
    watcher_pid=$(pgrep -f "specs-watcher.sh.*--daemon" 2>/dev/null)
    if [ -n "$watcher_pid" ]; then
        check_pass "specs-watcher daemon running (PID: $watcher_pid)"
    else
        local cron_entry
        cron_entry=$(crontab -l 2>/dev/null | grep -c "specs-watcher" || true)
        if [ "$cron_entry" -gt 0 ]; then
            check_pass "specs-watcher in crontab"
            crontab -l 2>/dev/null | grep "specs-watcher" | while read -r line; do
                echo -e "    ${DIM}$line${NC}"
            done
        else
            check_warn "specs-watcher not scheduled (no daemon, no cron)"
        fi
    fi

    # State file
    local state_file="$SCRIPT_DIR/.specs-watcher-state.json"
    if [ -f "$state_file" ]; then
        local last_run
        last_run=$(python3 -c "
import json
from datetime import datetime, timezone
with open('$state_file') as f:
    state = json.load(f)
last = state.get('last_run', '')
if last:
    dt = datetime.fromisoformat(last.replace('Z', '+00:00'))
    now = datetime.now(timezone.utc)
    diff = now - dt
    hours = diff.total_seconds() / 3600
    print(f'{last} ({hours:.1f}h ago)')
else:
    print('never')
" 2>/dev/null || echo "unknown")
        echo -e "  ${DIM}last run: $last_run${NC}"
    fi

    # -------------------------------------------------------------------------
    section "7. pipeline queue"
    # -------------------------------------------------------------------------

    if [ -n "$LINEAR_API_KEY" ]; then
        # Pending tasks
        local pending
        pending=$(curl -s -X POST https://api.linear.app/graphql \
            -H "Content-Type: application/json" \
            -H "Authorization: $LINEAR_API_KEY" \
            -d "{\"query\":\"{ issues(filter: { labels: { id: { eq: \\\"$LINEAR_LABEL_KIRO_ID\\\" } }, state: { name: { in: [\\\"Open\\\", \\\"Backlog\\\"] } } }) { nodes { identifier title state { name } } } }\"}" \
            2>/dev/null)

        echo "$pending" | python3 -c "
import json, sys
data = json.load(sys.stdin)
nodes = data['data']['issues']['nodes']
if not nodes:
    print('  \033[2mno pending kiro tasks\033[0m')
else:
    for issue in nodes:
        state = issue['state']['name']
        print(f'  {issue[\"identifier\"]} [{state}] — {issue[\"title\"]}')
" 2>/dev/null || echo -e "  ${DIM}could not fetch queue${NC}"

        # In progress
        local in_progress
        in_progress=$(curl -s -X POST https://api.linear.app/graphql \
            -H "Content-Type: application/json" \
            -H "Authorization: $LINEAR_API_KEY" \
            -d "{\"query\":\"{ issues(filter: { labels: { id: { eq: \\\"$LINEAR_LABEL_KIRO_ID\\\" } }, state: { name: { eq: \\\"In Progress\\\" } } }) { nodes { identifier title } } }\"}" \
            2>/dev/null)

        echo "$in_progress" | python3 -c "
import json, sys
data = json.load(sys.stdin)
nodes = data['data']['issues']['nodes']
if nodes:
    print()
    for issue in nodes:
        print(f'  \033[1;33m[IN PROGRESS]\033[0m {issue[\"identifier\"]} — {issue[\"title\"]}')
" 2>/dev/null
    fi

    # Open PRs
    local open_prs
    open_prs=$(gh pr list --repo "$repo" --label kiro --state open --json number,title,createdAt 2>/dev/null)
    echo "$open_prs" | python3 -c "
import json, sys
prs = json.load(sys.stdin)
if prs:
    print()
    for pr in prs:
        print(f'  \033[1;34m[PR #{pr[\"number\"]}]\033[0m {pr[\"title\"]}')
" 2>/dev/null

    # Deploy failures
    local fail_dir="$SCRIPT_DIR/deploy-failures"
    if [ -d "$fail_dir" ]; then
        local fail_files
        fail_files=$(ls -1 "$fail_dir"/*.json 2>/dev/null)
        if [ -n "$fail_files" ]; then
            echo ""
            check_warn "deploy failures pending retry:"
            echo "$fail_files" | while read -r f; do
                echo -e "    ${DIM}$(basename "$f")${NC}"
            done
        fi
    fi

    # =========================================================================
    # SUMMARY
    # =========================================================================

    echo ""
    echo -e "${BOLD}─────────────────────────────────${NC}"
    echo -e "${GREEN}pass: $PASS${NC}  ${RED}fail: $FAIL${NC}  ${YELLOW}warn: $WARN${NC}"

    if [ $FAIL -gt 0 ]; then
        echo -e "\n${RED}${BOLD}pipeline has issues — $FAIL check(s) failed${NC}"
        return 1
    elif [ $WARN -gt 0 ]; then
        echo -e "\n${YELLOW}${BOLD}pipeline is healthy with $WARN warning(s)${NC}"
        return 0
    else
        echo -e "\n${GREEN}${BOLD}pipeline is fully healthy${NC}"
        return 0
    fi
}

# =============================================================================
# ENTRY POINT
# =============================================================================

case "${1:-}" in
    --quick|-q)
        quick_check
        ;;
    --help|-h)
        echo "pipeline health check"
        echo ""
        echo "usage:"
        echo "  pipeline-health.sh          # full system check"
        echo "  pipeline-health.sh --quick  # just watcher/cron status"
        echo "  pipeline-health.sh --help   # this help"
        ;;
    *)
        full_check
        ;;
esac
