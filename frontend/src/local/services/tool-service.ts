/**
 * Local Tool Service — tool checkout/return for offline use.
 *
 * Mirrors the field-worker portions of tools_service.py.
 * Supports: tool lookup, checkout, return, my tools, kit verification.
 *
 * Maintenance management and admin features stay shop-only.
 */

import { getDb } from '../db';
import { trackChange } from '../change-tracker';
import { BaseRepo } from '../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

export interface Tool {
  id: number;
  tool_number: string;
  name: string;
  category: string;
  brand: string | null;
  model_number: string | null;
  serial_number: string | null;
  location_type: string;
  location_id: number | null;
  assigned_to: number | null;
  status: string;
  condition_rating: number;
  has_kit: number;
  notes: string | null;
  photo_path: string | null;
  barcode: string | null;
  is_active: number;
  created_at: string;
  updated_at: string;
  // Joined
  assigned_to_name?: string;
  location_name?: string;
}

export interface ToolMovement {
  id: number;
  tool_id: number;
  from_location_type: string | null;
  from_location_id: number | null;
  to_location_type: string | null;
  to_location_id: number | null;
  movement_type: string;
  reason: string | null;
  job_id: number | null;
  performed_by: number;
  condition_at_move: number | null;
  created_at: string;
  // Joined
  performer_name?: string;
  tool_name?: string;
}

export interface KitComponent {
  id: number;
  tool_id: number;
  component_name: string;
  component_type: string;
  qty_required: number;
  is_critical: number;
  sort_order: number;
}

export interface VerificationItem {
  template_item_id: number;
  component_name: string;
  component_type: string;
  qty_required: number;
  is_critical: boolean;
  is_present: boolean;
  condition_rating: number | null;
  notes: string | null;
}

const toolRepo = new BaseRepo('tools');
const movementRepo = new BaseRepo('tool_movements');

// ── Service Functions ──────────────────────────────────────────────

/** List tools with filters */
export async function listTools(opts?: {
  category?: string;
  status?: string;
  location_type?: string;
  search?: string;
  limit?: number;
  offset?: number;
}): Promise<{ items: Tool[]; total: number }> {
  const db = await getDb();
  const conditions: string[] = ['t.is_active = 1'];
  const params: any[] = [];

  if (opts?.category) {
    conditions.push('t.category = ?');
    params.push(opts.category);
  }
  if (opts?.status) {
    conditions.push('t.status = ?');
    params.push(opts.status);
  }
  if (opts?.location_type) {
    conditions.push('t.location_type = ?');
    params.push(opts.location_type);
  }
  if (opts?.search) {
    conditions.push('(t.name LIKE ? OR t.tool_number LIKE ? OR t.serial_number LIKE ?)');
    const term = `%${opts.search}%`;
    params.push(term, term, term);
  }

  const where = `WHERE ${conditions.join(' AND ')}`;
  const limit = opts?.limit ?? 100;
  const offset = opts?.offset ?? 0;

  const countResult = await db.query(
    `SELECT COUNT(*) as cnt FROM tools t ${where}`,
    params,
  );

  const result = await db.query(
    `SELECT t.*, u.display_name as assigned_to_name,
       CASE t.location_type
         WHEN 'warehouse' THEN 'Warehouse'
         WHEN 'truck' THEN (SELECT name FROM vehicles WHERE id = t.location_id)
         WHEN 'job' THEN (SELECT job_name FROM jobs WHERE id = t.location_id)
         ELSE t.location_type
       END as location_name
     FROM tools t
     LEFT JOIN users u ON u.id = t.assigned_to
     ${where}
     ORDER BY t.tool_number ASC
     LIMIT ? OFFSET ?`,
    [...params, limit, offset],
  );

  return {
    items: result.values as Tool[],
    total: countResult.values[0]?.cnt ?? 0,
  };
}

