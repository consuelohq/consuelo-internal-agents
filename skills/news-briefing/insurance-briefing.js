#!/usr/bin/env node
/**
 * Daily Insurance Industry News Briefing
 * Combines Brave search + Agent Browser scraping
 */

const { execSync } = require('child_process');

async function runInsuranceBriefing() {
  const results = {
    search: null,
    sites: {}
  };
  
  // 1. Brave Search - Industry news
  try {
    console.log('🔍 Brave search: insurance industry news...');
    const searchOutput = execSync(
      `openclaw web_search "life insurance industry news cold calling outbound sales today" --count 10`,
      { encoding: 'utf8', timeout: 30000 }
    );
    results.search = searchOutput;
  } catch (e) {
    console.error('Search failed:', e.message);
  }
  
  // 2. Agent Browser - Site scraping
  const sites = [
    { name: 'InsuranceNewsNet', url: 'https://insurancenewsnet.com/' },
    { name: 'Insurance Journal', url: 'https://www.insurancejournal.com/' },
    { name: 'ThinkAdvisor', url: 'https://www.thinkadvisor.com/' },
    { name: 'LifeHealthPro', url: 'https://www.lifehealthpro.com/' }
  ];
  
  for (const site of sites) {
    try {
      console.log(`🌐 Scraping ${site.name}...`);
      
      execSync(`agent-browser open "${site.url}" --session insbrief`, { timeout: 15000 });
      
      const snapshot = execSync(
        `agent-browser snapshot --json`,
        { encoding: 'utf8', timeout: 10000 }
      );
      
      results.sites[site.name] = snapshot.substring(0, 3000);
      
      execSync(`agent-browser close --session insbrief`, { timeout: 5000 });
    } catch (e) {
      console.error(`${site.name} failed:`, e.message);
      results.sites[site.name] = 'Failed to load';
    }
  }
  
  // 3. Compile and send
  const briefing = compileInsuranceBriefing(results);
  
  try {
    execSync(`openclaw message send --channel slack --to '#suelo' --message '${briefing.replace(/'/g, "'\"'\"'")}'`);
    console.log('✅ Insurance briefing sent to Slack');
  } catch (e) {
    console.error('Failed to send:', e.message);
  }
}

function compileInsuranceBriefing(data) {
  let msg = `🏛️ *Daily Insurance Industry Briefing*\n\n`;
  
  msg += `*📊 Industry News (Web Search)*\n`;
  if (data.search) {
    msg += data.search.substring(0, 2000);
  } else {
    msg += 'Search unavailable\n';
  }
  
  msg += `\n\n*📰 From Trade Publications:*\n`;
  for (const [site, content] of Object.entries(data.sites)) {
    msg += `\n*${site}:*\n`;
    msg += content.substring(0, 500) + (content.length > 500 ? '...' : '');
    msg += '\n';
  }
  
  return msg;
}

runInsuranceBriefing();
