/**
 * Conflict Resolver — LWW + Field-Level Merge for P2P Sync
 *
 * When two devices modify the same record offline, we need to decide
 * which version wins. The strategy:
 *
 * 1. Field-level merge: If Device A changes `part.name` and Device B
 *    changes `part.sell_price`, BOTH changes apply (no conflict).
 *
 * 2. Last-write-wins (LWW): If both devices change `part.sell_price`,
 *    the later timestamp wins.
 *
 * 3. Conflict logging: All overwrites are logged to `_conflict_log`
 *    so an admin can review and fix if needed.
 *
 * This replaces the naive INSERT OR REPLACE in peer-manager's
 * applyPeerChanges for UPDATE operations.
 */

import { getDb } from './db';
import { getDeviceId } from '../lib/device-identity';

// ── Types ────────────────────────────────────────────────────────────

export interface IncomingChange {
  id?: number;
  device_id: string;
  table_name: string;
  record_id: string;
  operation: 'INSERT' | 'UPDATE' | 'DELETE';
  changed_fields?: string | Record<string, any> | null;
  old_values?: string | Record<string, any> | null;
  record_data?: string | Record<string, any> | null;
  timestamp: string;
}

export interface ConflictEntry {
  table_name: string;
  record_id: string;
  field_name: string;
  local_value: string | null;
  remote_value: string | null;
  winner: 'local' | 'remote';
  local_device: string;
  remote_device: string;
  local_ts: string;
  remote_ts: string;
}

export interface MergeResult {
  applied: number;
  conflicts: number;
  skipped: number;
  errors: number;
}

// ── Core Resolution Engine ───────────────────────────────────────────

/**
 * Apply incoming peer changes with field-level merge and conflict resolution.
 *
 * For each incoming change:
 * - INSERT: Accept if the record doesn't exist locally, merge if it does
 * - UPDATE: Field-level merge with LWW per-field
 * - DELETE: Soft delete (with hard delete fallback)
 */
export async function resolveAndApplyChanges(
  changes: IncomingChange[],
): Promise<MergeResult> {
  const db = await getDb();
  const localDeviceId = await getDeviceId();
  const result: MergeResult = { applied: 0, conflicts: 0, skipped: 0, errors: 0 };

  for (const change of changes) {
    try {
      if (change.operation === 'DELETE') {
        await applyDelete(db, change);
        result.applied++;
      } else if (change.operation === 'INSERT') {
        const hadConflict = await applyInsert(db, change, localDeviceId);
        result.applied++;
        if (hadConflict) result.conflicts++;
      } else if (change.operation === 'UPDATE') {
        const conflictCount = await applyUpdate(db, change, localDeviceId);
        result.applied++;
        result.conflicts += conflictCount;
      } else {
        result.skipped++;
      }
    } catch (err) {
      console.error(
        `[conflict-resolver] Failed to apply ${change.operation} on ${change.table_name}.${change.record_id}:`,
        err,
      );
      result.errors++;
    }
  }

  return result;
}

// ── DELETE Handler ─────────────────────────────────────────────────

async function applyDelete(db: any, change: IncomingChange): Promise<void> {
  // Use soft delete if the table has deleted_at column
  try {
    await db.run(
      `UPDATE [${change.table_name}] SET deleted_at = ? WHERE id = ?`,
      [change.timestamp, change.record_id],
    );
  } catch {
    // Table may not have deleted_at — fall back to hard delete
    await db.run(
      `DELETE FROM [${change.table_name}] WHERE id = ?`,
      [change.record_id],
    );
  }
}

// ── INSERT Handler ─────────────────────────────────────────────────

/**
 * Apply an INSERT change. If the record already exists locally,
 * treat it as a merge (the same record was created on two devices
 * — use LWW per field).
 *
 * Returns true if there was a conflict (record already existed).
 */
