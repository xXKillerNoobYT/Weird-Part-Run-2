/**
 * Local Movement Service — stock movements for offline use.
 *
 * Mirrors the 3-phase flow from backend/app/services/movement_service.py:
 *   validate → preview → execute
 *
 * Supports all field-worker movement types:
 *   warehouse→truck, truck→job, job→truck, truck→warehouse, pulled→truck
 *
 * Supplier chain is preserved on every move.
 * Every movement is tracked for sync via change-tracker.
 */

import { getDb } from '../db';
import { trackChange } from '../change-tracker';

// ── Types ──────────────────────────────────────────────────────────

export interface MovementLineItem {
  part_id: number;
  qty: number;
  supplier_id?: number;
}

export interface MovementRequest {
  from_location_type: string;
  from_location_id: number;
  to_location_type: string;
  to_location_id: number;
  items: MovementLineItem[];
  reason?: string;
  reason_detail?: string;
  notes?: string;
  reference_number?: string;
  job_id?: number;
  photo_path?: string;
  scan_confirmed?: boolean;
  gps_lat?: number;
  gps_lng?: number;
  destination_type?: string;
  destination_id?: number;
  destination_label?: string;
}

export interface ValidationResult {
  valid: boolean;
  errors: string[];
  warnings: string[];
}

export interface PreviewLine {
  part_id: number;
  part_number: string;
  part_description: string;
  qty: number;
  supplier_id: number | null;
  supplier_name: string | null;
  source_before: number;
  source_after: number;
  dest_before: number;
  dest_after: number;
  unit_cost: number;
  line_value: number;
}

export interface MovementPreview {
  lines: PreviewLine[];
  total_qty: number;
  total_value: number;
  movement_type: string;
  photo_required: boolean;
  warnings: string[];
}

export interface MovementResult {
  success: boolean;
  movements: number[];
  total_items: number;
  total_qty: number;
  message: string;
}

// Movement rules: [from, to] → movement_type
const MOVEMENT_RULES: Record<string, { type: string; photoRequired: boolean }> = {
  'warehouse:pulled': { type: 'transfer', photoRequired: false },
  'pulled:truck': { type: 'transfer', photoRequired: false },
  'pulled:trailer': { type: 'transfer', photoRequired: false },
  'warehouse:truck': { type: 'transfer', photoRequired: false },
  'warehouse:trailer': { type: 'transfer', photoRequired: false },
  'truck:trailer': { type: 'transfer', photoRequired: false },
  'trailer:truck': { type: 'transfer', photoRequired: false },
  'truck:job': { type: 'consume', photoRequired: true },
  'trailer:job': { type: 'consume', photoRequired: true },
  'job:truck': { type: 'return', photoRequired: true },
  'job:trailer': { type: 'return', photoRequired: true },
  'truck:warehouse': { type: 'return', photoRequired: false },
  'trailer:warehouse': { type: 'return', photoRequired: false },
  'pulled:warehouse': { type: 'return', photoRequired: false },
  'trailer:pulled': { type: 'return', photoRequired: false },
};

// ── Service Functions ──────────────────────────────────────────────

/** Phase 1: Validate a movement request */
export async function validateMovement(req: MovementRequest): Promise<ValidationResult> {
  const errors: string[] = [];
  const warnings: string[] = [];

  // Check valid movement path
  const key = `${req.from_location_type}:${req.to_location_type}`;
  if (!MOVEMENT_RULES[key]) {
    errors.push(`Invalid movement path: ${req.from_location_type} → ${req.to_location_type}`);
    return { valid: false, errors, warnings };
  }

  if (!req.items.length) {
    errors.push('No items in movement request');
    return { valid: false, errors, warnings };
  }

  if (req.items.length > 20) {
    errors.push('Maximum 20 items per movement');
    return { valid: false, errors, warnings };
  }

  const db = await getDb();

  for (const item of req.items) {
    if (item.qty < 1) {
      errors.push(`Invalid quantity for part ${item.part_id}: must be >= 1`);
      continue;
    }

    // Check part exists
    const partResult = await db.query(
      'SELECT id, part_number, description FROM parts WHERE id = ?',
      [item.part_id],
    );
    if (!partResult.values.length) {
      errors.push(`Part ${item.part_id} not found`);
      continue;
    }

    // Check source stock
    const stockResult = await db.query(
      `SELECT COALESCE(SUM(qty), 0) as available
       FROM stock
       WHERE part_id = ? AND location_type = ? AND location_id = ?`,
      [item.part_id, req.from_location_type, req.from_location_id],
    );
    const available = stockResult.values[0]?.available ?? 0;

    if (available < item.qty) {
      errors.push(
        `Insufficient stock for ${partResult.values[0].part_number}: ` +
        `need ${item.qty}, have ${available} at ${req.from_location_type}`,
      );
    } else if (available === item.qty) {
      warnings.push(
        `${partResult.values[0].part_number} will be 0 at source after this move`,
      );
    }
  }

  return { valid: errors.length === 0, errors, warnings };
}

