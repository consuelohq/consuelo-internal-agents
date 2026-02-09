import { loadConfig } from '../config.js';
import { log, error, json, isJson } from '../output.js';

export async function callCommand(number: string): Promise<void> {
  const config = loadConfig();
  if (!config.twilioAccountSid && !config.managed) {
    error('not configured — run `consuelo init` first');
    process.exit(1);
  }
  if (isJson()) {
    json({ action: 'call', to: number, status: 'initiated' });
  } else {
    log(`calling ${number}...`);
    log('(connect your dialer implementation to make real calls)');
  }
}
