# Device Sync Management (V1.0.0 Detailed Plan + Implementation)

> **Date:** 2026-03-07  
> **Status:** Planned + Partially Implemented (backend core)  
> **Version target:** V1.0.0  
> **Primary roadmap reference:** `docs/plans/phase-13-sync-bluetooth.md` (Phase 11 forward roadmap)  
> **Scope here:** Deliver V1.0-compatible sync management foundation that honors mesh principles and device ownership rules.

---

## 1) Why this plan exists

Your sync architecture requires these non-negotiable behaviors:

1. Devices relay undelivered data through peer encounters.
2. Shop acts as truth anchor (single node now, cluster model later).
3. Active job core data is mandatory on all devices.
4. Media permanent storage is preference-driven, but undelivered media carry is mandatory.
5. Device behavior is governed by primary-user-owned profile; borrowed users cannot override.

This document turns those principles into implementation details and rollout order.

---

## 2) V1.0.0 deliverables (this implementation pass)

### 2.1 Backend schema (implemented)

Migration added:
- `backend/app/migrations/041_device_sync_management.sql`

Tables added:
- `_device_sync_profiles`
  - primary user ownership + sync/storage policy
- `_mesh_relay_events`
  - relay telemetry and undelivered-carry audit events

### 2.2 Backend service changes (implemented)

Updated:
- `backend/app/services/sync_service.py`

Added capabilities:
- sync profile read/update
- mesh relay event log/list
- initial sync option `only_active_jobs`
- default profile creation on device registration
- default log cleanup retention adjusted to 365 days

### 2.3 Backend API changes (implemented)

Updated:
- `backend/app/routers/sync.py`

New endpoints:
- `GET /api/sync/profile/{device_id}`
- `PUT /api/sync/profile/{device_id}`
- `POST /api/sync/mesh/relay-events`
- `GET /api/sync/mesh/relay-events`

Extended endpoint:
- `POST /api/sync/initial` now accepts `only_active_jobs`

### 2.4 Test coverage (implemented)

Added tests:
- `backend/tests/test_sync_device_management.py`

Covers:
- profile update/read flow
- mesh relay logging/listing
- active-jobs-only initial sync filter contract

---

## 3) Device behavior matrix (requested)

| Scenario | Primary User | Borrowed User | Active Job Core Data | Completed/On-Hold Core Data | Undelivered Media | Permanent Media |
|---|---|---|---|---|---|---|
| Normal operation | Controls profile | N/A | Must keep | Optional/purgeable | Must carry | Per profile |
| Borrowed login | Unchanged | Cannot alter profile | Must keep | Optional/purgeable | Must carry | Per primary profile |
| Low storage | Can adjust policy | Cannot adjust | Must keep | Purge first | Must carry until delivered | Reduce per policy |
| Device offline 2 months | Profile persists | Cannot alter | Must keep | Optional/purgeable | Must carry and relay | Per profile |
| Hard sync recovery | Rehydrated from shop | Cannot alter | Re-downloaded (active only if enabled) | Optional | Reconcile/replay required | Per profile |

---

## 4) Shop cluster sync algorithm (requested)

> V1.0.0 implements single shop-node behavior with cluster-compatible logs. Full cluster gossip/leader election remains Phase 11 scope.

### Algorithm (cluster-ready outline)

1. **Receive** device changes on any shop node.
2. **Apply** via conflict resolution (LWW with shop tie-break).
3. **Log** in shop change log + sync batches.
4. **Replicate** to peer shop nodes over LAN channel (Phase 11 transport).
5. **Ack** device with batch ID and server timestamp.
6. **Reconcile** lagging shop peers on reconnect using 1-year logs.

### Current V1.0.0 status
- Steps 1,2,3,5 implemented.
- Steps 4,6 planned for Phase 11 sync/bluetooth track.

---

## 5) Field device state machine (requested)

```text
UNPAIRED
  ↓ (register + profile init)
REGISTERED
  ↓ (initial sync)
BASELINED
  ↓ (normal operation)
SYNCING ←→ OFFLINE
  ↓ (conflict detected)
CONFLICT_REVIEW
  ↓
SYNCING
  ↓ (stale/corrupt/manual trigger)
HARD_SYNC_REQUESTED
  ↓
HARD_SYNC_APPLYING
  ↓
BASELINED
```

