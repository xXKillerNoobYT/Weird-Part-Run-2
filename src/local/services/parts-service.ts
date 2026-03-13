/**
 * Local Parts Service — full catalog, hierarchy, brands, suppliers,
 * stock, companions, alternatives, pricing, and forecasting.
 *
 * Covers all functions from api/parts.ts for offline Tauri mode.
 */

import { getDb } from '../db';
import { trackChange } from '../change-tracker';

// ═══════════════════════════════════════════════════════════════
// HIERARCHY — Tree + Category / Style / Type / Color CRUD
// ═══════════════════════════════════════════════════════════════

/** Build the full hierarchy tree: categories → styles → types (with colors). */
export async function getHierarchy(): Promise<any> {
  const db = await getDb();
  const cats = (await db.query(
    `SELECT * FROM part_categories WHERE is_active = 1 ORDER BY sort_order, name`,
  )).values;
  const styles = (await db.query(
    `SELECT * FROM part_styles WHERE is_active = 1 ORDER BY sort_order, name`,
  )).values;
  const types = (await db.query(
    `SELECT * FROM part_types WHERE is_active = 1 ORDER BY sort_order, name`,
  )).values;
  const colors = (await db.query(
    `SELECT * FROM part_colors WHERE is_active = 1 ORDER BY sort_order, name`,
  )).values;
  const tcLinks = (await db.query(`SELECT * FROM type_color_links`)).values;
  const tbLinks = (await db.query(`SELECT * FROM type_brand_links`)).values;

  // Build color map per type
  const colorsByType: Record<number, any[]> = {};
  for (const link of tcLinks as any[]) {
    if (!colorsByType[link.type_id]) colorsByType[link.type_id] = [];
    const c = (colors as any[]).find((cl: any) => cl.id === link.color_id);
    if (c) colorsByType[link.type_id].push({ ...c, link_id: link.id, image_url: link.image_url });
  }

  // Build brand links per type
  const brandsByType: Record<number, any[]> = {};
  for (const link of tbLinks as any[]) {
    if (!brandsByType[link.type_id]) brandsByType[link.type_id] = [];
    brandsByType[link.type_id].push({ link_id: link.id, brand_id: link.brand_id });
  }

  // Assemble tree
  const typesByStyle: Record<number, any[]> = {};
  for (const t of types as any[]) {
    if (!typesByStyle[t.style_id]) typesByStyle[t.style_id] = [];
    typesByStyle[t.style_id].push({
      ...t,
      colors: colorsByType[t.id] ?? [],
      brand_links: brandsByType[t.id] ?? [],
    });
  }

  const stylesByCat: Record<number, any[]> = {};
  for (const s of styles as any[]) {
    if (!stylesByCat[s.category_id]) stylesByCat[s.category_id] = [];
    stylesByCat[s.category_id].push({ ...s, types: typesByStyle[s.id] ?? [] });
  }

  return {
    categories: (cats as any[]).map((c: any) => ({
      ...c,
      styles: stylesByCat[c.id] ?? [],
    })),
  };
}

// ── Categories ──────────────────────────────────────────────────

/** List all part categories. */
export async function getCategories(params?: { search?: string; is_active?: boolean }): Promise<any[]> {
  const db = await getDb();
  const conditions: string[] = [];
  const args: any[] = [];
  if (params?.is_active !== undefined) { conditions.push('is_active = ?'); args.push(params.is_active ? 1 : 0); }
  if (params?.search) { conditions.push('name LIKE ?'); args.push(`%${params.search}%`); }
  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
  return (await db.query(`SELECT * FROM part_categories ${where} ORDER BY sort_order, name`, args)).values;
}

/** Create a new category. */
export async function createCategory(body: any): Promise<any> {
  const db = await getDb();
  const res = await db.run(
    `INSERT INTO part_categories (name, description, sort_order, is_active) VALUES (?, ?, ?, ?)`,
    [body.name, body.description ?? null, body.sort_order ?? 0, body.is_active ?? 1],
  );
  await trackChange('part_categories', res.changes.lastId!, 'INSERT');
  return (await db.query(`SELECT * FROM part_categories WHERE id = ?`, [res.changes.lastId])).values[0];
}

/** Update a category. */
export async function updateCategory(categoryId: number, body: any): Promise<any> {
  const db = await getDb();
  const sets: string[] = [];
  const args: any[] = [];
  for (const [k, v] of Object.entries(body)) {
    sets.push(`${k} = ?`);
    args.push(v);
  }
  if (sets.length) {
    sets.push(`updated_at = datetime('now')`);
    args.push(categoryId);
    await db.run(`UPDATE part_categories SET ${sets.join(', ')} WHERE id = ?`, args);
    await trackChange('part_categories', categoryId, 'UPDATE', Object.keys(body));
  }
  return (await db.query(`SELECT * FROM part_categories WHERE id = ?`, [categoryId])).values[0];
}

/** Delete a category. */
export async function deleteCategory(categoryId: number): Promise<void> {
  const db = await getDb();
  await db.run(`DELETE FROM part_categories WHERE id = ?`, [categoryId]);
  await trackChange('part_categories', categoryId, 'DELETE');
}

// ── Styles ──────────────────────────────────────────────────────

/** List styles for a category. */
export async function listStylesByCategory(categoryId: number, params?: { is_active?: boolean }): Promise<any[]> {
  const db = await getDb();
  const conds = ['category_id = ?'];
  const args: any[] = [categoryId];
  if (params?.is_active !== undefined) { conds.push('is_active = ?'); args.push(params.is_active ? 1 : 0); }
  return (await db.query(`SELECT * FROM part_styles WHERE ${conds.join(' AND ')} ORDER BY sort_order, name`, args)).values;
}