async function applyInsert(
  db: any,
  change: IncomingChange,
  localDeviceId: string,
): Promise<boolean> {
  const data = parseJsonField(change.record_data);
  if (!data) return false;

  // Check if record already exists locally
  const existing = await getLocalRecord(db, change.table_name, change.record_id);

  if (!existing) {
    // Simple insert — no conflict
    const keys = Object.keys(data);
    const placeholders = keys.map(() => '?').join(', ');
    const values = keys.map((k) => data[k]);
    await db.run(
      `INSERT OR IGNORE INTO [${change.table_name}] (${keys.join(', ')}) VALUES (${placeholders})`,
      values,
    );
    return false;
  }

  // Record exists — merge fields using LWW
  const localTimestamp = existing.updated_at ?? existing.created_at ?? '1970-01-01';
  const remoteTimestamp = change.timestamp;

  // Get which fields were locally modified since last sync
  const localChangedFields = await getLocalChangedFields(
    db, change.table_name, change.record_id,
  );

  const mergedData: Record<string, any> = {};
  const conflicts: ConflictEntry[] = [];

  for (const [field, remoteValue] of Object.entries(data)) {
    if (field === 'id') continue; // Never overwrite primary key

    const localValue = existing[field];
    const locallyModified = localChangedFields.has(field);

    if (!locallyModified) {
      // Field not locally modified — accept remote value
      mergedData[field] = remoteValue;
    } else if (remoteTimestamp > localTimestamp) {
      // Both modified, remote is newer — remote wins
      mergedData[field] = remoteValue;
      conflicts.push({
        table_name: change.table_name,
        record_id: change.record_id,
        field_name: field,
        local_value: stringifyValue(localValue),
        remote_value: stringifyValue(remoteValue),
        winner: 'remote',
        local_device: localDeviceId,
        remote_device: change.device_id,
        local_ts: localTimestamp,
        remote_ts: remoteTimestamp,
      });
    } else {
      // Both modified, local is newer — local wins (keep current value)
      conflicts.push({
        table_name: change.table_name,
        record_id: change.record_id,
        field_name: field,
        local_value: stringifyValue(localValue),
        remote_value: stringifyValue(remoteValue),
        winner: 'local',
        local_device: localDeviceId,
        remote_device: change.device_id,
        local_ts: localTimestamp,
        remote_ts: remoteTimestamp,
      });
    }
  }

  // Apply merged fields
  if (Object.keys(mergedData).length > 0) {
    const setClause = Object.keys(mergedData).map((k) => `${k} = ?`).join(', ');
    const values = Object.values(mergedData);
    await db.run(
      `UPDATE [${change.table_name}] SET ${setClause} WHERE id = ?`,
      [...values, change.record_id],
    );
  }

  // Log conflicts
  if (conflicts.length > 0) {
    await logConflicts(db, conflicts);
  }

  return conflicts.length > 0;
}

// ── UPDATE Handler ─────────────────────────────────────────────────

/**
 * Apply an UPDATE change with field-level merge.
 *
 * If the incoming change has `changed_fields`, we only compare those
 * fields against local state. Fields that weren't touched locally
 * are accepted without conflict.
 *
 * Returns the number of field-level conflicts detected.
 */
async function applyUpdate(
  db: any,
  change: IncomingChange,
  localDeviceId: string,
): Promise<number> {
  // Get the fields being updated
  const changedFields = parseJsonField(change.changed_fields);
  const recordData = parseJsonField(change.record_data);

  // If we have full record data but no changed_fields, fall back to
  // treating the whole record as changed (same as INSERT merge)
  if (!changedFields && recordData) {
    const hadConflict = await applyInsert(db, { ...change, operation: 'INSERT' }, localDeviceId);
    return hadConflict ? 1 : 0;
  }

  if (!changedFields) return 0; // Nothing to update

  // Get local record
  const existing = await getLocalRecord(db, change.table_name, change.record_id);
  if (!existing) {
    // Record doesn't exist locally — if we have full data, insert it
    if (recordData) {
      const keys = Object.keys(recordData);
      const placeholders = keys.map(() => '?').join(', ');
      const values = keys.map((k) => recordData[k]);
      await db.run(
        `INSERT OR IGNORE INTO [${change.table_name}] (${keys.join(', ')}) VALUES (${placeholders})`,
        values,
      );
    }
    return 0;
  }

  const localTimestamp = existing.updated_at ?? existing.created_at ?? '1970-01-01';
  const remoteTimestamp = change.timestamp;

  // Get which fields were locally modified (unsynced)
  const localChangedFields = await getLocalChangedFields(
    db, change.table_name, change.record_id,
  );

  const fieldsToUpdate: Record<string, any> = {};
  const conflicts: ConflictEntry[] = [];

  for (const [field, remoteValue] of Object.entries(changedFields)) {
    if (field === 'id') continue;

    const localValue = existing[field];
    const locallyModified = localChangedFields.has(field);

    if (!locallyModified) {
      // Not locally modified — accept remote
      fieldsToUpdate[field] = remoteValue;
    } else if (remoteTimestamp > localTimestamp) {
      // Both modified, remote newer — remote wins
      fieldsToUpdate[field] = remoteValue;
      conflicts.push({
        table_name: change.table_name,
        record_id: change.record_id,
        field_name: field,
        local_value: stringifyValue(localValue),
        remote_value: stringifyValue(remoteValue),
        winner: 'remote',
        local_device: localDeviceId,
        remote_device: change.device_id,
        local_ts: localTimestamp,
        remote_ts: remoteTimestamp,
      });
    } else {
      // Both modified, local newer — keep local
      conflicts.push({
        table_name: change.table_name,
        record_id: change.record_id,
        field_name: field,
        local_value: stringifyValue(localValue),
        remote_value: stringifyValue(remoteValue),
        winner: 'local',
        local_device: localDeviceId,
        remote_device: change.device_id,
        local_ts: localTimestamp,
        remote_ts: remoteTimestamp,
      });
    }
  }

  // Apply the merged fields
  if (Object.keys(fieldsToUpdate).length > 0) {
    const setClause = Object.keys(fieldsToUpdate).map((k) => `${k} = ?`).join(', ');
    const values = Object.values(fieldsToUpdate);
    await db.run(
      `UPDATE [${change.table_name}] SET ${setClause} WHERE id = ?`,
      [...values, change.record_id],
    );
  }

  // Log conflicts
  if (conflicts.length > 0) {
    await logConflicts(db, conflicts);
  }

  return conflicts.length;
}