### State responsibilities
- `REGISTERED`: device identity + profile established.
- `BASELINED`: local DB aligned with shop baseline.
- `SYNCING`: push/pull in normal loop.
- `OFFLINE`: queues retained, relay via mesh when available.
- `HARD_SYNC_*`: deterministic recovery flow.

---

## 6) Media routing algorithm (requested)

### Rules
1. If media is undelivered to shop, carry is mandatory.
2. Relay to any reachable peer permitted.
3. Purge only after shop delivery confirmation and policy check.

### Pseudocode

```text
for each media_blob:
  if delivered_to_shop == false:
    mark carrier_required = true
    advertise in relay manifest
    transfer to peer if peer missing
  else:
    carrier_required = false
    if profile allows purge:
      purge local copy
```

### V1.0.0 status
- Policy and telemetry primitives implemented.
- Full media relay transport and delivery receipts are Phase 11 work.

---

## 7) Conflict resolution matrix (requested)

| Conflict Type | Example | Resolution Rule | V1.0 Status |
|---|---|---|---|
| Record update collision | Same record edited on two devices | Last-writer-wins; shop as tie-break | Implemented |
| Delete vs update | One deletes, one updates | Later timestamp wins; logged | Implemented via existing sync conflict log |
| Device stale baseline | Very old device replay | Hard-sync package then replay pending | Implemented (hard-sync endpoints) |
| Media duplicate upload | Same blob relayed by multiple peers | Deduplicate by checksum/hash | Planned (Phase 11 media channel) |
| Shop peer divergence | Two shop PCs had divergent windows | Replay from retained shop logs | Planned (Phase 11 cluster replication) |

---

## 8) Active-job-only storage policy

### Rule
- Active jobs: always included for device core sync.
- Completed/on-hold: optional on device.

### V1.0 implementation
- `POST /api/sync/initial` supports `only_active_jobs=true`.
- `jobs` table is filtered to `status='active'` when this flag is enabled.
- Tables with direct `job_id` are filtered to active jobs where possible.

---

## 9) API contract additions (V1)

### Profile
- `GET /api/sync/profile/{device_id}`
- `PUT /api/sync/profile/{device_id}`

### Mesh telemetry
- `POST /api/sync/mesh/relay-events`
- `GET /api/sync/mesh/relay-events`

### Initial sync behavior extension
- `POST /api/sync/initial` with `only_active_jobs: boolean`

---

## 10) Security and ownership constraints

- Primary-user ownership stored in `_device_sync_profiles.primary_user_id`.
- Borrowed users cannot modify profile (admin-only profile update endpoint).
- Device relays are logged for auditability (`_mesh_relay_events`).
- Hard sync and profile controls remain shop-authorized workflows.

---

## 11) Rollout plan

### Step A (done)
- Add schema + service + API + tests.

### Step B (next)
- Settings UI for device sync profile management.
- Device admin dashboard card for mesh relay health.

### Step C (phase 11)
- Real device-to-device transport over Bluetooth.
- Shop-cluster replication protocol and conflict replay.
- Media relay receipts and purge confirmations.

---

## 12) Definition of done for this V1 pass

- [x] Sync profile persisted and retrievable per device.
- [x] Mesh relay events auditable via API.
- [x] Initial sync supports active-jobs-only scope.
- [x] Tests added for new behavior.
- [ ] UI for profile management.
- [ ] Real peer-to-peer relay transport and receipts.

---

## 13) File reference index

### Implemented code
- `backend/app/migrations/041_device_sync_management.sql`
- `backend/app/services/sync_service.py`
- `backend/app/routers/sync.py`
- `backend/tests/test_sync_device_management.py`

### Related docs
- `docs/plans/phase-13-sync-bluetooth.md`
- `docs/plans/Device security protocols.md`
- `docs/plans/Update protocol.md`
- `docs/plans/Hard sync backup.md`
