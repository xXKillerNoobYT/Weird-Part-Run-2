/**
 * Parts Stock Service — stock levels and summaries per part.
 */

import { getDb } from '../../db';

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
