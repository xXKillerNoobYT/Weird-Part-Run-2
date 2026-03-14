/**
 * Local Scheduling Service — read-only schedule access for offline use.
 *
 * Field workers can view their dispatch assignments, schedules, and
 * time-off status. Schedule creation/management stays shop-only.
 */

import { getDb } from '../db';

// ── Types ──────────────────────────────────────────────────────────

export interface DispatchAssignment {
  id: number;
  job_id: number;
  user_id: number;
  dispatch_date: string;
  start_time: string | null;
  end_time: string | null;
  status: string;
  notes: string | null;
  created_at: string;
  // Joined
  job_name?: string;
  job_number?: string;
  job_address?: string;
  user_name?: string;
}

export interface Schedule {
  id: number;
  user_id: number;
  day_of_week: number;
  start_time: string;
  end_time: string;
  is_active: number;
}

export interface TimeOffRequest {
  id: number;
  user_id: number;
  start_date: string;
  end_date: string;
  reason: string | null;
  status: string;
  approved_by: number | null;
  notes: string | null;
  created_at: string;
  // Joined
  user_name?: string;
  approver_name?: string;
}

// ── Service Functions ──────────────────────────────────────────────

/** Get my dispatch assignments for a date range */
export async function getMyDispatch(
  userId: number,
  dateFrom?: string,
  dateTo?: string,
): Promise<DispatchAssignment[]> {
  const db = await getDb();
  const conditions = ['da.user_id = ?'];
  const params: any[] = [userId];

  if (dateFrom) {
    conditions.push('da.dispatch_date >= ?');
    params.push(dateFrom);
  }
  if (dateTo) {
    conditions.push('da.dispatch_date <= ?');
    params.push(dateTo);
  }

  const result = await db.query(
    `SELECT da.*,
       j.job_name, j.job_number,
       j.address_line1 as job_address,
       u.display_name as user_name
     FROM dispatch_assignments da
     JOIN jobs j ON j.id = da.job_id
     JOIN users u ON u.id = da.user_id
     WHERE ${conditions.join(' AND ')}
     ORDER BY da.dispatch_date ASC, da.start_time ASC`,
    params,
  );
  return result.values as DispatchAssignment[];
}

/** Get today's dispatch for a user */
export async function getTodayDispatch(userId: number): Promise<DispatchAssignment[]> {
  const today = new Date().toISOString().split('T')[0];
  return getMyDispatch(userId, today, today);
}

/** Get the user's regular schedule (Mon-Fri pattern) */
export async function getMySchedule(userId: number): Promise<Schedule[]> {
  const db = await getDb();
  const result = await db.query(
    'SELECT * FROM employee_schedules WHERE user_id = ? AND is_active = 1 ORDER BY day_of_week ASC',
    [userId],
  );
  return result.values as Schedule[];
}

/** Get my time-off requests */
export async function getMyTimeOff(userId: number): Promise<TimeOffRequest[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT tor.*, u.display_name as user_name,
       au.display_name as approver_name
     FROM time_off_requests tor
     JOIN users u ON u.id = tor.user_id
     LEFT JOIN users au ON au.id = tor.approved_by
     WHERE tor.user_id = ?
     ORDER BY tor.start_date DESC`,
    [userId],
  );
  return result.values as TimeOffRequest[];
}

/** Get all dispatch assignments for a date (for dispatch board view) */
export async function getDispatchForDate(date: string): Promise<DispatchAssignment[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT da.*,
       j.job_name, j.job_number,
       j.address_line1 as job_address,
       u.display_name as user_name
     FROM dispatch_assignments da
     JOIN jobs j ON j.id = da.job_id
     JOIN users u ON u.id = da.user_id
     WHERE da.dispatch_date = ?
     ORDER BY u.display_name ASC, da.start_time ASC`,
    [date],
  );
  return result.values as DispatchAssignment[];
}

// ── Calendar (unified view) ──────────────────────────────────────

export interface CalendarEntry {
  reference_id: number | null;
  date: string;
  entry_type: string;
  user_id: number | null;
  user_name: string | null;
  job_id: number | null;
  job_name: string | null;
  gc_id: number | null;
  gc_name: string | null;
  status: string;
  role_on_job?: string | null;
  label: string;
}

/**
 * Assemble unified calendar data for a date range from local DB.
 * Combines dispatch assignments and time-off requests into a single view.
 */
