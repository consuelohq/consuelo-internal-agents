#!/usr/bin/env node
/**
 * Scrape Instagram leads using Brave web search
 * Finds insurance agent profiles and saves to database + CSV
 */

import { db } from '../db/db.js';
import { leads } from '../db/schema.js';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { fileURLToPath } from 'url';
import { execSync } from 'child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Create hash for deduplication
function createHash(source, externalId) {
  return crypto.createHash('md5').update(`${source}:${externalId}`.toLowerCase()).digest('hex');
}

// Sleep function for rate limiting
function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Search terms for finding insurance agents on Instagram
const SEARCH_TERMS = [
  'site:instagram.com insurance agent',
  'site:instagram.com "final expense" agent',
  'site:instagram.com life insurance agent',
  'site:instagram.com insurance broker',
  'site:instagram.com state farm agent',
  'site:instagram.com allstate agent',
  'site:instagram.com "insurance agent" "life insurance"',
  'site:instagram.com independent insurance agent',
  'site:instagram.com licensed insurance agent',
  'site:instagram.com new york life agent',
  'site:instagram.com northwestern mutual agent',
];

// Extract username from Instagram URL
function extractUsername(url) {
  const match = url.match(/instagram\.com\/([^\/\?]+)/);
  return match ? match[1].toLowerCase() : null;
}

// Extract follower count from text
function extractFollowers(text) {
  const match = text.match(/([\d,]+)\s*(?:followers|Followers)/);
  if (match) {
    return parseInt(match[1].replace(/,/g, ''));
  }
  return null;
}

// Check if text looks like an insurance agent profile
function isInsuranceAgentProfile(text, title) {
  const lower = (text + ' ' + title).toLowerCase();
  const indicators = [
    'insurance agent', 'insurance broker', 'life insurance', 
    'final expense', 'health insurance', 'licensed agent',
    'state farm', 'allstate', 'farmers insurance', 'progressive',
    'new york life', 'northwestern mutual', 'prudential',
    'help families', 'protect families', 'financial advisor'
  ];
  return indicators.some(i => lower.includes(i));
}

// Run web search using openclaw
async function runWebSearch(query) {
  try {
    // Use openclaw web_search tool via exec
    const result = execSync(
      `cd /Users/kokayi/.openclaw/workspace && echo '{"tool": "web_search", "arguments": {"query": "${query}", "count": 20}}' | openclaw tools web_search --json`,
      { encoding: 'utf8', timeout: 30000 }
    );
    return JSON.parse(result);
  } catch (e) {
    console.error(`search failed for "${query}":`, e.message);
    return [];
  }
}

// Alternative: use curl to call the search API directly
async function searchWeb(query, count = 20) {
  try {
    // Try using the web_search tool through npx
    const cmd = `npx openclaw tools web_search "${query.replace(/"/g, '\\"')}" --count ${count} --json`;
    const result = execSync(cmd, { 
      encoding: 'utf8', 
      timeout: 30000,
      cwd: '/Users/kokayi/.openclaw/workspace'
    });
    return JSON.parse(result);
  } catch (e) {
    console.error(`search error:`, e.message);
    return null;
  }
}

// Get existing Instagram usernames from database
async function getExistingUsernames() {
  const existing = await db.query.leads.findMany({
    where: (leads, { eq }) => eq(leads.source, 'instagram'),
    columns: { externalId: true }
  });
  return new Set(existing.map(l => l.externalId?.toLowerCase()).filter(Boolean));
}

// Scrape leads from search results
async function scrapeFromSearch(results, existingUsernames) {
  const newLeads = [];
  
  for (const result of results) {
    const url = result.url || result.link;
    if (!url || !url.includes('instagram.com')) continue;
    
    const username = extractUsername(url);
    if (!username) continue;
    
    // Skip if already in database
    if (existingUsernames.has(username)) continue;
    
    // Skip common non-agent accounts
    if (['p', 'reel', 'stories', 'explore', 'accounts'].includes(username)) continue;
    if (username.startsWith('p/') || username.includes('/')) continue;
    
    // Check if it looks like an agent profile
    const text = `${result.title || ''} ${result.description || ''} ${result.snippet || ''}`;
    if (!isInsuranceAgentProfile(text, result.title || '')) continue;
    
    const lead = {
      username: username,
      profileUrl: `https://instagram.com/${username}`,
      fullName: result.title?.split('•')[0]?.trim() || result.title?.split('•')[0]?.trim() || null,
      bio: result.description || result.snippet || null,
      followers: extractFollowers(text),
      location: null, // Would need to visit page to get this
      scrapedDate: new Date().toISOString().split('T')[0],
    };
    
    newLeads.push(lead);
    existingUsernames.add(username); // Add to prevent duplicates in same batch
  }
  
  return newLeads;
}

