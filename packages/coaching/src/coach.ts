import type { CoachingProvider } from './providers/base.js';
import type { CoachingConfig, Message, CoachOptions, AnalyzeOptions } from './types.js';
import type { SalesCoaching, CallAnalytics } from './schemas/coaching.js';
import { GroqProvider } from './providers/groq.js';
import { analyzeConversationDynamics } from './services/dynamics.js';

/**
 * Main Coach class — the public API for @consuelo/coaching.
 *
 * @example
 * ```ts
 * import { Coach } from '@consuelo/coaching';
 *
 * const coach = new Coach({ apiKey: '...' });
 * const tips = await coach.coach(transcript, { contextChunks: ['...'] });
 * ```
 */
export class Coach {
  readonly provider: CoachingProvider;

  constructor(config: CoachingConfig & { customProvider?: CoachingProvider } = {}) {
    this.provider = config.customProvider ?? new GroqProvider(config);
  }

  /** Get real-time coaching suggestions for an active conversation */
  async coach(conversation: Message[], options: CoachOptions = {}): Promise<SalesCoaching> {
    const dynamics = analyzeConversationDynamics(conversation);
    const recent = conversation.slice(-(options.maxRecentMessages ?? 15));
    const convText = recent.map((m) => `${m.role.toUpperCase()}: ${m.content}`).join('\n');

    const lastCustomerMsg = dynamics.customer_messages.at(-1) ?? '';

    const contextBlock = options.contextChunks?.length
      ? 'Product Context:\n' + options.contextChunks.join('\n\n') + '\n\n'
      : '';

    const prompt =
      `You are providing real-time sales coaching. Be direct and actionable.\n\n` +
      contextBlock +
      `Recent Conversation:\n${convText}\n\n` +
      `Customer's Last Statement: ${lastCustomerMsg}\n\n` +
      `Respond with JSON: {"product_or_option_name": "emotional trigger", "details": ["1-3 bold actionable phrases"], "clarifying_questions": ["2-3 pain funnel questions"]}\n` +
      `NO summaries. ONLY actionable content.`;

    return this.provider.coach(prompt);
  }

  /** Generate post-call analytics */
  async analyzeCall(conversation: Message[], options: AnalyzeOptions = {}): Promise<CallAnalytics> {
    const transcript = conversation.map((m) => `${m.role.toUpperCase()}: ${m.content}`).join('\n');
    return this.provider.analyze(transcript, {
      callSid: options.callSid ?? '',
      userId: options.userId ?? '',
      phoneNumber: options.phoneNumber ?? '',
    });
  }
}
