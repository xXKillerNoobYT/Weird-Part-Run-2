/**
 * Local Job Service — offline job CRUD and status management.
 *
 * Mirrors the core of backend/app/services/job_service.py for field workers.
 * Supports: create, list, detail, update, status transitions.
 * NOT ported: cost tracking aggregation, bill rate management (shop-only).
 */

import { getDb } from '../db';
import { BaseRepo } from '../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

export interface JobCreate {
  job_name: string;
  job_number?: string;
  customer_name?: string;
  address_line1?: string;
  address_line2?: string;
  city?: string;
  state?: string;
  zip?: string;
  gps_lat?: number;
  gps_lng?: number;
  job_type?: string;
  priority?: string;
  lead_user_id?: number;
  start_date?: string;
  due_date?: string;
  notes?: string;
  bill_rate_type_id?: number;
}

export interface JobUpdate {
  job_name?: string;
  customer_name?: string;
  address_line1?: string;
  address_line2?: string;
  city?: string;
  state?: string;
  zip?: string;
  gps_lat?: number;
  gps_lng?: number;
  job_type?: string;
  priority?: string;
  lead_user_id?: number;
  start_date?: string;
  due_date?: string;
  notes?: string;
  status?: string;
  bill_rate_type_id?: number;
}

export interface Job {
  id: number;
  job_number: string;
  job_name: string;
  customer_name: string | null;
  address_line1: string | null;
  address_line2: string | null;
  city: string | null;
  state: string | null;
  zip: string | null;
  gps_lat: number | null;
  gps_lng: number | null;
  status: string;
  job_type: string;
  priority: string;
  lead_user_id: number | null;
  bill_rate_type_id: number | null;
  start_date: string | null;
  due_date: string | null;
  completed_date: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
  // Aggregated fields (computed at query time)
  total_labor_hours?: number;
  active_workers?: number;
  open_task_count?: number;
}

const VALID_STATUSES = [
  'pending', 'active', 'on_hold', 'completed', 'cancelled',
  'continuous_maintenance', 'on_call',
];

const jobRepo = new BaseRepo('jobs');

// ── Service Functions ──────────────────────────────────────────────

