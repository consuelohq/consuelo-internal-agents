import fs from 'fs';
import path from 'path';

const WORKSPACE_ROOT = '/Users/kokayi/Dev/claude-agent-workflow';

// Files to inject, in order
const CONTEXT_FILES = [
  { name: 'agents', file: 'AGENTS.md' },
  { name: 'soul', file: 'SOUL.md' },
  { name: 'user', file: 'USER.md' },
  { name: 'tools', file: 'TOOLS.md' },
  { name: 'memory', file: 'MEMORY.md' },
];

// Re-inject context every N messages (10 total = 5 from user + 5 from assistant)
const REINJECT_EVERY = 10;

async function readFileSafe(filePath) {
  try {
    return await fs.promises.readFile(filePath, 'utf-8');
  } catch (e) {
    return null;
  }
}

async function buildContextBlock() {
  const parts = [];

  for (const { name, file } of CONTEXT_FILES) {
    const content = await readFileSafe(path.join(WORKSPACE_ROOT, file));
    if (content) {
      parts.push(`<${name}>\n${content}\n</${name}>`);
    }
  }

  if (parts.length === 0) return '';
  return `<auto-context>\n${parts.join('\n\n')}\n</auto-context>`;
}

function getMemoryInstructions() {
  const today = new Date().toISOString().split('T')[0];
  const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString().split('T')[0];

  return `
<memory-instructions>
Before responding:
1. Check memory/${today}.md and memory/${yesterday}.md for recent context
2. If in main session: also check ko.md and people.md for updates
3. Track any open loops or follow-ups mentioned
</memory-instructions>`;
}

export const AutoContextPlugin = async ({ client }) => {
  // Track message counts per session for periodic re-injection
  const sessionMessageCounts = new Map();

  return {
    // ─── SYSTEM PROMPT: Fresh file reads on every LLM call ───
    'experimental.chat.system.transform': async (input, output) => {
      const contextBlock = await buildContextBlock();

      if (contextBlock) {
        output.system.unshift(contextBlock);
      }

      output.system.push(getMemoryInstructions());
    },

    // ─── COMPACTION: Ensure files survive context compression ───
    'experimental.session.compacting': async (input, output) => {
      const contextBlock = await buildContextBlock();

      if (contextBlock) {
        output.context.push(`## Workspace Context Files (MUST be preserved through compaction)

The following files define the agent's identity, workspace rules, user preferences, available tools, and long-term memory. These are critical and must be retained in the compaction summary.

${contextBlock}

${getMemoryInstructions()}`);
      }
    },

    // ─── EVENT: Track message counts per session ───
    event: async ({ event }) => {
      if (event.type === 'message.updated') {
        const sessionID = event.properties?.sessionID;
        if (!sessionID) return;

        const current = sessionMessageCounts.get(sessionID) || 0;
        sessionMessageCounts.set(sessionID, current + 1);
      }

      // Clean up old sessions on delete
      if (event.type === 'session.deleted') {
        const sessionID = event.properties?.sessionID;
        if (sessionID) sessionMessageCounts.delete(sessionID);
      }
    },

    // ─── MESSAGES: Re-inject context every N messages ───
    'experimental.chat.messages.transform': async (input, output) => {
      if (!output.messages || output.messages.length === 0) return;

      const totalMessages = output.messages.length;

      // Only inject if we've crossed a threshold
      if (totalMessages < REINJECT_EVERY) return;

      // Find injection points: every REINJECT_EVERY messages
      const contextBlock = await buildContextBlock();
      if (!contextBlock) return;

      const reminderContent = `<system-reminder>
Context refresh (auto-injected every ${REINJECT_EVERY} messages to maintain continuity):

${contextBlock}

${getMemoryInstructions()}
</system-reminder>`;

      // Inject at each threshold point
      // We inject BEFORE the message at each threshold index
      // Walk backwards so insertions don't shift indices
      const injectionPoints = [];
      for (let i = REINJECT_EVERY; i < totalMessages; i += REINJECT_EVERY) {
        injectionPoints.push(i);
      }

      // For each injection point, append the reminder to the parts of the
      // message just before that index (so the model sees it in context)
      for (const idx of injectionPoints) {
        const targetMsg = output.messages[idx - 1];
        if (targetMsg && targetMsg.parts) {
          // Check if we already injected (avoid duplicates on re-runs)
          const alreadyInjected = targetMsg.parts.some(
            (p) => p.type === 'text' && p.text?.includes('<auto-context>')
          );
          if (!alreadyInjected) {
            targetMsg.parts.push({
              type: 'text',
              text: reminderContent,
            });
          }
        }
      }
    },
  };
};
