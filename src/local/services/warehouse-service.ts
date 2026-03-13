/**
 * Local Warehouse Service — inventory read-only access for offline use.
 *
 * Mirrors the read portions of the warehouse/inventory services.
 * Field workers can browse inventory, check stock levels, and search
 * parts — all from the local database.
 *
 * Write operations (receiving, adjustments) are handled by movement-service.
 * Cost/value calculations are shop-only (field workers see quantities, not dollars).
 */

import { getDb } from '../db';

// ── Types ──────────────────────────────────────────────────────────

export interface DashboardKPIs {
  stock_health_pct: number;
  total_units: number;
  shortfall_count: number;
  pending_task_count: number;
}

export interface ActivitySummary {
  id: number;
  summary: string;
  movement_type: string;
  performer_name: string | null;
  created_at: string;
}

export interface InventoryItem {
  id: number;
  part_number: string;
  description: string;
  category_name: string | null;
  brand_name: string | null;
  warehouse_qty: number;
  min_stock: number;
  max_stock: number;
  reorder_point: number;
  status: string;
  last_moved: string | null;
}

export interface PartStockDetail {
  part_id: number;
  part_number: string;
  description: string;
  locations: StockLocation[];
  total_qty: number;
}

export interface StockLocation {
  location_type: string;
  location_id: number;
  location_name: string;
  qty: number;
  supplier_name: string | null;
}

// ── Service Functions ──────────────────────────────────────────────

/** Get warehouse dashboard KPIs */
export async function getDashboardKPIs(): Promise<DashboardKPIs> {
  const db = await getDb();

  // Total warehouse units
  const totalResult = await db.query(
    `SELECT COALESCE(SUM(qty), 0) as total FROM stock WHERE location_type = 'warehouse'`,
  );
  const totalUnits = totalResult.values[0]?.total ?? 0;

  // Stock health: parts within min-max range
  const healthResult = await db.query(
    `SELECT
       COUNT(*) as total_parts,
       SUM(CASE WHEN wh_qty >= p.min_stock_level AND wh_qty <= p.max_stock_level THEN 1 ELSE 0 END) as healthy
     FROM (
       SELECT part_id, COALESCE(SUM(qty), 0) as wh_qty
       FROM stock WHERE location_type = 'warehouse'
       GROUP BY part_id
     ) sq
     JOIN parts p ON p.id = sq.part_id
     WHERE p.is_active = 1`,
  );
  const totalParts = healthResult.values[0]?.total_parts ?? 1;
  const healthy = healthResult.values[0]?.healthy ?? 0;
  const healthPct = totalParts > 0 ? Math.round((healthy / totalParts) * 100) : 100;

  // Shortfall count (below min)
  const shortfallResult = await db.query(
    `SELECT COUNT(*) as cnt
     FROM (
       SELECT part_id, COALESCE(SUM(qty), 0) as wh_qty
       FROM stock WHERE location_type = 'warehouse'
       GROUP BY part_id
     ) sq
     JOIN parts p ON p.id = sq.part_id
     WHERE p.is_active = 1 AND sq.wh_qty < p.min_stock_level`,
  );
  const shortfallCount = shortfallResult.values[0]?.cnt ?? 0;

  // Pending tasks (staged items count)
  const pendingResult = await db.query(
    `SELECT COUNT(*) as cnt FROM stock WHERE location_type = 'pulled' AND qty > 0`,
  );
  const pendingCount = pendingResult.values[0]?.cnt ?? 0;

  return {
    stock_health_pct: healthPct,
    total_units: totalUnits,
    shortfall_count: shortfallCount,
    pending_task_count: pendingCount,
  };
}

