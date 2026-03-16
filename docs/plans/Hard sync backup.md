# Hard Sync Backup & Recovery Protocol (V1.0.0)

> **Date:** 2026-03-07
> **Status:** ✅ Complete (V1.0.0)
> **Version target:** V1.0.0
> **Scope:** Safe, deterministic device reset-and-resync flow for recovery cases.

---

## 1) Objective

Provide a controlled **break-glass recovery flow** when a device is stale/corrupt/partial, while preserving security boundaries and unsent outbound changes.

Hard sync in this system means:

> Replace local replicated data with shop-authoritative snapshot, preserve device identity + pending outbound intent, then rejoin normal sync.

---

## 2) Recovery triggers

Use hard sync when:
- device missing expected jobs/orders/inventory,
- device has inconsistent local cache,
- device was offline for extended period,
- local DB state is partial/corrupted,
- repeated sync conflicts cannot be reconciled safely.

---

## 3) V1.0.0 implementation delivered

### 3.1 Database

Migration added:
- `backend/app/migrations/038_hard_sync_backup.sql`

New table:
- `_hard_sync_events`
  - event audit lifecycle (`requested`, `package_ready`, `in_progress`, `completed`, `failed`)
  - request metadata (reason code, included tables, pending outbound hashes)
  - package summary + batch linkage

### 3.2 Backend service

Implemented in:
- `backend/app/services/sync_service.py`

New methods:
- `request_hard_sync(...)`
- `complete_hard_sync(...)`
- `get_hard_sync_history(...)`

Behavior:
- Generates hard-sync package via existing initial-sync table ordering.
- Creates/links a sync batch for auditability.
- Stores package summary and request metadata.
- Marks completion and updates device sync status on ACK.

### 3.3 API endpoints

Implemented in:
- `backend/app/routers/sync.py`

New endpoints:
- `POST /api/sync/hard-sync/request`
- `POST /api/sync/hard-sync/complete`
- `GET /api/sync/hard-sync/history`

### 3.4 Frontend API client

Implemented in:
- `frontend/src/api/sync.ts`

New client functions:
- `requestHardSync(...)`
- `completeHardSync(...)`
- `getHardSyncHistory(...)`

---

## 4) Protocol sequence (authoritative)

1. Admin (shop side) requests hard sync for a device.
2. Shop generates deterministic package (ordered tables).
3. Device purges local replicated state (keeps identity + pending outbound intent).
4. Device applies package.
5. Device confirms completion (`/hard-sync/complete`).
6. Device resumes normal push/pull loop.

---

## 5) Safety rules

- Shop remains source of truth.
- Hard sync does not bypass auth/permissions.
- Device identity remains intact.
- Pending outbound data should be preserved and replayed after package apply.
- Package generation respects existing sync table allowlist.

---

## 6) Testing requirements

### Backend tests implemented

Test file:
- `backend/tests/test_sync_hard_sync.py`

Covered:
- hard-sync package request success,
- hard-sync complete ACK flow,
- hard-sync history retrieval.

### Additional validation

- Run full backend suite after sync changes.
- Verify no regression to `/sync/push`, `/sync/pull`, `/sync/initial`.

---

## 7) UI work (completed)

Added in Settings → Sync (`SyncPage.tsx`):
- [x] Hard Sync Recovery action panel (admin-only, amber-bordered break-glass card)
- [x] Device picker dropdown + reason code selector + notes textarea + preserve-pending checkbox
- [x] Two-step confirmation dialog with Confirm/Cancel
- [x] Recovery result summary display + error handling
- [x] Hard Sync History table wired to `getHardSyncHistory` (status badges, timestamps)
- [x] Refactored existing cards (devices, history, conflicts) to typed API functions

---

## 8) Definition of done (V1.0.0)

- [x] Backend hard-sync event schema exists.
- [x] Hard-sync request/complete/history endpoints exist.
- [x] Sync service handles package generation and completion bookkeeping.
- [x] Frontend API helpers exist for UI wiring.
- [x] Sync settings UI exposes hard-sync operations.
- [ ] Device-side flow confirms pending outbound replay behavior in field test. *(requires physical device testing)*

---

## 9) Notes

This feature intentionally reuses existing `initial sync` table-order guarantees rather than inventing a second package format, which reduces risk and keeps behavior deterministic.
