/** Contact record */
export interface Contact {
  id: string;
  name: string;
  phone: string; // E.164
  email?: string;
  company?: string;
  tags?: string[];
  customFields?: Record<string, string>;
  userId?: string;
  orgId?: string;
  createdAt: string;
  updatedAt: string;
}

/** Queue record */
export interface Queue {
  id: string;
  name: string;
  contactIds: string[];
  ordering: 'sequential' | 'round-robin' | 'priority';
  currentIndex: number;
  status: 'idle' | 'active' | 'paused' | 'completed';
  results: QueueResult[];
  createdAt: string;
}

export interface QueueResult {
  contactId: string;
  callSid?: string;
  outcome?: string;
  attemptedAt: string;
}

/** Storage provider interface — users supply their own persistence */
export interface StorageProvider {
  // Contacts
  createContact(contact: Omit<Contact, 'id' | 'createdAt' | 'updatedAt'>): Promise<Contact>;
  getContact(id: string): Promise<Contact | null>;
  updateContact(id: string, data: Partial<Contact>): Promise<Contact | null>;
  deleteContact(id: string): Promise<boolean>;
  searchContacts(query: string, userId?: string): Promise<Contact[]>;
  listContacts(userId: string): Promise<Contact[]>;

  // Queues
  createQueue(queue: Omit<Queue, 'id' | 'createdAt'>): Promise<Queue>;
  getQueue(id: string): Promise<Queue | null>;
  updateQueue(id: string, data: Partial<Queue>): Promise<Queue | null>;
}
