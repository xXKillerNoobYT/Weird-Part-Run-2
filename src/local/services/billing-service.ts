/**
 * Local Billing Service — billing period management for cost locking.
 *
 * Manages billing periods that lock labor/cost data for a date range.
 * Supports: create, list, lock, unlock periods.
 *
 * Source tables: migration 010_costs_receiving
 */

import { getDb } from '../db';
import { BaseRepo } from '../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

export interface BillingPeriodCreate {
  job_id?: number; // null = company-wide
  period_start: string;
  period_end: string;
  notes?: string;
}

export interface BillingPeriodUpdate {
  notes?: string;
}

export interface BillingPeriod {
  id: number;
  job_id: number | null;
  period_start: string;
  period_end: string;
  locked_at: string | null;
  locked_by: number | null;
  notes: string | null;
  deleted_at: string | null;
  created_at: string;
  updated_at: string;
  // Joined fields
  job_name?: string;
  locked_by_name?: string;
  is_locked?: boolean;
}

// ── Repos ──────────────────────────────────────────────────────────

const periodRepo = new BaseRepo('billing_periods');

// ═══════════════════════════════════════════════════════════════════
// BILLING PERIODS
// ═══════════════════════════════════════════════════════════════════

/** Create a billing period */
export async function createBillingPeriod(data: BillingPeriodCreate): Promise<BillingPeriod> {
  const now = new Date().toISOString();
  const id = await periodRepo.insert({
    job_id: data.job_id ?? null,
    period_start: data.period_start,
    period_end: data.period_end,
    notes: data.notes ?? null,
    created_at: now,
    updated_at: now,
  });
  return (await getBillingPeriod(id))!;
}

/** Get a billing period by ID */
export async function getBillingPeriod(id: number): Promise<BillingPeriod | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT bp.*,
       j.job_name,
       u.display_name as locked_by_name,
       CASE WHEN bp.locked_at IS NOT NULL THEN 1 ELSE 0 END as is_locked
     FROM billing_periods bp
     LEFT JOIN jobs j ON j.id = bp.job_id
     LEFT JOIN users u ON u.id = bp.locked_by
     WHERE bp.id = ?`,
    [id],
  );
  return (result.values[0] as BillingPeriod) ?? null;
}

/** List billing periods with optional filters */
export async function listBillingPeriods(opts?: {
  job_id?: number;
  locked_only?: boolean;
  unlocked_only?: boolean;
  limit?: number;
  offset?: number;
}): Promise<{ items: BillingPeriod[]; total: number }> {
  const db = await getDb();
  const conditions: string[] = ['bp.deleted_at IS NULL'];
  const params: any[] = [];

  if (opts?.job_id !== undefined) {
    if (opts.job_id === 0) {
      conditions.push('bp.job_id IS NULL'); // company-wide
    } else {
      conditions.push('bp.job_id = ?');
      params.push(opts.job_id);
    }
  }

  if (opts?.locked_only) {
    conditions.push('bp.locked_at IS NOT NULL');
  }
  if (opts?.unlocked_only) {
    conditions.push('bp.locked_at IS NULL');
  }

  const where = conditions.join(' AND ');
  const limit = opts?.limit ?? 100;
  const offset = opts?.offset ?? 0;

  const countResult = await db.query(
    `SELECT COUNT(*) as cnt FROM billing_periods bp WHERE ${where}`,
    params,
  );

  const result = await db.query(
    `SELECT bp.*,
       j.job_name,
       u.display_name as locked_by_name,
       CASE WHEN bp.locked_at IS NOT NULL THEN 1 ELSE 0 END as is_locked
     FROM billing_periods bp
     LEFT JOIN jobs j ON j.id = bp.job_id
     LEFT JOIN users u ON u.id = bp.locked_by
     WHERE ${where}
     ORDER BY bp.period_start DESC
     LIMIT ? OFFSET ?`,
    [...params, limit, offset],
  );

  return {
    items: result.values as BillingPeriod[],
    total: countResult.values[0]?.cnt ?? 0,
  };
}

/** Lock a billing period */
export async function lockBillingPeriod(
  id: number,
  lockedBy: number,
): Promise<BillingPeriod | null> {
  const updated = await periodRepo.update(id, {
    locked_at: new Date().toISOString(),
    locked_by: lockedBy,
    updated_at: new Date().toISOString(),
  });
  if (!updated) return null;
  return getBillingPeriod(id);
}

/** Unlock a billing period */
export async function unlockBillingPeriod(id: number): Promise<BillingPeriod | null> {
  const updated = await periodRepo.update(id, {
    locked_at: null,
    locked_by: null,
    updated_at: new Date().toISOString(),
  });
  if (!updated) return null;
  return getBillingPeriod(id);
}

/** Update billing period notes */
export async function updateBillingPeriod(
  id: number,
  data: BillingPeriodUpdate,
): Promise<BillingPeriod | null> {
  const updated = await periodRepo.update(id, {
    ...data,
    updated_at: new Date().toISOString(),
  });
  if (!updated) return null;
  return getBillingPeriod(id);
}

/** Soft-delete a billing period */
export async function deleteBillingPeriod(id: number): Promise<boolean> {
  return periodRepo.update(id, { deleted_at: new Date().toISOString() });
}

/** Check if a date falls within a locked billing period for a job */
export async function isDateLocked(jobId: number | null, date: string): Promise<boolean> {
  const db = await getDb();
  const result = await db.query(
    `SELECT COUNT(*) as cnt FROM billing_periods
     WHERE deleted_at IS NULL
       AND locked_at IS NOT NULL
       AND (job_id = ? OR job_id IS NULL)
       AND period_start <= ? AND period_end >= ?`,
    [jobId, date, date],
  );
  return (result.values[0]?.cnt ?? 0) > 0;
}