// ── Helpers ──────────────────────────────────────────────────────────

/**
 * Get a record from the local database.
 */
async function getLocalRecord(
  db: any,
  tableName: string,
  recordId: string,
): Promise<Record<string, any> | null> {
  try {
    const result = await db.query(
      `SELECT * FROM [${tableName}] WHERE id = ?`,
      [recordId],
    );
    if (result.values && result.values.length > 0) {
      return result.values[0];
    }
  } catch {
    // Table might not exist or other query error
  }
  return null;
}

/**
 * Get the set of field names that were locally changed for a record
 * and haven't been synced yet (unsynced changes).
 *
 * This tells us which fields the local device has modified since
 * the last sync — if a field isn't in this set, the remote version
 * can be accepted without conflict.
 */
async function getLocalChangedFields(
  db: any,
  tableName: string,
  recordId: string,
): Promise<Set<string>> {
  const fields = new Set<string>();

  try {
    const result = await db.query(
      `SELECT changed_fields FROM _change_log
       WHERE table_name = ? AND record_id = ? AND synced = 0
       ORDER BY timestamp DESC`,
      [tableName, recordId],
    );

    for (const row of result.values as any[]) {
      if (row.changed_fields) {
        try {
          const parsed = typeof row.changed_fields === 'string'
            ? JSON.parse(row.changed_fields)
            : row.changed_fields;
          for (const key of Object.keys(parsed)) {
            fields.add(key);
          }
        } catch {
          // Malformed JSON — skip
        }
      }
    }
  } catch {
    // If query fails, assume no local changes (remote wins by default)
  }

  return fields;
}

/**
 * Log conflict entries to the _conflict_log table.
 */
async function logConflicts(db: any, conflicts: ConflictEntry[]): Promise<void> {
  for (const c of conflicts) {
    try {
      await db.run(
        `INSERT INTO _conflict_log
           (table_name, record_id, field_name, local_value, remote_value,
            winner, local_device, remote_device, local_ts, remote_ts)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          c.table_name, c.record_id, c.field_name,
          c.local_value, c.remote_value,
          c.winner, c.local_device, c.remote_device,
          c.local_ts, c.remote_ts,
        ],
      );
    } catch (err) {
      console.error('[conflict-resolver] Failed to log conflict:', err);
    }
  }
}

/**
 * Parse a JSON field that might be a string, object, or null.
 */
function parseJsonField(
  field: string | Record<string, any> | null | undefined,
): Record<string, any> | null {
  if (!field) return null;
  if (typeof field === 'object') return field;
  try {
    return JSON.parse(field);
  } catch {
    return null;
  }
}

/**
 * Stringify a value for conflict log storage.
 */
function stringifyValue(value: any): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value === 'string') return value;
  return JSON.stringify(value);
}

// ── Conflict Review API (for admin UI) ───────────────────────────────

/**
 * Get unreviewed conflicts for admin review.
 */
export async function getUnreviewedConflicts(
  limit = 50,
): Promise<any[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT * FROM _conflict_log WHERE reviewed = 0 ORDER BY resolved_at DESC LIMIT ?`,
    [limit],
  );
  return result.values ?? [];
}

/**
 * Mark a conflict as reviewed.
 */
export async function markConflictReviewed(conflictId: number): Promise<void> {
  const db = await getDb();
  await db.run(
    'UPDATE _conflict_log SET reviewed = 1 WHERE id = ?',
    [conflictId],
  );
}

/**
 * Get conflict statistics (for sync status UI).
 */
export async function getConflictStats(): Promise<{
  total: number;
  unreviewed: number;
  last24h: number;
}> {
  const db = await getDb();
  const result = await db.query(`
    SELECT
      COUNT(*) as total,
      SUM(CASE WHEN reviewed = 0 THEN 1 ELSE 0 END) as unreviewed,
      SUM(CASE WHEN resolved_at > datetime('now', '-1 day') THEN 1 ELSE 0 END) as last24h
    FROM _conflict_log
  `);
  const row = result.values?.[0] ?? {};
  return {
    total: row.total ?? 0,
    unreviewed: row.unreviewed ?? 0,
    last24h: row.last24h ?? 0,
  };
}
