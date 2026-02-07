#!/usr/bin/env python3
"""
Mem0 Memory Module - Easy interface for OpenClaw agent
"""

import json
import os
from mem0 import MemoryClient

class Mem0Memory:
    def __init__(self, api_key=None, user_id="ko"):
        self.api_key = api_key or os.environ.get("MEM0_API_KEY", "")
        self.user_id = user_id
        self.client = MemoryClient(api_key=self.api_key)
        self.filters = {"OR": [{"user_id": self.user_id}]}
    
    def add(self, content, role="user", metadata=None):
        """Add a memory. Content can be string or list of messages."""
        if isinstance(content, str):
            messages = [{"role": role, "content": content}]
        else:
            messages = content
        
        return self.client.add(
            messages=messages,
            user_id=self.user_id,
            version="v2",
            metadata=metadata or {}
        )
    
    def search(self, query, limit=10):
        """Search memories by semantic similarity."""
        return self.client.search(
            query=query,
            filters=self.filters,
            version="v2",
            limit=limit
        )
    
    def get_recent(self, limit=20):
        """Get recent memories."""
        return self.client.get_all(
            filters=self.filters,
            limit=limit
        )
    
    def get_context_for_prompt(self, query, max_memories=5):
        """Get formatted memory context to inject into prompts."""
        results = self.search(query, limit=max_memories)
        
        if not results or not results.get('results'):
            return ""
        
        memories = []
        for mem in results['results']:
            if isinstance(mem, dict) and 'memory' in mem:
                memories.append(f"- {mem['memory']}")
        
        if not memories:
            return ""
        
        return "\n".join(["## Relevant memories from previous conversations:"] + memories)

# Singleton instance for reuse
_memory = None

def get_memory():
    global _memory
    if _memory is None:
        _memory = Mem0Memory()
    return _memory

if __name__ == "__main__":
    import sys
    
    mem = get_memory()
    cmd = sys.argv[1] if len(sys.argv) > 1 else "help"
    
    if cmd == "search":
        query = sys.argv[2] if len(sys.argv) > 2 else ""
        result = mem.search(query)
        print(json.dumps(result, indent=2, default=str))
    
    elif cmd == "context":
        query = sys.argv[2] if len(sys.argv) > 2 else ""
        print(mem.get_context_for_prompt(query))
    
    elif cmd == "recent":
        result = mem.get_recent()
        print(json.dumps(result, indent=2, default=str))
    
    else:
        print("Usage: python mem0_client.py <search|context|recent> [query]")
