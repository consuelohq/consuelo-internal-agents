#!/bin/bash
# Exa search implementation

QUERY="$1"
COUNT="${2:-5}"

if [ -z "$QUERY" ]; then
    echo '{"error": "Query is required"}'
    exit 1
fi

# Ensure count is reasonable
if [ "$COUNT" -gt 10 ]; then
    COUNT=10
elif [ "$COUNT" -lt 1 ]; then
    COUNT=1
fi

# Check for API key
if [ -z "$EXA_API_KEY" ]; then
    cat << 'EOF'
{
  "error": "EXA_API_KEY not set",
  "setup": "Get your API key at https://dashboard.exa.ai/api-keys and add EXA_API_KEY to ~/.openclaw/.env",
  "docs": "https://docs.exa.ai/"
}
EOF
    exit 1
fi

# Perform Exa search
curl -s -X POST "https://api.exa.ai/search" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${EXA_API_KEY}" \
    -d "{
        \"query\": \"${QUERY}\",
        \"numResults\": ${COUNT},
        \"useAutoprompt\": true,
        \"type\": \"auto\"
    }" | jq -r '.results | map({
        title: .title,
        url: .url,
        snippet: .text
    }) | {results: .}'
