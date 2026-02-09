import type { Message } from '../types.js';

export interface ConversationDynamics {
  customer_messages: string[];
  rep_messages: string[];
  latest_speaker: 'customer' | 'sales_rep' | null;
  total_exchanges: number;
}

/** Analyze conversation to understand customer vs sales rep dynamics. */
export function analyzeConversationDynamics(conversation: Message[]): ConversationDynamics {
  if (!conversation.length) {
    return { customer_messages: [], rep_messages: [], latest_speaker: null, total_exchanges: 0 };
  }

  const customer_messages: string[] = [];
  const rep_messages: string[] = [];
  let latest_speaker: ConversationDynamics['latest_speaker'] = null;

  for (const msg of conversation) {
    if (msg.role === 'customer') {
      customer_messages.push(msg.content);
      latest_speaker = 'customer';
    } else {
      rep_messages.push(msg.content);
      latest_speaker = 'sales_rep';
    }
  }

  return { customer_messages, rep_messages, latest_speaker, total_exchanges: conversation.length };
}
