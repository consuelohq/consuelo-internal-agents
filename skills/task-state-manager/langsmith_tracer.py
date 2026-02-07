"""
LangSmith Tracer for Task State Manager - Fixed Version.

Usage:
    tracer = TaskTracer()
    run_id = tracer.start_task_trace("task-123", "Scrape leads", "Find insurance agents")
    tracer.log_tool_call(run_id, "web_search", {"query": "agents"}, "results...")
    tracer.end_task_trace(run_id, "completed", {"found": 50})
"""
import os
from typing import Dict, Optional, Any
from langsmith import Client
from langsmith.run_trees import RunTree

class TaskTracer:
    """
    Traces task execution using LangSmith.
    """
    
    def __init__(self, project_name: Optional[str] = None):
        # Load from env if not provided
        self.project_name = project_name or os.getenv("LANGSMITH_PROJECT", "'suelo")
        
        # Ensure API key is set
        api_key = os.getenv("LANGSMITH_API_KEY")
        if not api_key:
            raise ValueError("LANGSMITH_API_KEY not set in environment")
        
        # Initialize client
        try:
            self.client = Client(api_key=api_key)
            print(f"[TaskTracer] Connected to LangSmith project: {self.project_name}")
        except Exception as e:
            print(f"[TaskTracer] Error connecting to LangSmith: {e}")
            raise
        
    def start_task_trace(
        self,
        task_id: str,
        task_title: str,
        task_description: str
    ) -> str:
        """
        Start a new trace for a task.
        """
        try:
            run_tree = RunTree(
                name=f"Task: {task_title}",
                run_type="chain",
                inputs={
                    "task_id": task_id,
                    "description": task_description
                },
                project_name=self.project_name,
                metadata={
                    "task_type": "long_running",
                    "started_by": "suelo",
                    "started_at": datetime.now().isoformat()
                }
            )
            
            run_tree.post()
            print(f"[TaskTracer] Started trace: {run_tree.id}")
            return run_tree.id
            
        except Exception as e:
            print(f"[TaskTracer] Error starting trace: {e}")
            # Return a dummy ID so execution continues
            return f"error-{task_id}"
    
    def log_step(
        self,
        run_id: str,
        step_name: str,
        inputs: Dict[str, Any],
        outputs: Dict[str, Any],
        progress_percent: float = 0
    ):
        """Log a step in the task execution."""
        try:
            child_run = RunTree(
                name=step_name,
                run_type="tool",
                inputs=inputs,
                outputs=outputs,
                parent_run_id=run_id,
                project_name=self.project_name,
                metadata={"progress_percent": progress_percent}
            )
            child_run.post()
            child_run.end()
        except Exception as e:
            print(f"[TaskTracer] Error logging step: {e}")
    
    def log_tool_call(
        self,
        run_id: str,
        tool_name: str,
        tool_input: Dict[str, Any],
        tool_output: Any,
        error: Optional[str] = None
    ):
        """Log a specific tool call."""
        try:
            child_run = RunTree(
                name=f"tool:{tool_name}",
                run_type="tool",
                inputs=tool_input,
                outputs={"result": str(tool_output)[:1000], "error": error},  # Truncate long outputs
                parent_run_id=run_id,
                project_name=self.project_name
            )
            child_run.post()
            child_run.end()
        except Exception as e:
            print(f"[TaskTracer] Error logging tool: {e}")
    
    def end_task_trace(
        self,
        run_id: str,
        status: str,
        outputs: Dict[str, Any],
        error: Optional[str] = None
    ):
        """End the task trace."""
        try:
            # For RunTree, we need to get the original run and end it
            # Since we don't store the RunTree object, we'll create a minimal end record
            end_run = RunTree(
                name="task_end",
                run_type="tool",
                inputs={},
                outputs={"status": status, **outputs, "error": error},
                parent_run_id=run_id,
                project_name=self.project_name
            )
            end_run.post()
            end_run.end()
            print(f"[TaskTracer] Ended trace: {run_id}")
        except Exception as e:
            print(f"[TaskTracer] Error ending trace: {e}")
    
    def get_run_url(self, run_id: str) -> str:
        """Get URL to view trace."""
        import urllib.parse
        # URL encode the project name properly
        project = urllib.parse.quote(self.project_name, safe='')
        return f"https://smith.langchain.com/projects/{project}/runs/{run_id}"


# Simple test function
def test_langsmith():
    """Test LangSmith connection."""
    import os
    from datetime import datetime
    
    # Load env vars
    env_file = "/Users/kokayi/.openclaw/workspace/.env.suelo"
    if os.path.exists(env_file):
        with open(env_file) as f:
            for line in f:
                if '=' in line and not line.startswith('#'):
                    key, value = line.strip().split('=', 1)
                    os.environ[key] = value
    
    print("Testing LangSmith connection...")
    print(f"API Key: {os.getenv('LANGSMITH_API_KEY', 'NOT SET')[:20]}...")
    print(f"Project: {os.getenv('LANGSMITH_PROJECT', 'NOT SET')}")
    
    try:
        tracer = TaskTracer()
        run_id = tracer.start_task_trace(
            "test-task-001",
            "Test Task",
            "Testing LangSmith integration"
        )
        
        tracer.log_tool_call(
            run_id,
            "web_search",
            {"query": "test"},
            "test results"
        )
        
        tracer.end_task_trace(
            run_id,
            "completed",
            {"test": True}
        )
        
        url = tracer.get_run_url(run_id)
        print(f"\n✅ Success! View trace at:")
        print(f"   {url}")
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    test_langsmith()
