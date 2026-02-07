"""
Linear API client for fetching task details.

Pulls tasks by ID (e.g., CON-456) with full description,
acceptance criteria, comments, and metadata.

Uses Linear GraphQL API via requests.
"""

import os
import subprocess
import requests
from typing import Dict, Optional, List, Any
from datetime import datetime


class LinearAPI:
    """Client for fetching Linear tasks."""

    API_URL = "https://api.linear.app/graphql"

    # Hardcoded IDs for consuelo workspace
    TEAM_ID = "29f5c661-da6c-4bfb-bd48-815a006ccaac"

    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key or self._load_api_key()
        if not self.api_key:
            raise ValueError(
                "LINEAR_API_KEY not found. Set it as an env var or in .agent/linear-api.sh"
            )
        self.headers = {
            "Authorization": self.api_key,
            "Content-Type": "application/json",
        }

    @staticmethod
    def _load_api_key() -> Optional[str]:
        """Try loading the Linear API key from various sources."""
        # 1. Environment variable
        key = os.getenv("LINEAR_API_KEY")
        if key:
            return key

        # 2. Source from .agent/linear-api.sh (common pattern in this workspace)
        try:
            result = subprocess.run(
                ["bash", "-c", "source .agent/linear-api.sh 2>/dev/null && echo $LINEAR_API_KEY"],
                capture_output=True, text=True,
                cwd=os.path.expanduser("~/Dev/claude-agent-workflow"),
            )
            key = result.stdout.strip()
            if key:
                return key
        except Exception:
            pass

        # 3. Try the consuelo repo
        try:
            result = subprocess.run(
                ["bash", "-c", "source .agent/linear-api.sh 2>/dev/null && echo $LINEAR_API_KEY"],
                capture_output=True, text=True,
                cwd=os.path.expanduser("~/Dev/consuelo_on_call_coaching"),
            )
            key = result.stdout.strip()
            if key:
                return key
        except Exception:
            pass

        return None

    def _query(self, query: str, variables: Optional[Dict] = None) -> Dict:
        """Execute a GraphQL query."""
        response = requests.post(
            self.API_URL,
            headers=self.headers,
            json={"query": query, "variables": variables or {}},
        )
        response.raise_for_status()
        data = response.json()

        if data.get("errors"):
            raise Exception(f"Linear GraphQL error: {data['errors']}")

        return data.get("data", {})

    # -------------------------------------------------------------------------
    # Task fetching
    # -------------------------------------------------------------------------

    def get_task_by_identifier(self, identifier: str) -> Optional[Dict[str, Any]]:
        """
        Fetch a task by its identifier (e.g., "DEV-456").

        Returns a rich dict with:
        - id, identifier, title, description, priority, state, labels
        - comments (with author and timestamps)
        - parent issue (if subtask)
        - attachments/links
        - assignee info
        """
        # Parse the identifier — Linear uses "TEAM-NUMBER" format
        # Extract the number from e.g. "DEV-480"
        parts = identifier.split("-")
        if len(parts) != 2:
            print(f"[error] Invalid identifier format: {identifier}. Expected TEAM-NUMBER (e.g., DEV-480)")
            return None

        try:
            issue_number = int(parts[1])
        except ValueError:
            print(f"[error] Invalid issue number in identifier: {identifier}")
            return None

        query = """
        query GetIssue($teamId: ID!, $number: Float!) {
            issues(
                filter: {
                    team: { id: { eq: $teamId } }
                    number: { eq: $number }
                }
                first: 1
            ) {
                nodes {
                    id
                    identifier
                    title
                    description
                    priority
                    priorityLabel
                    state {
                        id
                        name
                        type
                    }
                    assignee {
                        name
                        email
                    }
                    creator {
                        name
                    }
                    labels {
                        nodes {
                            name
                            color
                        }
                    }
                    project {
                        name
                        id
                    }
                    parent {
                        identifier
                        title
                    }
                    children {
                        nodes {
                            identifier
                            title
                            state {
                                name
                            }
                        }
                    }
                    comments {
                        nodes {
                            body
                            createdAt
                            user {
                                name
                            }
                        }
                    }
                    attachments {
                        nodes {
                            title
                            url
                            metadata
                        }
                    }
                    url
                    createdAt
                    updatedAt
                    dueDate
                    estimate
                }
            }
        }
        """

        result = self._query(query, {"teamId": self.TEAM_ID, "number": issue_number})
        nodes = result.get("issues", {}).get("nodes", [])

        if not nodes:
            return None

        return nodes[0]

    def update_task_state(self, issue_id: str, state_name: str) -> bool:
        """
        Update a task's state (e.g., "In Progress", "In Review", "Done").
        """
        # First, resolve the state name to an ID
        state_id = self._get_state_id(state_name)
        if not state_id:
            print(f"[error] Could not find state '{state_name}'")
            return False

        mutation = """
        mutation IssueUpdate($id: String!, $input: IssueUpdateInput!) {
            issueUpdate(id: $id, input: $input) {
                success
                issue {
                    identifier
                    state {
                        name
                    }
                }
            }
        }
        """

        result = self._query(mutation, {
            "id": issue_id,
            "input": {"stateId": state_id},
        })

        return result.get("issueUpdate", {}).get("success", False)

    def add_comment(self, issue_id: str, body: str) -> bool:
        """Add a comment to a task."""
        mutation = """
        mutation CommentCreate($input: CommentCreateInput!) {
            commentCreate(input: $input) {
                success
            }
        }
        """

        result = self._query(mutation, {
            "input": {
                "issueId": issue_id,
                "body": body,
            },
        })

        return result.get("commentCreate", {}).get("success", False)

    def _get_state_id(self, state_name: str) -> Optional[str]:
        """Resolve a state name to its ID."""
        query = """
        query GetTeamStates($teamId: String!) {
            team(id: $teamId) {
                states {
                    nodes {
                        id
                        name
                    }
                }
            }
        }
        """

        result = self._query(query, {"teamId": self.TEAM_ID})
        states = result.get("team", {}).get("states", {}).get("nodes", [])

        for state in states:
            if state["name"].lower() == state_name.lower():
                return state["id"]

        return None

    # -------------------------------------------------------------------------
    # Formatting helpers
    # -------------------------------------------------------------------------

    @staticmethod
    def task_to_markdown(task: Dict[str, Any]) -> str:
        """
        Convert a Linear task dict to a well-structured markdown document.
        This is the "assignment sheet" that the agent reads from.
        """
        lines = []

        # Header
        lines.append(f"# {task['identifier']}: {task['title']}")
        lines.append("")

        # Metadata table
        lines.append("## Metadata")
        lines.append(f"- **Identifier:** {task['identifier']}")
        lines.append(f"- **Priority:** {task.get('priorityLabel', 'None')}")
        lines.append(f"- **State:** {task.get('state', {}).get('name', 'Unknown')}")

        if task.get("assignee"):
            lines.append(f"- **Assignee:** {task['assignee'].get('name', 'Unassigned')}")
        if task.get("creator"):
            lines.append(f"- **Creator:** {task['creator'].get('name', 'Unknown')}")

        labels = task.get("labels", {}).get("nodes", [])
        if labels:
            label_names = ", ".join(l["name"] for l in labels)
            lines.append(f"- **Labels:** {label_names}")

        if task.get("project"):
            lines.append(f"- **Project:** {task['project'].get('name', 'None')}")

        if task.get("dueDate"):
            lines.append(f"- **Due Date:** {task['dueDate']}")
        if task.get("estimate"):
            lines.append(f"- **Estimate:** {task['estimate']} points")

        lines.append(f"- **Created:** {task.get('createdAt', 'Unknown')[:10]}")
        lines.append(f"- **Updated:** {task.get('updatedAt', 'Unknown')[:10]}")
        lines.append(f"- **URL:** {task.get('url', 'N/A')}")
        lines.append(f"- **Linear ID:** {task.get('id', 'N/A')}")
        lines.append("")

        # Parent task (if this is a subtask)
        if task.get("parent"):
            lines.append("## Parent Task")
            parent = task["parent"]
            lines.append(f"- {parent['identifier']}: {parent['title']}")
            lines.append("")

        # Subtasks
        children = task.get("children", {}).get("nodes", [])
        if children:
            lines.append("## Subtasks")
            for child in children:
                state = child.get("state", {}).get("name", "")
                check = "x" if state in ("Done", "Completed", "Canceled") else " "
                lines.append(f"- [{check}] {child['identifier']}: {child['title']} ({state})")
            lines.append("")

        # Description (the main spec/body)
        lines.append("## Description")
        lines.append("")
        description = task.get("description", "")
        if description:
            lines.append(description)
        else:
            lines.append("*No description provided.*")
        lines.append("")

        # Comments
        comments = task.get("comments", {}).get("nodes", [])
        if comments:
            lines.append("## Comments")
            lines.append("")
            # Sort by date (oldest first)
            sorted_comments = sorted(comments, key=lambda c: c.get("createdAt", ""))
            for comment in sorted_comments:
                author = comment.get("user", {}).get("name", "Unknown")
                date = comment.get("createdAt", "")[:10]
                body = comment.get("body", "")
                lines.append(f"### {author} — {date}")
                lines.append("")
                lines.append(body)
                lines.append("")

        # Attachments
        attachments = task.get("attachments", {}).get("nodes", [])
        if attachments:
            lines.append("## Attachments")
            for att in attachments:
                title = att.get("title", "Untitled")
                url = att.get("url", "")
                lines.append(f"- [{title}]({url})")
            lines.append("")

        return "\n".join(lines)
