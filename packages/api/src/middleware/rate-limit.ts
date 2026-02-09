import type { ApiRequest, ApiResponse } from '../types.js';

/**
 * Simple in-memory rate limiter.
 */
export function rateLimitMiddleware(max = 100, windowMs = 60_000) {
  const hits = new Map<string, { count: number; resetAt: number }>();

  return (req: ApiRequest, res: ApiResponse, next: () => void) => {
    const key = req.headers['authorization'] ?? req.headers['x-forwarded-for'] ?? 'anon';
    const now = Date.now();
    const entry = hits.get(key);

    if (!entry || now > entry.resetAt) {
      hits.set(key, { count: 1, resetAt: now + windowMs });
      next();
      return;
    }

    if (entry.count >= max) {
      res.status(429).json({ error: { code: 'rate_limited', message: 'Too many requests' } });
      return;
    }

    entry.count++;
    next();
  };
}
