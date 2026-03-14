/**
 * Parts Catalog Service — list, get, create, update, delete, stats,
 * groups, pending part numbers.
 */

import { getDb } from '../../db';
import { trackChange } from '../../change-tracker';

// ═══════════════════════════════════════════════════════════════
// CATALOG — list, get, create, update, delete, stats, groups
// ═══════════════════════════════════════════════════════════════

/** List parts with search and filters. */
export async function listParts(opts?: {
  search?: string;
  category_id?: number;
  style_id?: number;
  type_id?: number;
  brand_id?: number;
  is_deprecated?: boolean;
  limit?: number;
  offset?: number;
  page?: number;
  page_size?: number;
}): Promise<{ items: any[]; total: number }> {
  const db = await getDb();
  const conditions: string[] = ['p.is_active = 1'];
  const params: any[] = [];

  if (opts?.search) {
    conditions.push('(p.name LIKE ? OR p.code LIKE ? OR p.description LIKE ?)');
    const term = `%${opts.search}%`;
    params.push(term, term, term);
  }
  if (opts?.category_id) { conditions.push('p.category_id = ?'); params.push(opts.category_id); }
  if (opts?.style_id) { conditions.push('p.style_id = ?'); params.push(opts.style_id); }
  if (opts?.type_id) { conditions.push('p.type_id = ?'); params.push(opts.type_id); }
  if (opts?.brand_id) { conditions.push('p.brand_id = ?'); params.push(opts.brand_id); }
  if (opts?.is_deprecated !== undefined) { conditions.push('p.is_deprecated = ?'); params.push(opts.is_deprecated ? 1 : 0); }

  const where = `WHERE ${conditions.join(' AND ')}`;
  const limit = opts?.page_size ?? opts?.limit ?? 100;
  const offset = opts?.page ? (opts.page - 1) * limit : (opts?.offset ?? 0);

  const countResult = await db.query(`SELECT COUNT(*) as cnt FROM parts p ${where}`, params);
  const result = await db.query(
    `SELECT p.*,
       c.name as category_name,
       ps.name as style_name,
       pt.name as type_name,
       b.name as brand_name,
       pc.name as color_name,
       COALESCE((SELECT SUM(qty) FROM stock WHERE part_id = p.id AND location_type = 'warehouse'), 0) as warehouse_qty
     FROM parts p
     LEFT JOIN part_categories c ON c.id = p.category_id
     LEFT JOIN part_styles ps ON ps.id = p.style_id
     LEFT JOIN part_types pt ON pt.id = p.type_id
     LEFT JOIN brands b ON b.id = p.brand_id
     LEFT JOIN part_colors pc ON pc.id = p.color_id
     ${where}
     ORDER BY p.name ASC
     LIMIT ? OFFSET ?`,
    [...params, limit, offset],
  );
  return { items: result.values as any[], total: countResult.values[0]?.cnt ?? 0 };
}

