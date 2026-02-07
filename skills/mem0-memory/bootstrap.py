#!/usr/bin/env python3
"""Bootstrap mem0 with key facts about Ko"""

import sys
sys.path.insert(0, '/Users/kokayi/.openclaw/workspace/skills/mem0-memory')

from mem0_client import get_memory

mem = get_memory()

key_facts = [
    "Ko is the founder of Consuelo, an on-call coaching platform with Twilio integration and AI-powered talking points",
    "Ko is currently focused on go-to-market strategy and trying to get paying customers",
    "Ko prefers all lowercase communication always, including in threads",
    "Ko wakes up around 10am and goes to bed around 3am",
    "Ko works from home and does lots of coding",
    "Ko's dream is to build a big tech company",
    "Ko likes indie music, rap, R&B, EDM - a little bit of everything",
    "Ko is active on Twitter and loves being on the front edge of tech/AI",
    "Ko prefers Suelo to take action without asking for confirmation, except for destructive actions",
    "Ko wants help breaking patterns around drinking and masturbating",
    "All notifications should go to Slack channel #suelo, not webchat",
    "Ko wants Suelo to be an all-around helper for both work and personal",
]

print("Adding key facts to mem0...")
for fact in key_facts:
    result = mem.add(fact)
    print(f"✓ Added: {fact[:60]}...")

print("\nDone! Testing search...")
results = mem.search("communication style")
print(f"\nFound {len(results.get('results', []))} relevant memories")
