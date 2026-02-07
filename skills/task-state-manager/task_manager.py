"""
Task State Manager - Core lifecycle for long-running tasks.

Integrates with Linear for persistence and LangSmith for tracing.
"""
import os
import json
from datetime import datetime
from typing import Optional, Dict, Any, List
from dataclasses import dataclass, asdict

@dataclass
class TaskProgress:
    current: int
    total: int
    percent: float
    current_step: str
    
@dataclass
class Task:
    id: str
    linear_issue_id: Optional[str]
    title: str
    description: str
    status: str  # pending | running | paused | completed | failed
    started_at: str
    last_update: str
    estimated_duration: Optional[str]
    progress: TaskProgress
    notes: List[Dict[str, str]]
    deliverable: Optional[str]
    langsmith_run_id: Optional[str]
    
    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Task':
        data['progress'] = TaskProgress(**data['progress'])
        return cls(**data)

class TaskStateManager:
    """
    Manages task lifecycle across multiple sessions.
    
    Key insight: Linear is the source of truth for task state.
    Local JSON is just a cache for fast lookups.
    """
    
    def __init__(self):
        self.cache_dir = "/Users/kokayi/.openclaw/workspace/memory/tasks/cache"
        os.makedirs(self.cache_dir, exist_ok=True)
        
        # Linear project ID for Suelo Tasks
        self.linear_project_id = os.getenv("LINEAR_SUelo_PROJECT_ID")
        
    async def create_task(
        self,
        title: str,
        description: str,
        estimated_duration: Optional[str] = None
    ) -> Task:
        """
        Create a new task in Linear and start LangSmith tracing.
        """
        task_id = f"task-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
        
        # 1. Create Linear issue
        linear_issue = await self._create_linear_issue(
            title=title,
            description=description
        )
        
        # 2. Start LangSmith run
        langsmith_run = await self._start_langsmith_trace(
            task_id=task_id,
            title=title
        )
        
        # 3. Create task object
        task = Task(
            id=task_id,
            linear_issue_id=linear_issue['id'],
            title=title,
            description=description,
            status="running",
            started_at=datetime.now().isoformat(),
            last_update=datetime.now().isoformat(),
            estimated_duration=estimated_duration,
            progress=TaskProgress(
                current=0,
                total=100,
                percent=0.0,
                current_step="Initializing"
            ),
            notes=[{
                "time": datetime.now().strftime("%H:%M"),
                "note": "Task created and started"
            }],
            deliverable=None,
            langsmith_run_id=langsmith_run['id']
        )
        
        # 4. Cache locally
        self._save_to_cache(task)
        
        # 5. Notify Slack
        await self._notify_slack_task_started(task)
        
        return task
    
    async def update_progress(
        self,
        task_id: str,
        current: int,
        total: int,
        current_step: str,
        note: Optional[str] = None
    ) -> Task:
        """
        Update task progress in Linear, LangSmith, and local cache.
        Call this every 5-10 minutes during long tasks.
        """
        task = self._load_from_cache(task_id)
        if not task:
            # Try to fetch from Linear
            task = await self._fetch_from_linear(task_id)
        
        if not task:
            raise ValueError(f"Task {task_id} not found")
        
        # Update progress
        task.progress.current = current
        task.progress.total = total
        task.progress.percent = (current / total) * 100 if total > 0 else 0
        task.progress.current_step = current_step
        task.last_update = datetime.now().isoformat()
        
        if note:
            task.notes.append({
                "time": datetime.now().strftime("%H:%M"),
                "note": note
            })
        
        # Update Linear
        await self._update_linear_issue(
            issue_id=task.linear_issue_id,
            progress=task.progress,
            note=note
        )
        
        # Update LangSmith
        await self._update_langsmith_trace(
            run_id=task.langsmith_run_id,
            progress=task.progress,
            note=note
        )
        
        # Update cache
        self._save_to_cache(task)
        
        return task
    
    async def complete_task(
        self,
        task_id: str,
        deliverable: Optional[str] = None,
        summary: Optional[str] = None
    ) -> Task:
        """
        Mark task as complete.
        """
        task = self._load_from_cache(task_id)
        if not task:
            task = await self._fetch_from_linear(task_id)
        
        task.status = "completed"
        task.last_update = datetime.now().isoformat()
        task.deliverable = deliverable
        task.progress.percent = 100.0
        task.progress.current_step = "Completed"
        
        # Update Linear
        await self._complete_linear_issue(
            issue_id=task.linear_issue_id,
            summary=summary or "Task completed"
        )
        
        # End LangSmith trace
        await self._end_langsmith_trace(
            run_id=task.langsmith_run_id,
            output=summary
        )
        
        # Update cache
        self._save_to_cache(task)
        
        # Notify Slack
        await self._notify_slack_task_completed(task)
        
        return task
    
    async def get_active_tasks(self) -> List[Task]:
        """
        Get all active tasks from Linear.
        This works from ANY session.
        """
        # Query Linear for issues in "In Progress" state
        linear_issues = await self._query_linear_active()
        
        tasks = []
        for issue in linear_issues:
            # Check cache first
            task = self._load_from_cache_by_linear_id(issue['id'])
            
            if not task:
                # Reconstruct from Linear
                task = await self._reconstruct_from_linear(issue)
            
            tasks.append(task)
        
        return tasks
    
    async def resume_task(self, task_id: str) -> Task:
        """
        Resume a task from any session.
        Fetches full state from Linear + LangSmith.
        """
        task = self._load_from_cache(task_id)
        
        if not task:
            task = await self._fetch_from_linear(task_id)
        
        if not task:
            raise ValueError(f"Task {task_id} not found")
        
        # Fetch LangSmith trace for context
        trace = await self._fetch_langsmith_trace(task.langsmith_run_id)
        
        # Return task + context so I can continue
        return task, trace
    
    # Private methods
    
    def _save_to_cache(self, task: Task):
        """Save task to local cache for fast lookups."""
        filepath = os.path.join(self.cache_dir, f"{task.id}.json")
        with open(filepath, 'w') as f:
            json.dump(task.to_dict(), f, indent=2)
    
    def _load_from_cache(self, task_id: str) -> Optional[Task]:
        """Load task from local cache."""
        filepath = os.path.join(self.cache_dir, f"{task_id}.json")
        if os.path.exists(filepath):
            with open(filepath, 'r') as f:
                return Task.from_dict(json.load(f))
        return None
    
    # Placeholder methods - will implement with actual API calls
    
    async def _create_linear_issue(self, title: str, description: str) -> Dict:
        """Create issue in Linear Suelo Tasks project."""
        # TODO: Implement Linear API call
        pass
    
    async def _start_langsmith_trace(self, task_id: str, title: str) -> Dict:
        """Start LangSmith run for tracing."""
        # TODO: Implement LangSmith API call
        pass
    
    async def _update_linear_issue(self, issue_id: str, progress: TaskProgress, note: Optional[str]):
        """Update Linear issue with progress."""
        pass
    
    async def _update_langsmith_trace(self, run_id: str, progress: TaskProgress, note: Optional[str]):
        """Add span to LangSmith trace."""
        pass
    
    async def _complete_linear_issue(self, issue_id: str, summary: str):
        """Mark Linear issue as done."""
        pass
    
    async def _end_langsmith_trace(self, run_id: str, output: str):
        """End LangSmith run."""
        pass
    
    async def _query_linear_active(self) -> List[Dict]:
        """Query Linear for active tasks."""
        pass
    
    async def _fetch_from_linear(self, task_id: str) -> Optional[Task]:
        """Fetch task state from Linear."""
        pass
    
    async def _reconstruct_from_linear(self, issue: Dict) -> Task:
        """Reconstruct task from Linear issue."""
        pass
    
    async def _fetch_langsmith_trace(self, run_id: str) -> Dict:
        """Fetch LangSmith trace for context."""
        pass
    
    async def _notify_slack_task_started(self, task: Task):
        """Send Slack notification."""
        pass
    
    async def _notify_slack_task_completed(self, task: Task):
        """Send Slack completion notification."""
        pass
