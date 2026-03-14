/**
 * Parts Hierarchy Service — Tree + Category / Style / Type / Color CRUD,
 * Type↔Color links, Type↔Brand links.
 */

import { getDb } from '../../db';
import { trackChange } from '../../change-tracker';

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
