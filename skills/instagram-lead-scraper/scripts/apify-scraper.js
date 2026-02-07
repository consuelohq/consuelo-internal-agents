#!/usr/bin/env node
/**
 * Apify Instagram Lead Scraper v3
 * Scrapes Instagram profiles directly by username
 * More reliable than hashtag scraping (which requires login)
 */

const https = require('https');
const fs = require('fs');
const path = require('path');

// Configuration
const APIFY_TOKEN = process.env.APIFY_TOKEN || '';
const ACTOR_ID = 'apify~instagram-profile-scraper';

// Sample insurance agent usernames to test with
// In real usage, these would come from your manual research or other sources
const SAMPLE_USERNAMES = [
  'allstate',
  'statefarm', 
  'progressive',
  'geico',
  'nationwide',
  'farmersinsurance',
  'libertymutual',
  'travelers',
  'aflac',
  'metlife'
];

/**
 * Make HTTPS request to Apify API
 */
function apifyRequest(endpoint, method = 'GET', data = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(endpoint, 'https://api.apify.com');
    
    const options = {
      hostname: url.hostname,
      path: url.pathname + url.search,
      method: method,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      }
    };

    if (data) {
      options.headers['Content-Length'] = Buffer.byteLength(JSON.stringify(data));
    }

    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(body);
          if (res.statusCode >= 200 && res.statusCode < 300) {
            resolve(json);
          } else {
            reject(new Error(`HTTP ${res.statusCode}: ${json.error?.message || body}`));
          }
        } catch (e) {
          reject(new Error(`Invalid JSON: ${body}`));
        }
      });
    });

    req.on('error', reject);
    req.setTimeout(30000, () => reject(new Error('Request timeout')));

    if (data) {
      req.write(JSON.stringify(data));
    }
    req.end();
  });
}

/**
 * Run the Instagram Profile scraper
 */
async function runProfileScraper(usernames) {
  console.log('🚀 Starting Apify Instagram Profile Scraper...');
  console.log(`   Usernames to scrape: ${usernames.length}`);
  console.log('');

  // Build input for Instagram Profile Scraper
  const runInput = {
    usernames: usernames,
    proxy: {
      useApifyProxy: true,
      apifyProxyGroups: ['RESIDENTIAL']
    }
  };

  console.log('⏳ Starting scraper...');

  // Start the actor run
  const run = await apifyRequest(
    `/v2/acts/${ACTOR_ID}/runs?token=${APIFY_TOKEN}`,
    'POST',
    runInput
  );

  const runId = run.data.id;
  const defaultDatasetId = run.data.defaultDatasetId;
  
  console.log(`   Run ID: ${runId}`);
  console.log('   Waiting for completion...');

  // Poll for completion (max 5 minutes)
  const maxWait = 5 * 60 * 1000;
  const pollInterval = 5000;
  const startTime = Date.now();

  while (Date.now() - startTime < maxWait) {
    await new Promise(r => setTimeout(r, pollInterval));
    
    try {
      const status = await apifyRequest(
        `/v2/actor-runs/${runId}?token=${APIFY_TOKEN}`
      );

      const state = status.data.status;

      if (state === 'SUCCEEDED') {
        console.log('   ✅ Scraper completed!');
        return { runId, datasetId: defaultDatasetId };
      }
      
      if (['FAILED', 'ABORTED', 'TIMED_OUT'].includes(state)) {
        console.log(`   ⚠️ Scraper ended with: ${state}`);
        return { runId, datasetId: defaultDatasetId, partial: true };
      }
      
      process.stdout.write('.');
    } catch (e) {
      // Continue polling
    }
  }

  console.log('   ⏱️ Timeout - fetching partial results');
  return { runId, datasetId: defaultDatasetId, partial: true };
}

/**
 * Fetch dataset items from Apify
 */
async function fetchDatasetItems(datasetId, limit = 100) {
  console.log(`\n📥 Fetching results...`);
  
  const response = await apifyRequest(
    `/v2/datasets/${datasetId}/items?token=${APIFY_TOKEN}&limit=${limit}`
  );

  return response.data || [];
}

/**
 * Extract profile data from results
 * Field names based on actual Apify Instagram Profile Scraper output
 */
function extractProfiles(items) {
  const profiles = [];

  for (const item of items) {
    if (!item.username) continue;

    profiles.push({
      username: item.username,
      url: `https://instagram.com/${item.username}`,
      fullName: item.fullName || '',
      biography: item.biography || '',
      followersCount: item.followersCount || 0,
      followingCount: item.followsCount || 0,  // Note: API uses followsCount
      postsCount: item.postsCount || 0,
      externalUrl: item.externalUrl || '',
      isBusinessAccount: item.isBusinessAccount || false,
      isVerified: item.verified || false,  // Note: API uses verified
      isPrivate: item.private || false,  // Note: API uses private
      profilePicUrl: item.profilePicUrl || ''
    });
  }

  return profiles;
}

/**
 * Filter leads by insurance-related keywords
 */
function filterInsuranceLeads(profiles) {
  const insuranceKeywords = [
    'insurance', 'agent', 'broker', 'final expense', 'life insurance',
    'health insurance', 'financial', 'advisor', 'consultant', 'underwriter',
    'allstate', 'state farm', 'progressive', 'geico', 'nationwide'
  ];

  return profiles.filter(profile => {
    const bio = (profile.biography || '').toLowerCase();
    const name = (profile.fullName || '').toLowerCase();
    const combined = `${bio} ${name} ${profile.username}`;
    return insuranceKeywords.some(keyword => combined.includes(keyword.toLowerCase()));
  });
}

