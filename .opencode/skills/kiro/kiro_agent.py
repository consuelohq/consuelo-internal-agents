#!/usr/bin/env python3
"""
Kiro Agent Orchestrator — spawn and manage Kiro ACP coding sessions.

This is the bridge between OpenCode (orchestrator) and Kiro (coder).
OpenCode calls this to:
  1. Start a Kiro session with a coding task
  2. Monitor progress (streaming tool calls and updates)
  3. Detect whether Kiro created specs or coded
  4. Report results back

Usage:
    from kiro_agent import KiroSession

    session = KiroSession(cwd="/path/to/project")
    session.start()
    result = session.run_task(
        task_description="implement user auth",
        branch_name="remote/consuelo-a3f2--user-auth",
    )
    session.stop()
"""

import os
import sys
import re
import json
import time
from typing import Optional, Dict, List, Any, Callable

# Add sibling skill directories to path
SKILL_DIR = os.path.dirname(os.path.abspath(__file__))
SKILLS_ROOT = os.path.dirname(SKILL_DIR)
sys.path.insert(0, os.path.join(SKILLS_ROOT, "kiro-acp"))
sys.path.insert(0, os.path.join(SKILLS_ROOT, "github-dev"))

from client import KiroACP

# Paths
GITHUB_DEV = os.path.join(SKILLS_ROOT, "github-dev", "dev")
LINEAR_HELPER = os.path.join(SKILL_DIR, "linear_helper.py")

DEFAULT_CWD = "/Users/kokayi/Dev/consuelo_on_call_coaching"
DEFAULT_REPO = "kokayicobb/consuelo_on_call_coaching"


def build_kiro_prompt(
    task_description: str,
    branch_name: str,
    linear_spec: Optional[str] = None,
    linear_task_id: Optional[str] = None,
    error_context: Optional[str] = None,
) -> str:
    """Build the prompt that gets sent to Kiro for coding."""

    parts = []

    parts.append("You are coding a feature for the Consuelo project (on-call coaching platform).")
    parts.append("")

    # error context for retry flows
    if error_context:
        parts.append("## Previous Deploy Failure")
        parts.append("The previous deploy of this branch failed with this error:")
        parts.append(f"```\n{error_context}\n```")
        parts.append("Fix the issue on the existing branch and commit the fix.")
        parts.append("")

    # task description
    parts.append("## Task")
    parts.append(task_description)
    parts.append("")

    # linear spec if provided
    if linear_spec:
        parts.append("## Linear Task Spec")
        parts.append(linear_spec)
        parts.append("")

    if linear_task_id:
        parts.append(f"**Linear Task ID:** {linear_task_id}")
        parts.append("")

    # branch
    parts.append("## Working Branch")
    parts.append(f"You are working on branch: `{branch_name}`")
    parts.append("A github-dev session is already active for this branch.")
    parts.append("")

    # instructions for github-dev usage
    parts.append("## How to Read/Write Code")
    parts.append("")
    parts.append("You MUST use the github-dev CLI for ALL file operations. Do NOT use your")
    parts.append("built-in file edit tools for the repo — all code changes must go through the GitHub API.")
    parts.append("")
    parts.append("### Read a file")
    parts.append(f"```bash\npython3 {GITHUB_DEV} read <path>\n```")
    parts.append("")
    parts.append("### List a directory")
    parts.append(f"```bash\npython3 {GITHUB_DEV} ls <path>\n```")
    parts.append("")
    parts.append("### View file tree")
    parts.append(f"```bash\npython3 {GITHUB_DEV} tree <optional_prefix>\n```")
    parts.append("")
    parts.append("### Write a file (stage for commit)")
    parts.append("Write content to a temp file first, then stage it:")
    parts.append("```bash")
    parts.append("cat > /tmp/kiro-edit.tsx << 'KIROEOF'")
    parts.append("... your code here ...")
    parts.append("KIROEOF")
    parts.append(f"python3 {GITHUB_DEV} write src/path/to/file.tsx --content-file /tmp/kiro-edit.tsx")
    parts.append("```")
    parts.append("")
    parts.append("### Commit staged changes")
    parts.append(f'```bash\npython3 {GITHUB_DEV} commit "feat: description of changes"\n```')
    parts.append("")
    parts.append("### Check what\'s staged / session status")
    parts.append(f"```bash\npython3 {GITHUB_DEV} staged\npython3 {GITHUB_DEV} status\n```")
    parts.append("")

    # complexity decision
    parts.append("## Complexity Decision")
    parts.append("")
    parts.append("Evaluate this task before starting:")
    parts.append("")
    parts.append("**If this task is complex** (needs multiple PRs, architectural decisions,")
    parts.append("involves many interconnected changes, or needs a detailed spec):")
    parts.append(f"1. Create Linear issues for each piece of work:")
    parts.append(f'   ```bash\n   python3 {LINEAR_HELPER} create --title "Issue title" --description "Full description" --label kiro\n   ```')
    parts.append("2. Report what specs you created (list the issue titles)")
    parts.append("3. **STOP** — do not code anything")
    parts.append("")
    parts.append("**If this task is straightforward:**")
    parts.append("1. Read the relevant code to understand the codebase")
    parts.append("2. Plan your changes")
    parts.append("3. Write the code using the github-dev commands above")
    parts.append("4. Commit with descriptive conventional commit messages (feat:, fix:, refactor:, etc.)")
    parts.append("5. Report what you changed and why — list all files changed/created")
    parts.append("")

    # rules
    parts.append("## Rules")
    parts.append("- Use conventional commit messages (feat:, fix:, refactor:, chore:, etc.)")
    parts.append("- Write clean, production-ready code")
    parts.append("- Add comments for complex logic")
    parts.append("- Do NOT delete files unless the task specifically requires it")
    parts.append("- If you're unsure, implement the most reasonable approach")
    parts.append("- You can do multiple write+commit cycles for logical groupings")
    parts.append("- When done, provide a summary of all changes")

    return "\n".join(parts)