// Save leads to database in batches
async function saveToDatabase(leadsData, batchId) {
  const saved = [];
  
  for (const lead of leadsData) {
    try {
      const hash = createHash('instagram', lead.username);
      
      await db.insert(leads).values({
        source: 'instagram',
        batchId: batchId,
        externalId: lead.username,
        externalUrl: lead.profileUrl,
        fullName: lead.fullName,
        bio: lead.bio,
        followers: lead.followers,
        location: lead.location,
        leadType: 'agent',
        niche: 'final_expense',
        scrapedDate: lead.scrapedDate,
        hash: hash,
        status: 'new'
      });
      
      saved.push(lead);
    } catch (e) {
      if (!e.message?.includes('UNIQUE constraint')) {
        console.error(`error saving ${lead.username}:`, e.message);
      }
    }
  }
  
  return saved;
}

// Save leads to CSV
function saveToCSV(leadsData, filename) {
  const leadsDir = path.join(__dirname, '..', '..', 'leads');
  if (!fs.existsSync(leadsDir)) {
    fs.mkdirSync(leadsDir, { recursive: true });
  }
  
  const filePath = path.join(leadsDir, filename);
  const headers = ['username', 'profile_url', 'full_name', 'bio', 'followers', 'location', 'scraped_date'];
  
  // Check if file exists to determine if we need headers
  const fileExists = fs.existsSync(filePath);
  
  const lines = leadsData.map(l => [
    l.username,
    l.profileUrl,
    `"${(l.fullName || '').replace(/"/g, '""')}"`,
    `"${(l.bio || '').replace(/"/g, '""')}"`,
    l.followers || '',
    l.location || '',
    l.scrapedDate
  ].join(','));
  
  if (!fileExists) {
    fs.writeFileSync(filePath, headers.join(',') + '\n' + lines.join('\n'));
  } else {
    fs.appendFileSync(filePath, '\n' + lines.join('\n'));
  }
  
  return filePath;
}

// Main scraping function
async function scrapeInstagramLeads(targetCount = 50) {
  const batchId = `instagram-${new Date().toISOString().split('T')[0]}-batch`;
  console.log(`🔍 scraping instagram leads (target: ${targetCount})\n`);
  
  // Get existing usernames to avoid duplicates
  const existingUsernames = await getExistingUsernames();
  console.log(`📊 existing instagram leads in db: ${existingUsernames.size}`);
  
  const allNewLeads = [];
  let searchCount = 0;
  
  // Shuffle search terms for variety
  const shuffledTerms = SEARCH_TERMS.sort(() => Math.random() - 0.5);
  
  for (const term of shuffledTerms) {
    if (allNewLeads.length >= targetCount) break;
    
    console.log(`\n🔎 searching: "${term}"`);
    searchCount++;
    
    try {
      // Use web_search tool via the available function
      const results = await webSearch(term, 20);
      
      if (results && results.length > 0) {
        const newLeads = await scrapeFromSearch(results, existingUsernames);
        
        if (newLeads.length > 0) {
          console.log(`  ✓ found ${newLeads.length} potential leads`);
          allNewLeads.push(...newLeads);
        } else {
          console.log(`  • no new leads found`);
        }
      }
    } catch (e) {
      console.error(`  ✗ search failed:`, e.message);
    }
    
    // Rate limiting - wait between searches
    if (searchCount < shuffledTerms.length) {
      await sleep(2000);
    }
  }
  
  console.log(`\n💾 saving ${allNewLeads.length} leads to database...`);
  
  // Save to database
  const saved = await saveToDatabase(allNewLeads, batchId);
  console.log(`  ✓ saved ${saved.length} new leads to database`);
  
  // Save to CSV
  const csvFile = `instagram-leads-${new Date().toISOString().split('T')[0]}-batch.csv`;
  const csvPath = saveToCSV(saved, csvFile);
  console.log(`  ✓ saved to csv: ${csvPath}`);
  
  // Get updated stats
  const stats = db.$client.prepare(`
    SELECT source, COUNT(*) as count 
    FROM leads 
    GROUP BY source
  `).all();
  
  const total = db.$client.prepare('SELECT COUNT(*) as count FROM leads').get();
  
  console.log(`\n📊 database totals:`);
  stats.forEach(s => console.log(`   - ${s.source}: ${s.count} leads`));
  console.log(`   - total: ${total.count} leads`);
  
  return {
    found: allNewLeads.length,
    saved: saved.length,
    csvFile: csvPath
  };
}

// Wrapper to call web_search tool
async function webSearch(query, count = 20) {
  // This function will be called by the actual tool
  // For now, return empty - the real implementation uses the web_search tool
  return [];
}

// Run if called directly
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const target = parseInt(process.argv[2]) || 50;
  scrapeInstagramLeads(target).catch(console.error);
}

export { scrapeInstagramLeads };
