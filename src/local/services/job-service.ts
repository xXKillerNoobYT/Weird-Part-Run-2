/**
 * Local Job Service — offline job CRUD, team, parts consumption,
 * questions, reports, preferences, and supplier assignments.
 *
 * Mirrors backend/app/services/job_service.py + job_preferences_service.py.
 * Covers everything a field worker needs to operate fully offline.
 */

import { getDb } from '../db';
import { trackChange } from '../change-tracker';
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


// =================================================================
// BILL RATE TYPES
// =================================================================

export interface BillRateType {
  id: number;
  name: string;
  description: string | null;
  sort_order: number;
  is_active: number;
  created_at: string;
}

const brtRepo = new BaseRepo('bill_rate_types');

/** List bill rate types for dropdowns */
export async function getBillRateTypes(activeOnly: boolean = true): Promise<BillRateType[]> {
  const db = await getDb();
  const where = activeOnly ? 'WHERE is_active = 1' : '';
  const result = await db.query(
    `SELECT * FROM bill_rate_types ${where} ORDER BY sort_order, name`,
  );
  return result.values as BillRateType[];
}

/** Create a new bill rate type */
export async function createBillRateType(data: {
  name: string;
  description?: string;
  sort_order?: number;
}): Promise<BillRateType> {
  const id = await brtRepo.insert({
    name: data.name,
    description: data.description ?? null,
    sort_order: data.sort_order ?? 0,
    is_active: 1,
    created_at: new Date().toISOString(),
  });
  return (await brtRepo.getById(id)) as BillRateType;
}

/** Update a bill rate type */
export async function updateBillRateType(
  id: number,
  data: { name?: string; description?: string; sort_order?: number; is_active?: boolean },
): Promise<BillRateType> {
  const updateData: Record<string, any> = {};
  if (data.name !== undefined) updateData.name = data.name;
  if (data.description !== undefined) updateData.description = data.description;
  if (data.sort_order !== undefined) updateData.sort_order = data.sort_order;
  if (data.is_active !== undefined) updateData.is_active = data.is_active ? 1 : 0;
  await brtRepo.update(id, updateData);
  return (await brtRepo.getById(id)) as BillRateType;
}

/** Deactivate (soft-delete) a bill rate type */
export async function deleteBillRateType(id: number): Promise<void> {
  await brtRepo.update(id, { is_active: 0 });
}


// =================================================================
// PARTS CONSUMPTION
// =================================================================

export interface JobPart {
  id: number;
  job_id: number;
  part_id: number;
  qty_consumed: number;
  qty_returned: number;
  unit_cost_at_consume: number | null;
  unit_sell_at_consume: number | null;
  consumed_by: number | null;
  consumed_at: string;
  notes: string | null;
  // Joined fields
  part_number?: string;
  part_description?: string;
  user_name?: string;
}

