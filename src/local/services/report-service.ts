/**
 * Local Report Service — annotations, share tokens, and saved templates.
 *
 * Mirrors backend report metadata management for offline use.
 * The actual report rendering happens in React components — this service
 * manages the supporting data (annotations, shared links, saved presets).
 *
 * Source tables: migration 011_reports_pto
 */

import { getDb } from '../db';
import { BaseRepo } from '../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

// --- Annotations ---

export interface AnnotationCreate {
  report_type: string;
  context_key: string;
  content: string;
  author_id: number;
}

export interface AnnotationUpdate {
  content?: string;
}

export interface ReportAnnotation {
  id: number;
  report_type: string;
  context_key: string;
  content: string;
  author_id: number;
  deleted_at: string | null;
  created_at: string;
  updated_at: string;
  author_name?: string;
}

// --- Share Tokens ---

export interface ShareTokenCreate {
  report_type: string;
  context_params: Record<string, any>;
  label?: string;
  created_by: number;
  expires_at?: string;
}

export interface ReportShareToken {
  id: number;
  token: string;
  report_type: string;
  context_params: string; // JSON
  label: string | null;
  created_by: number;
  expires_at: string | null;
  last_accessed_at: string | null;
  is_active: number;
  deleted_at: string | null;
  created_at: string;
  created_by_name?: string;
}

// --- Templates ---

export interface TemplateCreate {
  name: string;
  report_type: string;
  config_json: Record<string, any>;
  created_by: number;
}

export interface TemplateUpdate {
  name?: string;
  config_json?: Record<string, any>;
}

export interface ReportTemplate {
  id: number;
  name: string;
  report_type: string;
  config_json: string; // JSON
  created_by: number;
  deleted_at: string | null;
  created_at: string;
  updated_at: string;
  created_by_name?: string;
}

// ── Repos ──────────────────────────────────────────────────────────

const annotationRepo = new BaseRepo('report_annotations');
const tokenRepo = new BaseRepo('report_share_tokens');
const templateRepo = new BaseRepo('report_templates');

// ═══════════════════════════════════════════════════════════════════
// ANNOTATIONS
// ═══════════════════════════════════════════════════════════════════

/** Add an annotation to a report */
export async function createAnnotation(data: AnnotationCreate): Promise<ReportAnnotation> {
  const now = new Date().toISOString();
  const id = await annotationRepo.insert({
    report_type: data.report_type,
    context_key: data.context_key,
    content: data.content,
    author_id: data.author_id,
    created_at: now,
    updated_at: now,
  });
  return (await annotationRepo.getById(id)) as ReportAnnotation;
}

