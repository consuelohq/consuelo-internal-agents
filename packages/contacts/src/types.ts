// @consuelo/contacts — types

export interface ContactsConfig {
  storage?: "mongodb" | "sqlite" | "memory";
  connectionString?: string;
}

export interface Contact {
  id: string;
  firstName: string;
  lastName: string;
  phone: string; // E.164 format
  email?: string;
  company?: string;
  tags?: string[];
  customFields?: Record<string, string>;
  createdAt: Date;
  updatedAt: Date;
}

export interface Queue {
  id: string;
  name: string;
  contacts: string[]; // contact IDs
  ordering: "round-robin" | "priority" | "custom";
  currentIndex: number;
}

export interface StorageProvider {
  create(contact: Omit<Contact, "id" | "createdAt" | "updatedAt">): Promise<Contact>;
  get(id: string): Promise<Contact | null>;
  update(id: string, data: Partial<Contact>): Promise<Contact>;
  delete(id: string): Promise<void>;
  search(query: string): Promise<Contact[]>;
  importCsv(csv: string): Promise<Contact[]>;
}
