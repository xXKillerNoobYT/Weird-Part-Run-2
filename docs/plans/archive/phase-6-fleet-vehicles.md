# Phase 6: Fleet & Vehicle Management — Implementation Plan

> **Status**: Complete (March 2026)
> **Previous phases**: 1-3 (Foundation, Parts, Warehouse), 3.5+4 (Jobs & Labor), 4.5 (Notebooks), 5 (Orders & Procurement)

## Context

Wired-Part needs a full vehicle management system for the field service fleet. Electricians drive company trucks (and sometimes personal vehicles) to job sites daily, carrying parts inventory and tools. The business needs to track:

- **What's on each truck** (mobile parts inventory + tools)
- **What needs to be delivered** (job-bound delivery items)
- **How far they drive** (daily mileage: Home → Shop → Job → Home)
- **Vehicle health** (oil changes, tire rotations, brake inspections, etc.)
- **Who drives what** (assignments, take-home privileges)
- **Private vehicles** (full tracking + mileage reimbursement for employee-owned cars)
- **Shop/warehouse address** (needed as the anchor point for mileage estimation)

The existing codebase has **stub infrastructure** ready: 5 navigation tabs, stub router endpoints, `LocationType = 'truck'` in the stock system, and `users.default_truck_id`. This plan replaces all stubs with a complete implementation.

---

## User Decisions

| Question | Answer |
|----------|--------|
| Fleet management? | Yes — manager-level dashboard for all vehicles |
| Warehouse address location? | **Office section** — new tab under Office |
| Mileage estimation method? | **Manual input** — one-time distance entry per job and per employee home (see below) |
| Private vehicle tracking? | **Full parity** — same features as company vehicles + reimbursement |

### Manual Distance Input (Key Decision)

Instead of GPS-based calculations, distances are entered manually once:

1. **Job → Shop distance**: When creating/editing a job, a `distance_from_shop_miles` field is entered once. This is the known driving distance from the main shop to the job site.
2. **Employee Home → Shop distance**: On each vehicle assignment (or employee profile in fleet context), a `home_to_shop_miles` field is entered once. This is the employee's commute distance.

**Daily mileage estimation then becomes simple addition:**
- Standard route: `home_to_shop + shop_to_job + job_to_shop + shop_to_home`
- Take-home route: `home_to_job + job_to_home` (approx: `|home_to_shop - shop_to_job|` to `home_to_shop + shop_to_job` depending on direction)
- Multi-job day: sum of all legs

This is more accurate than GPS formulas (drivers know their actual routes) and requires zero API costs.

### Drive Time Tracking (Pay-Related)

Drive time between locations is tracked for **payroll purposes** — typically one-way drive time is billable (shop→job, job→job) while commute time (home→shop) is not.

- **Estimated drive time**: Manually entered per job (like distance) — `estimated_drive_minutes_from_shop` on the jobs table
- **Actual drive time**: Logged per trip leg alongside mileage — `actual_drive_minutes` on each trip leg
- **Billable flag**: Each trip leg marked as `is_billable` (shop→job = yes, home→shop = no)
- **Job-to-job drives**: When moving between jobs in a day, drive time + distance tracked as a separate leg with both job references
- **Integration with labor**: Drive time feeds into daily reports and pre-billing alongside clock hours

---

## Database Schema — Migration 017

**File**: `backend/app/migrations/017_fleet_vehicles.sql`

### Tables (10 new tables)

#### 1. `vehicles` — Core vehicle entity
```
id, vehicle_number (unique, e.g. "T-001"), vehicle_name, vehicle_type (company_truck|company_van|company_car|private_vehicle), status (active|inactive|maintenance|retired), make, model, year, color, vin, license_plate, insurance_policy, insurance_expiry, registration_expiry, current_odometer, owner_user_id (FK users — for private vehicles only), notes, photo_path, is_active, created_at, updated_at
```

#### 2. `vehicle_assignments` — Who drives what
```
id, vehicle_id (FK), user_id (FK), assignment_type (primary|authorized|temporary), is_take_home (bool), home_to_shop_miles (REAL — manual one-time entry), home_address_street/city/state/zip (optional, for reference only), start_date, end_date (null=current), notes, created_at, updated_at
UNIQUE(vehicle_id, user_id, assignment_type)
```
> `home_to_shop_miles` is the key field — manually entered once per driver assignment. Home address is optional reference info.

