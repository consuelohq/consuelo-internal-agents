# Mem0 Memory Skill for OpenClaw

Integrates with mem0.ai for persistent AI memory.

## Setup

API key is already configured in the skill.

## Usage

This skill provides automatic memory operations:

1. **After conversations** - Key facts are automatically extracted and stored
2. **On session start** - Relevant memories are retrieved based on context
3. **Search** - Query memories anytime with semantic search

## Tools Available

- `mem0_add` - Store new memories
- `mem0_search` - Retrieve relevant memories by query
- `mem0_get_all` - List all stored memories

## Memory Strategy

- **Facts about Ko** → mem0 (persistent, searchable)
- **Daily conversation logs** → Keep in files (local record)
- **Operational knowledge** → Keep in SKILL.md files (static)

This hybrid approach gives us the best of both worlds.
