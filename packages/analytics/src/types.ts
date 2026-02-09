// @consuelo/analytics — types

export interface AnalyticsConfig {
  storage?: "mongodb" | "sqlite" | "memory";
  connectionString?: string;
}

export interface CallAnalytics {
  callSid: string;
  duration: number;
  sentiment: SentimentAnalysis;
  keyMoments: KeyMoment[];
  performance: PerformanceMetrics;
}

export interface SentimentAnalysis {
  overall: "positive" | "neutral" | "negative";
  trajectory: Array<{ timestamp: string; score: number }>;
}

export interface KeyMoment {
  timestamp: string;
  type: string;
  text: string;
  significance: number;
}

export interface PerformanceMetrics {
  talkRatio: number;
  questionsAsked: number;
  objectionsHandled: number;
  closingAttempts: number;
  avgResponseTime: number;
}

export interface TranscriptEntry {
  speaker: "agent" | "customer";
  text: string;
  timestamp: string;
}