/** Create a style. */
export async function createStyle(body: any): Promise<any> {
  const db = await getDb();
  const res = await db.run(
    `INSERT INTO part_styles (category_id, name, description, image_url, sort_order, is_active) VALUES (?,?,?,?,?,?)`,
    [body.category_id, body.name, body.description ?? null, body.image_url ?? null, body.sort_order ?? 0, body.is_active ?? 1],
  );
  await trackChange('part_styles', res.changes.lastId!, 'INSERT');
  return (await db.query(`SELECT * FROM part_styles WHERE id = ?`, [res.changes.lastId])).values[0];
}

/** Update a style. */
export async function updateStyle(styleId: number, body: any): Promise<any> {
  const db = await getDb();
  const sets: string[] = [];
  const args: any[] = [];
  for (const [k, v] of Object.entries(body)) { sets.push(`${k} = ?`); args.push(v); }
  if (sets.length) {
    sets.push(`updated_at = datetime('now')`);
    args.push(styleId);
    await db.run(`UPDATE part_styles SET ${sets.join(', ')} WHERE id = ?`, args);
    await trackChange('part_styles', styleId, 'UPDATE', Object.keys(body));
  }
  return (await db.query(`SELECT * FROM part_styles WHERE id = ?`, [styleId])).values[0];
}

/** Delete a style. */
export async function deleteStyle(styleId: number): Promise<void> {
  const db = await getDb();
  await db.run(`DELETE FROM part_styles WHERE id = ?`, [styleId]);
  await trackChange('part_styles', styleId, 'DELETE');
}

// ── Types ───────────────────────────────────────────────────────

/** List types for a style. */
export async function listTypesByStyle(styleId: number, params?: { is_active?: boolean }): Promise<any[]> {
  const db = await getDb();
  const conds = ['style_id = ?'];
  const args: any[] = [styleId];
  if (params?.is_active !== undefined) { conds.push('is_active = ?'); args.push(params.is_active ? 1 : 0); }
  return (await db.query(`SELECT * FROM part_types WHERE ${conds.join(' AND ')} ORDER BY sort_order, name`, args)).values;
}

/** Get a single type with enriched context. */
export async function getType(typeId: number): Promise<any> {
  const db = await getDb();
  return (await db.query(`SELECT * FROM part_types WHERE id = ?`, [typeId])).values[0] ?? null;
}

/** Create a type. */
export async function createType(body: any): Promise<any> {
  const db = await getDb();
  const res = await db.run(
    `INSERT INTO part_types (style_id, name, description, color, image_url, sort_order, is_active) VALUES (?,?,?,?,?,?,?)`,
    [body.style_id, body.name, body.description ?? null, body.color ?? null, body.image_url ?? null, body.sort_order ?? 0, body.is_active ?? 1],
  );
  await trackChange('part_types', res.changes.lastId!, 'INSERT');
  return (await db.query(`SELECT * FROM part_types WHERE id = ?`, [res.changes.lastId])).values[0];
}

/** Update a type. */
export async function updateType(typeId: number, body: any): Promise<any> {
  const db = await getDb();
  const sets: string[] = [];
  const args: any[] = [];
  for (const [k, v] of Object.entries(body)) { sets.push(`${k} = ?`); args.push(v); }
  if (sets.length) {
    sets.push(`updated_at = datetime('now')`);
    args.push(typeId);
    await db.run(`UPDATE part_types SET ${sets.join(', ')} WHERE id = ?`, args);
    await trackChange('part_types', typeId, 'UPDATE', Object.keys(body));
  }
  return (await db.query(`SELECT * FROM part_types WHERE id = ?`, [typeId])).values[0];
}

/** Delete a type. */
export async function deleteType(typeId: number): Promise<void> {
  const db = await getDb();
  await db.run(`DELETE FROM part_types WHERE id = ?`, [typeId]);
  await trackChange('part_types', typeId, 'DELETE');
}

/** Get part types for a category (via styles). */
export async function getPartTypes(categoryId?: number): Promise<any[]> {
  const db = await getDb();
  if (categoryId) {
    return (await db.query(
      `SELECT pt.* FROM part_types pt
       JOIN part_styles ps ON ps.id = pt.style_id
       WHERE ps.category_id = ? ORDER BY pt.sort_order, pt.name`,
      [categoryId],
    )).values;
  }
  return (await db.query(`SELECT * FROM part_types ORDER BY style_id, sort_order, name`)).values;
}

// ── Type ↔ Color Links ──────────────────────────────────────────

/** Get colors linked to a type. */
export async function listTypeColors(typeId: number): Promise<any[]> {
  const db = await getDb();
  return (await db.query(
    `SELECT tcl.*, pc.name as color_name, pc.hex_code
     FROM type_color_links tcl
     JOIN part_colors pc ON pc.id = tcl.color_id
     WHERE tcl.type_id = ? ORDER BY tcl.sort_order`,
    [typeId],
  )).values;
}

/** Link colors to a type (bulk, idempotent). */
export async function linkColorsToType(typeId: number, colorIds: number[]): Promise<any[]> {
  const db = await getDb();
  for (const colorId of colorIds) {
    await db.run(
      `INSERT OR IGNORE INTO type_color_links (type_id, color_id) VALUES (?, ?)`,
      [typeId, colorId],
    );
  }
  return listTypeColors(typeId);
}

/** Unlink a color from a type. */
export async function unlinkColorFromType(typeId: number, colorId: number): Promise<void> {
  const db = await getDb();
  await db.run(`DELETE FROM type_color_links WHERE type_id = ? AND color_id = ?`, [typeId, colorId]);
}

// ── Type ↔ Brand Links ─────────────────────────────────────────

/** Get brand links for a type. */
export async function listTypeBrands(typeId: number): Promise<any[]> {
  const db = await getDb();
  return (await db.query(
    `SELECT tbl.*, b.name as brand_name
     FROM type_brand_links tbl
     LEFT JOIN brands b ON b.id = tbl.brand_id
     WHERE tbl.type_id = ?`,
    [typeId],
  )).values;
}

