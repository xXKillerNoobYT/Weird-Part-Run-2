# Phase 16B — Multi-Warehouse + Job Trailers Inventory Network

> **Date:** 2026-03-07  
> **Status:** Planned  
> **Version target:** V1.0.0  
> **Scope:** Add support for multiple physical warehouses, trailer-based inventory, and live trailer location tracking while preserving existing movement integrity.
> **Companion phase:** `docs/plans/phase-16-ux-polish-and-admin-hub.md`

---

## 1) Why this phase exists

Current inventory architecture already uses polymorphic locations (`stock.location_type + location_id`) and supports trucks/jobs. That gives us a strong base, but real operations now require:

1. **Multiple Warehouses** (main + satellites)
2. **Job Trailers** (mobile mini-warehouses stocked from warehouse)
3. **Trailer Location Visibility** (where each trailer is right now)
4. **Correct inventory behavior** where trailer preload is **not job-billed/consumed** until parts are explicitly pulled to job usage

This phase delivers that with minimal architectural disruption by extending existing movement patterns.

---

## 2) Business outcomes

By end of phase:

- Warehouse managers can stock and transfer parts between warehouses.
- Foremen can preload trailers with common parts for faster field grabs.
- Trailer stock is tracked separately from truck stock.
- Parts on trailers are **inventory only** (not billed/consumed) until explicit trailer→job consumption move.
- Office/dispatch can see trailer location state (warehouse, job, in transit, unknown) and last check-in.

---

## 3) Design principles

1. **Reuse the movement engine** (`MovementService`) instead of creating parallel inventory logic.
2. **Keep immutable movement audit trail** (`stock_movements`) as source of truth.
3. **Preserve offline-first behavior**; trailer location updates and stock moves must work offline and sync later.
4. **No auto-consume side effects**: preload to trailer is never consumed to job.
5. **Permission-safe**: trailer/warehouse operations gated by existing permissions with new keys added only when needed.

---

## 4) In-scope vs out-of-scope

### In scope
- Multi-warehouse inventory support in backend + frontend workflows
- Trailer entity model + assignment + status
- Trailer inventory movement paths
- Trailer location tracking and map/list visibility
- Warehouse/trailer dashboard updates
- Audit support for trailer inventory

### Out of scope (for this phase)
- Route optimization / dispatch routing engine
- GPS geofencing automation
- External telematics integrations
- Automated billing exports tied to trailer events

---

## 5) Proposed data model changes

## 5.1 Core approach

We will represent trailers as fleet assets and track their inventory via stock polymorphism.

Two viable options were reviewed:

- **Option A (recommended):** add `location_type='trailer'` in stock + movement tables
- Option B: model trailers as special vehicle rows and reuse `location_type='truck'`

### Recommended: Option A (`trailer` as explicit stock location type)

Why:
- Cleaner analytics split (truck vs trailer)
- Cleaner movement rules and UX labels
- Avoids confusing business language (trailer stock shown as truck stock)

## 5.2 Schema additions (new migration)

### A) Extend stock polymorphic enums

In `stock` and `stock_movements`, extend allowed location types:
- Existing: `warehouse`, `pulled`, `truck`, `job`
- New: `trailer`

### B) Trailer master table

`job_trailers`
- `id` PK
- `trailer_code` (unique human code, e.g., `TR-001`)
- `name`
- `status` (`active`, `in_transit`, `maintenance`, `inactive`)
- `home_warehouse_id` FK -> `warehouse_locations.id`
- `current_job_id` FK nullable -> `jobs.id`
- `assigned_driver_user_id` FK nullable -> `users.id`
- `notes`
- `is_active`
- timestamps

### C) Trailer location history table

`trailer_location_events`
- `id` PK
- `trailer_id` FK
- `event_type` (`check_in`, `departed`, `arrived_job`, `arrived_warehouse`, `manual_update`)
- `location_kind` (`warehouse`, `job`, `road`, `other`)
- `warehouse_id` FK nullable
- `job_id` FK nullable
- `lat`, `lng` nullable
- `recorded_by` FK -> `users.id`
- `recorded_at`
- `notes`

### D) Trailer template stock (optional, recommended)

`trailer_stock_templates`
- `id` PK
- `trailer_id` nullable (null = global template)
- `name`
- `is_default`

`trailer_stock_template_lines`
- `id` PK
- `template_id` FK
- `part_id` FK
- `target_qty`
- `min_qty`

This supports "common grab parts" restock guidance.

---

## 6) Movement rules (critical)

