/**
 * Device-side Sync Engine — pushes local changes to shop, pulls shop changes.
 *
 * Runs in native (Tauri) mode only. Triggered by:
 * - App launch / resume
 * - Manual "Sync Now" button
 * - Periodic timer (every 5 minutes when online, backoff when failing)
 * - Network change detection (online/offline events)
 * - App state change (visibilitychange)
 *
 * Protocol:
 * 1. Check if shop is reachable
 * 2. Push local _change_log entries to shop (POST /api/sync/push)
 * 3. Shop returns its changes + conflict resolutions
 * 4. Apply shop changes to local DB
 * 5. Acknowledge (POST /api/sync/ack)
 * 6. Mark local changes as synced
 *
 * Retry strategy: exponential backoff starting at 30s, max 5 minutes.
 * Resets to normal interval on successful sync or manual trigger.
 */

import { getDb } from './db';
import { getPendingChanges, markSynced, getPendingChangeCount } from './change-tracker';
import { getShopUrl, isShopReachable } from '../lib/shop-config';

// ── Sync State ────────────────────────────────────────────────────

export type SyncStatus = 'idle' | 'syncing' | 'synced' | 'error' | 'offline';

export interface SyncState {
  status: SyncStatus;
  lastSyncAt: string | null;
  pendingCount: number;
  error: string | null;
  consecutiveFailures: number;
  lastAttemptAt: string | null;
}

let syncState: SyncState = {
  status: 'idle',
  lastSyncAt: null,
  pendingCount: 0,
  error: null,
  consecutiveFailures: 0,
  lastAttemptAt: null,
};

const listeners: Set<(state: SyncState) => void> = new Set();

export function getSyncState(): SyncState {
  return { ...syncState };
}

export function onSyncStateChange(fn: (state: SyncState) => void): () => void {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

function updateState(partial: Partial<SyncState>) {
  syncState = { ...syncState, ...partial };
  for (const fn of listeners) {
    try { fn(syncState); } catch { /* ignore listener errors */ }
  }
}

// ── Retry Configuration ──────────────────────────────────────────

const SYNC_INTERVAL_MS = 5 * 60 * 1000;     // 5 minutes normal interval
const MIN_BACKOFF_MS = 30 * 1000;            // 30 seconds initial backoff
const MAX_BACKOFF_MS = 5 * 60 * 1000;        // 5 minutes max backoff
const MAX_CONSECUTIVE_FAILURES = 10;         // Stop auto-retry after this many

function getBackoffMs(): number {
  if (syncState.consecutiveFailures === 0) return SYNC_INTERVAL_MS;
  const backoff = MIN_BACKOFF_MS * Math.pow(2, syncState.consecutiveFailures - 1);
  return Math.min(backoff, MAX_BACKOFF_MS);
}

// ── Core Sync Flow ────────────────────────────────────────────────

let syncLock = false;

/**
 * Run a full sync cycle: push local changes, pull shop changes, apply.
 * Returns true if sync completed successfully, false otherwise.
 */
export async function runSync(deviceId: string): Promise<boolean> {
  if (syncLock) return false;
  syncLock = true;

  try {
    updateState({ status: 'syncing', error: null, lastAttemptAt: new Date().toISOString() });

    // Check connectivity
    const reachable = await isShopReachable();
    if (!reachable) {
      const count = await getPendingChangeCount();
      updateState({
        status: 'offline',
        pendingCount: count,
        consecutiveFailures: syncState.consecutiveFailures + 1,
      });
      scheduleRetry(deviceId);
      return false;
    }

    const shopUrl = await getShopUrl();
    if (!shopUrl) {
      updateState({ status: 'error', error: 'Shop URL not configured' });
      return false;
    }

    const token = localStorage.getItem('wiredpart_token');
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };
    if (token) headers['Authorization'] = `Bearer ${token}`;

    // 1. Get pending local changes
    const pendingChanges = await getPendingChanges();
    updateState({ pendingCount: pendingChanges.length });

    // 2. Push to shop
    const pushResponse = await fetch(`${shopUrl}/api/sync/push`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        device_id: deviceId,
        last_sync_at: syncState.lastSyncAt || '1970-01-01',
        changes: pendingChanges,
      }),
      signal: AbortSignal.timeout(30000),
    });

    if (!pushResponse.ok) {
      await pushResponse.text();
      updateState({
        status: 'error',
        error: `Push failed: ${pushResponse.status}`,
        consecutiveFailures: syncState.consecutiveFailures + 1,
      });
      scheduleRetry(deviceId);
      return false;
    }

    const pushData = await pushResponse.json();
    const result = pushData.data;

    // 3. Apply shop changes to local DB
    if (result.shop_changes?.length) {
      await applyShopChanges(result.shop_changes);
    }

    // 4. Mark local changes as synced
    if (pendingChanges.length > 0 && result.sync_batch_id) {
      const syncedIds = pendingChanges.map((c: any) => c.id);
      await markSynced(syncedIds, result.sync_batch_id);
    }

    // 5. Acknowledge
    try {
      await fetch(`${shopUrl}/api/sync/ack`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          device_id: deviceId,
          sync_batch_id: result.sync_batch_id,
        }),
        signal: AbortSignal.timeout(10000),
      });
    } catch {
      // Ack failure is non-critical — the sync data was already applied
    }

    const now = new Date().toISOString();
    updateState({
      status: 'synced',
      lastSyncAt: now,
      pendingCount: 0,
      error: null,
      consecutiveFailures: 0,
    });

    // Store last sync time persistently
    localStorage.setItem('last_sync_at', now);

    return true;
  } catch (err) {
    updateState({
      status: 'error',
      error: err instanceof Error ? err.message : 'Sync failed',
      consecutiveFailures: syncState.consecutiveFailures + 1,
    });
    scheduleRetry(deviceId);
    return false;
  } finally {
    syncLock = false;
  }
}