/** Link a brand (or General with null) to a type. */
export async function linkBrandToType(typeId: number, brandId: number | null): Promise<any> {
  const db = await getDb();
  const res = await db.run(
    `INSERT INTO type_brand_links (type_id, brand_id) VALUES (?, ?)
     ON CONFLICT(type_id, COALESCE(brand_id, 0)) DO NOTHING`,
    [typeId, brandId],
  );
  if (res.changes.lastId) await trackChange('type_brand_links', res.changes.lastId, 'INSERT');
  return (await db.query(
    `SELECT * FROM type_brand_links WHERE type_id = ? AND COALESCE(brand_id, 0) = ?`,
    [typeId, brandId ?? 0],
  )).values[0];
}

/** Unlink a brand from a type. */
export async function unlinkBrandFromType(typeId: number, brandId: number | null): Promise<void> {
  const db = await getDb();
  if (brandId === null || brandId === 0) {
    await db.run(`DELETE FROM type_brand_links WHERE type_id = ? AND brand_id IS NULL`, [typeId]);
  } else {
    await db.run(`DELETE FROM type_brand_links WHERE type_id = ? AND brand_id = ?`, [typeId, brandId]);
  }
}

/** List parts under a type + brand combo. */
export async function listPartsForTypeBrand(typeId: number, brandId: number | null): Promise<any[]> {
  const db = await getDb();
  if (brandId === null || brandId === 0) {
    return (await db.query(
      `SELECT * FROM parts WHERE type_id = ? AND brand_id IS NULL AND is_active = 1 ORDER BY name`,
      [typeId],
    )).values;
  }
  return (await db.query(
    `SELECT * FROM parts WHERE type_id = ? AND brand_id = ? AND is_active = 1 ORDER BY name`,
    [typeId, brandId],
  )).values;
}

/** Quick-create a part under type + brand by selecting a color. */
export async function quickCreatePart(typeId: number, brandId: number | null, colorId: number): Promise<any> {
  const db = await getDb();
  // Resolve hierarchy
  const typeRow = (await db.query(`SELECT pt.*, ps.category_id FROM part_types pt JOIN part_styles ps ON ps.id = pt.style_id WHERE pt.id = ?`, [typeId])).values[0] as any;
  const colorRow = (await db.query(`SELECT name FROM part_colors WHERE id = ?`, [colorId])).values[0] as any;
  const brandRow = brandId ? (await db.query(`SELECT name FROM brands WHERE id = ?`, [brandId])).values[0] as any : null;
  const name = `${typeRow?.name ?? ''} ${colorRow?.name ?? ''}${brandRow ? ` (${brandRow.name})` : ''}`.trim();
  const res = await db.run(
    `INSERT INTO parts (category_id, style_id, type_id, color_id, brand_id, name, part_type) VALUES (?,?,?,?,?,?,?)`,
    [typeRow?.category_id, typeRow?.style_id, typeId, colorId, brandId, name, brandId ? 'specific' : 'general'],
  );
  await trackChange('parts', res.changes.lastId!, 'INSERT');
  return (await db.query(`SELECT * FROM parts WHERE id = ?`, [res.changes.lastId])).values[0];
}

// ── Colors ──────────────────────────────────────────────────────

/** List all part colors. */
export async function listColors(params?: { search?: string; is_active?: boolean }): Promise<any[]> {
  const db = await getDb();
  const conds: string[] = [];
  const args: any[] = [];
  if (params?.is_active !== undefined) { conds.push('is_active = ?'); args.push(params.is_active ? 1 : 0); }
  if (params?.search) { conds.push('name LIKE ?'); args.push(`%${params.search}%`); }
  const where = conds.length ? `WHERE ${conds.join(' AND ')}` : '';
  return (await db.query(`SELECT * FROM part_colors ${where} ORDER BY sort_order, name`, args)).values;
}

/** Create a color. */
export async function createColor(body: any): Promise<any> {
  const db = await getDb();
  const res = await db.run(
    `INSERT INTO part_colors (name, hex_code, sort_order, is_active) VALUES (?,?,?,?)`,
    [body.name, body.hex_code ?? null, body.sort_order ?? 0, body.is_active ?? 1],
  );
  await trackChange('part_colors', res.changes.lastId!, 'INSERT');
  return (await db.query(`SELECT * FROM part_colors WHERE id = ?`, [res.changes.lastId])).values[0];
}

/** Update a color. */
export async function updateColor(colorId: number, body: any): Promise<any> {
  const db = await getDb();
  const sets: string[] = [];
  const args: any[] = [];
  for (const [k, v] of Object.entries(body)) { sets.push(`${k} = ?`); args.push(v); }
  if (sets.length) {
    args.push(colorId);
    await db.run(`UPDATE part_colors SET ${sets.join(', ')} WHERE id = ?`, args);
    await trackChange('part_colors', colorId, 'UPDATE', Object.keys(body));
  }
  return (await db.query(`SELECT * FROM part_colors WHERE id = ?`, [colorId])).values[0];
}

/** Delete a color. */
export async function deleteColor(colorId: number): Promise<void> {
  const db = await getDb();
  await db.run(`DELETE FROM part_colors WHERE id = ?`, [colorId]);
  await trackChange('part_colors', colorId, 'DELETE');
}


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

/** Get catalog grouped by category × brand. */
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


// ═══════════════════════════════════════════════════════════════
// PRICING
// ═══════════════════════════════════════════════════════════════

