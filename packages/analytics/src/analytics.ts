import type { AnalyticsConfig, Message, AnalyzeCallOptions, MetricsQuery, AggregateMetrics } from './types.js';
import type { CallAnalytics, SentimentAnalysis, PerformanceMetrics } from './schemas/models.js';

const ANALYTICS_PROMPT = (transcript: string) => `Analyze this sales call transcript and provide detailed analytics:

CALL TRANSCRIPT:
${transcript}

INSTRUCTIONS:
You are a sales coach analyzing a sales call. Provide objective, actionable analysis.
Respond with ONLY a JSON object, no markdown.

Return JSON with this structure:
{
  "key_moments": [{"timestamp": "MM:SS", "type": "type", "description": "desc", "transcript_snippet": "snippet"}],
  "sentiment_analysis": {"customer_sentiment": "positive|neutral|negative|mixed", "engagement_level": "high|medium|low", "objections_raised": [], "buying_signals": []},
  "performance_metrics": {"talk_ratio": 0.6, "questions_asked": 5, "objections_handled": 0, "next_steps_established": true},
  "overall_score": 85,
  "strengths": ["..."],
  "improvement_areas": ["..."],
  "action_items": ["..."]
}`;

/** Coerce a value that might be a string into a string array */
function toStringArray(val: unknown): string[] {
  if (Array.isArray(val)) return val.map(String);
  if (typeof val === 'string' && val.trim() && val.toLowerCase() !== 'none') return [val];
  return [];
}

/** Extract JSON from an LLM response that may contain markdown fences */
function extractJson(text: string): Record<string, unknown> {
  const fenced = text.match(/```json\s*([\s\S]*?)\s*```/);
  const raw = fenced ? fenced[1] : text.match(/\{[\s\S]*\}/)?.[0];
  if (!raw) throw new Error('No JSON found in analytics response');
  return JSON.parse(raw);
}

/**
 * Core Analytics class — generates call analytics via LLM.
 */
export class Analytics {
  private config: AnalyticsConfig;

  constructor(config: AnalyticsConfig = {}) {
    this.config = config;
  }

  /** Generate structured analytics for a call transcript */
  async analyzeCall(conversation: Message[], options: AnalyzeCallOptions = {}): Promise<CallAnalytics> {
    const transcript = conversation.map((m) => `${m.role.toUpperCase()}: ${m.content}`).join('\n');
    if (!transcript) throw new Error('Empty transcript');

    const apiKey = this.config.apiKey ?? process.env.GROQ_API_KEY ?? process.env.OPENAI_API_KEY;
    if (!apiKey) throw new Error('No API key provided');

    const isOpenAI = this.config.provider === 'openai';
    const baseURL = isOpenAI ? undefined : 'https://api.groq.com/openai/v1';
    const model = this.config.model ?? (isOpenAI ? 'gpt-4o-mini' : 'llama-3.1-8b-instant');

    const { default: OpenAI } = await import('openai');
    const client = new OpenAI({ apiKey, baseURL });

    const resp = await client.chat.completions.create({
      model,
      messages: [{ role: 'user', content: ANALYTICS_PROMPT(transcript) }],
      temperature: 0.3,
      max_tokens: 1500,
    });

    const text = resp.choices[0]?.message?.content ?? '';
    const data = extractJson(text);

    const sentiment = (data.sentiment_analysis ?? {}) as Record<string, unknown>;
    const metrics = (data.performance_metrics ?? {}) as Record<string, unknown>;

    // Parse talk_ratio — might be string like "70%"
    let talkRatio = 0.6;
    const rawRatio = metrics.talk_ratio;
    if (typeof rawRatio === 'number') talkRatio = rawRatio;
    else if (typeof rawRatio === 'string') {
      const m = rawRatio.match(/(\d+)%?/);
      if (m) talkRatio = parseFloat(m[1]) > 1 ? parseFloat(m[1]) / 100 : parseFloat(m[1]);
    }

    const now = new Date().toISOString();

    return {
      call_sid: options.callSid ?? '',
      user_id: options.userId ?? '',
      phone_number: options.phoneNumber ?? '',
      call_date: options.callDate ?? now.split('T')[0],
      key_moments: ((data.key_moments as unknown[]) ?? []).map((m: any) => ({
        timestamp: m.timestamp ?? '00:00',
        type: m.type ?? 'other',
        description: m.description ?? '',
        transcript_snippet: m.transcript_snippet ?? '',
      })),
      sentiment_analysis: {
        customer_sentiment: (sentiment.customer_sentiment as string)?.toLowerCase() ?? 'neutral',
        engagement_level: (sentiment.engagement_level as string)?.toLowerCase() ?? 'medium',
        objections_raised: toStringArray(sentiment.objections_raised),
        buying_signals: toStringArray(sentiment.buying_signals),
      } as SentimentAnalysis,
      performance_metrics: {
        talk_ratio: talkRatio,
        questions_asked: Number(metrics.questions_asked) || 0,
        objections_handled: Number(metrics.objections_handled) || 0,
        next_steps_established: Boolean(metrics.next_steps_established),
        call_duration_minutes: conversation.length * 0.5,
      } as PerformanceMetrics,
      overall_score: Number(data.overall_score) || 0,
      strengths: toStringArray(data.strengths),
      improvement_areas: toStringArray(data.improvement_areas),
      action_items: toStringArray(data.action_items),
      generated_at: now,
    };
  }

  /** Compute aggregate metrics from a set of analytics results */
  static aggregateMetrics(results: CallAnalytics[]): AggregateMetrics {
    if (!results.length) return { totalCalls: 0, avgScore: 0, avgTalkRatio: 0, totalQuestionsAsked: 0, totalObjectionsHandled: 0, callsWithNextSteps: 0 };
    const n = results.length;
    return {
      totalCalls: n,
      avgScore: results.reduce((s, r) => s + r.overall_score, 0) / n,
      avgTalkRatio: results.reduce((s, r) => s + r.performance_metrics.talk_ratio, 0) / n,
      totalQuestionsAsked: results.reduce((s, r) => s + r.performance_metrics.questions_asked, 0),
      totalObjectionsHandled: results.reduce((s, r) => s + r.performance_metrics.objections_handled, 0),
      callsWithNextSteps: results.filter((r) => r.performance_metrics.next_steps_established).length,
    };
  }
}
