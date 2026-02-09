import type { ApiRequest, ApiResponse } from '../types.js';

/** Wraps a handler to catch errors and return consistent error format */
export function errorHandler(handler: (req: ApiRequest, res: ApiResponse) => Promise<void>) {
  return async (req: ApiRequest, res: ApiResponse) => {
    try {
      await handler(req, res);
    } catch (err: any) {
      const message = err?.message ?? 'Internal server error';
      const code = err?.code ?? 'internal_error';
      const status = err?.status ?? 500;
      res.status(status).json({ error: { code, message } });
    }
  };
}