/** Update pricing for a part. */
export async function updatePartPricing(partId: number, body: any): Promise<void> {
  const db = await getDb();
  const sets: string[] = [];
  const args: any[] = [];
  if (body.company_cost_price !== undefined) { sets.push('company_cost_price = ?'); args.push(body.company_cost_price); }
  if (body.company_markup_percent !== undefined) { sets.push('company_markup_percent = ?'); args.push(body.company_markup_percent); }
  if (sets.length) {
    sets.push(`updated_at = datetime('now')`);
    args.push(partId);
    await db.run(`UPDATE parts SET ${sets.join(', ')} WHERE id = ?`, args);
    await trackChange('parts', partId, 'UPDATE', ['company_cost_price', 'company_markup_percent']);
  }
}


// ═══════════════════════════════════════════════════════════════
// STOCK
// ═══════════════════════════════════════════════════════════════

/** Get stock levels for a part across all locations. */
export async function getPartStock(partId: number): Promise<any[]> {
  const db = await getDb();
  return (await db.query(
    `SELECT s.*, sup.name as supplier_name
     FROM stock s
     LEFT JOIN suppliers sup ON sup.id = s.supplier_id
     WHERE s.part_id = ?
     ORDER BY s.location_type, s.location_id`,
    [partId],
  )).values;
}

/** Get aggregated stock summary for a part. */
export async function getPartStockSummary(partId: number): Promise<any> {
  const db = await getDb();
  const rows = (await db.query(
    `SELECT location_type, SUM(qty) as qty FROM stock WHERE part_id = ? GROUP BY location_type`,
    [partId],
  )).values as any[];
  const summary: any = { total: 0, warehouse: 0, truck: 0, pulled: 0, job: 0, trailer: 0 };
  for (const r of rows) {
    summary[r.location_type] = r.qty;
    summary.total += r.qty;
  }
  return summary;
}


// ═══════════════════════════════════════════════════════════════
// PART ↔ SUPPLIER LINKS
// ═══════════════════════════════════════════════════════════════

/** Get suppliers for a part. */
export async function getPartSuppliers(partId: number): Promise<any[]> {
  const db = await getDb();
  return (await db.query(
    `SELECT psl.*, s.name as supplier_name
     FROM part_supplier_links psl
     JOIN suppliers s ON s.id = psl.supplier_id
     WHERE psl.part_id = ?
     ORDER BY psl.is_preferred DESC, s.name ASC`,
    [partId],
  )).values;
}

/** Link a supplier to a part. */
export async function addPartSupplierLink(partId: number, body: any): Promise<void> {
  const db = await getDb();
  const res = await db.run(
    `INSERT INTO part_supplier_links (part_id, supplier_id, supplier_part_number, supplier_cost_price, moq, is_preferred)
     VALUES (?,?,?,?,?,?)`,
    [partId, body.supplier_id, body.supplier_part_number ?? null, body.supplier_cost_price ?? null, body.moq ?? 1, body.is_preferred ?? 0],
  );
  await trackChange('part_supplier_links', res.changes.lastId!, 'INSERT');
}

/** Remove a supplier link. */
export async function removePartSupplierLink(partId: number, linkId: number): Promise<void> {
  const db = await getDb();
  await db.run(`DELETE FROM part_supplier_links WHERE id = ? AND part_id = ?`, [linkId, partId]);
  await trackChange('part_supplier_links', linkId, 'DELETE');
}


// ═══════════════════════════════════════════════════════════════
// BRANDS
// ═══════════════════════════════════════════════════════════════

/** List all brands. */
export async function listBrands(params?: { search?: string; is_active?: boolean }): Promise<any[]> {
  const db = await getDb();
  const conds: string[] = [];
  const args: any[] = [];
  if (params?.is_active !== undefined) { conds.push('b.is_active = ?'); args.push(params.is_active ? 1 : 0); }
  if (params?.search) { conds.push('b.name LIKE ?'); args.push(`%${params.search}%`); }
  const where = conds.length ? `WHERE ${conds.join(' AND ')}` : '';
  return (await db.query(
    `SELECT b.*,
       (SELECT COUNT(*) FROM parts WHERE brand_id = b.id) as part_count,
       (SELECT COUNT(*) FROM brand_supplier_links WHERE brand_id = b.id) as supplier_count
     FROM brands b ${where} ORDER BY b.name`,
    args,
  )).values;
}

/** Get a single brand. */
export async function getBrand(brandId: number): Promise<any> {
  const db = await getDb();
  return (await db.query(`SELECT * FROM brands WHERE id = ?`, [brandId])).values[0] ?? null;
}

/** Create a brand. */
export async function createBrand(body: any): Promise<any> {
  const db = await getDb();
  const res = await db.run(
    `INSERT INTO brands (name, website, notes, is_active) VALUES (?,?,?,?)`,
    [body.name, body.website ?? null, body.notes ?? null, body.is_active ?? 1],
  );
  await trackChange('brands', res.changes.lastId!, 'INSERT');
  return (await db.query(`SELECT * FROM brands WHERE id = ?`, [res.changes.lastId])).values[0];
}

/** Update a brand. */
export async function updateBrand(brandId: number, body: any): Promise<any> {
  const db = await getDb();
  const sets: string[] = [];
  const args: any[] = [];
  for (const [k, v] of Object.entries(body)) { sets.push(`${k} = ?`); args.push(v); }
  if (sets.length) {
    sets.push(`updated_at = datetime('now')`);
    args.push(brandId);
    await db.run(`UPDATE brands SET ${sets.join(', ')} WHERE id = ?`, args);
    await trackChange('brands', brandId, 'UPDATE', Object.keys(body));
  }
  return (await db.query(`SELECT * FROM brands WHERE id = ?`, [brandId])).values[0];
}

/** Delete a brand. */
export async function deleteBrand(brandId: number): Promise<void> {
  const db = await getDb();
  await db.run(`DELETE FROM brands WHERE id = ?`, [brandId]);
  await trackChange('brands', brandId, 'DELETE');
}


// ═══════════════════════════════════════════════════════════════
// BRAND ↔ SUPPLIER LINKS
// ═══════════════════════════════════════════════════════════════