#### 3. `warehouse_locations` — Shop/warehouse addresses
```
id, name ("Main Shop"), address_street/city/state/zip, gps_lat/lng (optional, for map display), is_primary (main shop location), is_active, company_profile_id (FK optional), notes, created_at, updated_at
```
> The address is for display/reference. Mileage estimation uses manual `distance_from_shop_miles` on jobs and `home_to_shop_miles` on assignments — not GPS math.

#### 4. `vehicle_delivery_items` — Job-bound items on a truck
```
id, vehicle_id (FK), job_id (FK), part_id (FK), qty_assigned, qty_delivered, assigned_by (FK users), delivered_by (FK users), delivered_at, status (assigned|loaded|in_transit|delivered|returned), notes, created_at, updated_at
```
> **Distinct from vehicle inventory.** Delivery items are designated for a specific job. Vehicle inventory is general stock at `location_type='truck'`.

#### 5. `maintenance_types` — Configurable lookup (seeded)
```
id, name (unique), description, default_interval_miles, default_interval_months, sort_order, is_active, created_at
```
Seed data: Oil Change (5k mi/6mo), Tire Rotation (7.5k/6mo), Brake Inspection (15k/12mo), Transmission Service (30k/24mo), Coolant Flush, Air Filter, Cabin Air Filter, Spark Plugs, Battery Check, Wiper Blades, State Inspection, DEF Fluid, General Service.

#### 6. `vehicle_maintenance_schedules` — Per-vehicle intervals
```
id, vehicle_id (FK), maintenance_type_id (FK), interval_miles (override), interval_months (override), last_performed_at, last_performed_miles, next_due_date, next_due_miles, is_enabled, notes, created_at, updated_at
UNIQUE(vehicle_id, maintenance_type_id)
```

#### 7. `vehicle_maintenance_records` — Actual service history
```
id, vehicle_id (FK), maintenance_type_id (FK), service_date, odometer_reading, cost, vendor, invoice_number, description, performed_by (FK users), photo_path, notes, created_at
```

#### 8. `vehicle_mileage_logs` — Daily odometer readings
```
id, vehicle_id (FK), driver_id (FK users), log_date, odometer_start, odometer_end, total_miles (GENERATED: end - start), is_take_home_day, notes, created_at, updated_at
UNIQUE(vehicle_id, log_date)
```

#### 9. `vehicle_trip_legs` — Trip segments per day (miles + drive time)
```
id, mileage_log_id (FK CASCADE), leg_order, leg_type (home_to_shop|shop_to_job|job_to_job|job_to_shop|shop_to_home|job_to_home|other), from_label, to_label, from_gps_lat/lng, to_gps_lat/lng, estimated_miles, actual_miles, estimated_drive_minutes, actual_drive_minutes, is_billable (bool — shop→job and job→job = true, commute = false), from_job_id (FK jobs, for job_to_job legs), to_job_id (FK jobs, for job legs), notes, created_at
```

#### 10. `mileage_reimbursements` — Private vehicle payback
```
id, user_id (FK), vehicle_id (FK), period_start, period_end, total_miles, rate_per_mile (default 0.67 IRS rate), total_amount (GENERATED: miles × rate), status (pending|approved|paid|rejected), approved_by (FK users), approved_at, notes, created_at, updated_at
```

### Also in migration 017:
- Updated_at triggers for all relevant tables
- Indexes on all foreign keys and common query columns
- Seed `maintenance_types` with 13 common service types
- Seed `settings` with fleet config keys (reimbursement rate, alert thresholds)
- New permissions: `manage_fleet`, `log_mileage` granted to appropriate hats

---

## Backend Implementation

### Models — `backend/app/models/vehicles.py` (new)

Pydantic models following existing Create/Update/Response pattern:

| Group | Models |
|-------|--------|
| Vehicle | `VehicleCreate`, `VehicleUpdate`, `VehicleResponse`, `VehicleListItem` |
| Assignment | `VehicleAssignmentCreate`, `VehicleAssignmentResponse` |
| Warehouse | `WarehouseLocationCreate`, `WarehouseLocationUpdate`, `WarehouseLocationResponse` |
| Delivery | `DeliveryItemCreate`, `DeliveryItemUpdate`, `DeliveryItemResponse` |
| Maintenance | `MaintenanceTypeCreate`, `MaintenanceTypeResponse`, `MaintenanceScheduleCreate`, `MaintenanceScheduleUpdate`, `MaintenanceScheduleResponse`, `MaintenanceRecordCreate`, `MaintenanceRecordResponse` |
| Mileage | `MileageLogCreate`, `MileageLogUpdate`, `MileageLogResponse`, `TripLegCreate`, `TripLegResponse` |
| Reimbursement | `ReimbursementCreate`, `ReimbursementResponse` |
| Dashboard | `FleetDashboardStats`, `MyVehicleDashboard`, `MaintenanceAlert`, `MileageEstimate` |

