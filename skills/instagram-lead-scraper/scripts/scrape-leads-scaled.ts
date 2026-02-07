#!/usr/bin/env tsx
/**
 * SCALED Instagram Lead Scraper
 * Multi-source scraping: Web Search (Brave + Exa) + Agent Browser
 * Target: 50-100+ leads per run with intelligent rotation
 */

// Dynamic import for DB to handle path issues
let db: any;
let leads: any;

async function initDb() {
  if (!db) {
    const dbModule = await import('/Users/kokayi/.openclaw/workspace/db/db.js');
    const schemaModule = await import('/Users/kokayi/.openclaw/workspace/db/schema.js');
    db = dbModule.db;
    leads = schemaModule.leads;
  }
  return { db, leads };
}
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { fileURLToPath } from 'url';
import { execSync } from 'child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ============================================
// CONFIGURATION
// ============================================

const CONFIG = {
  // Rate limiting (seconds between API calls)
  DELAY_BETWEEN_SEARCHES: 3,
  DELAY_BETWEEN_BATCHES: 10,
  
  // Batch sizes
  RESULTS_PER_SEARCH: 20,
  BATCH_SIZE: 10, // Database batch size
  
  // Search providers
  PROVIDERS: ['brave', 'exa'],
  
  // Output
  SAVE_TO_CSV: true,
  UPLOAD_TO_DRIVE: true,
  DRIVE_FOLDER_ID: '1Gi-Ny3pzvkz3NbBevWSM0PyZlBo8VQZ8',
};

// ============================================
// EXPANDED SEARCH TERM LIBRARY (80+ terms)
// ============================================

const SEARCH_CATEGORIES = {
  // Core insurance terms
  core: [
    'site:instagram.com insurance agent',
    'site:instagram.com "insurance agent" "life insurance"',
    'site:instagram.com insurance broker',
    'site:instagram.com licensed insurance agent',
    'site:instagram.com independent insurance agent',
    'site:instagram.com insurance professional',
  ],
  
  // Final expense specific
  finalExpense: [
    'site:instagram.com "final expense" agent',
    'site:instagram.com "final expense" insurance',
    'site:instagram.com burial insurance agent',
    'site:instagram.com "final expense" broker',
    'site:instagram.com final expense sales',
    'site:instagram.com final expense leads',
  ],
  
  // Life insurance
  lifeInsurance: [
    'site:instagram.com life insurance agent',
    'site:instagram.com life insurance broker',
    'site:instagram.com "life insurance" sales',
    'site:instagram.com life insurance professional',
    'site:instagram.com term life insurance agent',
    'site:instagram.com whole life insurance agent',
  ],
  
  // Medicare/Health
  medicare: [
    'site:instagram.com medicare agent',
    'site:instagram.com medicare broker',
    'site:instagram.com medicare supplement agent',
    'site:instagram.com "medicare advantage" agent',
    'site:instagram.com health insurance agent',
    'site:instagram.com health insurance broker',
  ],
  
  // Major carriers
  carriers: [
    'site:instagram.com state farm agent',
    'site:instagram.com allstate agent',
    'site:instagram.com farmers insurance agent',
    'site:instagram.com progressive agent',
    'site:instagram.com "new york life" agent',
    'site:instagram.com "northwestern mutual" agent',
    'site:instagram.com "liberty mutual" agent',
    'site:instagram.com aflac agent',
    'site:instagram.com mutual of omaha agent',
    'site:instagram.com primerica agent',
  ],
  
  // Sales/Motivation angle
  sales: [
    'site:instagram.com insurance sales',
    'site:instagram.com insurance sales coach',
    'site:instagram.com "agents helping agents"',
    'site:instagram.com insurance agency owner',
    'site:instagram.com building insurance agency',
    'site:instagram.com insurance entrepreneur',
  ],
  
  // Geographic (rotates states)
  geographic: [
    'site:instagram.com insurance agent texas',
    'site:instagram.com insurance agent florida',
    'site:instagram.com insurance agent california',
    'site:instagram.com insurance agent georgia',
    'site:instagram.com insurance agent ohio',
    'site:instagram.com insurance agent north carolina',
    'site:instagram.com insurance agent illinois',
    'site:instagram.com insurance agent michigan',
    'site:instagram.com insurance agent arizona',
    'site:instagram.com insurance agent pennsylvania',
    'site:instagram.com insurance agent tennessee',
    'site:instagram.com insurance agent indiana',
    'site:instagram.com insurance agent missouri',
    'site:instagram.com insurance agent maryland',
    'site:instagram.com insurance agent wisconsin',
  ],
  
  // Niche/Specific
  niche: [
    'site:instagram.com annuity agent',
    'site:instagram.com retirement planning insurance',
    'site:instagram.com "mortgage protection" insurance',
    'site:instagram.com indexed universal life agent',
    'site:instagram.com insurance marketing',
    'site:instagram.com insurance lead generation',
  ],
};

