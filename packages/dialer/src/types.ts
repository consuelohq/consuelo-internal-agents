// @consuelo/dialer — types

export interface DialerConfig {
  provider?: "twilio";
  accountSid?: string;
  authToken?: string;
  defaultCallerId?: string;
  localPresence?: boolean;
}

export interface CallOptions {
  to: string;
  from?: string;
  callerId?: string;
  localPresence?: boolean;
}

export interface CallResult {
  callSid: string;
  status: string;
  from: string;
  to: string;
  startedAt: Date;
}

export interface DialerProvider {
  dial(options: CallOptions): Promise<CallResult>;
  hangup(callSid: string): Promise<void>;
  getToken(userId: string): Promise<string>;
  provisionNumber(areaCode: string): Promise<string>;
}