/**
 * Format leads for CSV output
 */
function formatLeadsForCSV(profiles) {
  const headers = ['username', 'profile_url', 'full_name', 'bio', 'followers', 'following', 'posts', 'website', 'is_business', 'is_verified', 'scraped_at'];
  
  const escapeCsv = (text) => {
    if (text === null || text === undefined) return '';
    const str = String(text).replace(/"/g, '""');
    return str.includes(',') || str.includes('\n') || str.includes('"') ? `"${str}"` : str;
  };

  const rows = profiles.map(p => [
    p.username,
    p.url,
    p.fullName,
    p.biography,
    p.followersCount,
    p.followingCount,
    p.postsCount,
    p.externalUrl,
    p.isBusinessAccount,
    p.isVerified,
    new Date().toISOString()
  ]);

  const csvContent = [
    headers.join(','),
    ...rows.map(row => row.map(escapeCsv).join(','))
  ].join('\n');

  return csvContent;
}

/**
 * Save leads to file
 */
function saveLeadsToFile(csvContent, filename) {
  const outputDir = path.join(process.cwd(), 'leads');
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  const filepath = path.join(outputDir, filename);
  fs.writeFileSync(filepath, csvContent);
  return filepath;
}

/**
 * Load usernames from file if provided
 */
function loadUsernames(args) {
  // Check if a file was provided
  const fileArg = args.find(arg => arg.endsWith('.txt') || arg.endsWith('.json'));
  
  if (fileArg && fs.existsSync(fileArg)) {
    console.log(`📁 Loading usernames from ${fileArg}`);
    const content = fs.readFileSync(fileArg, 'utf-8');
    
    if (fileArg.endsWith('.json')) {
      const data = JSON.parse(content);
      return Array.isArray(data) ? data : data.usernames || [];
    } else {
      return content.split('\n').map(l => l.trim()).filter(l => l && !l.startsWith('#'));
    }
  }
  
  return SAMPLE_USERNAMES;
}

/**
 * Main execution
 */
async function main() {
  const args = process.argv.slice(2);
  const outputOnly = args.includes('--output-only');
  
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('📸 Instagram Lead Scraper (Apify)');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('');
  console.log('⚠️  NOTE: Instagram blocks hashtag scraping without login.');
  console.log('   This tool scrapes profiles by username instead.');
  console.log('   To find usernames, use manual research or other tools.');
  console.log('');

  const usernames = loadUsernames(args);
  
  if (usernames.length === 0) {
    console.log('❌ No usernames to scrape. Add usernames to a .txt file');
    console.log('   (one per line) and pass the file path as an argument.');
    return { success: false, error: 'No usernames provided' };
  }

  console.log(`📋 Scraping ${usernames.length} profiles`);
  console.log('');

  try {
    // Run scraper
    const { datasetId, partial } = await runProfileScraper(usernames);

    // Fetch results
    const items = await fetchDatasetItems(datasetId, usernames.length);
    console.log(`   Profiles scraped: ${items.length}`);

    // Extract profiles
    const profiles = extractProfiles(items);

    // Filter for insurance leads
    const insuranceLeads = filterInsuranceLeads(profiles);
    console.log(`   Insurance leads: ${insuranceLeads.length}`);

    // Format and save
    const csvContent = formatLeadsForCSV(insuranceLeads);
    const timestamp = new Date().toISOString().split('T')[0];
    const filename = `apify-leads-${timestamp}-${insuranceLeads.length}.csv`;
    const filepath = saveLeadsToFile(csvContent, filename);

    // Output results
    console.log('');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log(partial ? '⚠️  PARTIAL RESULTS' : '✅ SCRAPE COMPLETE');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log(`   Total leads: ${insuranceLeads.length}`);
    console.log(`   File: ${filepath}`);
    console.log('');

    // Sample output
    if (insuranceLeads.length > 0) {
      console.log('📝 Sample leads:');
      insuranceLeads.slice(0, 3).forEach((lead, i) => {
        console.log(`   ${i + 1}. @${lead.username}`);
        if (lead.fullName) console.log(`      Name: ${lead.fullName}`);
        if (lead.biography) console.log(`      Bio: ${lead.biography.substring(0, 60)}...`);
      });
    }

    if (outputOnly) {
      console.log('\n---JSON_OUTPUT---');
      console.log(JSON.stringify({
        success: true,
        count: insuranceLeads.length,
        file: filepath,
        leads: insuranceLeads.slice(0, 5)
      }));
    }

    return { success: true, count: insuranceLeads.length, file: filepath };

  } catch (error) {
    console.error('');
    console.error('❌ ERROR:', error.message);
    
    if (outputOnly) {
      console.log('\n---JSON_OUTPUT---');
      console.log(JSON.stringify({
        success: false,
        error: error.message
      }));
    }

    return { success: false, error: error.message, count: 0 };
  }
}

// Run if called directly
if (require.main === module) {
  main().then(result => {
    process.exit(result.success ? 0 : 1);
  });
}

module.exports = { runProfileScraper, fetchDatasetItems, extractProfiles, filterInsuranceLeads };
