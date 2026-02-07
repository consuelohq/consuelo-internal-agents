#!/usr/bin/env tsx
/**
 * PURE AGENT-BROWSER Instagram Lead Scraper
 * Uses persistent session for efficient scraping
 */

import { db } from '../../../db/db.js';
import { leads } from '../../../db/schema.js';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { fileURLToPath } from 'url';
import { execSync, spawn } from 'child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ============================================
// CONFIGURATION
// ============================================

const CONFIG = {
  SESSION_NAME: 'instagram-scraper',
  DELAY_BETWEEN_PROFILES: 2,
  DELAY_BETWEEN_HASHTAGS: 3,
  PROFILES_PER_HASHTAG: 15,
  SAVE_TO_CSV: true,
  DRIVE_FOLDER_ID: '1Gi-Ny3pzvkz3NbBevWSM0PyZlBo8VQZ8',
};

const HASHTAGS = [
  'insuranceagent',
  'lifeinsuranceagent', 
  'finalexpense',
  'finalexpenseagent',
  'lifeinsurance',
  'insurancebroker',
  'medicareagent',
  'healthinsuranceagent',
  'insuranceagency',
  'insurancesales',
];

// ============================================
// DATABASE
// ============================================

async function initDb() {
  const dbModule = await import('/Users/kokayi/.openclaw/workspace/db/db.js');
  const schemaModule = await import('/Users/kokayi/.openclaw/workspace/db/schema.js');
  return { db: dbModule.db, leads: schemaModule.leads };
}

async function getExistingUsernames(): Promise<Set<string>> {
  const { db } = await initDb();
  const existing = await db.query.leads.findMany({
    where: (leads, { eq }) => eq(leads.source, 'instagram'),
    columns: { externalId: true }
  });
  return new Set(existing.map(l => l.externalId?.toLowerCase()).filter(Boolean));
}

function createHash(source: string, externalId: string): string {
  return crypto
    .createHash('md5')
    .update(`${source}:${externalId}`.toLowerCase())
    .digest('hex');
}

async function saveLead(lead: any): Promise<boolean> {
  const { db, leads } = await initDb();
  try {
    const hash = createHash('instagram', lead.username);
    
    await db.insert(leads).values({
      source: 'instagram',
      sourceType: 'profile',
      batchId: lead.batchId,
      externalId: lead.username,
      externalUrl: `https://instagram.com/${lead.username}`,
      fullName: lead.fullName,
      email: lead.email,
      phone: lead.phone,
      location: lead.location,
      bio: lead.bio,
      followers: lead.followers,
      following: lead.following,
      posts: lead.posts,
      leadType: lead.leadType || 'agent',
      niche: lead.niche || 'general',
      scrapedDate: new Date().toISOString().split('T')[0],
      hash: hash,
      status: 'new',
      notes: lead.notes || null,
      tags: lead.tags || null,
    });
    
    return true;
  } catch (e: any) {
    if (e.message?.includes('UNIQUE constraint')) {
      return false;
    }
    console.error(`  ✗ Error saving ${lead.username}:`, e.message);
    return false;
  }
}

// ============================================
// AGENT BROWSER - Persistent Session
// ============================================

