/**
 * Local PTO Service — paid time off policies and transactions.
 *
 * Manages PTO policies per employee and tracks accruals, usage,
 * adjustments, carryover, and forfeits.
 *
 * Source tables: migration 011_reports_pto
 */

import { getDb } from '../db';
import { BaseRepo } from '../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

export interface PtoPolicyCreate {
  user_id: number;
  policy_name?: string;
  accrual_rate?: number;
  accrual_period?: string; // 'weekly' | 'biweekly' | 'monthly'
  max_balance?: number;
  carryover_limit?: number;
  start_date: string;
}

export interface PtoPolicyUpdate {
  policy_name?: string;
  accrual_rate?: number;
  accrual_period?: string;
  max_balance?: number;
  carryover_limit?: number;
  is_active?: number;
}

export interface PtoPolicy {
  id: number;
  user_id: number;
  policy_name: string;
  accrual_rate: number;
  accrual_period: string;
  max_balance: number | null;
  carryover_limit: number | null;
  start_date: string;
  is_active: number;
  deleted_at: string | null;
  created_at: string;
  updated_at: string;
  // Computed
  current_balance?: number;
  display_name?: string;
}

export interface PtoTransactionCreate {
  user_id: number;
  transaction_type: string; // 'accrual' | 'usage' | 'adjustment' | 'carryover' | 'forfeit'
  hours: number;
  balance_after: number;
  reference_id?: number;
  reference_type?: string;
  note?: string;
  effective_date: string;
  created_by?: number;
}

export interface PtoTransaction {
  id: number;
  user_id: number;
  transaction_type: string;
  hours: number;
  balance_after: number;
  reference_id: number | null;
  reference_type: string | null;
  note: string | null;
  effective_date: string;
  created_by: number | null;
  deleted_at: string | null;
  created_at: string;
  created_by_name?: string;
}

// ── Repos ──────────────────────────────────────────────────────────

const policyRepo = new BaseRepo('pto_policies');
const transactionRepo = new BaseRepo('pto_transactions');

// ═══════════════════════════════════════════════════════════════════
// PTO POLICIES
// ═══════════════════════════════════════════════════════════════════

/** Create a PTO policy for a user (deactivates previous active policy) */
export async function createPolicy(data: PtoPolicyCreate): Promise<PtoPolicy> {
  const db = await getDb();
  const now = new Date().toISOString();

  // Deactivate any existing active policy for this user
  await db.run(
    `UPDATE pto_policies SET is_active = 0, updated_at = ?
     WHERE user_id = ? AND is_active = 1 AND deleted_at IS NULL`,
    [now, data.user_id],
  );

  const id = await policyRepo.insert({
    user_id: data.user_id,
    policy_name: data.policy_name ?? 'Standard PTO',
    accrual_rate: data.accrual_rate ?? 3.33,
    accrual_period: data.accrual_period ?? 'biweekly',
    max_balance: data.max_balance ?? null,
    carryover_limit: data.carryover_limit ?? null,
    start_date: data.start_date,
    is_active: 1,
    created_at: now,
    updated_at: now,
  });
  return (await getPolicy(id))!;
}

/** Get a PTO policy by ID */
export async function getPolicy(id: number): Promise<PtoPolicy | null> {
  const row = await policyRepo.getById(id);
  return row ? (row as PtoPolicy) : null;
}

/** Get the active policy for a user */
export async function getActivePolicy(userId: number): Promise<PtoPolicy | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT pp.*, u.display_name,
       (SELECT pt.balance_after FROM pto_transactions pt
        WHERE pt.user_id = pp.user_id AND pt.deleted_at IS NULL
        ORDER BY pt.effective_date DESC, pt.id DESC LIMIT 1) as current_balance
     FROM pto_policies pp
     LEFT JOIN users u ON u.id = pp.user_id
     WHERE pp.user_id = ? AND pp.is_active = 1 AND pp.deleted_at IS NULL
     LIMIT 1`,
    [userId],
  );
  return (result.values[0] as PtoPolicy) ?? null;
}

/** List all active PTO policies (admin view) */
export async function listActivePolicies(): Promise<PtoPolicy[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT pp.*, u.display_name,
       (SELECT pt.balance_after FROM pto_transactions pt
        WHERE pt.user_id = pp.user_id AND pt.deleted_at IS NULL
        ORDER BY pt.effective_date DESC, pt.id DESC LIMIT 1) as current_balance
     FROM pto_policies pp
     JOIN users u ON u.id = pp.user_id
     WHERE pp.is_active = 1 AND pp.deleted_at IS NULL
     ORDER BY u.display_name ASC`,
  );
  return result.values as PtoPolicy[];
}

