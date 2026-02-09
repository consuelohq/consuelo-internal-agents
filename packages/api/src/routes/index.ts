import type { ApiRequest, ApiResponse } from '../types.js';

/** Route descriptor — framework-agnostic */
export interface RouteDefinition {
  method: 'GET' | 'POST' | 'PUT' | 'DELETE';
  path: string;
  handler: (req: ApiRequest, res: ApiResponse) => Promise<void>;
}

/** /v1/calls routes */
export function callRoutes(): RouteDefinition[] {
  return [
    { method: 'POST', path: '/v1/calls', handler: async (req, res) => {
      const body = req.body as any;
      res.status(200).json({ callSid: body?.to ? `CA_${Date.now()}` : null, status: 'initiated' });
    }},
    { method: 'GET', path: '/v1/calls/:id', handler: async (req, res) => {
      res.status(200).json({ callSid: req.params?.id, status: 'in-progress' });
    }},
    { method: 'POST', path: '/v1/calls/:id/hangup', handler: async (req, res) => {
      res.status(200).json({ callSid: req.params?.id, status: 'completed' });
    }},
  ];
}

/** /v1/coaching routes */
export function coachingRoutes(): RouteDefinition[] {
  return [
    { method: 'POST', path: '/v1/coaching', handler: async (req, res) => {
      res.status(200).json({ message: 'Use @consuelo/coaching for full implementation' });
    }},
    { method: 'POST', path: '/v1/coaching/analyze', handler: async (req, res) => {
      res.status(200).json({ message: 'Use @consuelo/coaching for full implementation' });
    }},
    { method: 'POST', path: '/v1/coaching/playbook', handler: async (req, res) => {
      res.status(200).json({ message: 'Use @consuelo/coaching for full implementation' });
    }},
  ];
}

/** /v1/contacts routes */
export function contactRoutes(): RouteDefinition[] {
  return [
    { method: 'GET', path: '/v1/contacts', handler: async (_req, res) => {
      res.status(200).json({ contacts: [] });
    }},
    { method: 'POST', path: '/v1/contacts', handler: async (req, res) => {
      res.status(201).json({ contact: req.body });
    }},
    { method: 'GET', path: '/v1/contacts/:id', handler: async (req, res) => {
      res.status(200).json({ contact: { id: req.params?.id } });
    }},
    { method: 'PUT', path: '/v1/contacts/:id', handler: async (req, res) => {
      res.status(200).json({ contact: { id: req.params?.id, ...req.body as any } });
    }},
    { method: 'DELETE', path: '/v1/contacts/:id', handler: async (req, res) => {
      res.status(200).json({ deleted: true });
    }},
    { method: 'GET', path: '/v1/contacts/search', handler: async (_req, res) => {
      res.status(200).json({ contacts: [] });
    }},
    { method: 'POST', path: '/v1/contacts/import', handler: async (_req, res) => {
      res.status(200).json({ imported: 0 });
    }},
  ];
}

/** /v1/analytics routes */
export function analyticsRoutes(): RouteDefinition[] {
  return [
    { method: 'POST', path: '/v1/analytics/analyze', handler: async (req, res) => {
      res.status(200).json({ message: 'Use @consuelo/analytics for full implementation' });
    }},
    { method: 'GET', path: '/v1/analytics/transcript/:callSid', handler: async (req, res) => {
      res.status(200).json({ callSid: req.params?.callSid, transcript: [] });
    }},
    { method: 'GET', path: '/v1/analytics/metrics', handler: async (_req, res) => {
      res.status(200).json({ metrics: {} });
    }},
  ];
}

/** /v1/webhooks routes (Twilio callbacks) */
export function webhookRoutes(): RouteDefinition[] {
  return [
    { method: 'POST', path: '/v1/webhooks/transcription', handler: async (_req, res) => {
      res.status(200).json({ received: true });
    }},
    { method: 'POST', path: '/v1/webhooks/status', handler: async (_req, res) => {
      res.status(200).json({ received: true });
    }},
  ];
}

/** All v1 routes combined */
export function allRoutes(): RouteDefinition[] {
  return [
    ...callRoutes(),
    ...coachingRoutes(),
    ...contactRoutes(),
    ...analyticsRoutes(),
    ...webhookRoutes(),
  ];
}