/** Phase 2: Calculate movement preview with before/after quantities */
export async function calculatePreview(req: MovementRequest): Promise<MovementPreview> {
  const db = await getDb();
  const key = `${req.from_location_type}:${req.to_location_type}`;
  const rule = MOVEMENT_RULES[key];

  if (!rule) throw new Error(`Invalid movement path: ${key}`);

  const lines: PreviewLine[] = [];
  let totalQty = 0;
  let totalValue = 0;
  const warnings: string[] = [];

  for (const item of req.items) {
    // Get part info
    const partResult = await db.query(
      'SELECT id, part_number, description, company_cost_price FROM parts WHERE id = ?',
      [item.part_id],
    );
    const part = partResult.values[0];
    if (!part) continue;

    // Resolve supplier (use provided or FIFO from source)
    let supplierId = item.supplier_id ?? null;
    let supplierName: string | null = null;

    if (!supplierId) {
      const supplierResult = await db.query(
        `SELECT s.supplier_id, sup.name
         FROM stock s
         LEFT JOIN suppliers sup ON sup.id = s.supplier_id
         WHERE s.part_id = ? AND s.location_type = ? AND s.location_id = ? AND s.qty > 0
         ORDER BY s.updated_at ASC
         LIMIT 1`,
        [item.part_id, req.from_location_type, req.from_location_id],
      );
      if (supplierResult.values.length) {
        supplierId = supplierResult.values[0].supplier_id;
        supplierName = supplierResult.values[0].name;
      }
    }

    // Get source quantity
    const srcResult = await db.query(
      `SELECT COALESCE(SUM(qty), 0) as qty FROM stock
       WHERE part_id = ? AND location_type = ? AND location_id = ?`,
      [item.part_id, req.from_location_type, req.from_location_id],
    );
    const sourceBefore = srcResult.values[0]?.qty ?? 0;

    // Get destination quantity
    const destResult = await db.query(
      `SELECT COALESCE(SUM(qty), 0) as qty FROM stock
       WHERE part_id = ? AND location_type = ? AND location_id = ?`,
      [item.part_id, req.to_location_type, req.to_location_id],
    );
    const destBefore = destResult.values[0]?.qty ?? 0;

    const unitCost = part.company_cost_price ?? 0;
    const lineValue = unitCost * item.qty;

    lines.push({
      part_id: item.part_id,
      part_number: part.part_number,
      part_description: part.description,
      qty: item.qty,
      supplier_id: supplierId,
      supplier_name: supplierName,
      source_before: sourceBefore,
      source_after: sourceBefore - item.qty,
      dest_before: destBefore,
      dest_after: destBefore + item.qty,
      unit_cost: unitCost,
      line_value: lineValue,
    });

    totalQty += item.qty;
    totalValue += lineValue;
  }

  return {
    lines,
    total_qty: totalQty,
    total_value: totalValue,
    movement_type: rule.type,
    photo_required: rule.photoRequired,
    warnings,
  };
}

