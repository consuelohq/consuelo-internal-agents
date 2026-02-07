---
name: instagram-lead-scraper
description: "SCALED Instagram lead scraper using Agent Browser. Scrapes hashtags + profiles for rich contact data including phone, email, location. 50-100+ leads per run."
---

# Instagram Lead Scraper (Agent Browser Edition)

**Pure agent-browser scraping** for high-quality insurance agent leads with full contact details.

## What's Different (Agent Browser vs Brave Search)

| Feature | Brave Search | **Agent Browser** |
|---------|--------------|-------------------|
| **Speed** | 50 leads in 30s | 50 leads in 10-15 min |
| **Data Quality** | Basic (username, bio, followers) | **Rich (phone, email, location)** |
| **Source** | Google search results | **Instagram directly** |
| **Discovery** | Limited | **Hashtag pages = more leads** |
| **Contact Info** | ❌ | **✅ Phone, Email extracted from bios** |

**Trade-off:** Slower but way better data.

---

## Quick Start

### Run Agent Browser Scraper (50 leads, ~10-15 min)
```bash
cd skills/instagram-lead-scraper/scripts
npx tsx scrape-agent-browser.ts 50
```

### Options
```bash
# No Google Drive upload
npx tsx scrape-agent-browser.ts 50 --no-drive

# Small test (3 leads, ~2 min)
npx tsx scrape-agent-browser.ts 3 --no-drive
```

---

## How It Works

```
1. OPEN hashtag page (e.g., #insuranceagent)
2. EXTRACT usernames from profile pictures
3. VISIT each profile page
4. SCRAPE: bio, followers, posts, email, phone, location
5. FILTER: only insurance-related profiles
6. SAVE to database + CSV
```

### Data Extracted

| Field | Example |
|-------|---------|
| **username** | @garcia_agency |
| **full_name** | The Garcia Agency |
| **bio** | American Family Insurance Auto \| Home \| Life... |
| **followers** | 4,375 |
| **following** | 493 |
| **posts** | 196 |
| **📧 email** | teamgarcia@amfam.com |
| **📞 phone** | 470.854.2010 |
| **📍 location** | Atlanta, GA |
| **niche** | auto_home / life_insurance / medicare |
| **tags** | has-email, has-phone, has-location |

---

## Hashtags Scraped

The scraper rotates through these hashtags:

1. `#insuranceagent`
2. `#lifeinsuranceagent`
3. `#finalexpense`
4. `#finalexpenseagent`
5. `#lifeinsurance`
6. `#insurancebroker`
7. `#medicareagent`
8. `#healthinsuranceagent`
9. `#insuranceagency`
10. `#insurancesales`

Each hashtag yields 10-15 profiles before moving to the next.

---

## Database Schema

All fields are stored in the `leads` table:

```typescript
{
  source: 'instagram',
  sourceType: 'profile',
  externalId: 'garcia_agency',  // username
  externalUrl: 'https://instagram.com/garcia_agency',
  fullName: 'The Garcia Agency',
  email: 'teamgarcia@amfam.com',
  phone: '470.854.2010',
  location: 'Atlanta, GA',
  bio: 'American Family Insurance...',
  followers: 4375,
  following: 493,
  posts: 196,
  leadType: 'agent',
  niche: 'auto_home',
  tags: 'has-email,has-phone,has-location',
  status: 'new',
  scrapedDate: '2026-02-02'
}
```

---

## Usage

### As a Skill

When you say:
- "scrape instagram leads" → Runs agent-browser scraper
- "get me 50 insurance leads" → Runs agent-browser scraper
- "find agents on instagram" → Runs agent-browser scraper

### Programmatic

```typescript
import { scrapeInstagramAgentBrowser } from './scripts/scrape-agent-browser';

// Get 50 leads
const result = await scrapeInstagramAgentBrowser(50);

console.log(result);
// {
//   savedLeads: [...],
//   withEmail: 12,
//   withPhone: 8,
//   duration: 847, // seconds
//   csvFile: '/path/to/file.csv'
// }
```

---

## Performance

| Target | Time | Leads Found | With Contact Info |
|--------|------|-------------|-------------------|
| 10 | 2-3 min | 10-15 | 2-4 |
| 50 | 10-15 min | 50-70 | 10-20 |
| 100 | 20-30 min | 100-140 | 20-40 |

**Note:** Contact info (email/phone) appears in ~20-30% of bios.

---

## Comparison: Methods

### Method 1: Agent Browser (RECOMMENDED)
```bash
npx tsx scrape-agent-browser.ts 50
```
- ✅ Rich data (phone, email, location)
- ✅ Direct from Instagram
- ✅ Hashtag discovery
- ❌ Slower (10-15 min for 50)

### Method 2: Brave Search (Legacy)
```bash
npx tsx scrape-leads-scaled.ts 50
```
- ✅ Fast (30s for 50)
- ✅ No browser needed
- ❌ Basic data only
- ❌ Misses hashtag leads

**Recommendation:** Use Agent Browser for quality, Brave Search for speed/quantity.

---

## Files

```
skills/instagram-lead-scraper/
├── SKILL.md                              # This file
├── scripts/
│   ├── scrape-agent-browser.ts          # ⭐ MAIN: Agent browser scraper
│   ├── scrape-leads-scaled.ts           # Brave search version
│   ├── scrape-leads.ts                  # Original (legacy)
│   ├── apify-scraper.js                 # Apify integration
│   └── save-to-drive.py                 # Drive helper
└── references/
    ├── hashtag-guide.md
    └── quality-checklist.md
```

---

## Output Example

```
🤖 PURE AGENT-BROWSER INSTAGRAM SCRAPER
   Target: 50 leads
   Session: instagram-scraper

📊 Existing Instagram leads in DB: 299

🏷️  Scraping hashtag: #insuranceagent
   Found 12 profiles
   🔍 @garcia_agency... ✅ SAVED
      The Garcia Agency | 4,375 followers
      📧 teamgarcia@amfam.com
      📞 470.854.2010
      📍 Atlanta
   🔍 @alexmillerofficial... ✅ SAVED
      Alex Miller | 356K followers
   Progress: 3/50

✅ COMPLETE: 50 leads | 12 emails | 8 phones | 12m 34s
```

---

## Tips

### Getting More Contact Info
- Agents often put phone/email in bio
- Look for "📞", "📧", "Call", "Text" patterns
- Location often marked with "📍" or "in [City]"

### Rate Limiting
- Built-in 2s delay between profiles
- Built-in 3s delay between hashtags
- Uses persistent browser session

### Resuming
- Check database for existing usernames before scraping
- Won't duplicate leads (UNIQUE constraint on hash)

---

## Future Enhancements

- [ ] Auto-login for private profile access
- [ ] DM automation
- [ ] Follow automation
- [ ] Story viewing
- [ ] Comment scraping
- [ ] Engagement scoring

---

Last updated: 2026-02-02
Version: 3.0 (Agent Browser Edition)
