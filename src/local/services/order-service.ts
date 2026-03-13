/**
 * Local Order Service — JPO creation and management for offline use.
 *
 * Mirrors the JPO (Job Parts Order) portion of orders_service.py.
 * Field workers can create and view JPOs offline. PO management
 * (purchase orders, supplier selection, PDF generation) is shop-only.
 *
 * Only JPO create/list/detail are ported. Office approval workflow
 * and PO lifecycle stay on the shop server.
 */

import { getDb } from '../db';
import { BaseRepo } from '../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

export interface JPOLineCreate {
  part_id: number;
  qty_requested: number;
  priority?: string;
  notes?: string;
  suggested_supplier_id?: number;
}

export interface JPOCreate {
  job_id?: number;
  order_type?: string;
  priority?: string;
  notes?: string;
  lines: JPOLineCreate[];
  special_items?: SpecialItemCreate[];
}

export interface SpecialItemCreate {
  description: string;
  qty: number;
  estimated_cost?: number;
  vendor_suggestion?: string;
  notes?: string;
}

export interface JPO {
  id: number;
  job_id: number | null;
  order_number: string;
  status: string;
  priority: string;
  order_type: string;
  has_special_items: number;
  requested_by: number;
  approved_by: number | null;
  approved_at: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
  // Joined
  job_name?: string;
  job_number?: string;
  requester_name?: string;
  line_count?: number;
}

export interface JPOLine {
  id: number;
  jpo_id: number;
  part_id: number;
  qty_requested: number;
  qty_ordered: number;
  qty_received: number;
  priority: string;
  notes: string | null;
  suggested_supplier_id: number | null;
  created_at: string;
  // Joined
  part_number?: string;
  part_description?: string;
  supplier_name?: string;
}

const jpoRepo = new BaseRepo('job_parts_orders');
const jpoLineRepo = new BaseRepo('jpo_line_items');

// ── Service Functions ──────────────────────────────────────────────

/** Create a new Job Parts Order */
export async function createJPO(
  data: JPOCreate,
  requestedBy: number,
): Promise<JPO> {
  const db = await getDb();
  const now = new Date().toISOString();

  // Generate order number
  const countResult = await db.query('SELECT COUNT(*) as cnt FROM job_parts_orders');
  const count = (countResult.values[0]?.cnt ?? 0) + 1;
  const orderNumber = `JPO-${String(count).padStart(5, '0')}`;

  const jpoId = await jpoRepo.insert({
    job_id: data.job_id ?? null,
    order_number: orderNumber,
    status: 'draft',
    priority: data.priority ?? 'normal',
    order_type: data.order_type ?? 'job',
    has_special_items: (data.special_items?.length ?? 0) > 0 ? 1 : 0,
    smart_suggestions_enabled: 1,
    requested_by: requestedBy,
    approved_by: null,
    approved_at: null,
    notes: data.notes ?? null,
    created_at: now,
    updated_at: now,
  });

  // Insert line items
  for (const line of data.lines) {
    await jpoLineRepo.insert({
      jpo_id: jpoId,
      part_id: line.part_id,
      qty_requested: line.qty_requested,
      qty_ordered: 0,
      qty_received: 0,
      priority: line.priority ?? 'normal',
      notes: line.notes ?? null,
      suggested_supplier_id: line.suggested_supplier_id ?? null,
      created_at: now,
    });
  }

  // Insert special items
  if (data.special_items?.length) {
    for (const item of data.special_items) {
      await db.run(
        `INSERT INTO special_items (jpo_id, description, qty, estimated_cost, vendor_suggestion, notes, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [jpoId, item.description, item.qty, item.estimated_cost ?? null, item.vendor_suggestion ?? null, item.notes ?? null, now],
      );
    }
  }

  return (await getJPO(jpoId))!;
}

/** Submit a draft JPO for approval */
export async function submitJPO(jpoId: number, userId: number): Promise<JPO | null> {
  const jpo = await jpoRepo.getById(jpoId);
  if (!jpo || jpo.status !== 'draft') return null;

  await jpoRepo.update(jpoId, {
    status: 'pending_approval',
    updated_at: new Date().toISOString(),
  });

  // Log status change
  await logStatusChange('jpo', jpoId, 'draft', 'pending_approval', userId);

  return getJPO(jpoId);
}

/** Get a JPO with full details */
export async function getJPO(jpoId: number): Promise<JPO | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT jpo.*,
       j.job_name, j.job_number,
       u.display_name as requester_name,
       (SELECT COUNT(*) FROM jpo_line_items WHERE jpo_id = jpo.id) as line_count
     FROM job_parts_orders jpo
     LEFT JOIN jobs j ON j.id = jpo.job_id
     LEFT JOIN users u ON u.id = jpo.requested_by
     WHERE jpo.id = ?`,
    [jpoId],
  );
  return (result.values[0] as JPO) ?? null;
}

/** Get line items for a JPO */
export async function getJPOLines(jpoId: number): Promise<JPOLine[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT jli.*,
       p.part_number, p.description as part_description,
       s.name as supplier_name
     FROM jpo_line_items jli
     JOIN parts p ON p.id = jli.part_id
     LEFT JOIN suppliers s ON s.id = jli.suggested_supplier_id
     WHERE jli.jpo_id = ?
     ORDER BY jli.created_at ASC`,
    [jpoId],
  );
  return result.values as JPOLine[];
}

/** List JPOs with optional filters */
export async function listJPOs(opts?: {
  status?: string;
  job_id?: number;
  requested_by?: number;
  limit?: number;
  offset?: number;
}): Promise<{ items: JPO[]; total: number }> {
  const db = await getDb();
  const conditions: string[] = [];
  const params: any[] = [];

  if (opts?.status) {
    conditions.push('jpo.status = ?');
    params.push(opts.status);
  }
  if (opts?.job_id) {
    conditions.push('jpo.job_id = ?');
    params.push(opts.job_id);
  }
  if (opts?.requested_by) {
    conditions.push('jpo.requested_by = ?');
    params.push(opts.requested_by);
  }

  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
  const limit = opts?.limit ?? 100;
  const offset = opts?.offset ?? 0;

  const countResult = await db.query(
    `SELECT COUNT(*) as cnt FROM job_parts_orders jpo ${where}`,
    params,
  );

  const result = await db.query(
    `SELECT jpo.*,
       j.job_name, j.job_number,
       u.display_name as requester_name,
       (SELECT COUNT(*) FROM jpo_line_items WHERE jpo_id = jpo.id) as line_count
     FROM job_parts_orders jpo
     LEFT JOIN jobs j ON j.id = jpo.job_id
     LEFT JOIN users u ON u.id = jpo.requested_by
     ${where}
     ORDER BY jpo.created_at DESC
     LIMIT ? OFFSET ?`,
    [...params, limit, offset],
  );

  return {
    items: result.values as JPO[],
    total: countResult.values[0]?.cnt ?? 0,
  };
}

/** Get JPOs for the current user (my orders) */
export async function getMyOrders(userId: number): Promise<JPO[]> {
  const result = await listJPOs({ requested_by: userId });
  return result.items;
}

// ── Internal Helpers ───────────────────────────────────────────────

async function logStatusChange(
  entityType: string,
  entityId: number,
  oldStatus: string,
  newStatus: string,
  userId: number,
  notes?: string,
): Promise<void> {
  const db = await getDb();
  await db.run(
    `INSERT INTO order_status_history (entity_type, entity_id, old_status, new_status, changed_by, notes, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [entityType, entityId, oldStatus, newStatus, userId, notes ?? null, new Date().toISOString()],
  );
}
