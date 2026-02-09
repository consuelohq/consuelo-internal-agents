import type { TranscriptEntry, Message } from './types.js';

/**
 * Maps a Twilio transcription track to a conversation role.
 */
function trackToRole(track: string): TranscriptEntry['role'] {
  const t = track?.toLowerCase() ?? '';
  if (t === 'inbound' || t === 'inbound_track') return 'sales_rep';
  if (t === 'outbound' || t === 'outbound_track') return 'customer';
  return 'unknown';
}

/**
 * Process a Twilio real-time transcription webhook event
 * and return a structured TranscriptEntry.
 */
export function processTranscriptionEvent(form: Record<string, string>): TranscriptEntry | null {
  if (form.TranscriptionEvent !== 'transcription-content') return null;

  const dataStr = form.TranscriptionData;
  if (!dataStr) return null;

  const data = JSON.parse(dataStr);
  const transcript = data.transcript as string | undefined;
  if (!transcript) return null;

  const callSid = form.CallSid ?? '';
  const track = form.Track ?? '';
  const ts = Date.now();

  return {
    id: `${callSid}_${track}_${ts}`,
    callSid,
    track,
    transcript,
    final: form.Final === 'true',
    stability: form.Stability,
    timestamp: new Date().toISOString(),
    role: trackToRole(track),
  };
}

/**
 * Aggregate individual transcript entries into a conversation array.
 */
export function aggregateTranscript(entries: TranscriptEntry[]): Message[] {
  return entries
    .filter((e) => e.final && e.role !== 'unknown' && e.transcript.trim())
    .sort((a, b) => a.timestamp.localeCompare(b.timestamp))
    .map((e) => ({ role: e.role, content: e.transcript, timestamp: e.timestamp }));
}
