// @consuelo/coaching — types

export interface CoachingConfig {
  provider?: "groq" | "openai" | "anthropic";
  apiKey?: string;
  model?: string;
  playbookDir?: string;
}

export interface CoachingRequest {
  transcript: string;
  context?: string;
  playbook?: string;
}

export interface SalesCoaching {
  emotionalTrigger: string;
  actionablePhrases: string[];
  painFunnelQuestions: string[];
  objectionHandling?: string;
  closingStrategy?: string;
}

export interface CoachingProvider {
  coach(request: CoachingRequest): Promise<SalesCoaching>;
  analyzeCall(transcript: string): Promise<CallAnalysis>;
}

export interface CallAnalysis {
  sentiment: "positive" | "neutral" | "negative";
  keyMoments: KeyMoment[];
  talkRatio: number;
  questionsAsked: number;
  objectionsHandled: number;
}

export interface KeyMoment {
  timestamp: string;
  type: "objection" | "buying_signal" | "closing_attempt" | "pain_point";
  text: string;
  significance: number;
}
