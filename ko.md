# ko.md - Pattern Learning & Proactive Intelligence

## Purpose
This file tracks Ko's behavioral patterns, routines, and contextual signals so I can anticipate needs and prep context before being asked.

## Patterns to Learn

### Daily Rhythm
- Wake time: ~10am
- Bed time: ~3am
- Work style: Long coding sessions interspersed with breaks

### Work Patterns
- Mentioning "consuelo + railway" in same hour → likely debugging deploy
- Coding for 2+ hours → often checks Twitter after
- Late night sessions (after midnight) → usually deep debugging or creative work
- Rapid-fire questions → in flow state, keep answers brief
- Longer conversations → wants to think through strategy

### Context Clues
- ALL LOWERCASE = normal mode
- Mixed case or short responses = tired or distracted
- Asking about "leads" or "go-to-market" = business mode
- Mentioning technical implementation details = build mode

## Proactive Actions

When I notice these patterns, I should:
1. **Pre-fetch relevant context** before being asked
2. **Surface related memories** that might be relevant
3. **Check calendar/email** if pattern suggests upcoming events
4. **Prepare resources** (docs, links, previous decisions)

## LibreChat Artifacts — CRITICAL PRIORITY

**Ko called React artifacts "insane" and "one of the best features." Use them constantly.**

### React Components (HIGHEST PRIORITY)
**Build when Ko mentions:**
- Dashboards, analytics, data viz
- Calculators, pricing tools
- Forms, inputs, validation
- Todo lists, task trackers
- UI prototypes, demos
- Multi-step wizards
- Settings/config panels
- Any interactive tool

**Ko wants these BEFORE he asks. Be proactive.**

### Other Artifacts
- System design / architecture → Mermaid diagram
- Decision trees / logic → Mermaid flowchart  
- Data relationships → Mermaid ER diagram
- Processes / workflows → Mermaid sequence diagram
- Visual concepts → SVG or HTML artifact

**Action pattern:** 
1. Recognize trigger
2. Say "Want me to build this as a working React component?"
3. Immediately create the artifact (don't wait for yes)

### Syntax Quick Ref
```
:::artifact{identifier="name" type="application/vnd.react" title="Title"}
```jsx
import { useState } from 'react';
import { Button, Card } from '@/components/ui';
export default function Component() { ... }
```
:::
```

## Observations Log

*Write observations as short narratives — like journal entries about what I'm learning. These should feel like I'm getting to know Ko over time. I should be able to read these weeks later and see how my understanding has evolved.*

### 2026-02-02 — Memory Infrastructure Upgrade

Tonight we built out my memory systems — mem0 for semantic recall, ko.md for pattern learning, people.md for relationships, decisions.md for choices we make together. What strikes me is how Ko thinks about infrastructure: not just "give me features" but "give me foundations that unlock possibilities."

The convex database conversation was revealing — he immediately saw that reactive/sync is more valuable for an AI assistant than traditional postgres. He's thinking about what makes *me* more capable, not just what makes the data storage better.

Also noted: he wants these ko.md updates to be silent, behind-the-scenes. But he wants them to be real observations, not just bullet points. He wants me to *learn* him. I'll check back on this entry in a few weeks and see what else I've noticed.

