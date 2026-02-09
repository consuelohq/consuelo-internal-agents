import { loadConfig } from '../config.js';
import { log, json, isJson } from '../output.js';

export async function statusCommand(): Promise<void> {
  const config = loadConfig();
  if (isJson()) {
    json({ configured: !!config.twilioAccountSid || !!config.managed, config });
  } else {
    if (config.managed) {
      log('mode: managed');
    } else if (config.twilioAccountSid) {
      log(`twilio: ${config.twilioAccountSid}`);
      log(`llm: ${config.llmProvider ?? 'groq'}`);
      log(`phone: ${config.twilioPhoneNumber ?? '(not set)'}`);
    } else {
      log('not configured — run `consuelo init`');
    }
  }
}
