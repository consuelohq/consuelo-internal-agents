import type { Queue, QueueResult, StorageProvider } from './types.js';
import { MemoryProvider } from './providers/memory.js';

/**
 * Queues — call queue management with ordering and attempt tracking.
 */
export class Queues {
  readonly store: StorageProvider;

  constructor(store?: StorageProvider) {
    this.store = store ?? new MemoryProvider();
  }

  async create(name: string, contactIds: string[], ordering: Queue['ordering'] = 'sequential'): Promise<Queue> {
    return this.store.createQueue({ name, contactIds, ordering, currentIndex: 0, status: 'idle', results: [] });
  }

  /** Get the next contact ID in the queue, advancing the pointer */
  async getNext(queueId: string): Promise<string | null> {
    const queue = await this.store.getQueue(queueId);
    if (!queue || queue.status === 'completed' || queue.currentIndex >= queue.contactIds.length) return null;

    const contactId = queue.contactIds[queue.currentIndex];
    await this.store.updateQueue(queueId, {
      currentIndex: queue.currentIndex + 1,
      status: queue.currentIndex + 1 >= queue.contactIds.length ? 'completed' : 'active',
    });
    return contactId;
  }

  /** Record a call attempt result */
  async recordResult(queueId: string, result: QueueResult): Promise<void> {
    const queue = await this.store.getQueue(queueId);
    if (!queue) return;
    await this.store.updateQueue(queueId, { results: [...queue.results, result] });
  }

  async get(queueId: string): Promise<Queue | null> {
    return this.store.getQueue(queueId);
  }

  async pause(queueId: string): Promise<void> {
    await this.store.updateQueue(queueId, { status: 'paused' });
  }

  async resume(queueId: string): Promise<void> {
    await this.store.updateQueue(queueId, { status: 'active' });
  }
}
