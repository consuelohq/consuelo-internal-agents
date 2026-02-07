#!/usr/bin/env tsx
/**
 * Reddit Scraper using Playwright
 * Tests if Playwright can bypass bot detection better than agent-browser
 */

import { chromium, Browser, Page } from 'playwright';

const REDDIT_URL = 'https://www.reddit.com/r/vibecoding/comments/1pmgqtn/december_2025_guide_to_popular_ai_coding_agents/';

async function scrapeReddit() {
  console.log('🎭 Starting Playwright Reddit scrape...\n');
  
  let browser: Browser | null = null;
  
  try {
    // Launch with stealth options
    browser = await chromium.launch({
      headless: true,
    });
    
    const context = await browser.newContext({
      userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      viewport: { width: 1920, height: 1080 },
      locale: 'en-US',
      timezoneId: 'America/New_York',
    });
    
    const page = await context.newPage();
    
    // Navigate to Reddit
    console.log(`📄 Loading: ${REDDIT_URL}`);
    await page.goto(REDDIT_URL, { waitUntil: 'networkidle', timeout: 30000 });
    
    // Wait for content to load
    await page.waitForTimeout(3000);
    
    // Get page title
    const title = await page.title();
    console.log(`✅ Page loaded: ${title}\n`);
    
    // Extract post content
    const postData = await page.evaluate(() => {
      const data: any = {
        title: '',
        author: '',
        content: '',
        comments: [] as any[],
      };
      
      // Try to get post title
      const titleEl = document.querySelector('h1') || 
                      document.querySelector('[data-testid="post-title"]') ||
                      document.querySelector('.Post h1');
      if (titleEl) data.title = titleEl.textContent?.trim() || '';
      
      // Try to get author
      const authorEl = document.querySelector('a[href^="/u/"]') ||
                       document.querySelector('[data-testid="post-author-link"]');
      if (authorEl) data.author = authorEl.textContent?.trim() || '';
      
      // Try to get post content
      const contentEl = document.querySelector('[data-testid="post-content"]') ||
                        document.querySelector('.Post div[data-click-id="text"]');
      if (contentEl) data.content = contentEl.textContent?.trim() || '';
      
      // Try to get comments
      const commentEls = document.querySelectorAll('[data-testid="comment"]');
      commentEls.forEach((el, i) => {
        if (i < 5) { // First 5 comments
          const author = el.querySelector('a[href^="/u/"]')?.textContent?.trim();
          const text = el.querySelector('[data-testid="comment-content"]')?.textContent?.trim();
          if (text) {
            data.comments.push({ author: author || 'unknown', text: text.substring(0, 200) });
          }
        }
      });
      
      return data;
    });
    
    console.log('📊 Extracted Data:\n');
    console.log(JSON.stringify(postData, null, 2));
    
    // Also get full page text for debugging
    const pageText = await page.evaluate(() => document.body.innerText.substring(0, 3000));
    console.log('\n📝 Page text preview:\n', pageText.substring(0, 1000));
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    if (browser) await browser.close();
    console.log('\n🔒 Browser closed');
  }
}

scrapeReddit();
