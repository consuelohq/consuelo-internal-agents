# Agent Workflow User Guide

## The Big Picture

You've set up an autonomous task execution system with these parts:

1. **Beads** - Task queue (like a GitHub-native Jira)
2. **run-tasks.sh** - The autonomous runner that processes tasks one by one
3. **Claude/OpenCode** - The AI workers that actually write code
4. **RPI Workflow** - Research → Plan → Implement (prevents bad code)
5. **Quality Gates** - Code review + tests (prevents bad PRs)
6. **GitHub PRs** - The review interface for you

The workflow is:
```
You add tasks → Agent picks them up → Code review → Tests → PR → You review → Merge
```

---

## How to Use It Effectively

### Morning (CEO Mode - 15 mins)

```bash
# 1. Add tasks for things you want done
bd create "Fix 500 error when uploading large files"
bd create "Add export to CSV for reports"
bd create "Optimize page loading time"

# 2. Launch the agent (or schedule it to run overnight)
.agent/run-tasks.sh --max-tasks 3
```

The agent will:
- Pick up each task
- Research the codebase
- Create a plan
- Implement the code
- Run code review (automated quality gate)
- Run your tests
- Create a PR to your base branch

### Day (CEO Mode - ignore it)

Let the agent work. You can:
- Check PR status: `gh pr list --head "agent/*"`
- Monitor progress in real-time
- Go do other work (sales, meetings, strategy)

### Evening (CTO Mode - 30-60 mins)

```bash
# 1. Review PRs
gh pr list  # See what the agent did

# 2. Quick review of changes
gh pr view <number>  # Read the diff

# 3. If good: merge
gh pr merge <number> --squash

# 4. When ready for prod: merge to main
git checkout main
git merge <your-base-branch>
git push origin main
```

**Key insight**: You're doing strategic reviews, not writing code. The agent handles 80-90% of the work.

---

## Quality Gates (Your Safety Net)

The system has two automatic quality checks before it even creates a PR:

### 1. Code Review
- Runs Claude to check for:
  - Security issues (SQL injection, XSS)
  - Missing error handling
  - Breaking API changes
  - Obvious bugs or logic errors
- If it fails, creates follow-up Beads tasks automatically
- Retries up to 3 times

### 2. Tests
- Runs your configured test command
- If tests fail, the PR gets labeled `[TESTS FAILED]`
- You can see which specific test failed

### PR Status Indicators

- ✅ Clean PR (review + tests passed) → Auto-closes task
- ⚠️ `[TESTS FAILED]` → You review test output
- ⚠️ `[REVIEW ISSUES]` → Automated code review found problems
- ❌ `[NEEDS REVIEW]` → Both failed (rare)

---

## The RPI Workflow (Why It Works)

The agent follows this for every task:

### 1. Research (10-30 mins)
- Explores relevant code files
- Finds existing patterns to follow
- Writes findings to `.agent/research/current-task.md`
- Compresses knowledge so context stays lean

### 2. Plan (5-15 mins)
- Creates detailed implementation plan
- Includes file paths and line numbers
- Specifies tests for each change

### 3. Implement (20-60 mins)
- Executes plan step-by-step
- Commits frequently with good messages
- Runs tests after each change
- Updates tracking files

**Total time per task**: ~30-90 mins (vs 2-4 hours for humans)

---

## Your Optimal Workflow

### Automation Setup (One-time)

```bash
# Schedule agent to run overnight (cron on macOS/Linux)
crontab -e
# Add: 0 2 * * * cd /path/to/your/project && .agent/run-tasks.sh --max-tasks 5

# Or use launchd on macOS for better control
```

### Daily Cycle

**Morning (7:00 AM - 7:15 AM):**
```bash
# Add tasks you want done today
bd create "Feature: Add analytics for page views"
bd create "Bug: Fix mobile layout on Settings page"
bd create "Refactor: Extract duplicate validation logic"

# Launch agent before leaving for meetings
nohup .agent/run-tasks.sh --max-tasks 3 > agent.log 2>&1 &
```

**During Day:**
- Agent works autonomously
- You get notified when PRs are created (GitHub)
- Quick scan: PR looks good? Ignore until evening.

**Evening (6:00 PM - 7:00 PM):**
```bash
# Review PRs
gh pr list --state open --base <your-base-branch>

# For each PR
gh pr view <number>          # Read summary
gh pr diff <number>         # Check changes
gh pr checks <number>       # See test results

# If good
gh pr merge <number> --squash
```

**Weekly (Sunday evening):**
```bash
# Merge to main (push to prod)
git checkout main
git pull origin main
git merge <your-base-branch>
git push origin main
```

---

## Pro Tips

### 1. Task Writing Best Practices
- ✅ "Add export to CSV for call history" (specific, testable)
- ❌ "Improve call history" (too vague)
- Include requirements: "Support 1000+ rows, filter by date range"
- Prioritize: Start with bugs, then features

### 2. Let It Fail Gracefully
- Code review failures auto-create follow-up tasks
- Tests failing? Review output, add test-fixing task
- The system is designed to learn from failures

### 3. Review Efficiency
- Clean PRs (both gates passed) → 2-minute review, merge
- Test failures only → Check test file, fix test, re-run
- Review issues only → Agent already flagged the problem, just verify

### 4. Trust the System
- The code review catches 90% of mistakes
- Tests catch functional issues
- You only review high-level correctness, not syntax

### 5. Scale Up
- Add 5-10 tasks in morning
- Run agent with `--max-tasks 5`
- By evening: 3-5 PRs ready to review
- You've gained 15-20 hours of coding time

---

## Command Reference

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

---

## How to Start Right Now

```bash
# 1. Check if there are open tasks
bd list

# 2. Add a test task to see it work
bd create "Test task: Add a hello world endpoint at /api/hello"

# 3. Run the agent
.agent/run-tasks.sh --max-tasks 1

# 4. Watch it work (you'll see the RPI workflow in action)
# Then check: gh pr list

# 5. Review and merge
gh pr view <number>
gh pr merge <number> --squash
```

Once you see it work once, you'll trust it. Then you can add real tasks and let it run while you focus on other things.

---

## The Magic Part

The system does something most AI agents can't:

1. **Context Management** - Stays in "smart zone" by compressing research
2. **Quality Gates** - Doesn't just trust itself, verifies work
3. **Failure Recovery** - When it fails, it creates tasks to fix itself
4. **Session Continuity** - `claude-progress.txt` remembers everything across runs

You're effectively getting a junior engineer who:
- Works 24/7
- Never forgets anything
- Runs code review on their own code
- Writes tests before deploying
- Learns from mistakes
