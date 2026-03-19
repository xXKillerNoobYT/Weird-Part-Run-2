# Phase 16B: Multi-Warehouse & Job Trailers — Implementation

**Status:** ✅ Complete
**Date:** 2025-07-06

## Overview

Phase 16B adds multi-warehouse support, warehouse-to-warehouse transfers, and trailer stock templates to the existing fleet/warehouse system. Most of the infrastructure was already implemented in migrations 036 (multi-warehouse + trailers) and the corresponding services/routers. This phase closed the remaining gaps.

## What Was Already Built (Pre-Phase 16B)

- Migration 036: `job_trailers`, `trailer_location_events` tables, `trailer` location type in stock CHECK
- Movement rules: 15 rules covering warehouse↔truck↔trailer↔job paths
- `vehicle_service.py`: Full trailer CRUD, inventory, location tracking
- `trucks.py` router: ~14 trailer endpoints (CRUD, preload, consume, return, location)
- Sync tables: `job_trailers`, `trailer_location_events` already in SYNCED_TABLES_ORDERED
- Location picker: Already includes warehouses, trucks, trailers, jobs

## Gaps Identified & Fixed

### 1. Warehouse→Warehouse Transfer Rule ✅
**File:** `backend/app/models/warehouse.py`
**Change:** Added `("warehouse", "warehouse")` to `MOVEMENT_RULES` dict (16→17 rules)
**Why:** Inter-warehouse transfers were missing despite multi-warehouse support existing

### 2. Multi-Warehouse Dashboard/KPI Scoping ✅
**File:** `backend/app/services/warehouse_service.py`
**Change:** Added `warehouse_id: int | None` parameter to:
- `get_dashboard()` — passes through to KPI + activity
- `get_kpis()` — filters stock health, total units, warehouse value, shortfall queries
- `get_recent_activity()` — filters to movements touching specific warehouse
- `get_warehouse_inventory()` — scopes inventory grid and count queries

**File:** `backend/app/routers/warehouse.py`
**Change:** Added `warehouse_id: int | None = Query(None)` to dashboard, KPIs, activity, and inventory endpoints

### 3. Trailer Stock Templates ✅
**Migration:** `044_trailer_templates_and_warehouse_transfer.sql`
- `trailer_stock_templates` — id, trailer_id (nullable FK for global), name, is_default, notes
- `trailer_stock_template_lines` — id, template_id (CASCADE FK), part_id, target_qty, min_qty

**Service:** `vehicle_service.py` (added 7 methods)
- `list_trailer_templates(trailer_id?, include_global?)` — scoped listing
- `get_trailer_template(id)` — single template with lines + part details
- `create_trailer_template(data)` — create with lines, auto-clear defaults in same scope
- `update_trailer_template(id, data)` — update header + optionally replace all lines
- `delete_trailer_template(id)` — CASCADE deletes lines
- `get_restock_guidance(trailer_id)` — compare actual vs template targets, returns deficit + status

**Router:** `trucks.py` (added 6 endpoints)
- `GET /api/trucks/trailer-templates` — list (filterable by trailer_id)
- `GET /api/trucks/trailer-templates/{id}` — single with lines
- `POST /api/trucks/trailer-templates` — create
- `PUT /api/trucks/trailer-templates/{id}` — update
- `DELETE /api/trucks/trailer-templates/{id}` — delete
- `GET /api/trucks/trailers/{id}/restock-guidance` — deficit analysis

### 4. Vehicle Inventory Movement Bypass Fix ✅
**File:** `backend/app/services/vehicle_service.py`
**Change:** Refactored `add_to_vehicle_inventory()` and `remove_from_vehicle_inventory()` to route through `MovementService.execute_movement()` instead of raw SQL INSERT/UPDATE.
**Why:** These were the only two methods bypassing the atomic movement engine — breaking FIFO order, supplier tracking, and audit trail consistency.

### 5. Trailer Qty in Inventory Grid ✅
**File:** `backend/app/models/warehouse.py`
**Change:** Added `trailer_qty: int = 0` to `WarehouseInventoryItem` model

**File:** `backend/app/services/warehouse_service.py`
**Change:** Added trailer stock subquery to inventory grid SQL, includes trailer_qty in result mapping

### 6. Sync Table Registration ✅
**File:** `backend/app/services/sync_service.py`
**Change:** Added `trailer_stock_templates` and `trailer_stock_template_lines` to `SYNCED_TABLES_ORDERED`

### 7. Datetime Deprecation Fix ✅
**File:** `backend/app/services/device_security_service.py`
**Change:** Fixed `datetime.utcnow()` → `datetime.now(UTC)` with `from datetime import UTC`

## Tests

**File:** `backend/tests/test_phase16b_multi_warehouse.py` (5 tests)
1. `test_warehouse_to_warehouse_transfer` — verifies warehouse→warehouse movement via execute endpoint
2. `test_dashboard_kpis_with_warehouse_filter` — KPIs accept warehouse_id, return valid data
3. `test_inventory_with_warehouse_filter` — inventory scoping + trailer_qty field present
4. `test_trailer_template_crud` — full CRUD cycle + restock guidance with deficit analysis
5. `test_vehicle_add_remove_inventory_uses_movement` — vehicle add/remove now uses MovementService (returns movement_count)

## Files Modified

| File | Change |
|------|--------|
| `models/warehouse.py` | +warehouse→warehouse rule, +trailer_qty field |
| `services/warehouse_service.py` | +warehouse_id scoping on 4 methods, +trailer stock subquery |
| `services/vehicle_service.py` | +7 template methods, refactored 2 movement methods |
| `services/sync_service.py` | +2 sync tables |
| `services/device_security_service.py` | datetime.utcnow → datetime.now(UTC) |
| `routers/warehouse.py` | +warehouse_id Query params on 4 endpoints |
| `routers/trucks.py` | +6 template endpoints |

## Files Created

| File | Purpose |
|------|---------|
| `migrations/044_trailer_templates_and_warehouse_transfer.sql` | Template tables |
| `tests/test_phase16b_multi_warehouse.py` | 5 Phase 16B tests |
| `docs/plans/phase-16b-multi-warehouse-trailers-impl.md` | This file |

## API Endpoint Summary (New)

| Method | Path | Permission |
|--------|------|------------|
| GET | `/api/trucks/trailer-templates` | view_trucks |
| GET | `/api/trucks/trailer-templates/{id}` | view_trucks |
| POST | `/api/trucks/trailer-templates` | manage_fleet |
| PUT | `/api/trucks/trailer-templates/{id}` | manage_fleet |
| DELETE | `/api/trucks/trailer-templates/{id}` | manage_fleet |
| GET | `/api/trucks/trailers/{id}/restock-guidance` | view_trucks |

## Updated Endpoints

| Method | Path | Change |
|--------|------|--------|
| GET | `/api/warehouse/dashboard` | +warehouse_id param |
| GET | `/api/warehouse/dashboard/kpis` | +warehouse_id param |
| GET | `/api/warehouse/dashboard/activity` | +warehouse_id param |
| GET | `/api/warehouse/inventory` | +warehouse_id param, +trailer_qty in response |
