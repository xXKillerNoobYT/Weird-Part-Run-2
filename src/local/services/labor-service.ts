/**
 * Local Labor Service — clock in/out for offline use.
 *
 * Mirrors backend/app/services/labor_service.py for field workers.
 * Supports: clock in, clock out, active clock check, labor history.
 * Hours calculation: 8-hour OT threshold, drive time subtracted.
 *
 * Clock-out questionnaire responses are stored locally and synced.
 * Photo paths reference local device storage (synced as files later).
 */

import { getDb } from '../db';
import { trackChange } from '../change-tracker';
import { BaseRepo } from '../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

export interface ClockInRequest {
  job_id: number;
  gps_lat?: number;
  gps_lng?: number;
  photo_path?: string;
}

export interface ClockOutRequest {
  labor_entry_id: number;
  gps_lat?: number;
  gps_lng?: number;
  drive_time_minutes?: number;
  notes?: string;
  photo_path?: string;
  responses?: ClockOutResponseInput[];
  one_time_answers?: OneTimeAnswerInput[];
}

export interface ClockOutResponseInput {
  question_id: number;
  answer_text: string;
  answer_photo_path?: string;
}

export interface OneTimeAnswerInput {
  question_text: string;
  answer_text: string;
}

export interface LaborEntry {
  id: number;
  user_id: number;
  job_id: number;
  clock_in: string;
  clock_out: string | null;
  regular_hours: number;
  overtime_hours: number;
  drive_time_minutes: number;
  clock_in_gps_lat: number | null;
  clock_in_gps_lng: number | null;
  clock_out_gps_lat: number | null;
  clock_out_gps_lng: number | null;
  clock_in_photo_path: string | null;
  clock_out_photo_path: string | null;
  status: string;
  notes: string | null;
  created_at: string;
  // Joined fields
  job_name?: string;
  job_number?: string;
  user_name?: string;
}

export interface ActiveClock {
  entry: LaborEntry;
  elapsed_minutes: number;
}

const laborRepo = new BaseRepo('labor_entries');

// ── Service Functions ──────────────────────────────────────────────

/** Clock in to a job */
export async function clockIn(
  userId: number,
  data: ClockInRequest,
): Promise<LaborEntry> {
  // Prevent double clock-in
  const active = await getActiveClock(userId);
  if (active) {
    throw new Error('Already clocked in. Clock out first.');
  }

  const now = new Date().toISOString();

  const insertData: Record<string, any> = {
    user_id: userId,
    job_id: data.job_id,
    clock_in: now,
    clock_out: null,
    regular_hours: 0,
    overtime_hours: 0,
    drive_time_minutes: 0,
    clock_in_gps_lat: data.gps_lat ?? null,
    clock_in_gps_lng: data.gps_lng ?? null,
    clock_out_gps_lat: null,
    clock_out_gps_lng: null,
    clock_in_photo_path: data.photo_path ?? null,
    clock_out_photo_path: null,
    status: 'clocked_in',
    notes: null,
    created_at: now,
  };

  const entryId = await laborRepo.insert(insertData);
  return (await getLaborEntry(entryId))!;
}

/** Clock out from active labor entry */
export async function clockOut(
  userId: number,
  data: ClockOutRequest,
): Promise<LaborEntry> {
  const db = await getDb();

  // Verify the entry exists and belongs to this user
  const entry = await laborRepo.getById(data.labor_entry_id);
  if (!entry) throw new Error('Labor entry not found');
  if (entry.user_id !== userId) throw new Error('Not your labor entry');
  if (entry.status !== 'clocked_in') throw new Error('Entry is not clocked in');

  const now = new Date().toISOString();
  const clockInTime = new Date(entry.clock_in).getTime();
  const clockOutTime = new Date(now).getTime();

  // Calculate hours
  const totalHours = (clockOutTime - clockInTime) / (1000 * 60 * 60);
  const driveMinutes = data.drive_time_minutes ?? 0;
  const workHours = Math.max(0, totalHours - driveMinutes / 60);
  const regularHours = Math.min(workHours, 8.0);
  const overtimeHours = Math.max(0, workHours - 8.0);

  const updateData: Record<string, any> = {
    clock_out: now,
    regular_hours: Math.round(regularHours * 100) / 100,
    overtime_hours: Math.round(overtimeHours * 100) / 100,
    drive_time_minutes: driveMinutes,
    clock_out_gps_lat: data.gps_lat ?? null,
    clock_out_gps_lng: data.gps_lng ?? null,
    clock_out_photo_path: data.photo_path ?? null,
    status: 'clocked_out',
    notes: data.notes ?? entry.notes,
  };

  await laborRepo.update(data.labor_entry_id, updateData);

  // Save questionnaire responses
  if (data.responses?.length) {
    for (const resp of data.responses) {
      await db.run(
        `INSERT INTO clock_out_responses (labor_entry_id, question_id, answer_text, answer_photo_path, created_at)
         VALUES (?, ?, ?, ?, ?)`,
        [data.labor_entry_id, resp.question_id, resp.answer_text, resp.answer_photo_path ?? null, now],
      );
      await trackChange('clock_out_responses', 0, 'INSERT', {
        labor_entry_id: data.labor_entry_id,
        question_id: resp.question_id,
      });
    }
  }

  // Save one-time answers
  if (data.one_time_answers?.length) {
    for (const ans of data.one_time_answers) {
      await db.run(
        `INSERT INTO one_time_questions (job_id, question_text, answer_text, asked_by, created_at)
         VALUES (?, ?, ?, ?, ?)`,
        [entry.job_id, ans.question_text, ans.answer_text, userId, now],
      );
      await trackChange('one_time_questions', 0, 'INSERT', {
        job_id: entry.job_id,
        question_text: ans.question_text,
      });
    }
  }

  return (await getLaborEntry(data.labor_entry_id))!;
}