/** List parts consumed on a job */
export async function getJobParts(jobId: number): Promise<JobPart[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT jp.*, p.part_number, p.description as part_description,
            u.display_name as user_name
     FROM job_parts jp
     LEFT JOIN parts p ON p.id = jp.part_id
     LEFT JOIN users u ON u.id = jp.consumed_by
     WHERE jp.job_id = ?
     ORDER BY jp.consumed_at DESC`,
    [jobId],
  );
  return result.values as JobPart[];
}

/** Record part consumption on a job */
export async function consumePart(
  jobId: number,
  data: { part_id: number; qty: number; notes?: string },
  userId: number,
): Promise<JobPart> {
  const db = await getDb();
  const now = new Date().toISOString();

  // Get current pricing
  const partResult = await db.query(
    'SELECT sell_price, cost_price FROM parts WHERE id = ?',
    [data.part_id],
  );
  const part = partResult.values[0] as any;

  const insertData = {
    job_id: jobId,
    part_id: data.part_id,
    qty_consumed: data.qty,
    qty_returned: 0,
    unit_cost_at_consume: part?.cost_price ?? null,
    unit_sell_at_consume: part?.sell_price ?? null,
    consumed_by: userId,
    consumed_at: now,
    notes: data.notes ?? null,
  };

  const jpRepo = new BaseRepo('job_parts');
  const id = await jpRepo.insert(insertData);

  // Decrement stock from default location (truck or main warehouse)
  await db.run(
    `UPDATE stock SET qty_on_hand = MAX(0, qty_on_hand - ?)
     WHERE part_id = ? AND location_id = (
       SELECT id FROM stock_locations WHERE is_default = 1 LIMIT 1
     )`,
    [data.qty, data.part_id],
  );

  await trackChange('job_parts', id, 'INSERT', { job_id: jobId, part_id: data.part_id });

  const result = await db.query('SELECT * FROM job_parts WHERE id = ?', [id]);
  return result.values[0] as JobPart;
}


// =================================================================
// GLOBAL CLOCK-OUT QUESTIONS
// =================================================================

export interface ClockOutQuestion {
  id: number;
  question_text: string;
  answer_type: string;
  is_required: number;
  sort_order: number;
  is_active: number;
  created_by: number | null;
  created_at: string;
  updated_at: string;
}

/** List global clock-out questions */
export async function getGlobalQuestions(activeOnly: boolean = true): Promise<ClockOutQuestion[]> {
  const db = await getDb();
  const where = activeOnly ? 'WHERE is_active = 1' : '';
  const result = await db.query(
    `SELECT * FROM clock_out_questions ${where} ORDER BY sort_order, id`,
  );
  return result.values as ClockOutQuestion[];
}

/** Create a new global clock-out question */
export async function createGlobalQuestion(data: {
  question_text: string;
  answer_type?: string;
  is_required?: boolean;
  sort_order?: number;
}, userId: number): Promise<ClockOutQuestion> {
  const now = new Date().toISOString();
  const repo = new BaseRepo('clock_out_questions');
  const id = await repo.insert({
    question_text: data.question_text,
    answer_type: data.answer_type ?? 'text',
    is_required: data.is_required !== false ? 1 : 0,
    sort_order: data.sort_order ?? 0,
    is_active: 1,
    created_by: userId,
    created_at: now,
    updated_at: now,
  });
  return (await repo.getById(id)) as ClockOutQuestion;
}

/** Update a global clock-out question */
export async function updateGlobalQuestion(
  questionId: number,
  data: { question_text?: string; answer_type?: string; is_required?: boolean; sort_order?: number },
): Promise<ClockOutQuestion> {
  const repo = new BaseRepo('clock_out_questions');
  const updateData: Record<string, any> = { updated_at: new Date().toISOString() };
  if (data.question_text !== undefined) updateData.question_text = data.question_text;
  if (data.answer_type !== undefined) updateData.answer_type = data.answer_type;
  if (data.is_required !== undefined) updateData.is_required = data.is_required ? 1 : 0;
  if (data.sort_order !== undefined) updateData.sort_order = data.sort_order;
  await repo.update(questionId, updateData);
  return (await repo.getById(questionId)) as ClockOutQuestion;
}

/** Reorder global questions */
export async function reorderGlobalQuestions(orderedIds: number[]): Promise<void> {
  const db = await getDb();
  for (let i = 0; i < orderedIds.length; i++) {
    await db.run(
      'UPDATE clock_out_questions SET sort_order = ?, updated_at = ? WHERE id = ?',
      [i, new Date().toISOString(), orderedIds[i]],
    );
  }
}

/** Deactivate (soft-delete) a global question */
export async function deactivateGlobalQuestion(questionId: number): Promise<void> {
  const repo = new BaseRepo('clock_out_questions');
  await repo.update(questionId, { is_active: 0, updated_at: new Date().toISOString() });
}


// =================================================================
// ONE-TIME PER-JOB QUESTIONS
// =================================================================

export interface OneTimeQuestion {
  id: number;
  job_id: number;
  target_user_id: number | null;
  question_text: string;
  answer_type: string;
  status: string;
  created_by: number;
  answered_by: number | null;
  answer_text: string | null;
  answer_photo_path: string | null;
  shown_at_clock_in: number;
  created_at: string;
  answered_at: string | null;
}

/** List one-time questions for a job */
export async function getOneTimeQuestions(
  jobId: number,
  pendingOnly: boolean = false,
): Promise<OneTimeQuestion[]> {
  const db = await getDb();
  const conditions = ['job_id = ?'];
  if (pendingOnly) conditions.push("status = 'pending'");
  const result = await db.query(
    `SELECT * FROM one_time_questions WHERE ${conditions.join(' AND ')} ORDER BY created_at DESC`,
    [jobId],
  );
  return result.values as OneTimeQuestion[];
}

/** Create a one-time question for a job */
export async function createOneTimeQuestion(
  jobId: number,
  data: { question_text: string; answer_type?: string; target_user_id?: number },
  userId: number,
): Promise<OneTimeQuestion> {
  const repo = new BaseRepo('one_time_questions');
  const id = await repo.insert({
    job_id: jobId,
    target_user_id: data.target_user_id ?? null,
    question_text: data.question_text,
    answer_type: data.answer_type ?? 'text',
    status: 'pending',
    created_by: userId,
    shown_at_clock_in: 0,
    created_at: new Date().toISOString(),
  });
  await trackChange('one_time_questions', id, 'INSERT', { job_id: jobId });
  return (await repo.getById(id)) as OneTimeQuestion;
}

/** Answer a one-time question */
export async function answerOneTimeQuestion(
  questionId: number,
  answerText: string | null,
  userId: number,
): Promise<OneTimeQuestion> {
  const repo = new BaseRepo('one_time_questions');
  const now = new Date().toISOString();
  await repo.update(questionId, {
    status: 'answered',
    answer_text: answerText,
    answered_by: userId,
    answered_at: now,
  });
  await trackChange('one_time_questions', questionId, 'UPDATE', { status: 'answered' });
  return (await repo.getById(questionId)) as OneTimeQuestion;
}


// =================================================================
// CLOCK-OUT BUNDLE
// =================================================================

export interface ClockOutBundle {
  global_questions: ClockOutQuestion[];
  one_time_questions: OneTimeQuestion[];
  job: Job | null;
}

/** Get all questions for the clock-out flow */
export async function getClockOutBundle(jobId: number): Promise<ClockOutBundle> {
  const [globalQs, otQs, job] = await Promise.all([
    getGlobalQuestions(true),
    getOneTimeQuestions(jobId, true),
    getJob(jobId),
  ]);
  return {
    global_questions: globalQs,
    one_time_questions: otQs,
    job,
  };
}


// =================================================================
// DAILY REPORTS
// =================================================================

export interface DailyReport {
  id: number;
  job_id: number;
  report_date: string;
  report_json: string;
  status: string;
  generated_at: string;
  reviewed_by: number | null;
  reviewed_at: string | null;
  // Joined
  job_name?: string;
  job_number?: string;
}

/** List all daily reports across jobs */
export async function getAllReports(params?: {
  date_from?: string;
  date_to?: string;
}): Promise<DailyReport[]> {
  const db = await getDb();
  const conditions: string[] = [];
  const args: any[] = [];

  if (params?.date_from) {
    conditions.push('dr.report_date >= ?');
    args.push(params.date_from);
  }
  if (params?.date_to) {
    conditions.push('dr.report_date <= ?');
    args.push(params.date_to);
  }

  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
  const result = await db.query(
    `SELECT dr.*, j.job_name, j.job_number
     FROM daily_reports dr
     JOIN jobs j ON j.id = dr.job_id
     ${where}
     ORDER BY dr.report_date DESC`,
    args,
  );
  return result.values as DailyReport[];
}

/** List daily reports for a specific job */
export async function getJobReports(jobId: number): Promise<DailyReport[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT dr.*, j.job_name, j.job_number
     FROM daily_reports dr
     JOIN jobs j ON j.id = dr.job_id
     WHERE dr.job_id = ?
     ORDER BY dr.report_date DESC`,
    [jobId],
  );
  return result.values as DailyReport[];
}

