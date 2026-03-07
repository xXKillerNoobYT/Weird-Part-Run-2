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
