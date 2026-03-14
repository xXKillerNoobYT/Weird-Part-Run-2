/**
 * People — Wage History service.
 *
 * Immutable insert-only wage history for employees.
 * Source table: wage_history (migration 009_people_full)
 */

import { getDb } from '../../db';
import { BaseRepo } from '../../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

export interface WageHistoryCreate {
  user_id: number;
  pay_rate: number;
  effective_date: string;
  reason?: string;
  changed_by?: number;
}

export interface WageHistoryEntry {
  id: number;
  user_id: number;
  pay_rate: number;
  effective_date: string;
  reason: string | null;
  changed_by: number | null;
  created_at: string;
}

// ── Repo ───────────────────────────────────────────────────────────

const wageRepo = new BaseRepo('wage_history');

// ── Functions ──────────────────────────────────────────────────────

/** Add a wage history entry */
export async function addWageEntry(data: WageHistoryCreate): Promise<WageHistoryEntry> {
  const id = await wageRepo.insert({
    user_id: data.user_id,
    pay_rate: data.pay_rate,
    effective_date: data.effective_date,
    reason: data.reason ?? null,
    changed_by: data.changed_by ?? null,
    created_at: new Date().toISOString(),
  });
  return (await wageRepo.getById(id)) as WageHistoryEntry;
}

/** Get wage history for a user, newest first */
export async function getWageHistory(userId: number): Promise<WageHistoryEntry[]> {
  return (await wageRepo.findAll(
    'user_id = ?',
    [userId],
    'effective_date DESC',
  )) as WageHistoryEntry[];
}

/** Get current pay rate for a user */
export async function getCurrentPayRate(userId: number): Promise<number | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT pay_rate FROM wage_history
     WHERE user_id = ? AND effective_date <= date('now')
     ORDER BY effective_date DESC, id DESC LIMIT 1`,
    [userId],
  );
  return result.values[0]?.pay_rate ?? null;
}
