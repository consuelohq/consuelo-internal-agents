import * as readline from 'node:readline';
import { saveConfig } from '../config.js';
import { log } from '../output.js';
import type { CliConfig } from '../config.js';

function ask(rl: readline.Interface, question: string): Promise<string> {
  return new Promise((resolve) => rl.question(question, resolve));
}

export async function initCommand(opts: { managed?: boolean }): Promise<void> {
  if (opts.managed) {
    saveConfig({ managed: true });
    log('configured for managed mode — no credentials needed');
    return;
  }

  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const config: CliConfig = {};

  log('consuelo init — interactive setup\n');

  config.twilioAccountSid = await ask(rl, 'twilio account sid: ');
  config.twilioAuthToken = await ask(rl, 'twilio auth token: ');
  config.twilioPhoneNumber = await ask(rl, 'twilio phone number (E.164): ');

  const provider = await ask(rl, 'llm provider (groq/openai) [groq]: ');
  config.llmProvider = provider === 'openai' ? 'openai' : 'groq';
  config.llmApiKey = await ask(rl, `${config.llmProvider} api key: `);

  rl.close();

  saveConfig(config);
  log('\nconfig saved to ~/.consuelo/config.json');
}