/** Get annotations for a specific report context */
export async function getAnnotations(
  reportType: string,
  contextKey: string,
): Promise<ReportAnnotation[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT ra.*, u.display_name as author_name
     FROM report_annotations ra
     LEFT JOIN users u ON u.id = ra.author_id
     WHERE ra.report_type = ? AND ra.context_key = ? AND ra.deleted_at IS NULL
     ORDER BY ra.created_at DESC`,
    [reportType, contextKey],
  );
  return result.values as ReportAnnotation[];
}

/** Update an annotation */
export async function updateAnnotation(
  id: number,
  data: AnnotationUpdate,
): Promise<ReportAnnotation | null> {
  const updated = await annotationRepo.update(id, {
    ...data,
    updated_at: new Date().toISOString(),
  });
  if (!updated) return null;
  return (await annotationRepo.getById(id)) as ReportAnnotation;
}

/** Soft-delete an annotation */
export async function deleteAnnotation(id: number): Promise<boolean> {
  return annotationRepo.update(id, { deleted_at: new Date().toISOString() });
}

// ═══════════════════════════════════════════════════════════════════
// SHARE TOKENS
// ═══════════════════════════════════════════════════════════════════

/** Generate a unique token string */
function generateToken(): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let token = '';
  for (let i = 0; i < 32; i++) {
    token += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return token;
}

/** Create a share token for a report */
export async function createShareToken(data: ShareTokenCreate): Promise<ReportShareToken> {
  const id = await tokenRepo.insert({
    token: generateToken(),
    report_type: data.report_type,
    context_params: JSON.stringify(data.context_params),
    label: data.label ?? null,
    created_by: data.created_by,
    expires_at: data.expires_at ?? null,
    is_active: 1,
    created_at: new Date().toISOString(),
  });
  return (await tokenRepo.getById(id)) as ReportShareToken;
}

/** Get a share token by token string */
export async function getShareTokenByValue(token: string): Promise<ReportShareToken | null> {
  const results = await tokenRepo.findAll(
    'token = ? AND deleted_at IS NULL',
    [token],
  );
  return (results[0] as ReportShareToken) ?? null;
}

/** List share tokens for a report type */
export async function listShareTokens(opts?: {
  report_type?: string;
  active_only?: boolean;
}): Promise<ReportShareToken[]> {
  const db = await getDb();
  const conditions: string[] = ['st.deleted_at IS NULL'];
  const params: any[] = [];

  if (opts?.report_type) {
    conditions.push('st.report_type = ?');
    params.push(opts.report_type);
  }
  if (opts?.active_only) {
    conditions.push('st.is_active = 1');
    conditions.push("(st.expires_at IS NULL OR st.expires_at > datetime('now'))");
  }

  const result = await db.query(
    `SELECT st.*, u.display_name as created_by_name
     FROM report_share_tokens st
     LEFT JOIN users u ON u.id = st.created_by
     WHERE ${conditions.join(' AND ')}
     ORDER BY st.created_at DESC`,
    params,
  );
  return result.values as ReportShareToken[];
}

/** Deactivate a share token */
export async function deactivateShareToken(id: number): Promise<boolean> {
  return tokenRepo.update(id, { is_active: 0 });
}

/** Record token access */
export async function recordTokenAccess(id: number): Promise<void> {
  await tokenRepo.update(id, {
    last_accessed_at: new Date().toISOString(),
  }, false); // Don't track this change for sync — it's a read indicator
}

// ═══════════════════════════════════════════════════════════════════
// REPORT TEMPLATES
// ═══════════════════════════════════════════════════════════════════

/** Create a report template */
export async function createTemplate(data: TemplateCreate): Promise<ReportTemplate> {
  const now = new Date().toISOString();
  const id = await templateRepo.insert({
    name: data.name,
    report_type: data.report_type,
    config_json: JSON.stringify(data.config_json),
    created_by: data.created_by,
    created_at: now,
    updated_at: now,
  });
  return (await templateRepo.getById(id)) as ReportTemplate;
}

/** List templates for a report type */
export async function listTemplates(reportType?: string): Promise<ReportTemplate[]> {
  const db = await getDb();
  const conditions: string[] = ['rt.deleted_at IS NULL'];
  const params: any[] = [];

  if (reportType) {
    conditions.push('rt.report_type = ?');
    params.push(reportType);
  }

  const result = await db.query(
    `SELECT rt.*, u.display_name as created_by_name
     FROM report_templates rt
     LEFT JOIN users u ON u.id = rt.created_by
     WHERE ${conditions.join(' AND ')}
     ORDER BY rt.name ASC`,
    params,
  );
  return result.values as ReportTemplate[];
}

/** Update a template */
export async function updateTemplate(
  id: number,
  data: TemplateUpdate,
): Promise<ReportTemplate | null> {
  const updateData: Record<string, any> = {
    updated_at: new Date().toISOString(),
  };
  if (data.name !== undefined) updateData.name = data.name;
  if (data.config_json !== undefined) updateData.config_json = JSON.stringify(data.config_json);

  const updated = await templateRepo.update(id, updateData);
  if (!updated) return null;
  return (await templateRepo.getById(id)) as ReportTemplate;
}

/** Soft-delete a template */
export async function deleteTemplate(id: number): Promise<boolean> {
  return templateRepo.update(id, { deleted_at: new Date().toISOString() });
}

// ═══════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════

/** Run a SELECT query, returning [] if the table doesn't exist yet. */
async function safeSelect<T = Record<string, any>>(
  sql: string,
  params: any[] = [],
): Promise<T[]> {
  const db = await getDb();
  try {
    const result = await db.query(sql, params);
    return (result.values ?? []) as T[];
  } catch {
    return [];
  }
}

/** Run a scalar query returning a single numeric value, 0 on failure. */
async function safeScalar(sql: string, params: any[] = []): Promise<number> {
  const db = await getDb();
  try {
    const result = await db.query(sql, params);
    const row = result.values?.[0];
    if (!row) return 0;
    const val = Object.values(row)[0];
    return typeof val === 'number' ? val : 0;
  } catch {
    return 0;
  }
}

/**
 * Compute regular vs overtime for a set of labor entries grouped by employee+date.
 * Rule: >8 hours in a single day = overtime for that employee.
 * Returns entries with recalculated regular_hours / overtime_hours.
 */
function computeOvertimeForEntries<T extends { user_id?: number; employee_id?: number; date: string; total_hours: number }>(
  entries: T[],
): (T & { regular_hours: number; overtime_hours: number })[] {
  // Group by employee+date
  const dayMap = new Map<string, T[]>();
  for (const e of entries) {
    const empId = (e as any).user_id ?? (e as any).employee_id ?? 0;
    const key = `${empId}|${e.date}`;
    const arr = dayMap.get(key) ?? [];
    arr.push(e);
    dayMap.set(key, arr);
  }

  const result: (T & { regular_hours: number; overtime_hours: number })[] = [];

  for (const group of Array.from(dayMap.values())) {
    const dayTotal = group.reduce((s, e) => s + e.total_hours, 0);
    const overtimeTotal = Math.max(0, dayTotal - 8);
    const regularTotal = dayTotal - overtimeTotal;

    // Distribute proportionally across entries
    for (const e of group) {
      const pct = dayTotal > 0 ? e.total_hours / dayTotal : 0;
      result.push({
        ...e,
        regular_hours: Math.round(regularTotal * pct * 100) / 100,
        overtime_hours: Math.round(overtimeTotal * pct * 100) / 100,
      });
    }
  }

  return result;
}

/** Convert an array of objects to CSV text */
function toCsv(rows: Record<string, any>[]): string {
  if (rows.length === 0) return '';
  const headers = Object.keys(rows[0]);
  const lines = [
    headers.join(','),
    ...rows.map(row =>
      headers.map(h => {
        const val = row[h];
        if (val == null) return '';
        const str = String(val);
        // Escape fields containing commas, quotes, or newlines
        if (str.includes(',') || str.includes('"') || str.includes('\n')) {
          return `"${str.replace(/"/g, '""')}"`;
        }
        return str;
      }).join(','),
    ),
  ];
  return lines.join('\n');
}


// ═══════════════════════════════════════════════════════════════════
// PRE-BILLING
// ═══════════════════════════════════════════════════════════════════

export interface PreBillingJobSummary {
  job_id: number;
  job_number: string;
  job_name: string;
  total_labor_hours: number;
  total_parts_cost: number;
  total_parts_sell: number;
  budget_limit: number | null;
  budget_used_pct: number | null;
}

