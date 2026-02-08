#!/usr/bin/env python3
"""
Fetch a Linear task by ID and save it as a markdown file.

Usage:
    python3 fetch_task.py CON-456
    python3 fetch_task.py CON-456 --output /custom/path.md

This script is designed to be called by the agent to pull task specs
without burning context window on API round-trips. The agent then
reads the resulting markdown file to understand the requirements.
"""

import sys
import os
import argparse

# Add skill directory to path
SKILL_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SKILL_DIR)

from linear_api import LinearAPI


def main():
    parser = argparse.ArgumentParser(description="Fetch a Linear task and save as markdown")
    parser.add_argument("identifier", help="Linear task identifier (e.g., CON-456)")
    parser.add_argument("--output", "-o", help="Custom output path (default: tasks/<ID>.md)")
    parser.add_argument("--print", "-p", dest="print_output", action="store_true",
                        help="Print the markdown to stdout instead of saving")
    args = parser.parse_args()

    identifier = args.identifier.upper()

    # Initialize Linear client
    try:
        linear = LinearAPI()
    except ValueError as e:
        print(f"[error] {e}", file=sys.stderr)
        sys.exit(1)

    # Fetch the task
    print(f"Fetching task {identifier}...", file=sys.stderr)
    task = linear.get_task_by_identifier(identifier)

    if not task:
        print(f"[error] Task {identifier} not found", file=sys.stderr)
        sys.exit(1)

    # Convert to markdown
    markdown = LinearAPI.task_to_markdown(task)

    # Print or save
    if args.print_output:
        print(markdown)
    else:
        # Determine output path
        if args.output:
            output_path = args.output
        else:
            tasks_dir = os.path.join(SKILL_DIR, "tasks")
            os.makedirs(tasks_dir, exist_ok=True)
            output_path = os.path.join(tasks_dir, f"{identifier}.md")

        with open(output_path, "w") as f:
            f.write(markdown)

        print(f"Saved: {output_path}", file=sys.stderr)
        # Print the path to stdout so the caller can use it
        print(output_path)


if __name__ == "__main__":
    main()