/** Get recent stock activity */
export async function getRecentActivity(limit = 10): Promise<ActivitySummary[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT sm.id, sm.movement_type, sm.qty, sm.created_at,
       p.part_number, p.description as part_desc,
       u.display_name as performer_name,
       sm.from_location_type, sm.to_location_type
     FROM stock_movements sm
     JOIN parts p ON p.id = sm.part_id
     LEFT JOIN users u ON u.id = sm.performed_by
     ORDER BY sm.created_at DESC
     LIMIT ?`,
    [limit],
  );

  return result.values.map((row) => ({
    id: row.id as number,
    summary: `${row.performer_name ?? 'Unknown'} ${row.movement_type}d ${row.qty}× ${row.part_number} (${row.from_location_type ?? 'external'} → ${row.to_location_type ?? 'external'})`,
    movement_type: row.movement_type as string,
    performer_name: row.performer_name as string | null,
    created_at: row.created_at as string,
  }));
}

/** Get inventory grid with search and filters */
export async function getInventoryGrid(opts?: {
  search?: string;
  category_id?: number;
  status?: string;
  sort?: string;
  limit?: number;
  offset?: number;
}): Promise<{ items: InventoryItem[]; total: number }> {
  const db = await getDb();
  const conditions: string[] = ['p.is_active = 1'];
  const params: any[] = [];

  if (opts?.search) {
    conditions.push('(p.part_number LIKE ? OR p.description LIKE ?)');
    const term = `%${opts.search}%`;
    params.push(term, term);
  }

  if (opts?.category_id) {
    conditions.push('p.category_id = ?');
    params.push(opts.category_id);
  }

  const where = `WHERE ${conditions.join(' AND ')}`;
  const sortMap: Record<string, string> = {
    name: 'p.part_number',
    qty: 'warehouse_qty',
    status: 'stock_status',
  };
  const sort = sortMap[opts?.sort ?? 'name'] ?? 'p.part_number';
  const limit = opts?.limit ?? 100;
  const offset = opts?.offset ?? 0;

  const countResult = await db.query(
    `SELECT COUNT(*) as cnt FROM parts p ${where}`,
    params,
  );

  const result = await db.query(
    `SELECT p.id, p.part_number, p.description,
       c.name as category_name, b.name as brand_name,
       COALESCE(sq.wh_qty, 0) as warehouse_qty,
       p.min_stock_level as min_stock,
       p.max_stock_level as max_stock,
       p.reorder_point,
       CASE
         WHEN COALESCE(sq.wh_qty, 0) < p.min_stock_level THEN 'below_min'
         WHEN COALESCE(sq.wh_qty, 0) > p.max_stock_level THEN 'above_max'
         ELSE 'healthy'
       END as status,
       sq.last_moved
     FROM parts p
     LEFT JOIN categories c ON c.id = p.category_id
     LEFT JOIN brands b ON b.id = p.brand_id
     LEFT JOIN (
       SELECT part_id,
         SUM(qty) as wh_qty,
         MAX(updated_at) as last_moved
       FROM stock WHERE location_type = 'warehouse'
       GROUP BY part_id
     ) sq ON sq.part_id = p.id
     ${where}
     ORDER BY ${sort} ASC
     LIMIT ? OFFSET ?`,
    [...params, limit, offset],
  );

  // Apply status filter post-query if needed
  let items = result.values as InventoryItem[];
  if (opts?.status) {
    items = items.filter((i) => i.status === opts.status);
  }

  return {
    items,
    total: countResult.values[0]?.cnt ?? 0,
  };
}

/** Get detailed stock info for a specific part across all locations */
export async function getPartStockDetail(partId: number): Promise<PartStockDetail | null> {
  const db = await getDb();

  const partResult = await db.query(
    'SELECT id, part_number, description FROM parts WHERE id = ?',
    [partId],
  );
  const part = partResult.values[0];
  if (!part) return null;

  const stockResult = await db.query(
    `SELECT s.location_type, s.location_id, s.qty,
       sup.name as supplier_name,
       CASE s.location_type
         WHEN 'warehouse' THEN 'Warehouse'
         WHEN 'pulled' THEN 'Pulled/Staged'
         WHEN 'truck' THEN (SELECT name FROM vehicles WHERE id = s.location_id)
         WHEN 'job' THEN (SELECT job_name FROM jobs WHERE id = s.location_id)
         ELSE s.location_type
       END as location_name
     FROM stock s
     LEFT JOIN suppliers sup ON sup.id = s.supplier_id
     WHERE s.part_id = ? AND s.qty > 0
     ORDER BY s.location_type ASC, s.location_id ASC`,
    [partId],
  );

  const locations = stockResult.values as StockLocation[];
  const totalQty = locations.reduce((sum, loc) => sum + loc.qty, 0);

  return {
    part_id: part.id as number,
    part_number: part.part_number as string,
    description: part.description as string,
    locations,
    total_qty: totalQty,
  };
}

/** Search parts by number or description */
export async function searchParts(
  query: string,
  limit = 20,
): Promise<{ id: number; part_number: string; description: string; warehouse_qty: number }[]> {
  const db = await getDb();
  const term = `%${query}%`;
  const result = await db.query(
    `SELECT p.id, p.part_number, p.description,
       COALESCE((SELECT SUM(qty) FROM stock WHERE part_id = p.id AND location_type = 'warehouse'), 0) as warehouse_qty
     FROM parts p
     WHERE p.is_active = 1 AND (p.part_number LIKE ? OR p.description LIKE ?)
     ORDER BY p.part_number ASC
     LIMIT ?`,
    [term, term, limit],
  );
  return result.values as any[];
}