/** All-jobs pre-billing summary for a date range */
export async function getPreBillingAllJobs(params: {
  start_date: string;
  end_date: string;
}): Promise<PreBillingJobSummary[]> {
  const { start_date, end_date } = params;

  // Get active jobs with their labor hours in range
  const jobs = await safeSelect<{
    id: number;
    job_number: string;
    job_name: string;
    estimated_hours: number | null;
  }>(
    `SELECT id, job_number, job_name, estimated_hours
     FROM jobs
     WHERE status IN ('active', 'on_hold', 'continuous_maintenance', 'on_call')
       AND deleted_at IS NULL
     ORDER BY job_number`,
  );

  const summaries: PreBillingJobSummary[] = [];

  for (const job of jobs) {
    // Sum labor hours for this job in date range
    const laborHours = await safeScalar(
      `SELECT COALESCE(SUM(regular_hours + overtime_hours), 0)
       FROM labor_entries
       WHERE job_id = ? AND date(clock_in) >= ? AND date(clock_in) <= ?
         AND status != 'clocked_in'`,
      [job.id, start_date, end_date],
    );

    // Sum parts costs for this job in date range (from job_parts)
    const partsRow = await safeSelect<{ cost: number; sell: number }>(
      `SELECT
         COALESCE(SUM(qty_consumed * COALESCE(unit_cost_at_consume, 0)), 0) as cost,
         COALESCE(SUM(qty_consumed * COALESCE(unit_sell_at_consume, 0)), 0) as sell
       FROM job_parts
       WHERE job_id = ? AND date(consumed_at) >= ? AND date(consumed_at) <= ?`,
      [job.id, start_date, end_date],
    );

    const partsCost = partsRow[0]?.cost ?? 0;
    const partsSell = partsRow[0]?.sell ?? 0;
    const budgetLimit = job.estimated_hours ?? null;
    const budgetUsedPct = budgetLimit && budgetLimit > 0
      ? Math.round((laborHours / budgetLimit) * 10000) / 100
      : null;

    summaries.push({
      job_id: job.id,
      job_number: job.job_number,
      job_name: job.job_name,
      total_labor_hours: Math.round(laborHours * 100) / 100,
      total_parts_cost: Math.round(partsCost * 100) / 100,
      total_parts_sell: Math.round(partsSell * 100) / 100,
      budget_limit: budgetLimit,
      budget_used_pct: budgetUsedPct,
    });
  }

  return summaries;
}

export interface PreBillingLaborEntry {
  employee_id: number;
  employee: string;
  date: string;
  clock_in: string | null;
  clock_out: string | null;
  regular_hours: number;
  overtime_hours: number;
  total_hours: number;
  bill_rate_type: string | null;
}

export interface PreBillingPartItem {
  part_id: number;
  part_name: string;
  part_code: string | null;
  qty: number;
  unit_cost: number;
  sell_price: number;
  total_cost: number;
  total_sell: number;
}

export interface PreBillingMovement {
  date: string;
  part_name: string;
  from_location: string | null;
  to_location: string | null;
  qty: number;
  movement_type: string;
}

export interface PreBillingSummary {
  total_labor_hours: number;
  total_regular_hours: number;
  total_overtime_hours: number;
  total_parts_cost: number;
  total_parts_sell: number;
  budget_limit: number | null;
  budget_used_pct: number | null;
}

export interface PreBillingBundle {
  job_id: number;
  job_name: string;
  job_number: string;
  bill_rate_type: string | null;
  period_start: string;
  period_end: string;
  labor: PreBillingLaborEntry[];
  parts: PreBillingPartItem[];
  movements: PreBillingMovement[];
  summary: PreBillingSummary;
}

/** Pre-billing bundle for a single job + date range */
export async function getPreBilling(params: {
  job_id: number;
  start_date: string;
  end_date: string;
}): Promise<PreBillingBundle> {
  const { job_id, start_date, end_date } = params;

  // Job info
  const jobRows = await safeSelect<{
    job_name: string;
    job_number: string;
    estimated_hours: number | null;
    bill_rate_type_id: number | null;
  }>(
    `SELECT j.job_name, j.job_number, j.estimated_hours, j.bill_rate_type_id
     FROM jobs j WHERE j.id = ?`,
    [job_id],
  );
  const job = jobRows[0] ?? { job_name: '', job_number: '', estimated_hours: null, bill_rate_type_id: null };

  // Bill rate type name
  let billRateType: string | null = null;
  if (job.bill_rate_type_id) {
    const brtRows = await safeSelect<{ name: string }>(
      'SELECT name FROM bill_rate_types WHERE id = ?',
      [job.bill_rate_type_id],
    );
    billRateType = brtRows[0]?.name ?? null;
  }

  // Labor entries
  const rawLabor = await safeSelect<{
    user_id: number;
    display_name: string;
    date: string;
    clock_in: string;
    clock_out: string | null;
    total_hours: number;
    bill_rate_name: string | null;
  }>(
    `SELECT
       le.user_id,
       COALESCE(u.display_name, 'Unknown') as display_name,
       date(le.clock_in) as date,
       le.clock_in,
       le.clock_out,
       (le.regular_hours + le.overtime_hours) as total_hours,
       brt.name as bill_rate_name
     FROM labor_entries le
     LEFT JOIN users u ON u.id = le.user_id
     LEFT JOIN jobs j ON j.id = le.job_id
     LEFT JOIN bill_rate_types brt ON brt.id = j.bill_rate_type_id
     WHERE le.job_id = ? AND date(le.clock_in) >= ? AND date(le.clock_in) <= ?
       AND le.status != 'clocked_in'
     ORDER BY le.clock_in`,
    [job_id, start_date, end_date],
  );

  // Compute OT per employee per day
  const laborWithOT = computeOvertimeForEntries(rawLabor);

  const labor: PreBillingLaborEntry[] = laborWithOT.map(e => ({
    employee_id: e.user_id,
    employee: e.display_name,
    date: e.date,
    clock_in: e.clock_in,
    clock_out: e.clock_out,
    regular_hours: e.regular_hours,
    overtime_hours: e.overtime_hours,
    total_hours: e.total_hours,
    bill_rate_type: e.bill_rate_name,
  }));

  // Parts consumed on this job in date range
  const parts = await safeSelect<PreBillingPartItem>(
    `SELECT
       jp.part_id,
       p.name as part_name,
       p.code as part_code,
       jp.qty_consumed as qty,
       COALESCE(jp.unit_cost_at_consume, 0) as unit_cost,
       COALESCE(jp.unit_sell_at_consume, 0) as sell_price,
       (jp.qty_consumed * COALESCE(jp.unit_cost_at_consume, 0)) as total_cost,
       (jp.qty_consumed * COALESCE(jp.unit_sell_at_consume, 0)) as total_sell
     FROM job_parts jp
     LEFT JOIN parts p ON p.id = jp.part_id
     WHERE jp.job_id = ? AND date(jp.consumed_at) >= ? AND date(jp.consumed_at) <= ?
     ORDER BY jp.consumed_at`,
    [job_id, start_date, end_date],
  );

  // Stock movements for this job in date range
  const movements = await safeSelect<PreBillingMovement>(
    `SELECT
       date(sm.created_at) as date,
       p.name as part_name,
       sm.from_location_type as from_location,
       sm.to_location_type as to_location,
       sm.qty,
       sm.movement_type
     FROM stock_movements sm
     LEFT JOIN parts p ON p.id = sm.part_id
     WHERE sm.job_id = ? AND date(sm.created_at) >= ? AND date(sm.created_at) <= ?
     ORDER BY sm.created_at`,
    [job_id, start_date, end_date],
  );

  // Summary
  const totalLaborHours = labor.reduce((s, e) => s + e.total_hours, 0);
  const totalRegularHours = labor.reduce((s, e) => s + e.regular_hours, 0);
  const totalOvertimeHours = labor.reduce((s, e) => s + e.overtime_hours, 0);
  const totalPartsCost = parts.reduce((s, p) => s + p.total_cost, 0);
  const totalPartsSell = parts.reduce((s, p) => s + p.total_sell, 0);
  const budgetLimit = job.estimated_hours ?? null;
  const budgetUsedPct = budgetLimit && budgetLimit > 0
    ? Math.round((totalLaborHours / budgetLimit) * 10000) / 100
    : null;

  return {
    job_id,
    job_name: job.job_name,
    job_number: job.job_number,
    bill_rate_type: billRateType,
    period_start: start_date,
    period_end: end_date,
    labor,
    parts,
    movements,
    summary: {
      total_labor_hours: Math.round(totalLaborHours * 100) / 100,
      total_regular_hours: Math.round(totalRegularHours * 100) / 100,
      total_overtime_hours: Math.round(totalOvertimeHours * 100) / 100,
      total_parts_cost: Math.round(totalPartsCost * 100) / 100,
      total_parts_sell: Math.round(totalPartsSell * 100) / 100,
      budget_limit: budgetLimit,
      budget_used_pct: budgetUsedPct,
    },
  };
}


