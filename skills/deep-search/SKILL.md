---
name: deep-search
description: "Hybrid search using Brave for discovery + Agent Browser for deep extraction. Triggered by /deep-search command. Sequential execution, combined summary output."
---

# Deep Search

Hybrid search workflow: Brave Search finds URLs, Agent Browser extracts full page details.

## Usage

Mention `/deep-search` in your message:

```
/deep-search find insurance agents in miami
```

## What It Does

1. **Brave Search** — Finds top relevant URLs (3-5 results based on context)
2. **Agent Browser** — Sequentially opens each URL and extracts full page content
3. **Combined Summary** — Merges all findings into one coherent response

## Behavior

- **Trigger:** `/deep-search` anywhere in message
- **URL Count:** 3-5 results (judgment-based, not overkill)
- **Extraction:** Full page snapshot + text
- **Execution:** Sequential (Brave → Agent Browser one by one)
- **Output:** Single combined summary

## When to Use

- Deep research on a topic
- Finding contact info, company details, profiles
- When you need more than just search snippets
- Lead generation, competitor research, due diligence

## When NOT to Use

- Quick fact lookups (use regular web_search)
- Known URLs (use agent-browser or browser directly)
- Time-sensitive simple queries