/** Get the user's active clock-in entry, if any */
export async function getActiveClock(userId: number): Promise<ActiveClock | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT le.*, j.job_name, j.job_number
     FROM labor_entries le
     JOIN jobs j ON j.id = le.job_id
     WHERE le.user_id = ? AND le.status = 'clocked_in'
     ORDER BY le.clock_in DESC
     LIMIT 1`,
    [userId],
  );

  const entry = result.values[0] as LaborEntry | undefined;
  if (!entry) return null;

  const elapsed = (Date.now() - new Date(entry.clock_in).getTime()) / (1000 * 60);
  return { entry, elapsed_minutes: Math.round(elapsed) };
}

/** Get a single labor entry with joined job info */
export async function getLaborEntry(entryId: number): Promise<LaborEntry | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT le.*, j.job_name, j.job_number, u.display_name as user_name
     FROM labor_entries le
     JOIN jobs j ON j.id = le.job_id
     JOIN users u ON u.id = le.user_id
     WHERE le.id = ?`,
    [entryId],
  );
  return (result.values[0] as LaborEntry) ?? null;
}

/** Get labor entries for a specific job */
export async function getLaborForJob(
  jobId: number,
  dateFrom?: string,
  dateTo?: string,
): Promise<LaborEntry[]> {
  const db = await getDb();
  const conditions = ['le.job_id = ?'];
  const params: any[] = [jobId];

  if (dateFrom) {
    conditions.push('le.clock_in >= ?');
    params.push(dateFrom);
  }
  if (dateTo) {
    conditions.push('le.clock_in <= ?');
    params.push(dateTo);
  }

  const result = await db.query(
    `SELECT le.*, u.display_name as user_name
     FROM labor_entries le
     JOIN users u ON u.id = le.user_id
     WHERE ${conditions.join(' AND ')}
     ORDER BY le.clock_in DESC`,
    params,
  );
  return result.values as LaborEntry[];
}

/** Get labor entries for a specific user */
export async function getLaborForUser(
  userId: number,
  dateFrom?: string,
  dateTo?: string,
): Promise<LaborEntry[]> {
  const db = await getDb();
  const conditions = ['le.user_id = ?'];
  const params: any[] = [userId];

  if (dateFrom) {
    conditions.push('le.clock_in >= ?');
    params.push(dateFrom);
  }
  if (dateTo) {
    conditions.push('le.clock_in <= ?');
    params.push(dateTo);
  }

  const result = await db.query(
    `SELECT le.*, j.job_name, j.job_number
     FROM labor_entries le
     JOIN jobs j ON j.id = le.job_id
     WHERE ${conditions.join(' AND ')}
     ORDER BY le.clock_in DESC`,
    params,
  );
  return result.values as LaborEntry[];
}

/** Get today's labor summary for a user */
export async function getTodaySummary(userId: number): Promise<{
  entries: LaborEntry[];
  total_regular: number;
  total_overtime: number;
  total_drive_minutes: number;
}> {
  const today = new Date().toISOString().split('T')[0];
  const entries = await getLaborForUser(userId, today, today + 'T23:59:59');

  let totalRegular = 0;
  let totalOvertime = 0;
  let totalDrive = 0;

  for (const e of entries) {
    totalRegular += e.regular_hours ?? 0;
    totalOvertime += e.overtime_hours ?? 0;
    totalDrive += e.drive_time_minutes ?? 0;
  }

  return {
    entries,
    total_regular: Math.round(totalRegular * 100) / 100,
    total_overtime: Math.round(totalOvertime * 100) / 100,
    total_drive_minutes: totalDrive,
  };
}
