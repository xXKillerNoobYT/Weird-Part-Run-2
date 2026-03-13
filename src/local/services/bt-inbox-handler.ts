/**
 * BT Inbox Handler — applies sync changes received via Multipeer Connectivity.
 *
 * Multipeer messages arrive as JSON arrays of change objects (same format
 * as the LAN sync protocol). This module applies them to local SQLite
 * using the same logic as peer-manager.applyPeerChanges().
 *
 * Separated from bt-service.ts to avoid circular imports (bt-service
 * doesn't import db.ts directly).
 */

import { getDb } from '../db';

/**
 * Apply sync changes received from a Multipeer peer.
 *
 * Each change object has:
 *   - table_name: string
 *   - record_id: string | number
 *   - operation: 'INSERT' | 'UPDATE' | 'DELETE'
 *   - record_data?: object | string (full row for INSERT/UPDATE)
 *   - changed_fields?: object | string (partial fields for UPDATE)
 *
 * @param changes — array of change objects
 * @param fromDeviceId — the device_id of the peer that sent these changes
 */
export default async function applyChanges(
  changes: any[],
  fromDeviceId: string,
): Promise<{ applied: number; errors: number }> {
  const db = await getDb();
  let applied = 0;
  let errors = 0;

  for (const change of changes) {
    const { table_name, record_id, operation, record_data, changed_fields } = change;

    try {
      if (operation === 'DELETE') {
        // Soft delete if table supports it, hard delete as fallback
        try {
          await db.run(
            `UPDATE [${table_name}] SET deleted_at = datetime('now') WHERE id = ?`,
            [record_id],
          );
        } catch {
          await db.run(`DELETE FROM [${table_name}] WHERE id = ?`, [record_id]);
        }
        applied++;
      } else if (record_data) {
        // Full record — INSERT OR REPLACE
        const data = typeof record_data === 'string'
          ? JSON.parse(record_data)
          : record_data;
        const keys = Object.keys(data);
        const placeholders = keys.map(() => '?').join(', ');
        const values = keys.map((k) => data[k]);

        await db.run(
          `INSERT OR REPLACE INTO [${table_name}] (${keys.join(', ')}) VALUES (${placeholders})`,
          values,
        );
        applied++;
      } else if (changed_fields && operation === 'UPDATE') {
        // Partial update — only changed fields
        const fields = typeof changed_fields === 'string'
          ? JSON.parse(changed_fields)
          : changed_fields;
        const keys = Object.keys(fields);
        if (keys.length === 0) continue;

        const setClause = keys.map((k) => `${k} = ?`).join(', ');
        const values = keys.map((k) => fields[k]);

        await db.run(
          `UPDATE [${table_name}] SET ${setClause} WHERE id = ?`,
          [...values, record_id],
        );
        applied++;
      }
    } catch (err) {
      console.error(
        `[bt-inbox] Failed to apply ${operation} on ${table_name}.${record_id} from ${fromDeviceId}:`,
        err,
      );
      errors++;
    }
  }

  if (applied > 0) {
    console.log(`[bt-inbox] Applied ${applied} changes from ${fromDeviceId} (${errors} errors)`);
  }

  return { applied, errors };
}