function sleep(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function browserCommand(args: string[]): Promise<string> {
  try {
    const cmd = `agent-browser --session ${CONFIG.SESSION_NAME} ${args.join(' ')}`;
    return execSync(cmd, { 
      encoding: 'utf8', 
      timeout: 60000,
      stdio: ['pipe', 'pipe', 'pipe']
    });
  } catch (e: any) {
    return e.stdout || e.stderr || '';
  }
}

async function openHashtag(hashtag: string): Promise<string[]> {
  console.log(`\n🏷️  Scraping hashtag: #${hashtag}`);
  
  const url = `https://instagram.com/explore/tags/${hashtag}/`;
  await browserCommand(['open', url]);
  await sleep(2500);
  
  const snapshot = await browserCommand(['snapshot', '-c']);
  
  // Extract usernames from profile picture links
  const usernames: string[] = [];
  const seen = new Set<string>();
  
  const matches = snapshot.matchAll(/([^'"\s]+)'s profile picture/g);
  for (const match of matches) {
    const username = match[1].toLowerCase().trim();
    if (username && 
        !seen.has(username) &&
        username.length >= 3 &&
        username.length <= 30 &&
        !username.includes(' ') &&
        !username.includes('@') &&
        !['instagram', 'meta', 'about', 'help', 'privacy', 'terms'].includes(username)) {
      usernames.push(username);
      seen.add(username);
    }
  }
  
  return usernames;
}

function parseCount(countStr: string): number | null {
  if (!countStr) return null;
  const clean = countStr.replace(/,/g, '').toUpperCase();
  if (clean.includes('M')) {
    return Math.floor(parseFloat(clean) * 1000000);
  } else if (clean.includes('K')) {
    return Math.floor(parseFloat(clean) * 1000);
  }
  const num = parseInt(clean);
  return isNaN(num) ? null : num;
}

function extractEmail(text: string): string | null {
  const match = text.match(/([\w.-]+@[\w.-]+\.[A-Za-z]{2,})/);
  return match ? match[1] : null;
}

function extractPhone(text: string): string | null {
  const patterns = [
    /(?:\+?1[-.\s]?)?\(?([0-9]{3})\)?[-.\s]?([0-9]{3})[-.\s]?([0-9]{4})/,
    /\b(\d{3})[-.](\d{3})[-.](\d{4})\b/,
    /📞[:\s]*([\d\-+.\(\)\s]+)/,
    /☎️[:\s]*([\d\-+.\(\)\s]+)/,
    /(?:call|text|phone)[:\s]*([\d\-+.\(\)\s]{10,})/i,
  ];
  
  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (match) {
      // Format nicely
      const phone = match[0].replace(/[^\d]/g, '');
      if (phone.length >= 10) {
        return match[0].trim();
      }
    }
  }
  return null;
}

function extractLocation(text: string): string | null {
  const patterns = [
    /📍[:\s]*([^📞📧\n]+?)(?=📞|📧|$)/,
    /(?:in|serving|located in)[:\s]+([A-Z][a-zA-Z\s,]+(?:GA|FL|TX|CA|NY|NC|SC|TN|AL|MS|LA|VA|MD|OH|MI|IL|IN|MO|KY|WV|PA|NJ|DE|CT|RI|MA|VT|NH|ME|AZ|NV|UT|CO|NM|OK|AR|IA|MN|WI|KS|NE|SD|ND|MT|WY|ID|WA|OR|AK|HI|DC))/,  
    /(?:atlanta|georgia|florida|texas|california|new york|north carolina|arizona|nevada|colorado)\b/i,
  ];
  
  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (match) {
      return match[1] ? match[1].trim() : match[0].trim();
    }
  }
  return null;
}

function determineNiche(bio: string): string {
  const lower = bio.toLowerCase();
  if (lower.includes('final expense') || lower.includes('burial')) return 'final_expense';
  if (lower.includes('medicare')) return 'medicare';
  if (lower.includes('life insurance') && lower.includes('health')) return 'life_health';
  if (lower.includes('life insurance')) return 'life_insurance';
  if (lower.includes('health insurance')) return 'health_insurance';
  if (lower.includes('auto') && lower.includes('home')) return 'auto_home';
  if (lower.includes('commercial') || lower.includes('business')) return 'commercial';
  return 'general';
}

async function scrapeProfile(username: string): Promise<any | null> {
  try {
    const url = `https://instagram.com/${username}/`;
    await browserCommand(['open', url]);
    await sleep(2000);
    
    const snapshot = await browserCommand(['snapshot', '-c']);
    
    const data = {
      username,
      fullName: null as string | null,
      bio: null as string | null,
      followers: null as number | null,
      following: null as number | null,
      posts: null as number | null,
      email: null as string | null,
      phone: null as string | null,
      location: null as string | null,
      niche: 'general',
      tags: '',
      notes: '',
    };
    
    // Parse snapshot line by line
    const lines = snapshot.split('\n');
    let collectingBio = false;
    let bioLines: string[] = [];
    
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      
      // Full name from heading
      const headingMatch = line.match(/heading\s+"([^"]+)"/);
      if (headingMatch && !data.fullName && headingMatch[1] !== username) {
        data.fullName = headingMatch[1];
      }
      
      // Stats
      const postsMatch = line.match(/([\d,.]+[KM]?)\s+posts?/i);
      if (postsMatch) data.posts = parseCount(postsMatch[1]);
      
      const followersMatch = line.match(/([\d,.]+[KM]?)\s+followers?/i);
      if (followersMatch) data.followers = parseCount(followersMatch[1]);
      
      const followingMatch = line.match(/([\d,.]+[KM]?)\s+following?/i);
      if (followingMatch) data.following = parseCount(followingMatch[1]);
      
      // Bio text
      if (line.includes('text:') && !line.includes('posts') && !line.includes('followers')) {
        const textMatch = line.match(/text:\s*(.+)/);
        if (textMatch) {
          const text = textMatch[1].trim();
          if (text.length > 5) {
            bioLines.push(text);
          }
        }
      }
    }
    
    // Combine bio lines
    data.bio = bioLines.join(' ').substring(0, 500);
    
    // Skip if not insurance-related
    const bioLower = (data.bio || '').toLowerCase();
    const isInsurance = 
      bioLower.includes('insurance') ||
      bioLower.includes('agent') ||
      bioLower.includes('broker') ||
      bioLower.includes('state farm') ||
      bioLower.includes('allstate') ||
      bioLower.includes('farmers') ||
      bioLower.includes('financial') ||
      bioLower.includes('american family');
    
    if (!isInsurance) return null;
    
    // Extract contact info
    data.email = extractEmail(data.bio);
    data.phone = extractPhone(data.bio);
    data.location = extractLocation(data.bio);
    data.niche = determineNiche(data.bio);
    
    // Build tags
    const tags = [];
    if (data.email) tags.push('has-email');
    if (data.phone) tags.push('has-phone');
    if (data.location) tags.push('has-location');
    if (data.followers && data.followers > 5000) tags.push('high-followers');
    data.tags = tags.join(',');
    
    return data;
    
  } catch (e: any) {
    console.error(`  ✗ Error:`, e.message);
    return null;
  }
}