### Repository — `backend/app/repositories/vehicle_repo.py` (new)

10 repo classes extending `BaseRepo`:

| Repo | Table | Key Methods |
|------|-------|-------------|
| `VehicleRepo` | vehicles | `list_with_filters`, `get_with_details`, `get_by_user` |
| `VehicleAssignmentRepo` | vehicle_assignments | `get_active_for_user`, `get_active_for_vehicle`, `get_primary_driver` |
| `WarehouseLocationRepo` | warehouse_locations | `get_primary`, `list_active` |
| `VehicleDeliveryRepo` | vehicle_delivery_items | `get_for_vehicle`, `get_for_job`, `get_pending` |
| `MaintenanceTypeRepo` | maintenance_types | `list_active` |
| `MaintenanceScheduleRepo` | vehicle_maintenance_schedules | `get_for_vehicle`, `get_overdue`, `get_upcoming` |
| `MaintenanceRecordRepo` | vehicle_maintenance_records | `get_for_vehicle`, `get_cost_summary` |
| `MileageLogRepo` | vehicle_mileage_logs | `get_for_vehicle`, `get_for_driver`, `get_daily` |
| `TripLegRepo` | vehicle_trip_legs | `get_for_log`, `get_for_job` |
| `ReimbursementRepo` | mileage_reimbursements | `get_for_user`, `get_pending` |

### Services (4 new files)

| File | Responsibility |
|------|---------------|
| `backend/app/services/vehicle_service.py` | Vehicle CRUD, assignments, fleet dashboard, vehicle inventory (delegates to StockRepo with `location_type='truck'`) |
| `backend/app/services/delivery_service.py` | Assign delivery items, mark delivered (triggers stock movement truck→job), return undelivered |
| `backend/app/services/maintenance_service.py` | Log service records, update schedules, calculate next-due, alerts, cost reports |
| `backend/app/services/mileage_service.py` | Daily mileage logging, trip legs, Haversine estimation (x1.3 road factor), reimbursement CRUD |

### Router — `backend/app/routers/trucks.py` (rewrite existing stubs)

~35 endpoints, prefix stays `/api/trucks`:

```
# Vehicle CRUD
GET    /                              → list vehicles (filters: type, status, driver)
POST   /                              → create vehicle
GET    /my-vehicle                    → current user's assigned vehicle dashboard
GET    /{id}                          → vehicle detail (MUST BE LAST — catch-all)
PUT    /{id}                          → update vehicle (MUST BE LAST — catch-all)
DELETE /{id}                          → deactivate (MUST BE LAST — catch-all)

# Assignments
GET    /{id}/assignments              → list assignments
POST   /{id}/assign                   → assign driver
DELETE /{id}/assign/{user_id}         → unassign
PUT    /{id}/take-home                → toggle take-home

# Vehicle Inventory (uses existing stock system)
GET    /{id}/inventory                → parts on vehicle
POST   /{id}/inventory/add            → add parts (stock movement)
POST   /{id}/inventory/remove         → remove parts (stock movement)

# Delivery Items
GET    /{id}/deliveries               → delivery items
POST   /{id}/deliveries               → assign items for delivery
PUT    /{id}/deliveries/{item_id}/deliver  → mark delivered
PUT    /{id}/deliveries/{item_id}/return   → return undelivered

# Maintenance Types (admin)
GET    /maintenance-types             → list types
POST   /maintenance-types             → create
PUT    /maintenance-types/{id}        → update

# Maintenance Schedules
GET    /{id}/maintenance/schedule     → per-vehicle schedule
POST   /{id}/maintenance/schedule     → set/update schedule
GET    /maintenance/upcoming          → fleet-wide upcoming
GET    /maintenance/overdue           → fleet-wide overdue

# Maintenance Records
GET    /{id}/maintenance/history      → service history
POST   /{id}/maintenance/log          → log service
GET    /{id}/maintenance/costs        → cost summary

# Mileage
GET    /{id}/mileage                  → mileage logs
POST   /{id}/mileage                  → log daily mileage
PUT    /{id}/mileage/{log_id}         → update entry
GET    /{id}/mileage/{log_id}/trips   → trip legs
POST   /{id}/mileage/{log_id}/trips   → add trip legs
GET    /mileage/estimate              → estimate trip (query params)

# Reimbursement (private vehicles)
GET    /reimbursements                → list
POST   /reimbursements                → create
PUT    /reimbursements/{id}/approve   → approve

# Warehouse Locations
GET    /warehouse-locations           → list
POST   /warehouse-locations           → create
PUT    /warehouse-locations/{id}      → update
DELETE /warehouse-locations/{id}      → deactivate

# Fleet Dashboard
GET    /fleet/dashboard               → fleet overview stats
```

