// Core
export { Dialer } from './dialer.js';

// Providers
export { TwilioProvider } from './providers/twilio.js';
export type { DialerProvider } from './providers/base.js';

// Services
export { LocalPresenceService, extractAreaCode } from './services/local-presence.js';
export { CallerIdLockService, InMemoryLockStore } from './services/caller-id.js';
export type { LockStore } from './services/caller-id.js';
export type { NumberPool } from './services/local-presence.js';

// Types
export type {
  TwilioCredentials,
  DialerConfig,
  DialOptions,
  DialResult,
  HangupResult,
  VoiceToken,
  ProvisionNumberOptions,
  ProvisionResult,
  PhoneNumber,
  NumberSelection,
  CallerIdLock,
} from './types.js';
