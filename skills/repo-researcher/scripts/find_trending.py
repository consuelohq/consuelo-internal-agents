#!/usr/bin/env python3
"""
Find trending GitHub repos relevant to AI assistants.
Uses web search + GitHub API to discover new tools.
"""

import subprocess
import json
import sys

def web_search(query):
    """Run web search via brave API through openclaw."""
    # Note: This is called by the AI using web_search tool, not directly
    # This script is a placeholder for the workflow
    pass

def get_trending_searches():
    """Return list of search queries to run for trending repos."""
    return [
        "trending MCP servers 2025 github",
        "best new AI agent tools github 2025",
        "trending CLI tools developers github",
        "new playwright automation tools github",
        "twilio MCP server github",
    ]

def filter_by_relevance(repos, existing_skills):
    """Filter repos by relevance to user's stack."""
    existing_names = set(existing_skills)
    
    priority_keywords = [
        "mcp", "mcp-server", "model-context-protocol",
        "cli", "command-line",
        "browser", "automation", "playwright", "puppeteer",
        "twilio", "linear", "slack", "notion",
        "agent", "ai-agent", "llm",
    ]
    
    scored = []
    for repo in repos:
        score = 0
        name_lower = repo.get("name", "").lower()
        desc_lower = repo.get("description", "").lower()
        
        # Skip if already have it
        if any(existing in name_lower for existing in existing_names):
            continue
            
        # Score by keywords
        for kw in priority_keywords:
            if kw in name_lower or kw in desc_lower:
                score += 1
                
        # Boost MCP servers
        if "mcp" in name_lower or "model-context" in name_lower:
            score += 3
            
        # Boost official orgs
        owner = repo.get("owner", "").lower()
        if owner in ["modelcontextprotocol", "github", "twilio-labs", "linear"]:
            score += 2
            
        if score > 0:
            scored.append((score, repo))
    
    scored.sort(reverse=True)
    return [r for _, r in scored[:10]]

def format_suggestion(repo):
    """Format a repo for display."""
    owner = repo.get("owner", "")
    name = repo.get("name", "")
    desc = repo.get("description", "") or "No description"
    
    return {
        "repo": f"{owner}/{name}",
        "link": f"https://github.com/{owner}/{name}",
        "description": desc[:100] + "..." if len(desc) > 100 else desc,
    }

if __name__ == "__main__":
    print("# Trending Repo Discovery")
    print("# Run these web searches to find trending repos:")
    for query in get_trending_searches():
        print(f"# - {query}")
    print("\n# Then filter by relevance to user's stack")
    print("# Existing skills to check against:")
    print("# - deepwiki, exa-search, instagram-lead-scraper")
    print("# - last30days-skill, mcporter, mem0-memory")
    print("# - news-briefing, task-creator, task-state-manager")
    print("# - agent-browser")
