# GitHub Review Skill

World-class automated code reviews using GitHub API. One command, everything posted to GitHub.

## Quick Start

```bash
# review a pr and post everything to github
review pr 788

# preview without posting
review pr 788 --local-only

# by url
review "https://github.com/kokayicobb/consuelo_on_call_coaching/pull/788"
```

## What Gets Posted

Every review creates these GitHub artifacts:

### 1. Checklist Comment
Tracks all review categories with checkboxes:
- ✓ functionality
- ✓ readability  
- ✓ maintainability
- ✓ security
- ✓ performance
- ✓ coding standards

### 2. Overall Review Summary
Categorized findings:
- **Blocking Issues** - must fix before merge
- **Security Issues** - vulnerabilities found
- **Suggestions** - improvements (non-blocking)
- **Questions** - clarifications needed
- **Praise** - things done well
- **Nitpicks** - minor style issues

### 3. Inline Comments
Specific feedback on individual lines using conventional comments format:
```
issue (blocking): sql injection vulnerability

this directly interpolates user input. use parameterized queries instead.
```

### 4. Labels
Auto-applied based on findings:
- `needs-tests` - minimal or no test coverage
- `needs-docs` - pr description missing context
- `security-review` - security issues found
- `changes-requested` - blocking issues present

## Advanced Usage

```bash
# auto-approve if no blocking issues
review pr 788 --approve

# suggest splitting if too many features
review pr 788 --split-pr

# more detailed feedback
review pr 788 --verbose
```

## Conventional Comments

All feedback follows this format:
```
<label> [decorations]: <subject>

[discussion + reasoning]
```

**Labels:**
- `praise` - something done well
- `nitpick` - trivial preference (always non-blocking)
- `suggestion` - improvement idea
- `issue` - problem found
- `question` - clarification needed
- `thought` - idea for consideration

**Decorations:**
- `blocking` - must fix before merge
- `non-blocking` - nice to have but not required
- `security` - security-related
- `test` - testing-related
- `readability` - code clarity
- `maintainability` - future maintenance
- `performance` - efficiency concern

## How Split Detection Works

The skill intelligently suggests splitting when:
- Multiple file types are changed (frontend + backend + db)
- Multiple logical areas are touched (api + ui + utils)
- Too many files are changed (>15)
- Large functions are detected (>30 lines)

This is feature-based analysis, not line-count based.

## For OpenCode

Everything is posted to GitHub, so OpenCode can:
- See the full checklist and what was checked
- Review all inline comments
- Check labels and follow up on issues
- Address blocking items
- See praise and learn from good patterns

The GitHub PR page becomes the hub for all review activity.

## Requirements

- GitHub CLI (gh) installed and authenticated
- Python 3.8+
