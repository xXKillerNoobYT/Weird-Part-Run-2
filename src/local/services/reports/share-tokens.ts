/**
 * Report Share Tokens — create, list, deactivate, and access shared report links.
 *
 * Source table: report_share_tokens (migration 011_reports_pto)
 */

import { getDb } from '../../db';
import { BaseRepo } from '../../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

export interface ShareTokenCreate {
  report_type: string;
  context_params: Record<string, any>;
  label?: string;
  created_by: number;
  expires_at?: string;
}

export interface ReportShareToken {
  id: number;
  token: string;
  report_type: string;
  context_params: string; // JSON
  label: string | null;
  created_by: number;
  expires_at: string | null;
  last_accessed_at: string | null;
  is_active: number;
  deleted_at: string | null;
  created_at: string;
  created_by_name?: string;
}

// ── Repo ───────────────────────────────────────────────────────────

const tokenRepo = new BaseRepo('report_share_tokens');

// ── Helpers ────────────────────────────────────────────────────────

/** Generate a unique token string */
function generateToken(): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let token = '';
  for (let i = 0; i < 32; i++) {
    token += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return token;
}

// ── Functions ──────────────────────────────────────────────────────

/** Create a share token for a report */
export async function createShareToken(data: ShareTokenCreate): Promise<ReportShareToken> {
  const id = await tokenRepo.insert({
    token: generateToken(),
    report_type: data.report_type,
    context_params: JSON.stringify(data.context_params),
    label: data.label ?? null,
    created_by: data.created_by,
    expires_at: data.expires_at ?? null,
    is_active: 1,
    created_at: new Date().toISOString(),
  });
  return (await tokenRepo.getById(id)) as ReportShareToken;
}

/** Get a share token by token string */
export async function getShareTokenByValue(token: string): Promise<ReportShareToken | null> {
  const results = await tokenRepo.findAll(
    'token = ? AND deleted_at IS NULL',
    [token],
  );
  return (results[0] as ReportShareToken) ?? null;
}

/** List share tokens for a report type */
export async function listShareTokens(opts?: {
  report_type?: string;
  active_only?: boolean;
}): Promise<ReportShareToken[]> {
  const db = await getDb();
  const conditions: string[] = ['st.deleted_at IS NULL'];
  const params: any[] = [];

  if (opts?.report_type) {
    conditions.push('st.report_type = ?');
    params.push(opts.report_type);
  }
  if (opts?.active_only) {
    conditions.push('st.is_active = 1');
    conditions.push("(st.expires_at IS NULL OR st.expires_at > datetime('now'))");
  }

  const result = await db.query(
    `SELECT st.*, u.display_name as created_by_name
     FROM report_share_tokens st
     LEFT JOIN users u ON u.id = st.created_by
     WHERE ${conditions.join(' AND ')}
     ORDER BY st.created_at DESC`,
    params,
  );
  return result.values as ReportShareToken[];
}

/** Deactivate a share token */
export async function deactivateShareToken(id: number): Promise<boolean> {
  return tokenRepo.update(id, { is_active: 0 });
}

/** Record token access */
export async function recordTokenAccess(id: number): Promise<void> {
  await tokenRepo.update(id, {
    last_accessed_at: new Date().toISOString(),
  }, false); // Don't track this change for sync — it's a read indicator
}