/** Get suppliers carrying a brand. */
export async function getBrandSuppliers(brandId: number): Promise<any[]> {
  const db = await getDb();
  return (await db.query(
    `SELECT bsl.*, s.name as supplier_name
     FROM brand_supplier_links bsl
     JOIN suppliers s ON s.id = bsl.supplier_id
     WHERE bsl.brand_id = ? AND bsl.is_active = 1`,
    [brandId],
  )).values;
}

/** Get brands carried by a supplier. */
export async function getSupplierBrands(supplierId: number): Promise<any[]> {
  const db = await getDb();
  return (await db.query(
    `SELECT bsl.*, b.name as brand_name
     FROM brand_supplier_links bsl
     JOIN brands b ON b.id = bsl.brand_id
     WHERE bsl.supplier_id = ? AND bsl.is_active = 1`,
    [supplierId],
  )).values;
}

/** Create a brand-supplier link. */
export async function createBrandSupplierLink(body: any): Promise<any> {
  const db = await getDb();
  const res = await db.run(
    `INSERT INTO brand_supplier_links (brand_id, supplier_id, account_number, notes)
     VALUES (?,?,?,?)`,
    [body.brand_id, body.supplier_id, body.account_number ?? null, body.notes ?? null],
  );
  await trackChange('brand_supplier_links', res.changes.lastId!, 'INSERT');
  return (await db.query(`SELECT * FROM brand_supplier_links WHERE id = ?`, [res.changes.lastId])).values[0];
}

/** Delete a brand-supplier link. */
export async function deleteBrandSupplierLink(linkId: number): Promise<void> {
  const db = await getDb();
  await db.run(`DELETE FROM brand_supplier_links WHERE id = ?`, [linkId]);
  await trackChange('brand_supplier_links', linkId, 'DELETE');
}


// ═══════════════════════════════════════════════════════════════
// SUPPLIERS
// ═══════════════════════════════════════════════════════════════

/** List all suppliers. */
export async function listSuppliers(params?: { search?: string; is_active?: boolean }): Promise<any[]> {
  const db = await getDb();
  const conds: string[] = [];
  const args: any[] = [];
  if (params?.is_active !== undefined) { conds.push('is_active = ?'); args.push(params.is_active ? 1 : 0); }
  if (params?.search) { conds.push('name LIKE ?'); args.push(`%${params.search}%`); }
  const where = conds.length ? `WHERE ${conds.join(' AND ')}` : '';
  return (await db.query(
    `SELECT s.*,
       (SELECT COUNT(*) FROM brand_supplier_links WHERE supplier_id = s.id) as brand_count
     FROM suppliers s ${where} ORDER BY s.name`,
    args,
  )).values;
}

/** Create a supplier. */
export async function createSupplier(body: any): Promise<any> {
  const db = await getDb();
  const cols = ['name', 'contact_name', 'email', 'phone', 'address', 'website',
    'rep_name', 'rep_email', 'rep_phone', 'notes', 'delivery_method', 'delivery_days',
    'special_order_lead_days', 'delivery_notes', 'driver_name', 'driver_phone', 'driver_email'];
  const vals = cols.map(c => body[c] ?? null);
  const res = await db.run(
    `INSERT INTO suppliers (${cols.join(',')}) VALUES (${cols.map(() => '?').join(',')})`,
    vals,
  );
  await trackChange('suppliers', res.changes.lastId!, 'INSERT');
  return (await db.query(`SELECT * FROM suppliers WHERE id = ?`, [res.changes.lastId])).values[0];
}

/** Update a supplier. */
export async function updateSupplier(supplierId: number, body: any): Promise<any> {
  const db = await getDb();
  const sets: string[] = [];
  const args: any[] = [];
  for (const [k, v] of Object.entries(body)) { sets.push(`${k} = ?`); args.push(v); }
  if (sets.length) {
    sets.push(`updated_at = datetime('now')`);
    args.push(supplierId);
    await db.run(`UPDATE suppliers SET ${sets.join(', ')} WHERE id = ?`, args);
    await trackChange('suppliers', supplierId, 'UPDATE', Object.keys(body));
  }
  return (await db.query(`SELECT * FROM suppliers WHERE id = ?`, [supplierId])).values[0];
}

/** Delete a supplier. */
export async function deleteSupplier(supplierId: number): Promise<void> {
  const db = await getDb();
  await db.run(`DELETE FROM suppliers WHERE id = ?`, [supplierId]);
  await trackChange('suppliers', supplierId, 'DELETE');
}


// ═══════════════════════════════════════════════════════════════
// FORECASTING
// ═══════════════════════════════════════════════════════════════

/** Get forecasting data for all parts. */
export async function getForecasting(params?: {
  page?: number;
  page_size?: number;
}): Promise<{ items: any[]; total: number }> {
  const db = await getDb();
  const limit = params?.page_size ?? 50;
  const offset = params?.page ? (params.page - 1) * limit : 0;
  const total = (await db.query(`SELECT COUNT(*) as cnt FROM parts WHERE is_active = 1`)).values[0] as any;
  const items = (await db.query(
    `SELECT p.id, p.code, p.name, p.brand_id,
       p.forecast_adu_30, p.forecast_adu_90,
       p.forecast_reorder_point, p.forecast_target_qty,
       p.forecast_suggested_order, p.forecast_days_until_low,
       p.forecast_last_run,
       COALESCE((SELECT SUM(qty) FROM stock WHERE part_id = p.id AND location_type = 'warehouse'), 0) as warehouse_qty
     FROM parts p WHERE p.is_active = 1 ORDER BY p.forecast_days_until_low ASC
     LIMIT ? OFFSET ?`,
    [limit, offset],
  )).values;
  return { items: items as any[], total: total?.cnt ?? 0 };
}

