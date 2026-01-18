# Twitter Content Templates

> **NOTE**: These are example templates. Customize for your brand voice and audience.

## Template Types

### Single Posts
- `single-insight.json` - Share industry insights
- `single-question.json` - Engagement questions

### Threads
- `thread-howto.json` - How-to educational threads
- `thread-story.json` - Narrative/story threads

## Template Structure

```json
{
  "name": "template-name",
  "type": "single | thread",
  "category": "insight | question | howto | story | promotion",
  "tone": "professional | casual | bold | educational",
  "hooks": ["Array of opening hook patterns"],
  "structure": {
    "description": "How to structure the content"
  },
  "variables": ["placeholders", "to_fill"],
  "examples": ["Sample content"]
}
```

## Best Practices

### Hooks (First Line)
- Lead with value or curiosity
- Avoid "I" as the first word
- Keep under 100 characters
- Test different angles

### Content
- Break long sentences into multiple tweets (threads)
- Use line breaks for readability
- Include 1-2 relevant hashtags max
- Tag relevant people/companies sparingly

### Timing
- Post during peak engagement hours for your audience
- Space out promotional content
- Engage with replies within first hour

## Customization

1. Update examples with your industry knowledge
2. Adjust tone to match your brand
3. Add your own hooks that have worked
4. Track which templates get best engagement
