/**
 * Local Receiving Service — session-based PO receiving workflow.
 *
 * Mirrors backend receiving functionality for warehouse workers.
 * Supports: start session, scan/enter items, complete/cancel sessions.
 *
 * Source tables: migration 010_costs_receiving
 */

import { getDb } from '../db';
import { BaseRepo } from '../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

export interface ReceivingSessionCreate {
  po_id: number;
  started_by: number;
  mode?: string; // 'packing_slip' | 'scan'
  notes?: string;
}

export interface ReceivingSession {
  id: number;
  po_id: number;
  started_by: number;
  mode: string;
  status: string;
  completed_at: string | null;
  notes: string | null;
  deleted_at: string | null;
  created_at: string;
  // Joined fields
  po_number?: string;
  supplier_name?: string;
  started_by_name?: string;
  item_count?: number;
  received_count?: number;
}

export interface ReceivingItemCreate {
  session_id: number;
  po_line_id: number;
  expected_qty: number;
  received_qty?: number;
  actual_cost?: number;
  notes?: string;
}

export interface ReceivingItemUpdate {
  received_qty?: number;
  actual_cost?: number;
  notes?: string;
}

export interface ReceivingItem {
  id: number;
  session_id: number;
  po_line_id: number;
  expected_qty: number;
  received_qty: number;
  actual_cost: number | null;
  scanned_at: string | null;
  notes: string | null;
  deleted_at: string | null;
  created_at: string;
  // Joined fields
  part_number?: string;
  part_description?: string;
}

// ── Repos ──────────────────────────────────────────────────────────

const sessionRepo = new BaseRepo('receiving_sessions');
const itemRepo = new BaseRepo('receiving_session_items');

// ═══════════════════════════════════════════════════════════════════
// SESSIONS
// ═══════════════════════════════════════════════════════════════════

/** Start a new receiving session */
export async function startSession(data: ReceivingSessionCreate): Promise<ReceivingSession> {
  const id = await sessionRepo.insert({
    po_id: data.po_id,
    started_by: data.started_by,
    mode: data.mode ?? 'packing_slip',
    status: 'in_progress',
    notes: data.notes ?? null,
    created_at: new Date().toISOString(),
  });
  return (await getSession(id))!;
}

/** Get a receiving session with detail */
export async function getSession(sessionId: number): Promise<ReceivingSession | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT rs.*,
       po.po_number, s.name as supplier_name,
       u.display_name as started_by_name,
       (SELECT COUNT(*) FROM receiving_session_items ri
        WHERE ri.session_id = rs.id AND ri.deleted_at IS NULL) as item_count,
       (SELECT COUNT(*) FROM receiving_session_items ri
        WHERE ri.session_id = rs.id AND ri.deleted_at IS NULL AND ri.received_qty > 0) as received_count
     FROM receiving_sessions rs
     JOIN purchase_orders po ON po.id = rs.po_id
     LEFT JOIN suppliers s ON s.id = po.supplier_id
     LEFT JOIN users u ON u.id = rs.started_by
     WHERE rs.id = ?`,
    [sessionId],
  );
  return (result.values[0] as ReceivingSession) ?? null;
}

/** List sessions for a PO */
export async function getSessionsForPO(poId: number): Promise<ReceivingSession[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT rs.*, u.display_name as started_by_name,
       (SELECT COUNT(*) FROM receiving_session_items ri
        WHERE ri.session_id = rs.id AND ri.deleted_at IS NULL) as item_count
     FROM receiving_sessions rs
     LEFT JOIN users u ON u.id = rs.started_by
     WHERE rs.po_id = ? AND rs.deleted_at IS NULL
     ORDER BY rs.created_at DESC`,
    [poId],
  );
  return result.values as ReceivingSession[];
}

/** List active (in-progress) sessions */
export async function getActiveSessions(): Promise<ReceivingSession[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT rs.*, po.po_number, s.name as supplier_name,
       u.display_name as started_by_name
     FROM receiving_sessions rs
     JOIN purchase_orders po ON po.id = rs.po_id
     LEFT JOIN suppliers s ON s.id = po.supplier_id
     LEFT JOIN users u ON u.id = rs.started_by
     WHERE rs.status = 'in_progress' AND rs.deleted_at IS NULL
     ORDER BY rs.created_at DESC`,
  );
  return result.values as ReceivingSession[];
}

/** Complete a receiving session */
export async function completeSession(sessionId: number): Promise<ReceivingSession | null> {
  const updated = await sessionRepo.update(sessionId, {
    status: 'completed',
    completed_at: new Date().toISOString(),
  });
  if (!updated) return null;
  return getSession(sessionId);
}

/** Cancel a receiving session */
export async function cancelSession(sessionId: number): Promise<ReceivingSession | null> {
  const updated = await sessionRepo.update(sessionId, {
    status: 'cancelled',
    completed_at: new Date().toISOString(),
  });
  if (!updated) return null;
  return getSession(sessionId);
}

// ═══════════════════════════════════════════════════════════════════
// SESSION ITEMS
// ═══════════════════════════════════════════════════════════════════

/** Add an item to a receiving session */
export async function addSessionItem(data: ReceivingItemCreate): Promise<ReceivingItem> {
  const id = await itemRepo.insert({
    session_id: data.session_id,
    po_line_id: data.po_line_id,
    expected_qty: data.expected_qty,
    received_qty: data.received_qty ?? 0,
    actual_cost: data.actual_cost ?? null,
    notes: data.notes ?? null,
    created_at: new Date().toISOString(),
  });
  return (await itemRepo.getById(id)) as ReceivingItem;
}

/** Get all items in a session with part details */
export async function getSessionItems(sessionId: number): Promise<ReceivingItem[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT ri.*, p.part_number, p.description as part_description
     FROM receiving_session_items ri
     JOIN po_line_items pl ON pl.id = ri.po_line_id
     JOIN parts p ON p.id = pl.part_id
     WHERE ri.session_id = ? AND ri.deleted_at IS NULL
     ORDER BY p.part_number ASC`,
    [sessionId],
  );
  return result.values as ReceivingItem[];
}

/** Update a received item (qty, cost, notes) */
export async function updateSessionItem(
  itemId: number,
  data: ReceivingItemUpdate,
): Promise<ReceivingItem | null> {
  const updateData: Record<string, any> = { ...data };
  if (data.received_qty !== undefined && data.received_qty > 0) {
    updateData.scanned_at = new Date().toISOString();
  }
  const updated = await itemRepo.update(itemId, updateData);
  if (!updated) return null;
  return (await itemRepo.getById(itemId)) as ReceivingItem;
}

/** Record a scan (set received_qty and timestamp) */
export async function recordScan(
  itemId: number,
  qty: number,
): Promise<ReceivingItem | null> {
  return updateSessionItem(itemId, {
    received_qty: qty,
  });
}