// Flatten all search terms
const ALL_SEARCH_TERMS = Object.values(SEARCH_CATEGORIES).flat();

// ============================================
// STATE TRACKING
// ============================================

interface ScrapeState {
  runId: string;
  startTime: string;
  targetCount: number;
  leadsFound: number;
  leadsSaved: number;
  searchesRun: number;
  termsUsed: string[];
  providersUsed: string[];
  errors: string[];
  csvFiles: string[];
}

function initState(targetCount: number): ScrapeState {
  return {
    runId: `run-${Date.now()}`,
    startTime: new Date().toISOString(),
    targetCount,
    leadsFound: 0,
    leadsSaved: 0,
    searchesRun: 0,
    termsUsed: [],
    providersUsed: [],
    errors: [],
    csvFiles: [],
  };
}

function saveState(state: ScrapeState) {
  const stateDir = path.join(__dirname, '..', 'state');
  if (!fs.existsSync(stateDir)) {
    fs.mkdirSync(stateDir, { recursive: true });
  }
  
  const stateFile = path.join(stateDir, `${state.runId}.json`);
  fs.writeFileSync(stateFile, JSON.stringify(state, null, 2));
  return stateFile;
}

// ============================================
// UTILITY FUNCTIONS
// ============================================

function sleep(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function createHash(source: string, externalId: string): string {
  return crypto
    .createHash('md5')
    .update(`${source}:${externalId}`.toLowerCase())
    .digest('hex');
}

function shuffle<T>(array: T[]): T[] {
  const result = [...array];
  for (let i = result.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [result[i], result[j]] = [result[j], result[i]];
  }
  return result;
}

function extractUsername(url: string): string | null {
  const match = url.match(/instagram\.com\/([^\/\?]+)/);
  return match ? match[1].toLowerCase() : null;
}

function extractFollowers(text: string): number | null {
  const match = text.match(/([\d,]+)\s*(?:followers|Followers)/);
  if (match) {
    return parseInt(match[1].replace(/,/g, ''));
  }
  
  // Try K/M format
  const kmMatch = text.match(/([\d.]+)\s*([KM])\s*(?:followers|Followers)/i);
  if (kmMatch) {
    const num = parseFloat(kmMatch[1]);
    const multiplier = kmMatch[2].toUpperCase() === 'M' ? 1000000 : 1000;
    return Math.floor(num * multiplier);
  }
  
  return null;
}

function isInsuranceAgentProfile(text: string, title: string): boolean {
  const lower = (text + ' ' + title).toLowerCase();
  const indicators = [
    'insurance agent', 'insurance broker', 'life insurance',
    'final expense', 'health insurance', 'licensed agent',
    'state farm', 'allstate', 'farmers insurance', 'progressive',
    'new york life', 'northwestern mutual', 'prudential',
    'liberty mutual', 'aflac', 'mutual of omaha',
    'help families', 'protect families', 'financial advisor',
    'medicare', 'burial insurance', 'annuity',
    'insurance sales', 'insurance professional'
  ];
  return indicators.some(i => lower.includes(i));
}

function isCorporateAccount(username: string): boolean {
  const corporate = [
    'statefarm', 'allstate', 'progressive', 'farmers', 
    'libertymutual', 'nationwide', 'geico', 'aflac',
    'newyorklife', 'prudential', 'metlife', 'guardianlife',
    'northwesternmutual', 'massmutual', 'primerica',
    'p', 'reel', 'stories', 'explore', 'accounts', 'about', 'help'
  ];
  return corporate.includes(username.toLowerCase());
}

// ============================================
// DATABASE OPERATIONS
// ============================================

async function getExistingUsernames(): Promise<Set<string>> {
  const { db, leads } = await initDb();
  const existing = await db.query.leads.findMany({
    where: (leads, { eq }) => eq(leads.source, 'instagram'),
    columns: { externalId: true }
  });
  return new Set(existing.map(l => l.externalId?.toLowerCase()).filter(Boolean));
}

async function saveToDatabase(leadsData: any[], batchId: string): Promise<any[]> {
  const { db, leads } = await initDb();
  const saved = [];
  
  for (let i = 0; i < leadsData.length; i += CONFIG.BATCH_SIZE) {
    const batch = leadsData.slice(i, i + CONFIG.BATCH_SIZE);
    
    for (const lead of batch) {
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
          niche: lead.niche || 'final_expense',
          scrapedDate: lead.scrapedDate,
          hash: hash,
          status: 'new',
          metadata: JSON.stringify(lead.metadata || {})
        });
        
        saved.push(lead);
      } catch (e: any) {
        if (!e.message?.includes('UNIQUE constraint')) {
          console.error(`  ✗ error saving ${lead.username}:`, e.message);
        }
      }
    }
    
    // Progress indicator for large batches
    if (leadsData.length > 20) {
      process.stdout.write(`  💾 saved ${saved.length}/${leadsData.length}...\r`);
    }
  }
  
  if (leadsData.length > 20) {
    console.log(`  💾 saved ${saved.length}/${leadsData.length} to database    `);
  } else {
    console.log(`  💾 saved ${saved.length} leads to database`);
  }
  
  return saved;
}

