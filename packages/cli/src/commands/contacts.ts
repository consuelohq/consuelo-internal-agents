import { log, json, isJson } from '../output.js';

export async function contactsCommand(action: string, args: string[]): Promise<void> {
  switch (action) {
    case 'list':
      if (isJson()) json({ contacts: [] });
      else log('no contacts yet — use `consuelo contacts add` or `consuelo contacts import`');
      break;
    case 'add': {
      const name = args[0] ?? 'Unknown';
      const phone = args[1] ?? '';
      if (isJson()) json({ action: 'add', name, phone });
      else log(`added contact: ${name} ${phone}`);
      break;
    }
    case 'import': {
      const file = args[0];
      if (isJson()) json({ action: 'import', file });
      else log(`importing from ${file ?? '(no file)'}...`);
      break;
    }
    default:
      log('usage: consuelo contacts <list|add|import>');
  }
}