/** Recalculate forecasts locally from stock movements. */
export async function recalculateForecasts(): Promise<{ recalculated: number; errors: number; total_parts: number }> {
  const db = await getDb();
  const now = new Date().toISOString();
  const parts = (await db.query(`SELECT id FROM parts WHERE is_active = 1`)).values as any[];
  let recalculated = 0;
  let errors = 0;
  for (const p of parts) {
    try {
      // 30-day ADU
      const m30 = (await db.query(
        `SELECT COALESCE(SUM(qty), 0) as total FROM stock_movements
         WHERE part_id = ? AND movement_type = 'consume'
         AND created_at >= datetime('now', '-30 days')`,
        [p.id],
      )).values[0] as any;
      const adu30 = (m30?.total ?? 0) / 30;
      // 90-day ADU
      const m90 = (await db.query(
        `SELECT COALESCE(SUM(qty), 0) as total FROM stock_movements
         WHERE part_id = ? AND movement_type = 'consume'
         AND created_at >= datetime('now', '-90 days')`,
        [p.id],
      )).values[0] as any;
      const adu90 = (m90?.total ?? 0) / 90;
      const adu = Math.max(adu30, adu90);
      const reorderPoint = Math.ceil(adu * 14); // 2-week lead time
      const target = Math.ceil(adu * 30);
      const whQty = ((await db.query(
        `SELECT COALESCE(SUM(qty), 0) as total FROM stock WHERE part_id = ? AND location_type = 'warehouse'`,
        [p.id],
      )).values[0] as any)?.total ?? 0;
      const daysUntilLow = adu > 0 ? Math.floor(whQty / adu) : 999;
      const suggested = Math.max(0, target - whQty);
      await db.run(
        `UPDATE parts SET forecast_adu_30 = ?, forecast_adu_90 = ?,
         forecast_reorder_point = ?, forecast_target_qty = ?,
         forecast_suggested_order = ?, forecast_days_until_low = ?,
         forecast_last_run = ? WHERE id = ?`,
        [adu30, adu90, reorderPoint, target, suggested, daysUntilLow, now, p.id],
      );
      recalculated++;
    } catch {
      errors++;
    }
  }
  return { recalculated, errors, total_parts: parts.length };
}


// ═══════════════════════════════════════════════════════════════
// IMPORT / EXPORT
// ═══════════════════════════════════════════════════════════════

/** Export parts as CSV string (Tauri mode — returns string, not Blob). */
export async function exportPartsCsv(): Promise<any> {
  const db = await getDb();
  const rows = (await db.query(
    `SELECT p.*, c.name as category_name, b.name as brand_name
     FROM parts p
     LEFT JOIN part_categories c ON c.id = p.category_id
     LEFT JOIN brands b ON b.id = p.brand_id
     WHERE p.is_active = 1 ORDER BY p.name`,
  )).values as any[];
  const header = 'id,code,name,category,brand,cost_price,markup,sell_price,uom,min_stock,max_stock,reorder_point\n';
  const csv = rows.map(r =>
    `${r.id},"${r.code ?? ''}","${r.name}","${r.category_name ?? ''}","${r.brand_name ?? ''}",${r.company_cost_price},${r.company_markup_percent},${r.company_sell_price},"${r.unit_of_measure}",${r.min_stock_level},${r.max_stock_level},${r.reorder_point}`,
  ).join('\n');
  return new Blob([header + csv], { type: 'text/csv' });
}

/** Import parts from CSV. Simplified local version — inserts new parts. */
export async function importPartsCsv(file: File): Promise<any> {
  const text = await file.text();
  const lines = text.split('\n').filter(l => l.trim());
  if (lines.length < 2) return { created: 0, updated: 0, errors: 0, skipped: 0 };
  const db = await getDb();
  let created = 0, errors = 0;
  // Simple CSV parse (assumes no embedded commas in quoted fields for now)
  for (let i = 1; i < lines.length; i++) {
    try {
      const cols = lines[i].split(',').map(c => c.replace(/^"|"$/g, '').trim());
      const [, code, name, , , costStr, markupStr] = cols;
      if (!name) continue;
      const cost = parseFloat(costStr) || 0;
      const markup = parseFloat(markupStr) || 0;
      await db.run(
        `INSERT INTO parts (code, name, category_id, company_cost_price, company_markup_percent)
         VALUES (?, ?, 1, ?, ?)`,
        [code || null, name, cost, markup],
      );
      created++;
    } catch {
      errors++;
    }
  }
  return { created, updated: 0, errors, skipped: 0 };
}


// ═══════════════════════════════════════════════════════════════
// COMPANION RULES
// ═══════════════════════════════════════════════════════════════

/** List all companion rules with sources and targets. */
export async function listCompanionRules(): Promise<any[]> {
  const db = await getDb();
  const rules = (await db.query(`SELECT * FROM companion_rules ORDER BY name`)).values as any[];
  for (const rule of rules) {
    rule.sources = (await db.query(
      `SELECT crs.*, c.name as category_name, s.name as style_name
       FROM companion_rule_sources crs
       JOIN part_categories c ON c.id = crs.category_id
       LEFT JOIN part_styles s ON s.id = crs.style_id
       WHERE crs.rule_id = ?`,
      [rule.id],
    )).values;
    rule.targets = (await db.query(
      `SELECT crt.*, c.name as category_name, s.name as style_name
       FROM companion_rule_targets crt
       JOIN part_categories c ON c.id = crt.category_id
       LEFT JOIN part_styles s ON s.id = crt.style_id
       WHERE crt.rule_id = ?`,
      [rule.id],
    )).values;
  }
  return rules;
}

