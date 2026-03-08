#!/bin/bash
# post a comment to a linear issue as the kiro bot
# usage: linear-comment.sh <issue-uuid> <body-or-file>
#   if second arg is a file path, reads the file. otherwise treats as raw text.

set -euo pipefail

ISSUE_ID="${1:?usage: linear-comment.sh <issue-uuid> <body-or-file>}"
BODY_ARG="${2:?usage: linear-comment.sh <issue-uuid> <body-or-file>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIRO_TOKEN=$(cat "$SCRIPT_DIR/.oauth-token.json" | jq -r '.access_token')

if [ -f "$BODY_ARG" ]; then
  BODY=$(cat "$BODY_ARG")
else
  BODY="$BODY_ARG"
fi

jq -n --arg id "$ISSUE_ID" --arg body "$BODY" \
  '{"query": "mutation($id:String!,$body:String!){commentCreate(input:{issueId:$id,body:$body}){success}}", "variables": {"id": $id, "body": $body}}' | \
curl -s https://api.linear.app/graphql \
  -H "Authorization: Bearer $KIRO_TOKEN" \
  -H "Content-Type: application/json" \
  -d @-
