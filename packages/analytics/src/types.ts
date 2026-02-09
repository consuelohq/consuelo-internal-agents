/** Configuration for the Analytics module */
export interface AnalyticsConfig {
  /** LLM API key (Groq or OpenAI) */
  apiKey?: string;
  /** Model to use for analytics generation */
  model?: string;
  /** Provider: 'groq' (default) or 'openai' */
  provider?: 'groq' | 'openai';
}

/** A single message in a conversation */
export interface Message {
  role: string;
  content: string;
  timestamp?: string;
}

/** A raw transcription entry from a webhook */
export interface TranscriptEntry {
  id: string;
  callSid: string;
  track: string;
  transcript: string;
  final: boolean;
  stability?: string;
  timestamp: string;
  role: 'sales_rep' | 'customer' | 'unknown';
}

/** Options for analyzeCall() */
export interface AnalyzeCallOptions {
  callSid?: string;
  userId?: string;
  phoneNumber?: string;
  callDate?: string;
}

/** Options for getMetrics() */
export interface MetricsQuery {
  userId: string;
  startDate?: string;
  endDate?: string;
}

/** Aggregate metrics result */
export interface AggregateMetrics {
  totalCalls: number;
  avgScore: number;
  avgTalkRatio: number;
  totalQuestionsAsked: number;
  totalObjectionsHandled: number;
  callsWithNextSteps: number;
}

/** Storage interface — users supply their own persistence */
export interface AnalyticsStore {
  saveTranscript(callSid: string, entry: TranscriptEntry): Promise<void>;
  getTranscript(callSid: string): Promise<TranscriptEntry[]>;
  saveAnalytics(callSid: string, analytics: import('./schemas/models.js').CallAnalytics): Promise<void>;
  getAnalytics(query: MetricsQuery): Promise<import('./schemas/models.js').CallAnalytics[]>;
}
