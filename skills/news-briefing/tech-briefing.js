#!/usr/bin/env node
/**
 * Daily Tech/AI News Briefing
 * Combines Brave search + Agent Browser scraping
 */

const { execSync } = require('child_process');

async function runTechBriefing() {
  const results = {
    search: null,
    sites: {}
  };
  
  // 1. Brave Search - Breaking news
  try {
    console.log('🔍 Brave search: tech/ai news...');
    const searchOutput = execSync(
      `openclaw web_search "today tech AI news breaking major developments" --count 10`,
      { encoding: 'utf8', timeout: 30000 }
    );
    results.search = searchOutput;
  } catch (e) {
    console.error('Search failed:', e.message);
  }
  
  // 2. Agent Browser - Site scraping
  const sites = [
    { name: 'TechCrunch', url: 'https://techcrunch.com/latest/' },
    { name: 'The Verge', url: 'https://www.theverge.com/tech' },
    { name: 'Ars Technica', url: 'https://arstechnica.com/' },
    { name: 'Techmeme', url: 'https://www.techmeme.com/' },
    { name: 'Wired', url: 'https://www.wired.com/' }
  ];
  
  for (const site of sites) {
    try {
      console.log(`🌐 Scraping ${site.name}...`);
      
      // Open and snapshot
      execSync(`agent-browser open "${site.url}" --session techbrief`, { timeout: 15000 });
      
      // Get snapshot for headlines
      const snapshot = execSync(
        `agent-browser snapshot --json`,
        { encoding: 'utf8', timeout: 10000 }
      );
      
      results.sites[site.name] = snapshot.substring(0, 3000); // Truncate
      
      execSync(`agent-browser close --session techbrief`, { timeout: 5000 });
    } catch (e) {
      console.error(`${site.name} failed:`, e.message);
      results.sites[site.name] = 'Failed to load';
    }
  }
  
  // 3. Compile and send to Slack
  const briefing = compileTechBriefing(results);
  
  try {
    execSync(`openclaw message send --channel slack --to '#suelo' --message '${briefing.replace(/'/g, "'\"'\"'")}'`);
    console.log('✅ Tech briefing sent to Slack');
  } catch (e) {
    console.error('Failed to send:', e.message);
  }
}

function compileTechBriefing(data) {
  let msg = `📰 *Daily Tech/AI Briefing*\n\n`;
  
  msg += `*🔥 Breaking News (Web Search)*\n`;
  if (data.search) {
    msg += data.search.substring(0, 2000);
  } else {
    msg += 'Search unavailable\n';
  }
  
  msg += `\n\n*📱 From Key Sites:*\n`;
  for (const [site, content] of Object.entries(data.sites)) {
    msg += `\n*${site}:*\n`;
    msg += content.substring(0, 500) + (content.length > 500 ? '...' : '');
    msg += '\n';
  }
  
  return msg;
}

runTechBriefing();
