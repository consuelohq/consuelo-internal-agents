"""
One-time setup script for Linear integration.
Run this to get Team ID and create the Suelo Tasks project.
"""
import os
import requests
from dotenv import load_dotenv

# Load env vars
load_dotenv('.env.suelo')

LINEAR_API_KEY = os.getenv('LINEAR_API_KEY')

if not LINEAR_API_KEY:
    print("❌ LINEAR_API_KEY not found in .env.suelo")
    exit(1)

headers = {
    "Authorization": LINEAR_API_KEY,
    "Content-Type": "application/json"
}

def linear_query(query, variables=None):
    response = requests.post(
        "https://api.linear.app/graphql",
        headers=headers,
        json={"query": query, "variables": variables or {}}
    )
    response.raise_for_status()
    return response.json()

print("🔍 Fetching your Linear teams...")

teams_query = """
query {
    teams {
        nodes {
            id
            name
            key
        }
    }
}
"""

try:
    result = linear_query(teams_query)
    teams = result['data']['teams']['nodes']
    
    print(f"\n✅ Found {len(teams)} team(s):\n")
    for team in teams:
        print(f"  Name: {team['name']}")
        print(f"  ID: {team['id']}")
        print(f"  Key: {team['key']}")
        print()
    
    if len(teams) == 1:
        team_id = teams[0]['id']
        print(f"✏️  Add this to .env.suelo:")
        print(f"   LINEAR_SUelo_TEAM_ID={team_id}")
    else:
        print("⚠️  Multiple teams found. Pick the one you want and add its ID to .env.suelo")
        
except Exception as e:
    print(f"❌ Error: {e}")
    print("Make sure your LINEAR_API_KEY is correct")
