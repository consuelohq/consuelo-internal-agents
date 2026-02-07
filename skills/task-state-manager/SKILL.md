---
name: task-state-manager
description: Manages long-running tasks using Linear for persistence and LangSmith for observability. Multi-session aware - any chat can see and resume tasks.
---

# Task State Manager

Manages long-running tasks with proper state persistence across chat sessions.

## Problem Solved

- Tasks get lost when chats end or sessions change
- No visibility into progress of long-running work
- Can't resume interrupted tasks
- Multiple chat sessions don't share context

## Solution

Uses **Linear** as the source of truth for task state + **LangSmith** for execution tracing.

### Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Chat       │────▶│   Linear     │◀────│  Any Chat   │
│  Session 1  │     │   (State)    │     │  Session 2  │
└─────────────┘     └──────────────┘     └─────────────┘
        │                                    │
        ▼                                    ▼
┌─────────────────────────────────────────────────────┐
│              LangSmith (Tracing)                    │
│  - Every tool call logged                           │
│  - Full execution context                           │
│  - Debug failures                                   │
└─────────────────────────────────────────────────────┘
```

### Key Features

1. **Linear Issues** = Task state (Backlog → In Progress → Done)
2. **LangSmith Traces** = Execution details (every tool call, decision, error)
3. **Slack Notifications** = Real-time updates on progress
4. **Multi-Session** = Any chat can query/resume any task

## Usage

### When Starting a Long Task

I'll automatically:
1. Create Linear issue in "Suelo Tasks" project
2. Start LangSmith trace
3. Send Slack notification
4. Update every 5-10 minutes

### During Execution

Progress updates go to:
- Linear issue description (visible in Linear app)
- LangSmith trace (visible in smith.langchain.com)
- Slack message (if configured)

### When You Ask "Did You Finish?"

I'll:
1. Query Linear for active tasks
2. Show current status + progress
3. Provide link to full trace in LangSmith
4. Offer to resume if interrupted

## Setup Status

✅ **Linear**: Connected (Team: DEV, Project: Suelo Tasks)  
✅ **LangSmith**: API key configured  
⏳ **Testing**: Ready to test

## Quick Test

```bash
# Create a test task
curl -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "mutation { issueCreate(input: { title: \"[Suelo] My Task\" description: \"Testing...\" teamId: \"29f5c661-da6c-4bfb-bd48-815a006ccaac\" projectId: \"4ad23224-d294-42ac-a9c4-1f4ac943f6e3\" }) { success issue { id identifier title url } } }"}'
```

## Files

- `task_manager.py` - Core task lifecycle
- `linear_client.py` - Linear API wrapper  
- `langsmith_tracer.py` - Execution tracing
- `SETUP.md` - Setup instructions

## Projects

- **Linear**: "'suelo Tasks" (separate from Mercury coding tasks)
- **LangSmith**: "'suelo"
- **Slack**: #suelo

## Example Workflow

```
You: scrape 200 instagram leads for final expense agents

Me: 
1. Creates Linear issue: "[Suelo] Scrape 200 Instagram leads"
2. Starts LangSmith trace
3. Sends Slack: "Starting task: Scrape 200 Instagram leads"
4. Works on task, updates every 10 min

[Chat ends, 2 hours pass]

You: (new chat) did you finish that instagram task?

Me:
1. Queries Linear for active tasks
2. Finds the task, sees 145/200 completed
3. Shows: "Still running - 145/200 leads found (72%)"
4. Offers: "Continue working? View trace? Show results so far?"
```

## Benefits

✅ **Never lose track** - Linear is persistent  
✅ **Any session** - Query/resume from any chat  
✅ **Full visibility** - LangSmith shows every step  
✅ **Notifications** - Slack keeps you updated  
✅ **Debugging** - Traces show exactly what happened  

## Integration with Memory

This skill is referenced in `MEMORY.md` under Long-Running Task Tracking.

Before starting any task >10 minutes, I will:
1. Use this skill to create proper tracking
2. Update progress regularly
3. Mark complete when done

If you ask "did you finish that task?", I'll check Linear first.
