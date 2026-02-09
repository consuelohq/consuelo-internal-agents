import type {
  DialOptions,
  DialResult,
  HangupResult,
  VoiceToken,
  ProvisionNumberOptions,
  ProvisionResult,
} from '../types.js';

/**
 * Abstract dialer provider interface.
 * Implement this to add support for telephony providers beyond Twilio.
 */
export interface DialerProvider {
  readonly name: string;

  /** Initiate an outbound call */
  dial(options: DialOptions): Promise<DialResult>;

  /** Hang up an active call */
  hangup(callSid: string): Promise<HangupResult>;

  /** Generate a voice token for browser-based calling */
  getToken(userId: string): Promise<VoiceToken>;

  /** Provision a new phone number */
  provisionNumber(options: ProvisionNumberOptions): Promise<ProvisionResult>;

  /** Check if a call is in a terminal state */
  isCallCompleted(callSid: string): Promise<boolean>;
}
