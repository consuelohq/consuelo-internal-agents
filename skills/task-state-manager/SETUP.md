# Setup Guide - Task State Manager

## Prerequisites

1. **Linear Account** - You need a Linear workspace
2. **LangSmith Account** - Sign up at smith.langchain.com (free tier)
3. **Slack Webhook** - For notifications (optional but recommended)

## Step 1: Linear Setup

### Create API Key
1. Go to Linear → Settings → API
2. Create personal API key
3. Copy the key

### Create "Suelo Tasks" Project
Run this once to set up:

```python
from linear_client import LinearClient

client = LinearClient()
project = client.setup_project("Suelo Tasks")
print(f"Project ID: {project['id']}")
print(f"Project URL: {project['url']}")
```

### Get Team ID
```python
# Query your teams
query = """
query {
    teams {
        nodes {
            id
            name
        }
    }
}
"""
```

### Set Environment Variables
Add to `.env`:
```
LINEAR_API_KEY=your_key_here
LINEAR_SUelo_TEAM_ID=your_team_id
LINEAR_SUelo_PROJECT_ID=your_project_id
```

## Step 2: LangSmith Setup

### Create Project
1. Go to smith.langchain.com
2. Create project called "suelo-personal"
3. Get API key from settings

### Set Environment Variable
```
LANGSMITH_API_KEY=your_key_here
```

## Step 3: Test the Integration

```python
import asyncio
from task_manager import TaskStateManager

async def test():
    manager = TaskStateManager()
    
    # Create a task
    task = await manager.create_task(
        title="Test Instagram Scrape",
        description="Find 10 insurance agents on Instagram",
        estimated_duration="30 minutes"
    )
    
    print(f"Created task: {task.id}")
    print(f"Linear issue: {task.linear_issue_id}")
    
    # Update progress
    await manager.update_progress(
        task_id=task.id,
        current=5,
        total=10,
        current_step="Searching #finalexpense tags",
        note="Found 5 leads so far"
    )
    
    # Complete
    await manager.complete_task(
        task_id=task.id,
        deliverable="memory/outputs/test-leads.csv",
        summary="Found 10 leads, saved to CSV"
    )

asyncio.run(test())
```

## Step 4: Multi-Session Test

1. **Session A**: Start a long task
2. **Close chat**
3. **Session B**: Ask "what tasks are running?"
4. Should see the task from Session A

## Usage in Conversations

When I start a long task, I'll now:
1. Create Linear issue (visible in Linear app)
2. Start LangSmith trace (visible in LangSmith UI)
3. Update every 5-10 minutes
4. Complete and notify Slack

You can check status by:
- Asking me: "what tasks are running?"
- Looking in Linear app
- Viewing traces in LangSmith

## Troubleshooting

**Task not showing up in Linear?**
- Check LINEAR_SUelo_PROJECT_ID is set
- Verify API key has write access

**LangSmith traces not appearing?**
- Verify LANGSMITH_API_KEY
- Check project name matches "suelo-personal"

**Multi-session not working?**
- Linear is source of truth, not local cache
- Should work across any session