// ============================================
// CSV & DRIVE
// ============================================

function saveToCSV(leadsData: any[], filename: string): string {
  const leadsDir = path.join(__dirname, '..', '..', '..', 'leads');
  if (!fs.existsSync(leadsDir)) fs.mkdirSync(leadsDir, { recursive: true });
  
  const filePath = path.join(leadsDir, filename);
  const headers = [
    'username', 'full_name', 'bio', 'followers', 'following', 'posts',
    'email', 'phone', 'location', 'niche', 'tags', 'scraped_date'
  ];
  
  const lines = leadsData.map(l => [
    l.username,
    `"${(l.fullName || '').replace(/"/g, '""')}"`,
    `"${(l.bio || '').replace(/"/g, '""').substring(0, 200)}"`,
    l.followers || '',
    l.following || '',
    l.posts || '',
    l.email || '',
    l.phone || '',
    `"${(l.location || '').replace(/"/g, '""')}"`,
    l.niche,
    l.tags || '',
    new Date().toISOString().split('T')[0]
  ].join(','));
  
  fs.writeFileSync(filePath, headers.join(',') + '\n' + lines.join('\n'));
  return filePath;
}

function uploadToDrive(filePath: string): boolean {
  try {
    execSync(`gog drive upload "${filePath}" --parent ${CONFIG.DRIVE_FOLDER_ID}`, {
      timeout: 60000, stdio: 'pipe'
    });
    return true;
  } catch (e) { return false; }
}

