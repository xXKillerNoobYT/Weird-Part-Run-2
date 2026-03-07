/**
 * Change Tracker — logs all local writes for sync.
 *
 * Every INSERT, UPDATE, DELETE on the local SQLite database is
 * logged to the `_change_log` table. The sync engine reads this
 * log to know what changes to push to the shop server.
 *
 * The change log is append-only. Entries are marked as synced
 * (but never deleted) so we have a full audit trail.
 */

import { getDb } from './db';
import { getDeviceId } from '../lib/device-identity';

export interface ChangeLogEntry {
  id: number;
  device_id: string;
  table_name: string;
  record_id: number;
  operation: 'INSERT' | 'UPDATE' | 'DELETE';
  changed_fields: string | null;
  old_values: string | null;
  timestamp: string;
  synced: number;
  sync_batch_id: string | null;
}

/**
 * Log a write operation for future sync.
 *
 * Call this after every INSERT, UPDATE, or DELETE in a local service.
 * The sync engine will pick up unsynced entries and push them to the shop.
 */
export async function trackChange(
  tableName: string,
  recordId: number,
  operation: 'INSERT' | 'UPDATE' | 'DELETE',
  changedFields?: Record<string, any>,
  oldValues?: Record<string, any>,
): Promise<void> {
  const db = await getDb();
  const deviceId = await getDeviceId();

  await db.run(
    `INSERT INTO _change_log
       (device_id, table_name, record_id, operation, changed_fields, old_values)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [
      deviceId,
      tableName,
      recordId,
      operation,
      changedFields ? JSON.stringify(changedFields) : null,
      oldValues ? JSON.stringify(oldValues) : null,
    ],
  );
}

/** Get all unsynced changes, ordered by timestamp */
export async function getPendingChanges(): Promise<ChangeLogEntry[]> {
  const db = await getDb();
  const result = await db.query(
    'SELECT * FROM _change_log WHERE synced = 0 ORDER BY timestamp ASC',
  );
  return result.values as ChangeLogEntry[];
}

/** Get count of unsynced changes (for UI badge) */
export async function getPendingChangeCount(): Promise<number> {
  const db = await getDb();
  const result = await db.query(
    'SELECT COUNT(*) as cnt FROM _change_log WHERE synced = 0',
  );
  return result.values[0]?.cnt ?? 0;
}

/** Mark changes as synced after successful push to shop */
export async function markSynced(
  ids: number[],
  batchId: string,
): Promise<void> {
  if (ids.length === 0) return;
  const db = await getDb();
  const placeholders = ids.map(() => '?').join(',');
  await db.run(
    `UPDATE _change_log SET synced = 1, sync_batch_id = ?
     WHERE id IN (${placeholders})`,
    [batchId, ...ids],
  );
}

/** Clean up old synced entries (keep last 30 days) */
export async function pruneOldChanges(): Promise<number> {
  const db = await getDb();
  const result = await db.run(
    `DELETE FROM _change_log
     WHERE synced = 1 AND timestamp < datetime('now', '-30 days')`,
  );
  return result.changes.changes;
}