---

## Frontend Implementation

### Types — `frontend/src/lib/types.ts` (additions)

```typescript
VehicleType = 'company_truck' | 'company_van' | 'company_car' | 'private_vehicle'
VehicleStatus = 'active' | 'inactive' | 'maintenance' | 'retired'
Vehicle, VehicleListItem, VehicleAssignment, WarehouseLocation
VehicleDeliveryItem, MaintenanceType, MaintenanceSchedule, MaintenanceRecord
MileageLog, TripLeg, MileageReimbursement
FleetDashboardStats, MyVehicleDashboard, MaintenanceAlert, MileageEstimate
```

### API Layer — `frontend/src/api/vehicles.ts` (new)

TanStack Query wrappers for all ~35 endpoints. Follows existing patterns in `api/settings.ts` and `api/orders.ts`.

### Navigation — `frontend/src/lib/navigation.ts` (modify)

Update trucks module tabs:
```
My Vehicle | All Vehicles | Tools | Maintenance | Mileage | Fleet (manage_fleet only)
```

Add to Office module:
```
Warehouse Locations (new tab for shop address management)
```

### Pages

| File | Tab | Description |
|------|-----|-------------|
| `features/trucks/pages/MyTruckPage.tsx` | My Vehicle | Driver dashboard: assigned vehicle info, inventory, today's deliveries, maintenance alerts, quick mileage log |
| `features/trucks/pages/AllTrucksPage.tsx` | All Vehicles | Fleet list with filters (type/status/driver), search, create button |
| `features/trucks/pages/VehicleDetailPage.tsx` | /trucks/:id | Deep dive: info, inventory, deliveries, maintenance, mileage, assignments |
| `features/trucks/pages/ToolsPage.tsx` | Tools | Per-vehicle tool tracking, check-in/out (stub — coming soon) |
| `features/trucks/pages/MaintenancePage.tsx` | Maintenance | Cross-fleet: upcoming/overdue, log service, cost summaries |
| `features/trucks/pages/MileagePage.tsx` | Mileage | Daily logs, trip breakdown, estimation calculator, reimbursement section |
| `features/trucks/pages/FleetDashboardPage.tsx` | Fleet | Manager KPIs: total vehicles, fleet miles, maintenance alerts, costs |
| `features/office/pages/WarehouseLocationsPage.tsx` | Office tab | CRUD for shop/warehouse physical addresses |

### Components — `frontend/src/features/trucks/components/`

```
VehicleCard.tsx                — Vehicle card in list view
VehicleInfoPanel.tsx           — Editable details panel
VehicleInventoryList.tsx       — Parts on vehicle with search
DeliveryItemCard.tsx           — Delivery item with action buttons
DeliveryItemList.tsx           — Deliveries per vehicle/job
MaintenanceAlertBanner.tsx     — Overdue warning banner
MaintenanceRecordModal.tsx     — Log new service modal
MaintenanceScheduleEditor.tsx  — Edit intervals per vehicle
MaintenanceTimeline.tsx        — Visual service history
MileageLogForm.tsx             — Daily odometer entry
MileageLogTable.tsx            — Mileage log list
TripLegEditor.tsx              — Add/edit trip segments
TripEstimator.tsx              — Home→Shop→Job→Home calculator (uses stored manual distances)
AssignDriverModal.tsx          — Assign drivers to vehicles
CreateVehicleModal.tsx         — Create vehicle form
VehicleStatusBadge.tsx         — Color-coded status pill
ReimbursementList.tsx          — Reimbursement records
ReimbursementModal.tsx         — Create reimbursement for period
WarehouseLocationEditor.tsx    — CRUD for warehouse locations
FleetKpiCards.tsx              — Fleet dashboard KPI cards
```