/** Create a companion rule. */
export async function createCompanionRule(body: any): Promise<any> {
  const db = await getDb();
  const res = await db.run(
    `INSERT INTO companion_rules (name, description, style_match, qty_mode, qty_ratio, is_active, created_by)
     VALUES (?,?,?,?,?,?,?)`,
    [body.name, body.description ?? null, body.style_match ?? 'auto', body.qty_mode ?? 'sum', body.qty_ratio ?? 1.0, body.is_active ?? 1, body.created_by ?? null],
  );
  const ruleId = res.changes.lastId!;
  await trackChange('companion_rules', ruleId, 'INSERT');
  for (const src of body.sources ?? []) {
    await db.run(`INSERT INTO companion_rule_sources (rule_id, category_id, style_id) VALUES (?,?,?)`,
      [ruleId, src.category_id, src.style_id ?? null]);
  }
  for (const tgt of body.targets ?? []) {
    await db.run(`INSERT INTO companion_rule_targets (rule_id, category_id, style_id) VALUES (?,?,?)`,
      [ruleId, tgt.category_id, tgt.style_id ?? null]);
  }
  return (await listCompanionRules()).find(r => r.id === ruleId);
}

/** Update a companion rule. */
export async function updateCompanionRule(ruleId: number, body: any): Promise<any> {
  const db = await getDb();
  const sets: string[] = [];
  const args: any[] = [];
  for (const k of ['name', 'description', 'style_match', 'qty_mode', 'qty_ratio', 'is_active']) {
    if (body[k] !== undefined) { sets.push(`${k} = ?`); args.push(body[k]); }
  }
  if (sets.length) {
    sets.push(`updated_at = datetime('now')`);
    args.push(ruleId);
    await db.run(`UPDATE companion_rules SET ${sets.join(', ')} WHERE id = ?`, args);
    await trackChange('companion_rules', ruleId, 'UPDATE');
  }
  // Replace sources/targets if provided
  if (body.sources) {
    await db.run(`DELETE FROM companion_rule_sources WHERE rule_id = ?`, [ruleId]);
    for (const src of body.sources) {
      await db.run(`INSERT INTO companion_rule_sources (rule_id, category_id, style_id) VALUES (?,?,?)`,
        [ruleId, src.category_id, src.style_id ?? null]);
    }
  }
  if (body.targets) {
    await db.run(`DELETE FROM companion_rule_targets WHERE rule_id = ?`, [ruleId]);
    for (const tgt of body.targets) {
      await db.run(`INSERT INTO companion_rule_targets (rule_id, category_id, style_id) VALUES (?,?,?)`,
        [ruleId, tgt.category_id, tgt.style_id ?? null]);
    }
  }
  return (await listCompanionRules()).find(r => r.id === ruleId);
}

/** Delete a companion rule. */
export async function deleteCompanionRule(ruleId: number): Promise<void> {
  const db = await getDb();
  await db.run(`DELETE FROM companion_rules WHERE id = ?`, [ruleId]);
  await trackChange('companion_rules', ruleId, 'DELETE');
}


// ═══════════════════════════════════════════════════════════════
// COMPANION SUGGESTIONS
// ═══════════════════════════════════════════════════════════════

/** Generate suggestions from input items. */
export async function generateCompanionSuggestions(body: any): Promise<any[]> {
  const db = await getDb();
  const inputItems = body.items ?? [];
  if (!inputItems.length) return [];
  // Match rules where any source matches an input category
  const catIds = [...new Set(inputItems.map((i: any) => i.category_id))];
  const placeholders = catIds.map(() => '?').join(',');
  const matchedRules = (await db.query(
    `SELECT DISTINCT cr.* FROM companion_rules cr
     JOIN companion_rule_sources crs ON crs.rule_id = cr.id
     WHERE cr.is_active = 1 AND crs.category_id IN (${placeholders})`,
    catIds,
  )).values as any[];
  const suggestions: any[] = [];
  for (const rule of matchedRules) {
    const targets = (await db.query(
      `SELECT crt.*, c.name as category_name FROM companion_rule_targets crt
       JOIN part_categories c ON c.id = crt.category_id WHERE crt.rule_id = ?`,
      [rule.id],
    )).values as any[];
    for (const t of targets) {
      const totalQty = inputItems.reduce((sum: number, i: any) => sum + (i.qty ?? 1), 0);
      const suggestedQty = rule.qty_mode === 'sum' ? totalQty : rule.qty_mode === 'max' ? Math.max(...inputItems.map((i: any) => i.qty ?? 1)) : Math.ceil(totalQty * (rule.qty_ratio ?? 1));
      const res = await db.run(
        `INSERT INTO companion_suggestions (rule_id, target_category_id, target_style_id, target_description, suggested_qty, reason_type, reason_text, triggered_by)
         VALUES (?,?,?,?,?,?,?,?)`,
        [rule.id, t.category_id, t.style_id ?? null, `${t.category_name} companion`, suggestedQty, 'rule', `Rule: ${rule.name}`, body.triggered_by ?? null],
      );
      const suggestion = (await db.query(`SELECT * FROM companion_suggestions WHERE id = ?`, [res.changes.lastId])).values[0];
      suggestions.push(suggestion);
    }
  }
  return suggestions;
}

/** List suggestions with filters. */
export async function listCompanionSuggestions(params?: {
  status?: string;
  page?: number;
  page_size?: number;
}): Promise<any[]> {
  const db = await getDb();
  const conds: string[] = [];
  const args: any[] = [];
  if (params?.status) { conds.push('status = ?'); args.push(params.status); }
  const where = conds.length ? `WHERE ${conds.join(' AND ')}` : '';
  const limit = params?.page_size ?? 50;
  const offset = params?.page ? (params.page - 1) * limit : 0;
  return (await db.query(
    `SELECT cs.*, c.name as target_category_name
     FROM companion_suggestions cs
     JOIN part_categories c ON c.id = cs.target_category_id
     ${where} ORDER BY cs.created_at DESC LIMIT ? OFFSET ?`,
    [...args, limit, offset],
  )).values;
}

