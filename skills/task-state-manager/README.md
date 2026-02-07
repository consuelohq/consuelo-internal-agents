# Task State Manager

Manages long-running tasks using Linear for persistence and LangSmith for observability.

## Problem Solved
- Tasks get lost across chat sessions
- No visibility into what I'm working on
- Can't resume interrupted work
- Multiple chats don't share state

## Architecture

```
User Request
    ↓
Create Linear Issue (Suelo Tasks project)
    ↓
Start LangSmith Run (tracing)
    ↓
Work on Task (with progress updates)
    ↓
Update Linear + LangSmith every 5 min
    ↓
Complete → Mark done, notify Slack
```

## Linear Setup

Project: **"Suelo Tasks"** (separate from Mercury coding tasks)
States: Backlog → In Progress → Done

## LangSmith Setup

Project: **"suelo-personal"**
Traces every tool call, decision, and progress update

## Multi-Session Support

Any session can:
1. Query Linear for active tasks
2. Resume a task by ID
3. See full history via LangSmith traces

## Files

- `task_manager.py` - Core task lifecycle
- `linear_client.py` - Linear API wrapper
- `langsmith_tracer.py` - Observability
- `slack_notifier.py` - Progress notifications

## Usage

```python
# Start task
task = await task_manager.create_task(
    title="Scrape 200 Instagram leads",
    description="Find final expense insurance agents",
    estimated_duration="2 hours"
)

# Update progress
await task.update_progress(45, 200, "Rate limited, waiting 60s")

# Complete
await task.complete(deliverable="memory/outputs/leads.csv")
```
