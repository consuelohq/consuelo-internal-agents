#!/usr/bin/env node

import { initCommand } from './commands/init.js';
import { callCommand } from './commands/call.js';
import { coachCommand } from './commands/coach.js';
import { contactsCommand } from './commands/contacts.js';
import { analyticsCommand } from './commands/analytics.js';
import { statusCommand } from './commands/status.js';

const args = process.argv.slice(2);
const flags = new Set(args.filter((a) => a.startsWith('--')));
const positional = args.filter((a) => !a.startsWith('--'));

if (flags.has('--json')) (globalThis as any).__consuelo_json = true;
if (flags.has('--quiet')) (globalThis as any).__consuelo_quiet = true;

const command = positional[0];

async function main() {
  switch (command) {
    case 'init':
      await initCommand({ managed: flags.has('--managed') });
      break;
    case 'call':
      await callCommand(positional[1] ?? '');
      break;
    case 'coach':
      await coachCommand({ transcript: flagValue('--transcript') });
      break;
    case 'contacts':
      await contactsCommand(positional[1] ?? 'list', positional.slice(2));
      break;
    case 'analytics':
      await analyticsCommand(positional[1] ?? '');
      break;
    case 'status':
      await statusCommand();
      break;
    default:
      console.log(`consuelo — AI-powered sales toolkit

commands:
  init                    interactive setup
  call <number>           make a call with AI coaching
  coach --transcript <f>  analyze a transcript
  contacts <action>       manage contacts (list|add|import)
  analytics <callSid>     get call analytics
  status                  show config and account status

flags:
  --json                  machine-readable output
  --quiet                 suppress output
  --managed               use hosted infrastructure`);
  }
}

function flagValue(flag: string): string | undefined {
  const idx = args.indexOf(flag);
  return idx >= 0 ? args[idx + 1] : undefined;
}

main().catch((err) => {
  console.error(`error: ${err.message}`);
  process.exit(1);
});