// ── Apply Shop Changes to Local DB ────────────────────────────────

async function applyShopChanges(changes: any[]): Promise<void> {
  const db = await getDb();

  for (const change of changes) {
    const { table_name, record_id, operation, record_data } = change;

    try {
      if (operation === 'DELETE') {
        await db.run(`DELETE FROM [${table_name}] WHERE id = ?`, [record_id]);
      } else if (record_data) {
        // Use INSERT OR REPLACE for both INSERT and UPDATE
        const keys = Object.keys(record_data);
        const placeholders = keys.map(() => '?').join(', ');
        const values = keys.map((k) => record_data[k]);

        await db.run(
          `INSERT OR REPLACE INTO [${table_name}] (${keys.join(', ')}) VALUES (${placeholders})`,
          values,
        );
      }
    } catch (err) {
      console.error(`Failed to apply sync change: ${table_name}.${record_id}`, err);
      // Continue with other changes — don't let one failure block the batch
    }
  }
}

// ── Initial Sync ──────────────────────────────────────────────────

/**
 * Perform initial sync — pull all data from shop to populate local DB.
 * Called on first launch or when the device has no data.
 */
export async function runInitialSync(deviceId: string): Promise<boolean> {
  try {
    updateState({ status: 'syncing', error: null });

    const shopUrl = await getShopUrl();
    if (!shopUrl) {
      updateState({ status: 'error', error: 'Shop URL not configured' });
      return false;
    }

    const token = localStorage.getItem('wiredpart_token');
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };
    if (token) headers['Authorization'] = `Bearer ${token}`;

    const response = await fetch(`${shopUrl}/api/sync/initial`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ device_id: deviceId }),
      signal: AbortSignal.timeout(120000), // 2 min for large datasets
    });

    if (!response.ok) {
      updateState({ status: 'error', error: 'Initial sync failed' });
      return false;
    }

    const data = await response.json();
    const tables = data.data?.tables || {};

    const db = await getDb();

    // Populate each table
    for (const [tableName, rows] of Object.entries(tables)) {
      if (!Array.isArray(rows) || rows.length === 0) continue;

      for (const row of rows as Record<string, any>[]) {
        const keys = Object.keys(row);
        const placeholders = keys.map(() => '?').join(', ');
        const values = keys.map((k) => row[k]);

        try {
          await db.run(
            `INSERT OR REPLACE INTO [${tableName}] (${keys.join(', ')}) VALUES (${placeholders})`,
            values,
          );
        } catch {
          // Skip individual row errors
        }
      }
    }

    const now = new Date().toISOString();
    updateState({
      status: 'synced',
      lastSyncAt: now,
      pendingCount: 0,
      consecutiveFailures: 0,
    });

    // Store last sync time
    localStorage.setItem('last_sync_at', now);

    return true;
  } catch (err) {
    updateState({
      status: 'error',
      error: err instanceof Error ? err.message : 'Initial sync failed',
    });
    return false;
  }
}

// ── Retry with Exponential Backoff ───────────────────────────────

let retryTimeout: ReturnType<typeof setTimeout> | null = null;

function scheduleRetry(deviceId: string): void {
  if (retryTimeout) clearTimeout(retryTimeout);
  if (syncState.consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
    // Stop auto-retry — user must manually trigger
    updateState({ error: 'Too many failures. Tap to retry.' });
    return;
  }
  const delay = getBackoffMs();
  retryTimeout = setTimeout(() => {
    retryTimeout = null;
    runSync(deviceId).catch(console.error);
  }, delay);
}