/** Update a PTO policy */
export async function updatePolicy(
  id: number,
  data: PtoPolicyUpdate,
): Promise<PtoPolicy | null> {
  const updated = await policyRepo.update(id, {
    ...data,
    updated_at: new Date().toISOString(),
  });
  if (!updated) return null;
  return getPolicy(id);
}

/** Soft-delete a PTO policy */
export async function deletePolicy(id: number): Promise<boolean> {
  return policyRepo.update(id, { deleted_at: new Date().toISOString() });
}

// ═══════════════════════════════════════════════════════════════════
// PTO TRANSACTIONS
// ═══════════════════════════════════════════════════════════════════

/** Record a PTO transaction */
export async function recordTransaction(data: PtoTransactionCreate): Promise<PtoTransaction> {
  const id = await transactionRepo.insert({
    user_id: data.user_id,
    transaction_type: data.transaction_type,
    hours: data.hours,
    balance_after: data.balance_after,
    reference_id: data.reference_id ?? null,
    reference_type: data.reference_type ?? null,
    note: data.note ?? null,
    effective_date: data.effective_date,
    created_by: data.created_by ?? null,
    created_at: new Date().toISOString(),
  });
  return (await transactionRepo.getById(id)) as PtoTransaction;
}

/** Get transactions for a user */
export async function getUserTransactions(
  userId: number,
  opts?: {
    start_date?: string;
    end_date?: string;
    transaction_type?: string;
    limit?: number;
    offset?: number;
  },
): Promise<{ items: PtoTransaction[]; total: number }> {
  const db = await getDb();
  const conditions: string[] = ['pt.user_id = ?', 'pt.deleted_at IS NULL'];
  const params: any[] = [userId];

  if (opts?.start_date) {
    conditions.push('pt.effective_date >= ?');
    params.push(opts.start_date);
  }
  if (opts?.end_date) {
    conditions.push('pt.effective_date <= ?');
    params.push(opts.end_date);
  }
  if (opts?.transaction_type) {
    conditions.push('pt.transaction_type = ?');
    params.push(opts.transaction_type);
  }

  const where = conditions.join(' AND ');
  const limit = opts?.limit ?? 100;
  const offset = opts?.offset ?? 0;

  const countResult = await db.query(
    `SELECT COUNT(*) as cnt FROM pto_transactions pt WHERE ${where}`,
    params,
  );

  const result = await db.query(
    `SELECT pt.*, u.display_name as created_by_name
     FROM pto_transactions pt
     LEFT JOIN users u ON u.id = pt.created_by
     WHERE ${where}
     ORDER BY pt.effective_date DESC, pt.id DESC
     LIMIT ? OFFSET ?`,
    [...params, limit, offset],
  );

  return {
    items: result.values as PtoTransaction[],
    total: countResult.values[0]?.cnt ?? 0,
  };
}

/** Get current PTO balance for a user */
export async function getCurrentBalance(userId: number): Promise<number> {
  const db = await getDb();
  const result = await db.query(
    `SELECT balance_after FROM pto_transactions
     WHERE user_id = ? AND deleted_at IS NULL
     ORDER BY effective_date DESC, id DESC LIMIT 1`,
    [userId],
  );
  return result.values[0]?.balance_after ?? 0;
}

/** Record PTO usage (convenience wrapper) */
export async function recordUsage(
  userId: number,
  hours: number,
  effectiveDate: string,
  opts?: { reference_id?: number; reference_type?: string; note?: string; created_by?: number },
): Promise<PtoTransaction> {
  const currentBalance = await getCurrentBalance(userId);
  const newBalance = currentBalance - hours;

  return recordTransaction({
    user_id: userId,
    transaction_type: 'usage',
    hours: -hours, // Negative for usage
    balance_after: newBalance,
    effective_date: effectiveDate,
    ...opts,
  });
}

/** Record PTO accrual (convenience wrapper) */
export async function recordAccrual(
  userId: number,
  hours: number,
  effectiveDate: string,
  opts?: { note?: string; created_by?: number },
): Promise<PtoTransaction> {
  const currentBalance = await getCurrentBalance(userId);
  const newBalance = currentBalance + hours;

  return recordTransaction({
    user_id: userId,
    transaction_type: 'accrual',
    hours,
    balance_after: newBalance,
    effective_date: effectiveDate,
    ...opts,
  });
}