// ═══════════════════════════════════════════════════════════════════
// TIMESHEETS
// ═══════════════════════════════════════════════════════════════════

export interface TimesheetEntry {
  id: number;
  date: string;
  job_id: number;
  job_name: string;
  job_number: string;
  clock_in: string;
  clock_out: string | null;
  regular_hours: number;
  overtime_hours: number;
  total_hours: number;
  bill_rate_type: string | null;
  gps_in: { lat: number; lng: number } | null;
  gps_out: { lat: number; lng: number } | null;
}

export interface TimesheetDayGroup {
  date: string;
  entries: TimesheetEntry[];
  total_hours: number;
  regular_hours: number;
  overtime_hours: number;
}

export interface TimesheetSummary {
  total_hours: number;
  regular_hours: number;
  overtime_hours: number;
  days_worked: number;
  jobs_worked: number;
}

export interface TimesheetReport {
  employee_id: number | null;
  employee_name: string | null;
  period_start: string;
  period_end: string;
  group_by: string;
  entries: TimesheetEntry[];
  day_groups: TimesheetDayGroup[];
  summary: TimesheetSummary;
}

/** Employee timesheet for a date range */
export async function getTimesheets(params: {
  start_date: string;
  end_date: string;
  employee_id?: number;
  group_by?: string;
}): Promise<TimesheetReport> {
  const { start_date, end_date, employee_id, group_by = 'day' } = params;

  // Get employee name if filtered
  let employeeName: string | null = null;
  if (employee_id) {
    const empRows = await safeSelect<{ display_name: string }>(
      'SELECT display_name FROM users WHERE id = ?',
      [employee_id],
    );
    employeeName = empRows[0]?.display_name ?? null;
  }

  // Build conditions
  const conditions = [
    "date(le.clock_in) >= ?",
    "date(le.clock_in) <= ?",
    "le.status != 'clocked_in'",
  ];
  const queryParams: any[] = [start_date, end_date];

  if (employee_id) {
    conditions.push('le.user_id = ?');
    queryParams.push(employee_id);
  }

  const rawEntries = await safeSelect<{
    id: number;
    user_id: number;
    date: string;
    job_id: number;
    job_name: string;
    job_number: string;
    clock_in: string;
    clock_out: string | null;
    total_hours: number;
    bill_rate_name: string | null;
    clock_in_gps_lat: number | null;
    clock_in_gps_lng: number | null;
    clock_out_gps_lat: number | null;
    clock_out_gps_lng: number | null;
  }>(
    `SELECT
       le.id,
       le.user_id,
       date(le.clock_in) as date,
       le.job_id,
       COALESCE(j.job_name, 'Unknown') as job_name,
       COALESCE(j.job_number, '') as job_number,
       le.clock_in,
       le.clock_out,
       (le.regular_hours + le.overtime_hours) as total_hours,
       brt.name as bill_rate_name,
       le.clock_in_gps_lat,
       le.clock_in_gps_lng,
       le.clock_out_gps_lat,
       le.clock_out_gps_lng
     FROM labor_entries le
     LEFT JOIN jobs j ON j.id = le.job_id
     LEFT JOIN bill_rate_types brt ON brt.id = j.bill_rate_type_id
     WHERE ${conditions.join(' AND ')}
     ORDER BY le.clock_in`,
    queryParams,
  );

  // Compute OT per employee per day (>8h = OT)
  const withOT = computeOvertimeForEntries(rawEntries);

  const entries: TimesheetEntry[] = withOT.map(e => ({
    id: e.id,
    date: e.date,
    job_id: e.job_id,
    job_name: e.job_name,
    job_number: e.job_number,
    clock_in: e.clock_in,
    clock_out: e.clock_out,
    regular_hours: e.regular_hours,
    overtime_hours: e.overtime_hours,
    total_hours: e.total_hours,
    bill_rate_type: e.bill_rate_name,
    gps_in: e.clock_in_gps_lat != null && e.clock_in_gps_lng != null
      ? { lat: e.clock_in_gps_lat, lng: e.clock_in_gps_lng }
      : null,
    gps_out: e.clock_out_gps_lat != null && e.clock_out_gps_lng != null
      ? { lat: e.clock_out_gps_lat, lng: e.clock_out_gps_lng }
      : null,
  }));

  // Group by day
  const dayMap = new Map<string, TimesheetEntry[]>();
  for (const entry of entries) {
    const arr = dayMap.get(entry.date) ?? [];
    arr.push(entry);
    dayMap.set(entry.date, arr);
  }

  const day_groups: TimesheetDayGroup[] = Array.from(dayMap.entries())
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([date, dayEntries]) => {
      const total_hours = dayEntries.reduce((s, e) => s + e.total_hours, 0);
      const regular_hours = dayEntries.reduce((s, e) => s + e.regular_hours, 0);
      const overtime_hours = dayEntries.reduce((s, e) => s + e.overtime_hours, 0);
      return {
        date,
        entries: dayEntries,
        total_hours: Math.round(total_hours * 100) / 100,
        regular_hours: Math.round(regular_hours * 100) / 100,
        overtime_hours: Math.round(overtime_hours * 100) / 100,
      };
    });

  // Summary
  const totalHours = entries.reduce((s, e) => s + e.total_hours, 0);
  const regularHours = entries.reduce((s, e) => s + e.regular_hours, 0);
  const overtimeHours = entries.reduce((s, e) => s + e.overtime_hours, 0);
  const uniqueJobs = new Set(entries.map(e => e.job_id));

  return {
    employee_id: employee_id ?? null,
    employee_name: employeeName,
    period_start: start_date,
    period_end: end_date,
    group_by,
    entries,
    day_groups,
    summary: {
      total_hours: Math.round(totalHours * 100) / 100,
      regular_hours: Math.round(regularHours * 100) / 100,
      overtime_hours: Math.round(overtimeHours * 100) / 100,
      days_worked: dayMap.size,
      jobs_worked: uniqueJobs.size,
    },
  };
}


