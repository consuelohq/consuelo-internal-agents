# Claude Agent Workflow Template

An autonomous AI agent workflow system for Claude Code that processes tasks from a queue, implements changes, runs quality gates, and creates pull requests automatically. 

Coding agent pro tip: use 1-3 times-daily by adding 10-20 (30?) tasks in the morning, afternoon, and evening and let Claude work for a few hours and your job becomes a decision maker and code reviewer, not code writer

COO: Works on a daily schedule so set it up once and improve as you see ways for your use case.

## What This Does

This workflow turns Claude Code into an autonomous coding agent that:

1. **Picks up tasks** from a Beads task queue
2. **Researches** the codebase to understand context
3. **Plans** implementation with file paths and steps
4. **Implements** changes following project patterns
5. **Reviews** its own code with automated quality checks
6. **Tests** changes with your test suite
7. **Creates PRs** with status indicators (passed/failed gates)
8. **Notifies** you via Slack (optional)

## The RPI Workflow

Every task follows the **Research-Plan-Implement** pattern:

```
Research (2-30 min)     Plan (2-15 min)         Implement (5-60 min)
├── Explore codebase     ├── Detailed steps      ├── Execute plan
├── Find patterns        ├── File paths          ├── Commit changes
└── Compress findings    └── Test strategy       └── Run quality gates
```

## Prerequisites

Before installing, ensure you have:

- **Node.js** (v18+) - `node --version`
- **Python** (3.9+) - `python3 --version`
- **jq** - JSON processor
  - macOS: `brew install jq`
  - Ubuntu/Debian: `apt install jq`
  - Windows: `choco install jq`
- **GitHub CLI** (`gh`) - `gh --version`
  - Install: https://cli.github.com
  - Auth: `gh auth login`
- **Claude Code CLI** - `claude --version`
  - Or **OpenCode** if using that instead
- **Beads CLI** (`bd`) - Task management
  - Install: https://github.com/steveyegge/beads
  - Or use pip: `pip install beads-cli`

## Copy into Claude Code for Easy Setup

```
I want to set up the Claude Agent Workflow from this repo. Please help me:

1. First, check which prerequisites I'm missing (node, python, jq, gh, claude/opencode, bd) and install any that are missing using the appropriate package manager for my system.

2. Clone https://github.com/kokayicobb/consuelo-internal-agents to a temporary location, then copy the .agent/ and .claude/ directories to my current project.

3. Initialize Beads in my project with `bd init`.

4. Update .agent/config.sh with my project's settings:
   - Set the correct BASE_BRANCH (check what my main branch is called)
   - Set TEST_COMMAND to whatever test command my project uses (check package.json or pyproject.toml)
   - Keep AGENT_CLI as "claude" unless I'm using opencode

5. Make all scripts executable.

6. Run .agent/init.sh to verify everything is set up correctly.

7. Walk me through setting up any optional integrations:
   - Slack notifications: Help me create a Slack webhook URL (guide me through Slack API → Create App → Incoming Webhooks) and add it to config.sh
   - GitHub CLI auth: Make sure `gh auth status` works, if not guide me through `gh auth login`
   - Any environment variables I need to set in ~/.zshrc or ~/.bashrc

8. Show me a summary of what was configured, what integrations are active, and how to create my first task with `bd create`.
```

## Quick Start

### Option 1: Clone and Install (Recommended)

```bash
# Clone the template
git clone https://github.com/kokayicobb/consuelo-internal-agents
cd claude-agent-workflow

# Copy to your project
cp -r .agent /path/to/your/project/
cp -r .claude /path/to/your/project/
cd /path/to/your/project

# Run the installer
chmod +x .agent/install.sh
.agent/install.sh
```

### Option 2: Manual Setup

1. Copy `.agent/` and `.claude/` directories to your project root
2. Edit `.agent/config.sh` with your settings
3. Run `bd init` to initialize Beads
4. Make scripts executable: `chmod +x .agent/*.sh .claude/hooks/**/*.sh`

## Configuration

Edit `.agent/config.sh` to customize for your project:

```bash
# Which AI CLI to use
AGENT_CLI="claude"           # or "opencode"

# Git settings
BASE_BRANCH="main"           # Branch for PRs (change to your main branch)
BRANCH_PREFIX="agent"        # Prefix for agent branches

# Testing
TEST_COMMAND="npm test"      # Your test command
RUN_TESTS_AFTER_TASK=true    # Run tests after each task

# Notifications (optional)
SLACK_WEBHOOK_URL=""         # Slack webhook for notifications
```

