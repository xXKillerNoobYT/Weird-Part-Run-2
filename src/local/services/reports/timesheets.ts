/**
 * Timesheet Reports — employee timesheets with day grouping and overtime calculation.
 */

import { safeSelect, computeOvertimeForEntries } from './helpers';

// ── Types ──────────────────────────────────────────────────────────

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

// ── Functions ──────────────────────────────────────────────────────

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