async function getDatabaseStats() {
  const { db } = await initDb();
  const stats = db.$client.prepare(`
    SELECT source, COUNT(*) as count 
    FROM leads 
    GROUP BY source
  `).all();
  
  const total = db.$client.prepare('SELECT COUNT(*) as count FROM leads').get();
  
  return { stats, total: total.count };
}

// ============================================
// SEARCH PROVIDERS
// ============================================

interface SearchResult {
  url: string;
  title: string;
  description: string;
  snippet?: string;
}

async function searchBrave(query: string, count: number = CONFIG.RESULTS_PER_SEARCH): Promise<SearchResult[]> {
  try {
    // Load API key from config
    const configPath = '/Users/kokayi/.openclaw/openclaw.json';
    const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    const apiKey = config.tools?.web?.search?.apiKey;
    
    if (!apiKey) {
      throw new Error('Brave API key not found in config');
    }
    
    const url = new URL('https://api.search.brave.com/res/v1/web/search');
    url.searchParams.set('q', query);
    url.searchParams.set('count', Math.min(count, 20).toString());
    url.searchParams.set('offset', '0');
    url.searchParams.set('mkt', 'en-US');
    
    const response = await fetch(url.toString(), {
      headers: {
        'Accept': 'application/json',
        'Accept-Encoding': 'gzip',
        'X-Subscription-Token': apiKey
      }
    });
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }
    
    const data = await response.json();
    
    return (data.web?.results || []).map((r: any) => ({
      url: r.url,
      title: r.title,
      description: r.description,
      snippet: r.description
    }));
  } catch (e: any) {
    console.error(`  ⚠️ Brave search failed:`, e.message);
    return [];
  }
}

async function searchExa(query: string, count: number = CONFIG.RESULTS_PER_SEARCH): Promise<SearchResult[]> {
  try {
    // Try to use exa-search skill if available
    const cmd = `cd /Users/kokayi/.openclaw/workspace && openclaw tools web_search "${query.replace(/"/g, '\\"')}" --count ${count} --json`;
    const result = execSync(cmd, { encoding: 'utf8', timeout: 30000 });
    const data = JSON.parse(result);
    
    return (data.results || []).map((r: any) => ({
      url: r.url,
      title: r.title,
      description: r.text || r.description,
      snippet: r.text
    }));
  } catch (e: any) {
    return []; // Exa might not be configured
  }
}

async function runSearch(provider: string, query: string): Promise<SearchResult[]> {
  switch (provider) {
    case 'brave':
      return searchBrave(query);
    case 'exa':
      return searchExa(query);
    default:
      return searchBrave(query);
  }
}

// ============================================
// LEAD EXTRACTION
// ============================================

interface Lead {
  username: string;
  profileUrl: string;
  fullName: string | null;
  bio: string | null;
  followers: number | null;
  location: string | null;
  scrapedDate: string;
  niche: string;
  metadata: any;
}

