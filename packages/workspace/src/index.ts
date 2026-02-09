/** Research entry */
export interface Research {
  id: string;
  title: string;
  content: string;
  status: 'active' | 'archived' | 'draft';
  tags: string[];
  sourceUrl?: string;
  createdAt: string;
  updatedAt: string;
}

/** Cron job record */
export interface CronJob {
  id: string;
  name: string;
  command: string;
  schedule: string;
  lastRun?: string;
  lastStatus?: 'success' | 'failed';
  lastOutput?: string;
  createdAt: string;
}

/** Project record */
export interface Project {
  id: string;
  name: string;
  description: string;
  status: 'active' | 'archived';
  createdAt: string;
  updatedAt: string;
}

/** Decision record */
export interface Decision {
  id: string;
  title: string;
  context: string;
  decision: string;
  rationale: string;
  tags: string[];
  createdAt: string;
}

/** Dashboard config */
export interface Dashboard {
  id: string;
  name: string;
  config: Record<string, unknown>;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
}

/** Query options */
export interface QueryOptions {
  status?: string;
  tag?: string;
  search?: string;
  limit?: number;
  offset?: number;
}

/** Paginated response */
export interface PaginatedResponse<T> {
  data: T[];
  meta: { total: number; limit: number; offset: number };
}

/** Storage interface — users supply their own persistence */
export interface WorkspaceStore {
  // Research
  createResearch(data: Omit<Research, 'id' | 'createdAt' | 'updatedAt'>): Promise<Research>;
  getResearch(id: string): Promise<Research | null>;
  listResearch(opts?: QueryOptions): Promise<PaginatedResponse<Research>>;
  updateResearch(id: string, data: Partial<Research>): Promise<Research | null>;
  deleteResearch(id: string): Promise<boolean>;

  // Cron Jobs
  createCronJob(data: Omit<CronJob, 'id' | 'createdAt'>): Promise<CronJob>;
  getCronJob(id: string): Promise<CronJob | null>;
  listCronJobs(opts?: QueryOptions): Promise<PaginatedResponse<CronJob>>;
  updateCronJob(id: string, data: Partial<CronJob>): Promise<CronJob | null>;
  deleteCronJob(id: string): Promise<boolean>;

  // Projects
  createProject(data: Omit<Project, 'id' | 'createdAt' | 'updatedAt'>): Promise<Project>;
  getProject(id: string): Promise<Project | null>;
  listProjects(opts?: QueryOptions): Promise<PaginatedResponse<Project>>;
  updateProject(id: string, data: Partial<Project>): Promise<Project | null>;
  deleteProject(id: string): Promise<boolean>;

  // Decisions
  createDecision(data: Omit<Decision, 'id' | 'createdAt'>): Promise<Decision>;
  getDecision(id: string): Promise<Decision | null>;
  listDecisions(opts?: QueryOptions): Promise<PaginatedResponse<Decision>>;
  deleteDecision(id: string): Promise<boolean>;

  // Dashboards
  createDashboard(data: Omit<Dashboard, 'id' | 'createdAt' | 'updatedAt'>): Promise<Dashboard>;
  getDashboard(id: string): Promise<Dashboard | null>;
  listDashboards(opts?: QueryOptions): Promise<PaginatedResponse<Dashboard>>;
  updateDashboard(id: string, data: Partial<Dashboard>): Promise<Dashboard | null>;
  deleteDashboard(id: string): Promise<boolean>;
}

/**
 * Workspace — structured data store for research, projects, decisions, cron jobs, and dashboards.
 * Wraps a WorkspaceStore implementation (SQLite, in-memory, etc.)
 */
export class Workspace {
  constructor(readonly store: WorkspaceStore) {}

  // Research
  async addResearch(data: Omit<Research, 'id' | 'createdAt' | 'updatedAt'>) { return this.store.createResearch(data); }
  async getResearch(id: string) { return this.store.getResearch(id); }
  async listResearch(opts?: QueryOptions) { return this.store.listResearch(opts); }
  async updateResearch(id: string, data: Partial<Research>) { return this.store.updateResearch(id, data); }
  async deleteResearch(id: string) { return this.store.deleteResearch(id); }

  // Cron Jobs
  async addCronJob(data: Omit<CronJob, 'id' | 'createdAt'>) { return this.store.createCronJob(data); }
  async getCronJob(id: string) { return this.store.getCronJob(id); }
  async listCronJobs(opts?: QueryOptions) { return this.store.listCronJobs(opts); }
  async updateCronJob(id: string, data: Partial<CronJob>) { return this.store.updateCronJob(id, data); }
  async deleteCronJob(id: string) { return this.store.deleteCronJob(id); }

  // Projects
  async addProject(data: Omit<Project, 'id' | 'createdAt' | 'updatedAt'>) { return this.store.createProject(data); }
  async getProject(id: string) { return this.store.getProject(id); }
  async listProjects(opts?: QueryOptions) { return this.store.listProjects(opts); }
  async updateProject(id: string, data: Partial<Project>) { return this.store.updateProject(id, data); }
  async deleteProject(id: string) { return this.store.deleteProject(id); }

  // Decisions
  async addDecision(data: Omit<Decision, 'id' | 'createdAt'>) { return this.store.createDecision(data); }
  async getDecision(id: string) { return this.store.getDecision(id); }
  async listDecisions(opts?: QueryOptions) { return this.store.listDecisions(opts); }
  async deleteDecision(id: string) { return this.store.deleteDecision(id); }

  // Dashboards
  async addDashboard(data: Omit<Dashboard, 'id' | 'createdAt' | 'updatedAt'>) { return this.store.createDashboard(data); }
  async getDashboard(id: string) { return this.store.getDashboard(id); }
  async listDashboards(opts?: QueryOptions) { return this.store.listDashboards(opts); }
  async updateDashboard(id: string, data: Partial<Dashboard>) { return this.store.updateDashboard(id, data); }
  async deleteDashboard(id: string) { return this.store.deleteDashboard(id); }
}

/** SQL schema for creating workspace tables */
export const SCHEMA_SQL = `
CREATE TABLE IF NOT EXISTS research (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  content TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'draft',
  tags TEXT NOT NULL DEFAULT '[]',
  source_url TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS cron_jobs (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  command TEXT NOT NULL,
  schedule TEXT NOT NULL,
  last_run TEXT,
  last_status TEXT,
  last_output TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'active',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS decisions (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  context TEXT NOT NULL DEFAULT '',
  decision TEXT NOT NULL DEFAULT '',
  rationale TEXT NOT NULL DEFAULT '',
  tags TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS dashboards (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  config TEXT NOT NULL DEFAULT '{}',
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
`;