// ═══════════════════════════════════════════════════════════════════
// LABOR OVERVIEW
// ═══════════════════════════════════════════════════════════════════

export interface LaborByEmployee {
  employee_id: number;
  employee: string;
  total_hours: number;
  regular_hours: number;
  overtime_hours: number;
  jobs_worked: number;
  days_worked: number;
  avg_hours_per_day: number;
}

export interface LaborByJob {
  job_id: number;
  job_name: string;
  job_number: string;
  total_hours: number;
  employee_count: number;
}

export interface LaborByBillRate {
  rate_type: string;
  total_hours: number;
  entry_count: number;
}

export interface LaborOverviewTotals {
  total_hours: number;
  regular_hours: number;
  overtime_hours: number;
  total_employees: number;
  total_jobs: number;
  total_days: number;
}

export interface LaborOverviewReport {
  period_start: string;
  period_end: string;
  by_employee: LaborByEmployee[];
  by_job: LaborByJob[];
  by_bill_rate: LaborByBillRate[];
  totals: LaborOverviewTotals;
}

/** Cross-job labor overview for a date range */
export async function getLaborOverview(params: {
  start_date: string;
  end_date: string;
  job_id?: number;
}): Promise<LaborOverviewReport> {
  const { start_date, end_date, job_id } = params;

  const jobFilter = job_id ? 'AND le.job_id = ?' : '';
  const baseParams = job_id ? [start_date, end_date, job_id] : [start_date, end_date];

  // Raw entries for OT calculation
  const rawEntries = await safeSelect<{
    user_id: number;
    display_name: string;
    date: string;
    job_id: number;
    job_name: string;
    job_number: string;
    total_hours: number;
    bill_rate_name: string | null;
  }>(
    `SELECT
       le.user_id,
       COALESCE(u.display_name, 'Unknown') as display_name,
       date(le.clock_in) as date,
       le.job_id,
       COALESCE(j.job_name, '') as job_name,
       COALESCE(j.job_number, '') as job_number,
       (le.regular_hours + le.overtime_hours) as total_hours,
       brt.name as bill_rate_name
     FROM labor_entries le
     LEFT JOIN users u ON u.id = le.user_id
     LEFT JOIN jobs j ON j.id = le.job_id
     LEFT JOIN bill_rate_types brt ON brt.id = j.bill_rate_type_id
     WHERE date(le.clock_in) >= ? AND date(le.clock_in) <= ?
       AND le.status != 'clocked_in'
       ${jobFilter}
     ORDER BY le.clock_in`,
    baseParams,
  );

  // Apply OT calculation
  const withOT = computeOvertimeForEntries(rawEntries);

  // By Employee
  const empMap = new Map<number, {
    employee: string;
    totalHours: number;
    regularHours: number;
    overtimeHours: number;
    jobs: Set<number>;
    days: Set<string>;
  }>();

  for (const e of withOT) {
    const existing = empMap.get(e.user_id);
    if (existing) {
      existing.totalHours += e.total_hours;
      existing.regularHours += e.regular_hours;
      existing.overtimeHours += e.overtime_hours;
      existing.jobs.add(e.job_id);
      existing.days.add(e.date);
    } else {
      empMap.set(e.user_id, {
        employee: e.display_name,
        totalHours: e.total_hours,
        regularHours: e.regular_hours,
        overtimeHours: e.overtime_hours,
        jobs: new Set([e.job_id]),
        days: new Set([e.date]),
      });
    }
  }

  const by_employee: LaborByEmployee[] = Array.from(empMap.entries()).map(([id, d]) => ({
    employee_id: id,
    employee: d.employee,
    total_hours: Math.round(d.totalHours * 100) / 100,
    regular_hours: Math.round(d.regularHours * 100) / 100,
    overtime_hours: Math.round(d.overtimeHours * 100) / 100,
    jobs_worked: d.jobs.size,
    days_worked: d.days.size,
    avg_hours_per_day: d.days.size > 0
      ? Math.round((d.totalHours / d.days.size) * 100) / 100
      : 0,
  }));

  // By Job
  const jobMap = new Map<number, {
    job_name: string;
    job_number: string;
    totalHours: number;
    employees: Set<number>;
  }>();

  for (const e of withOT) {
    const existing = jobMap.get(e.job_id);
    if (existing) {
      existing.totalHours += e.total_hours;
      existing.employees.add(e.user_id);
    } else {
      jobMap.set(e.job_id, {
        job_name: e.job_name,
        job_number: e.job_number,
        totalHours: e.total_hours,
        employees: new Set([e.user_id]),
      });
    }
  }

  const by_job: LaborByJob[] = Array.from(jobMap.entries()).map(([id, d]) => ({
    job_id: id,
    job_name: d.job_name,
    job_number: d.job_number,
    total_hours: Math.round(d.totalHours * 100) / 100,
    employee_count: d.employees.size,
  }));

  // By Bill Rate
  const brMap = new Map<string, { totalHours: number; count: number }>();
  for (const e of withOT) {
    const rateType = e.bill_rate_name ?? 'Unassigned';
    const existing = brMap.get(rateType);
    if (existing) {
      existing.totalHours += e.total_hours;
      existing.count += 1;
    } else {
      brMap.set(rateType, { totalHours: e.total_hours, count: 1 });
    }
  }

  const by_bill_rate: LaborByBillRate[] = Array.from(brMap.entries()).map(([type, d]) => ({
    rate_type: type,
    total_hours: Math.round(d.totalHours * 100) / 100,
    entry_count: d.count,
  }));

  // Totals
  const allDays = new Set(withOT.map(e => e.date));
  const totalHours = withOT.reduce((s, e) => s + e.total_hours, 0);
  const regularHours = withOT.reduce((s, e) => s + e.regular_hours, 0);
  const overtimeHours = withOT.reduce((s, e) => s + e.overtime_hours, 0);

  return {
    period_start: start_date,
    period_end: end_date,
    by_employee,
    by_job,
    by_bill_rate,
    totals: {
      total_hours: Math.round(totalHours * 100) / 100,
      regular_hours: Math.round(regularHours * 100) / 100,
      overtime_hours: Math.round(overtimeHours * 100) / 100,
      total_employees: empMap.size,
      total_jobs: jobMap.size,
      total_days: allDays.size,
    },
  };
}


