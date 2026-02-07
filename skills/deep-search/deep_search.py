#!/usr/bin/env python3
"""
Deep Search: Brave Search + Agent Browser hybrid
Triggered by /deep-search command
"""

import subprocess
import json
import sys
import re
import os

def run_brave_search(query, count=5):
    """Run Brave search and return URLs"""
    # Remove the /deep-search trigger from query
    clean_query = re.sub(r'/deep-search\s*', '', query, flags=re.IGNORECASE).strip()
    
    print(f"🔍 Brave Search: {clean_query}")
    
    # Call web_search using the OpenClaw Python SDK approach
    # We'll use curl to hit the Brave API directly
    api_key = os.environ.get('BRAVE_API_KEY', '')
    
    if not api_key:
        # Try to get from config
        try:
            result = subprocess.run(
                ['openclaw', 'config', 'get', 'tools.web.search.apiKey'],
                capture_output=True,
                text=True
            )
            api_key = result.stdout.strip()
        except:
            pass
    
    # Fallback: use web_search via OpenClaw gateway if available
    try:
        import urllib.request
        import urllib.parse
        
        encoded_query = urllib.parse.quote(clean_query)
        url = f"https://api.search.brave.com/res/v1/web/search?q={encoded_query}&count={count}"
        
        headers = {
            'Accept': 'application/json',
            'Accept-Encoding': 'gzip',
            'X-Subscription-Token': api_key
        }
        
        req = urllib.request.Request(url, headers=headers)
        
        with urllib.request.urlopen(req, timeout=30) as response:
            data = json.loads(response.read().decode('utf-8'))
            
            urls = []
            if 'web' in data and 'results' in data['web']:
                for result in data['web']['results']:
                    if 'url' in result:
                        urls.append(result['url'])
            
            return urls[:count]
            
    except Exception as e:
        print(f"⚠️  Brave API error: {e}")
        # Fallback: return empty and let caller handle
        return []

def extract_with_agent_browser(url):
    """Use agent-browser to extract full page content"""
    print(f"🌐 Agent Browser: {url}")
    
    try:
        # Open the page
        subprocess.run(
            ['agent-browser', 'open', url],
            capture_output=True,
            timeout=30
        )
        
        # Get snapshot
        result = subprocess.run(
            ['agent-browser', 'snapshot', '-i', '-c'],
            capture_output=True,
            text=True,
            timeout=30
        )
        
        snapshot = result.stdout
        
        # Get page title
        title_result = subprocess.run(
            ['agent-browser', 'get', 'title'],
            capture_output=True,
            text=True,
            timeout=10
        )
        title = title_result.stdout.strip()
        
        # Close browser
        subprocess.run(
            ['agent-browser', 'close'],
            capture_output=True,
            timeout=10
        )
        
        return {
            'url': url,
            'title': title,
            'content': snapshot[:8000]  # Limit content length
        }
        
    except Exception as e:
        return {
            'url': url,
            'title': 'Error',
            'content': f'Failed to extract: {str(e)}'
        }

def deep_search(query):
    """Main deep search workflow"""
    print(f"\n🚀 Deep Search Initiated\n{'='*50}\n")
    
    # Step 1: Brave Search
    urls = run_brave_search(query, count=5)
    
    if not urls:
        print("❌ No results found")
        return None
    
    print(f"✅ Found {len(urls)} URLs\n")
    
    # Step 2: Sequential Agent Browser extraction
    results = []
    for i, url in enumerate(urls, 1):
        print(f"\n[{i}/{len(urls)}] Processing...")
        data = extract_with_agent_browser(url)
        results.append(data)
    
    # Step 3: Output combined results
    print(f"\n{'='*50}")
    print("📊 DEEP SEARCH RESULTS")
    print(f"{'='*50}\n")
    
    for r in results:
        print(f"\n🔗 {r['url']}")
        print(f"📄 {r['title']}")
        print(f"{'-'*50}")
        print(r['content'][:2000])  # Preview first 2000 chars
        print(f"{'='*50}")
    
    # Return structured data for AI processing
    return {
        'query': query,
        'urls_found': len(urls),
        'results': results
    }

if __name__ == '__main__':
    query = ' '.join(sys.argv[1:]) if len(sys.argv) > 1 else ''
    if not query:
        print("Usage: python3 deep_search.py <search query>")
        sys.exit(1)
    
    result = deep_search(query)
    
    # Also output JSON for programmatic use
    if result:
        print("\n" + json.dumps(result, indent=2))