## Directory Structure

After installation, your project will have:

```
your-project/
├── .agent/
│   ├── config.sh            # Configuration settings
│   ├── init.sh              # Environment verification
│   ├── run-tasks.sh         # Main task runner
│   ├── append-research.sh   # Research note helper
│   ├── label-pr.sh          # PR labeling automation
│   ├── notify.sh            # Slack notifications + metrics
│   ├── prune-progress.sh    # Log maintenance
│   ├── human.md             # User guide
│   ├── claude-progress.txt  # Session history (auto-generated)
│   ├── metrics.json         # Task metrics (auto-generated)
│   └── research/
│       └── current-task.md  # Research notes (auto-generated)
│
├── .claude/
│   └── hooks/
│       ├── pre-tool-use/
│       │   ├── code-rules.sh     # Code quality checks
│       │   └── loop-detection.sh # Runaway loop prevention
│       ├── post-tool-use/
│       │   └── track-result.sh   # Success tracking
│       ├── session-end/
│       │   └── update-beads.sh   # Progress tracking
│       └── stop/
│           └── quality-gates.sh  # Test validation
│
└── .beads/                  # Beads task database (auto-created)
```

## Usage

### Daily Workflow

**Morning (CEO Mode - 15 mins):**
```bash
# Add tasks for the day
bd create "Fix 500 error when uploading large files"
bd create "Add CSV export for user data"
bd create "Optimize dashboard loading time"

# Launch the agent
.agent/run-tasks.sh --max-tasks 3
```

**During Day:**
- Agent works autonomously
- Check PR status: `gh pr list --head "agent/*"`
- You do other work

**Evening (CTO Mode - 30 mins):**
```bash
# Review PRs
gh pr list --state open

# For each PR
gh pr view <number>          # Read summary
gh pr diff <number>          # Check changes
gh pr merge <number> --squash

# Push to production when ready
git checkout main
git merge <your-base-branch>
git push origin main
```

### Command Reference

```bash
# Task Management
bd create "Task description"     # Add a task
bd list                          # List open tasks
bd show <task-id>                # Show task details
bd close <task-id>               # Close a task

# Running the Agent
.agent/run-tasks.sh                    # Process all open tasks
.agent/run-tasks.sh --max-tasks 3      # Process at most 3 tasks
.agent/run-tasks.sh --dry-run          # Preview without processing
.agent/run-tasks.sh --agent opencode   # Use OpenCode instead

# Utilities
.agent/init.sh                   # Check environment status
.agent/notify.sh --show-metrics  # View task metrics
.agent/prune-progress.sh         # Clean old progress entries
```

## Quality Gates

The workflow includes two automatic quality checks:

### 1. Code Review (runs before PR)
- Security issues (SQL injection, XSS, hardcoded secrets)
- Missing error handling
- Code pattern violations
- Up to 3 retry attempts if issues found

### 2. Test Suite (configurable)
- Runs your test command from `config.sh`
- Blocks PR if tests fail
- Captures test output for debugging

### PR Status Labels

PRs are automatically labeled based on quality gate results:

| Status | Meaning |
|--------|---------|
| Clean PR | Both gates passed, task auto-closed |
| `[TESTS FAILED]` | Code review passed, tests failed |
| `[REVIEW ISSUES]` | Tests passed, code review found problems |
| `[NEEDS REVIEW]` | Both gates failed |

## Customizing for Your Project

### Code Rules (Required)

Edit `.claude/hooks/pre-tool-use/code-rules.sh` to match your project:

```bash
# TODO: Add your project-specific rules
# Examples:
# - Required import patterns
# - Forbidden functions
# - Naming conventions
# - API usage patterns
```

### Area Labels

Edit `.agent/label-pr.sh` to define your project's file areas:

```bash
# TODO: Update these patterns for your project
# Default patterns check for:
# - src/     -> area/frontend
# - app/     -> area/backend
# - e2e/     -> area/tests
# Add your own area patterns
```

### Notifications

Set up Slack notifications (optional):

```bash
# Add to ~/.zshrc or ~/.bashrc
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T.../B.../..."
```

## Hooks Reference

### Pre-tool-use Hooks
Run BEFORE Claude executes a tool:

- **code-rules.sh** - Validates code changes against project rules
- **loop-detection.sh** - Prevents agent from retrying failed commands

### Post-tool-use Hooks
Run AFTER Claude executes a tool:

- **track-result.sh** - Tracks command success to reset loop detection

### Session-end Hooks
Run when Claude session ends:

- **update-beads.sh** - Updates task status and progress log