/** Get full daily report for a specific job and date */
export async function getReport(jobId: number, reportDate: string): Promise<DailyReport | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT dr.*, j.job_name, j.job_number
     FROM daily_reports dr
     JOIN jobs j ON j.id = dr.job_id
     WHERE dr.job_id = ? AND dr.report_date = ?`,
    [jobId, reportDate],
  );
  return (result.values[0] as DailyReport) ?? null;
}

/** Generate a daily report locally (creates report_json from today's data) */
export async function generateReportsNow(targetDate?: string): Promise<DailyReport[]> {
  const db = await getDb();
  const date = targetDate ?? new Date().toISOString().split('T')[0];
  const now = new Date().toISOString();

  // Get jobs with labor entries on the target date
  const jobsResult = await db.query(
    `SELECT DISTINCT j.id, j.job_name, j.job_number
     FROM jobs j
     JOIN labor_entries le ON le.job_id = j.id
     WHERE le.clock_in >= ? AND le.clock_in < ?`,
    [`${date}T00:00:00`, `${date}T23:59:59`],
  );

  const reports: DailyReport[] = [];
  for (const job of jobsResult.values as any[]) {
    // Get labor for this job on this date
    const laborResult = await db.query(
      `SELECT le.*, u.display_name as user_name
       FROM labor_entries le
       JOIN users u ON u.id = le.user_id
       WHERE le.job_id = ? AND le.clock_in >= ? AND le.clock_in < ?`,
      [job.id, `${date}T00:00:00`, `${date}T23:59:59`],
    );

    const reportJson = JSON.stringify({
      date,
      job_id: job.id,
      job_name: job.job_name,
      labor_entries: laborResult.values,
      generated_at: now,
    });

    // Upsert
    await db.run(
      `INSERT INTO daily_reports (job_id, report_date, report_json, status, generated_at)
       VALUES (?, ?, ?, 'generated', ?)
       ON CONFLICT(job_id, report_date)
       DO UPDATE SET report_json = excluded.report_json, generated_at = excluded.generated_at`,
      [job.id, date, reportJson, now],
    );

    const inserted = await getReport(job.id, date);
    if (inserted) reports.push(inserted);
  }

  return reports;
}


// =================================================================
// JOB PREFERENCES (Smart Suggestions)
// =================================================================

export interface JobPreference {
  id: number;
  job_id: number;
  preference_type: string;
  entity_id: number | null;
  text_value: string | null;
  category: string | null;
  is_active: number;
  auto_learned: number;
  confidence_score: number;
  last_used_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface JobPreferencesSummary {
  brands: { text_value: string; confidence: number }[];
  colors: { text_value: string; confidence: number }[];
  suppliers: { entity_id: number; text_value: string; confidence: number }[];
  parts: { entity_id: number; text_value: string; confidence: number }[];
}

/** Get all learned preferences for a job */
export async function getJobPreferences(
  jobId: number,
  params?: { preference_type?: string; category?: string },
): Promise<JobPreference[]> {
  const db = await getDb();
  const conditions = ['jp.job_id = ?', 'jp.deleted_at IS NULL'];
  const args: any[] = [jobId];

  if (params?.preference_type) {
    conditions.push('jp.preference_type = ?');
    args.push(params.preference_type);
  }
  if (params?.category) {
    conditions.push('jp.category = ?');
    args.push(params.category);
  }

  const result = await db.query(
    `SELECT jp.* FROM job_preferences jp
     WHERE ${conditions.join(' AND ')}
     ORDER BY jp.confidence_score DESC`,
    args,
  );
  return result.values as JobPreference[];
}

/** Get ranked smart suggestions for the unified order form */
export async function getJobSuggestions(
  jobId: number,
  category?: string,
): Promise<JobPreferencesSummary> {
  const prefs = await getJobPreferences(jobId, {
    ...(category ? { category } : {}),
  });

  const activePrefs = prefs.filter((p) => p.is_active);

  return {
    brands: activePrefs
      .filter((p) => p.preference_type === 'brand')
      .map((p) => ({ text_value: p.text_value ?? '', confidence: p.confidence_score })),
    colors: activePrefs
      .filter((p) => p.preference_type === 'color')
      .map((p) => ({ text_value: p.text_value ?? '', confidence: p.confidence_score })),
    suppliers: activePrefs
      .filter((p) => p.preference_type === 'supplier')
      .map((p) => ({ entity_id: p.entity_id ?? 0, text_value: p.text_value ?? '', confidence: p.confidence_score })),
    parts: activePrefs
      .filter((p) => p.preference_type === 'part')
      .map((p) => ({ entity_id: p.entity_id ?? 0, text_value: p.text_value ?? '', confidence: p.confidence_score })),
  };
}

/** Toggle a learned preference on or off */
export async function toggleJobPreference(
  jobId: number,
  prefId: number,
  toggle: { is_active: boolean },
): Promise<JobPreference> {
  const db = await getDb();
  const now = new Date().toISOString();
  await db.run(
    'UPDATE job_preferences SET is_active = ?, updated_at = ? WHERE id = ? AND job_id = ?',
    [toggle.is_active ? 1 : 0, now, prefId, jobId],
  );
  await trackChange('job_preferences', prefId, 'UPDATE', { is_active: toggle.is_active ? 1 : 0 });
  const result = await db.query('SELECT * FROM job_preferences WHERE id = ?', [prefId]);
  return result.values[0] as JobPreference;
}


// =================================================================
// EXPLICIT PREFERRED SUPPLIERS
// =================================================================

export interface ExplicitSupplier {
  id: number;
  job_id: number;
  supplier_id: number;
  rank: number;
  created_at: string;
  // Joined
  supplier_name?: string;
}

/** Get manually set preferred suppliers for a job (primary first, then backups) */
export async function getJobPreferredSuppliers(jobId: number): Promise<ExplicitSupplier[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT jps.*, s.name as supplier_name
     FROM job_preferred_suppliers jps
     LEFT JOIN suppliers s ON s.id = jps.supplier_id
     WHERE jps.job_id = ? AND jps.deleted_at IS NULL
     ORDER BY jps.rank ASC`,
    [jobId],
  );
  return result.values as ExplicitSupplier[];
}