### Route Registration — `frontend/src/App.tsx`

```
/trucks/:id → VehicleDetailPage
/trucks/fleet → FleetDashboardPage
```

---

## Integration Points

| System | Integration | Files Modified |
|--------|-------------|---------------|
| **Stock movements** | Vehicle inventory uses existing `location_type='truck'`, delivery marks trigger truck→job movements | `services/movement_service.py`, `repositories/stock_repo.py` |
| **Jobs** | Add `distance_from_shop_miles` column to `jobs` table, delivery items linked via `job_id`, trip legs linked to jobs, optional mileage prompt on clock-out | `routers/jobs.py`, `models/jobs.py` (add field to create/update/response) |
| **Users** | `users.default_truck_id` points to `vehicles.id`, assignment enriches user profile | `repositories/user_repo.py` |
| **Notifications** | Maintenance due alerts via scheduler | `scheduler.py`, `services/notification_service.py` |
| **Settings** | Fleet config keys (reimbursement rate, alert thresholds) via existing key-value settings | `routers/app_settings.py` |

---

## Mileage Estimation — Manual Input Based

No GPS calculations needed. Distances are manually entered once and reused:

### Data Sources
- **`vehicle_assignments.home_to_shop_miles`** — entered once when assigning driver
- **`jobs.distance_from_shop_miles`** — entered once when creating/editing a job (NEW column on existing `jobs` table)

### Estimation Logic
```python
def estimate_daily_miles(home_to_shop: float, shop_to_job: float, take_home: bool, multi_jobs: list[float] = None) -> MileageEstimate:
    """
    Standard day:  Home → Shop → Job → Shop → Home
      = home_to_shop + shop_to_job + shop_to_job + home_to_shop
      = 2 x (home_to_shop + shop_to_job)

    Take-home day: Home → Job → Home
      = estimated as home_to_shop + shop_to_job (one way, doubled)
      or manual override

    Multi-job day: Home → Shop → Job1 → Job2 → ... → Shop → Home
      = home_to_shop + shop_to_job1 + job1_to_job2 (manual) + ... + last_job_to_shop + home_to_shop
    """
```

### Jobs Table Changes
Add columns to existing `jobs` table (part of migration 017):
```sql
ALTER TABLE jobs ADD COLUMN distance_from_shop_miles REAL;
ALTER TABLE jobs ADD COLUMN estimated_drive_minutes_from_shop INTEGER;
```
Both are one-time inputs when creating or editing a job. Distance in miles, drive time in minutes.

---

## Build Sequence (10 Steps)

| Step | What | Files | Status |
|------|------|-------|--------|
| **1** | Migration + Models | `017_fleet_vehicles.sql`, `models/vehicles.py` | ✅ Complete |
| **2** | Repositories | `repositories/vehicle_repo.py` | ✅ Complete |
| **3** | Vehicle + Delivery services | `services/vehicle_service.py`, `services/delivery_service.py` | ✅ Complete |
| **4** | Maintenance + Mileage services | `services/maintenance_service.py`, `services/mileage_service.py` | ✅ Complete |
| **5** | Router (all endpoints) | `routers/trucks.py` (rewrite) | ✅ Complete |
| **6** | Frontend types + API | `types.ts`, `api/vehicles.ts` | ✅ Complete |
| **7** | My Vehicle + All Vehicles pages | `MyTruckPage.tsx`, `AllTrucksPage.tsx`, `VehicleDetailPage.tsx` + components | ✅ Complete |
| **8** | Maintenance pages | `MaintenancePage.tsx` + components | ✅ Complete |
| **9** | Mileage pages + Warehouse Locations | `MileagePage.tsx`, `WarehouseLocationsPage.tsx` + components | ✅ Complete |
| **10** | Fleet Dashboard + Integration + Responsive audit | `FleetDashboardPage.tsx`, navigation updates, responsive testing | ✅ Complete |

---

## Verification Results

