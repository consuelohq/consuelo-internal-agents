"""GitHub API interactions for review skill."""

import subprocess
import json
import sys
import os
import urllib.request
import urllib.error
from typing import List, Dict, Optional, Any


class GitHubAPI:
    """Wrapper around GitHub CLI for review operations."""
    
    def __init__(self, repo: Optional[str] = None):
        """Initialize with optional repo override."""
        self.repo = repo
    
    def _run_gh(self, args: List[str]) -> str:
        """Run gh command and return stdout."""
        import os
        # Ensure homebrew PATH is available
        env = os.environ.copy()
        env["PATH"] = "/opt/homebrew/bin:" + env.get("PATH", "")

        cmd = ["gh"] + args
        if self.repo:
            cmd.extend(["--repo", self.repo])

        result = subprocess.run(cmd, capture_output=True, text=True, env=env)
        if result.returncode != 0:
            print(f"gh error: {result.stderr}", file=sys.stderr)
            return ""
        if not result.stdout:
            print(f"gh warning: command returned empty output: {cmd}", file=sys.stderr)
        return result.stdout
    
    def get_pr_info(self, pr_number: str) -> Dict[str, Any]:
        """Get PR information."""
        output = self._run_gh(["pr", "view", pr_number, "--json", "number,title,body,headRefName,baseRefName,state,author,url,headRefOid"])
        if not output:
            print(f"get_pr_info: no output received", file=sys.stderr)
            return {}
        return json.loads(output)
    
    def get_pr_diff(self, pr_number: str) -> str:
        """Get PR diff. Handles large diffs gracefully."""
        import urllib.request
        
        diff = self._run_gh(["pr", "diff", pr_number])
        if not diff or "too_large" in diff or "exceeded the maximum" in diff:
            # Diff too large, use GitHub API directly
            # Get token from gh
            token_result = subprocess.run(
                ["gh", "auth", "token"],
                capture_output=True, text=True,
                env={"PATH": "/opt/homebrew/bin:" + os.environ.get("PATH", "")}
            )
            token = token_result.stdout.strip() if token_result.returncode == 0 else ""
            
            if token and self.repo:
                try:
                    # Use GitHub API to get files
                    headers = {
                        "Authorization": f"Bearer {token}",
                        "Accept": "application/vnd.github.v3+json"
                    }
                    url = f"https://api.github.com/repos/{self.repo}/pulls/{pr_number}/files"
                    req = urllib.request.Request(url, headers=headers)
                    with urllib.request.urlopen(req) as response:
                        files_data = json.loads(response.read().decode())
                    
                    # Build diff from file patches (limited to first 30 files)
                    diff_parts = []
                    for file_info in files_data[:30]:
                        patch = file_info.get("patch", "")
                        filename = file_info.get("filename", "")
                        status = file_info.get("status", "modified")
                        if patch:
                            diff_parts.append(f"diff --git a/{filename} b/{filename}")
                            diff_parts.append(f"--- a/{filename}")
                            diff_parts.append(f"+++ b/{filename}")
                            diff_parts.append(patch)
                            diff_parts.append("")
                    
                    diff = "\n".join(diff_parts)
                except Exception as e:
                    print(f"Warning: Could not fetch large diff via API: {e}", file=sys.stderr)
                    diff = ""
        return diff
    
    def get_pr_files(self, pr_number: str) -> List[Dict[str, Any]]:
        """Get list of changed files."""
        output = self._run_gh(["pr", "view", pr_number, "--json", "files"])
        if not output:
            print(f"get_pr_files: no output received", file=sys.stderr)
            return []
        data = json.loads(output)
        return data.get("files", [])
    
    def get_pr_commits(self, pr_number: str) -> List[Dict[str, Any]]:
        """Get PR commits."""
        output = self._run_gh(["pr", "view", pr_number, "--json", "commits"])
        if not output:
            print(f"get_pr_commits: no output received", file=sys.stderr)
            return []
        data = json.loads(output)
        return data.get("commits", [])
    
    def get_pr_checks(self, pr_number: str) -> List[Dict[str, Any]]:
        """Get CI check status."""
        output = self._run_gh(["pr", "checks", pr_number, "--json", "name,state,workflow"])
        if not output:
            print(f"get_pr_checks: no output received", file=sys.stderr)
            return []
        return json.loads(output)
    
    def post_comment(self, pr_number: str, body: str) -> bool:
        """Post a comment on the PR."""
        env = os.environ.copy()
        env["PATH"] = "/opt/homebrew/bin:" + env.get("PATH", "")
        cmd = ["gh", "pr", "comment", pr_number, "--body", body]
        if self.repo:
            cmd.extend(["--repo", self.repo])
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            env=env
        )
        if result.returncode != 0:
            print(f"post_comment error: {result.stderr}", file=sys.stderr)
        return result.returncode == 0
    
    def post_inline_comment(self, pr_number: str, file_path: str, line: int, body: str) -> bool:
        """Post an inline comment on a specific line via GitHub API."""
        import urllib.request
        
        # Get token from gh
        env = os.environ.copy()
        env["PATH"] = "/opt/homebrew/bin:" + env.get("PATH", "")
        token_result = subprocess.run(
            ["gh", "auth", "token"],
            capture_output=True, text=True, env=env
        )
        token = token_result.stdout.strip() if token_result.returncode == 0 else ""
        
        if not token or not self.repo:
            return False
        
        try:
            # Get the PR details to find the head sha
            headers = {
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github.v3+json"
            }
            
            # First get the PR to find the head sha
            pr_url = f"https://api.github.com/repos/{self.repo}/pulls/{pr_number}"
            req = urllib.request.Request(pr_url, headers=headers)
            with urllib.request.urlopen(req) as response:
                pr_data = json.loads(response.read().decode())
            
            head_sha = pr_data.get("head", {}).get("sha", "")
            if not head_sha:
                return False
            
            # Post the review comment
            comment_url = f"https://api.github.com/repos/{self.repo}/pulls/{pr_number}/comments"
            comment_data = {
                "body": body,
                "commit_id": head_sha,
                "path": file_path,
                "line": line,
                "side": "RIGHT"
            }
            
            req = urllib.request.Request(
                comment_url,
                data=json.dumps(comment_data).encode(),
                headers={**headers, "Content-Type": "application/json"},
                method="POST"
            )
            
            with urllib.request.urlopen(req) as response:
                return response.status == 201
        except Exception as e:
            print(f"Inline comment error: {e}", file=sys.stderr)
            return False
    
    def add_label(self, pr_number: str, label: str) -> bool:
        """Add a label to the PR."""
        env = os.environ.copy()
        env["PATH"] = "/opt/homebrew/bin:" + env.get("PATH", "")
        cmd = ["gh", "pr", "edit", pr_number, "--add-label", label]
        if self.repo:
            cmd.extend(["--repo", self.repo])
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            env=env
        )
        if result.returncode != 0:
            print(f"add_label error: {result.stderr}", file=sys.stderr)
        return result.returncode == 0
    
    def remove_label(self, pr_number: str, label: str) -> bool:
        """Remove a label from the PR."""
        env = os.environ.copy()
        env["PATH"] = "/opt/homebrew/bin:" + env.get("PATH", "")
        cmd = ["gh", "pr", "edit", pr_number, "--remove-label", label]
        if self.repo:
            cmd.extend(["--repo", self.repo])
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            env=env
        )
        if result.returncode != 0:
            print(f"remove_label error: {result.stderr}", file=sys.stderr)
        return result.returncode == 0

    def approve_pr(self, pr_number: str, body: Optional[str] = None) -> bool:
        """Approve the PR."""
        env = os.environ.copy()
        env["PATH"] = "/opt/homebrew/bin:" + env.get("PATH", "")
        cmd = ["gh", "pr", "review", pr_number, "--approve"]
        if body:
            cmd.extend(["--body", body])
        if self.repo:
            cmd.extend(["--repo", self.repo])

        result = subprocess.run(cmd, capture_output=True, text=True, env=env)
        if result.returncode != 0:
            print(f"approve_pr error: {result.stderr}", file=sys.stderr)
        return result.returncode == 0

    def request_changes(self, pr_number: str, body: str) -> bool:
        """Request changes on the PR."""
        env = os.environ.copy()
        env["PATH"] = "/opt/homebrew/bin:" + env.get("PATH", "")
        cmd = ["gh", "pr", "review", pr_number, "--request-changes", "--body", body]
        if self.repo:
            cmd.extend(["--repo", self.repo])

        result = subprocess.run(cmd, capture_output=True, text=True, env=env)
        if result.returncode != 0:
            print(f"request_changes error: {result.stderr}", file=sys.stderr)
        return result.returncode == 0

    def comment_on_pr(self, pr_number: str, body: str) -> bool:
        """Post a review comment (not approve/request changes)."""
        env = os.environ.copy()
        env["PATH"] = "/opt/homebrew/bin:" + env.get("PATH", "")
        result = subprocess.run(
            ["gh", "pr", "review", pr_number, "--comment", "--body", body],
            capture_output=True,
            text=True,
            env=env
        )
        if result.returncode != 0:
            print(f"comment_on_pr error: {result.stderr}", file=sys.stderr)
        return result.returncode == 0

    def post_review(self, pr_number: str, event: str, body: str, comments: List[Dict[str, Any]]) -> bool:
        """Post a batch review with summary + all inline comments via GitHub API.

        Uses the separate comments API for inline comments (more reliable than reviews API
        since it uses actual line numbers instead of diff patch positions).

        Args:
            pr_number: Pull request number
            event: Review event - "APPROVE", "REQUEST_CHANGES", or "COMMENT" (for PR review)
            body: Review summary and checklist text
            comments: List of inline comments with keys: commit_id, path, line, body

        Returns:
            bool: True if successful
        """
        import urllib.request
        import json

        # Get token from gh
        env = os.environ.copy()
        env["PATH"] = "/opt/homebrew/bin:" + env.get("PATH", "")
        token_result = subprocess.run(
            ["gh", "auth", "token"],
            capture_output=True, text=True, env=env
        )
        token = token_result.stdout.strip() if token_result.returncode == 0 else ""

        if not token or not self.repo:
            print(f"post_review: no token or repo available", file=sys.stderr)
            return False

        try:
            headers = {
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github.v3+json",
                "Content-Type": "application/json"
            }

            # Step 1: Post inline comments using the comments API (not reviews API)
            # This is more reliable because it uses actual line numbers, not diff positions
            posted_comments = 0
            if comments:
                comments_url = f"https://api.github.com/repos/{self.repo}/pulls/{pr_number}/comments"
                for comment in comments:
                    comment_data = {
                        "body": comment.get("body"),
                        "commit_id": comment.get("commit_id"),
                        "path": comment.get("file_path"),
                        "line": comment.get("line"),
                        "side": "RIGHT"
                    }
                    req = urllib.request.Request(
                        comments_url,
                        data=json.dumps(comment_data).encode(),
                        headers=headers,
                        method="POST"
                    )
                    try:
                        with urllib.request.urlopen(req) as response:
                            if response.status == 201:
                                posted_comments += 1
                    except urllib.error.HTTPError as he:
                        print(f"post_review: comment error {he.code}: {he.reason}", file=sys.stderr)

                print(f"post_review: posted {posted_comments}/{len(comments)} inline comments", file=sys.stderr)

            # Step 2: Post the PR review (without inline comments since we used comments API)
            # Only if event is APPROVE, REQUEST_CHANGES, or COMMENT
            if event in ("APPROVE", "REQUEST_CHANGES", "COMMENT"):
                review_data = {
                    "event": event,
                    "body": body
                }
                review_url = f"https://api.github.com/repos/{self.repo}/pulls/{pr_number}/reviews"
                req = urllib.request.Request(
                    review_url,
                    data=json.dumps(review_data).encode(),
                    headers=headers,
                    method="POST"
                )
                with urllib.request.urlopen(req) as response:
                    if response.status == 201:
                        print(f"post_review: success - review event {event} posted", file=sys.stderr)
                        return True

            # If we got here but posted comments, consider it a success
            if posted_comments > 0:
                print(f"post_review: partial success - {posted_comments} comments posted", file=sys.stderr)
                return True

            print(f"post_review: failed - no comments posted", file=sys.stderr)
            return False

        except urllib.error.HTTPError as e:
            print(f"post_review: HTTP error {e.code}: {e.reason}", file=sys.stderr)
            if e.read():
                print(f"post_review: error response: {e.read().decode()}", file=sys.stderr)
            return False
        except Exception as e:
            print(f"post_review: error: {e}", file=sys.stderr)
            return False
