/**
 * Local Parts Service — read-only catalog access for offline use.
 *
 * Field workers can browse the parts catalog, search by number/description,
 * view hierarchy (categories → types), and check pricing.
 *
 * All data is synced from the shop. No local writes to parts tables.
 */

import { getDb } from '../db';

// ── Types ──────────────────────────────────────────────────────────

export interface Part {
  id: number;
  part_number: string;
  description: string;
  category_id: number | null;
  type_id: number | null;
  brand_id: number | null;
  uom: string;
  company_cost_price: number;
  company_sell_price: number;
  min_stock_level: number;
  max_stock_level: number;
  reorder_point: number;
  is_active: number;
  shelf_location: string | null;
  bin_location: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
  // Joined
  category_name?: string;
  type_name?: string;
  brand_name?: string;
  warehouse_qty?: number;
}

export interface Category {
  id: number;
  name: string;
  description: string | null;
  parent_id: number | null;
  color: string | null;
  sort_order: number;
  is_active: number;
}

export interface PartType {
  id: number;
  name: string;
  category_id: number;
  description: string | null;
  color: string | null;
  sort_order: number;
}

// ── Service Functions ──────────────────────────────────────────────

/** List parts with search and filters */
export async function listParts(opts?: {
  search?: string;
  category_id?: number;
  type_id?: number;
  brand_id?: number;
  limit?: number;
  offset?: number;
}): Promise<{ items: Part[]; total: number }> {
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
  if (opts?.type_id) {
    conditions.push('p.type_id = ?');
    params.push(opts.type_id);
  }
  if (opts?.brand_id) {
    conditions.push('p.brand_id = ?');
    params.push(opts.brand_id);
  }

  const where = `WHERE ${conditions.join(' AND ')}`;
  const limit = opts?.limit ?? 100;
  const offset = opts?.offset ?? 0;

  const countResult = await db.query(
    `SELECT COUNT(*) as cnt FROM parts p ${where}`,
    params,
  );

  const result = await db.query(
    `SELECT p.*,
       c.name as category_name,
       pt.name as type_name,
       b.name as brand_name,
       COALESCE((SELECT SUM(qty) FROM stock WHERE part_id = p.id AND location_type = 'warehouse'), 0) as warehouse_qty
     FROM parts p
     LEFT JOIN categories c ON c.id = p.category_id
     LEFT JOIN part_types pt ON pt.id = p.type_id
     LEFT JOIN brands b ON b.id = p.brand_id
     ${where}
     ORDER BY p.part_number ASC
     LIMIT ? OFFSET ?`,
    [...params, limit, offset],
  );

  return {
    items: result.values as Part[],
    total: countResult.values[0]?.cnt ?? 0,
  };
}

/** Get a single part with full details */
export async function getPart(partId: number): Promise<Part | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT p.*,
       c.name as category_name,
       pt.name as type_name,
       b.name as brand_name,
       COALESCE((SELECT SUM(qty) FROM stock WHERE part_id = p.id AND location_type = 'warehouse'), 0) as warehouse_qty
     FROM parts p
     LEFT JOIN categories c ON c.id = p.category_id
     LEFT JOIN part_types pt ON pt.id = p.type_id
     LEFT JOIN brands b ON b.id = p.brand_id
     WHERE p.id = ?`,
    [partId],
  );
  return (result.values[0] as Part) ?? null;
}

/** Quick search for part picker components */
export async function searchParts(
  query: string,
  limit = 15,
): Promise<Pick<Part, 'id' | 'part_number' | 'description' | 'warehouse_qty'>[]> {
  const db = await getDb();
  const term = `%${query}%`;
  const result = await db.query(
    `SELECT p.id, p.part_number, p.description,
       COALESCE((SELECT SUM(qty) FROM stock WHERE part_id = p.id AND location_type = 'warehouse'), 0) as warehouse_qty
     FROM parts p
     WHERE p.is_active = 1 AND (p.part_number LIKE ? OR p.description LIKE ?)
     ORDER BY
       CASE WHEN p.part_number LIKE ? THEN 0 ELSE 1 END,
       p.part_number ASC
     LIMIT ?`,
    [term, term, `${query}%`, limit],
  );
  return result.values as any[];
}

/** Get all categories (for navigation/filtering) */
export async function getCategories(): Promise<Category[]> {
  const db = await getDb();
  const result = await db.query(
    'SELECT * FROM categories WHERE is_active = 1 ORDER BY sort_order ASC, name ASC',
  );
  return result.values as Category[];
}

/** Get part types for a category */
export async function getPartTypes(categoryId?: number): Promise<PartType[]> {
  const db = await getDb();
  if (categoryId) {
    const result = await db.query(
      'SELECT * FROM part_types WHERE category_id = ? ORDER BY sort_order ASC, name ASC',
      [categoryId],
    );
    return result.values as PartType[];
  }
  const result = await db.query(
    'SELECT * FROM part_types ORDER BY category_id ASC, sort_order ASC, name ASC',
  );
  return result.values as PartType[];
}

/** Get suppliers for a part (for ordering) */
export async function getPartSuppliers(
  partId: number,
): Promise<{ supplier_id: number; supplier_name: string; sku: string | null; cost: number | null }[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT ps.supplier_id, s.name as supplier_name,
       ps.supplier_sku as sku, ps.supplier_cost_price as cost
     FROM part_suppliers ps
     JOIN suppliers s ON s.id = ps.supplier_id
     WHERE ps.part_id = ?
     ORDER BY ps.is_preferred DESC, s.name ASC`,
    [partId],
  );
  return result.values as any[];
}
