/** LLM provider configuration */
export interface CoachingConfig {
  provider?: 'groq' | 'openai' | 'anthropic';
  apiKey?: string;
  model?: string;
  baseUrl?: string;
  temperature?: number;
  maxTokens?: number;
}

/** A single message in a conversation */
export interface Message {
  role: 'customer' | 'sales_rep';
  content: string;
}

/** Options for real-time coaching */
export interface CoachOptions {
  callSid?: string;
  contextChunks?: string[];
  maxRecentMessages?: number;
}

/** Options for post-call analysis */
export interface AnalyzeOptions {
  callSid?: string;
  userId?: string;
  phoneNumber?: string;
}

/** Playbook upload options */
export interface PlaybookUploadOptions {
  collectionName: string;
  userId?: string;
  fileTag?: string;
  chunkSize?: number;
}

/** Vector store abstraction for playbook search */
export interface VectorStore {
  add(documents: string[], embeddings: number[][], ids: string[], metadata?: Record<string, string>[]): Promise<void>;
  query(embedding: number[], topK: number, where?: Record<string, string>): Promise<string[]>;
}

/** Embedding function abstraction */
export type EmbedFn = (text: string) => Promise<number[]>;

/** Text extraction function for file uploads */
export type ReadFileFn = (content: Buffer, ext: string) => Promise<string>;
