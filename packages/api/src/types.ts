/** API configuration */
export interface ApiConfig {
  /** Function to validate an API key. Return user context or null. */
  validateKey?: (key: string) => Promise<ApiKeyContext | null>;
  /** Rate limit: max requests per window */
  rateLimit?: { max: number; windowMs: number };
}

/** Context attached to an authenticated request */
export interface ApiKeyContext {
  userId: string;
  orgId?: string;
  mode: 'live' | 'test';
  tier?: string;
}

/** Standard API error response */
export interface ApiError {
  error: { code: string; message: string };
}

/** Generic request abstraction */
export interface ApiRequest {
  method: string;
  path: string;
  headers: Record<string, string | undefined>;
  body?: unknown;
  query?: Record<string, string>;
  params?: Record<string, string>;
}

/** Generic response helpers */
export interface ApiResponse {
  status(code: number): ApiResponse;
  json(data: unknown): void;
}