export async function getCalendarData(
  dateFrom: string,
  dateTo: string,
): Promise<{ date_from: string; date_to: string; entries: CalendarEntry[] }> {
  const db = await getDb();
  const entries: CalendarEntry[] = [];

  // Dispatches
  const dispatches = await db.query(
    `SELECT da.id, da.dispatch_date, da.status, da.notes,
       da.user_id, u.display_name as user_name,
       da.job_id, j.job_name, j.job_number,
       da.role_on_job
     FROM dispatch_assignments da
     JOIN jobs j ON j.id = da.job_id
     LEFT JOIN users u ON u.id = da.user_id
     WHERE da.dispatch_date >= ? AND da.dispatch_date <= ?
     ORDER BY da.dispatch_date ASC, u.display_name ASC`,
    [dateFrom, dateTo],
  );
  for (const d of dispatches.values as any[]) {
    entries.push({
      reference_id: d.id,
      date: d.dispatch_date,
      entry_type: 'dispatch',
      user_id: d.user_id,
      user_name: d.user_name,
      job_id: d.job_id,
      job_name: d.job_name,
      gc_id: null,
      gc_name: null,
      status: d.status ?? 'scheduled',
      role_on_job: d.role_on_job ?? null,
      label: `${d.user_name ?? 'Unassigned'} → ${d.job_name ?? d.job_number}`,
    });
  }

  // Time-off requests (approved or pending that overlap the range)
  const timeOff = await db.query(
    `SELECT tor.id, tor.user_id, u.display_name as user_name,
       tor.start_date, tor.end_date, tor.status, tor.reason
     FROM time_off_requests tor
     JOIN users u ON u.id = tor.user_id
     WHERE tor.start_date <= ? AND tor.end_date >= ?
       AND tor.status IN ('approved', 'pending')
     ORDER BY tor.start_date ASC`,
    [dateTo, dateFrom],
  );
  for (const t of timeOff.values as any[]) {
    // Expand multi-day time-off into individual day entries within the range
    const start = t.start_date > dateFrom ? t.start_date : dateFrom;
    const end = t.end_date < dateTo ? t.end_date : dateTo;
    let current = start;
    while (current <= end) {
      entries.push({
        reference_id: t.id,
        date: current,
        entry_type: 'time_off',
        user_id: t.user_id,
        user_name: t.user_name,
        job_id: null,
        job_name: null,
        gc_id: null,
        gc_name: null,
        status: t.status,
        label: `${t.user_name} — ${t.reason ?? 'Time Off'}`,
      });
      // Advance to next day
      const d = new Date(current + 'T00:00:00');
      d.setDate(d.getDate() + 1);
      current = d.toISOString().slice(0, 10);
    }
  }

  return { date_from: dateFrom, date_to: dateTo, entries };
}

// ── PTO Balance ──────────────────────────────────────────────────

/**
 * Get PTO balance + recent transactions for a user from local DB.
 */
export async function getPtoBalance(userId: number): Promise<{
  user_id: number;
  user_name: string;
  current_balance: number;
  accrued_ytd: number;
  used_ytd: number;
  policy: any | null;
  recent_transactions: any[];
}> {
  const db = await getDb();
  const yearStart = new Date().getFullYear() + '-01-01';

  // Get user name
  const userRow = await db.query(
    'SELECT display_name FROM users WHERE id = ?',
    [userId],
  );
  const userName = (userRow.values[0] as any)?.display_name ?? 'Unknown';

  // Get active policy
  const policyResult = await db.query(
    `SELECT * FROM pto_policies
     WHERE user_id = ? AND is_active = 1 AND deleted_at IS NULL LIMIT 1`,
    [userId],
  );
  const policy = (policyResult.values[0] as any) ?? null;

  // Get current balance (latest transaction)
  const balanceResult = await db.query(
    `SELECT balance_after FROM pto_transactions
     WHERE user_id = ? AND deleted_at IS NULL
     ORDER BY effective_date DESC, id DESC LIMIT 1`,
    [userId],
  );
  const currentBalance = (balanceResult.values[0] as any)?.balance_after ?? 0;

  // YTD accrued
  const accruedResult = await db.query(
    `SELECT COALESCE(SUM(hours), 0) as total FROM pto_transactions
     WHERE user_id = ? AND transaction_type = 'accrual'
       AND effective_date >= ? AND deleted_at IS NULL`,
    [userId, yearStart],
  );
  const accruedYtd = (accruedResult.values[0] as any)?.total ?? 0;

  // YTD used (usage hours are negative, so ABS)
  const usedResult = await db.query(
    `SELECT COALESCE(SUM(ABS(hours)), 0) as total FROM pto_transactions
     WHERE user_id = ? AND transaction_type = 'usage'
       AND effective_date >= ? AND deleted_at IS NULL`,
    [userId, yearStart],
  );
  const usedYtd = (usedResult.values[0] as any)?.total ?? 0;

  // Recent transactions
  const txResult = await db.query(
    `SELECT pt.*, u.display_name as created_by_name
     FROM pto_transactions pt
     LEFT JOIN users u ON u.id = pt.created_by
     WHERE pt.user_id = ? AND pt.deleted_at IS NULL
     ORDER BY pt.effective_date DESC, pt.id DESC LIMIT 10`,
    [userId],
  );

  return {
    user_id: userId,
    user_name: userName,
    current_balance: currentBalance,
    accrued_ytd: accruedYtd,
    used_ytd: usedYtd,
    policy: policy ? {
      id: policy.id,
      policy_name: policy.policy_name,
      accrual_rate: policy.accrual_rate,
      accrual_period: policy.accrual_period,
      max_balance: policy.max_balance,
    } : null,
    recent_transactions: txResult.values,
  };
}
