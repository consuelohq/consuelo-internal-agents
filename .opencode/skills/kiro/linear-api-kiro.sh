#!/bin/bash
#
# Linear API Wrapper for Kiro Specs Watcher
#
# Provides functions to interact with Linear's GraphQL API for kiro-tagged tasks.
#

# Load config
if [ -f "$(dirname "${BASH_SOURCE[0]}")/config.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_info() { echo -e "[INFO] $1"; }

# =============================================================================
# API SETUP
# =============================================================================

# Check and setup Linear API
linear_check_api() {
    if [ -z "$LINEAR_API_KEY" ]; then
        log_error "LINEAR_API_KEY not set. Add to ~/.zshrc: export LINEAR_API_KEY=\"...\""
        return 1
    fi

    if [ -z "$LINEAR_TEAM_ID" ]; then
        log_error "LINEAR_TEAM_ID not set. Add to ~/.zshrc: export LINEAR_TEAM_ID=\"...\""
        return 1
    fi

    # Test API connection
    local test_response
    test_response=$(curl -s -X POST https://api.linear.app/graphql \
        -H "Authorization: $LINEAR_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{"query":"{ viewer { id name } }"}')

    if echo "$test_response" | grep -q '"errors"'; then
        log_error "Linear API error: $(echo "$test_response" | head -c 200)"
        return 1
    fi

    log_info "Linear API connected successfully"
    return 0
}

# GraphQL query wrapper
linear_graphql() {
    local query="$1"
    # Escape newlines and quotes for valid JSON
    local escaped
    escaped=$(echo "$query" | tr '\n' ' ' | sed 's/"/\\"/g')

    curl -s -X POST https://api.linear.app/graphql \
        -H "Authorization: $LINEAR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"query\":\"$escaped\"}"
}

# =============================================================================
# LABEL & STATE ID DISCOVERY
# =============================================================================

# Get label ID by name
linear_get_label_id() {
    local label_name="$1"

    # Use cached ID if available
    if [ "$label_name" = "kiro" ] && [ -n "$LINEAR_LABEL_KIRO_ID" ]; then
        echo "$LINEAR_LABEL_KIRO_ID"
        return 0
    fi

    # Query Linear for the label
    local response
    response=$(linear_graphql "{
        team(id: \"$LINEAR_TEAM_ID\") {
            labels(first: 50) {
                nodes { id name }
            }
        }
    }")

    local label_id
    label_id=$(echo "$response" | jq -r ".data.team.labels.nodes[] | select(.name == \"$label_name\") | .id" 2>/dev/null | head -1)

    if [ -z "$label_id" ] || [ "$label_id" = "null" ]; then
        log_error "Label '$label_name' not found in team"
        return 1
    fi

    echo "$label_id"
}

# Get workflow state ID by name
linear_get_state_id() {
    local state_name="$1"

    # Use cached IDs if available
    case "$state_name" in
        "Open")        [ -n "$LINEAR_STATE_OPEN_ID" ] && echo "$LINEAR_STATE_OPEN_ID" && return 0 ;;
        "In Progress") [ -n "$LINEAR_STATE_IN_PROGRESS_ID" ] && echo "$LINEAR_STATE_IN_PROGRESS_ID" && return 0 ;;
        "In Review")   [ -n "$LINEAR_STATE_IN_REVIEW_ID" ] && echo "$LINEAR_STATE_IN_REVIEW_ID" && return 0 ;;
        "Done")        [ -n "$LINEAR_STATE_DONE_ID" ] && echo "$LINEAR_STATE_DONE_ID" && return 0 ;;
    esac

    local response
    response=$(linear_graphql "{
        team(id: \"$LINEAR_TEAM_ID\") {
            states(first: 50) {
                nodes { id name type }
            }
        }
    }")

    local state_id
    state_id=$(echo "$response" | jq -r ".data.team.states.nodes[] | select(.name == \"$state_name\") | .id" 2>/dev/null | head -1)

    if [ -z "$state_id" ] || [ "$state_id" = "null" ]; then
        log_error "State '$state_name' not found in team"
        return 1
    fi

    echo "$state_id"
}

# =============================================================================
# ISSUE FETCHING
# =============================================================================

# Get kiro-labeled issues in Open state
# Uses label name filter (works for both team and workspace labels)
linear_get_kiro_issues() {
    local label_name="${LINEAR_LABEL_NAME:-kiro}"
    local state_name="${LINEAR_STATE_OPEN:-Open}"

    local query='{ issues(first: 20, filter: { and: [{ labels: { name: { eq: \"'"$label_name"'\" } } }, { state: { name: { eq: \"'"$state_name"'\" } } }] }, orderBy: createdAt) { nodes { id identifier title description priority createdAt } } }'

    local response
    response=$(curl -s -X POST https://api.linear.app/graphql \
        -H "Authorization: $LINEAR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"$query\"}")

    local issues
    issues=$(echo "$response" | jq -c '.data.issues.nodes[]' 2>/dev/null)

    if [ -z "$issues" ]; then
        echo "[]"
        return 0
    fi

    echo "$issues"
}