// ═══════════════════════════════════════════════════════════════════
// PROFITABILITY
// ═══════════════════════════════════════════════════════════════════

export interface JobProfitability {
  job_id: number;
  job_name: string;
  job_number: string;
  status: string;
  labor_hours: number;
  labor_cost: number;
  parts_cost: number;
  parts_sell: number;
  total_cost: number;
  parts_margin: number;
  budget_limit: number | null;
  budget_remaining: number | null;
  budget_utilization_pct: number | null;
}

export interface CompanyProfitabilityTotals {
  total_labor_cost: number;
  total_parts_cost: number;
  total_parts_sell: number;
  total_combined_cost: number;
  total_parts_margin: number;
  total_labor_hours: number;
  jobs_under_budget: number;
  jobs_over_budget: number;
  jobs_no_budget: number;
}

export interface ProfitabilityReport {
  period_start: string;
  period_end: string;
  by_job: JobProfitability[];
  totals: CompanyProfitabilityTotals;
}

/** Default assumed labor cost rate for profitability calculations */
const DEFAULT_LABOR_RATE = 50; // $/hr — placeholder, adjust as needed

/** Job profitability analysis for a date range */
export async function getProfitability(params: {
  start_date: string;
  end_date: string;
  job_id?: number;
}): Promise<ProfitabilityReport> {
  const { start_date, end_date, job_id } = params;

  const jobFilter = job_id ? 'AND j.id = ?' : '';
  const _jobParams = job_id
    ? [start_date, end_date, job_id]
    : [start_date, end_date];

  // Get all relevant jobs
  const jobs = await safeSelect<{
    id: number;
    job_name: string;
    job_number: string;
    status: string;
    estimated_hours: number | null;
    billing_rate: number | null;
  }>(
    `SELECT DISTINCT j.id, j.job_name, j.job_number, j.status,
            j.estimated_hours, j.billing_rate
     FROM jobs j
     WHERE j.deleted_at IS NULL ${jobFilter}
     ORDER BY j.job_number`,
    job_id ? [job_id] : [],
  );

  const by_job: JobProfitability[] = [];

  for (const job of jobs) {
    // Labor hours for this job in range
    const laborHours = await safeScalar(
      `SELECT COALESCE(SUM(regular_hours + overtime_hours), 0)
       FROM labor_entries
       WHERE job_id = ? AND date(clock_in) >= ? AND date(clock_in) <= ?
         AND status != 'clocked_in'`,
      [job.id, start_date, end_date],
    );

    // Parts cost/sell for this job in range
    const partsRow = await safeSelect<{ cost: number; sell: number }>(
      `SELECT
         COALESCE(SUM(qty_consumed * COALESCE(unit_cost_at_consume, 0)), 0) as cost,
         COALESCE(SUM(qty_consumed * COALESCE(unit_sell_at_consume, 0)), 0) as sell
       FROM job_parts
       WHERE job_id = ? AND date(consumed_at) >= ? AND date(consumed_at) <= ?`,
      [job.id, start_date, end_date],
    );

    const partsCost = partsRow[0]?.cost ?? 0;
    const partsSell = partsRow[0]?.sell ?? 0;

    // Skip jobs with no activity in this period (unless specifically requested)
    if (!job_id && laborHours === 0 && partsCost === 0) continue;

    const laborRate = job.billing_rate ?? DEFAULT_LABOR_RATE;
    const laborCost = laborHours * laborRate;
    const totalCost = laborCost + partsCost;
    const partsMargin = partsSell - partsCost;
    const budgetLimit = job.estimated_hours ?? null;
    const budgetRemaining = budgetLimit != null ? budgetLimit - laborHours : null;
    const budgetUtilPct = budgetLimit && budgetLimit > 0
      ? Math.round((laborHours / budgetLimit) * 10000) / 100
      : null;

    by_job.push({
      job_id: job.id,
      job_name: job.job_name,
      job_number: job.job_number,
      status: job.status,
      labor_hours: Math.round(laborHours * 100) / 100,
      labor_cost: Math.round(laborCost * 100) / 100,
      parts_cost: Math.round(partsCost * 100) / 100,
      parts_sell: Math.round(partsSell * 100) / 100,
      total_cost: Math.round(totalCost * 100) / 100,
      parts_margin: Math.round(partsMargin * 100) / 100,
      budget_limit: budgetLimit,
      budget_remaining: budgetRemaining != null ? Math.round(budgetRemaining * 100) / 100 : null,
      budget_utilization_pct: budgetUtilPct,
    });
  }

  // Totals
  const totalLaborCost = by_job.reduce((s, j) => s + j.labor_cost, 0);
  const totalPartsCost = by_job.reduce((s, j) => s + j.parts_cost, 0);
  const totalPartsSell = by_job.reduce((s, j) => s + j.parts_sell, 0);
  const totalLaborHours = by_job.reduce((s, j) => s + j.labor_hours, 0);

  let jobsUnder = 0, jobsOver = 0, jobsNoBudget = 0;
  for (const j of by_job) {
    if (j.budget_limit == null) jobsNoBudget++;
    else if (j.budget_utilization_pct != null && j.budget_utilization_pct > 100) jobsOver++;
    else jobsUnder++;
  }

  return {
    period_start: start_date,
    period_end: end_date,
    by_job,
    totals: {
      total_labor_cost: Math.round(totalLaborCost * 100) / 100,
      total_parts_cost: Math.round(totalPartsCost * 100) / 100,
      total_parts_sell: Math.round(totalPartsSell * 100) / 100,
      total_combined_cost: Math.round((totalLaborCost + totalPartsCost) * 100) / 100,
      total_parts_margin: Math.round((totalPartsSell - totalPartsCost) * 100) / 100,
      total_labor_hours: Math.round(totalLaborHours * 100) / 100,
      jobs_under_budget: jobsUnder,
      jobs_over_budget: jobsOver,
      jobs_no_budget: jobsNoBudget,
    },
  };
}