// ============================================
// MAIN
// ============================================

export async function scrapeInstagramAgentBrowser(
  targetCount: number = 50,
  options: { skipDrive?: boolean } = {}
) {
  const startTime = Date.now();
  const runId = `ab-${Date.now()}`;
  
  console.log(`\n🤖 PURE AGENT-BROWSER INSTAGRAM SCRAPER`);
  console.log(`   Target: ${targetCount} leads`);
  console.log(`   Session: ${CONFIG.SESSION_NAME}\n`);
  
  // Close any existing session
  try {
    await browserCommand(['close']);
  } catch (e) {}
  
  const existingUsernames = await getExistingUsernames();
  console.log(`📊 Existing Instagram leads in DB: ${existingUsernames.size}`);
  
  const savedLeads: any[] = [];
  const seenProfiles = new Set<string>();
  let withEmail = 0, withPhone = 0;
  
  for (const hashtag of HASHTAGS) {
    if (savedLeads.length >= targetCount) break;
    
    const usernames = await openHashtag(hashtag);
    console.log(`   Found ${usernames.length} profiles`);
    
    let scraped = 0;
    for (const username of usernames) {
      if (savedLeads.length >= targetCount) break;
      if (seenProfiles.has(username)) continue;
      if (existingUsernames.has(username)) {
        console.log(`   • @${username} already in DB`);
        continue;
      }
      if (scraped >= CONFIG.PROFILES_PER_HASHTAG) break;
      
      seenProfiles.add(username);
      scraped++;
      
      process.stdout.write(`   🔍 @${username}... `);
      const profile = await scrapeProfile(username);
      
      if (profile) {
        profile.batchId = runId;
        const saved = await saveLead(profile);
        
        if (saved) {
          savedLeads.push(profile);
          if (profile.email) withEmail++;
          if (profile.phone) withPhone++;
          
          console.log(`✅ SAVED`);
          console.log(`      ${profile.fullName || 'N/A'} | ${profile.followers?.toLocaleString() || 'N/A'} followers`);
          if (profile.email) console.log(`      📧 ${profile.email}`);
          if (profile.phone) console.log(`      📞 ${profile.phone}`);
          if (profile.location) console.log(`      📍 ${profile.location}`);
        } else {
          console.log(`⚠️ exists`);
        }
      } else {
        console.log(`❌ not insurance`);
      }
      
      await sleep(CONFIG.DELAY_BETWEEN_PROFILES * 1000);
    }
    
    console.log(`   Progress: ${savedLeads.length}/${targetCount}`);
    await sleep(CONFIG.DELAY_BETWEEN_HASHTAGS * 1000);
  }
  
  // Cleanup
  try { await browserCommand(['close']); } catch (e) {}
  
  // Save CSV
  let csvFile: string | null = null;
  if (savedLeads.length > 0) {
    const filename = `ig-agentbrowser-${new Date().toISOString().split('T')[0]}-${runId}.csv`;
    csvFile = saveToCSV(savedLeads, filename);
    console.log(`\n📁 CSV: ${csvFile}`);
    
    if (!options.skipDrive) {
      console.log(`☁️  Drive: ${uploadToDrive(csvFile) ? '✓ uploaded' : '✗ failed'}`);
    }
  }
  
  const duration = Math.round((Date.now() - startTime) / 1000);
  console.log(`\n✅ COMPLETE: ${savedLeads.length} leads | ${withEmail} emails | ${withPhone} phones | ${Math.floor(duration/60)}m ${duration%60}s`);
  
  return { savedLeads, withEmail, withPhone, duration, csvFile };
}

// CLI
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const target = parseInt(process.argv[2]) || 50;
  const skipDrive = process.argv.includes('--no-drive');
  
  scrapeInstagramAgentBrowser(target, { skipDrive })
    .then(() => process.exit(0))
    .catch(err => { console.error('Fatal:', err); process.exit(1); });
}
