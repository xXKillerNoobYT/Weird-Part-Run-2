/**
 * Parts Suppliers Service — Part↔Supplier links, Brands, Brand↔Supplier links,
 * and Supplier CRUD.
 */

import { getDb } from '../../db';
import { trackChange } from '../../change-tracker';

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
