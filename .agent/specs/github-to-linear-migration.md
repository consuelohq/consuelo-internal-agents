# Migrate agent workflow from GitHub Issues to Linear

## Overview

Migrate the autonomous agent task runner (`.agent/run-tasks.sh`) from GitHub Issues to Linear for issue tracking. Continue using GitHub for PRs, but use Linear's Git integration to auto-link PRs to Linear issues.

## Why

- Linear has native workflow states (cleaner than label-based status tracking)
- "Mercury" project with "Claude" label provides better organization
- Better overall UX for issue management

---

## Spec

### 1. Configuration Changes

**File:** `.agent/config.sh`

Add Linear configuration:
```bash
# Linear API
LINEAR_API_KEY="${LINEAR_API_KEY:-}"
LINEAR_TEAM_ID=""           # Get from Linear API query
LINEAR_LABEL_NAME="Claude"  # Label to filter issues by

# Workflow State IDs (get from Linear API)
LINEAR_STATE_READY=""       # "Ready" or equivalent
LINEAR_STATE_IN_PROGRESS="" # "In Progress"
LINEAR_STATE_IN_REVIEW=""   # "In Review"
LINEAR_STATE_DONE=""        # "Done" (for reference, human moves to this)
```

### 2. Create Linear API Wrapper

**File:** `.agent/linear-api.sh` (NEW)

Simple curl-based wrapper functions:

```bash
#!/bin/bash
# Linear API helper functions

linear_graphql() {
  local query="$1"
  curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $LINEAR_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"$query\"}"
}

# Get issues with Claude label that are in Ready state
# IMPORTANT: Order by createdAt ascending (oldest first) so multi-part specs
# are processed in order (part 1 before part 2, etc.)
linear_get_ready_issues() {
  linear_graphql '
    query {
      issues(
        filter: {
          labels: { name: { eq: "Claude" } }
          state: { name: { eq: "Ready" } }
        }
        orderBy: createdAt
      ) {
        nodes {
          id
          identifier
          title
          description
          createdAt
        }
      }
    }
  ' | jq -c '.data.issues.nodes[]'
}

# Update issue state
linear_update_state() {
  local issue_id="$1"
  local state_id="$2"
  linear_graphql "
    mutation {
      issueUpdate(id: \"$issue_id\", input: { stateId: \"$state_id\" }) {
        success
        issue { id identifier state { name } }
      }
    }
  "
}

# Add comment to issue
linear_add_comment() {
  local issue_id="$1"
  local body="$2"
  # Escape quotes and newlines in body
  local escaped_body=$(echo "$body" | sed 's/"/\\"/g' | tr '\n' ' ')
  linear_graphql "
    mutation {
      commentCreate(input: { issueId: \"$issue_id\", body: \"$escaped_body\" }) {
        success
      }
    }
  "
}
```

### 3. Modify run-tasks.sh

**File:** `.agent/run-tasks.sh`

#### 3a. Source the Linear wrapper
```bash
source "$SCRIPT_DIR/linear-api.sh"
```

#### 3b. Replace `get_open_issues()` function

**Before (GitHub):**
```bash
gh issue list --label "$ISSUE_LABEL" --state open --limit 50 --json number,title,body
```

**After (Linear):**
```bash
linear_get_ready_issues
```

#### 3c. Replace status update calls

**Before (GitHub):**
```bash
gh issue edit "$issue_number" --remove-label "agent-ready" --add-label "agent-working"
```

**After (Linear):**
```bash
linear_update_state "$issue_id" "$LINEAR_STATE_IN_PROGRESS"
```

#### 3d. Update branch naming convention

**Before:**
```bash
RUN_BRANCH="${BRANCH_PREFIX}/run-${RUN_ID}"
```

**After (include Linear issue ID for auto-linking):**
```bash
# For single issue: agent/CON-123-fix-description
# For batch: agent/run-2025-01-24-abc123
# Include issue identifiers in commit messages for linking
```

#### 3e. Final status update

When task completes (passes quality gates):
```bash
# Move to "In Review" - keep Claude label (Linear doesn't remove labels on state change)
linear_update_state "$issue_id" "$LINEAR_STATE_IN_REVIEW"

# Add comment with PR link
linear_add_comment "$issue_id" "PR created: $PR_URL"
```

### 4. Task Ordering (IMPORTANT)

**Issues MUST be processed oldest-first (by creation date).**

When creating multi-part specs (e.g., parts 1-8), they should be processed in order. Without explicit ordering, the API may return newest-first, causing part 8 to run before part 1.

The `linear_get_ready_issues()` function uses `orderBy: createdAt` which returns oldest first by default. This ensures:
- Part 1 of a spec runs before Part 2
- Dependencies are respected when tasks build on each other
- Predictable execution order for batch runs

### 5. Workflow State Mapping

| Current (GitHub Labels) | New (Linear States) |
|------------------------|---------------------|
| `agent-ready` | Ready state + Claude label |
| `agent-working` | In Progress state |
| `agent-review` | In Review state |
| `agent-completed` | Done state (human moves here) |
| `agent-test` | In Review state + comment noting test failure |

### 6. PR Linking

Linear's Git integration auto-links PRs when:
- Branch name contains issue identifier (e.g., `agent/CON-123-description`)
- Commit message contains identifier (e.g., `fix(CON-123): description`)
- PR title/body contains identifier

**Update PR body template to include Linear links:**
```markdown
## Agent Run Summary

**Linear Issues:** CON-123, CON-124, CON-125
...
```

---

## Setup Steps (One-time)

1. Create Linear API key: Settings → API → Personal API keys
2. Query workspace to get Team ID and State IDs:
   ```bash
   curl -X POST https://api.linear.app/graphql \
     -H "Authorization: $LINEAR_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"query": "{ teams { nodes { id name states { nodes { id name } } } } }"}'
   ```
3. Create "Claude" label in Linear if it doesn't exist
4. Add `LINEAR_API_KEY` to environment (local + Railway if needed)
5. Update `.agent/config.sh` with IDs

---

## Testing

1. Create a test issue in Linear with "Claude" label in "Ready" state
2. Run `.agent/run-tasks.sh --dry-run` to verify it picks up the issue
3. Run full workflow on test issue
4. Verify:
   - Issue moves to "In Progress" when agent starts
   - Issue moves to "In Review" when agent finishes
   - PR is auto-linked in Linear
   - Claude label remains on issue

---

## Out of Scope

- GitHub PR creation (keep using `gh pr create`)
- Quality gates (keep as-is)
- Slack notifications (keep as-is)
- Sentry issue import (remove or adapt separately)

---

## Acceptance Criteria

- [ ] `.agent/linear-api.sh` created with query/mutation helpers
- [ ] `.agent/config.sh` updated with Linear config
- [ ] `.agent/run-tasks.sh` uses Linear instead of GitHub for issue tracking
- [ ] Issues picked up by "Claude" label + "Ready" state
- [ ] **Issues processed oldest-first (by createdAt) so multi-part specs run in order**
- [ ] Issues moved to "In Review" on completion (Claude label kept)
- [ ] PRs auto-linked to Linear issues via branch naming
- [ ] Dry-run mode works with Linear
