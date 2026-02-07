# Task Tracking System

## How It Works

For any task that takes >10 minutes or spans multiple sessions:

1. **Create task entry** in `active.json` immediately
2. **Update every 5-10 min** with progress
3. **Mark complete** → move to `completed.json`
4. **If interrupted** → status stays, user can ask for resume

## Task Entry Format

```json
{
  "task_id": "{type}-{YYYYMMDD}-{seq}",
  "type": "instagram_lead_scraper|web_research|code_review|etc",
  "description": "human readable description",
  "status": "pending|running|paused|completed|failed",
  "priority": "low|medium|high|urgent",
  "started_at": "ISO timestamp",
  "last_update": "ISO timestamp",
  "estimated_completion": "ISO timestamp (optional)",
  "progress": {
    "current": 45,
    "total": 200,
    "percent": 22.5,
    "current_step": "what i'm doing right now"
  },
  "notes": [
    {"time": "23:45", "note": "started"},
    {"time": "23:50", "note": "hit rate limit, waiting"}
  ],
  "deliverable": "path/to/output/file",
  "session_key": "librechat:conversation_id" 
}
```

## User Queries

When user asks:
- "did you finish that task?" → check active.json, give status
- "what were you working on?" → show last 3 tasks
- "resume the lead scraping" → find task, check status, continue

## Important

- ALWAYS write task entry BEFORE starting work
- ALWAYS update progress during long operations
- If i get cut off, status stays "running" - user can resume
