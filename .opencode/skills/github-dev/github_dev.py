"""
GitHub Remote Development Orchestrator.

Manages the full workflow of developing features remotely via GitHub API:
1. Pull task from Linear → save as markdown spec
2. Create branch from main (or specified base)
3. Read/write/update files on the branch
4. Batch commit changes atomically
5. Create PR with Linear task linking
6. Auto-sync Linear task status

Two modes:
- Task mode: Start from a Linear task ID
- PR mode: Work on an existing PR's branch

All operations are remote — no local clone needed.
"""

import os
import sys
import json
import re
from datetime import datetime
from typing import Optional, Dict, List, Any

# Add skill directory to path
SKILL_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SKILL_DIR)

from github_api import GitHubAPI, DEFAULT_REPO
from linear_api import LinearAPI


class RemoteDev:
    """
    Orchestrator for remote development via GitHub API.

    Usage:
        dev = RemoteDev()

        # Mode 1: Start from a Linear task
        dev.start_task("CON-456")
        dev.write_file("src/new-feature.tsx", content)
        dev.write_file("src/utils/helper.ts", content)
        dev.commit("feat: implement new feature")
        pr = dev.create_pr()

        # Mode 2: Work on an existing PR
        dev.work_on_pr(789)
        dev.update_file("src/fix.tsx", new_content)
        dev.commit("fix: address review comments")
    """

    def __init__(self, repo: Optional[str] = None):
        self.gh = GitHubAPI(repo)
        self.linear: Optional[LinearAPI] = None

        # Current session state
        self.branch: Optional[str] = None
        self.task: Optional[Dict[str, Any]] = None
        self.task_id: Optional[str] = None  # Linear internal ID (for API calls)
        self.task_identifier: Optional[str] = None  # e.g., "CON-456"
        self.pr_number: Optional[str] = None

        # Staging area: files to commit in the next batch
        self._staged_files: List[Dict[str, Any]] = []

        # State file for session persistence
        self._state_file = os.path.join(SKILL_DIR, "tasks", ".session-state.json")

    # -------------------------------------------------------------------------
    # Linear integration (lazy-loaded)
    # -------------------------------------------------------------------------

    def _get_linear(self) -> LinearAPI:
        """Lazy-load the Linear client."""
        if not self.linear:
            self.linear = LinearAPI()
        return self.linear

    # -------------------------------------------------------------------------
    # Mode 1: Start from Linear task
    # -------------------------------------------------------------------------

    def start_task(self, identifier: str, base_branch: str = "main") -> Dict[str, Any]:
        """
        Full workflow: fetch task → create branch → update Linear status.

        Returns a summary dict with task info and branch name.
        """
        identifier = identifier.upper()
        linear = self._get_linear()

        # Step 1: Fetch the task
        print(f"[1/4] Fetching task {identifier} from Linear...")
        task = linear.get_task_by_identifier(identifier)
        if not task:
            raise ValueError(f"Task {identifier} not found in Linear")

        self.task = task
        self.task_id = task["id"]
        self.task_identifier = task["identifier"]

        # Step 2: Save task as markdown
        print(f"[2/4] Saving task spec...")
        task_md = LinearAPI.task_to_markdown(task)
        tasks_dir = os.path.join(SKILL_DIR, "tasks")
        os.makedirs(tasks_dir, exist_ok=True)
        task_path = os.path.join(tasks_dir, f"{identifier}.md")
        with open(task_path, "w") as f:
            f.write(task_md)

        # Step 3: Create branch
        print(f"[3/4] Creating branch from {base_branch}...")
        branch_desc = self._task_to_branch_description(task)
        self.branch = GitHubAPI.generate_branch_name(branch_desc, self.gh.name)

        success = self.gh.create_branch(self.branch, base_branch)
        if not success:
            raise RuntimeError(f"Failed to create branch '{self.branch}'")

        # Step 4: Update Linear status
        print(f"[4/4] Updating Linear status to 'In Progress'...")
        linear.update_task_state(self.task_id, "In Progress")
        linear.add_comment(
            self.task_id,
            f"Started remote development on branch `{self.branch}`\n\n"
            f"Working via GitHub API (no local clone)."
        )

        # Save session state
        self._save_state()

        summary = {
            "task": identifier,
            "title": task["title"],
            "branch": self.branch,
            "task_file": task_path,
            "base_branch": base_branch,
            "repo": self.gh.repo,
        }

        print(f"\nReady to code!")
        print(f"  Task: {identifier} — {task['title']}")
        print(f"  Branch: {self.branch}")
        print(f"  Spec: {task_path}")
        print(f"  Repo: {self.gh.repo}")

        return summary

    # -------------------------------------------------------------------------
    # Mode 2: Work on existing PR
    # -------------------------------------------------------------------------

    def work_on_pr(self, pr_number: int) -> Dict[str, Any]:
        """
        Start working on an existing PR's branch.

        Returns PR info with branch name set for subsequent operations.
        """
        self.pr_number = str(pr_number)

        print(f"[1/2] Fetching PR #{pr_number} info...")
        pr_info = self.gh.get_pr_info(self.pr_number)
        if not pr_info:
            raise ValueError(f"PR #{pr_number} not found")

        self.branch = pr_info["headRefName"]

        # Try to find a linked Linear task from the PR body
        print(f"[2/2] Checking for linked Linear task...")
        self._extract_linear_task_from_pr(pr_info)

        # Save session state
        self._save_state()

        print(f"\nReady to work on PR #{pr_number}!")
        print(f"  Title: {pr_info['title']}")
        print(f"  Branch: {self.branch}")
        print(f"  State: {pr_info['state']}")
        if self.task_identifier:
            print(f"  Linked task: {self.task_identifier}")

        return pr_info

    # -------------------------------------------------------------------------
    # File operations (on the current branch)
    # -------------------------------------------------------------------------

    def read_file(self, path: str) -> Optional[str]:
        """Read a file from the current branch."""
        self._ensure_branch()
        result = self.gh.get_file(path, self.branch)
        if result:
            return result["content"]
        return None

    def write_file(self, path: str, content: str, stage: bool = True) -> None:
        """
        Stage a file for the next commit.
        If stage=False, commits immediately as a single file.
        """
        self._ensure_branch()

        if stage:
            # Add to staging area for batch commit
            # Check if already staged (update in place)
            for f in self._staged_files:
                if f["path"] == path:
                    f["content"] = content
                    print(f"  Updated staged: {path}")
                    return
            self._staged_files.append({"path": path, "content": content})
            print(f"  Staged: {path}")
        else:
            # Commit immediately
            exists = self.gh.file_exists(path, self.branch)
            if exists:
                self.gh.update_file(path, content, f"update {path}", self.branch)
            else:
                self.gh.create_file(path, content, f"add {path}", self.branch)
            print(f"  Committed: {path}")

    def delete_file(self, path: str, stage: bool = True) -> None:
        """Stage a file deletion or delete immediately."""
        self._ensure_branch()

        if stage:
            self._staged_files.append({"path": path, "delete": True})
            print(f"  Staged deletion: {path}")
        else:
            self.gh.delete_file(path, f"delete {path}", self.branch)
            print(f"  Deleted: {path}")

    def list_files(self, path: str = "") -> List[Dict]:
        """List directory contents on the current branch."""
        self._ensure_branch()
        return self.gh.list_directory(path, self.branch)

    def get_repo_structure(self, path_filter: Optional[str] = None) -> List[str]:
        """
        Get the full file tree of the repo (useful for understanding codebase).
        Optionally filter by path prefix (e.g., "src/components").
        """
        files = self.gh.get_repo_tree(self.branch)
        paths = [f["path"] for f in files]
        if path_filter:
            paths = [p for p in paths if p.startswith(path_filter)]
        return paths

    # -------------------------------------------------------------------------
    # Commit operations
    # -------------------------------------------------------------------------

    def commit(self, message: str) -> bool:
        """
        Commit all staged files as a single atomic operation.
        Uses the Git Trees API for efficiency.
        """
        self._ensure_branch()

        if not self._staged_files:
            print("[warn] No files staged for commit")
            return False

        file_count = len(self._staged_files)
        print(f"Committing {file_count} file(s): {message}")

        assert self.branch is not None  # guaranteed by _ensure_branch()
        success = self.gh.batch_commit(self._staged_files, message, self.branch)

        if success:
            self._staged_files = []
            print(f"  Committed {file_count} file(s) to {self.branch}")
        else:
            print(f"  [error] Commit failed!", file=sys.stderr)

        return success

    def staged_files(self) -> List[str]:
        """List currently staged file paths."""
        return [f["path"] for f in self._staged_files]

    def unstage(self, path: str) -> bool:
        """Remove a file from the staging area."""
        for i, f in enumerate(self._staged_files):
            if f["path"] == path:
                self._staged_files.pop(i)
                print(f"  Unstaged: {path}")
                return True
        return False

    def clear_staged(self) -> None:
        """Clear all staged files."""
        count = len(self._staged_files)
        self._staged_files = []
        print(f"  Cleared {count} staged file(s)")

    # -------------------------------------------------------------------------
    # PR operations
    # -------------------------------------------------------------------------

    def create_pr(self, title: Optional[str] = None, body: Optional[str] = None,
                  base: Optional[str] = None, draft: bool = False) -> Optional[Dict]:
        """
        Create a PR for the current branch.
        If working from a Linear task, auto-generates title/body with linking.
        """
        self._ensure_branch()

        # Check for uncommitted staged files
        if self._staged_files:
            print(f"[warn] You have {len(self._staged_files)} unstaged files. Commit first?")

        if not title:
            if self.task:
                title = f"{self.task['identifier']}: {self.task['title']}"
            else:
                title = f"Remote dev: {self.branch}"

        if not body:
            body = self._generate_pr_body()

        print(f"Creating PR: {title}")
        assert self.branch is not None  # guaranteed by _ensure_branch()
        pr = self.gh.create_pr(title, body, self.branch, base)

        if pr:
            self.pr_number = str(pr.get("number", ""))
            print(f"  PR created: #{self.pr_number}")
            print(f"  URL: {pr.get('url', 'N/A')}")

            # Update Linear task with PR link
            if self.task_id:
                linear = self._get_linear()
                linear.update_task_state(self.task_id, "In Review")
                linear.add_comment(
                    self.task_id,
                    f"PR created: #{self.pr_number}\n\n"
                    f"URL: {pr.get('url', 'N/A')}\n\n"
                    f"Ready for review."
                )
                print(f"  Linear task moved to 'In Review'")

            self._save_state()

        return pr

    # -------------------------------------------------------------------------
    # Session state persistence
    # -------------------------------------------------------------------------

    def _save_state(self) -> None:
        """Save current session state for resumption.

        Persists full staged file content so the staging area survives
        between separate CLI invocations (e.g., 'dev write' then 'dev commit').
        """
        state = {
            "branch": self.branch,
            "task_identifier": self.task_identifier,
            "task_id": self.task_id,
            "pr_number": self.pr_number,
            "repo": self.gh.repo,
            "staged_files": self._staged_files,  # full dicts with path + content
            "updated_at": datetime.now().isoformat(),
        }

        os.makedirs(os.path.dirname(self._state_file), exist_ok=True)
        with open(self._state_file, "w") as f:
            json.dump(state, f, indent=2)

    def resume(self) -> bool:
        """Resume a previous session from state file."""
        if not os.path.exists(self._state_file):
            print("[info] No previous session found")
            return False

        with open(self._state_file) as f:
            state = json.load(f)

        self.branch = state.get("branch")
        self.task_identifier = state.get("task_identifier")
        self.task_id = state.get("task_id")
        self.pr_number = state.get("pr_number")

        # Restore staged files (full content)
        staged = state.get("staged_files", [])
        if staged and isinstance(staged, list):
            if staged and isinstance(staged[0], dict):
                # New format: list of dicts with path + content
                self._staged_files = staged
            elif staged and isinstance(staged[0], str):
                # Legacy format: just paths (no content to restore)
                self._staged_files = []
                print(f"  [warn] {len(staged)} staged file(s) from old format — content lost, re-stage them")

        # Verify the branch still exists
        if self.branch:
            sha = self.gh.get_branch_sha(self.branch)
            if not sha:
                print(f"[warn] Branch '{self.branch}' no longer exists")
                return False

        print(f"Resumed session:")
        print(f"  Branch: {self.branch}")
        if self.task_identifier:
            print(f"  Task: {self.task_identifier}")
        if self.pr_number:
            print(f"  PR: #{self.pr_number}")
        if self._staged_files:
            print(f"  Staged: {len(self._staged_files)} file(s)")
        print(f"  Last updated: {state.get('updated_at', 'Unknown')}")

        return True

    # -------------------------------------------------------------------------
    # Internal helpers
    # -------------------------------------------------------------------------

    def _ensure_branch(self) -> None:
        """Ensure we have an active branch to work on."""
        if not self.branch:
            raise RuntimeError(
                "No active branch. Call start_task() or work_on_pr() first."
            )

    @staticmethod
    def _task_to_branch_description(task: Dict) -> str:
        """Generate a branch description from a task."""
        title = task.get("title", "untitled")
        # Clean up the title for branch naming
        # Remove common prefixes like [FEATURE], [BUG], etc.
        title = re.sub(r'^\[.*?\]\s*:?\s*', '', title)
        return title

    def _extract_linear_task_from_pr(self, pr_info: Dict) -> None:
        """Try to find a Linear task ID in the PR body."""
        body = pr_info.get("body", "") or ""
        # Look for patterns like CON-123, DEV-456, etc.
        match = re.search(r'\b([A-Z]+-\d+)\b', body)
        if match:
            self.task_identifier = match.group(1)
            # Try to fetch the actual task
            try:
                linear = self._get_linear()
                task = linear.get_task_by_identifier(self.task_identifier)
                if task:
                    self.task = task
                    self.task_id = task["id"]
            except Exception:
                pass  # Linear connection might not be available

    def _generate_pr_body(self) -> str:
        """Generate a PR body with Linear task linking."""
        lines = []

        if self.task:
            lines.append(f"## {self.task['identifier']}: {self.task['title']}")
            lines.append("")

            description = self.task.get("description", "")
            if description:
                # Truncate long descriptions for the PR body
                if len(description) > 2000:
                    description = description[:2000] + "\n\n*[truncated — see Linear task for full spec]*"
                lines.append(description)
                lines.append("")

            lines.append(f"**Linear Task:** {self.task.get('url', self.task_identifier)}")
            lines.append(f"**Priority:** {self.task.get('priorityLabel', 'None')}")
            lines.append("")
        else:
            lines.append("## Changes")
            lines.append("")
            lines.append("*Remote development — no local clone.*")
            lines.append("")

        lines.append("---")
        lines.append(f"*Created via remote dev workflow on `{self.branch}`*")

        return "\n".join(lines)