/** Set explicit preferred suppliers for a job. First = primary, rest = backups. */
export async function setJobPreferredSuppliers(
  jobId: number,
  supplierIds: number[],
): Promise<{ id: number; supplier_id: number; rank: number }[]> {
  const db = await getDb();
  const now = new Date().toISOString();

  // Soft-delete existing
  await db.run(
    "UPDATE job_preferred_suppliers SET deleted_at = ? WHERE job_id = ? AND deleted_at IS NULL",
    [now, jobId],
  );

  // Insert new rankings
  const results: { id: number; supplier_id: number; rank: number }[] = [];
  for (let i = 0; i < supplierIds.length; i++) {
    const res = await db.run(
      `INSERT INTO job_preferred_suppliers (job_id, supplier_id, rank, created_at)
       VALUES (?, ?, ?, ?)`,
      [jobId, supplierIds[i], i, now],
    );
    const id = (res as any).lastInsertId ?? (res as any).changes?.lastId ?? 0;
    results.push({ id, supplier_id: supplierIds[i], rank: i });
    await trackChange('job_preferred_suppliers', id, 'INSERT', { job_id: jobId, supplier_id: supplierIds[i] });
  }

  return results;
}


// =================================================================
// JOB TEAM MEMBERS
// =================================================================

export interface JobTeamMember {
  id: number;
  job_id: number;
  user_id: number;
  role: string;
  assigned_at: string;
  assigned_by: number | null;
  notes: string | null;
  // Joined
  display_name?: string;
  email?: string;
}

