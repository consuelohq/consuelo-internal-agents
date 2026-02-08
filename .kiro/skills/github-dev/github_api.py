"""
GitHub API client for remote development.

Hybrid approach:
- gh CLI (high-level) for PRs, reviews, labels, comments
- gh api (raw REST) for file CRUD, branches, batch commits

All operations are remote — no local clone needed.
"""

import subprocess
import json
import base64
import hashlib
import re
import sys
from typing import List, Dict, Optional, Any, Tuple

# gh binary location (not always on PATH in agent sessions)
GH_BIN = "/opt/homebrew/bin/gh"

DEFAULT_REPO = "kokayicobb/consuelo_on_call_coaching"


class GitHubAPI:
    """Extended GitHub API client for remote development."""

    def __init__(self, repo: Optional[str] = None):
        self.repo = repo or DEFAULT_REPO
        self.owner, self.name = self.repo.split("/")

    # -------------------------------------------------------------------------
    # Low-level helpers
    # -------------------------------------------------------------------------

    def _run_gh(self, args: List[str], input_data: Optional[str] = None) -> Tuple[str, str, int]:
        """
        Run a gh command. Returns (stdout, stderr, returncode).
        """
        cmd = [GH_BIN] + args
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            input=input_data,
        )
        return result.stdout, result.stderr, result.returncode

    def _gh_cli(self, args: List[str]) -> str:
        """Run gh CLI command with --repo flag. Returns stdout or empty string on error."""
        full_args = args + ["--repo", self.repo]
        stdout, stderr, rc = self._run_gh(full_args)
        if rc != 0:
            print(f"[gh error] {' '.join(args[:3])}: {stderr.strip()}", file=sys.stderr)
            return ""
        return stdout

    def _api(self, endpoint: str, method: str = "GET", data: Optional[Dict] = None,
             raw_body: Optional[str] = None) -> Any:
        """
        Call GitHub REST API via `gh api`.
        Returns parsed JSON or None on error.
        """
        args = ["api", endpoint, "-X", method]

        if data and method in ("POST", "PUT", "PATCH", "DELETE"):
            # Use --input to pass JSON body via stdin (avoids shell escaping hell)
            body = json.dumps(data)
            args.extend(["--input", "-"])
            stdout, stderr, rc = self._run_gh(args, input_data=body)
        elif raw_body and method in ("POST", "PUT", "PATCH", "DELETE"):
            args.extend(["--input", "-"])
            stdout, stderr, rc = self._run_gh(args, input_data=raw_body)
        else:
            stdout, stderr, rc = self._run_gh(args)

        if rc != 0:
            print(f"[gh api error] {method} {endpoint}: {stderr.strip()}", file=sys.stderr)
            return None

        if not stdout.strip():
            return None

        try:
            return json.loads(stdout)
        except json.JSONDecodeError:
            return stdout

    def _repo_endpoint(self, path: str = "") -> str:
        """Build repos/{owner}/{repo}/{path} endpoint."""
        base = f"repos/{self.owner}/{self.name}"
        if path:
            return f"{base}/{path}"
        return base

    # -------------------------------------------------------------------------
    # Branch operations (gh api)
    # -------------------------------------------------------------------------

    def get_default_branch(self) -> str:
        """Get the default branch name (usually 'main')."""
        result = self._api(self._repo_endpoint(""))
        if result and isinstance(result, dict):
            return result.get("default_branch", "main")
        return "main"

    def get_branch_sha(self, branch: str = "main") -> Optional[str]:
        """Get the latest commit SHA of a branch."""
        result = self._api(self._repo_endpoint(f"git/ref/heads/{branch}"))
        if result and isinstance(result, dict):
            return result.get("object", {}).get("sha")
        return None

    def create_branch(self, branch_name: str, from_branch: str = "main") -> bool:
        """Create a new branch from an existing branch."""
        sha = self.get_branch_sha(from_branch)
        if not sha:
            print(f"[error] Could not get SHA for branch '{from_branch}'", file=sys.stderr)
            return False

        result = self._api(
            self._repo_endpoint("git/refs"),
            method="POST",
            data={
                "ref": f"refs/heads/{branch_name}",
                "sha": sha,
            }
        )
        return result is not None and isinstance(result, dict) and "ref" in result

    def delete_branch(self, branch_name: str) -> bool:
        """Delete a branch."""
        result = self._api(
            self._repo_endpoint(f"git/refs/heads/{branch_name}"),
            method="DELETE"
        )
        # DELETE returns empty on success
        return True  # gh api returns rc=0 on success

    def list_branches(self, prefix: Optional[str] = None) -> List[str]:
        """List branches, optionally filtered by prefix."""
        result = self._api(self._repo_endpoint("branches?per_page=100"))
        if not result or not isinstance(result, list):
            return []
        names = [b["name"] for b in result]
        if prefix:
            names = [n for n in names if n.startswith(prefix)]
        return names

    # -------------------------------------------------------------------------
    # File operations (gh api — Contents API)
    # -------------------------------------------------------------------------

    def get_file(self, path: str, branch: Optional[str] = None) -> Optional[Dict[str, str]]:
        """
        Read a file from the repo.
        Returns {"content": str, "sha": str, "path": str} or None.
        """
        endpoint = self._repo_endpoint(f"contents/{path}")
        if branch:
            endpoint += f"?ref={branch}"

        result = self._api(endpoint)
        if not result or not isinstance(result, dict):
            return None

        if result.get("type") != "file":
            return None

        content = result.get("content", "")
        # GitHub returns base64 with newlines
        decoded = base64.b64decode(content).decode("utf-8")

        return {
            "content": decoded,
            "sha": result["sha"],
            "path": result["path"],
            "size": result.get("size", 0),
        }

    def create_file(self, path: str, content: str, message: str,
                    branch: Optional[str] = None) -> bool:
        """Create a new file on a branch."""
        encoded = base64.b64encode(content.encode("utf-8")).decode("utf-8")

        data = {
            "message": message,
            "content": encoded,
        }
        if branch:
            data["branch"] = branch

        result = self._api(
            self._repo_endpoint(f"contents/{path}"),
            method="PUT",
            data=data,
        )
        return result is not None and isinstance(result, dict) and "content" in result

    def update_file(self, path: str, content: str, message: str,
                    branch: Optional[str] = None, sha: Optional[str] = None) -> bool:
        """
        Update an existing file on a branch.
        If sha is not provided, fetches it automatically.
        """
        if not sha:
            existing = self.get_file(path, branch)
            if not existing:
                print(f"[error] File not found for update: {path}", file=sys.stderr)
                return False
            sha = existing["sha"]

        encoded = base64.b64encode(content.encode("utf-8")).decode("utf-8")

        data = {
            "message": message,
            "content": encoded,
            "sha": sha,
        }
        if branch:
            data["branch"] = branch

        result = self._api(
            self._repo_endpoint(f"contents/{path}"),
            method="PUT",
            data=data,
        )
        return result is not None and isinstance(result, dict) and "content" in result

    def delete_file(self, path: str, message: str,
                    branch: Optional[str] = None, sha: Optional[str] = None) -> bool:
        """Delete a file from a branch."""
        if not sha:
            existing = self.get_file(path, branch)
            if not existing:
                return False
            sha = existing["sha"]

        data = {
            "message": message,
            "sha": sha,
        }
        if branch:
            data["branch"] = branch

        result = self._api(
            self._repo_endpoint(f"contents/{path}"),
            method="DELETE",
            data=data,
        )
        return result is not None

    def list_directory(self, path: str = "", branch: Optional[str] = None) -> List[Dict[str, str]]:
        """
        List contents of a directory.
        Returns list of {"name": str, "type": "file"|"dir", "path": str, "size": int}.
        """
        endpoint = self._repo_endpoint(f"contents/{path}")
        if branch:
            endpoint += f"?ref={branch}"

        result = self._api(endpoint)
        if not result or not isinstance(result, list):
            return []

        return [
            {
                "name": item["name"],
                "type": item["type"],
                "path": item["path"],
                "size": item.get("size", 0),
            }
            for item in result
        ]

    # -------------------------------------------------------------------------
    # Batch commit (Git Trees API — atomic multi-file commits)
    # -------------------------------------------------------------------------

    def batch_commit(self, files: List[Dict[str, str]], message: str,
                     branch: str) -> bool:
        """
        Commit multiple files atomically using the Git Trees API.

        files: list of {"path": str, "content": str} for creates/updates
               or {"path": str, "delete": True} for deletions

        This is way more efficient than one-file-at-a-time for real coding work.
        """
        # Step 1: Get the current commit SHA and tree SHA for the branch
        branch_sha = self.get_branch_sha(branch)
        if not branch_sha:
            print(f"[error] Could not get SHA for branch '{branch}'", file=sys.stderr)
            return False

        commit_data = self._api(self._repo_endpoint(f"git/commits/{branch_sha}"))
        if not commit_data:
            return False
        base_tree_sha = commit_data["tree"]["sha"]

        # Step 2: Build tree entries
        tree_entries = []
        for f in files:
            if f.get("delete"):
                # To delete, set sha to null (omit content, set mode)
                tree_entries.append({
                    "path": f["path"],
                    "mode": "100644",
                    "type": "blob",
                    "sha": None,
                })
            else:
                # Create a blob first for each file
                blob_result = self._api(
                    self._repo_endpoint("git/blobs"),
                    method="POST",
                    data={
                        "content": f["content"],
                        "encoding": "utf-8",
                    }
                )
                if not blob_result:
                    print(f"[error] Failed to create blob for {f['path']}", file=sys.stderr)
                    return False

                tree_entries.append({
                    "path": f["path"],
                    "mode": "100644",
                    "type": "blob",
                    "sha": blob_result["sha"],
                })

        # Step 3: Create the new tree
        tree_result = self._api(
            self._repo_endpoint("git/trees"),
            method="POST",
            data={
                "base_tree": base_tree_sha,
                "tree": tree_entries,
            }
        )
        if not tree_result:
            print("[error] Failed to create tree", file=sys.stderr)
            return False

        # Step 4: Create the commit
        commit_result = self._api(
            self._repo_endpoint("git/commits"),
            method="POST",
            data={
                "message": message,
                "tree": tree_result["sha"],
                "parents": [branch_sha],
            }
        )
        if not commit_result:
            print("[error] Failed to create commit", file=sys.stderr)
            return False

        # Step 5: Update the branch ref to point to the new commit
        ref_result = self._api(
            self._repo_endpoint(f"git/refs/heads/{branch}"),
            method="PATCH",
            data={
                "sha": commit_result["sha"],
            }
        )
        return ref_result is not None

    # -------------------------------------------------------------------------
    # PR operations (gh CLI — high-level, clean)
    # -------------------------------------------------------------------------

    def create_pr(self, title: str, body: str, head: str,
                  base: Optional[str] = None) -> Optional[Dict[str, Any]]:
        """Create a pull request. Returns PR info dict or None."""
        if not base:
            base = self.get_default_branch()

        stdout = self._gh_cli([
            "pr", "create",
            "--title", title,
            "--body", body,
            "--head", head,
            "--base", base,
        ])
        if not stdout:
            return None

        # gh pr create returns the PR URL on success
        url = stdout.strip()

        # Fetch the PR info to get the number and full details
        # Extract PR number from URL
        match = re.search(r'/pull/(\d+)', url)
        if match:
            return self.get_pr_info(match.group(1))

        return {"url": url}

    def get_pr_info(self, pr_number: str) -> Dict[str, Any]:
        """Get PR information."""
        output = self._gh_cli([
            "pr", "view", str(pr_number),
            "--json", "number,title,body,headRefName,baseRefName,state,author,url,labels"
        ])
        if not output:
            return {}
        return json.loads(output)

    def get_pr_diff(self, pr_number: str) -> str:
        """Get PR diff."""
        return self._gh_cli(["pr", "diff", str(pr_number)])

    def get_pr_files(self, pr_number: str) -> List[Dict[str, Any]]:
        """Get list of changed files in a PR."""
        output = self._gh_cli(["pr", "view", str(pr_number), "--json", "files"])
        if not output:
            return []
        data = json.loads(output)
        return data.get("files", [])

    def get_pr_commits(self, pr_number: str) -> List[Dict[str, Any]]:
        """Get PR commits."""
        output = self._gh_cli(["pr", "view", str(pr_number), "--json", "commits"])
        if not output:
            return []
        data = json.loads(output)
        return data.get("commits", [])

    def post_pr_comment(self, pr_number: str, body: str) -> bool:
        """Post a comment on a PR."""
        stdout, stderr, rc = self._run_gh([
            "pr", "comment", str(pr_number),
            "--body", body,
            "--repo", self.repo,
        ])
        return rc == 0

    def add_label(self, pr_number: str, label: str) -> bool:
        """Add a label to a PR."""
        stdout, stderr, rc = self._run_gh([
            "pr", "edit", str(pr_number),
            "--add-label", label,
            "--repo", self.repo,
        ])
        return rc == 0

    def merge_pr(self, pr_number: str, method: str = "squash") -> bool:
        """Merge a PR. method: merge, squash, rebase."""
        stdout, stderr, rc = self._run_gh([
            "pr", "merge", str(pr_number),
            f"--{method}",
            "--repo", self.repo,
        ])
        return rc == 0

    # -------------------------------------------------------------------------
    # Utility helpers
    # -------------------------------------------------------------------------

    @staticmethod
    def generate_branch_name(description: str, repo_name: Optional[str] = None) -> str:
        """
        Generate a branch name in the remote/ convention.
        Format: remote/{repo_name}-{4char_hash}--{kebab-description}
        """
        if not repo_name:
            repo_name = DEFAULT_REPO.split("/")[1]

        # Create kebab-case description
        kebab = re.sub(r'[^a-z0-9]+', '-', description.lower()).strip('-')
        # Truncate to reasonable length
        if len(kebab) > 60:
            kebab = kebab[:60].rsplit('-', 1)[0]

        # Generate 4-char hash for uniqueness
        hash_input = f"{description}{repo_name}{id(description)}"
        short_hash = hashlib.md5(hash_input.encode()).hexdigest()[:4]

        return f"remote/{repo_name}-{short_hash}--{kebab}"

    def file_exists(self, path: str, branch: Optional[str] = None) -> bool:
        """Check if a file exists on a branch."""
        return self.get_file(path, branch) is not None

    def get_repo_tree(self, branch: Optional[str] = None, recursive: bool = True) -> List[Dict]:
        """
        Get the full repository file tree.
        Useful for understanding repo structure before making changes.
        """
        if not branch:
            branch = self.get_default_branch()

        sha = self.get_branch_sha(branch)
        if not sha:
            return []

        endpoint = self._repo_endpoint(f"git/trees/{sha}")
        if recursive:
            endpoint += "?recursive=1"

        result = self._api(endpoint)
        if not result or not isinstance(result, dict):
            return []

        return [
            {
                "path": item["path"],
                "type": item["type"],  # "blob" = file, "tree" = directory
                "size": item.get("size", 0),
            }
            for item in result.get("tree", [])
            if item["type"] == "blob"  # Only return files, not dirs
        ]
