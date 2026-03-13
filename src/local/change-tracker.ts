/**
 * Change Tracker — logs all local writes for sync.
 *
 * Every INSERT, UPDATE, DELETE on the local SQLite database is
 * logged to the `_change_log` table. The sync engine reads this
 * log to know what changes to push to the shop server or peers.
 *
 * The change log is append-only. Entries are marked as synced
 * (but never deleted) so we have a full audit trail.
 *
 * Vector clocks: Each change gets a monotonically increasing `sequence`
 * number (via SQLite trigger in migration 008). The `_vector_clock` table
 * tracks what each peer has seen, enabling efficient delta sync — only
 * sending changes the other device hasn't received yet.
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
  sequence: number | null;
}

/** What this device knows about each peer's progress */
export interface VectorClock {
  [deviceId: string]: number; // device_id → last seen sequence
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

// ── Vector Clock Operations ─────────────────────────────────────────

/**
 * Get this device's vector clock — what sequence number we last received
 * from each known peer. Used in pull requests so peers only send new changes.
 */
export async function getVectorClock(): Promise<VectorClock> {
  const db = await getDb();
  const deviceId = await getDeviceId();
  const result = await db.query(
    'SELECT peer_id, last_sequence FROM _vector_clock WHERE device_id = ?',
    [deviceId],
  );
  const vc: VectorClock = {};
  for (const row of result.values as any[]) {
    vc[row.peer_id] = row.last_sequence;
  }
  return vc;
}

/**
 * Update the vector clock after receiving changes from a peer.
 * Records the highest sequence number we've seen from that peer.
 */
export async function updateVectorClock(
  peerId: string,
  lastSequence: number,
): Promise<void> {
  const db = await getDb();
  const deviceId = await getDeviceId();
  await db.run(
    `INSERT INTO _vector_clock (device_id, peer_id, last_sequence, updated_at)
     VALUES (?, ?, ?, datetime('now'))
     ON CONFLICT(device_id, peer_id)
     DO UPDATE SET last_sequence = MAX(last_sequence, ?), updated_at = datetime('now')`,
    [deviceId, peerId, lastSequence, lastSequence],
  );
}

/**
 * Get changes since a specific sequence number.
 * Used when a peer requests our changes — we only send what they haven't seen.
 */
export async function getChangesSince(sinceSequence: number): Promise<ChangeLogEntry[]> {
  const db = await getDb();
  const result = await db.query(
    'SELECT * FROM _change_log WHERE sequence > ? ORDER BY sequence ASC',
    [sinceSequence],
  );
  return result.values as ChangeLogEntry[];
}

/**
 * Get the current maximum sequence number in our change log.
 * Peers store this to know where to resume next sync.
 */
export async function getMaxSequence(): Promise<number> {
  const db = await getDb();
  const result = await db.query(
    'SELECT COALESCE(MAX(sequence), 0) as max_seq FROM _change_log',
  );
  return result.values[0]?.max_seq ?? 0;
}

// ── Device Registry ─────────────────────────────────────────────────

/**
 * Register or update a peer device we've synced with.
 * Builds a local registry of known devices in the company.
 */
export async function registerPeerDevice(
  peerId: string,
  peerName: string,
  platform?: string,
): Promise<void> {
  const db = await getDb();
  await db.run(
    `INSERT INTO _device_registry (device_id, device_name, platform, last_seen_at, is_trusted)
     VALUES (?, ?, ?, datetime('now'), 1)
     ON CONFLICT(device_id)
     DO UPDATE SET device_name = ?, last_seen_at = datetime('now')`,
    [peerId, peerName, platform ?? null, peerName],
  );
}

/**
 * Update the last sync time for a peer in the device registry.
 */
export async function updatePeerSyncTime(peerId: string): Promise<void> {
  const db = await getDb();
  await db.run(
    `UPDATE _device_registry SET last_sync_at = datetime('now'), last_seen_at = datetime('now')
     WHERE device_id = ?`,
    [peerId],
  );
}
