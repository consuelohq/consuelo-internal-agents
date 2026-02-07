#!/usr/bin/env python3
"""
GitHub PR Review Skill

World-class automated code reviews. One command, everything posted to GitHub.
"""

import sys
import os
import re
import subprocess
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass

from github_api import GitHubAPI
from checklist import ReviewChecklist
from conventional import ReviewSummary, ConventionalComment, Label, Decoration
from analyzer import DiffAnalyzer


@dataclass
class ReviewContext:
    """Context for the review."""
    pr_number: str
    repo: str
    pr_info: Dict
    diff: str
    files: List[Dict]
    commits: List[Dict]
    checks: List[Dict]

    @property
    def pr_size(self) -> int:
        """Count total lines changed."""
        total = 0
        for file in self.files:
            total += file.get("additions", 0)
            total += file.get("deletions", 0)
        return total

    @property
    def has_description(self) -> bool:
        """Check if PR has a description."""
        body = self.pr_info.get("body", "")
        return len(body) > 50

    @property
    def has_tests(self) -> bool:
        """Check if PR includes test changes."""
        for file in self.files:
            path = file.get("path", "").lower()
            if "test" in path or "spec" in path:
                return True
        return False

    @property
    def ci_passing(self) -> bool:
        """Check if CI is passing."""
        if not self.checks:
            return True  # No checks means no failures
        for check in self.checks:
            state = check.get("state")
            if state not in ["SUCCESS", "PENDING", "QUEUED"]:
                return False
        return True