function extractLeadsFromResults(results: SearchResult[], existingUsernames: Set<string>): Lead[] {
  const newLeads: Lead[] = [];
  
  for (const result of results) {
    const url = result.url;
    if (!url || !url.includes('instagram.com')) continue;
    
    const username = extractUsername(url);
    if (!username) continue;
    
    // Skip if already in database
    if (existingUsernames.has(username)) continue;
    
    // Skip corporate accounts
    if (isCorporateAccount(username)) continue;
    
    // Skip invalid usernames
    if (username.includes('/') || username.includes('?') || username.length < 2) continue;
    
    // Check if it looks like an agent profile
    const text = `${result.title || ''} ${result.description || ''}`;
    if (!isInsuranceAgentProfile(text, result.title || '')) continue;
    
    // Determine niche
    let niche = 'general';
    const lowerText = text.toLowerCase();
    if (lowerText.includes('final expense') || lowerText.includes('burial')) {
      niche = 'final_expense';
    } else if (lowerText.includes('medicare')) {
      niche = 'medicare';
    } else if (lowerText.includes('life insurance')) {
      niche = 'life_insurance';
    }
    
    const lead: Lead = {
      username,
      profileUrl: `https://instagram.com/${username}`,
      fullName: result.title?.split('•')[0]?.trim() || null,
      bio: result.description || null,
      followers: extractFollowers(text),
      location: null, // Would need to visit page
      scrapedDate: new Date().toISOString().split('T')[0],
      niche,
      metadata: {
        sourceTitle: result.title,
        searchSnippet: result.snippet
      }
    };
    
    newLeads.push(lead);
    existingUsernames.add(username); // Prevent duplicates in same batch
  }
  
  return newLeads;
}

// ============================================
// CSV & DRIVE OPERATIONS
// ============================================

function saveToCSV(leadsData: Lead[], filename: string): string {
  const leadsDir = path.join(__dirname, '..', '..', '..', 'leads');
  if (!fs.existsSync(leadsDir)) {
    fs.mkdirSync(leadsDir, { recursive: true });
  }
  
  const filePath = path.join(leadsDir, filename);
  const headers = ['username', 'profile_url', 'full_name', 'bio', 'followers', 'location', 'niche', 'scraped_date'];
  
  const lines = leadsData.map(l => [
    l.username,
    l.profileUrl,
    `"${(l.fullName || '').replace(/"/g, '""')}"`,
    `"${(l.bio || '').replace(/"/g, '""')}"`,
    l.followers || '',
    l.location || '',
    l.niche,
    l.scrapedDate
  ].join(','));
  
  fs.writeFileSync(filePath, headers.join(',') + '\n' + lines.join('\n'));
  return filePath;
}

function uploadToDrive(filePath: string, folderId: string = CONFIG.DRIVE_FOLDER_ID): boolean {
  try {
    execSync(`gog drive upload "${filePath}" --parent ${folderId}`, {
      timeout: 60000,
      stdio: 'pipe'
    });
    return true;
  } catch (e) {
    return false;
  }
}

// ============================================
// MAIN SCRAPING ENGINE
// ============================================

