/** Structured output schemas — mirrors monolith pydantic models */

export interface KeyMoment {
  timestamp: string; // "MM:SS"
  type: 'objection' | 'buying_signal' | 'price_discussion' | 'next_steps' | 'closing_attempt' | string;
  description: string;
  transcript_snippet: string;
}

export interface SentimentAnalysis {
  customer_sentiment: 'positive' | 'neutral' | 'negative' | 'mixed';
  engagement_level: 'high' | 'medium' | 'low';
  objections_raised: string[];
  buying_signals: string[];
}

export interface PerformanceMetrics {
  talk_ratio: number; // 0-1
  questions_asked: number;
  objections_handled: number;
  next_steps_established: boolean;
  call_duration_minutes: number;
}

export interface CallAnalytics {
  call_sid: string;
  user_id: string;
  phone_number: string;
  call_date: string;
  key_moments: KeyMoment[];
  sentiment_analysis: SentimentAnalysis;
  performance_metrics: PerformanceMetrics;
  overall_score: number; // 0-100
  strengths: string[];
  improvement_areas: string[];
  action_items: string[];
  generated_at: string; // ISO timestamp
}