class KiroSession:
    """Manages a single Kiro ACP coding session."""

    def __init__(
        self,
        cwd: str = DEFAULT_CWD,
        repo: str = DEFAULT_REPO,
        on_progress: Optional[Callable[[str], None]] = None,
        timeout: int = 14400,  # 4 hours default
    ):
        self.cwd = cwd
        self.repo = repo
        self.on_progress = on_progress or (lambda msg: print(f"[kiro] {msg}"))
        self.timeout = timeout
        self.kiro: Optional[KiroACP] = None

        # session results
        self.created_specs: List[str] = []
        self.files_changed: List[str] = []
        self.commits_made: List[str] = []
        self.kiro_response: str = ""
        self.session_type: Optional[str] = None  # "specs" or "code"

    def start(self) -> None:
        """Start the Kiro ACP session."""
        self.on_progress("spawning kiro acp session...")
        self.kiro = KiroACP(cwd=self.cwd)
        self.kiro.start()
        self.on_progress(f"kiro session started: {self.kiro.session_id}")

    def stop(self) -> None:
        """Stop the Kiro ACP session."""
        if self.kiro:
            self.kiro.stop()
            self.on_progress("kiro session stopped")

    def run_task(
        self,
        task_description: str,
        branch_name: str,
        linear_spec: Optional[str] = None,
        linear_task_id: Optional[str] = None,
        error_context: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Send a coding task to Kiro and monitor until completion.

        Returns:
            dict with keys:
            - type: "specs" or "code"
            - response: Kiro's full text response
            - specs_created: list of Linear issue titles (if type=specs)
            - files_changed: list of file paths (if type=code)
            - commits: list of commit messages (if type=code)
        """
        if not self.kiro:
            raise RuntimeError("Session not started. Call start() first.")

        # build the prompt
        prompt = build_kiro_prompt(
            task_description=task_description,
            branch_name=branch_name,
            linear_spec=linear_spec,
            linear_task_id=linear_task_id,
            error_context=error_context,
        )

        self.on_progress("sending task to kiro...")
        self.on_progress(f"branch: {branch_name}")

        # stream the response and monitor
        full_response = []
        tool_calls = []

        for chunk in self.kiro.prompt_stream(prompt):
            if not isinstance(chunk, dict):
                continue

            chunk_type = chunk.get("type", "")

            if chunk_type == "AgentMessageChunk":
                text = self.kiro._extract_text(chunk)
                if text:
                    full_response.append(text)

            elif chunk_type == "ToolCall":
                tool_name = chunk.get("name", "")
                tool_status = chunk.get("status", "")
                tool_params = chunk.get("params", {})

                tool_calls.append(chunk)

                # relay significant tool calls
                if tool_status == "running":
                    if "terminal" in tool_name.lower() or "shell" in tool_name.lower() or "exec" in tool_name.lower():
                        cmd = str(tool_params.get("command", ""))[:100]
                        if "github-dev" in cmd or "dev " in cmd:
                            self.on_progress(f"executing: {cmd}")
                        elif "linear_helper" in cmd:
                            self.on_progress(f"creating linear spec: {cmd}")

                elif tool_status == "complete":
                    if "write" in tool_name.lower() or "edit" in tool_name.lower():
                        path = tool_params.get("path", tool_params.get("filePath", ""))
                        if path:
                            self.files_changed.append(path)

            elif chunk_type == "ToolCallUpdate":
                # progress updates for running tools — mostly noise, skip
                pass

        self.kiro_response = "".join(full_response)

        # analyze what happened
        result = self._analyze_session(self.kiro_response, tool_calls)
        return result

    def run_followup(self, prompt: str) -> str:
        """Send a follow-up prompt to Kiro in the same session."""
        if not self.kiro:
            raise RuntimeError("Session not started.")

        self.on_progress(f"sending follow-up to kiro...")
        response = self.kiro.prompt(prompt, timeout=self.timeout)
        return response

    def _analyze_session(
        self, response: str, tool_calls: List[Dict]
    ) -> Dict[str, Any]:
        """Analyze Kiro's output to determine what happened."""

        response_lower = response.lower()

        # check if Kiro created specs
        spec_indicators = [
            "created linear issue",
            "created spec",
            "created issue",
            "linear_helper",
            "created the following specs",
            "created the following issues",
            "created tasks",
        ]
        created_specs = any(ind in response_lower for ind in spec_indicators)

        # check for spec creation in tool calls
        for tc in tool_calls:
            cmd = str(tc.get("params", {}).get("command", ""))
            if "linear_helper" in cmd and "create" in cmd:
                created_specs = True

        # extract spec titles/IDs from response
        spec_ids = re.findall(r'(CON-\d+|DEV-\d+|MER-\d+)', response)

        # check for coding indicators
        commit_indicators = [
            "committed",
            "commit ",
            "github-dev.*commit",
            "files changed",
            "wrote.*file",
        ]
        did_code = any(re.search(ind, response_lower) for ind in commit_indicators)

        # check tool calls for commit commands
        for tc in tool_calls:
            cmd = str(tc.get("params", {}).get("command", ""))
            if "dev" in cmd and "commit" in cmd:
                did_code = True
                # extract commit message
                match = re.search(r'commit\s+"([^"]+)"', cmd)
                if match:
                    self.commits_made.append(match.group(1))

        if created_specs and not did_code:
            self.session_type = "specs"
            self.on_progress(f"kiro created specs: {', '.join(spec_ids) if spec_ids else 'check response'}")
        else:
            self.session_type = "code"
            self.on_progress(f"kiro finished coding. commits: {len(self.commits_made)}, files: {len(self.files_changed)}")

        return {
            "type": self.session_type,
            "response": self.kiro_response,
            "specs_created": spec_ids,
            "files_changed": list(set(self.files_changed)),
            "commits": self.commits_made,
        }

    def get_summary(self) -> str:
        """Get a human-readable summary of the session."""
        if self.session_type == "specs":
            return (
                f"Kiro assessed this task as complex and created Linear specs: "
                f"{', '.join(self.created_specs) if self.created_specs else 'see response'}.\n"
                f"No code was written. The specs will be picked up for implementation later."
            )
        elif self.session_type == "code":
            return (
                f"Kiro coded the solution.\n"
                f"  Commits: {len(self.commits_made)}\n"
                f"  Files changed: {len(self.files_changed)}\n"
                f"  Changes: {', '.join(self.commits_made) if self.commits_made else 'see response'}"
            )
        else:
            return "Session not yet completed."


# ---------------------------------------------------------------------------
# Convenience functions for OpenCode to call directly
# ---------------------------------------------------------------------------

def run_coding_task(
    task_description: str,
    branch_name: str,
    cwd: str = DEFAULT_CWD,
    repo: str = DEFAULT_REPO,
    linear_spec: Optional[str] = None,
    linear_task_id: Optional[str] = None,
    error_context: Optional[str] = None,
    on_progress: Optional[Callable[[str], None]] = None,
) -> Dict[str, Any]:
    """
    One-shot: spawn Kiro, run a task, return results.

    This is the simplest way to use the kiro skill from OpenCode:

        from kiro_agent import run_coding_task
        result = run_coding_task(
            task_description="implement user auth with JWT",
            branch_name="remote/consuelo-a3f2--user-auth",
        )
    """
    session = KiroSession(cwd=cwd, repo=repo, on_progress=on_progress)
    try:
        session.start()
        result = session.run_task(
            task_description=task_description,
            branch_name=branch_name,
            linear_spec=linear_spec,
            linear_task_id=linear_task_id,
            error_context=error_context,
        )
        result["summary"] = session.get_summary()
        return result
    finally:
        session.stop()


# ---------------------------------------------------------------------------
# CLI interface (for testing / direct invocation)
# ---------------------------------------------------------------------------

def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Kiro Agent — spawn Kiro for coding tasks",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run a coding task on an existing branch
  python3 kiro_agent.py run --branch remote/consuelo-a3f2--auth "implement JWT auth"

  # Run a Linear task
  python3 kiro_agent.py run --branch remote/consuelo-a3f2--auth --linear CON-456 "implement the spec"

  # Retry after deploy failure
  python3 kiro_agent.py run --branch remote/consuelo-a3f2--auth --error "TypeError: x is undefined" "fix the deploy error"
        """
    )

    subparsers = parser.add_subparsers(dest="command")

    run_parser = subparsers.add_parser("run", help="Run a coding task")
    run_parser.add_argument("task", help="Task description")
    run_parser.add_argument("--branch", required=True, help="Branch name to work on")
    run_parser.add_argument("--cwd", default=DEFAULT_CWD, help="Kiro working directory")
    run_parser.add_argument("--repo", default=DEFAULT_REPO, help="GitHub repo")
    run_parser.add_argument("--linear", help="Linear task ID (e.g., CON-456)")
    run_parser.add_argument("--linear-spec-file", help="Path to Linear spec markdown file")
    run_parser.add_argument("--error", help="Error context for retry flows")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    if args.command == "run":
        linear_spec = None
        if args.linear_spec_file:
            with open(args.linear_spec_file) as f:
                linear_spec = f.read()

        result = run_coding_task(
            task_description=args.task,
            branch_name=args.branch,
            cwd=args.cwd,
            repo=args.repo,
            linear_spec=linear_spec,
            linear_task_id=args.linear,
            error_context=args.error,
        )

        print(json.dumps(result, indent=2, default=str))


if __name__ == "__main__":
    main()