/** Approve or discard a suggestion. */
export async function decideCompanionSuggestion(suggestionId: number, body: any): Promise<any> {
  const db = await getDb();
  await db.run(
    `UPDATE companion_suggestions SET status = ?, decided_by = ?, decided_at = datetime('now'),
     approved_qty = ?, notes = ? WHERE id = ?`,
    [body.decision, body.decided_by ?? null, body.approved_qty ?? null, body.notes ?? null, suggestionId],
  );
  await trackChange('companion_suggestions', suggestionId, 'UPDATE');
  return (await db.query(`SELECT * FROM companion_suggestions WHERE id = ?`, [suggestionId])).values[0];
}


// ═══════════════════════════════════════════════════════════════
// COMPANION STATS & CO-OCCURRENCE
// ═══════════════════════════════════════════════════════════════

/** Get companion dashboard stats. */
export async function getCompanionStats(): Promise<any> {
  const db = await getDb();
  const rules = (await db.query(`SELECT COUNT(*) as cnt FROM companion_rules WHERE is_active = 1`)).values[0] as any;
  const pending = (await db.query(`SELECT COUNT(*) as cnt FROM companion_suggestions WHERE status = 'pending'`)).values[0] as any;
  const approved = (await db.query(`SELECT COUNT(*) as cnt FROM companion_suggestions WHERE status = 'approved'`)).values[0] as any;
  const pairs = (await db.query(`SELECT COUNT(*) as cnt FROM co_occurrence_pairs`)).values[0] as any;
  return {
    active_rules: rules?.cnt ?? 0,
    pending_suggestions: pending?.cnt ?? 0,
    approved_suggestions: approved?.cnt ?? 0,
    co_occurrence_pairs: pairs?.cnt ?? 0,
  };
}

/** Get top co-occurrence pairs. */
export async function getCoOccurrences(limit = 50): Promise<any[]> {
  const db = await getDb();
  return (await db.query(
    `SELECT cop.*, ca.name as category_a_name, cb.name as category_b_name
     FROM co_occurrence_pairs cop
     JOIN part_categories ca ON ca.id = cop.category_a_id
     JOIN part_categories cb ON cb.id = cop.category_b_id
     ORDER BY cop.co_occurrence_count DESC LIMIT ?`,
    [limit],
  )).values;
}

/** Refresh co-occurrence from stock movements (simplified local version). */
export async function refreshCoOccurrence(): Promise<string> {
  const db = await getDb();
  // Count category co-occurrences from job consumption
  await db.run(`DELETE FROM co_occurrence_pairs`);
  await db.run(
    `INSERT INTO co_occurrence_pairs (category_a_id, category_b_id, co_occurrence_count, last_computed)
     SELECT a.category_id, b.category_id, COUNT(DISTINCT a.job_id), datetime('now')
     FROM (SELECT DISTINCT job_id, p.category_id FROM stock_movements sm JOIN parts p ON p.id = sm.part_id WHERE sm.movement_type = 'consume' AND sm.job_id IS NOT NULL) a
     JOIN (SELECT DISTINCT job_id, p.category_id FROM stock_movements sm JOIN parts p ON p.id = sm.part_id WHERE sm.movement_type = 'consume' AND sm.job_id IS NOT NULL) b
     ON a.job_id = b.job_id AND a.category_id < b.category_id
     GROUP BY a.category_id, b.category_id`,
  );
  return 'Co-occurrence pairs refreshed from job consumption data';
}


// ═══════════════════════════════════════════════════════════════
// PART ALTERNATIVES
// ═══════════════════════════════════════════════════════════════

/** List alternatives for a part (bidirectional). */
export async function listPartAlternatives(partId: number): Promise<any[]> {
  const db = await getDb();
  return (await db.query(
    `SELECT pa.*, p.name as alternative_name, p.code as alternative_code
     FROM part_alternatives pa
     JOIN parts p ON p.id = pa.alternative_part_id
     WHERE pa.part_id = ?
     UNION ALL
     SELECT pa.*, p.name as alternative_name, p.code as alternative_code
     FROM part_alternatives pa
     JOIN parts p ON p.id = pa.part_id
     WHERE pa.alternative_part_id = ?`,
    [partId, partId],
  )).values;
}

/** Link an alternative part. */
export async function linkPartAlternative(partId: number, body: any): Promise<any> {
  const db = await getDb();
  const res = await db.run(
    `INSERT INTO part_alternatives (part_id, alternative_part_id, relationship, preference, notes, created_by)
     VALUES (?,?,?,?,?,?)`,
    [partId, body.alternative_part_id, body.relationship ?? 'substitute', body.preference ?? 0, body.notes ?? null, body.created_by ?? null],
  );
  await trackChange('part_alternatives', res.changes.lastId!, 'INSERT');
  return (await db.query(`SELECT * FROM part_alternatives WHERE id = ?`, [res.changes.lastId])).values[0];
}

/** Update an alternative link. */
export async function updatePartAlternative(linkId: number, body: any): Promise<any> {
  const db = await getDb();
  const sets: string[] = [];
  const args: any[] = [];
  for (const [k, v] of Object.entries(body)) { sets.push(`${k} = ?`); args.push(v); }
  if (sets.length) {
    args.push(linkId);
    await db.run(`UPDATE part_alternatives SET ${sets.join(', ')} WHERE id = ?`, args);
    await trackChange('part_alternatives', linkId, 'UPDATE', Object.keys(body));
  }
  return (await db.query(`SELECT * FROM part_alternatives WHERE id = ?`, [linkId])).values[0];
}

/** Remove an alternative link. */
export async function unlinkPartAlternative(linkId: number): Promise<void> {
  const db = await getDb();
  await db.run(`DELETE FROM part_alternatives WHERE id = ?`, [linkId]);
  await trackChange('part_alternatives', linkId, 'DELETE');
}