/** Get a single tool by ID */
export async function getTool(toolId: number): Promise<Tool | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT t.*, u.display_name as assigned_to_name,
       CASE t.location_type
         WHEN 'warehouse' THEN 'Warehouse'
         WHEN 'truck' THEN (SELECT name FROM vehicles WHERE id = t.location_id)
         WHEN 'job' THEN (SELECT job_name FROM jobs WHERE id = t.location_id)
         ELSE t.location_type
       END as location_name
     FROM tools t
     LEFT JOIN users u ON u.id = t.assigned_to
     WHERE t.id = ?`,
    [toolId],
  );
  return (result.values[0] as Tool) ?? null;
}

/** Lookup tool by barcode/QR scan */
export async function getToolByBarcode(barcode: string): Promise<Tool | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT t.*, u.display_name as assigned_to_name
     FROM tools t
     LEFT JOIN users u ON u.id = t.assigned_to
     WHERE t.barcode = ? OR t.tool_number = ?`,
    [barcode, barcode],
  );
  return (result.values[0] as Tool) ?? null;
}

/** Checkout a tool (move to truck/job) */
export async function checkoutTool(
  toolId: number,
  data: {
    to_location_type: string;
    to_location_id: number;
    condition_at_move?: number;
    reason?: string;
    job_id?: number;
  },
  userId: number,
): Promise<Tool> {
  const db = await getDb();
  const now = new Date().toISOString();
  const tool = await getTool(toolId);
  if (!tool) throw new Error('Tool not found');
  if (tool.status !== 'available') throw new Error(`Tool is ${tool.status}, cannot checkout`);

  // Log movement
  await movementRepo.insert({
    tool_id: toolId,
    from_location_type: tool.location_type,
    from_location_id: tool.location_id,
    to_location_type: data.to_location_type,
    to_location_id: data.to_location_id,
    movement_type: 'checkout',
    reason: data.reason ?? null,
    job_id: data.job_id ?? null,
    performed_by: userId,
    verified_by: null,
    condition_at_move: data.condition_at_move ?? tool.condition_rating,
    created_at: now,
  });

  // Update tool location and status
  await toolRepo.update(toolId, {
    location_type: data.to_location_type,
    location_id: data.to_location_id,
    assigned_to: userId,
    status: 'checked_out',
    condition_rating: data.condition_at_move ?? tool.condition_rating,
    updated_at: now,
  });

  return (await getTool(toolId))!;
}

/** Return a tool (move back to warehouse) */
export async function returnTool(
  toolId: number,
  data: {
    to_location_type?: string;
    to_location_id?: number;
    condition_at_move?: number;
    reason?: string;
  },
  userId: number,
): Promise<Tool> {
  const db = await getDb();
  const now = new Date().toISOString();
  const tool = await getTool(toolId);
  if (!tool) throw new Error('Tool not found');

  const toLoc = data.to_location_type ?? 'warehouse';
  const toId = data.to_location_id ?? 1;

  // Log movement
  await movementRepo.insert({
    tool_id: toolId,
    from_location_type: tool.location_type,
    from_location_id: tool.location_id,
    to_location_type: toLoc,
    to_location_id: toId,
    movement_type: 'return',
    reason: data.reason ?? null,
    job_id: null,
    performed_by: userId,
    verified_by: null,
    condition_at_move: data.condition_at_move ?? tool.condition_rating,
    created_at: now,
  });

  // Update tool
  await toolRepo.update(toolId, {
    location_type: toLoc,
    location_id: toId,
    assigned_to: null,
    status: 'available',
    condition_rating: data.condition_at_move ?? tool.condition_rating,
    updated_at: now,
  });

  return (await getTool(toolId))!;
}

