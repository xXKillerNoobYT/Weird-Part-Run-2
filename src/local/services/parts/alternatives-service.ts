/**
 * Parts Alternatives Service — bidirectional part alternative links.
 */

import { getDb } from '../../db';
import { trackChange } from '../../change-tracker';

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
