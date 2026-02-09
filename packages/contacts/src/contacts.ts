import type { Contact, StorageProvider } from './types.js';
import { normalizePhone, parseCsv } from './utils.js';
import { MemoryProvider } from './providers/memory.js';

/**
 * Contacts — CRUD, search, and CSV import for sales contacts.
 */
export class Contacts {
  readonly store: StorageProvider;

  constructor(store?: StorageProvider) {
    this.store = store ?? new MemoryProvider();
  }

  async create(data: Omit<Contact, 'id' | 'createdAt' | 'updatedAt'>): Promise<Contact> {
    return this.store.createContact({ ...data, phone: normalizePhone(data.phone) });
  }

  async get(id: string): Promise<Contact | null> {
    return this.store.getContact(id);
  }

  async update(id: string, data: Partial<Contact>): Promise<Contact | null> {
    if (data.phone) data.phone = normalizePhone(data.phone);
    return this.store.updateContact(id, data);
  }

  async delete(id: string): Promise<boolean> {
    return this.store.deleteContact(id);
  }

  async search(query: string, userId?: string): Promise<Contact[]> {
    return this.store.searchContacts(query, userId);
  }

  async list(userId: string): Promise<Contact[]> {
    return this.store.listContacts(userId);
  }

  /** Bulk import contacts from a CSV string. Expects columns: name, phone, email, company */
  async importCsv(csv: string, userId?: string): Promise<Contact[]> {
    const rows = parseCsv(csv);
    const results: Contact[] = [];
    for (const row of rows) {
      if (!row.phone && !row.name) continue;
      const contact = await this.create({
        name: row.name ?? '',
        phone: row.phone ?? '',
        email: row.email,
        company: row.company,
        userId,
      });
      results.push(contact);
    }
    return results;
  }
}
