/**
 * Parts Companions Service — companion rules, suggestions, stats,
 * and co-occurrence analysis.
 */

import { getDb } from '../../db';
import { trackChange } from '../../change-tracker';

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
