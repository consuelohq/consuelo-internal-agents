/** Structured sales coaching output — mirrors the monolith's SalesCoaching pydantic model */
export interface SalesCoaching {
  product_or_option_name: string;
  details: string[];
  clarifying_questions?: string[] | null;
  timestamp?: string | null;
  is_new_content?: boolean | null;
}

/** Key moment during a call */
export interface KeyMoment {
  timestamp: string;
  type: 'objection' | 'buying_signal' | 'price_discussion' | 'next_steps' | 'closing_attempt';
  description: string;
  transcript_snippet: string;
}

/** Sentiment analysis of a call */
export interface SentimentAnalysis {
  customer_sentiment: 'positive' | 'neutral' | 'negative' | 'mixed';
  engagement_level: 'high' | 'medium' | 'low';
  objections_raised: string[];
  buying_signals: string[];
}

/** Quantitative call performance metrics */
export interface PerformanceMetrics {
  talk_ratio: number;
  questions_asked: number;
  objections_handled: number;
  next_steps_established: boolean;
  call_duration_minutes: number;
}

/** Complete post-call analytics */
export interface CallAnalytics {
  call_sid: string;
  user_id: string;
  phone_number: string;
  call_date: string;
  key_moments: KeyMoment[];
  sentiment_analysis: SentimentAnalysis;
  performance_metrics: PerformanceMetrics;
  overall_score: number;
  strengths: string[];
  improvement_areas: string[];
  action_items: string[];
  generated_at: string;
}