# Get issue details by ID
linear_get_issue() {
    local issue_id="$1"

    local response
    response=$(linear_graphql "{
        issue(id: \"$issue_id\") {
            id
            identifier
            title
            description
            priority
            createdAt
            state { id name }
            labels { nodes { id name } }
        }
    }")

    echo "$response"
}

# =============================================================================
# STATE MANAGEMENT
# =============================================================================

# Move issue to a new state
linear_update_state() {
    local issue_id="$1"
    local new_state_id="$2"

    local response
    response=$(linear_graphql "mutation {
        issueUpdate(
            id: \"$issue_id\"
            input: { stateId: \"$new_state_id\" }
        ) { success }
    }")

    local success
    success=$(echo "$response" | jq -r '.data.issueUpdate.success' 2>/dev/null)

    if [ "$success" = "true" ]; then
        return 0
    else
        log_error "Failed to update issue state: $response"
        return 1
    fi
}

# =============================================================================
# LABEL MANAGEMENT
# =============================================================================

# Add label to issue
linear_add_label() {
    local issue_id="$1"
    local label_id="$2"

    local response
    response=$(linear_graphql "mutation {
        issueAddLabel(
            id: \"$issue_id\"
            labelId: \"$label_id\"
        ) { success }
    }")

    local success
    success=$(echo "$response" | jq -r '.data.issueAddLabel.success' 2>/dev/null)

    if [ "$success" = "true" ]; then
        return 0
    else
        log_error "Failed to add label: $response"
        return 1
    fi
}

# Remove label from issue
linear_remove_label() {
    local issue_id="$1"
    local label_id="$2"

    local response
    response=$(linear_graphql "mutation {
        issueRemoveLabel(
            id: \"$issue_id\"
            labelId: \"$label_id\"
        ) { success }
    }")

    local success
    success=$(echo "$response" | jq -r '.data.issueRemoveLabel.success' 2>/dev/null)

    if [ "$success" = "true" ]; then
        return 0
    else
        log_error "Failed to remove label: $response"
        return 1
    fi
}

# =============================================================================
# COMMENTS
# =============================================================================

# Add comment to issue
linear_add_comment() {
    local issue_id="$1"
    local body="$2"

    local response
    response=$(linear_graphql "mutation {
        commentCreate(
            input: {
                issueId: \"$issue_id\"
                body: \"$body\"
            }
        ) { success }
    }")

    local success
    success=$(echo "$response" | jq -r '.data.commentCreate.success' 2>/dev/null)

    if [ "$success" = "true" ]; then
        return 0
    else
        log_error "Failed to add comment: $response"
        return 1
    fi
}

# =============================================================================
# ISSUE CREATION
# =============================================================================

# Create a new issue (used by kiro for sub-specs)
linear_create_issue() {
    local title="$1"
    local description="$2"
    local label_id="${3:-}"

    local label_input=""
    if [ -n "$label_id" ]; then
        label_id_escaped=$(echo "$label_id" | jq -Rs '.')
        label_input=", labelIds: [$label_id_escaped]"
    fi

    local response
    response=$(linear_graphql "mutation {
        issueCreate(
            input: {
                teamId: \"$LINEAR_TEAM_ID\"
                title: \"$title\"
                description: \"$description\"
                $label_input
            }
        ) {
            success
            issue { id identifier title }
        }
    }")

    local success
    success=$(echo "$response" | jq -r '.data.issueCreate.success' 2>/dev/null)

    if [ "$success" = "true" ]; then
        local issue_id issue_ident title
        issue_id=$(echo "$response" | jq -r '.data.issueCreate.issue.id')
        issue_ident=$(echo "$response" | jq -r '.data.issueCreate.issue.identifier')
        title=$(echo "$response" | jq -r '.data.issueCreate.issue.title')
        echo "$issue_id|$issue_ident|$title"
        return 0
    else
        log_error "Failed to create issue: $response"
        return 1
    fi
}

# =============================================================================
# SETUP HELPERS
# =============================================================================

# Setup and cache IDs
linear_setup_cache() {
    log_info "Setting up Linear API cache..."

    if ! linear_check_api; then
        log_error "API check failed"
        return 1
    fi

    log_info "Team ID: $LINEAR_TEAM_ID"
    log_info "Label: $LINEAR_LABEL_NAME"

    local label_id
    label_id=$(linear_get_label_id "$LINEAR_LABEL_NAME")
    log_info "Label ID: $label_id"

    for state in "$LINEAR_STATE_OPEN" "$LINEAR_STATE_IN_PROGRESS" "$LINEAR_STATE_IN_REVIEW"; do
        local state_id
        state_id=$(linear_get_state_id "$state")
        log_info "State '$state' ID: $state_id"
    done

    log_info "Setup complete. All IDs cached in config.sh."
    echo ""
    echo "LINEAR_LABEL_KIRO_ID=\"$label_id\""
}

# Print usage info
linear_usage() {
    cat << EOF
Linear API Commands:
  check-api           Test API connection
  get-issues          Get kiro-labeled open issues
  get-issue <id>      Get issue details
  update-state <id> <new_state_id>  Move issue to new state
  create-issue \"title\" \"desc\" [label_id]  Create new issue
  setup-cache         Discover and print all IDs for config

Environment Variables Required:
  LINEAR_API_KEY     Your Linear API key
  LINEAR_TEAM_ID     Your Linear team ID

EOF
}
