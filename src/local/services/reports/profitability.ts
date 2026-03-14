/**
 * Profitability Reports — job profitability analysis with labor costs, parts margins, and budget tracking.
 */

import { safeSelect, safeScalar } from './helpers';

// ── Types ──────────────────────────────────────────────────────────

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

// ── Functions ──────────────────────────────────────────────────────

/** Job profitability analysis for a date range */
export async function getProfitability(params: {
  start_date: string;
  end_date: string;
  job_id?: number;
}): Promise<ProfitabilityReport> {
  const { start_date, end_date, job_id } = params;

  const jobFilter = job_id ? 'AND j.id = ?' : '';

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
