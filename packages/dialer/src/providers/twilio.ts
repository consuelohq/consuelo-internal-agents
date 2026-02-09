import type { DialerProvider } from './base.js';
import type {
  TwilioCredentials,
  DialOptions,
  DialResult,
  HangupResult,
  VoiceToken,
  ProvisionNumberOptions,
  ProvisionResult,
} from '../types.js';

const TERMINAL_STATUSES = ['completed', 'failed', 'busy', 'no-answer', 'canceled'];

/**
 * Twilio implementation of the DialerProvider.
 *
 * Requires the `twilio` package as a peer dependency.
 * Credentials can be passed directly or read from env vars:
 *   TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_API_KEY,
 *   TWILIO_API_SECRET, TWILIO_TWIML_APP_SID
 */
export class TwilioProvider implements DialerProvider {
  readonly name = 'twilio';
  private client: any;
  private credentials: TwilioCredentials;

  constructor(credentials?: TwilioCredentials) {
    this.credentials = {
      accountSid: credentials?.accountSid ?? process.env.TWILIO_ACCOUNT_SID ?? '',
      authToken: credentials?.authToken ?? process.env.TWILIO_AUTH_TOKEN ?? '',
      apiKey: credentials?.apiKey ?? process.env.TWILIO_API_KEY,
      apiSecret: credentials?.apiSecret ?? process.env.TWILIO_API_SECRET,
      twimlAppSid: credentials?.twimlAppSid ?? process.env.TWILIO_TWIML_APP_SID,
    };
  }

  private async getClient(): Promise<any> {
    if (this.client) return this.client;
    const twilio = await import('twilio');
    this.client = twilio.default(this.credentials.accountSid, this.credentials.authToken);
    return this.client;
  }

  async dial(options: DialOptions): Promise<DialResult> {
    try {
      const client = await this.getClient();
      const fromNumber = options.callerIdNumber ?? options.from;

      const call = await client.calls.create({
        to: options.from, // call the agent first (3-way pattern)
        from: fromNumber,
        url: options.statusCallbackUrl
          ? `${options.statusCallbackUrl}?customer_number=${encodeURIComponent(options.to)}&user_id=${encodeURIComponent(options.userId)}`
          : undefined,
        statusCallback: options.statusCallbackUrl,
        statusCallbackEvent: ['completed'],
        statusCallbackMethod: 'POST',
      });

      return {
        success: true,
        callSid: call.sid,
        fromNumber,
        selectionMethod: options.callerIdNumber ? 'manual' : 'system_default',
      };
    } catch (err: any) {
      return { success: false, error: err.message };
    }
  }

  async hangup(callSid: string): Promise<HangupResult> {
    try {
      const client = await this.getClient();
      await client.calls(callSid).update({ status: 'completed' });
      return { success: true, callSid };
    } catch (err: any) {
      return { success: false, callSid, error: err.message };
    }
  }

  async getToken(userId: string): Promise<VoiceToken> {
    const { apiKey, apiSecret, twimlAppSid, accountSid } = this.credentials;
    if (!apiKey || !apiSecret || !twimlAppSid) {
      throw new Error('Twilio API key, secret, and TwiML app SID are required for voice tokens');
    }

    const twilio = await import('twilio');
    const { AccessToken } = twilio.jwt;
    const { VoiceGrant } = AccessToken;

    const identity = `user_${userId}`;
    const ttl = 3600;

    const token = new AccessToken(accountSid, apiKey, apiSecret, { identity, ttl });
    const grant = new VoiceGrant({ outgoingApplicationSid: twimlAppSid, incomingAllow: true });
    token.addGrant(grant);

    return { token: token.toJwt(), identity, ttl };
  }

  async provisionNumber(options: ProvisionNumberOptions): Promise<ProvisionResult> {
    try {
      const client = await this.getClient();

      if (options.phoneNumber) {
        // provision a specific number
        const number = await client.incomingPhoneNumbers.create({
          phoneNumber: options.phoneNumber,
          friendlyName: options.friendlyName ?? 'Consuelo Number',
          voiceUrl: options.voiceUrl,
          voiceMethod: 'POST',
          smsUrl: options.smsUrl,
          smsMethod: 'POST',
        });
        return {
          success: true,
          phoneNumber: number.phoneNumber,
          sid: number.sid,
          areaCode: options.areaCode,
        };
      }

      // search by area code then provision first available
      const available = await client.availablePhoneNumbers('US').local.list({
        areaCode: options.areaCode,
        limit: 1,
      });

      if (!available.length) {
        return { success: false, error: `No numbers available for area code ${options.areaCode}` };
      }

      const number = await client.incomingPhoneNumbers.create({
        phoneNumber: available[0].phoneNumber,
        friendlyName: options.friendlyName ?? 'Consuelo Number',
        voiceUrl: options.voiceUrl,
        voiceMethod: 'POST',
        smsUrl: options.smsUrl,
        smsMethod: 'POST',
      });

      return {
        success: true,
        phoneNumber: number.phoneNumber,
        sid: number.sid,
        areaCode: options.areaCode,
      };
    } catch (err: any) {
      return { success: false, error: err.message };
    }
  }

  async isCallCompleted(callSid: string): Promise<boolean> {
    try {
      const client = await this.getClient();
      const call = await client.calls(callSid).fetch();
      return TERMINAL_STATUSES.includes(call.status);
    } catch {
      return true; // if we can't fetch it, treat as completed
    }
  }
}
