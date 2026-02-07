# LibreChat Artifacts - Working

## Status: ✅ FUNCTIONAL

Mermaid diagrams render correctly as interactive artifacts in LibreChat.

## Correct Format

```
:::artifact{identifier="unique-id" type="application/vnd.mermaid" title="Title"}
```mermaid
[content here]
```
:::
```

## Supported Types
- `application/vnd.mermaid` - flowcharts, diagrams ✅ TESTED
- `text/html` - html components
- `application/vnd.react` - react components
- `image/svg+xml` - svg graphics

## Use Cases (Be Proactive!)

**Use artifacts when:**
- Explaining workflows or architecture
- Visualizing data flow
- Creating diagrams of systems
- Building quick interactive prototypes
- Showing code structure
- Creating visual summaries

**Don't use when:**
- Simple text answer suffices
- Code is for copy-paste only
- One-line response

## Examples to Use

### System Architecture
```mermaid
flowchart TD
    A[Frontend] --> B[API]
    B --> C[Database]
```

### Decision Trees
```mermaid
flowchart TD
    A{Is it working?} -->|Yes| B[Ship it]
    A -->|No| C[Debug]
```

### Process Flows
```mermaid
sequenceDiagram
    User->>LibreChat: Send message
    LibreChat->>OpenClaw: API request
    OpenClaw->>Suelo: Process
    Suelo-->>OpenClaw: Response
    OpenClaw-->>LibreChat: Return
    LibreChat-->>User: Display
```

## Key Rule

**Always prefer artifacts over text walls when explaining complex systems.**

Visual diagrams > paragraphs of explanation
