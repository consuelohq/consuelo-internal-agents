# COO Agent Customization Guide

This guide walks you through customizing the COO agent template for your business.

---

## Step 1: Set Your Project Root

Edit `.coo/agent/config.sh` and set your project path:

```bash
# Find this line:
PROJECT_ROOT=""  # TODO: Set your project root path

# Change to:
PROJECT_ROOT="/Users/yourname/Dev/your-project"
```

---

## Step 2: Configure bd-coo Alias

Add the alias to your shell configuration:

```bash
# Add to ~/.zshrc or ~/.bashrc:
alias bd-coo="bd --config /Users/yourname/Dev/your-project/.coo/.beads/config.yaml"

# Reload:
source ~/.zshrc
```

Then initialize:

```bash
cd /Users/yourname/Dev/your-project
bd-coo init
```

---

## Step 3: Update launchd plist Files

Each plist file in `.coo/agent/launchd/` needs path updates:

### Option A: Manual Update (Recommended for understanding)

Edit each `.plist` file and update:

1. **Label** - Change `com.yourcompany.coo.*` to your company name
2. **ProgramArguments** - Update path to `run-scheduled-task.sh`
3. **WorkingDirectory** - Update to your project root

Example changes in `com.yourcompany.coo.morning-research.plist`:

```xml
<!-- Change this: -->
<string>com.yourcompany.coo.morning-research</string>

<!-- To your company name: -->
<string>com.acme.coo.morning-research</string>

<!-- Update paths: -->
<string>/Users/yourname/Dev/your-project/.coo/agent/launchd/run-scheduled-task.sh</string>
<string>/Users/yourname/Dev/your-project</string>
```

### Option B: Batch Update (Quick)

```bash
# Run from your project root
cd /Users/yourname/Dev/your-project

# Replace placeholder paths in all plist files
find .coo/agent/launchd -name "*.plist" -exec sed -i '' \
  -e 's|/path/to/your/project|/Users/yourname/Dev/your-project|g' \
  -e 's|com.yourcompany|com.acme|g' \
  {} \;
```

### Option C: Interactive Install Script

The `install-launchd.sh` script will prompt for missing paths if they contain placeholders.

---

## Step 4: Create Your Business Context Document

Copy the template and fill in your details:

```bash
cp .coo/docs/BUSINESS_CONTEXT_TEMPLATE.md .coo/docs/BUSINESS_CONTEXT.md
```

Then edit `.coo/docs/BUSINESS_CONTEXT.md` with:

- What your product does
- Target customers and their pain points
- Your differentiation
- Current priorities
- Brand voice guidelines

This document is referenced by the COO agent when generating content.

---

## Step 5: Configure API Keys

Add required API keys to `~/.zshrc` or create `.coo/.env`:

```bash
# Core (Required)
export RESEND_API_KEY="re_..."           # Email sending

# Research (At least one required)
export CLAY_API_KEY="..."                # Lead enrichment
export APOLLO_API_KEY="..."              # Contact data

# Social (Optional - for Twitter/Instagram features)
export TWITTER_BEARER_TOKEN="..."        # Twitter API
export INSTAGRAM_ACCESS_TOKEN="..."      # Instagram API

# Notifications (Optional but recommended)
export SLACK_WEBHOOK_URL="https://hooks.slack.com/..."

# Metrics (Optional)
export GOOGLE_SHEETS_CREDENTIALS="/path/to/credentials.json"
```

---

## Step 6: Customize Email Templates

Edit files in `.coo/agent/templates/emails/`:

1. Update example templates with your product value propositions
2. Adjust A/B variant messaging for your audience
3. Set appropriate subject line patterns

Template structure:

```yaml
# templates/emails/01-ai-hook.yaml
name: AI Hook
variant: A
subject_template: "{first_name}, quick question about {company}"
body_template: |
  Hi {first_name},

  [Your personalized opening about their company]

  [Your value proposition - 2-3 sentences max]

  [Clear CTA]

  Best,
  [Your name]
```

---

## Step 7: Customize Twitter Templates

Edit files in `.coo/agent/templates/twitter/`:

1. Update content categories in `daily-tips.json`
2. Adjust hashtags in `hashtags.json` for your industry
3. Customize thread topics in `threads.json`

---

## Step 8: Update Install/Uninstall Scripts

Both scripts reference the launchd prefix. Update if you changed your company name:

In `.coo/agent/launchd/install-launchd.sh`:
```bash
PLIST_PREFIX="com.yourcompany.coo"  # Change to your prefix
```

In `.coo/agent/launchd/uninstall-launchd.sh`:
```bash
LAUNCHD_PREFIX="com.yourcompany.coo"  # Change to your prefix
```

---

## Step 9: Test the Setup

### Verify Environment

```bash
.coo/agent/init.sh
```

This checks:
- Required CLI tools
- bd-coo alias
- Directory structure
- API keys
- launchd jobs status

### Manual Task Test

```bash
# Run a task manually (doesn't send anything)
.coo/agent/launchd/run-scheduled-task.sh morning-research

# Check outputs in staging
ls -la .coo/agent/staging/$(date +%Y-%m-%d)/
```

### Dry Run QA

```bash
# Validate staging without sending
.coo/agent/run-qa.sh --dry-run
```

---

## Step 10: Install launchd Jobs

Once everything is configured:

```bash
.coo/agent/launchd/install-launchd.sh
```

Verify:

```bash
launchctl list | grep yourcompany
```

---

## Quick Checklist

- [ ] Set `PROJECT_ROOT` in `config.sh`
- [ ] Set up `bd-coo` alias and run `bd-coo init`
- [ ] Update paths in all 9 plist files
- [ ] Update labels in plist files (`com.yourcompany.coo.*`)
- [ ] Create `BUSINESS_CONTEXT.md` from template
- [ ] Configure API keys (at minimum: RESEND_API_KEY)
- [ ] Customize email templates for your product
- [ ] Update hashtags for your industry
- [ ] Run `init.sh` to verify setup
- [ ] Test with manual task execution
- [ ] Install launchd jobs

---

## Troubleshooting Common Issues

### "command not found: bd"

Install Beads CLI:
```bash
pip install beads-cli
# or
npm install -g beads-cli
```

### "No such file or directory" in launchd logs

Path not updated correctly. Check:
```bash
# View the plist file
cat ~/Library/LaunchAgents/com.yourcompany.coo.morning-research.plist

# Verify paths exist
ls -la /path/shown/in/plist
```

### "Permission denied" running scripts

Make scripts executable:
```bash
chmod +x .coo/agent/*.sh
chmod +x .coo/agent/launchd/*.sh
```

### Tasks not running at scheduled times

1. Verify jobs are loaded: `launchctl list | grep yourcompany`
2. Check Mac wasn't asleep at scheduled time
3. Review logs: `tail -f /tmp/coo-agent/scheduler.log`

### QA validation always failing

1. Check staging directory has files
2. Review specific errors in QA log
3. Verify email/phone formats match expected patterns

---

## Support

For issues with:
- **Template structure**: Check this repo's issues
- **Beads CLI**: https://github.com/steveyegge/beads
- **Claude Code**: https://github.com/anthropics/claude-code
- **launchd**: `man launchd.plist`