// ═══════════════════════════════════════════════════════════════════
// EXPORT GENERATION (LOCAL STUBS)
// ═══════════════════════════════════════════════════════════════════

/** Generate a CSV/PDF export blob locally. PDF falls back to CSV. */
export async function generateExport(params: {
  report_type: 'pre-billing' | 'timesheet' | 'labor-overview' | 'profitability';
  format: 'csv' | 'pdf';
  job_id?: number;
  employee_id?: number;
  start_date?: string;
  end_date?: string;
}): Promise<Blob> {
  const start = params.start_date ?? '2000-01-01';
  const end = params.end_date ?? '2099-12-31';

  let csvText = '';

  switch (params.report_type) {
    case 'pre-billing': {
      if (params.job_id) {
        const bundle = await getPreBilling({ job_id: params.job_id, start_date: start, end_date: end });
        // Labor sheet
        csvText += '=== LABOR ===\n';
        csvText += toCsv(bundle.labor);
        csvText += '\n\n=== PARTS ===\n';
        csvText += toCsv(bundle.parts);
        csvText += '\n\n=== MOVEMENTS ===\n';
        csvText += toCsv(bundle.movements);
        csvText += '\n\n=== SUMMARY ===\n';
        csvText += toCsv([bundle.summary as any]);
      } else {
        const allJobs = await getPreBillingAllJobs({ start_date: start, end_date: end });
        csvText = toCsv(allJobs);
      }
      break;
    }
    case 'timesheet': {
      const report = await getTimesheets({
        start_date: start,
        end_date: end,
        employee_id: params.employee_id,
      });
      csvText = toCsv(report.entries.map(e => ({
        date: e.date,
        job_number: e.job_number,
        job_name: e.job_name,
        clock_in: e.clock_in,
        clock_out: e.clock_out ?? '',
        regular_hours: e.regular_hours,
        overtime_hours: e.overtime_hours,
        total_hours: e.total_hours,
        bill_rate_type: e.bill_rate_type ?? '',
      })));
      break;
    }
    case 'labor-overview': {
      const report = await getLaborOverview({
        start_date: start,
        end_date: end,
        job_id: params.job_id,
      });
      csvText += '=== BY EMPLOYEE ===\n';
      csvText += toCsv(report.by_employee);
      csvText += '\n\n=== BY JOB ===\n';
      csvText += toCsv(report.by_job);
      csvText += '\n\n=== BY BILL RATE ===\n';
      csvText += toCsv(report.by_bill_rate);
      csvText += '\n\n=== TOTALS ===\n';
      csvText += toCsv([report.totals as any]);
      break;
    }
    case 'profitability': {
      const report = await getProfitability({
        start_date: start,
        end_date: end,
        job_id: params.job_id,
      });
      csvText = toCsv(report.by_job);
      csvText += '\n\n=== TOTALS ===\n';
      csvText += toCsv([report.totals as any]);
      break;
    }
  }

  return new Blob([csvText], { type: 'text/csv' });
}