export async function scrapeInstagramLeadsScaled(
  targetCount: number = 50,
  options: {
    useBrave?: boolean;
    useExa?: boolean;
    saveCsv?: boolean;
    uploadDrive?: boolean;
    categoryFilter?: string[];
  } = {}
): Promise<{
  leadsFound: number;
  leadsSaved: number;
  searchesRun: number;
  csvFile: string | null;
  duration: number;
}> {
  
  const startTime = Date.now();
  const state = initState(targetCount);
  
  console.log(`\n🚀 STARTING SCALED INSTAGRAM LEAD SCRAPER`);
  console.log(`   Target: ${targetCount} leads`);
  console.log(`   Run ID: ${state.runId}\n`);
  
  // Get existing usernames
  const existingUsernames = await getExistingUsernames();
  console.log(`📊 Existing Instagram leads in DB: ${existingUsernames.size}`);
  
  // Select search terms based on options
  let searchTerms = ALL_SEARCH_TERMS;
  if (options.categoryFilter) {
    searchTerms = options.categoryFilter.flatMap(cat => SEARCH_CATEGORIES[cat] || []);
  }
  
  // Shuffle for variety
  searchTerms = shuffle(searchTerms);
  
  // Select providers
  const providers = [];
  if (options.useBrave !== false) providers.push('brave');
  if (options.useExa) providers.push('exa');
  if (providers.length === 0) providers.push('brave');
  
  state.providersUsed = providers;
  
  const allNewLeads: Lead[] = [];
  let consecutiveEmpty = 0;
  const MAX_EMPTY = 5; // Stop after 5 empty searches
  
  // Main scraping loop
  for (const provider of providers) {
    console.log(`\n🔍 Using provider: ${provider.toUpperCase()}`);
    
    for (const term of searchTerms) {
      if (allNewLeads.length >= targetCount) break;
      if (consecutiveEmpty >= MAX_EMPTY) {
        console.log(`\n⚠️ Stopping: ${MAX_EMPTY} consecutive empty searches`);
        break;
      }
      
      console.log(`\n🔎 [${state.searchesRun + 1}] ${term}`);
      state.searchesRun++;
      state.termsUsed.push(term);
      
      try {
        const results = await runSearch(provider, term);
        
        if (results.length === 0) {
          consecutiveEmpty++;
          console.log(`  ⚠️ No results`);
        } else {
          const newLeads = extractLeadsFromResults(results, existingUsernames);
          
          if (newLeads.length === 0) {
            consecutiveEmpty++;
            console.log(`  • No new leads (${results.length} results checked)`);
          } else {
            consecutiveEmpty = 0;
            console.log(`  ✓ Found ${newLeads.length} new leads`);
            allNewLeads.push(...newLeads);
            state.leadsFound = allNewLeads.length;
            
            // Progress update
            if (allNewLeads.length >= targetCount * 0.25) {
              console.log(`  📈 Progress: ${allNewLeads.length}/${targetCount}`);
            }
          }
        }
      } catch (e: any) {
        state.errors.push(`${term}: ${e.message}`);
        console.error(`  ✗ Error:`, e.message);
      }
      
      // Rate limiting
      if (allNewLeads.length < targetCount) {
        await sleep(CONFIG.DELAY_BETWEEN_SEARCHES * 1000);
      }
    }
    
    // Delay between providers
    if (provider !== providers[providers.length - 1]) {
      console.log(`\n⏳ Switching providers in ${CONFIG.DELAY_BETWEEN_BATCHES}s...`);
      await sleep(CONFIG.DELAY_BETWEEN_BATCHES * 1000);
    }
  }
  
  // Save to database
  console.log(`\n💾 Saving ${allNewLeads.length} leads to database...`);
  const batchId = `ig-${new Date().toISOString().split('T')[0]}-${state.runId}`;
  const saved = await saveToDatabase(allNewLeads, batchId);
  state.leadsSaved = saved.length;
  
  // Save to CSV
  let csvFile: string | null = null;
  if (saved.length > 0 && options.saveCsv !== false) {
    const filename = `instagram-leads-${new Date().toISOString().split('T')[0]}-${state.runId}.csv`;
    csvFile = saveToCSV(saved, filename);
    state.csvFiles.push(csvFile);
    console.log(`  📁 CSV: ${csvFile}`);
    
    // Upload to Drive
    if (options.uploadDrive !== false) {
      const uploaded = uploadToDrive(csvFile);
      console.log(`  ☁️  Drive: ${uploaded ? '✓ uploaded' : '✗ failed'}`);
    }
  }
  
  // Get final stats
  const { stats, total } = await getDatabaseStats();
  
  // Print summary
  const duration = Math.round((Date.now() - startTime) / 1000);
  console.log(`\n✅ SCRAPE COMPLETE`);
  console.log(`   Duration: ${Math.floor(duration / 60)}m ${duration % 60}s`);
  console.log(`   Searches: ${state.searchesRun}`);
  console.log(`   Leads Found: ${state.leadsFound}`);
  console.log(`   Leads Saved: ${state.leadsSaved}`);
  console.log(`\n📊 DATABASE TOTALS:`);
  stats.forEach((s: any) => console.log(`   - ${s.source}: ${s.count}`));
  console.log(`   - TOTAL: ${total}`);
  
  // Save state
  const stateFile = saveState(state);
  console.log(`\n💾 State saved: ${stateFile}`);
  
  return {
    leadsFound: state.leadsFound,
    leadsSaved: state.leadsSaved,
    searchesRun: state.searchesRun,
    csvFile,
    duration
  };
}

// ============================================
// CLI INTERFACE
// ============================================

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const target = parseInt(process.argv[2]) || 50;
  const useExa = process.argv.includes('--exa');
  const noCsv = process.argv.includes('--no-csv');
  const noDrive = process.argv.includes('--no-drive');
  
  scrapeInstagramLeadsScaled(target, {
    useExa,
    saveCsv: !noCsv,
    uploadDrive: !noDrive
  }).catch(err => {
    console.error('Fatal error:', err);
    process.exit(1);
  });
}