/** Create a new job */
export async function createJob(data: JobCreate, userId: number): Promise<Job> {
  const db = await getDb();

  // Generate job number if not provided
  let jobNumber = data.job_number;
  if (!jobNumber) {
    const countResult = await db.query('SELECT COUNT(*) as cnt FROM jobs');
    const count = (countResult.values[0]?.cnt ?? 0) + 1;
    jobNumber = `J-${String(count).padStart(4, '0')}`;
  }

  const insertData: Record<string, any> = {
    job_number: jobNumber,
    job_name: data.job_name,
    customer_name: data.customer_name ?? null,
    address_line1: data.address_line1 ?? null,
    address_line2: data.address_line2 ?? null,
    city: data.city ?? null,
    state: data.state ?? null,
    zip: data.zip ?? null,
    gps_lat: data.gps_lat ?? null,
    gps_lng: data.gps_lng ?? null,
    status: 'pending',
    job_type: data.job_type ?? 'service',
    priority: data.priority ?? 'normal',
    lead_user_id: data.lead_user_id ?? null,
    bill_rate_type_id: data.bill_rate_type_id ?? null,
    start_date: data.start_date ?? null,
    due_date: data.due_date ?? null,
    notes: data.notes ?? null,
    created_by: userId,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  const jobId = await jobRepo.insert(insertData);
  return (await getJob(jobId))!;
}

/** Get a job by ID with aggregated data */
export async function getJob(jobId: number): Promise<Job | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT j.*,
       COALESCE(
         (SELECT SUM(le.regular_hours + le.overtime_hours)
          FROM labor_entries le WHERE le.job_id = j.id AND le.clock_out IS NOT NULL), 0
       ) as total_labor_hours,
       (SELECT COUNT(*) FROM labor_entries le
        WHERE le.job_id = j.id AND le.status = 'clocked_in') as active_workers,
       (SELECT COUNT(*) FROM notebook_entries ne
        JOIN notebook_sections ns ON ns.id = ne.section_id
        JOIN notebooks nb ON nb.id = ns.notebook_id
        WHERE nb.job_id = j.id AND ne.entry_type = 'task'
          AND ne.task_status != 'done' AND ne.is_deleted = 0) as open_task_count
     FROM jobs j WHERE j.id = ?`,
    [jobId],
  );
  return (result.values[0] as Job) ?? null;
}

/** List active jobs with optional filters */
export async function getActiveJobs(opts?: {
  search?: string;
  status?: string;
  job_type?: string;
  priority?: string;
  sort_by?: string;
  sort_dir?: string;
  limit?: number;
  offset?: number;
}): Promise<{ items: Job[]; total: number }> {
  const db = await getDb();
  const conditions: string[] = [];
  const params: any[] = [];

  // Default: exclude completed/cancelled
  if (opts?.status) {
    conditions.push('j.status = ?');
    params.push(opts.status);
  } else {
    conditions.push("j.status NOT IN ('completed', 'cancelled')");
  }

  if (opts?.search) {
    conditions.push('(j.job_name LIKE ? OR j.job_number LIKE ? OR j.customer_name LIKE ?)');
    const term = `%${opts.search}%`;
    params.push(term, term, term);
  }

  if (opts?.job_type) {
    conditions.push('j.job_type = ?');
    params.push(opts.job_type);
  }

  if (opts?.priority) {
    conditions.push('j.priority = ?');
    params.push(opts.priority);
  }

  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
  const sortBy = opts?.sort_by ?? 'created_at';
  const sortDir = opts?.sort_dir === 'asc' ? 'ASC' : 'DESC';
  const limit = opts?.limit ?? 100;
  const offset = opts?.offset ?? 0;

  // Count total
  const countResult = await db.query(
    `SELECT COUNT(*) as cnt FROM jobs j ${where}`,
    params,
  );
  const total = countResult.values[0]?.cnt ?? 0;

  // Fetch page
  const result = await db.query(
    `SELECT j.*,
       COALESCE(
         (SELECT SUM(le.regular_hours + le.overtime_hours)
          FROM labor_entries le WHERE le.job_id = j.id AND le.clock_out IS NOT NULL), 0
       ) as total_labor_hours,
       (SELECT COUNT(*) FROM labor_entries le
        WHERE le.job_id = j.id AND le.status = 'clocked_in') as active_workers
     FROM jobs j ${where}
     ORDER BY j.${sortBy} ${sortDir}
     LIMIT ? OFFSET ?`,
    [...params, limit, offset],
  );

  return { items: result.values as Job[], total };
}

/** Update job fields */
export async function updateJob(jobId: number, data: JobUpdate): Promise<Job | null> {
  const updateData: Record<string, any> = { ...data, updated_at: new Date().toISOString() };
  const updated = await jobRepo.update(jobId, updateData);
  if (!updated) return null;
  return getJob(jobId);
}

/** Update job status with business logic */
export async function updateJobStatus(jobId: number, newStatus: string): Promise<Job | null> {
  if (!VALID_STATUSES.includes(newStatus)) {
    throw new Error(`Invalid job status: ${newStatus}`);
  }

  const updateData: Record<string, any> = {
    status: newStatus,
    updated_at: new Date().toISOString(),
  };

  // Auto-set completed_date when completing/cancelling
  if (newStatus === 'completed' || newStatus === 'cancelled') {
    updateData.completed_date = new Date().toISOString();
  }

  await jobRepo.update(jobId, updateData);
  return getJob(jobId);
}

/** Get jobs assigned to a specific user (as lead) */
export async function getMyJobs(userId: number): Promise<Job[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT j.* FROM jobs j
     WHERE j.lead_user_id = ? AND j.status NOT IN ('completed', 'cancelled')
     ORDER BY j.priority DESC, j.created_at DESC`,
    [userId],
  );
  return result.values as Job[];
}

/** Get jobs where the user is currently clocked in */
export async function getJobsWithActiveClock(userId: number): Promise<Job[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT j.* FROM jobs j
     JOIN labor_entries le ON le.job_id = j.id
     WHERE le.user_id = ? AND le.status = 'clocked_in'`,
    [userId],
  );
  return result.values as Job[];
}