/** Get a single part with full details. */
export async function getPart(partId: number): Promise<any | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT p.*,
       c.name as category_name,
       ps.name as style_name,
       pt.name as type_name,
       b.name as brand_name,
       pc.name as color_name,
       COALESCE((SELECT SUM(qty) FROM stock WHERE part_id = p.id AND location_type = 'warehouse'), 0) as warehouse_qty
     FROM parts p
     LEFT JOIN part_categories c ON c.id = p.category_id
     LEFT JOIN part_styles ps ON ps.id = p.style_id
     LEFT JOIN part_types pt ON pt.id = p.type_id
     LEFT JOIN brands b ON b.id = p.brand_id
     LEFT JOIN part_colors pc ON pc.id = p.color_id
     WHERE p.id = ?`,
    [partId],
  );
  return result.values[0] ?? null;
}

/** Quick search for part picker components. */
export async function searchParts(query: string, limit = 15): Promise<any[]> {
  const db = await getDb();
  const term = `%${query}%`;
  return (await db.query(
    `SELECT p.id, p.code as part_number, p.name as description,
       COALESCE((SELECT SUM(qty) FROM stock WHERE part_id = p.id AND location_type = 'warehouse'), 0) as warehouse_qty
     FROM parts p
     WHERE p.is_active = 1 AND (p.code LIKE ? OR p.name LIKE ?)
     ORDER BY CASE WHEN p.code LIKE ? THEN 0 ELSE 1 END, p.name ASC
     LIMIT ?`,
    [term, term, `${query}%`, limit],
  )).values;
}

/** Create a new part. */
export async function createPart(body: any): Promise<any> {
  const db = await getDb();
  const cols = ['category_id', 'style_id', 'type_id', 'color_id', 'brand_id', 'code', 'name',
    'description', 'part_type', 'manufacturer_part_number', 'unit_of_measure',
    'company_cost_price', 'company_markup_percent', 'min_stock_level', 'max_stock_level',
    'target_stock_level', 'reorder_point', 'notes', 'shelf_location', 'bin_location'];
  const vals = cols.map(c => body[c] ?? null);
  const placeholders = cols.map(() => '?').join(',');
  const res = await db.run(`INSERT INTO parts (${cols.join(',')}) VALUES (${placeholders})`, vals);
  await trackChange('parts', res.changes.lastId!, 'INSERT');
  return getPart(res.changes.lastId!);
}

/** Update an existing part. */
export async function updatePart(partId: number, body: any): Promise<any> {
  const db = await getDb();
  const sets: string[] = [];
  const args: any[] = [];
  for (const [k, v] of Object.entries(body)) { sets.push(`${k} = ?`); args.push(v); }
  if (sets.length) {
    sets.push(`updated_at = datetime('now')`);
    args.push(partId);
    await db.run(`UPDATE parts SET ${sets.join(', ')} WHERE id = ?`, args);
    await trackChange('parts', partId, 'UPDATE', Object.keys(body));
  }
  return getPart(partId);
}

/** Delete a part (only works if no stock exists). */
export async function deletePart(partId: number): Promise<void> {
  const db = await getDb();
  const stock = (await db.query(`SELECT SUM(qty) as total FROM stock WHERE part_id = ?`, [partId])).values[0] as any;
  if (stock?.total > 0) throw new Error('Cannot delete part with existing stock');
  await db.run(`DELETE FROM parts WHERE id = ?`, [partId]);
  await trackChange('parts', partId, 'DELETE');
}

/** Get catalog summary stats. */
export async function getCatalogStats(): Promise<any> {
  const db = await getDb();
  const parts = (await db.query(`SELECT COUNT(*) as cnt FROM parts WHERE is_active = 1`)).values[0] as any;
  const cats = (await db.query(`SELECT COUNT(*) as cnt FROM part_categories WHERE is_active = 1`)).values[0] as any;
  const brands = (await db.query(`SELECT COUNT(*) as cnt FROM brands WHERE is_active = 1`)).values[0] as any;
  const suppliers = (await db.query(`SELECT COUNT(*) as cnt FROM suppliers WHERE is_active = 1`)).values[0] as any;
  const deprecated = (await db.query(`SELECT COUNT(*) as cnt FROM parts WHERE is_deprecated = 1`)).values[0] as any;
  return {
    total_parts: parts?.cnt ?? 0,
    total_categories: cats?.cnt ?? 0,
    total_brands: brands?.cnt ?? 0,
    total_suppliers: suppliers?.cnt ?? 0,
    deprecated_parts: deprecated?.cnt ?? 0,
  };
}

/** Get catalog grouped by category x brand. */
export async function getCatalogGroups(params?: {
  search?: string;
  category_id?: number;
  is_deprecated?: boolean;
}): Promise<any[]> {
  const db = await getDb();
  const conds = ['p.is_active = 1'];
  const args: any[] = [];
  if (params?.search) { conds.push('(p.name LIKE ? OR p.code LIKE ?)'); const t = `%${params.search}%`; args.push(t, t); }
  if (params?.category_id) { conds.push('p.category_id = ?'); args.push(params.category_id); }
  if (params?.is_deprecated !== undefined) { conds.push('p.is_deprecated = ?'); args.push(params.is_deprecated ? 1 : 0); }
  const where = conds.join(' AND ');
  const rows = (await db.query(
    `SELECT p.category_id, c.name as category_name, p.brand_id, b.name as brand_name, COUNT(*) as part_count
     FROM parts p
     LEFT JOIN part_categories c ON c.id = p.category_id
     LEFT JOIN brands b ON b.id = p.brand_id
     WHERE ${where}
     GROUP BY p.category_id, p.brand_id
     ORDER BY c.name, b.name`,
    args,
  )).values;
  return rows as any[];
}


// ═══════════════════════════════════════════════════════════════
// PENDING PART NUMBERS
// ═══════════════════════════════════════════════════════════════

/** Get branded parts missing MPN. */
export async function getPendingPartNumbers(params?: {
  brand_id?: number;
  page?: number;
  page_size?: number;
}): Promise<{ items: any[]; total: number }> {
  const db = await getDb();
  const conds = ['p.brand_id IS NOT NULL', '(p.manufacturer_part_number IS NULL OR p.manufacturer_part_number = \'\')'];
  const args: any[] = [];
  if (params?.brand_id) { conds.push('p.brand_id = ?'); args.push(params.brand_id); }
  const where = conds.join(' AND ');
  const limit = params?.page_size ?? 50;
  const offset = params?.page ? (params.page - 1) * limit : 0;
  const total = (await db.query(`SELECT COUNT(*) as cnt FROM parts p WHERE ${where}`, args)).values[0] as any;
  const items = (await db.query(
    `SELECT p.*, b.name as brand_name FROM parts p LEFT JOIN brands b ON b.id = p.brand_id WHERE ${where} ORDER BY p.name LIMIT ? OFFSET ?`,
    [...args, limit, offset],
  )).values;
  return { items: items as any[], total: total?.cnt ?? 0 };
}

/** Get count of pending part numbers. */
export async function getPendingPartNumbersCount(): Promise<number> {
  const db = await getDb();
  const r = (await db.query(
    `SELECT COUNT(*) as cnt FROM parts WHERE brand_id IS NOT NULL AND (manufacturer_part_number IS NULL OR manufacturer_part_number = '')`,
  )).values[0] as any;
  return r?.cnt ?? 0;
}
