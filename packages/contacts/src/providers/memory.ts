import type { Contact, Queue, QueueResult, StorageProvider } from '../types.js';

/** In-memory storage provider — useful for testing and simple setups */
export class MemoryProvider implements StorageProvider {
  private contacts = new Map<string, Contact>();
  private queues = new Map<string, Queue>();
  private nextId = 1;

  private id(): string { return String(this.nextId++); }

  async createContact(data: Omit<Contact, 'id' | 'createdAt' | 'updatedAt'>): Promise<Contact> {
    const now = new Date().toISOString();
    const contact: Contact = { ...data, id: this.id(), createdAt: now, updatedAt: now };
    this.contacts.set(contact.id, contact);
    return contact;
  }

  async getContact(id: string): Promise<Contact | null> {
    return this.contacts.get(id) ?? null;
  }

  async updateContact(id: string, data: Partial<Contact>): Promise<Contact | null> {
    const existing = this.contacts.get(id);
    if (!existing) return null;
    const updated = { ...existing, ...data, id, updatedAt: new Date().toISOString() };
    this.contacts.set(id, updated);
    return updated;
  }

  async deleteContact(id: string): Promise<boolean> {
    return this.contacts.delete(id);
  }

  async searchContacts(query: string, userId?: string): Promise<Contact[]> {
    const q = query.toLowerCase();
    return [...this.contacts.values()].filter((c) => {
      if (userId && c.userId !== userId) return false;
      return c.name?.toLowerCase().includes(q) || c.phone?.includes(q) || c.email?.toLowerCase().includes(q);
    });
  }

  async listContacts(userId: string): Promise<Contact[]> {
    return [...this.contacts.values()].filter((c) => c.userId === userId);
  }

  async createQueue(data: Omit<Queue, 'id' | 'createdAt'>): Promise<Queue> {
    const queue: Queue = { ...data, id: this.id(), createdAt: new Date().toISOString() };
    this.queues.set(queue.id, queue);
    return queue;
  }

  async getQueue(id: string): Promise<Queue | null> {
    return this.queues.get(id) ?? null;
  }

  async updateQueue(id: string, data: Partial<Queue>): Promise<Queue | null> {
    const existing = this.queues.get(id);
    if (!existing) return null;
    const updated = { ...existing, ...data, id };
    this.queues.set(id, updated);
    return updated;
  }
}