function cancelRetry(): void {
  if (retryTimeout) {
    clearTimeout(retryTimeout);
    retryTimeout = null;
  }
}

// ── Periodic Sync Timer ──────────────────────────────────────────

let syncInterval: ReturnType<typeof setInterval> | null = null;
export let _deviceId: string | null = null;

/** Start periodic sync (every 5 minutes) */
export function startPeriodicSync(deviceId: string): void {
  _deviceId = deviceId;
  if (syncInterval) return;
  syncInterval = setInterval(() => {
    // Only sync on interval if we're not already retrying
    if (!retryTimeout && syncState.consecutiveFailures === 0) {
      runSync(deviceId).catch(console.error);
    }
  }, SYNC_INTERVAL_MS);
}

/** Stop periodic sync and cancel pending retries */
export function stopPeriodicSync(): void {
  if (syncInterval) {
    clearInterval(syncInterval);
    syncInterval = null;
  }
  cancelRetry();
}

// ── Manual Sync (resets backoff) ─────────────────────────────────

/** Trigger a manual sync — resets consecutive failure count */
export async function manualSync(deviceId: string): Promise<boolean> {
  cancelRetry();
  updateState({ consecutiveFailures: 0 });
  return runSync(deviceId);
}

// ── Network Change Handler ───────────────────────────────────────

let networkListenerSetup = false;

/**
 * Listen for network changes and auto-sync when shop becomes reachable.
 * Call once during app init.
 */
export async function setupNetworkListener(deviceId: string): Promise<void> {
  if (networkListenerSetup) return;
  networkListenerSetup = true;

  window.addEventListener('online', () => {
    // Network came back — try syncing after a short delay
    setTimeout(() => {
      cancelRetry();
      updateState({ consecutiveFailures: 0 });
      runSync(deviceId).catch(console.error);
    }, 2000);
  });

  window.addEventListener('offline', () => {
    updateState({ status: 'offline' });
  });
}

/**
 * Listen for app state changes and sync when returning to foreground.
 * Call once during app init.
 */
export async function setupAppStateListener(deviceId: string): Promise<void> {
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      // App came to foreground — sync if it's been a while
      const lastAttempt = syncState.lastAttemptAt;
      const now = Date.now();
      const timeSinceLastAttempt = lastAttempt
        ? now - new Date(lastAttempt).getTime()
        : Infinity;

      // Only auto-sync if at least 30 seconds since last attempt
      if (timeSinceLastAttempt > 30000) {
        runSync(deviceId).catch(console.error);
      }
    }
  });
}

// ── Restore last sync timestamp ──────────────────────────────────

export async function restoreLastSyncTime(): Promise<void> {
  const saved = localStorage.getItem('last_sync_at');
  if (saved) {
    syncState.lastSyncAt = saved;
  }

  // Also update pending count
  try {
    const count = await getPendingChangeCount();
    syncState.pendingCount = count;
  } catch { /* non-critical */ }
}

// ── Full Init (convenience) ──────────────────────────────────────

/**
 * Initialize the entire sync system. Call once at app startup.
 *
 * Sets up:
 * 1. Restored last sync time
 * 2. Network change listener
 * 3. App state listener
 * 4. Periodic sync timer
 * 5. Immediate sync attempt
 * 6. P2P peer sync (Tauri only — axum server + mDNS discovery)
 */
export async function initSync(deviceId: string): Promise<void> {
  _deviceId = deviceId;

  await restoreLastSyncTime();
  await setupNetworkListener(deviceId);
  await setupAppStateListener(deviceId);
  startPeriodicSync(deviceId);

  // Try an immediate sync (shop server)
  runSync(deviceId).catch(console.error);

  // Start P2P peer sync if running in Tauri
  const { isTauri } = await import('../lib/environment');
  if (isTauri()) {
    try {
      const { startPeerSync, refreshOutbox } = await import('./peer-manager');
      const deviceName = localStorage.getItem('device_name') || 'WiredPart Device';
      const companyId = localStorage.getItem('company_id') || 'default';
      await startPeerSync(deviceId, deviceName, companyId);

      // Refresh the outbox periodically (every 30s) so peers can pull latest changes
      setInterval(() => { refreshOutbox().catch(console.error); }, 30_000);
      // Initial outbox refresh
      refreshOutbox().catch(console.error);
    } catch (err) {
      console.error('[sync] P2P peer sync failed to start:', err);
      // Non-critical — shop sync still works
    }
  }
}
