#!/usr/bin/env python3
"""
Linear Helper — CLI for creating/managing Linear issues from shell.

Designed for Kiro to call via shell commands when it determines a task
needs specs broken down into Linear issues.

Usage:
    # Create an issue
    python3 linear_helper.py create --title "Add auth middleware" --description "Full spec here" --label kiro

    # Create an issue with a parent
    python3 linear_helper.py create --title "Sub-task" --description "Details" --parent CON-456 --label kiro

    # List recent issues
    python3 linear_helper.py list --label kiro --limit 5

    # Add a label to an existing issue
    python3 linear_helper.py label CON-456 --add kiro
"""

import os
import sys
import json
import argparse

# Add github-dev to path for LinearAPI
SKILLS_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(SKILLS_ROOT, "github-dev"))

from linear_api import LinearAPI


def create_issue(args):
    """Create a new Linear issue."""
    linear = LinearAPI()

    # Build the mutation
    query = """
    mutation IssueCreate($input: IssueCreateInput!) {
        issueCreate(input: $input) {
            success
            issue {
                id
                identifier
                title
                url
            }
        }
    }
    """

    input_data = {
        "title": args.title,
        "teamId": LinearAPI.TEAM_ID,
    }

    if args.description:
        input_data["description"] = args.description

    if args.priority:
        # Linear priorities: 0=none, 1=urgent, 2=high, 3=medium, 4=low
        priority_map = {"urgent": 1, "high": 2, "medium": 3, "low": 4, "none": 0}
        input_data["priority"] = priority_map.get(args.priority.lower(), 3)

    if args.parent:
        # Resolve parent identifier to ID
        parent_task = linear.get_task_by_identifier(args.parent.upper())
        if parent_task:
            input_data["parentId"] = parent_task["id"]
        else:
            print(f"[warn] Parent task {args.parent} not found, creating without parent")

    result = linear._query(query, {"input": input_data})
    issue_create = result.get("issueCreate", {})

    if issue_create.get("success"):
        issue = issue_create["issue"]
        identifier = issue["identifier"]
        print(f"[ok] Created: {identifier} — {issue['title']}")
        print(f"     URL: {issue['url']}")

        # Add labels if specified
        if args.label:
            for label_name in args.label:
                add_label_to_issue(linear, issue["id"], label_name)

        return issue
    else:
        print("[error] Failed to create issue")
        sys.exit(1)


def add_label_to_issue(linear, issue_id, label_name):
    """Add a label to an issue by name."""
    # First, find or create the label
    label_id = find_or_create_label(linear, label_name)
    if not label_id:
        print(f"[warn] Could not find/create label: {label_name}")
        return

    # Add label to issue
    query = """
    mutation IssueAddLabel($id: String!, $labelId: String!) {
        issueAddLabel(id: $id, labelId: $labelId) {
            success
        }
    }
    """

    try:
        result = linear._query(query, {"id": issue_id, "labelId": label_id})
        if result.get("issueAddLabel", {}).get("success"):
            print(f"     Label added: {label_name}")
        else:
            print(f"[warn] Failed to add label: {label_name}")
    except Exception as e:
        print(f"[warn] Error adding label {label_name}: {e}")


def find_or_create_label(linear, label_name):
    """Find a label by name, or create it if it doesn't exist."""
    # Search for existing label
    query = """
    query FindLabel($teamId: ID!) {
        team(id: $teamId) {
            labels {
                nodes {
                    id
                    name
                }
            }
        }
    }
    """

    result = linear._query(query, {"teamId": LinearAPI.TEAM_ID})
    labels = result.get("team", {}).get("labels", {}).get("nodes", [])

    for label in labels:
        if label["name"].lower() == label_name.lower():
            return label["id"]

    # Label doesn't exist — create it
    create_query = """
    mutation CreateLabel($input: IssueLabelCreateInput!) {
        issueLabelCreate(input: $input) {
            success
            issueLabel {
                id
                name
            }
        }
    }
    """

    try:
        result = linear._query(create_query, {
            "input": {
                "name": label_name,
                "teamId": LinearAPI.TEAM_ID,
            }
        })
        created = result.get("issueLabelCreate", {})
        if created.get("success"):
            print(f"     Created label: {label_name}")
            return created["issueLabel"]["id"]
    except Exception as e:
        print(f"[warn] Error creating label: {e}")

    return None


def label_issue(args):
    """Add a label to an existing issue."""
    linear = LinearAPI()

    task = linear.get_task_by_identifier(args.identifier.upper())
    if not task:
        print(f"[error] Issue {args.identifier} not found")
        sys.exit(1)

    if args.add:
        for label_name in args.add:
            add_label_to_issue(linear, task["id"], label_name)


def list_issues(args):
    """List recent issues, optionally filtered by label."""
    linear = LinearAPI()

    # Query recent issues
    query = """
    query RecentIssues($teamId: ID!, $limit: Int!) {
        issues(
            filter: {
                team: { id: { eq: $teamId } }
            }
            orderBy: createdAt
            first: $limit
        ) {
            nodes {
                identifier
                title
                state { name }
                labels { nodes { name } }
                createdAt
            }
        }
    }
    """

    result = linear._query(query, {
        "teamId": LinearAPI.TEAM_ID,
        "limit": args.limit,
    })
    issues = result.get("issues", {}).get("nodes", [])

    # filter by label if specified
    if args.label:
        label_lower = args.label.lower()
        issues = [
            i for i in issues
            if any(l["name"].lower() == label_lower for l in i.get("labels", {}).get("nodes", []))
        ]

    if not issues:
        print("No issues found")
        return

    for issue in issues:
        labels = ", ".join(l["name"] for l in issue.get("labels", {}).get("nodes", []))
        state = issue.get("state", {}).get("name", "?")
        date = issue.get("createdAt", "")[:10]
        print(f"  {issue['identifier']}  [{state}]  {issue['title']}")
        if labels:
            print(f"    labels: {labels}")


def main():
    parser = argparse.ArgumentParser(
        description="Linear Helper — create and manage Linear issues from shell"
    )
    subparsers = parser.add_subparsers(dest="command")

    # create command
    create_parser = subparsers.add_parser("create", help="Create a new issue")
    create_parser.add_argument("--title", required=True, help="Issue title")
    create_parser.add_argument("--description", help="Issue description/spec (markdown)")
    create_parser.add_argument("--priority", choices=["urgent", "high", "medium", "low", "none"],
                               default="medium", help="Priority level")
    create_parser.add_argument("--parent", help="Parent issue identifier (e.g., CON-456)")
    create_parser.add_argument("--label", action="append", default=[],
                               help="Labels to add (repeatable)")

    # label command
    label_parser = subparsers.add_parser("label", help="Add labels to an issue")
    label_parser.add_argument("identifier", help="Issue identifier (e.g., CON-456)")
    label_parser.add_argument("--add", action="append", default=[], help="Label to add (repeatable)")

    # list command
    list_parser = subparsers.add_parser("list", help="List recent issues")
    list_parser.add_argument("--label", help="Filter by label name")
    list_parser.add_argument("--limit", type=int, default=10, help="Max issues to return")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    if args.command == "create":
        create_issue(args)
    elif args.command == "label":
        label_issue(args)
    elif args.command == "list":
        list_issues(args)


if __name__ == "__main__":
    main()
