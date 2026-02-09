import { log, json, isJson } from '../output.js';

export async function analyticsCommand(callSid: string): Promise<void> {
  if (isJson()) {
    json({ callSid, status: 'pending' });
  } else {
    log(`fetching analytics for ${callSid}...`);
    log('(connect your analytics provider to generate real analytics)');
  }
}
