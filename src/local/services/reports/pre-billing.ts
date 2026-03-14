/**
 * Pre-Billing Reports — all-jobs summary and per-job bundles with labor, parts, and movements.
 */

import { safeSelect, safeScalar, computeOvertimeForEntries } from './helpers';

// ── Types ──────────────────────────────────────────────────────────

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

// ── Functions ──────────────────────────────────────────────────────

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