/** Get tools assigned to / checked out by a user */
export async function getMyTools(userId: number): Promise<Tool[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT t.*, u.display_name as assigned_to_name,
       CASE t.location_type
         WHEN 'warehouse' THEN 'Warehouse'
         WHEN 'truck' THEN (SELECT name FROM vehicles WHERE id = t.location_id)
         WHEN 'job' THEN (SELECT job_name FROM jobs WHERE id = t.location_id)
         ELSE t.location_type
       END as location_name
     FROM tools t
     LEFT JOIN users u ON u.id = t.assigned_to
     WHERE t.assigned_to = ? AND t.is_active = 1
     ORDER BY t.name ASC`,
    [userId],
  );
  return result.values as Tool[];
}

/** Get tools at a specific location (truck, job) */
export async function getToolsAtLocation(
  locationType: string,
  locationId: number,
): Promise<Tool[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT t.*, u.display_name as assigned_to_name
     FROM tools t
     LEFT JOIN users u ON u.id = t.assigned_to
     WHERE t.location_type = ? AND t.location_id = ? AND t.is_active = 1
     ORDER BY t.name ASC`,
    [locationType, locationId],
  );
  return result.values as Tool[];
}

/** Get kit components for a tool */
export async function getKitTemplate(toolId: number): Promise<KitComponent[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT * FROM kit_templates WHERE tool_id = ? ORDER BY sort_order ASC`,
    [toolId],
  );
  return result.values as KitComponent[];
}

/** Start a kit verification session (pre-populate from template) */
export async function startVerification(
  toolId: number,
  triggerType: string,
  userId: number,
  movementId?: number,
): Promise<{ sessionId: number; items: VerificationItem[] }> {
  const db = await getDb();
  const now = new Date().toISOString();

  // Create session
  const sessionResult = await db.run(
    `INSERT INTO kit_verification_sessions (tool_id, movement_id, verified_by, trigger_type, is_complete, missing_count, created_at)
     VALUES (?, ?, ?, ?, 0, 0, ?)`,
    [toolId, movementId ?? null, userId, triggerType, now],
  );
  const sessionId = sessionResult.changes.lastId;

  await trackChange('kit_verification_sessions', sessionId, 'INSERT', {
    tool_id: toolId,
    trigger_type: triggerType,
  });

  // Get template items
  const template = await getKitTemplate(toolId);
  const items: VerificationItem[] = template.map((comp) => ({
    template_item_id: comp.id,
    component_name: comp.component_name,
    component_type: comp.component_type,
    qty_required: comp.qty_required,
    is_critical: comp.is_critical === 1,
    is_present: true, // default to present, user unchecks missing
    condition_rating: null,
    notes: null,
  }));

  return { sessionId, items };
}

/** Complete a verification session */
export async function completeVerification(
  toolId: number,
  sessionId: number,
  items: VerificationItem[],
  notes?: string,
): Promise<void> {
  const db = await getDb();
  const now = new Date().toISOString();

  let missingCount = 0;

  for (const item of items) {
    await db.run(
      `INSERT INTO kit_verification_items (session_id, template_item_id, is_present, condition_rating, notes)
       VALUES (?, ?, ?, ?, ?)`,
      [sessionId, item.template_item_id, item.is_present ? 1 : 0, item.condition_rating, item.notes],
    );
    if (!item.is_present) missingCount++;
  }

  // Complete session
  await db.run(
    `UPDATE kit_verification_sessions SET is_complete = 1, missing_count = ?, notes = ? WHERE id = ?`,
    [missingCount, notes ?? null, sessionId],
  );

  await trackChange('kit_verification_sessions', sessionId, 'UPDATE', {
    is_complete: 1,
    missing_count: missingCount,
  });
}

/** Get movement history for a tool */
export async function getToolHistory(toolId: number, limit = 20): Promise<ToolMovement[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT tm.*, u.display_name as performer_name, t.name as tool_name
     FROM tool_movements tm
     LEFT JOIN users u ON u.id = tm.performed_by
     LEFT JOIN tools t ON t.id = tm.tool_id
     WHERE tm.tool_id = ?
     ORDER BY tm.created_at DESC
     LIMIT ?`,
    [toolId, limit],
  );
  return result.values as ToolMovement[];
}
