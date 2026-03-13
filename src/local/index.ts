/**
 * Local Data Layer — Entry Point
 *
 * This module provides offline-capable data access for Tauri native apps.
 * It mirrors a subset of the Python backend services using TypeScript + SQLite.
 *
 * Structure:
 *   local/
 *   ├── index.ts          ← you are here (re-exports)
 *   ├── db.ts             ← SQLite connection manager
 *   ├── change-tracker.ts ← Write logging for sync
 *   ├── local-client.ts   ← Unified API surface (matches HTTP client)
 *   ├── migrations/       ← SQL schema (ported from Python) (Task 11)
 *   ├── services/         ← Business logic (11 services)
 *   │   ├── auth-service.ts       P0: PIN auth, user lookup
 *   │   ├── job-service.ts        P0: Job CRUD, status
 *   │   ├── labor-service.ts      P0: Clock in/out, hours calc
 *   │   ├── movement-service.ts   P0: Stock movements (validate/preview/execute)
 *   │   ├── order-service.ts      P1: JPO create/list
 *   │   ├── notebook-service.ts   P1: Entries + tasks
 *   │   ├── warehouse-service.ts  P1: Inventory read
 *   │   ├── tool-service.ts       P1: Checkout/return
 *   │   ├── parts-service.ts      P2: Catalog lookup (read-only)
 *   │   ├── fleet-service.ts      P2: Vehicle info (read-only)
 *   │   └── scheduling-service.ts P2: My schedule (read-only)
 *   └── repos/
 *       └── base-repo.ts  ← Generic CRUD with change tracking
 *
 * NOT implemented locally (shop-only):
 *   cost-tracking, approvals, reports, PDF generation,
 *   companions, scheduler, notifications
 */

export { initLocalDb, getDb } from './db';
export {
  trackChange, getPendingChanges, getPendingChangeCount, markSynced, pruneOldChanges,
  getVectorClock, updateVectorClock, getChangesSince, getMaxSequence,
  registerPeerDevice, updatePeerSyncTime,
  type ChangeLogEntry, type VectorClock,
} from './change-tracker';
export {
  runSync, runInitialSync, manualSync, initSync,
  getSyncState, onSyncStateChange,
  startPeriodicSync, stopPeriodicSync,
  setupNetworkListener, setupAppStateListener,
  restoreLastSyncTime,
  type SyncStatus, type SyncState,
} from './sync-engine';
export {
  startPeerSync, stopPeerSync, syncWithPeer, syncWithAllPeers,
  getPeerManagerState, onPeerManagerStateChange, refreshOutbox,
  type DiscoveredPeer, type PeerSyncResult, type PeerManagerState,
} from './peer-manager';

// Re-export the local client as the main API surface
export * as localClient from './local-client';

export const LOCAL_DATA_LAYER_VERSION = '1.0.0';
export const LOCAL_DATA_LAYER_STATUS = 'ready';
