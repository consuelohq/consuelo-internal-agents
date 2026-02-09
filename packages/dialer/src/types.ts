/** Twilio credentials configuration */
export interface TwilioCredentials {
  accountSid: string;
  authToken: string;
  apiKey?: string;
  apiSecret?: string;
  twimlAppSid?: string;
}

/** Dialer configuration */
export interface DialerConfig {
  provider?: 'twilio';
  credentials?: TwilioCredentials;
  /** Base URL for webhooks (status callbacks, TwiML) */
  baseUrl?: string;
  /** Default caller ID number */
  defaultNumber?: string;
}

/** Options for initiating a call */
export interface DialOptions {
  /** Number to call */
  to: string;
  /** Caller's personal number (agent's phone) */
  from: string;
  /** Manually selected outbound number (overrides auto-selection) */
  callerIdNumber?: string;
  /** User ID for the agent making the call */
  userId: string;
  /** Enable double-dial retry on no-answer */
  doubleDial?: boolean;
  /** Enable local presence number selection */
  localPresence?: boolean;
  /** Status callback URL */
  statusCallbackUrl?: string;
}

/** Result of a dial() call */
export interface DialResult {
  success: boolean;
  callSid?: string;
  fromNumber?: string;
  selectionMethod?: 'manual' | 'primary' | 'local_presence' | 'primary_fallback' | 'system_default';
  error?: string;
}

/** Result of a hangup() call */
export interface HangupResult {
  success: boolean;
  callSid: string;
  error?: string;
}

/** Twilio voice token for browser calling */
export interface VoiceToken {
  token: string;
  identity: string;
  ttl: number;
}

/** Options for provisioning a phone number */
export interface ProvisionNumberOptions {
  /** Area code to search for */
  areaCode: string;
  /** Specific number to provision (if known) */
  phoneNumber?: string;
  /** Friendly name for the number */
  friendlyName?: string;
  /** Voice webhook URL */
  voiceUrl?: string;
  /** SMS webhook URL */
  smsUrl?: string;
}

/** Result of provisioning a number */
export interface ProvisionResult {
  success: boolean;
  phoneNumber?: string;
  sid?: string;
  areaCode?: string;
  error?: string;
}

/** Phone number with metadata */
export interface PhoneNumber {
  phoneNumber: string;
  areaCode: string;
  isPrimary: boolean;
  isActive: boolean;
  city?: string;
  state?: string;
  latitude?: number;
  longitude?: number;
  twilioSid?: string;
  friendlyName?: string;
}

/** Local presence number selection result */
export interface NumberSelection {
  phoneNumber: string;
  areaCode: string;
  localMatch: boolean;
  proximityMatch: boolean;
  distanceMiles?: number;
  isPrimary: boolean;
  customerAreaCode?: string;
}

/** Caller ID lock record */
export interface CallerIdLock {
  phoneNumber: string;
  userId: string;
  callSid: string;
  acquiredAt: Date;
  expiresAt: Date;
}
