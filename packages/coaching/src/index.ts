// Core
export { Coach } from './coach.js';

// Providers
export { GroqProvider } from './providers/groq.js';
export { OpenAIProvider } from './providers/openai.js';
export type { CoachingProvider } from './providers/base.js';

// Services
export { PlaybookService, chunkText } from './services/playbook.js';
export { analyzeConversationDynamics } from './services/dynamics.js';
export type { ConversationDynamics } from './services/dynamics.js';

// Schemas
export type {
  SalesCoaching,
  CallAnalytics,
  KeyMoment,
  SentimentAnalysis,
  PerformanceMetrics,
} from './schemas/coaching.js';

// Types
export type {
  CoachingConfig,
  Message,
  CoachOptions,
  AnalyzeOptions,
  PlaybookUploadOptions,
  VectorStore,
  EmbedFn,
  ReadFileFn,
} from './types.js';
