---
name: task-creator
description: Create Linear issues for coding workflows in the Suelo project. Auto-detects complexity to create full specs or quick tasks. Supports priority levels. Use when Ko asks to create tasks, issues, or linear tasks for coding work.
---

# Task Creator

Create Linear issues for the `.agent/run-tasks.sh` workflow with intelligent complexity detection. Automatically chooses between detailed specification issues and lightweight quick tasks. Issues are automatically added to the Linear Suelo project for agent pickup.

## Default Project

**Always use the Suelo project by default**, unless the user explicitly specifies a different project (e.g., "create this in the Mercury project" or "put this in [Project Name]").

## Prerequisites

Linear workspace IDs are hardcoded for the consuelo workspace:
- Team ID: `29f5c661-da6c-4bfb-bd48-815a006ccaac`
- Claude label ID: `b3c52ecf-d35a-4ccd-a305-c288f033c01f`
- **Suelo project ID: `10004248-b69d-4a76-825a-83d5628571c8`** (Default - use unless told otherwise)
- Mercury project ID: `10004248-b69d-4a76-825a-83d5628571c8` (Only when explicitly specified)

To verify Linear API connection:

```bash
source .agent/linear-api.sh
linear_check_connection
```

## Two Modes

### 1. Full Spec Issues (Complex Tasks)

Comprehensive GitHub Issues with detailed requirements, design considerations, and task breakdowns. Used for features, multi-file changes, and architectural work.

### 2. Quick Issues (Simple Tasks)

Lightweight GitHub Issues for bug fixes, typos, and single-file changes.

## Complexity Detection

Analyze the user's request to determine complexity:

### FULL SPEC indicators (default when ambiguous):

- Keywords: "implement", "build", "create", "add feature", "new system", "design"
- Multiple components or files involved
- API + frontend work together
- Database/schema changes
- User explicitly says "spec", "detailed", "full", "comprehensive"
- Architecture decisions required
- New endpoints or routes
- State management changes

### QUICK ISSUE indicators:

- Keywords: "fix", "bug", "tweak", "typo", "simple", "quick", "minor"
- Single file changes
- Text/copy updates
- Style/CSS adjustments
- User explicitly says "quick", "simple", "small"
- Clear, bounded scope with obvious implementation

### Manual Override:

- `--quick` flag forces quick issue mode
- `--full` flag forces full spec mode

## Full Spec Format

For complex tasks, create a GitHub Issue with this structure:

### Title Format

```
[TYPE]: Brief, actionable description
```

### Body Format

```markdown
## Overview

**Problem Statement:** [Clear description of what's broken or missing]

**Why This Matters:** [Business/technical justification - user impact, revenue, technical debt]

**Current State:** [How things work now, including limitations]

**Desired State:** [How things should work after implementation]

---

## Requirements

### Requirement 1: [Core Functionality Title]

**User Story:** As a [role], I want [goal], so that [benefit].

#### Acceptance Criteria

1. WHEN [trigger] THE System SHALL [action]
2. IF [condition] THEN THE System SHALL [response]
3. THE System SHALL [always-on requirement]
4. THE [Component] SHALL [render/display/update] [specific behavior]
5. WHEN [error scenario] THE System SHALL [error handling behavior]

### Requirement 2: Error Handling

**User Story:** As a user, I want clear error messages, so that I can understand and recover from problems.

#### Acceptance Criteria

1. WHEN [error occurs] THE System SHALL [display user-friendly message]
2. THE System SHALL [log error to Sentry with category tag]
3. THE System SHALL [preserve user data/state despite error]

### Requirement 3: Performance

**User Story:** As a user, I want fast response, so that my workflow isn't interrupted.

#### Acceptance Criteria

1. THE System SHALL [complete operation in <X seconds]
2. THE System SHALL [show loading state after 200ms]

---

## Design

### Architecture

[Component hierarchy, data flow diagram]

```
ParentComponent
├── ChildComponent1
│   └── API Call → /api/endpoint
└── ChildComponent2
```

### Key Files

- `path/to/file1.tsx` - [what changes]
- `path/to/file2.py` - [what changes]

### Data Models

```typescript
interface NewFeatureData {
  id: string;
  userId: string;
  // ... relevant fields
}
```

### Implementation Notes

[Any technical considerations, patterns to follow, gotchas to avoid]

---

## Tasks

- [ ] Task 1: [Description] (Req 1.1, 1.2)
- [ ] Task 2: [Description] (Req 1.3)
- [ ] Task 3: [Description] (Req 2.1)
- [ ] Task 4: Write tests
- [ ] Task 5: Update documentation (if needed)
```

## Quick Issue Format

