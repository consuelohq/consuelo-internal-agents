"""
Light Task Manager - Session-scoped task tracking for LibreChat
Shows task list at start, updates as complete, shows checked at end.
"""

import json
import os
from datetime import datetime
from typing import List, Optional

TASKS_DIR = os.path.expanduser("~/.openclaw/workspace/memory/tasks")


def _get_session_file():
    """Get the session-specific task file."""
    # In OpenClaw, we can use an env var or generate from context
    # For now, use timestamp-based session ID that's stored for the session
    session_id = os.environ.get('OPENCLAW_SESSION_ID', 'default')
    return os.path.join(TASKS_DIR, f"{session_id}.json")


def _ensure_dir():
    """Ensure tasks directory exists."""
    os.makedirs(TASKS_DIR, exist_ok=True)


def _load_tasks():
    """Load current session tasks."""
    _ensure_dir()
    filepath = _get_session_file()
    if os.path.exists(filepath):
        with open(filepath, 'r') as f:
            return json.load(f)
    return {"tasks": [], "session_started": datetime.now().isoformat()}


def _save_tasks(data):
    """Save current session tasks."""
    filepath = _get_session_file()
    with open(filepath, 'w') as f:
        json.dump(data, f, indent=2)


def task_start(tasks: List[str]) -> str:
    """
    Start a task list. Shows unchecked tasks immediately.
    
    Args:
        tasks: List of task descriptions
        
    Returns:
        Markdown string showing the task list
    """
    data = {
        "tasks": [{"description": t, "status": "pending", "started_at": None, "completed_at": None} for t in tasks],
        "session_started": datetime.now().isoformat(),
        "last_updated": datetime.now().isoformat()
    }
    _save_tasks(data)
    
    # Return formatted markdown
    lines = ["**Task List:**"]
    for task in data["tasks"]:
        lines.append(f"- [ ] {task['description']}")
    return "\n".join(lines)


def task_done(description: str) -> str:
    """
    Mark a task as done. Can be called multiple times.
    
    Args:
        description: Task description (partial match works)
        
    Returns:
        Empty string (silent update to JSON)
    """
    data = _load_tasks()
    now = datetime.now().isoformat()
    
    # Find and update the task (partial match)
    for task in data["tasks"]:
        if description.lower() in task["description"].lower() and task["status"] != "done":
            task["status"] = "done"
            task["completed_at"] = now
            if not task["started_at"]:
                task["started_at"] = data["session_started"]
            break
    
    data["last_updated"] = now
    _save_tasks(data)
    return ""  # Silent


def task_end() -> str:
    """
    End the task session. Shows all tasks as checked.
    Moves to completed.json for history.
    
    Returns:
        Markdown string showing completed task list
    """
    data = _load_tasks()
    now = datetime.now().isoformat()
    
    # Mark any remaining as done
    for task in data["tasks"]:
        if task["status"] != "done":
            task["status"] = "done"
            task["completed_at"] = now
    
    data["session_ended"] = now
    
    # Save to completed history
    completed_file = os.path.join(TASKS_DIR, "completed.json")
    completed = []
    if os.path.exists(completed_file):
        with open(completed_file, 'r') as f:
            completed = json.load(f)
    
    completed.append(data)
    
    # Keep only last 100 sessions
    if len(completed) > 100:
        completed = completed[-100:]
    
    with open(completed_file, 'w') as f:
        json.dump(completed, f, indent=2)
    
    # Remove active session file
    session_file = _get_session_file()
    if os.path.exists(session_file):
        os.remove(session_file)
    
    # Return formatted markdown
    lines = ["**Task List:**"]
    for task in data["tasks"]:
        lines.append(f"- [x] {task['description']}")
    return "\n".join(lines)


def get_active_tasks() -> Optional[dict]:
    """
    Get current active tasks for this session.
    
    Returns:
        Task data or None if no active session
    """
    filepath = _get_session_file()
    if os.path.exists(filepath):
        with open(filepath, 'r') as f:
            return json.load(f)
    return None


# Convenience function for automatic detection
def should_use_task_list(tasks_or_description) -> bool:
    """
    Check if we should use task list (2+ items).
    
    Args:
        tasks_or_description: List of tasks or string description
        
    Returns:
        True if 2+ items detected
    """
    if isinstance(tasks_or_description, list):
        return len(tasks_or_description) >= 2
    # If it's a string with "and" or commas, probably multiple tasks
    if isinstance(tasks_or_description, str):
        text = tasks_or_description.lower()
        indicators = [' and ', ', then ', ', after ', '\n', 'first', 'second', 'next']
        return any(ind in text for ind in indicators)
    return False
