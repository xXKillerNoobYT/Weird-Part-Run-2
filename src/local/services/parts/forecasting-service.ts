/**
 * Parts Forecasting Service — demand forecasting and ADU calculation.
 */

import { getDb } from '../../db';

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