Update `MOVEMENT_RULES` and validation in `backend/app/models/warehouse.py` + `movement_service.py`.

### New valid paths

- `warehouse -> trailer` (transfer, preload)
- `trailer -> warehouse` (return)
- `trailer -> job` (consume; this is the explicit job usage event)
- `job -> trailer` (return from job)
- `pulled -> trailer` (transfer)
- `trailer -> pulled` (transfer)
- `truck -> trailer` and `trailer -> truck` (transfer, optional but useful in field)

### Guardrails

- **No auto-consume on preload:** warehouse→trailer and pulled→trailer are transfer only.
- **Consume only on explicit trailer→job movement.**
- Photo requirement policy should mirror truck/job transitions (configurable later).

---

## 7) Multi-warehouse behavior

## 7.1 Warehouse identity

Use existing `warehouse_locations` as canonical warehouse entities. 
Inventory views and movements must stop assuming warehouse id=1.

## 7.2 Required backend changes

1. Replace hardcoded defaults (`location_id=1`) where business flow intends "selected warehouse".
2. Add warehouse filters to inventory endpoints:
   - warehouse dashboard
   - inventory grid
   - parts search
   - staging summaries
3. Add inter-warehouse transfer flow:
   - `warehouse A -> warehouse B`

## 7.3 Warehouse UX

- Warehouse selector in top bar for warehouse module views
- Persist selected warehouse in local state/user preference
- KPI cards and queues scoped to selected warehouse (with optional "All Warehouses" aggregate)

---

## 8) Trailer location tracking behavior

Each trailer has a **current location snapshot** + historical events.

## 8.1 Current location resolution

Current location is computed from latest `trailer_location_events` row (plus fallback to last movement destination if no location events exist).

## 8.2 Update sources

- Manual check-in by field user
- Dispatch office updates
- Auto location hint from executed movement destinations (non-authoritative)

## 8.3 UX

New Trailer Dashboard / list must show:
- Trailer code/name
- Current location text (e.g., "Job 142 - West Plaza")
- Last check-in timestamp + who updated
- Inventory health (below-min lines)

---

## 9) API plan (new/extended endpoints)

## 9.1 Trailer CRUD + status

- `GET /api/trailers`
- `POST /api/trailers`
- `GET /api/trailers/{id}`
- `PUT /api/trailers/{id}`
- `DELETE /api/trailers/{id}` (soft deactivate)

## 9.2 Trailer location

- `GET /api/trailers/{id}/location`
- `GET /api/trailers/{id}/location-events`
- `POST /api/trailers/{id}/location-events`

## 9.3 Trailer inventory

- `GET /api/trailers/{id}/inventory`
- `POST /api/trailers/{id}/inventory/preload` (warehouse/pulled -> trailer)
- `POST /api/trailers/{id}/inventory/consume` (trailer -> job)
- `POST /api/trailers/{id}/inventory/return` (trailer -> warehouse)

## 9.4 Multi-warehouse inventory

- Extend `/api/warehouse/inventory` with `warehouse_id`
- Extend `/api/warehouse/dashboard*` with `warehouse_id`
- Add `POST /api/warehouse/transfer` (warehouse->warehouse convenience wrapper)

---

## 10) Frontend plan

## 10.1 Navigation

Add Trailer surfaces under fleet/warehouse depending on workflow preference:

### Recommended tab placement
- **Trucks module**
  - New tab: `Trailers`
  - New tab: `Trailer Locations`
- **Warehouse module**
  - New tab: `Warehouse Network` (multi-warehouse transfer + health)

## 10.2 New pages/components

- `frontend/src/features/trucks/pages/TrailersPage.tsx`
- `frontend/src/features/trucks/pages/TrailerDetailPage.tsx`
- `frontend/src/features/trucks/pages/TrailerLocationsPage.tsx`
- `frontend/src/features/warehouse/pages/WarehouseNetworkPage.tsx`

Shared components:
- Trailer location badge/card
- Trailer inventory table (matching truck inventory UX)
- Preload wizard (warehouse->trailer)

## 10.3 UX workflows

### A) Preload trailer
1. Select source warehouse
2. Select trailer
3. Choose common parts/template
4. Preview movement
5. Execute transfer

### B) Consume from trailer on job
1. Open trailer inventory
2. Select job destination
3. Enter qty used
4. Execute trailer->job movement

### C) Trailer location update
1. Open trailer card
2. Set current location (warehouse/job/road/manual)
3. Optional GPS capture
4. Save event

---

## 11) Permissions model

Reuse existing where possible:

- `view_trucks` (view trailer list/details)
- `manage_fleet` (create/edit trailers)
- `view_warehouse` (warehouse network visibility)
- `manage_inventory` (preload/transfer/consume/return movements)

Add only if needed:
- `manage_trailer_locations`

---

## 12) Reporting & analytics updates

Add trailer-aware metrics to dashboards/reports:

- Inventory by location type now includes `trailer`
- Trailer stock value and below-min count
- Preload vs consume ratio by trailer
- "Where is inventory parked?" split: warehouse/truck/trailer/job/pulled

---

## 13) Sync/offline implications (mobile)

Because mobile uses lean TS services and local SQLite:

1. Add trailer tables and enum updates to local migrations (`frontend/src/local/migrations/*`).
2. Add trailer service in local layer (`frontend/src/local/services/trailers-service.ts`).
3. Update sync replication list for new tables:
   - `job_trailers`
   - `trailer_location_events`
   - `trailer_stock_templates`
   - `trailer_stock_template_lines`
4. Ensure last-writer-wins merge is acceptable for location events (append-only table is safest).

---

## 14) Migration & rollout plan

## Suggested migration sequence

- `036_multi_warehouse_trailers_core.sql`
  - stock/movement enum expansion
  - trailer tables
  - indexes
- `037_trailer_templates.sql`
  - template tables
- `038_trailer_seed_data.sql`
  - optional defaults/permissions

> If migration numbers are already consumed in your active branch, keep names and bump numbers to next available.

## Rollout phases

### Phase 16B.1 — Foundation
- DB migration + models + base APIs
- No UI yet (internal validation)

### Phase 16B.2 — Operational UI
- Trailer pages + warehouse network views
- Movement wizard support for trailer paths

### Phase 16B.3 — Optimization
- Templates + low-stock alerts + trailer health KPIs

---

## 15) Testing strategy (E2E)

## 15.1 Critical flows

1. **Warehouse A -> Trailer preload**
2. **Trailer -> Job consume** (job usage increments, trailer decrements)
3. **Trailer -> Warehouse return**
4. **Inter-warehouse transfer**
5. **Trailer location check-in and history visibility**

## 15.2 Regression flows

- Existing truck inventory flows unchanged
- Existing warehouse->truck and truck->job flows unchanged
- Forecast/low-stock updates still run after movements
- Audit sessions still work with no broken queries

## 15.3 Responsive validation

Verify new pages at:
- 375x812
- 768x1024
- 1280x800+

---

## 16) Risks and mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Enum expansion breaks old queries | High | Add tests for all location filters; search for hardcoded `IN ('warehouse','pulled','truck','job')` |
| Hidden assumptions of warehouse id=1 | High | Introduce explicit `warehouse_id` parameter and defaults only at UI edge |
| Trailer vs truck confusion in UX | Medium | Use explicit labels/icons and separate tabs |
| Offline sync conflicts on location updates | Medium | Use append-only location events + derive current state |
| Movement rule regressions | High | Add movement matrix tests for all allowed/denied paths |

---

## 17) Definition of done

Phase is complete when:

- [ ] Multiple warehouses can be created and selected in operational views
- [ ] Trailer records can be created and managed
- [ ] Trailer inventory can be preloaded, consumed to job, and returned
- [ ] Parts on trailer are not consumed to job until explicit trailer->job move
- [ ] Trailer current location + history are visible and editable
- [ ] Warehouse and fleet dashboards include trailer/multi-warehouse metrics
- [ ] Mobile local DB + sync support new trailer/multi-warehouse data
- [ ] Backend tests pass, frontend build passes, responsive checks pass
- [ ] Existing truck and warehouse flows are regression-clean

---

## 18) Immediate next implementation tasks

1. Finalize Option A (`location_type='trailer'`) approval.
2. Write migration SQL draft and movement-rule matrix tests.
3. Add backend trailer router/service/repo skeleton.
4. Implement warehouse selector and trailer list UI.
5. Execute E2E test script for preload->consume->return lifecycle.

---

## 19) Open decisions for user confirmation

1. Should trailers appear under **Trucks** only, or both **Trucks + Warehouse** nav contexts?
2. Should trailer location updates require GPS capture or allow manual-only by default?
3. For trailer templates: per-trailer templates only, or global reusable templates too?
4. Should trailer->job consume require photo verification like truck->job currently does?
5. Should we allow direct `warehouse -> job_trailer_assigned_job` quick-pull in one action, or enforce two-step flow (warehouse->trailer, trailer->job)?
