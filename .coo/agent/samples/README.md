# Sample Data Files

> **NOTE**: These are fictional example files to demonstrate expected data formats.
> All names, companies, and emails are made up for illustration purposes.

## Purpose

These samples show the expected format for:
- Input files (leads to process)
- Output files (generated content)

Use them as references when:
- Setting up your data pipeline
- Testing the agent workflow
- Understanding expected formats

## Files

### Input Formats

| File | Description |
|------|-------------|
| `sample-leads.csv` | Prospect list format |
| `sample-research.json` | Company research data |

### Output Formats

| File | Description |
|------|-------------|
| `sample-emails-output.csv` | Generated email drafts |
| `sample-twitter-output.json` | Generated twitter content |

## Field Definitions

### Leads CSV Fields
- `email`: Contact email address
- `first_name`: Contact first name
- `last_name`: Contact last name
- `company`: Company name
- `title`: Job title
- `linkedin_url`: LinkedIn profile (optional)
- `source`: Where the lead came from
- `notes`: Additional context

### Emails Output Fields
- `to_email`: Recipient email
- `to_name`: Recipient name
- `subject`: Email subject line
- `body`: Email content
- `template_used`: Which template generated this
- `status`: draft | approved | sent | failed

### Twitter Output Fields
- `content`: Tweet text
- `type`: single | thread
- `scheduled_time`: When to post
- `template_used`: Which template generated this
- `status`: draft | approved | posted

## Integration

These formats work with:
- Resend API (emails)
- Twitter API v2 (posts)
- Standard CRM exports (leads)

Modify as needed for your specific integrations.