class Reviewer:
    """Main review orchestrator."""

    DEFAULT_REPO = "kokayicobb/consuelo_on_call_coaching"

    def __init__(self, pr_number: str, repo: Optional[str] = None):
        self.pr_number = pr_number
        self.api = GitHubAPI(repo or self.DEFAULT_REPO)
        self.checklist = ReviewChecklist()
        self.summary = ReviewSummary()
        self.analyzer = DiffAnalyzer()
        self.context: Optional[ReviewContext] = None

    def run(self, flags: Dict[str, bool] = None) -> bool:
        """Run the full review.

        When --auto is set, this operates in automated mode:
        - Reviews the PR normally
        - Determines if the change is "big" or "small"
        - Small + no blocking issues → auto-approve, merge, deploy check
        - Small + blocking issues → Slack notification
        - Big → Slack notification requesting manual review

        Returns bool for normal mode, or a dict for auto mode with deploy info.
        """
        if flags is None:
            flags = {}

        self._auto_mode = flags.get("auto", False)

        sys.stdout.write(f"Starting review for PR #{self.pr_number}...\n")
        if self._auto_mode:
            sys.stdout.write("  (auto mode — will decide big/small after review)\n")

        # Phase 1: Gather context
        if not self._gather_context():
            sys.stdout.write("Failed to gather PR context\n")
            return False

        sys.stdout.write(f"Gathered context: {self.context.pr_size} lines changed\n")

        # Phase 1.5: Spec compliance check
        self._check_spec_compliance()

        # Phase 2: Walk through checklist
        sys.stdout.write("Walking through checklist...\n")
        self._walk_checklist()

        # Phase 3: Analyze diff
        sys.stdout.write("Analyzing code changes...\n")
        self._analyze_diff()

        # Phase 4: Synthesize and categorize
        sys.stdout.write("Synthesizing findings...\n")
        labels = self._synthesize()

        # Phase 4.5: Live testing (if --test flag)
        if flags.get("test", False):
            sys.stdout.write("Running live tests with agent browser...\n")
            test_results = self._run_live_tests()
            if test_results:
                self._add_test_results(test_results)

        # Phase 5: Check if should split
        if flags.get("split_pr", False):
            self._check_split_suggestion()

        # Phase 6: Post to GitHub (unless local-only)
        if not flags.get("local_only", False):
            sys.stdout.write("Posting to GitHub...\n")
            post_success = self._post_review(labels, flags.get("approve", False))

            # Phase 7: Auto mode — decide and act
            if self._auto_mode and post_success:
                return self._handle_auto_mode(labels)

            return post_success
        else:
            sys.stdout.write("Local-only mode - skipping posting\n")
            self._print_local_summary(labels)
            return True

    def _gather_context(self) -> bool:
        """Gather all PR context."""
        # Get PR info
        self.pr_info = self.api.get_pr_info(self.pr_number)
        if not self.pr_info:
            return False

        # Get diff
        diff = self.api.get_pr_diff(self.pr_number)
        if not diff:
            return False

        # Get files
        files = self.api.get_pr_files(self.pr_number)
        if files is None:
            return False

        # Get commits
        commits = self.api.get_pr_commits(self.pr_number)
        if commits is None:
            return False

        # Get checks
        checks = self.api.get_pr_checks(self.pr_number)
        if checks is None:
            checks = []

        self.context = ReviewContext(
            pr_number=self.pr_number,
            repo=self.pr_info.get("headRepository", {}).get("name", ""),
            pr_info=self.pr_info,
            diff=diff,
            files=files,
            commits=commits,
            checks=checks
        )

        return True

    def _extract_verification_criteria(self, body: str) -> List[str]:
        """Extract verification criteria checkboxes from PR body."""
        criteria = []
        in_section = False

        for line in body.split("\n"):
            # Detect start of verification section
            if re.search(r'(?i)(verification criteria|VERIFICATION)', line):
                in_section = True
                continue

            if in_section:
                # Stop at next markdown header or horizontal rule
                if line.startswith("#") or line.strip() == "---":
                    break
                # Capture checkbox items
                match = re.match(r'\s*-\s*\[[ x]\]\s*(.*)', line)
                if match:
                    criteria.append(match.group(1).strip())

        return criteria

    def _check_spec_compliance(self):
        """Check if PR changes satisfy the original task spec criteria."""
        if not self.context:
            return

        body = self.context.pr_info.get("body", "")
        criteria = self._extract_verification_criteria(body)

        if not criteria:
            return  # No spec criteria found in PR body

        sys.stdout.write(f"📋 Checking {len(criteria)} verification criteria...\n")

        passed = 0
        failed = 0
        unknown = 0

        for criterion in criteria:
            result = self.analyzer.check_verification_criterion(
                criterion, self.context.diff, self.context.files
            )

            if result == "pass":
                self.checklist.check(f"Spec: {criterion}")
                passed += 1
            elif result == "fail":
                self.summary.add_comment(ConventionalComment(
                    label=Label.ISSUE,
                    subject=f"Spec criterion not met: {criterion}",
                    decorations=[Decoration.BLOCKING],
                    discussion=(
                        f"The original task spec requires: {criterion}\n"
                        "This doesn't appear to be implemented in the current changes."
                    )
                ))
                failed += 1
            else:
                self.summary.add_comment(ConventionalComment(
                    label=Label.QUESTION,
                    subject=f"Spec criterion unverified: {criterion}",
                    decorations=[Decoration.NON_BLOCKING],
                    discussion=(
                        f"Could not automatically verify: {criterion}\n"
                        "Manual review recommended for this criterion."
                    )
                ))
                unknown += 1

        sys.stdout.write(
            f"  Spec compliance: {passed} passed, {failed} failed, {unknown} unknown\n"
        )

    def _walk_checklist(self):
        """Walk through the checklist systematically by analyzing the actual code."""
        diff_content = self.context.diff.lower()
        file_paths = [f.get("path", "").lower() for f in self.context.files]

        # === FUNCTIONALITY ===
        # Check if error handling exists in new code
        error_patterns = ["try", "catch", "throw", "error", "exception"]
        has_error_handling = any(p in diff_content for p in error_patterns)
        if has_error_handling:
            self.checklist.check("error handling verified")
        elif self.context.has_tests:
            self.checklist.check("error handling verified")

        # Check if inputs are validated (look for validation keywords)
        validation_patterns = ["validate", "sanitize", "check", "verify", "guard"]
        has_input_validation = any(p in diff_content for p in validation_patterns)
        if has_input_validation:
            self.checklist.check("inputs validated")
        elif self.context.has_tests:
            self.checklist.check("inputs validated")

        # === READABILITY ===
        # Check for descriptive names (look for magic numbers, single letter vars)
        # Single letter variables on their own line suggest poor naming
        has_magic_numbers = bool(re.search(r'\b\d{4,}\b', diff_content)) and "const " in diff_content
        if not has_magic_numbers:
            self.checklist.check("no magic numbers/strings")

        # Check for comments/documentation
        if "// " in diff_content or "# " in diff_content or "/*" in diff_content:
            self.checklist.check("well-documented with comments")

        # Descriptive names - check for single-letter variable declarations
        # But exclude loop counters like i, j, k
        bad_var_pattern = r'\b(let|const|var)\s+[a-z]\s*='
        has_poor_names = bool(re.search(bad_var_pattern, diff_content))
        if not has_poor_names:
            self.checklist.check("descriptive variable/function names")

        # Logical organization - check for very long files (could indicate poor organization)
        file_sizes = [f.get("additions", 0) for f in self.context.files]
        avg_file_size = sum(file_sizes) / len(file_sizes) if file_sizes else 0
        if avg_file_size < 500:  # Reasonable average file size
            self.checklist.check("logical code organization")

        # === SECURITY ===
        # Input sanitization - check for .innerHTML, .innerHTML = dangerous
        has_innerhtml = "innerhtml" in diff_content or "innerhtml =" in diff_content
        if not has_innerhtml:
            self.checklist.check("no XSS vulnerabilities")

        # SQL injection - check for SQL string concatenation
        has_sql_concat = re.search(r'["\']\s*\+\s*["\']', diff_content) and "sql" in diff_content
        if not has_sql_concat:
            self.checklist.check("no SQL injection vulnerabilities")

        # Access controls - check if auth-related files are touched
        has_auth_files = any("auth" in p or "login" in p for p in file_paths)
        if has_auth_files:
            self.checklist.check("access controls checked")

        # Sensitive data - check for hardcoded secrets
        secret_patterns = ["api_key", "apikey", "secret", "password", "token"]
        has_hardcoded_secrets = any(p in diff_content for p in secret_patterns) and ("const " or "let " or "var ") in diff_content
        if not has_hardcoded_secrets:
            self.checklist.check("sensitive data properly handled")

        # === PERFORMANCE ===
        # Check for potential N+1 queries (nested loops with database calls)
        has_nested_db_pattern = re.search(r'(for|while).*\{(.*\n.*){5,}.*\}(.*\n.*){2,}.*query|db|database', diff_content)
        if not has_nested_db_pattern:
            self.checklist.check("no unnecessary database queries")

        # Check for caching patterns
        cache_patterns = ["cache", "memoize", "memoization"]
        has_caching = any(p in diff_content for p in cache_patterns)
        if has_caching:
            self.checklist.check("caching where appropriate")

        # === MAINTAINABILITY ===
        # Check for modularity - reasonable file count, not too monolithic
        if len(self.context.files) < 50 and len(self.context.files) > 5:
            self.checklist.check("modular functions (single responsibility)")

        # Check for code duplication (diff stats: if deletions > 0.5 * additions, may indicate refactoring)
        additions = sum(f.get("additions", 0) for f in self.context.files)
        deletions = sum(f.get("deletions", 0) for f in self.context.files)
        if deletions < additions * 0.5:
            self.checklist.check("no code duplication")

        # === CODING STANDARDS ===
        # Project conventions - assuming consistent patterns in existing code
        # Check if TypeScript interfaces exist (indicates typing)
        if "interface " in diff_content or "type " in diff_content:
            self.checklist.check("consistent naming conventions")  # Type definitions suggest consistency

        # Linter/Format - check for consistent indentation
        lines = diff_content.split('\n')
        indent_pattern = r'^(\s+)'
        indents = [len(m.group(1)) for line in lines if (m := re.match(indent_pattern, line))]
        if indents and len(set(indents)) < 5:  # Few unique indentation levels
            self.checklist.check("consistent formatting")

        # Note: Items not checked above remain unchecked for manual review

    def _analyze_diff(self):
        """Analyze the diff for issues."""
        hunks = self.analyzer.parse_diff(self.context.diff)

        # Group by file
        files_to_analyze = {}
        for hunk in hunks:
            if hunk.file_path not in files_to_analyze:
                files_to_analyze[hunk.file_path] = []
            files_to_analyze[hunk.file_path].append(hunk)

        # Analyze each file
        for file_path, file_hunks in files_to_analyze.items():
            comments = self.analyzer.analyze_file(file_path, file_hunks)
            for comment in comments:
                self.summary.add_comment(comment)

        # Update checklist based on findings
        security_issues = self.summary.get_security_issues()
        if not security_issues:
            self.checklist.check("inputs sanitized/validated")
            self.checklist.check("no SQL injection vulnerabilities")
            self.checklist.check("no XSS vulnerabilities")

        # Check for hardcoded secrets
        for comment in self.summary.comments:
            if "hardcoded" in comment.subject.lower() and "secret" in comment.subject.lower():
                self.checklist.uncheck("sensitive data properly handled")

    def _synthesize(self) -> List[str]:
        """Synthesize findings and determine labels."""
        labels = []

        # Determine labels based on findings
        if not self.context.has_tests and not self.context.has_tests:
            labels.append("needs-tests")

        if not self.context.has_description:
            labels.append("needs-docs")

        if self.summary.get_security_issues():
            labels.append("security-review")

        if self.summary.get_blocking_issues():
            labels.append("changes-requested")

        # Add praise if no issues
        if not self.summary.comments:
            self.summary.add_comment(ConventionalComment(
                label=Label.PRAISE,
                subject="Clean PR - everything looks good!",
                decorations=[]
            ))

        return labels

    def _check_split_suggestion(self):
        """Check if PR should be split."""
        analysis = self.analyzer.analyze_complexity(self.context.diff, self.context.files)

        if analysis["should_split"]:
            reasons = "\n".join(f"- {r}" for r in analysis["reasons"])

            split_comment = f"""## ⚠️ Suggestion: Split This PR

This PR contains multiple distinct changes. Research shows that smaller, focused PRs are reviewed more thoroughly and merged faster.

**Reasons:**
{reasons}

**Suggested Splits:**
"""
            for i, split in enumerate(analysis["suggested_splits"], 1):
                split_comment += f"{i}. {split}\n"

            split_comment += """
Smaller PRs are:
- 3x more likely to be reviewed thoroughly
- Faster to merge
- Easier to revert if needed
- Less likely to have merge conflicts

Would you like help splitting this PR?
"""

            # Post split suggestion
            if self.context:
                self.api.post_comment(self.context.pr_number, split_comment)

    def _has_recent_review(self) -> bool:
        """Check if a review was already posted recently (within 2 hours)."""
        import datetime
        import urllib.request
        import urllib.error

        try:
            # Get token
            env = {"PATH": "/opt/homebrew/bin:" + os.environ.get("PATH", "")}
            token_result = subprocess.run(
                ["gh", "auth", "token"],
                capture_output=True, text=True, env=env
            )
            token = token_result.stdout.strip() if token_result.returncode == 0 else ""

            if not token or not self.api.repo:
                return False

            # Fetch comments via GitHub API
            headers = {
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github.v3+json"
            }

            url = f"https://api.github.com/repos/{self.api.repo}/issues/{self.context.pr_number}/comments"
            req = urllib.request.Request(url, headers=headers)

            with urllib.request.urlopen(req) as response:
                import json
                comments = json.loads(response.read().decode())

            now = datetime.datetime.now(datetime.timezone.utc)

            for comment in comments:
                body = comment.get("body", "")
                user_login = comment.get("user", {}).get("login", "")
                created_at = comment.get("created_at", "")

                # Check if it's our bot and has review content
                # Comments from gh CLI are posted as the authenticated user
                if "## Review Summary" in body and "## ✅ Code Review Checklist" in body:
                    created = datetime.datetime.fromisoformat(created_at.replace("Z", "+00:00"))
                    age = now - created
                    if age.total_seconds() < 7200:  # 2 hours
                        sys.stdout.write(f"⚠️ Recent review exists ({int(age.seconds // 60)} min ago) - skipping new post\n")
                        return True

        except Exception as e:
            sys.stdout.write(f"⚠️ Could not check for existing reviews: {e}\n")

        return False

    def _post_review(self, labels: List[str], approve: bool = False) -> bool:
        """Post the complete review to GitHub using batch review API."""
        if not self.context:
            return False

        # Check for recent review to avoid duplicates
        if self._has_recent_review():
            sys.stdout.write("📋 Applying labels to existing review...\n")
            for label in labels:
                self.api.add_label(self.context.pr_number, label)
            return True

        success = True

        # Get the head commit sha for inline comments
        head_commit = self.context.pr_info.get("headRefOid", "")
        if not head_commit:
            sys.stdout.write("⚠️ Warning: could not get head commit sha for inline comments\n")
            head_commit = None

        # Combine checklist and summary for review body
        checklist_text = self.checklist.format()
        summary_text = self.summary.format(
            self.context.pr_size,
            self.context.has_description,
            self.context.has_tests
        )
        review_body = f"{summary_text}\n\n{checklist_text}"

        # Determine review event
        review_event = "COMMENT"
        if approve and not self.summary.has_blocking():
            review_event = "APPROVE"
        elif self.summary.has_blocking():
            review_event = "REQUEST_CHANGES"

        # Prepare inline comments for batch review
        comments_data = []
        for comment in self.summary.comments:
            if comment.file_path and comment.line and head_commit:
                comments_data.append({
                    "file_path": comment.file_path,
                    "line": comment.line,
                    "body": comment.format_inline()
                })

        # For very large PRs (30K+ lines), inline comments often fail with 422
        # because GitHub can't validate line numbers against the full diff
        is_large_pr = self.context.pr_size > 25000

        if is_large_pr:
            # Skip inline comments for large PRs, just post summary
            sys.stdout.write(f"⚠️ Large PR ({self.context.pr_size} lines) - posting summary only\n")
            if self.api.post_comment(self.context.pr_number, review_body):
                sys.stdout.write("✓ Review summary posted\n")
            else:
                sys.stdout.write("❌ Failed to post review summary\n")
                success = False
        else:
            # Normal flow for smaller PRs
            print(f"Posting batch review with {len(comments_data)} inline comments...", file=sys.stderr)
            if not self.api.post_review(
                self.context.pr_number,
                review_event,
                review_body,
                comments_data
            ):
                sys.stdout.write("❌ Failed to post batch review\n")
                success = False
                # Fallback: post summary+checklist as regular comments
                sys.stdout.write("⚠️ Falling back to posting summary as regular comment...\n")
                if not self.api.post_comment(self.context.pr_number, review_body):
                    sys.stdout.write("❌ Failed to post fallback comment\n")
                    success = False
            else:
                sys.stdout.write(f"✓ Batch review posted ({review_event})\n")

        # Apply labels
        for label in labels:
            if not self.api.add_label(self.context.pr_number, label):
                sys.stdout.write(f"⚠️ Failed to add label: {label}\n")

        return success

    def _print_local_summary(self, labels: List[str]):
        """Display summary in local-only mode."""
        out = sys.stdout.write
        out("\n" + "="*60 + "\n")
        out("LOCAL-ONLY PREVIEW\n")
        out("="*60 + "\n")

        out(f"\n📊 PR Size: {self.context.pr_size} lines\n")
        out(f"📝 Description: {'✓' if self.context.has_description else '✗'}\n")
        out(f"🧪 Tests: {'✓' if self.context.has_tests else '✗'}\n")
        out(f"✅ CI: {'✓ Passing' if self.context.ci_passing else '✗ Failing'}\n")

        out(f"\n🏷️  Labels: {', '.join(labels) if labels else 'none'}\n")

        out("\n📋 Checklist:\n")
        for item in self.checklist.get_unchecked()[:5]:
            out(f"  - [ ] {item.text}\n")
        if len(self.checklist.get_unchecked()) > 5:
            out(f"  ... and {len(self.checklist.get_unchecked()) - 5} more\n")

        out(f"\n💬 Comments: {len(self.summary.comments)}\n")
        out(f"  - Blocking: {len(self.summary.get_blocking_issues())}\n")
        out(f"  - Security: {len(self.summary.get_security_issues())}\n")
        out(f"  - Suggestions: {len(self.summary.suggestions)}\n")
        out(f"  - Nitpicks: {len(self.summary.nitpicks)}\n")

        out("\n" + "="*60 + "\n")

    # -----------------------------------------------------------------------
    # Auto mode — big/small detection, merge, deploy, retry
    # -----------------------------------------------------------------------

    def _is_small_change(self) -> bool:
        """Determine if this PR is a 'small' change suitable for auto-merge.

        Small = <10 files changed AND <500 total lines AND single logical concern.
        """
        if not self.context:
            return False

        num_files = len(self.context.files)
        total_lines = self.context.pr_size

        # hard thresholds
        if num_files >= 10 or total_lines >= 500:
            return False

        # check for multiple distinct concerns (frontend + backend, etc.)
        file_paths = [f.get("path", "").lower() for f in self.context.files]
        has_frontend = any("component" in p or ".tsx" in p or ".jsx" in p or "page" in p for p in file_paths)
        has_backend = any("api" in p or "route" in p or "server" in p or "handler" in p for p in file_paths)
        has_schema = any("schema" in p or "migration" in p or "model" in p for p in file_paths)

        distinct_areas = sum([has_frontend, has_backend, has_schema])
        if distinct_areas >= 2:
            return False  # cross-cutting change = big

        return True

    def _handle_auto_mode(self, labels: List[str]) -> bool:
        """Handle automated review decisions after posting the review.

        Returns True if the automated flow completed (regardless of deploy result).
        """
        is_small = self._is_small_change()
        has_blocking = self.summary.has_blocking()

        sys.stdout.write(f"\n--- Auto Mode ---\n")
        sys.stdout.write(f"  Change size: {'small' if is_small else 'big'}\n")
        sys.stdout.write(f"  Blocking issues: {len(self.summary.get_blocking_issues())}\n")

        if is_small and not has_blocking:
            # auto-approve, merge, deploy check
            sys.stdout.write("  Decision: auto-approve and merge\n")

            # approve
            self.api.approve_pr(self.pr_number, "Auto-approved by Kiro pipeline (small change, no blocking issues)")

            # merge
            merged = self._merge_pr()
            if not merged:
                sys.stdout.write("  Failed to merge PR\n")
                self._send_slack_notification(
                    f"Failed to merge PR #{self.pr_number} after auto-approval. Manual intervention needed.",
                    level="warning",
                )
                return False

            sys.stdout.write("  PR merged. Starting deploy check...\n")

            # deploy check
            deploy_result = self._check_railway_deploy()
            if deploy_result.get("deployed"):
                sys.stdout.write("  Deploy successful!\n")
                self._send_slack_notification(
                    f"PR #{self.pr_number} auto-merged and deployed successfully.",
                    level="success",
                )
                return True
            else:
                error = deploy_result.get("error", "unknown error")
                sys.stdout.write(f"  Deploy FAILED: {error}\n")
                self._send_slack_notification(
                    f"PR #{self.pr_number} deployed but Railway failed:\n```\n{error}\n```\n"
                    f"Triggering Kiro retry.",
                    level="error",
                )
                # Write deploy failure info for the pr-watcher to pick up
                self._write_deploy_failure(deploy_result)
                return False

        elif is_small and has_blocking:
            sys.stdout.write("  Decision: small change but has blocking issues — notify\n")
            blocking = self.summary.get_blocking_issues()
            issues_text = "\n".join(f"- {c.subject}" for c in blocking[:5])
            self._send_slack_notification(
                f"PR #{self.pr_number} has blocking issues (small change):\n{issues_text}\n"
                f"Fix needed before auto-merge.",
                level="warning",
            )
            return True

        else:
            # big change — just notify
            sys.stdout.write("  Decision: big change — requesting manual review via Slack\n")
            self._send_slack_notification(
                f"PR #{self.pr_number} needs manual review (big change: "
                f"{len(self.context.files)} files, {self.context.pr_size} lines).\n"
                f"Title: {self.context.pr_info.get('title', 'N/A')}\n"
                f"URL: {self.context.pr_info.get('url', 'N/A')}",
                level="info",
            )
            return True

    def _merge_pr(self) -> bool:
        """Merge the PR using squash merge."""
        env = os.environ.copy()
        env["PATH"] = "/opt/homebrew/bin:" + env.get("PATH", "")
        cmd = ["gh", "pr", "merge", str(self.pr_number), "--squash", "--delete-branch"]
        if self.api.repo:
            cmd.extend(["--repo", self.api.repo])

        result = subprocess.run(cmd, capture_output=True, text=True, env=env)
        if result.returncode != 0:
            sys.stdout.write(f"  merge error: {result.stderr.strip()}\n")
        return result.returncode == 0

    def _check_railway_deploy(self) -> Dict:
        """Check Railway deployment status after merge.

        Sleeps for 5 minutes to allow Railway to deploy, then checks logs.

        Returns:
            dict with keys:
            - deployed: bool
            - error: str (if failed)
            - pr_number: str
            - branch: str
        """
        import time

        pr_branch = self.context.pr_info.get("headRefName", "") if self.context else ""

        sys.stdout.write("  Waiting 5 minutes for Railway deploy...\n")
        time.sleep(300)  # 5 minutes

        env = os.environ.copy()
        env["PATH"] = "/opt/homebrew/bin:" + env.get("PATH", "")

        # Check Railway logs for errors
        try:
            result = subprocess.run(
                ["railway", "logs", "--latest", "-n", "50"],
                capture_output=True, text=True, env=env, timeout=30,
            )

            logs = result.stdout + result.stderr
            log_lower = logs.lower()

            # Look for error indicators
            error_indicators = [
                "error", "fatal", "failed", "crash", "exception",
                "econnrefused", "typeerror", "referenceerror", "syntaxerror",
                "module not found", "cannot find module",
            ]

            errors_found = [ind for ind in error_indicators if ind in log_lower]

            if errors_found or result.returncode != 0:
                # Extract relevant error lines
                error_lines = []
                for line in logs.split("\n"):
                    if any(ind in line.lower() for ind in error_indicators):
                        error_lines.append(line.strip())

                error_summary = "\n".join(error_lines[:10]) if error_lines else logs[-500:]

                return {
                    "deployed": False,
                    "error": error_summary,
                    "pr_number": self.pr_number,
                    "branch": pr_branch,
                    "full_logs": logs[-2000:],
                }

            # Check for success indicators
            success_indicators = ["listening", "ready", "started", "deployed", "serving"]
            has_success = any(ind in log_lower for ind in success_indicators)

            if has_success:
                return {
                    "deployed": True,
                    "pr_number": self.pr_number,
                    "branch": pr_branch,
                }

            # No clear signal — assume success if no errors
            sys.stdout.write("  No clear error/success signal in logs. Assuming success.\n")
            return {
                "deployed": True,
                "pr_number": self.pr_number,
                "branch": pr_branch,
            }

        except subprocess.TimeoutExpired:
            return {
                "deployed": False,
                "error": "Railway CLI timed out",
                "pr_number": self.pr_number,
                "branch": pr_branch,
            }
        except FileNotFoundError:
            sys.stdout.write("  Railway CLI not found. Skipping deploy check.\n")
            return {
                "deployed": True,  # assume ok if no Railway CLI
                "pr_number": self.pr_number,
                "branch": pr_branch,
            }

    def _send_slack_notification(self, message: str, level: str = "info") -> bool:
        """Send a Slack notification to #suelo channel.

        Uses the Slack webhook URL from env var SLACK_WEBHOOK_URL.
        Falls back to posting via slack CLI if available.
        """
        import urllib.request
        import json

        webhook_url = os.environ.get("SLACK_WEBHOOK_URL")

        # emoji prefix based on level
        prefix = {
            "success": "[ok]",
            "warning": "[warn]",
            "error": "[error]",
            "info": "[info]",
        }.get(level, "")

        full_message = f"{prefix} {message}" if prefix else message

        if webhook_url:
            try:
                data = json.dumps({"text": full_message}).encode()
                req = urllib.request.Request(
                    webhook_url,
                    data=data,
                    headers={"Content-Type": "application/json"},
                    method="POST",
                )
                with urllib.request.urlopen(req) as resp:
                    return resp.status == 200
            except Exception as e:
                sys.stdout.write(f"  Slack webhook error: {e}\n")

        # Fallback: try slack CLI or just print
        sys.stdout.write(f"  [SLACK] {full_message}\n")
        return False

    def _write_deploy_failure(self, deploy_result: Dict) -> None:
        """Write deploy failure info to a file for the pr-watcher to pick up."""
        failure_file = os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            "..", "kiro", "deploy-failures",
            f"pr-{self.pr_number}.json",
        )
        os.makedirs(os.path.dirname(failure_file), exist_ok=True)

        import json
        with open(failure_file, "w") as f:
            json.dump(deploy_result, f, indent=2)
        sys.stdout.write(f"  Deploy failure saved: {failure_file}\n")

    # -----------------------------------------------------------------------
    # End auto mode methods
    # -----------------------------------------------------------------------

    def _extract_linear_task_id(self) -> Optional[str]:
        """Extract Linear task ID from PR body."""
        body = self.context.pr_info.get("body", "")

        # Look for common patterns: "DEV-123", "Linear: DEV-123", "Task: DEV-123"
        patterns = [
            r'DEV-\d+',
            r'(?i)linear\s*[:]\s*([A-Z]+-\d+)',
            r'(?i)task\s*[:]\s*([A-Z]+-\d+)',
        ]

        for pattern in patterns:
            match = re.search(pattern, body)
            if match:
                # Return the full match (DEV-123)
                return match.group(0) if match.groups() else match.group(0)

        return None

    def _fetch_linear_task(self, task_id: str) -> Optional[Dict]:
        """Fetch Linear task details using GraphQL API."""
        import os
        import subprocess

        # Try to get LINEAR_API_KEY from environment or config
        linear_key = os.environ.get("LINEAR_API_KEY")

        if not linear_key:
            # Try to source from .agent/linear-api.sh if it exists
            workspace = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            linear_api_sh = os.path.join(workspace, ".agent", "linear-api.sh")

            if os.path.exists(linear_api_sh):
                try:
                    result = subprocess.run(
                        ['bash', '-c', f'source "{linear_api_sh}" && echo $LINEAR_API_KEY'],
                        capture_output=True,
                        text=True
                    )
                    linear_key = result.stdout.strip()
                except Exception as e:
                    sys.stdout.write(f"⚠️ Could not load Linear API key: {e}\n")

        if not linear_key:
            sys.stdout.write("⚠️ LINEAR_API_KEY not found. Skipping Linear task fetch.\n")
            return None

        # Query Linear GraphQL API
        query = """
        query Issue($identifier: String!) {
            issue(identifier: $identifier) {
                id
                identifier
                title
                description
                state {
                    name
                }
                labels {
                    nodes {
                        name
                    }
                }
            }
        }
        """

        import json
        try:
            import requests
            response = requests.post(
                "https://api.linear.app/graphql",
                headers={
                    "Authorization": linear_key,
                    "Content-Type": "application/json"
                },
                json={
                    "query": query,
                    "variables": {"identifier": task_id}
                },
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()
                if data.get("data", {}).get("issue"):
                    return data["data"]["issue"]
                else:
                    sys.stdout.write(f"⚠️ Linear task {task_id} not found\n")
                    return None
            else:
                sys.stdout.write(f"⚠️ Failed to fetch Linear task: {response.status_code}\n")
                return None

        except ImportError:
            sys.stdout.write("⚠️ requests library not installed. Skipping Linear fetch.\n")
            return None
        except Exception as e:
            sys.stdout.write(f"⚠️ Error fetching Linear task: {e}\n")
            return None

    def _run_live_tests(self) -> Optional[Dict]:
        """Run live tests using agent browser."""
        import subprocess
        import os

        # Extract Linear task ID
        linear_task_id = self._extract_linear_task_id()
        linear_task = None

        if linear_task_id:
            sys.stdout.write(f"📋 Found Linear task: {linear_task_id}\n")
            linear_task = self._fetch_linear_task(linear_task_id)

        # Extract staging URL from PR body
        body = self.context.pr_info.get("body", "")
        url_match = re.search(r'(?:preview|staging|deploy)\s*[:]\s*(https?://[^\s\n]+)', body, re.IGNORECASE)

        staging_url = None
        if url_match:
            staging_url = url_match.group(1).rstrip('.,')
            sys.stdout.write(f"🌐 Found staging URL: {staging_url}\n")

        if not staging_url:
            # Try to find Railway or Vercel preview URLs
            url_match = re.search(r'https?://[^\s\n]*?(?:railway|vercel)\.app/[^\s\n]*', body)
            if url_match:
                staging_url = url_match.group(0).rstrip('.,')
                sys.stdout.write(f"🌐 Found deployment URL: {staging_url}\n")

        if not staging_url:
            sys.stdout.write("⚠️ No staging URL found in PR. Skipping live tests.\n")
            return None

        # Build test instructions for agent browser
        test_instructions = self._build_test_instructions(linear_task, staging_url)

        # Create a temporary file with test instructions
        import tempfile
        with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
            f.write(test_instructions)
            test_file = f.name

        try:
            sys.stdout.write("🚀 Launching agent browser for testing...\n")

            # Run agent-browser with the test instructions
            # This assumes agent-browser is available as a CLI tool
            result = subprocess.run(
                ['agent-browser', 'test', '--instructions', test_file],
                capture_output=True,
                text=True,
                timeout=300  # 5 minute timeout
            )

            # Parse the results
            if result.returncode == 0:
                sys.stdout.write("✓ Agent browser tests completed\n")
                return self._parse_agent_browser_results(result.stdout, staging_url)
            else:
                sys.stdout.write(f"⚠️ Agent browser failed: {result.stderr}\n")
                return None

        except subprocess.TimeoutExpired:
            sys.stdout.write("⚠️ Agent browser timed out\n")
            return None
        except FileNotFoundError:
            sys.stdout.write("⚠️ agent-browser CLI not found. Install it first.\n")
            return None
        except Exception as e:
            sys.stdout.write(f"⚠️ Error running agent browser: {e}\n")
            return None
        finally:
            # Clean up temp file
            try:
                os.unlink(test_file)
            except:
                pass

    def _build_test_instructions(self, linear_task: Optional[Dict], staging_url: str) -> str:
        """Build test instructions for agent browser based on task and PR changes."""
        instructions = f"""# Live Testing Instructions

Staging URL: {staging_url}
"""

        if linear_task:
            instructions += f"""
Linear Task: {linear_task.get('identifier')} - {linear_task.get('title')}

Task Description:
{linear_task.get('description', 'No description')}
"""

        instructions += f"""
## What Changed in This PR

Based on the PR diff, focus testing on:
"""

        # Analyze the diff to identify what to test
        file_types = {}
        for file in self.context.files:
            path = file.get("path", "").lower()
            if path.endswith('.tsx') or path.endswith('.jsx'):
                file_types['UI/Frontend'] = file_types.get('UI/Frontend', 0) + file.get('additions', 0)
            elif path.endswith('.py') or path.endswith('.js') and ('api' in path or 'route' in path):
                file_types['API/Routes'] = file_types.get('API/Routes', 0) + file.get('additions', 0)
            elif path.endswith('.sql') or 'migration' in path or 'schema' in path:
                file_types['Database'] = file_types.get('Database', 0) + file.get('additions', 0)

        for file_type, lines in sorted(file_types.items(), key=lambda x: x[1], reverse=True):
            instructions += f"- {file_type} changes ({lines} lines)\n"

        instructions += """
## Test Checklist

Navigate to the staging URL and test the following:
"""

        # Extract verification criteria from PR body
        criteria = self._extract_verification_criteria(self.context.pr_info.get("body", ""))

        if criteria:
            for i, criterion in enumerate(criteria, 1):
                instructions += f"{i}. {criterion}\n"
        else:
            instructions += """1. Navigate to the application and identify which UI/feature changed
2. Test the core functionality (what the feature is supposed to do)
3. Test error states (invalid inputs, network errors, etc.)
4. Test edge cases (empty states, boundary conditions)
5. Check responsive behavior on different screen sizes (if UI changes)
"""

        instructions += """
## Report Format

After testing, report in this format:

## Test Results

### Summary
[PASS/FAIL/MIXED] - Brief summary of test results

### What Worked
- Feature 1: Working as expected
- Feature 2: Working as expected

### What Failed
- Issue 1: Description + expected vs actual
- Issue 2: Description + expected vs actual

### Edge Cases Tested
- Case 1: Result
- Case 2: Result

### Screenshots (if applicable)
[Brief description of what screenshot would show]

### Overall Assessment
- Ready to merge / Needs fixes / Needs more testing
"""

        return instructions

    def _parse_agent_browser_results(self, output: str, staging_url: str) -> Dict:
        """Parse the output from agent browser testing."""
        # For now, just return the raw output as a structured dict
        # In the future, we can parse this more intelligently
        return {
            "staging_url": staging_url,
            "raw_output": output,
            "summary": self._extract_test_summary(output),
            "passed": output.count("PASS") if "PASS" in output else 0,
            "failed": output.count("FAIL") if "FAIL" in output else 0,
        }

    def _extract_test_summary(self, output: str) -> str:
        """Extract a brief summary from test output."""
        # Look for "### Summary" or similar patterns
        lines = output.split('\n')
        for i, line in enumerate(lines):
            if 'summary' in line.lower():
                # Return the next few lines
                return '\n'.join(lines[i:i+5])
        return "Tests completed. See detailed output above."

    def _add_test_results(self, results: Dict):
        """Add test results to the review summary."""
        summary = results.get("summary", "Tests completed")
        staging_url = results.get("staging_url", "")

        # Add as a conventional comment
        test_comment = ConventionalComment(
            label=Label.NOTE,
            subject=f"Live Test Results ({staging_url})",
            decorations=[Decoration.TEST],
            discussion=f"""
**Test Summary:**
{summary}

**Staging URL:** {staging_url}

**Stats:** {results.get('passed', 0)} passed, {results.get('failed', 0)} failed

**Detailed Results:**
```
{results.get('raw_output', '')}
```
"""
        )
        self.summary.add_comment(test_comment)

        # If tests failed, mark as blocking
        if results.get('failed', 0) > 0:
            blocking_comment = ConventionalComment(
                label=Label.ISSUE,
                subject="Live tests failed - please fix before merging",
                decorations=[Decoration.BLOCKING, Decoration.TEST],
                discussion=f"One or more live tests failed. See the test results above for details. All tests must pass before this PR can be approved."
            )
            self.summary.add_comment(blocking_comment)


def parse_pr_number(input_str: str) -> Tuple[str, Optional[str]]:
    """Parse PR number and optional repo from input."""
    # URL format
    if "github.com" in input_str:
        match = re.search(r'/pull/(\d+)', input_str)
        if match:
            pr_number = match.group(1)
            # Extract repo from URL
            repo_match = re.search(r'github\.com/([^/]+/[^/]+)/', input_str)
            repo = repo_match.group(1) if repo_match else None
            return pr_number, repo

    # Just number
    if input_str.isdigit():
        return input_str, None

    # Try to extract number
    match = re.search(r'(\d+)', input_str)
    if match:
        return match.group(1), None

    return input_str, None


def main():
    """Main entry point."""
    if len(sys.argv) < 2:
        sys.stdout.write("Usage: review <pr_number|url> [--local-only] [--approve] [--split-pr] [--verbose] [--test] [--auto]\n")
        sys.exit(1)

    # Parse input
    input_str = sys.argv[1]
    pr_number, repo = parse_pr_number(input_str)

    if not pr_number:
        sys.stdout.write(f"Could not parse PR number from: {input_str}\n")
        sys.exit(1)

    # Parse flags
    flags = {
        "local_only": "--local-only" in sys.argv,
        "approve": "--approve" in sys.argv,
        "split_pr": "--split-pr" in sys.argv,
        "verbose": "--verbose" in sys.argv,
        "test": "--test" in sys.argv,
        "auto": "--auto" in sys.argv,
    }

    # Run review
    reviewer = Reviewer(pr_number, repo)
    success = reviewer.run(flags)

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
