/**
 * Parts Pricing Service — price updates for parts.
 */

import { getDb } from '../../db';
import { trackChange } from '../../change-tracker';

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