# -------------------------------------------------------------------------
# CLI interface
# -------------------------------------------------------------------------

def main():
    """CLI entry point for the dev skill."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Remote development via GitHub API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  dev task CON-456              # Start working on a Linear task
  dev pr 789                    # Work on an existing PR
  dev create-branch "add auth"  # Create a branch (no Linear task)
  dev read src/file.tsx         # Read a file from current branch
  dev ls src/components/        # List directory contents
  dev tree src/                 # Show file tree
  dev write src/new.tsx --content-file /tmp/code.tsx   # Stage a file
  echo 'content' | dev write src/file.tsx              # Stage via stdin
  dev staged                    # List staged files
  dev commit "feat: add auth"   # Commit staged files to branch
  dev create-pr --label kiro    # Create PR with labels
  dev status                    # Show current session info
  dev resume                    # Resume previous session
        """
    )

    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    # task command
    task_parser = subparsers.add_parser("task", help="Start from a Linear task")
    task_parser.add_argument("identifier", help="Linear task ID (e.g., CON-456)")
    task_parser.add_argument("--base", default="main", help="Base branch (default: main)")
    task_parser.add_argument("--repo", help="Override repo (default: consuelo)")

    # pr command
    pr_parser = subparsers.add_parser("pr", help="Work on an existing PR")
    pr_parser.add_argument("number", type=int, help="PR number")
    pr_parser.add_argument("--repo", help="Override repo")

    # read command
    read_parser = subparsers.add_parser("read", help="Read a file")
    read_parser.add_argument("path", help="File path in repo")

    # ls command
    ls_parser = subparsers.add_parser("ls", help="List directory contents")
    ls_parser.add_argument("path", nargs="?", default="", help="Directory path")

    # tree command
    tree_parser = subparsers.add_parser("tree", help="Show repo file tree")
    tree_parser.add_argument("path", nargs="?", default=None, help="Filter by path prefix")

    # status command
    subparsers.add_parser("status", help="Show current session info")

    # resume command
    subparsers.add_parser("resume", help="Resume previous session")

    # write command — stage a file for commit
    write_parser = subparsers.add_parser("write", help="Write/stage a file on the branch")
    write_parser.add_argument("path", help="File path in repo (e.g., src/new-file.tsx)")
    write_parser.add_argument("--stdin", action="store_true",
                              help="Read content from stdin (default if no --content)")
    write_parser.add_argument("--content", help="File content as a string (use stdin for large files)")
    write_parser.add_argument("--content-file", help="Read content from a local file path")
    write_parser.add_argument("--immediate", action="store_true",
                              help="Commit immediately (skip staging)")

    # commit command — commit all staged files
    commit_parser = subparsers.add_parser("commit", help="Commit all staged files to the branch")
    commit_parser.add_argument("message", help="Commit message")

    # staged command — show staged files
    subparsers.add_parser("staged", help="List currently staged files")

    # unstage command
    unstage_parser = subparsers.add_parser("unstage", help="Unstage a file")
    unstage_parser.add_argument("path", help="File path to unstage")

    # create-branch command — create a branch without a Linear task
    branch_parser = subparsers.add_parser("create-branch", help="Create a new branch (no Linear task)")
    branch_parser.add_argument("description", help="Branch description (will be kebab-cased)")
    branch_parser.add_argument("--base", default="main", help="Base branch (default: main)")
    branch_parser.add_argument("--repo", help="Override repo")

    # create-pr command — create a PR for the current branch
    pr_create_parser = subparsers.add_parser("create-pr", help="Create a PR for the current branch")
    pr_create_parser.add_argument("--title", help="PR title (auto-generated if omitted)")
    pr_create_parser.add_argument("--body", help="PR body (auto-generated if omitted)")
    pr_create_parser.add_argument("--base", help="Base branch (default: repo default)")
    pr_create_parser.add_argument("--label", action="append", default=[], help="Labels to add (repeatable)")
    pr_create_parser.add_argument("--draft", action="store_true", help="Create as draft PR")

    # delete-file command — stage a file deletion
    del_parser = subparsers.add_parser("delete", help="Stage a file deletion")
    del_parser.add_argument("path", help="File path to delete")
    del_parser.add_argument("--immediate", action="store_true", help="Delete immediately (skip staging)")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    repo = getattr(args, "repo", None)
    dev = RemoteDev(repo)

    if args.command == "task":
        dev.start_task(args.identifier, args.base)

    elif args.command == "pr":
        dev.work_on_pr(args.number)

    elif args.command == "read":
        if not dev.resume():
            print("[error] No active session. Run 'dev task' or 'dev pr' first.")
            sys.exit(1)
        content = dev.read_file(args.path)
        if content:
            print(content)
        else:
            print(f"[error] File not found: {args.path}")

    elif args.command == "ls":
        if not dev.resume():
            print("[error] No active session. Run 'dev task' or 'dev pr' first.")
            sys.exit(1)
        items = dev.list_files(args.path)
        for item in items:
            prefix = "d " if item["type"] == "dir" else "  "
            size = f"({item['size']}b)" if item["type"] == "file" else ""
            print(f"{prefix}{item['name']} {size}")

    elif args.command == "tree":
        if not dev.resume():
            print("[error] No active session. Run 'dev task' or 'dev pr' first.")
            sys.exit(1)
        files = dev.get_repo_structure(args.path)
        for f in files:
            print(f)

    elif args.command == "status":
        state_file = os.path.join(SKILL_DIR, "tasks", ".session-state.json")
        if os.path.exists(state_file):
            with open(state_file) as f:
                state = json.load(f)
            print(json.dumps(state, indent=2))
        else:
            print("No active session")

    elif args.command == "resume":
        dev.resume()

    elif args.command == "write":
        if not dev.resume():
            print("[error] No active session. Run 'dev task' or 'dev pr' first.")
            sys.exit(1)

        # resolve content from one of three sources
        content = None
        if args.content:
            content = args.content
        elif args.content_file:
            with open(args.content_file, "r") as f:
                content = f.read()
        else:
            # read from stdin
            content = sys.stdin.read()

        if not content:
            print("[error] No content provided. Use --content, --content-file, or pipe via stdin.")
            sys.exit(1)

        if args.immediate:
            dev.write_file(args.path, content, stage=False)
        else:
            dev.write_file(args.path, content, stage=True)
            # persist staged files to state so they survive between CLI calls
            dev._save_state()
        print(f"[ok] {'Committed' if args.immediate else 'Staged'}: {args.path}")

    elif args.command == "commit":
        if not dev.resume():
            print("[error] No active session. Run 'dev task' or 'dev pr' first.")
            sys.exit(1)
        if not dev._staged_files:
            print("[error] No files staged. Use 'dev write <path>' first.")
            sys.exit(1)
        success = dev.commit(args.message)
        if success:
            dev._save_state()
            print(f"[ok] Committed {len(dev._staged_files) if not success else 0} file(s)")
        else:
            print("[error] Commit failed")
            sys.exit(1)

    elif args.command == "staged":
        if not dev.resume():
            print("[error] No active session.")
            sys.exit(1)
        files = dev.staged_files()
        if files:
            print(f"{len(files)} file(s) staged:")
            for f in files:
                print(f"  {f}")
        else:
            print("No files staged")

    elif args.command == "unstage":
        if not dev.resume():
            print("[error] No active session.")
            sys.exit(1)
        if dev.unstage(args.path):
            dev._save_state()
            print(f"[ok] Unstaged: {args.path}")
        else:
            print(f"[error] File not staged: {args.path}")

    elif args.command == "create-branch":
        branch_desc = args.description
        repo_name = (args.repo or dev.gh.repo).split("/")[-1]
        branch_name = GitHubAPI.generate_branch_name(branch_desc, repo_name)
        dev.branch = branch_name

        success = dev.gh.create_branch(branch_name, args.base)
        if success:
            dev._save_state()
            print(f"[ok] Branch created: {branch_name}")
        else:
            print(f"[error] Failed to create branch: {branch_name}")
            sys.exit(1)

    elif args.command == "create-pr":
        if not dev.resume():
            print("[error] No active session. Run 'dev task' or 'dev create-branch' first.")
            sys.exit(1)
        if dev._staged_files:
            print(f"[warn] {len(dev._staged_files)} file(s) still staged. Commit first?")

        pr = dev.create_pr(
            title=args.title,
            body=args.body,
            base=args.base,
            draft=args.draft,
        )
        if pr:
            # add labels
            for label in args.label:
                dev.gh.add_label(str(pr.get("number", "")), label)
                print(f"  Added label: {label}")
            print(f"[ok] PR created: #{pr.get('number', '?')} — {pr.get('url', 'N/A')}")
        else:
            print("[error] Failed to create PR")
            sys.exit(1)

    elif args.command == "delete":
        if not dev.resume():
            print("[error] No active session.")
            sys.exit(1)
        if args.immediate:
            dev.delete_file(args.path, stage=False)
        else:
            dev.delete_file(args.path, stage=True)
            dev._save_state()
        print(f"[ok] {'Deleted' if args.immediate else 'Staged deletion'}: {args.path}")


if __name__ == "__main__":
    main()