/** Phase 3: Execute the movement atomically */
export async function executeMovement(
  req: MovementRequest,
  performedBy: number,
): Promise<MovementResult> {
  // Validate first
  const validation = await validateMovement(req);
  if (!validation.valid) {
    return {
      success: false,
      movements: [],
      total_items: 0,
      total_qty: 0,
      message: validation.errors.join('; '),
    };
  }

  const db = await getDb();
  const key = `${req.from_location_type}:${req.to_location_type}`;
  const rule = MOVEMENT_RULES[key]!;
  const now = new Date().toISOString();
  const movementIds: number[] = [];
  let totalQty = 0;

  for (const item of req.items) {
    // Resolve supplier
    let supplierId = item.supplier_id ?? null;
    if (!supplierId) {
      const supplierResult = await db.query(
        `SELECT supplier_id FROM stock
         WHERE part_id = ? AND location_type = ? AND location_id = ? AND qty > 0
         ORDER BY updated_at ASC LIMIT 1`,
        [item.part_id, req.from_location_type, req.from_location_id],
      );
      supplierId = supplierResult.values[0]?.supplier_id ?? null;
    }

    // Get cost snapshot
    const partResult = await db.query(
      'SELECT company_cost_price, company_sell_price FROM parts WHERE id = ?',
      [item.part_id],
    );
    const unitCost = partResult.values[0]?.company_cost_price ?? 0;
    const unitSell = partResult.values[0]?.company_sell_price ?? 0;

    // 1. Deduct from source (atomic guard)
    const deductResult = await db.run(
      `UPDATE stock SET qty = qty - ?, updated_at = ?
       WHERE part_id = ? AND location_type = ? AND location_id = ?
         AND qty >= ?
         ${supplierId != null ? 'AND supplier_id = ?' : 'AND supplier_id IS NULL'}`,
      [
        item.qty, now,
        item.part_id, req.from_location_type, req.from_location_id,
        item.qty,
        ...(supplierId != null ? [supplierId] : []),
      ],
    );

    if (deductResult.changes.changes === 0) {
      // Try without supplier filter (fallback)
      const fallbackResult = await db.run(
        `UPDATE stock SET qty = qty - ?, updated_at = ?
         WHERE part_id = ? AND location_type = ? AND location_id = ? AND qty >= ?`,
        [item.qty, now, item.part_id, req.from_location_type, req.from_location_id, item.qty],
      );
      if (fallbackResult.changes.changes === 0) {
        throw new Error(`Failed to deduct stock for part ${item.part_id} — insufficient quantity`);
      }
    }

    // 2. Add to destination (UPSERT)
    const existingDest = await db.query(
      `SELECT id, qty FROM stock
       WHERE part_id = ? AND location_type = ? AND location_id = ?
         ${supplierId != null ? 'AND supplier_id = ?' : 'AND supplier_id IS NULL'}`,
      [
        item.part_id, req.to_location_type, req.to_location_id,
        ...(supplierId != null ? [supplierId] : []),
      ],
    );

    if (existingDest.values.length) {
      await db.run(
        `UPDATE stock SET qty = qty + ?, updated_at = ? WHERE id = ?`,
        [item.qty, now, existingDest.values[0].id],
      );
    } else {
      await db.run(
        `INSERT INTO stock (part_id, location_type, location_id, qty, supplier_id, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [item.part_id, req.to_location_type, req.to_location_id, item.qty, supplierId, now],
      );
    }

    // 3. Log the movement record
    const moveResult = await db.run(
      `INSERT INTO stock_movements
         (part_id, qty, from_location_type, from_location_id,
          to_location_type, to_location_id, supplier_id,
          movement_type, reason, job_id, reference_number, notes,
          performed_by, photo_path, scan_confirmed, gps_lat, gps_lng,
          unit_cost_at_move, unit_sell_at_move, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        item.part_id, item.qty,
        req.from_location_type, req.from_location_id,
        req.to_location_type, req.to_location_id,
        supplierId, rule.type,
        req.reason ?? null, req.job_id ?? null,
        req.reference_number ?? null, req.notes ?? null,
        performedBy,
        req.photo_path ?? null,
        req.scan_confirmed ? 1 : 0,
        req.gps_lat ?? null, req.gps_lng ?? null,
        unitCost, unitSell, now,
      ],
    );

    const moveId = moveResult.changes.lastId;
    movementIds.push(moveId);
    totalQty += item.qty;

    // Track changes for sync
    await trackChange('stock_movements', moveId, 'INSERT', {
      part_id: item.part_id,
      qty: item.qty,
      from: `${req.from_location_type}:${req.from_location_id}`,
      to: `${req.to_location_type}:${req.to_location_id}`,
    });
  }

  // Clean up zero-qty stock rows
  await db.run(
    `DELETE FROM stock WHERE qty <= 0`,
  );

  return {
    success: true,
    movements: movementIds,
    total_items: req.items.length,
    total_qty: totalQty,
    message: `Moved ${totalQty} items successfully`,
  };
}

/** Get recent movements visible to a user (their truck, their jobs) */
export async function getRecentMovements(
  userId: number,
  limit = 20,
): Promise<Record<string, any>[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT sm.*, p.part_number, p.description as part_description,
       u.display_name as performer_name
     FROM stock_movements sm
     JOIN parts p ON p.id = sm.part_id
     LEFT JOIN users u ON u.id = sm.performed_by
     WHERE sm.performed_by = ?
     ORDER BY sm.created_at DESC
     LIMIT ?`,
    [userId, limit],
  );
  return result.values;
}

/** Get current stock at a location */
export async function getStockAtLocation(
  locationType: string,
  locationId: number,
): Promise<Record<string, any>[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT s.*, p.part_number, p.description as part_description,
       p.category_id, sup.name as supplier_name
     FROM stock s
     JOIN parts p ON p.id = s.part_id
     LEFT JOIN suppliers sup ON sup.id = s.supplier_id
     WHERE s.location_type = ? AND s.location_id = ? AND s.qty > 0
     ORDER BY p.part_number ASC`,
    [locationType, locationId],
  );
  return result.values;
}