For simple tasks, create a lightweight GitHub Issue:

### Title Format

```
[TYPE]: Brief, actionable description
```

### Body Format

```markdown
**PURPOSE:** What needs to be done and why (1-2 sentences)

**KEY FILES:** (if known)
- path/to/likely/file.tsx

**ACCEPTANCE CRITERIA:**
- [ ] Clear, testable criterion 1
- [ ] Clear, testable criterion 2
- [ ] Clear, testable criterion 3
```

## Type Prefixes

| Type | Use When |
|------|----------|
| `[FEATURE]` | "add", "create", "implement", "new" |
| `[BUG]` | "fix", "broken", "error", "bug", "issue" |
| `[REFACTOR]` | "refactor", "restructure", "reorganize", "clean up" |
| `[TASK]` | "update", "change", "cleanup", "docs", general work |

## Instructions

When the user requests task/issue creation, follow these steps:

### Step 1: Parse User Input

Extract from the user's description:
- **What** needs to be done (the core task)
- **Why** it matters (if provided)
- **Where** it might live (file hints if mentioned)
- **Type** of work (feature, bug, task, refactor)
- **Complexity** signals (keywords, scope, components involved)

### Step 2: Determine Mode

1. Check for explicit flags (`--quick`, `--full`)
2. If no flags, analyze complexity indicators
3. **When ambiguous, default to FULL SPEC** (better to over-specify than under-specify)

### Step 3: Research (Full Spec Only)

For full specs, briefly explore the codebase to identify:
- Relevant existing files and patterns
- API routes that might be affected
- Database collections involved
- Similar features to reference

### Step 4: Generate Issue Content

**For Full Spec:**
- Write comprehensive Overview section
- Create 3-5 requirements with acceptance criteria
- Include architecture/design section
- Break down into specific tasks
- Reference actual file paths when possible

**For Quick Issue:**
- Write concise PURPOSE statement
- List KEY FILES if identifiable
- Create 3-5 acceptance criteria checkboxes

### Step 5: Create the Linear Issue

**Source Linear API and config:**

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../.."
source "$SCRIPT_DIR/.agent/config.sh"
source "$SCRIPT_DIR/.agent/linear-api.sh"
```

**Set Linear IDs (hardcoded for consuelo workspace):**

```bash
# Linear workspace IDs for consuelo
export LINEAR_TEAM_ID="29f5c661-da6c-4bfb-bd48-815a006ccaac"
export LINEAR_LABEL_CLAUDE_ID="b3c52ecf-d35a-4ccd-a305-c288f033c01f"

# Default project: Suelo (use unless user explicitly specifies another)
export LINEAR_PROJECT_SUELO_ID="10004248-b69d-4a76-825a-83d5628571c8"

# Other projects (only use when explicitly requested)
export LINEAR_PROJECT_MERCURY_ID="10004248-b69d-4a76-825a-83d5628571c8"

# Determine which project to use (default: Suelo)
PROJECT_ID="${LINEAR_PROJECT_SUELO_ID}"

# Check if user explicitly requested a different project
if [[ "$USER_REQUEST" == *"mercury"* ]] || [[ "$USER_REQUEST" == *"Mercury"* ]]; then
  PROJECT_ID="${LINEAR_PROJECT_MERCURY_ID}"
elif [[ "$USER_REQUEST" == *"in the"*"project"* ]] || [[ "$USER_REQUEST" == *"put this in"* ]]; then
  # Extract project name from request - default remains Suelo unless explicitly changed
  : # Keep Suelo as default
fi
```

**Parse priority flag (if provided):**

```bash
# Check for --priority flag in user's request
PRIORITY=0  # Default: no priority

if [[ "$USER_REQUEST" == *"--priority urgent"* ]]; then
  PRIORITY=1
elif [[ "$USER_REQUEST" == *"--priority high"* ]]; then
  PRIORITY=2
elif [[ "$USER_REQUEST" == *"--priority medium"* ]]; then
  PRIORITY=3
elif [[ "$USER_REQUEST" == *"--priority low"* ]]; then
  PRIORITY=4
fi
```

**Create the issue:**

```bash
# Build issue body (Full Spec or Quick Issue format)
ISSUE_BODY=$(cat <<'EOF'
[Full spec or quick issue markdown content here]
EOF
)

# Create Linear issue (uses PROJECT_ID which defaults to Suelo)
RESULT=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"query\": \"mutation IssueCreate(\$input: IssueCreateInput!) { issueCreate(input: \$input) { success issue { id identifier title url } } }\",
    \"variables\": {
      \"input\": {
        \"title\": \"[TYPE]: Title here\",
        \"description\": \"$ISSUE_BODY\",
        \"teamId\": \"$LINEAR_TEAM_ID\",
        \"projectId\": \"$PROJECT_ID\",
        \"labelIds\": [\"$LINEAR_LABEL_CLAUDE_ID\"],
        \"priority\": $PRIORITY
      }
    }
  }")

