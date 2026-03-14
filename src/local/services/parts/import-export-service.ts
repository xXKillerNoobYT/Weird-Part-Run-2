/**
 * Parts Import/Export Service — CSV export and import.
 */

import { getDb } from '../../db';

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
