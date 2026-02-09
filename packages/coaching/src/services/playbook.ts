import type { VectorStore, EmbedFn, ReadFileFn, PlaybookUploadOptions } from '../types.js';

/** Split text into word-based chunks (default 500 words, matching monolith). */
export function chunkText(text: string, chunkSize = 500): string[] {
  const words = text.split(/\s+/);
  const chunks: string[] = [];
  for (let i = 0; i < words.length; i += chunkSize) {
    chunks.push(words.slice(i, i + chunkSize).join(' '));
  }
  return chunks;
}

/**
 * Playbook service — upload documents and retrieve relevant context via vector search.
 *
 * Requires user-supplied `embedFn` and `vectorStore` to stay free of heavy dependencies
 * (sentence-transformers, chromadb, etc.).
 */
export class PlaybookService {
  constructor(
    private vectorStore: VectorStore,
    private embedFn: EmbedFn,
    private readFileFn?: ReadFileFn,
  ) {}

  /** Upload a document: extract text → chunk → embed → store */
  async upload(content: Buffer | string, ext: string, options: PlaybookUploadOptions): Promise<{ chunksIndexed: number }> {
    let text: string;
    if (typeof content === 'string') {
      text = content;
    } else if (this.readFileFn) {
      text = await this.readFileFn(content, ext);
    } else {
      text = content.toString('utf-8');
    }

    const chunks = chunkText(text, options.chunkSize);
    const embeddings = await Promise.all(chunks.map((c) => this.embedFn(c)));
    const ts = Date.now();
    const ids = chunks.map((_, i) => `${options.collectionName}_chunk_${i}_${ts}`);
    const metadata = chunks.map(() => {
      const m: Record<string, string> = {};
      if (options.userId) m.user_id = options.userId;
      if (options.fileTag) m.file_tag = options.fileTag;
      return m;
    });

    await this.vectorStore.add(chunks, embeddings, ids, metadata);
    return { chunksIndexed: chunks.length };
  }

  /** Retrieve relevant context chunks for a query */
  async retrieveContext(query: string, topK = 3, userId?: string): Promise<string[]> {
    const embedding = await this.embedFn(query);
    const where = userId ? { user_id: userId } : undefined;
    return this.vectorStore.query(embedding, topK, where);
  }
}