/** List all employees assigned to a job's team */
export async function getJobTeam(jobId: number): Promise<JobTeamMember[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT jtm.*, u.display_name, u.email
     FROM job_team_members jtm
     JOIN users u ON u.id = jtm.user_id
     WHERE jtm.job_id = ? AND jtm.deleted_at IS NULL
     ORDER BY jtm.role DESC, u.display_name`,
    [jobId],
  );
  return result.values as JobTeamMember[];
}

/** Add an employee to a job's team */
export async function addJobTeamMember(
  jobId: number,
  data: { user_id: number; role?: string; notes?: string },
  assignedBy: number,
): Promise<JobTeamMember> {
  const db = await getDb();
  const now = new Date().toISOString();

  await db.run(
    `INSERT INTO job_team_members (job_id, user_id, role, assigned_at, assigned_by, notes)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT(job_id, user_id) DO UPDATE SET
       role = excluded.role, assigned_by = excluded.assigned_by,
       notes = excluded.notes, deleted_at = NULL`,
    [jobId, data.user_id, data.role ?? 'member', now, assignedBy, data.notes ?? null],
  );

  await trackChange('job_team_members', 0, 'INSERT', { job_id: jobId, user_id: data.user_id });

  const result = await db.query(
    `SELECT jtm.*, u.display_name, u.email
     FROM job_team_members jtm
     JOIN users u ON u.id = jtm.user_id
     WHERE jtm.job_id = ? AND jtm.user_id = ?`,
    [jobId, data.user_id],
  );
  return result.values[0] as JobTeamMember;
}

/** Remove a team member from a job (soft-delete) */
export async function removeJobTeamMember(jobId: number, memberId: number): Promise<void> {
  const db = await getDb();
  await db.run(
    'UPDATE job_team_members SET deleted_at = ? WHERE id = ? AND job_id = ?',
    [new Date().toISOString(), memberId, jobId],
  );
  await trackChange('job_team_members', memberId, 'DELETE', { job_id: jobId });
}
