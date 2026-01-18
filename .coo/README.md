# COO Agent Template

> Autonomous business operations agent for GTM tasks. Executes prospecting, email generation, social content, and metrics tracking on a schedule.

---

## Overview

The COO Agent is an autonomous AI system that runs scheduled business tasks. It operates independently from the development agent, with its own:

- **Beads task queue** (`.coo/.beads/`) - Separate from dev tasks
- **Scheduling system** (macOS launchd) - Runs at set times daily
- **Output directories** (staging + final) - For generated content
- **Two-session workflow** - Worker generates, QA validates before sending

**Key Principle:** Nothing is sent (emails, tweets) or pushed (GitHub) until QA validation passes.

---

## Quick Start

### Prerequisites

1. **Beads CLI** installed (`npm install -g beads-cli`)
2. **Claude Code CLI** installed and authenticated
3. **macOS** (for launchd scheduling)
4. **API keys** configured (see [Environment Setup](#environment-setup))

### Installation

```bash
# 1. Set up bd-coo alias (run once)
# TODO: Update PROJECT_ROOT to your project path
echo 'alias bd-coo="bd --config /path/to/your/project/.coo/.beads/config.yaml"' >> ~/.zshrc
source ~/.zshrc

# 2. Initialize COO Beads instance (if first time)
cd /path/to/your/project
bd-coo init

# 3. Install launchd scheduled tasks
# NOTE: First update paths in plist files (see CUSTOMIZATION.md)
.coo/agent/launchd/install-launchd.sh

# 4. Verify installation
launchctl list | grep yourcompany
```

### Uninstallation

```bash
# Remove all scheduled tasks
.coo/agent/launchd/uninstall-launchd.sh
```

---

## Architecture

```
.coo/
├── README.md                   # This file
├── CLAUDE.md                   # COO context and instructions for Claude
├── CUSTOMIZATION.md            # Step-by-step customization guide
├── docs/
│   └── BUSINESS_CONTEXT.md     # Your business context document
├── .beads/                     # Separate Beads instance (COO tasks only)
│   ├── config.yaml
│   ├── beads.db
│   └── issues.jsonl
└── agent/
    ├── coo-progress.txt        # Session continuity log
    ├── launchd/
    │   ├── install-launchd.sh       # Install all scheduled tasks
    │   ├── uninstall-launchd.sh     # Remove all scheduled tasks
    │   ├── run-scheduled-task.sh    # Task wrapper (called by launchd)
    │   └── *.plist                  # Individual task schedules
    ├── staging/                # Worker outputs (pending QA)
    │   └── {date}/             # Date-organized subdirectories
    ├── outputs/                # Final outputs (after QA validation)
    │   ├── emails/             # Sent email logs
    │   ├── leads/              # Lead CSVs
    │   ├── instagram/          # Instagram prospect lists
    │   └── twitter/            # Posted Twitter content
    └── state/
        └── warmup-day.txt      # Email warm-up day counter
```

---

## Daily Schedule

| Time | Task | Description |
|------|------|-------------|
| 7:00 AM | Morning Research | Research prospects using Clay, Apollo, YouSearch |
| 7:45 AM | Generate Emails | Create personalized cold emails (respects warm-up limits) |
| 8:00 AM | Twitter Post #1 | Morning post (industry insights) |
| 9:00 AM | Instagram Prospects | Generate list for manual DM outreach |
| 12:00 PM | Twitter Post #2 | Midday post (productivity/tips) |
| 12:30 PM | Dialer Leads | Generate phone leads CSV for sales calls |
| 4:00 PM | Update Metrics | Update tracking spreadsheet |
| 4:30 PM | Twitter Thread | Educational thread (Tue/Thu only) |
| 5:00 PM | Twitter Post #3 | Evening post (engagement/questions) |

---

## Two-Session Workflow

The COO agent uses a two-session safety workflow:

### Session 1: Worker
1. Picks up task from `bd-coo` queue
2. Researches/generates content
3. Saves outputs to `staging/{date}/`
4. Does NOT send emails or post tweets

### Session 2: QA (Quality Assurance)
1. Reads from staging directory
2. Validates all outputs:
   - **Emails:** Required fields, valid addresses, A/B variant assigned, warm-up limits
   - **Leads:** No duplicates, valid phone format (E.164), required fields
   - **Twitter:** Under 280 chars, has hashtags, no sensitive content
3. **If ALL pass:** Sends emails, posts tweets, pushes to GitHub, marks task complete
4. **If ANY fail:** Halts all actions, marks task `needs-review`, notifies via Slack

**Safety guarantee:** External actions only happen after QA validation passes.

---

## Beads Task Management

The COO agent uses a separate Beads instance to avoid task confusion with the dev agent.

```bash
# COO tasks only (use bd-coo alias)
bd-coo list                      # List open COO tasks
bd-coo create "[GTM]: Task..."   # Create new task
bd-coo show <task-id>            # Show task details
bd-coo close <task-id>           # Close completed task

# Dev tasks (regular bd command)
bd list                          # List open dev tasks
```

### Task Types

| Prefix | Description |
|--------|-------------|
| `[GTM]` | Go-to-market tasks |
| `[OUTREACH]` | Email/social outreach |
| `[RESEARCH]` | Prospect research |
| `[CONTENT]` | Content creation (Twitter, blog) |
| `[METRICS]` | Tracking and reporting |

---

## Email Warm-Up

New email domains need warm-up to avoid spam filters. The agent auto-tracks this:

| Days | Daily Limit |
|------|-------------|
| 1-3 | 10 emails |
| 4-7 | 25 emails |
| 8-14 | 50 emails |
| 15+ | 100 emails |

Warm-up day is stored in `.coo/agent/state/warmup-day.txt` and automatically increments.

---

## Environment Setup

### Required API Keys

Add these to `.coo/.env` or `~/.zshrc`:

```bash
# Email (Required for outreach)
export RESEND_API_KEY="re_..."

# Prospect Research
export CLAY_API_KEY="your_clay_key"
export APOLLO_API_KEY="your_apollo_key"

# Social Media
export TWITTER_API_KEY="your_twitter_key"
export TWITTER_API_SECRET="your_twitter_secret"
export TWITTER_BEARER_TOKEN="your_bearer_token"
export INSTAGRAM_ACCESS_TOKEN="your_instagram_token"

# Metrics & Scraping
export GOOGLE_SHEETS_CREDENTIALS="/path/to/credentials.json"
export BROWSE_AI_API_KEY="your_browse_key"

# Notifications
export SLACK_WEBHOOK_URL="https://hooks.slack.com/..."
```

### API Key Sources

| Service | How to Get | Cost |
|---------|------------|------|
| Resend | resend.com signup | Free tier: 3k emails/mo |
| Clay | clay.com → Settings → API | Free tier available |
| Apollo.io | apollo.io → Settings → Integrations | Free: 100 credits/mo |
| Twitter/X | developer.twitter.com (apply) | Free tier (50 tweets/day) |
| Google Sheets | Google Cloud Console (service account) | Free |
| Browse.ai | browse.ai dashboard | Free: 2 robots |
| Instagram | Meta Business Suite | Free |

---

## Logs & Debugging

### Log Locations

```bash
# Main log
tail -f /tmp/coo-agent/coo-agent.log

# Worker logs (by date)
tail -f /tmp/coo-agent/worker-$(date +%Y-%m-%d).log

# QA logs (by date)
tail -f /tmp/coo-agent/qa-$(date +%Y-%m-%d).log

# Session progress
cat .coo/agent/coo-progress.txt
```

### Verify launchd Status

```bash
# List all COO jobs
launchctl list | grep yourcompany

# Check if a specific job ran
log show --predicate 'subsystem == "com.apple.launchd"' --last 1h | grep yourcompany
```

### Manual Task Execution

```bash
# Run a specific task manually (for testing)
.coo/agent/launchd/run-scheduled-task.sh morning-research

# Available task types:
# morning-research, generate-emails, twitter-post-1, twitter-post-2,
# twitter-post-3, twitter-thread, instagram-prospects, dialer-leads, update-metrics
```

---

## Troubleshooting

### Task Not Running

1. Check launchd job is loaded:
   ```bash
   launchctl list | grep yourcompany.coo.morning-research
   ```

2. Check if Mac was asleep at scheduled time (launchd catches up)

3. Verify `bd` and `claude` CLIs are in PATH:
   ```bash
   which bd && which claude
   ```

### QA Validation Failing

1. Check staging directory:
   ```bash
   ls -la .coo/agent/staging/$(date +%Y-%m-%d)/
   ```

2. Review QA log:
   ```bash
   cat /tmp/coo-agent/qa-$(date +%Y-%m-%d).log
   ```

3. Task will be marked `needs-review` - manually review and fix

### Emails Not Sending

1. Check Resend API key is valid
2. Check warm-up limits not exceeded
3. Verify QA validation passed
4. Review `.coo/agent/outputs/emails/` for sent logs

### Missing API Keys

```bash
# Check which keys are set
env | grep -E "(RESEND|CLAY|APOLLO|TWITTER|SLACK)" | cut -d= -f1
```

---

## Decisions & Rationale

| Decision | Choice | Why |
|----------|--------|-----|
| Beads separation | Separate instance | No task confusion with dev agent |
| Scheduling | macOS launchd | Survives sleep/wake, reliable |
| Two-session workflow | Worker + QA | Nothing sent until validated |
| GitHub push | After QA only | Audit trail, Slack notifications |
| Email warm-up | Auto-track | Agent adjusts volume automatically |
| Twitter cadence | 3 posts/day | Maximizes visibility across timezones |

---

*Template version: 1.0.0*
