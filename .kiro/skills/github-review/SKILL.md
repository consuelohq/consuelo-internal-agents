# GitHub Review Skill

World-class automated code reviews using GitHub API. One command, everything posted to GitHub.

## Usage

```bash
# review a pr and post everything to github (uses default repo)
review pr 788

# review pr in a different repo
review pr 788 --repo owner/other-repo

# by full url
review "https://github.com/kokayicobb/consuelo_on_call_coaching/pull/788"

# preview without posting
review pr 788 --local-only

# optional flags
review pr 788 --approve # auto-approve if no blocking issues
review pr 788 --split-pr # suggest splitting if too many features
review pr 788 --verbose # more detailed feedback
review pr 788 --test # use agent browser to test the changes live
review pr 788 --auto # automated mode: decide big/small, auto-merge small changes, deploy check
```

**Note:** This skill works remotely - no local repo clone needed. Just ensure you're authenticated with `gh auth status`.

## What It Does

Every review creates these GitHub artifacts:

1. **Checklist comment** - tracks all review categories (functionality, readability, maintainability, security, performance, coding standards)
2. **Overall review summary** - categorized findings (blocking issues, suggestions, nits, praise)
3. **Inline comments** - specific feedback on individual lines using conventional comments format
4. **Labels** - auto-applied based on findings (needs-tests, needs-docs, security-review, etc.)

## How It Works

**Phase 1: Context**
- Read PR description, check for what/why/risks
- Verify PR structure and complexity
- Check CI status

**Phase 1.5: Spec Compliance**
- Parse PR body for "Verification Criteria" sections (from Linear task specs)
- For each criterion, check the diff to see if it's satisfied
- Report compliance status (met / unmet / unknown)
- Flag any criteria the diff doesn't address at all as blocking issues
- Skip this phase if no Verification Criteria are found in the PR body

**Phase 2: Checklist Walkthrough**
- Work through each category systematically
- Check items as you go (don't stop until complete)
- Build inline comment list

**Phase 3: Synthesize**
- Categorize findings (blocking issues, suggestions, nits, praise)
- Draft overall summary
- Identify labels to apply
- Analyze if PR should be split (based on features/complexity, not just lines)

**Phase 4: Post to GitHub**
- Post checklist (tracked via GitHub task lists)
- Post overall review summary
- Post inline comments
- Apply labels
- Optionally approve if no blocking issues

**Phase 4.5: Live Testing (when --test flag is used)**
- Parse Linear task ID from PR description (if present)
- Fetch the Linear task details to understand requirements
- Analyze the PR diff to identify what changed
- Launch agent browser to test the deployed/staging application
- Test the specific functionality based on task requirements and PR changes
- Report test results back to the review (pass/fail + details)

## Conventional Comments

All feedback follows this format:
```
<label> [decorations]: <subject>

[discussion + reasoning]
```

Labels: `praise`, `nitpick`, `suggestion`, `issue`, `todo`, `question`, `thought`, `chore`, `note`

Decorations: `blocking`, `non-blocking`, `security`, `test`, `if-minor`, `readability`, `maintainability`, `performance`

## Split PR Logic

Auto-suggests splitting when PR contains multiple distinct features or is overly complex. Uses intelligent analysis instead of line count thresholds.

Examples that trigger split suggestion:
- Frontend + backend changes in one PR
- Multiple unrelated features bundled together
- Schema changes + API changes + UI changes all in one
- Refactoring + new feature in same PR

## Live Testing (--test flag)

When `--test` flag is used, the review includes automated live testing:

1. **Linear Task Integration**: Extracts the Linear task ID from the PR body and fetches the full task spec
2. **Change Analysis**: Examines the PR diff to understand what code changed
3. **Agent Browser**: Launches agent-browser to navigate and test the deployed application
4. **Requirement Verification**: Tests each verification criterion from the Linear task
5. **Test Reporting**: Adds test results to the review (pass/fail, screenshots when relevant, edge cases covered)

**What Gets Tested:**
- User flows mentioned in Linear task requirements
- UI changes (buttons, forms, pages)
- API endpoints (if accessible via browser)
- Error states and edge cases
- Responsive design (if UI changes)

**Requirements for --test to work:**
- PR must have a deployed staging/preview environment
- Staging URL should be mentioned in PR description (auto-detected if present)
- Linear task ID should be in PR body (format: `Linear: DEV-123`)
- agent-browser CLI must be installed and working

**Example PR body format:**
```markdown
## Description
Implements user login feature

## Linear Task
DEV-456

## Verification Criteria
- [ ] User can log in with email/password
- [ ] Error message shown on invalid credentials
- [ ] User redirected to dashboard on success
```

## Requirements

- GitHub CLI (`gh`) installed and authenticated (`gh auth status`)
- Python 3.8+

**Note:** No local repo clone needed. This skill works entirely remotely via the GitHub API using `gh` CLI.

## Auto Mode (--auto)

When `--auto` is passed, the review operates in automated mode as part of the Kiro pipeline:

### How It Works

1. **Normal review runs first** — all phases (context, checklist, diff analysis, synthesis)
2. **Big vs small detection:**
   - **Small**: <10 files changed, <500 total lines, single logical concern (no cross-cutting changes)
   - **Big**: Everything else (many files, lots of lines, frontend+backend+schema mixed)
3. **Decision:**
   - **Small + no blocking issues** → auto-approve, squash merge, then Railway deploy check
   - **Small + blocking issues** → Slack notification with the issues
   - **Big** → Slack notification requesting manual review

### Railway Deploy Check

After auto-merging a small PR:
1. Sleeps 5 minutes (Railway deploy time)
2. Checks `railway logs --latest` for errors
3. **Success** → Slack success notification, mark for testing
4. **Failure** → Extracts error, saves to `kiro/deploy-failures/pr-{N}.json`, Slack error notification

### Deploy Failure Retry

When a deploy fails, the failure info is saved so the pr-watcher can trigger kiro to fix the issue. The failure file contains:
```json
{
  "deployed": false,
  "error": "TypeError: Cannot read property 'map' of undefined",
  "pr_number": "123",
  "branch": "remote/consuelo-a3f2--feature-name"
}
```

### Slack Notifications

Notifications go to #suelo via `SLACK_WEBHOOK_URL` env var. Messages are prefixed with level:
- `[ok]` — success
- `[warn]` — needs attention
- `[error]` — failure/urgent