# Check for success
if ! echo "$RESULT" | jq -e '.data.issueCreate.success' > /dev/null 2>&1; then
  echo "ERROR: Failed to create Linear issue"
  echo "$RESULT" | jq '.errors'
  exit 1
fi

# Extract issue details
ISSUE_ID=$(echo "$RESULT" | jq -r '.data.issueCreate.issue.id')
ISSUE_IDENTIFIER=$(echo "$RESULT" | jq -r '.data.issueCreate.issue.identifier')
ISSUE_URL=$(echo "$RESULT" | jq -r '.data.issueCreate.issue.url')
```

**Labels:** Linear issues are automatically tagged with the "claude" label. No need for additional label commands.

**Project:** Issues are automatically added to **Suelo project by default**. Only use Mercury or other projects if the user explicitly requests it.

### Step 6: Confirm to User

Show the user:
- Issue identifier created (e.g., `DEV-123`)
- Title
- Mode used (Full Spec or Quick Issue)
- Priority (if set)
- **Project: Added to Suelo project (default)** - or specify if different project was used
- Linear URL (clickable)
- Key acceptance criteria summary

**Example confirmation:**

```
Created Linear issue DEV-456 (Full Spec, Priority: High)

Title: [FEATURE]: Implement user authentication with email/password and Google OAuth
Added to Suelo project

View: https://linear.app/your-workspace/issue/DEV-456

Key acceptance criteria:
- Email/password account creation with validation
- Google OAuth integration
- Email verification flow
- Rate limiting on failed logins
- Comprehensive error handling

The agent will pick this up automatically from Linear.
```

## Integration with Agent Workflow

Issues created by this skill are designed for `.agent/run-tasks.sh` with Linear integration.

### Linear Workflow

1. **Task created**: Issue created in Linear with "claude" label, "Open" state, added to **Suelo project** (by default)
2. **Agent picks up task**: `.agent/run-tasks.sh` queries Linear for issues with "claude" label + "Open" state
3. **Agent marks in-progress**: State changes to "In Progress"
4. **Agent follows RPI workflow**: Research, Plan, Implement
5. **Agent completes**: State changes to "In Review" (human reviews and moves to "Done")

### Workflow State Mapping

| Linear State | Agent Status | Description |
|-------------|--------------|-------------|
| `Open` + "claude" label | Ready for pickup | Agent queries this state for new tasks |
| `In Progress` | Working | Agent is currently processing |
| `In Review` | Awaiting human review | Agent finished |
| `Done` | Completed | Human approved and closed (agent never moves here) |

### Priority Levels (Optional)

When using `--priority` flag:

| Priority | Linear Value | When to Use |
|----------|-------------|-------------|
| `urgent` | 1 | Critical bugs, production down, security issues |
| `high` | 2 | Important features, major bugs affecting users |
| `medium` | 3 | Standard features, minor bugs |
| `low` | 4 | Nice-to-haves, future improvements |

Priority doesn't affect agent pickup order (always processes oldest first by `createdAt`).

## Best Practices

1. **When in doubt, use Full Spec** - Over-specification is better than under-specification
2. **Be specific in acceptance criteria** - Each criterion should be verifiable as done/not done
3. **Reference actual files when possible** - Helps agent during research phase
4. **One concept per issue** - Split "add feature + refactor auth" into two issues
5. **Keep quick issues truly quick** - If it needs more than 3-5 acceptance criteria, use full spec
6. **Include error handling** - Even quick issues should consider failure cases

## Useful Commands

```bash
# Check Linear API connection
source .agent/linear-api.sh
linear_check_connection

# View ready issues in Linear
source .agent/linear-api.sh
linear_get_ready_issues

# Get Linear label and project IDs (one-time setup)
source .agent/linear-api.sh
linear_setup_cache

# View team info
source .agent/linear-api.sh
linear_get_teams

# View workflow states
source .agent/linear-api.sh
linear_get_team_states "$LINEAR_TEAM_ID"

# View team labels
source .agent/linear-api.sh
linear_get_team_labels "$LINEAR_TEAM_ID"

# Run the agent workflow (Linear mode)
.agent/run-tasks.sh --source linear

# Preview Linear issues without processing
.agent/run-tasks.sh --source linear --dry-run

# Open Linear workspace in browser
open "https://linear.app/your-workspace"
```