### Stop Hooks
Run before allowing task completion:

- **quality-gates.sh** - Runs tests and validates changes

## Troubleshooting

### Agent stuck in a loop
The loop detection hook prevents this by:
1. Tracking consecutive command attempts
2. Blocking after 3 failed attempts
3. Instructing agent to skip to next task

### Tests timing out
Edit `.claude/hooks/stop/quality-gates.sh`:
```bash
TEST_TIMEOUT=120  # Increase timeout in seconds
```

### Hooks not running
1. Check executable permissions: `chmod +x .claude/hooks/**/*.sh`
2. Verify jq is installed: `jq --version`
3. Check hook output: Run hook manually with sample input

### No Beads tasks found
1. Verify Beads is initialized: `bd list`
2. Create a test task: `bd create "Test task"`
3. Check task status: Tasks must be "open" or "pending"

## Advanced Configuration

### Running Overnight (Cron)

```bash
# Edit crontab
crontab -e

# Add (runs at 2 AM daily)
0 2 * * * cd /path/to/your/project && .agent/run-tasks.sh --max-tasks 5 >> agent.log 2>&1
```

### Multiple Projects

Each project needs its own:
- `.agent/config.sh` with project-specific settings
- `.beads/` database (run `bd init` in each project)
- Customized code rules in `.claude/hooks/`

### Integrating with CI/CD

The workflow integrates with GitHub Actions via PR labels:
- `agent-generated` - All agent PRs
- `tests-passed` / `tests-failed` - Gate status
- `review-passed` / `review-failed` - Review status

Use these labels in CI workflows to customize behavior.

## Session Continuity

The agent maintains context across sessions via:

- **`.agent/claude-progress.txt`** - Session history (last 6 hours)
- **`.agent/research/current-task.md`** - Research notes per task
- **`.agent/metrics.json`** - Daily task metrics

Progress is automatically pruned after 6 hours to keep context manageable.

## COO Agent Template

In addition to the development-focused agent workflow, this repository includes a **COO (Chief Operating Officer) Agent** template for autonomous GTM and business automation tasks.

### What the COO Agent Does

The COO agent handles marketing and sales operations on a schedule:

- **Morning Research** - Prospect research and lead gathering
- **Email Generation** - Personalized cold outreach drafts
- **Twitter Content** - Posts, threads, and engagement content
- **Lead Processing** - Dialer lists and CRM-ready exports
- **Metrics Tracking** - Daily activity and performance metrics

### Key Features

- **Scheduled Automation** - macOS launchd runs tasks at optimal times
- **Two-Session Workflow** - Worker generates, QA validates before sending
- **Email Warm-Up** - Gradual volume increase (10→100 emails over 14 days)
- **Separate Task Queue** - COO Beads instance keeps business tasks separate from dev tasks

### Quick Start

```bash
# Copy COO template to your project
cp -r .coo /path/to/your/project/

# Configure
cd /path/to/your/project
vim .coo/agent/config.sh  # Set PROJECT_ROOT

# Create your business context
cp .coo/docs/BUSINESS_CONTEXT_TEMPLATE.md .coo/docs/BUSINESS_CONTEXT.md
vim .coo/docs/BUSINESS_CONTEXT.md  # Fill in your business details

# Install launchd schedules
.coo/agent/launchd/install-launchd.sh

# Initialize Beads (separate from dev tasks)
bd-coo init
```

### Documentation

- **[.coo/README.md](.coo/README.md)** - Full overview and architecture
- **[.coo/CUSTOMIZATION.md](.coo/CUSTOMIZATION.md)** - Step-by-step setup guide
- **[.coo/CLAUDE.md](.coo/CLAUDE.md)** - Agent instructions and workflow

### Schedule (Default)

| Time | Task |
|------|------|
| 7:00 AM | Morning research |
| 7:45 AM | Generate email drafts |
| 8:00 AM | Twitter post #1 |
| 9:00 AM | Instagram prospects |
| 12:00 PM | Twitter post #2 |
| 12:30 PM | Dialer leads |
| 4:00 PM | Update metrics |
| 4:30 PM (Tue/Thu) | Twitter thread |
| 5:00 PM | Twitter post #3 |

Customize schedules in `.coo/agent/launchd/*.plist` files.

---

## Contributing

Contributions welcome! Please:
1. Fork this repository
2. Create a feature branch
3. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Credits

Built for use with:
- [Claude Code](https://claude.ai/claude-code) by Anthropic
- [Beads](https://github.com/steveyegge/beads) task management
- [GitHub CLI](https://cli.github.com)
