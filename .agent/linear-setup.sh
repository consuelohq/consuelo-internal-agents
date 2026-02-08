#!/bin/bash
#
# Linear Setup Helper
#
# Run this script once after setting LINEAR_API_KEY to get the Team ID
# and Workflow State IDs needed for .agent/config.sh
#
# Usage:
#   export LINEAR_API_KEY="lin_api_your_key_here"
#   .agent/linear-setup.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the Linear API helper
source "$SCRIPT_DIR/linear-api.sh"

echo "=============================================="
echo "Linear Setup Helper"
echo "=============================================="
echo ""

# Check for API key
if [ -z "$LINEAR_API_KEY" ]; then
  echo "ERROR: LINEAR_API_KEY environment variable not set"
  echo ""
  echo "To set it:"
  echo "  1. Go to Linear -> Settings -> API -> Personal API keys"
  echo "  2. Create a new key"
  echo "  3. Add to your shell profile (~/.zshrc or ~/.bashrc):"
  echo "     export LINEAR_API_KEY=\"lin_api_your_key_here\""
  echo "  4. Run: source ~/.zshrc"
  echo "  5. Run this script again"
  exit 1
fi

# Check for jq
if ! command -v jq &> /dev/null; then
  echo "ERROR: jq is required but not installed"
  echo "Install with: brew install jq"
  exit 1
fi

# Check connection
echo "Checking Linear API connection..."
if ! linear_check_connection; then
  exit 1
fi
echo ""

# Get teams
echo "=============================================="
echo "Your Linear Teams"
echo "=============================================="
echo ""

teams_json=$(linear_graphql '{ teams { nodes { id name key } } }')

# Display teams
echo "$teams_json" | jq -r '.data.teams.nodes[] | "Team: \(.name) (key: \(.key))\n  ID: \(.id)\n"'

# Check for DEV team specifically
dev_team_id=$(echo "$teams_json" | jq -r '.data.teams.nodes[] | select(.key == "DEV") | .id')

if [ -n "$dev_team_id" ] && [ "$dev_team_id" != "null" ]; then
  echo "=============================================="
  echo "DEV Team Workflow States"
  echo "=============================================="
  echo ""

  # Get states for DEV team
  states_json=$(linear_get_team_states "$dev_team_id")

  echo "Workflow States:"
  echo "$states_json" | jq -r '"  - \(.name) (type: \(.type))\n    ID: \(.id)"'

  echo ""
  echo "=============================================="
  echo "DEV Team Labels"
  echo "=============================================="
  echo ""

  # Get labels
  labels_json=$(linear_get_team_labels "$dev_team_id")
  echo "Labels:"
  echo "$labels_json" | jq -r '"  - \(.name)\n    ID: \(.id)"'

  # Check for Claude label
  claude_label=$(echo "$labels_json" | jq -r 'select(.name == "Claude") | .id')
  if [ -z "$claude_label" ] || [ "$claude_label" = "null" ]; then
    echo ""
    echo "NOTE: 'Claude' label not found. Create it in Linear:"
    echo "  Settings -> Labels -> Create label named 'Claude'"
  fi

  echo ""
  echo "=============================================="
  echo "DEV Team Projects"
  echo "=============================================="
  echo ""

  # Get projects
  projects_json=$(linear_get_team_projects "$dev_team_id")
  echo "Projects:"
  echo "$projects_json" | jq -r '"  - \(.name) (state: \(.state))\n    ID: \(.id)"'

  # Check for Mercury project
  mercury_project=$(echo "$projects_json" | jq -r 'select(.name == "Mercury") | .id')
  if [ -z "$mercury_project" ] || [ "$mercury_project" = "null" ]; then
    echo ""
    echo "NOTE: 'Mercury' project not found. Create it in Linear if needed:"
    echo "  Projects -> Create project named 'Mercury'"
  fi

  echo ""
  echo "=============================================="
  echo "Configuration for .agent/config.sh"
  echo "=============================================="
  echo ""
  echo "Copy these values to the LINEAR SETTINGS section in .agent/config.sh:"
  echo ""
  echo "# Linear Team ID"
  echo "LINEAR_TEAM_ID=\"$dev_team_id\""
  echo ""
  echo "# Workflow State IDs (copy the IDs from above that match your workflow)"
  echo "# Example mapping for DEV team:"

  # Extract common state names
  open_id=$(echo "$states_json" | jq -r 'select(.name == "Open") | .id' | head -1)
  in_progress_id=$(echo "$states_json" | jq -r 'select(.name == "In Progress") | .id' | head -1)
  in_review_id=$(echo "$states_json" | jq -r 'select(.name == "In Review") | .id' | head -1)
  done_id=$(echo "$states_json" | jq -r 'select(.name == "Done") | .id' | head -1)

  [ -n "$open_id" ] && [ "$open_id" != "null" ] && echo "LINEAR_STATE_OPEN_ID=\"$open_id\""
  [ -n "$in_progress_id" ] && [ "$in_progress_id" != "null" ] && echo "LINEAR_STATE_IN_PROGRESS_ID=\"$in_progress_id\""
  [ -n "$in_review_id" ] && [ "$in_review_id" != "null" ] && echo "LINEAR_STATE_IN_REVIEW_ID=\"$in_review_id\""
  [ -n "$done_id" ] && [ "$done_id" != "null" ] && echo "LINEAR_STATE_DONE_ID=\"$done_id\""

  # Get Claude label ID for task-creator
  claude_label_id=$(echo "$labels_json" | jq -r 'select(.name == "claude") | .id' | head -1)
  mercury_project_id=$(echo "$projects_json" | jq -r 'select(.name == "Mercury") | .id' | head -1)

  echo ""
  echo "# Task-Creator Configuration"
  [ -n "$claude_label_id" ] && [ "$claude_label_id" != "null" ] && \
    echo "LINEAR_LABEL_CLAUDE_ID=\"$claude_label_id\""

  if [ -n "$mercury_project_id" ] && [ "$mercury_project_id" != "null" ]; then
    echo "LINEAR_PROJECT_MERCURY_ID=\"$mercury_project_id\""
  else
    echo "# LINEAR_PROJECT_MERCURY_ID=\"\"  # Mercury project not found - create in Linear if needed"
  fi

else
  echo ""
  echo "NOTE: DEV team not found. Look for your team above and run:"
  echo "  linear_get_team_states \"<team_id>\""
  echo "to see workflow states."
fi

echo ""
echo "=============================================="
echo "Setup Complete"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. Copy the configuration values above to .agent/config.sh"
echo "  2. Create a test issue in Linear with 'Claude' label and 'Open' status"
echo "  3. Run: .agent/run-tasks.sh --source linear --dry-run"
