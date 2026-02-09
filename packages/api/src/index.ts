// Middleware
export { authMiddleware, rateLimitMiddleware, errorHandler } from './middleware/index.js';

// Routes
export {
  allRoutes,
  callRoutes,
  coachingRoutes,
  contactRoutes,
  analyticsRoutes,
  webhookRoutes,
} from './routes/index.js';
export type { RouteDefinition } from './routes/index.js';

// Types
export type { ApiConfig, ApiKeyContext, ApiError, ApiRequest, ApiResponse } from './types.js';