| # | Check | Result |
|---|-------|--------|
| 1 | Migration: 10 tables created + seeds populated | ✅ Pass |
| 2 | API: ~35 endpoints registered, no startup errors | ✅ Pass |
| 3 | My Vehicle: Empty state renders ("No Vehicle Assigned") | ✅ Pass |
| 4 | All Vehicles: List, search, filter, create button render | ✅ Pass |
| 5 | Tools: Stub placeholder renders ("Coming soon") | ✅ Pass |
| 6 | Maintenance: Overview stats, timeframe selector, log service button | ✅ Pass |
| 7 | Mileage: Vehicle selector, stat cards, daily logs tab, reimbursements tab | ✅ Pass |
| 8 | Warehouse Locations: Seeded "Main Shop" renders, CRUD buttons work | ✅ Pass |
| 9 | Fleet Dashboard: 6 fleet KPIs + 4 monthly metrics + maintenance sections | ✅ Pass |
| 10 | Responsive 1280x800 (desktop) | ✅ Pass — all 7 pages |
| 11 | Responsive 768x1024 (tablet) | ✅ Pass — all 7 pages, tab bar fits without scroll |
| 12 | Responsive 375x812 (mobile) | ✅ Pass — all 7 pages, tab bar scrolls horizontally |

---

## Bugs Found & Fixed During Verification

### 1. Trailing-slash 307 redirect stripping auth headers
- **Symptom**: All API calls returned 401 Unauthorized
- **Root cause**: FastAPI's `redirect_slashes=True` (default) sends 307 redirect when `/api/trucks/` hits `/api/trucks`. Browsers strip `Authorization` header on redirect.
- **Fix**: Added `redirect_slashes=False` to all routers; removed trailing slashes from frontend API calls
- **Files**: All `routers/*.py`, `frontend/src/api/vehicles.ts`, `frontend/src/api/settings.ts`

### 2. Fleet Dashboard 500 — NULL SQL aggregates on empty tables
- **Symptom**: `GET /api/trucks/fleet/dashboard` returned 500 ResponseValidationError
- **Root cause**: `SUM(CASE WHEN ... THEN 1 ELSE 0 END)` returns `NULL` (not `0`) when the `vehicles` table is empty. Pydantic rejects `None` for `int` fields.
- **Fix**: Wrapped all SUM aggregates in `COALESCE(..., 0)` in `vehicle_repo.py`'s `get_fleet_stats()`
- **Files**: `backend/app/repositories/vehicle_repo.py`

### 3. Route ordering collision — `/{vehicle_id}` catch-all blocking named routes
- **Symptom**: `GET /api/trucks/warehouse-locations` returned 422, `GET /api/trucks/fleet/dashboard` also 422
- **Root cause**: `/{vehicle_id}` defined early in the file matched before `/warehouse-locations`, `/fleet/*`, etc. Starlette is first-match with no backtracking after type validation failure.
- **Fix**: Moved `/{vehicle_id}` GET/PUT/DELETE to the very end of the router file
- **Files**: `backend/app/routers/trucks.py`

### 4. Paginated response unwrap
- **Symptom**: Vehicle list showed empty despite data existing
- **Root cause**: `listVehicles()` expected `data.data` but backend returns `data.data.items` for paginated responses
- **Fix**: Updated `vehicles.ts` to unwrap `data.data?.items ?? []`
- **Files**: `frontend/src/api/vehicles.ts`

### 5. HMR createRoot corruption
- **Symptom**: Hot reload caused blank screen with React "already a root" error
- **Root cause**: Vite HMR re-executed `main.tsx` creating duplicate React roots
- **Fix**: Added guard `if (!root) root = createRoot(...)` pattern
- **Files**: `frontend/src/main.tsx`

---

## Lessons Learned

1. **COALESCE all SQL aggregates** — SQLite returns NULL for SUM/COUNT on empty result sets. Always wrap in COALESCE when the result feeds into a typed model.
2. **Route ordering in FastAPI is critical** — `/{param}` catch-all routes must be registered LAST. Starlette matches by registration order and does not backtrack on type validation failure. This mirrors the same pattern already used in `app_settings.py` with `/{key}`.
3. **`redirect_slashes=False`** should be set on ALL routers to prevent 307 redirects that strip auth headers. This is especially important for API routers where clients may or may not include trailing slashes.
4. **Test empty states first** — most bugs surface when tables are empty (NULL aggregates, missing data guards). A fresh database is the best first test.
5. **Tab bar overflow pattern** — `overflow-x-auto scrollbar-thin` provides graceful horizontal scrolling on mobile without needing to truncate or hide tab labels.
