/**
 * Local Supplier Portal Service — portal tokens and PO acknowledgments.
 *
 * Manages access tokens for the supplier-facing portal and tracks
 * supplier acknowledgments of purchase orders.
 *
 * Source tables: migration 013_tools_supplier_extras
 */

import { getDb } from '../db';
import { BaseRepo } from '../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

// --- Portal Tokens ---

export interface PortalTokenCreate {
  supplier_id: number;
  note?: string;
  expires_at?: string;
  created_by?: number;
}

export interface SupplierPortalToken {
  id: number;
  supplier_id: number;
  token: string;
  note: string | null;
  is_active: number;
  expires_at: string | null;
  last_used_at: string | null;
  created_by: number | null;
  deleted_at: string | null;
  created_at: string;
  // Joined
  supplier_name?: string;
  created_by_name?: string;
}

// --- PO Acknowledgments ---

export interface AcknowledgmentCreate {
  po_id: number;
  supplier_id: number;
  token_id?: number;
  estimated_delivery?: string;
  supplier_notes?: string;
}

export interface SupplierPOAcknowledgment {
  id: number;
  po_id: number;
  supplier_id: number;
  token_id: number | null;
  estimated_delivery: string | null;
  supplier_notes: string | null;
  acknowledged_at: string;
  deleted_at: string | null;
  // Joined
  po_number?: string;
  supplier_name?: string;
}

// ── Repos ──────────────────────────────────────────────────────────

const tokenRepo = new BaseRepo('supplier_portal_tokens');
const ackRepo = new BaseRepo('supplier_po_acknowledgments');

// ═══════════════════════════════════════════════════════════════════
// PORTAL TOKENS
// ═══════════════════════════════════════════════════════════════════

/** Generate a unique portal token */
function generatePortalToken(): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let token = 'SPT-'; // Supplier Portal Token prefix
  for (let i = 0; i < 28; i++) {
    token += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return token;
}

/** Create a portal token for a supplier */
export async function createPortalToken(data: PortalTokenCreate): Promise<SupplierPortalToken> {
  const id = await tokenRepo.insert({
    supplier_id: data.supplier_id,
    token: generatePortalToken(),
    note: data.note ?? null,
    is_active: 1,
    expires_at: data.expires_at ?? null,
    created_by: data.created_by ?? null,
    created_at: new Date().toISOString(),
  });
  return (await getPortalToken(id))!;
}

/** Get a portal token by ID */
export async function getPortalToken(id: number): Promise<SupplierPortalToken | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT spt.*, s.name as supplier_name, u.display_name as created_by_name
     FROM supplier_portal_tokens spt
     LEFT JOIN suppliers s ON s.id = spt.supplier_id
     LEFT JOIN users u ON u.id = spt.created_by
     WHERE spt.id = ?`,
    [id],
  );
  return (result.values[0] as SupplierPortalToken) ?? null;
}

/** Validate a portal token (returns supplier info if valid) */
export async function validateToken(token: string): Promise<SupplierPortalToken | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT spt.*, s.name as supplier_name
     FROM supplier_portal_tokens spt
     LEFT JOIN suppliers s ON s.id = spt.supplier_id
     WHERE spt.token = ? AND spt.is_active = 1 AND spt.deleted_at IS NULL
       AND (spt.expires_at IS NULL OR spt.expires_at > datetime('now'))`,
    [token],
  );
  if (result.values.length === 0) return null;

  // Update last_used_at (don't track for sync — read indicator)
  await tokenRepo.update(result.values[0].id as number, {
    last_used_at: new Date().toISOString(),
  }, false);

  return result.values[0] as SupplierPortalToken;
}

/** List portal tokens for a supplier */
export async function getTokensForSupplier(supplierId: number): Promise<SupplierPortalToken[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT spt.*, u.display_name as created_by_name
     FROM supplier_portal_tokens spt
     LEFT JOIN users u ON u.id = spt.created_by
     WHERE spt.supplier_id = ? AND spt.deleted_at IS NULL
     ORDER BY spt.created_at DESC`,
    [supplierId],
  );
  return result.values as SupplierPortalToken[];
}

/** Deactivate a portal token */
export async function deactivateToken(id: number): Promise<boolean> {
  return tokenRepo.update(id, { is_active: 0 });
}

/** Soft-delete a portal token */
export async function deletePortalToken(id: number): Promise<boolean> {
  return tokenRepo.update(id, { deleted_at: new Date().toISOString() });
}

// ═══════════════════════════════════════════════════════════════════
// PO ACKNOWLEDGMENTS
// ═══════════════════════════════════════════════════════════════════

/** Record a supplier PO acknowledgment */
export async function createAcknowledgment(data: AcknowledgmentCreate): Promise<SupplierPOAcknowledgment> {
  const id = await ackRepo.insert({
    po_id: data.po_id,
    supplier_id: data.supplier_id,
    token_id: data.token_id ?? null,
    estimated_delivery: data.estimated_delivery ?? null,
    supplier_notes: data.supplier_notes ?? null,
    acknowledged_at: new Date().toISOString(),
  });
  return (await getAcknowledgment(id))!;
}

/** Get an acknowledgment by ID */
export async function getAcknowledgment(id: number): Promise<SupplierPOAcknowledgment | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT spa.*, po.po_number, s.name as supplier_name
     FROM supplier_po_acknowledgments spa
     LEFT JOIN purchase_orders po ON po.id = spa.po_id
     LEFT JOIN suppliers s ON s.id = spa.supplier_id
     WHERE spa.id = ?`,
    [id],
  );
  return (result.values[0] as SupplierPOAcknowledgment) ?? null;
}

/** Get acknowledgment for a specific PO */
export async function getAcknowledgmentForPO(poId: number): Promise<SupplierPOAcknowledgment | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT spa.*, po.po_number, s.name as supplier_name
     FROM supplier_po_acknowledgments spa
     LEFT JOIN purchase_orders po ON po.id = spa.po_id
     LEFT JOIN suppliers s ON s.id = spa.supplier_id
     WHERE spa.po_id = ? AND spa.deleted_at IS NULL`,
    [poId],
  );
  return (result.values[0] as SupplierPOAcknowledgment) ?? null;
}

/** List recent acknowledgments */
export async function listRecentAcknowledgments(
  opts?: { supplier_id?: number; limit?: number },
): Promise<SupplierPOAcknowledgment[]> {
  const db = await getDb();
  const conditions: string[] = ['spa.deleted_at IS NULL'];
  const params: any[] = [];

  if (opts?.supplier_id) {
    conditions.push('spa.supplier_id = ?');
    params.push(opts.supplier_id);
  }

  const limit = opts?.limit ?? 50;

  const result = await db.query(
    `SELECT spa.*, po.po_number, s.name as supplier_name
     FROM supplier_po_acknowledgments spa
     LEFT JOIN purchase_orders po ON po.id = spa.po_id
     LEFT JOIN suppliers s ON s.id = spa.supplier_id
     WHERE ${conditions.join(' AND ')}
     ORDER BY spa.acknowledged_at DESC
     LIMIT ?`,
    [...params, limit],
  );
  return result.values as SupplierPOAcknowledgment[];
}

/** Check if a PO has been acknowledged */
export async function isPOAcknowledged(poId: number): Promise<boolean> {
  const ack = await getAcknowledgmentForPO(poId);
  return ack !== null;
}
