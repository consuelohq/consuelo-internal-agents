import type { CallerIdLock } from '../types.js';

/**
 * Caller ID lock service — prevents concurrent use of the same
 * outbound number across multiple active calls.
 *
 * This is a storage-agnostic interface. Provide your own store
 * implementation (e.g. MongoDB, Redis, in-memory for testing).
 */
export interface LockStore {
  acquire(lock: CallerIdLock): Promise<boolean>;
  release(callSid: string): Promise<boolean>;
  releaseByNumber(phoneNumber: string): Promise<boolean>;
  isAvailable(phoneNumber: string): Promise<boolean>;
  getByCallSid(callSid: string): Promise<CallerIdLock | null>;
  getByUser(userId: string): Promise<CallerIdLock[]>;
}

const DEFAULT_TTL_MS = 5 * 60 * 1000; // 5 minutes

export class CallerIdLockService {
  private store: LockStore;
  private ttlMs: number;

  constructor(store: LockStore, ttlMs?: number) {
    this.store = store;
    this.ttlMs = ttlMs ?? DEFAULT_TTL_MS;
  }

  async acquireLock(phoneNumber: string, userId: string, callSid: string): Promise<boolean> {
    const now = new Date();
    return this.store.acquire({
      phoneNumber,
      userId,
      callSid,
      acquiredAt: now,
      expiresAt: new Date(now.getTime() + this.ttlMs),
    });
  }

  async releaseLock(callSid: string): Promise<boolean> {
    return this.store.release(callSid);
  }

  async releaseLockByNumber(phoneNumber: string): Promise<boolean> {
    return this.store.releaseByNumber(phoneNumber);
  }

  async isNumberAvailable(phoneNumber: string): Promise<boolean> {
    return this.store.isAvailable(phoneNumber);
  }

  async getUserLocks(userId: string): Promise<CallerIdLock[]> {
    return this.store.getByUser(userId);
  }
}

/**
 * Simple in-memory lock store for testing / single-process use.
 */
export class InMemoryLockStore implements LockStore {
  private locks = new Map<string, CallerIdLock>();

  async acquire(lock: CallerIdLock): Promise<boolean> {
    // clean expired
    this.cleanExpired();
    const existing = this.locks.get(lock.phoneNumber);
    if (existing && existing.callSid !== lock.callSid) return false;
    this.locks.set(lock.phoneNumber, lock);
    return true;
  }

  async release(callSid: string): Promise<boolean> {
    for (const [key, lock] of this.locks) {
      if (lock.callSid === callSid) {
        this.locks.delete(key);
        return true;
      }
    }
    return false;
  }

  async releaseByNumber(phoneNumber: string): Promise<boolean> {
    return this.locks.delete(phoneNumber);
  }

  async isAvailable(phoneNumber: string): Promise<boolean> {
    this.cleanExpired();
    return !this.locks.has(phoneNumber);
  }

  async getByCallSid(callSid: string): Promise<CallerIdLock | null> {
    for (const lock of this.locks.values()) {
      if (lock.callSid === callSid) return lock;
    }
    return null;
  }

  async getByUser(userId: string): Promise<CallerIdLock[]> {
    return [...this.locks.values()].filter((l) => l.userId === userId);
  }

  private cleanExpired(): void {
    const now = Date.now();
    for (const [key, lock] of this.locks) {
      if (lock.expiresAt.getTime() < now) this.locks.delete(key);
    }
  }
}
