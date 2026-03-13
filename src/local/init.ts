/**
 * Local System Initializer — called once at app startup in native mode
 * (Tauri).
 *
 * Responsibilities:
 * 1. Initialize the local SQLite database (create tables via migrations)
 * 2. Restore last sync timestamp from storage
 * 3. Start the background scheduler (backups, cleanup jobs)
 *
 * The sync engine itself is started AFTER authentication (in auth-store),
 * because sync requires a valid token for the shop server.
 */

import { isNativeApp } from '../lib/environment';
import { initLocalDb } from './db';
import { restoreLastSyncTime } from './sync-engine';
import { startScheduler } from './services/scheduler-service';

let _initialized = false;
let _initPromise: Promise<void> | null = null;

/**
 * Initialize the local data layer. Safe to call multiple times —
 * subsequent calls return the same promise. No-ops on browser.
 */
export function initLocalSystem(): Promise<void> {
  if (_initialized) return Promise.resolve();
  if (_initPromise) return _initPromise;

  if (!isNativeApp()) {
    _initialized = true;
    return Promise.resolve();
  }

  _initPromise = (async () => {
    try {
      console.log('[local] Initializing local database...');
      await initLocalDb();
      console.log('[local] Database initialized, restoring sync state...');
      await restoreLastSyncTime();
      console.log('[local] Starting background scheduler...');
      await startScheduler();
      _initialized = true;
      console.log('[local] Local system ready.');
    } catch (err) {
      console.error('[local] Failed to initialize:', err);
      _initPromise = null;
      throw err;
    }
  })();

  return _initPromise;
}

/** Check if the local system has been initialized */
export function isLocalSystemReady(): boolean {
  return _initialized;
}
