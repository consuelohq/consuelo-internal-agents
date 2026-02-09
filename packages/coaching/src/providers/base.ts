import type { SalesCoaching, CallAnalytics } from '../schemas/coaching.js';

/** LLM provider interface for coaching */
export interface CoachingProvider {
  /** Generate structured coaching from a prompt */
  coach(prompt: string): Promise<SalesCoaching>;

  /** Generate call analytics from a transcript */
  analyze(transcript: string, meta: { callSid: string; userId: string; phoneNumber: string }): Promise<CallAnalytics>;
}
