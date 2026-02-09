import * as fs from 'node:fs';
import { log, error, json, isJson } from '../output.js';

export async function coachCommand(opts: { transcript?: string }): Promise<void> {
  if (!opts.transcript) {
    error('provide a transcript file: consuelo coach --transcript <file>');
    process.exit(1);
  }
  if (!fs.existsSync(opts.transcript)) {
    error(`file not found: ${opts.transcript}`);
    process.exit(1);
  }
  const content = fs.readFileSync(opts.transcript, 'utf-8');
  const lines = content.trim().split('\n').filter(Boolean);

  if (isJson()) {
    json({ action: 'coach', lines: lines.length, status: 'ready' });
  } else {
    log(`loaded ${lines.length} lines from ${opts.transcript}`);
    log('(connect your coaching provider to generate coaching tips)');
  }
}
