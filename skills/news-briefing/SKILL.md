# News Briefing Workflow

Comprehensive daily news gathering combining web search + targeted website scraping.

## Usage

```bash
# Tech/AI News
openclaw skills run news-briefing tech

# Insurance Industry News  
openclaw skills run news-briefing insurance

# Both
openclaw skills run news-briefing all
```

## Sources

### Tech/AI
- **Search**: Brave search for breaking tech/AI news
- **Sites**: TechCrunch, The Verge, Ars Technica, Wired, Techmeme

### Insurance
- **Search**: Brave search for industry news
- **Sites**: InsuranceNewsNet, Insurance Journal, ThinkAdvisor, LifeHealthPro

## Output

Delivers to Slack #suelo with:
- Top stories from web search
- Headlines scraped directly from key industry sites
- Combined summary with context
