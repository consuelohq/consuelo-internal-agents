import * as crypto from 'node:crypto';

/** API key record */
export interface ApiKey {
  id: string;
  userId: string;
  prefix: string; // "sk_live_abc..." (first 12 chars)
  hash: string; // SHA-256 of full key
  mode: 'live' | 'test';
  scope: 'full' | 'readonly';
  name?: string;
  createdAt: string;
  revokedAt?: string;
}

/** Usage record */
export interface UsageRecord {
  id: string;
  apiKeyId: string;
  userId: string;
  type: 'call_minute' | 'coaching_request' | 'transcription_minute' | 'analytics_request';
  quantity: number;
  costCents: number;
  timestamp: string;
}

/** User balance */
export interface Balance {
  userId: string;
  balanceCents: number;
  spendLimitCents: number;
  autoTopUp: boolean;
  topUpAmountCents: number;
  topUpThresholdCents: number;
}

/** Usage query */
export interface UsageQuery {
  userId: string;
  startDate?: string;
  endDate?: string;
  type?: UsageRecord['type'];
}

/** Storage interface for metering data */
export interface MeteringStore {
  saveApiKey(key: ApiKey): Promise<void>;
  getApiKeyByHash(hash: string): Promise<ApiKey | null>;
  listApiKeys(userId: string): Promise<ApiKey[]>;
  revokeApiKey(id: string): Promise<void>;

  recordUsage(record: UsageRecord): Promise<void>;
  getUsage(query: UsageQuery): Promise<UsageRecord[]>;

  getBalance(userId: string): Promise<Balance | null>;
  updateBalance(userId: string, balanceCents: number): Promise<void>;
}

// Default cost per unit in cents
const COSTS: Record<UsageRecord['type'], number> = {
  call_minute: 3,          // $0.03/min
  coaching_request: 1,     // $0.01/request
  transcription_minute: 2, // $0.02/min
  analytics_request: 1,    // $0.01/request
};

/**
 * Metering — API key management, usage tracking, and balance management.
 */
export class Metering {
  constructor(private store: MeteringStore) {}

  /** Generate a new API key. Returns the full key (only shown once). */
  async createKey(userId: string, opts: { mode?: 'live' | 'test'; scope?: 'full' | 'readonly'; name?: string } = {}): Promise<{ key: string; record: ApiKey }> {
    const mode = opts.mode ?? 'live';
    const raw = crypto.randomBytes(24).toString('base64url');
    const fullKey = `sk_${mode}_${raw}`;
    const hash = crypto.createHash('sha256').update(fullKey).digest('hex');

    const record: ApiKey = {
      id: crypto.randomUUID(),
      userId,
      prefix: fullKey.slice(0, 12) + '...',
      hash,
      mode,
      scope: opts.scope ?? 'full',
      name: opts.name,
      createdAt: new Date().toISOString(),
    };

    await this.store.saveApiKey(record);
    return { key: fullKey, record };
  }

  /** Validate an API key. Returns the key record or null. */
  async validateKey(key: string): Promise<ApiKey | null> {
    const hash = crypto.createHash('sha256').update(key).digest('hex');
    const record = await this.store.getApiKeyByHash(hash);
    if (!record || record.revokedAt) return null;
    return record;
  }

  async listKeys(userId: string): Promise<ApiKey[]> {
    return this.store.listApiKeys(userId);
  }

  async revokeKey(id: string): Promise<void> {
    return this.store.revokeApiKey(id);
  }

  /** Record a usage event and deduct from balance. Returns false if insufficient balance. */
  async recordUsage(apiKeyId: string, userId: string, type: UsageRecord['type'], quantity = 1): Promise<boolean> {
    const costCents = COSTS[type] * quantity;
    const balance = await this.store.getBalance(userId);

    if (balance && balance.balanceCents < costCents) return false;

    await this.store.recordUsage({
      id: crypto.randomUUID(),
      apiKeyId,
      userId,
      type,
      quantity,
      costCents,
      timestamp: new Date().toISOString(),
    });

    if (balance) {
      const newBalance = balance.balanceCents - costCents;
      await this.store.updateBalance(userId, newBalance);

      // Auto top-up check
      if (balance.autoTopUp && newBalance <= balance.topUpThresholdCents) {
        await this.store.updateBalance(userId, newBalance + balance.topUpAmountCents);
        // In production: trigger Stripe charge here
      }
    }

    return true;
  }

  async getUsage(query: UsageQuery): Promise<UsageRecord[]> {
    return this.store.getUsage(query);
  }

  async getBalance(userId: string): Promise<Balance | null> {
    return this.store.getBalance(userId);
  }
}
