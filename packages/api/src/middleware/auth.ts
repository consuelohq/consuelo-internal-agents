import type { ApiKeyContext, ApiRequest, ApiResponse } from '../types.js';

/**
 * API key authentication middleware.
 * Expects `Authorization: Bearer sk_live_... | sk_test_...`
 */
export function authMiddleware(
  validateKey?: (key: string) => Promise<ApiKeyContext | null>,
) {
  return async (req: ApiRequest, res: ApiResponse, next: () => void) => {
    const header = req.headers['authorization'] ?? req.headers['Authorization'] ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';

    if (!token) {
      res.status(401).json({ error: { code: 'unauthorized', message: 'Missing API key' } });
      return;
    }

    if (validateKey) {
      const ctx = await validateKey(token);
      if (!ctx) {
        res.status(401).json({ error: { code: 'unauthorized', message: 'Invalid API key' } });
        return;
      }
      (req as any).apiKeyContext = ctx;
    } else {
      // Default: parse mode from key prefix
      const mode = token.startsWith('sk_test_') ? 'test' : 'live';
      (req as any).apiKeyContext = { userId: 'default', mode } satisfies ApiKeyContext;
    }

    next();
  };
}
