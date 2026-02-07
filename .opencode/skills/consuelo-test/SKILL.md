---
name: consuelo-test
description: Test deployed Consuelo changes against Linear task requirements and PR verification criteria. Runs after successful Railway deploys to verify features work in production.
---

# Consuelo Test Runner

Test deployed changes against the original requirements. This skill runs after a successful Railway deploy to verify that the changes actually work.

## When to Use This Skill

- After a successful Railway deploy (triggered by pr-watcher or heartbeat)
- When asked to test a specific feature on the live app
- During heartbeat checks if there are recently-deployed PRs that haven't been tested

## What You Need

- **PR number** or **Linear task ID** — to know what was changed and what to test
- **Railway URL** — the deployed Consuelo app (usually from Railway dashboard or env)

## Testing Flow

### Step 1: Gather Requirements

**From Linear task (if available):**
```bash
# Fetch the Linear task spec
python3 /Users/kokayi/Dev/claude-agent-workflow/.opencode/skills/github-dev/fetch_task.py CON-456
# Read the spec
cat /Users/kokayi/Dev/claude-agent-workflow/.opencode/skills/github-dev/tasks/CON-456.md
```

**From PR description:**
```bash
gh pr view <number> --json body,title,files --repo kokayicobb/consuelo_on_call_coaching
```

### Step 2: Extract Verification Criteria

Look for these in the Linear task spec or PR body:
- `## Verification Criteria` section with checkboxes
- `## Acceptance Criteria` section
- `## What to Test` section
- Any description of expected behavior

If no explicit criteria exist, derive them from:
- The PR title and description (what was the intent?)
- The changed files (what areas were modified?)
- The commit messages (what was implemented?)

### Step 3: Run Tests

For each verification criterion, test it against the deployed app:

**API Tests (curl/httpie):**
```bash
# Test an API endpoint
curl -s https://your-railway-url.up.railway.app/api/endpoint | python3 -m json.tool

# Test with authentication
curl -s -H "Authorization: Bearer $TOKEN" https://your-railway-url.up.railway.app/api/protected
```

**UI Tests (agent-browser if available):**
If the changes involve UI:
1. Navigate to the relevant page
2. Verify the UI elements are present
3. Test user interactions (clicks, form submissions)
4. Check error states

**Health Check:**
```bash
# Always start with a basic health check
curl -s -o /dev/null -w "%{http_code}" https://your-railway-url.up.railway.app/
```

### Step 4: Report Results

Post test results as a PR comment:

```markdown
## Test Results — PR #123

**Deployed URL:** https://...
**Tested at:** 2026-02-07 15:30 UTC

### Criteria Results

| Criterion | Result | Notes |
|-----------|--------|-------|
| User can log in | PASS | Tested with test credentials |
| Error on invalid login | PASS | Shows appropriate error message |
| Dashboard loads | FAIL | 500 error on /dashboard |

### Summary
2/3 criteria passed. Dashboard endpoint returning 500.

### Recommendation
Fix the dashboard endpoint before marking as complete.
```

### Step 5: Update Linear Task

If all tests pass:
```bash
# Move task to Done (via linear_helper or direct API)
python3 /Users/kokayi/Dev/claude-agent-workflow/.opencode/skills/kiro/linear_helper.py label CON-456 --add tested
```

If tests fail:
- Post the failure details to the PR
- Send Slack notification
- Leave the task in "In Review" state

## Test Categories

### Critical (Must Pass)
- App starts without errors (health check returns 200)
- Core user flow works (the main feature being tested)
- No console errors in the response

### Important (Should Pass)
- Error handling works (invalid inputs, edge cases)
- Response times are reasonable (<5s for API calls)
- No regressions in existing functionality

### Nice to Have
- UI looks correct (screenshots if agent-browser available)
- Responsive design works
- Edge cases handled gracefully

## Important Notes

- **Don't test destructive operations** on production data
- **Use test/staging credentials** if authentication is needed
- **Report partial results** — even if some tests fail, report what passed
- **This skill complements the github-review skill's --test flag** — the review skill tests during review, this skill tests after deploy
- **Railway URL** should be discoverable from Railway CLI or environment config
