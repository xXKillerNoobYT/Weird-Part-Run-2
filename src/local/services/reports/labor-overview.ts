/**
 * Labor Overview Reports — cross-job labor analysis by employee, job, and bill rate.
 */

import { safeSelect, computeOvertimeForEntries } from './helpers';

// ── Types ──────────────────────────────────────────────────────────

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

// ── Functions ──────────────────────────────────────────────────────

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
