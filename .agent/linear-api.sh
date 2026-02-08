#!/bin/bash
#
# Linear API Helper Functions
#
# Provides functions for interacting with Linear's GraphQL API.
# Used by run-tasks.sh for issue management when TASK_SOURCE="linear".
#
# Prerequisites:
#   - LINEAR_API_KEY environment variable set
#   - jq installed
#

# =============================================================================
# CORE API FUNCTION
# =============================================================================

# Execute a GraphQL query against Linear API
# Uses jq to properly escape JSON (fixes Sentry bug with newlines in queries)
linear_graphql() {
  local query="$1"
  local variables="${2:-}"

  if [ -z "$LINEAR_API_KEY" ]; then
    echo "ERROR: LINEAR_API_KEY environment variable not set" >&2
    return 1
  fi

  local json_payload
  if [ -n "$variables" ]; then
    # Query with variables
    json_payload=$(jq -n --arg q "$query" --argjson v "$variables" '{"query": $q, "variables": $v}')
  else
    # Query without variables
    json_payload=$(jq -n --arg q "$query" '{"query": $q}')
  fi

  curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $LINEAR_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$json_payload"
}

# =============================================================================
# ISSUE QUERIES
# =============================================================================

# Get issues ready for the agent (Claude label + Open state)
# Orders by createdAt ASC (oldest first for multi-part specs)
linear_get_ready_issues() {
  local team_id="${LINEAR_TEAM_ID:-}"
  local label_name="${LINEAR_LABEL_NAME:-claude}"
  local state_name="${LINEAR_STATE_OPEN:-Open}"

  if [ -z "$team_id" ]; then
    echo "ERROR: LINEAR_TEAM_ID not set in config.sh" >&2
    return 1
  fi

  # Build query with values directly interpolated (Linear's variable support is limited)
  # NOTE: orderBy only specifies WHICH field, not direction (defaults to descending)
  # Use sort parameter with createdAt.order: Ascending for oldest-first ordering
  local query="
    query {
      issues(
        filter: {
          team: { id: { eq: \"$team_id\" } }
          labels: { name: { eq: \"$label_name\" } }
          state: { name: { eq: \"$state_name\" } }
        }
        sort: [{ createdAt: { order: Ascending } }]
        first: 100
      ) {
        nodes {
          id
          identifier
          title
          description
          createdAt
        }
      }
    }
  "

  linear_graphql "$query" | jq -c '.data.issues.nodes[]' 2>/dev/null
}

# Get a single issue by identifier (e.g., "CON-123")
linear_get_issue() {
  local identifier="$1"

  local query='
    query($identifier: String!) {
      issue(id: $identifier) {
        id
        identifier
        title
        description
        state {
          id
          name
        }
      }
    }
  '

  local variables=$(jq -n --arg identifier "$identifier" '{identifier: $identifier}')

  linear_graphql "$query" "$variables" | jq '.data.issue' 2>/dev/null
}

# =============================================================================
# STATE MANAGEMENT
# =============================================================================

# Update an issue's workflow state
# Parameters:
#   $1 - Issue ID (Linear UUID, not identifier)
#   $2 - New state ID (Linear UUID)
linear_update_state() {
  local issue_id="$1"
  local state_id="$2"

  if [ -z "$issue_id" ] || [ -z "$state_id" ]; then
    echo "ERROR: linear_update_state requires issue_id and state_id" >&2
    return 1
  fi

  local query='
    mutation($issueId: String!, $stateId: String!) {
      issueUpdate(
        id: $issueId,
        input: { stateId: $stateId }
      ) {
        success
        issue {
          id
          identifier
          state {
            name
          }
        }
      }
    }
  '

  local variables=$(jq -n \
    --arg issueId "$issue_id" \
    --arg stateId "$state_id" \
    '{issueId: $issueId, stateId: $stateId}')

  linear_graphql "$query" "$variables"
}

# Helper: Update state by name (looks up state ID from config)
linear_set_issue_state() {
  local issue_id="$1"
  local state_name="$2"

  local state_id=""
  case "$state_name" in
    "open"|"Open")
      state_id="$LINEAR_STATE_OPEN_ID"
      ;;
    "in_progress"|"In Progress")
      state_id="$LINEAR_STATE_IN_PROGRESS_ID"
      ;;
    "in_review"|"In Review")
      state_id="$LINEAR_STATE_IN_REVIEW_ID"
      ;;
    "done"|"Done")
      state_id="$LINEAR_STATE_DONE_ID"
      ;;
    *)
      echo "ERROR: Unknown state name: $state_name" >&2
      return 1
      ;;
  esac

  if [ -z "$state_id" ]; then
    echo "ERROR: State ID for '$state_name' not configured. Run .agent/linear-setup.sh" >&2
    return 1
  fi

  linear_update_state "$issue_id" "$state_id"
}

# =============================================================================
# COMMENTS
# =============================================================================

# Add a comment to an issue
linear_add_comment() {
  local issue_id="$1"
  local body="$2"

  if [ -z "$issue_id" ] || [ -z "$body" ]; then
    echo "ERROR: linear_add_comment requires issue_id and body" >&2
    return 1
  fi

  local query='
    mutation($issueId: String!, $body: String!) {
      commentCreate(
        input: {
          issueId: $issueId,
          body: $body
        }
      ) {
        success
        comment {
          id
        }
      }
    }
  '

  local variables=$(jq -n \
    --arg issueId "$issue_id" \
    --arg body "$body" \
    '{issueId: $issueId, body: $body}')

  linear_graphql "$query" "$variables"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Check if Linear API is accessible
linear_check_connection() {
  local result=$(linear_graphql '{ viewer { id name } }')

  if echo "$result" | jq -e '.data.viewer.id' > /dev/null 2>&1; then
    local name=$(echo "$result" | jq -r '.data.viewer.name')
    echo "Connected to Linear as: $name"
    return 0
  else
    echo "ERROR: Failed to connect to Linear API" >&2
    echo "$result" >&2
    return 1
  fi
}

# Get team info (useful for setup)
linear_get_teams() {
  linear_graphql '{ teams { nodes { id name key } } }' | jq '.data.teams.nodes[]'
}

# Get workflow states for a team
linear_get_team_states() {
  local team_id="$1"

  if [ -z "$team_id" ]; then
    echo "ERROR: team_id required" >&2
    return 1
  fi

  local query='
    query($teamId: String!) {
      team(id: $teamId) {
        states {
          nodes {
            id
            name
            type
          }
        }
      }
    }
  '

  local variables=$(jq -n --arg teamId "$team_id" '{teamId: $teamId}')

  linear_graphql "$query" "$variables" | jq '.data.team.states.nodes[]'
}

# Get labels for a team
linear_get_team_labels() {
  local team_id="$1"

  if [ -z "$team_id" ]; then
    echo "ERROR: team_id required" >&2
    return 1
  fi

  local query='
    query($teamId: String!) {
      team(id: $teamId) {
        labels {
          nodes {
            id
            name
          }
        }
      }
    }
  '

  local variables=$(jq -n --arg teamId "$team_id" '{teamId: $teamId}')

  linear_graphql "$query" "$variables" | jq '.data.team.labels.nodes[]'
}

# =============================================================================
# PROJECT MANAGEMENT
# =============================================================================

# Get projects for a team
# Returns: JSON array of projects with id, name, state
linear_get_team_projects() {
  local team_id="${1:-$LINEAR_TEAM_ID}"

  if [ -z "$team_id" ]; then
    echo "ERROR: team_id required" >&2
    return 1
  fi

  local query='
    query($teamId: String!) {
      team(id: $teamId) {
        projects {
          nodes {
            id
            name
            state
          }
        }
      }
    }
  '

  local variables=$(jq -n --arg teamId "$team_id" '{teamId: $teamId}')

  linear_graphql "$query" "$variables" | jq '.data.team.projects.nodes[]'
}

# =============================================================================
# ISSUE CREATION
# =============================================================================

# Create a new Linear issue
# Parameters:
#   $1 - title (required)
#   $2 - description (required, Markdown)
#   $3 - priority (optional: 0=none, 1=urgent, 2=high, 3=medium, 4=low)
# Environment vars used:
#   LINEAR_TEAM_ID
#   LINEAR_STATE_OPEN_ID
#   LINEAR_LABEL_CLAUDE_ID (must be set, run linear_setup_cache to get it)
#   LINEAR_PROJECT_MERCURY_ID (optional)
linear_create_issue() {
  local title="$1"
  local description="$2"
  local priority="${3:-0}"  # Default to no priority

  if [ -z "$title" ] || [ -z "$description" ]; then
    echo "ERROR: linear_create_issue requires title and description" >&2
    return 1
  fi

  if [ -z "$LINEAR_TEAM_ID" ]; then
    echo "ERROR: LINEAR_TEAM_ID not set in config.sh" >&2
    return 1
  fi

  if [ -z "$LINEAR_STATE_OPEN_ID" ]; then
    echo "ERROR: LINEAR_STATE_OPEN_ID not set in config.sh" >&2
    return 1
  fi

  if [ -z "$LINEAR_LABEL_CLAUDE_ID" ]; then
    echo "ERROR: LINEAR_LABEL_CLAUDE_ID not set. Run: linear_setup_cache" >&2
    return 1
  fi

  # Build the mutation input
  local query='
    mutation($input: IssueCreateInput!) {
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
  '

  # Build variables JSON with jq (properly handle multi-line descriptions)
  local label_ids_json
  label_ids_json=$(jq -n --arg id "$LINEAR_LABEL_CLAUDE_ID" '[$id]')

  local variables
  variables=$(jq -n \
    --arg title "$title" \
    --arg description "$description" \
    --arg teamId "$LINEAR_TEAM_ID" \
    --arg stateId "$LINEAR_STATE_OPEN_ID" \
    --argjson labelIds "$label_ids_json" \
    --argjson priority "$priority" \
    '{
      input: {
        title: $title,
        description: $description,
        teamId: $teamId,
        stateId: $stateId,
        labelIds: $labelIds,
        priority: $priority
      }
    }')

  # Add projectId if Mercury project is configured
  if [ -n "$LINEAR_PROJECT_MERCURY_ID" ]; then
    variables=$(printf '%s' "$variables" | jq --arg projectId "$LINEAR_PROJECT_MERCURY_ID" \
      '.input.projectId = $projectId')
  fi

  linear_graphql "$query" "$variables"
}

# =============================================================================
# SETUP HELPERS
# =============================================================================

# One-time setup to cache label and project IDs
# Call this before using linear_create_issue for the first time
# Outputs config to copy to .agent/config.sh
linear_setup_cache() {
  echo "Querying Linear for label and project IDs..."
  echo ""

  # Get Claude label ID
  local labels_json=$(linear_get_team_labels "$LINEAR_TEAM_ID")
  local claude_label_id=$(echo "$labels_json" | jq -r 'select(.name == "claude") | .id')

  if [ -z "$claude_label_id" ] || [ "$claude_label_id" = "null" ]; then
    echo "ERROR: 'claude' label not found in Linear. Create it first:" >&2
    echo "  Linear -> Settings -> Labels -> Create label named 'claude'" >&2
    return 1
  fi

  echo "Found 'claude' label: $claude_label_id"

  # Get projects (case-insensitive search for "mercury")
  local projects_json=$(linear_get_team_projects "$LINEAR_TEAM_ID")
  local mercury_project_id=$(echo "$projects_json" | jq -r 'select(.name | ascii_downcase == "mercury") | .id')

  if [ -n "$mercury_project_id" ] && [ "$mercury_project_id" != "null" ]; then
    echo "Found 'Mercury' project: $mercury_project_id"
  else
    echo "WARNING: 'Mercury' project not found. Issues will not be added to a project."
    mercury_project_id=""
  fi

  echo ""
  echo "=============================================="
  echo "Add these to .agent/config.sh LINEAR SETTINGS:"
  echo "=============================================="
  echo ""
  echo "# Claude label ID (required for task-creator)"
  echo "LINEAR_LABEL_CLAUDE_ID=\"$claude_label_id\""
  echo ""
  if [ -n "$mercury_project_id" ]; then
    echo "# Mercury project ID (optional - auto-adds issues to project)"
    echo "LINEAR_PROJECT_MERCURY_ID=\"$mercury_project_id\""
  else
    echo "# LINEAR_PROJECT_MERCURY_ID=\"\"  # Mercury project not found"
  fi
  echo ""
}