/** Generate a bookkeeper-formatted export (QuickBooks, General Ledger, Payroll). */
export async function generateBookkeeperExport(params: {
  format: 'quickbooks' | 'general_ledger' | 'payroll';
  job_ids?: number[];
  period_start: string;
  period_end: string;
  include_labor?: boolean;
  include_parts?: boolean;
}): Promise<Blob> {
  const { format, job_ids, period_start, period_end, include_labor = true, include_parts = true } = params;

  const sections: string[] = [];

  // Determine which jobs to include
  const jobList = job_ids && job_ids.length > 0
    ? job_ids
    : (await safeSelect<{ id: number }>(
        `SELECT id FROM jobs WHERE deleted_at IS NULL ORDER BY job_number`,
      )).map(j => j.id);

  for (const jobId of jobList) {
    const bundle = await getPreBilling({ job_id: jobId, start_date: period_start, end_date: period_end });

    if (format === 'quickbooks') {
      // QuickBooks IIF-like CSV format
      if (include_labor && bundle.labor.length > 0) {
        sections.push(`!TIMEACT\tDATE\tJOB\tEMPLOYEE\tDURATION\tBILLABLESTATUS`);
        for (const entry of bundle.labor) {
          sections.push(`TIMEACT\t${entry.date}\t${bundle.job_number}\t${entry.employee}\t${entry.total_hours}\tBillable`);
        }
      }
      if (include_parts && bundle.parts.length > 0) {
        sections.push(`!TRNS\tDATE\tACCNT\tNAME\tAMOUNT\tMEMO`);
        for (const part of bundle.parts) {
          sections.push(`TRNS\t${period_end}\tCost of Goods\t${bundle.job_number}\t${part.total_cost}\t${part.part_name}`);
        }
      }
    } else if (format === 'general_ledger') {
      // General ledger format
      if (include_labor) {
        sections.push(`Date,Account,Description,Debit,Credit,Job`);
        for (const entry of bundle.labor) {
          const amount = Math.round(entry.total_hours * (bundle.bill_rate_type ? 50 : 50) * 100) / 100; // placeholder rate
          sections.push(`${entry.date},5000 - Labor,${entry.employee} - ${bundle.job_number},${amount},,${bundle.job_number}`);
        }
      }
      if (include_parts) {
        for (const part of bundle.parts) {
          sections.push(`${period_end},5100 - Materials,${part.part_name} - ${bundle.job_number},${part.total_cost},,${bundle.job_number}`);
        }
      }
    } else {
      // Payroll format
      if (include_labor) {
        sections.push(`Employee,Date,Job,Regular Hours,Overtime Hours,Total Hours`);
        for (const entry of bundle.labor) {
          sections.push(`${entry.employee},${entry.date},${bundle.job_number},${entry.regular_hours},${entry.overtime_hours},${entry.total_hours}`);
        }
      }
    }
  }

  const csvText = sections.join('\n');
  return new Blob([csvText], { type: 'text/csv' });
}

/** Generate an export bundle (multiple reports). In local mode, concatenates into a single CSV. */
export async function generateExportBundle(exports: Array<{
  report_type: string;
  format?: string;
  job_id?: number;
  employee_id?: number;
  start_date: string;
  end_date: string;
}>): Promise<Blob> {
  const parts: string[] = [];

  for (const exp of exports) {
    const reportType = exp.report_type as 'pre-billing' | 'timesheet' | 'labor-overview' | 'profitability';
    const blob = await generateExport({
      report_type: reportType,
      format: (exp.format as 'csv' | 'pdf') ?? 'csv',
      job_id: exp.job_id,
      employee_id: exp.employee_id,
      start_date: exp.start_date,
      end_date: exp.end_date,
    });
    const text = await blob.text();
    parts.push(`\n========== ${exp.report_type.toUpperCase()} (${exp.start_date} to ${exp.end_date}) ==========\n`);
    parts.push(text);
  }

  return new Blob(parts, { type: 'text/csv' });
}

/** Get a public report by share token (local mode: look up token, generate report data). */
export async function getPublicReport(token: string): Promise<{
  report_type: string;
  label: string | null;
  generated_at: string;
  context_params: Record<string, any>;
  data: Record<string, any>;
  annotations: ReportAnnotation[];
}> {
  // Look up the token
  const tokenRecord = await getShareTokenByValue(token);

  if (!tokenRecord || !tokenRecord.is_active) {
    throw new Error('Invalid or expired share token');
  }

  // Check expiration
  if (tokenRecord.expires_at && new Date(tokenRecord.expires_at) < new Date()) {
    throw new Error('Share token has expired');
  }

  // Record the access
  await recordTokenAccess(tokenRecord.id);

  // Parse context params
  const contextParams: Record<string, any> = typeof tokenRecord.context_params === 'string'
    ? JSON.parse(tokenRecord.context_params)
    : tokenRecord.context_params;

  // Generate the report data based on type and context
  let reportData: Record<string, any> = {};
  const start = contextParams.start_date ?? contextParams.period_start ?? '2000-01-01';
  const end = contextParams.end_date ?? contextParams.period_end ?? '2099-12-31';

  switch (tokenRecord.report_type) {
    case 'pre-billing': {
      if (contextParams.job_id) {
        reportData = await getPreBilling({ job_id: contextParams.job_id, start_date: start, end_date: end });
      } else {
        reportData = { jobs: await getPreBillingAllJobs({ start_date: start, end_date: end }) };
      }
      break;
    }
    case 'timesheet': {
      reportData = await getTimesheets({
        start_date: start,
        end_date: end,
        employee_id: contextParams.employee_id,
      });
      break;
    }
    case 'labor-overview': {
      reportData = await getLaborOverview({
        start_date: start,
        end_date: end,
        job_id: contextParams.job_id,
      });
      break;
    }
    case 'profitability': {
      reportData = await getProfitability({
        start_date: start,
        end_date: end,
        job_id: contextParams.job_id,
      });
      break;
    }
    default:
      reportData = { error: `Unknown report type: ${tokenRecord.report_type}` };
  }

  // Get annotations for this report context
  const contextKey = contextParams.context_key ?? `${tokenRecord.report_type}:${start}:${end}`;
  const annotations = await getAnnotations(tokenRecord.report_type, contextKey);

  return {
    report_type: tokenRecord.report_type,
    label: tokenRecord.label,
    generated_at: new Date().toISOString(),
    context_params: contextParams,
    data: reportData,
    annotations,
  };
}
