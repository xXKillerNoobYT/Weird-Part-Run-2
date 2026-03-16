# Fleet & Vehicles Audit

> **Date:** 2026-03-06
> **Status:** ✅ Verified Complete (2026-03-07) — 100% functional (44 endpoints, all pages). E2E responsive validated at mobile/tablet/desktop. Architectural notes about large files (vehicle_repo 915L, trucks router 974L) are informational; no refactoring needed for V1.0.
> **Scope:** Full audit of the Fleet module — vehicles, assignments, vehicle inventory, deliveries, maintenance (types/schedules/records), mileage (logs/trips/estimates), reimbursements, warehouse locations, fleet dashboard

---

## Table of Contents

1. [Backend Inventory](#1-backend-inventory)
2. [Frontend Inventory](#2-frontend-inventory)
3. [Feature Completeness](#3-feature-completeness)
4. [Cross-References](#4-cross-references)
5. [Issues & TODOs](#5-issues--todos)

---

## 1. Backend Inventory

### Router: `backend/app/routers/trucks.py` (~974 lines)

Mounted in `main.py` as `app.routers.trucks`. Prefix: `/api/trucks`.

**⚠️ Route ordering is critical:** The `/{vehicle_id}` catch-all routes (GET/PUT/DELETE) MUST be registered last to avoid collisions with named paths like `/maintenance-types`, `/reimbursements`, `/warehouse-locations`, and `/fleet/*`.

#### Vehicle CRUD (3 endpoints)

| # | Method | Path | Description | Permission | Status |
|---|--------|------|-------------|------------|--------|
| 1 | `GET` | `/` | List vehicles (paginated, search, status filter) | `view_trucks` | ✅ Functional |
| 2 | `POST` | `/` | Create vehicle | `manage_fleet` | ✅ Functional |
| 3 | `GET` | `/my-vehicle` | Current user's vehicle dashboard | any auth | ✅ Functional |

#### Assignments (4 endpoints)

| # | Method | Path | Description | Permission | Status |
|---|--------|------|-------------|------------|--------|
| 4 | `GET` | `/{vehicle_id}/assignments` | List active assignments for vehicle | `view_trucks` | ✅ Functional |
| 5 | `POST` | `/{vehicle_id}/assign` | Assign driver to vehicle | `manage_fleet` | ✅ Functional |
| 6 | `DELETE` | `/{vehicle_id}/assign/{target_user_id}` | Unassign driver from vehicle | `manage_fleet` | ✅ Functional |
| 7 | `PUT` | `/{vehicle_id}/take-home` | Toggle take-home status (current user) | any auth | ✅ Functional |

#### Vehicle Inventory (3 endpoints)

| # | Method | Path | Description | Permission | Status |
|---|--------|------|-------------|------------|--------|
| 8 | `GET` | `/{vehicle_id}/inventory` | Get parts inventory on vehicle | `view_trucks` | ✅ Functional |
| 9 | `POST` | `/{vehicle_id}/inventory/add` | Add parts (warehouse→truck movement) | `manage_fleet` | ✅ Functional |
| 10 | `POST` | `/{vehicle_id}/inventory/remove` | Remove parts (truck→warehouse movement) | `manage_fleet` | ✅ Functional |

#### Delivery Items (5 endpoints)

| # | Method | Path | Description | Permission | Status |
|---|--------|------|-------------|------------|--------|
| 11 | `GET` | `/{vehicle_id}/deliveries` | List delivery items on vehicle | `view_trucks` | ✅ Functional |
| 12 | `POST` | `/{vehicle_id}/deliveries` | Assign delivery items (bulk) | `manage_fleet` | ✅ Functional |
| 13 | `PUT` | `/{vehicle_id}/deliveries/{item_id}/status` | Update delivery status | any auth | ✅ Functional |
| 14 | `PUT` | `/{vehicle_id}/deliveries/{item_id}/deliver` | Mark delivered (truck→job movement) | any auth | ✅ Functional |
| 15 | `PUT` | `/{vehicle_id}/deliveries/{item_id}/return` | Return undelivered (truck or warehouse) | any auth | ✅ Functional |

#### Maintenance Types — Admin (3 endpoints)

| # | Method | Path | Description | Permission | Status |
|---|--------|------|-------------|------------|--------|
| 16 | `GET` | `/maintenance-types` | List all maintenance types | `view_trucks` | ✅ Functional |
| 17 | `POST` | `/maintenance-types` | Create maintenance type | `manage_fleet` | ✅ Functional |
| 18 | `PUT` | `/maintenance-types/{type_id}` | Update maintenance type | `manage_fleet` | ✅ Functional |

#### Maintenance Schedules — Per-Vehicle (2 endpoints)

| # | Method | Path | Description | Permission | Status |
|---|--------|------|-------------|------------|--------|
| 19 | `GET` | `/{vehicle_id}/maintenance/schedule` | Get vehicle's maintenance schedule | `view_trucks` | ✅ Functional |
| 20 | `POST` | `/{vehicle_id}/maintenance/schedule` | Set/update schedule for a type | `manage_fleet` | ✅ Functional |

#### Maintenance Fleet Alerts (2 endpoints)

| # | Method | Path | Description | Permission | Status |
|---|--------|------|-------------|------------|--------|
| 21 | `GET` | `/maintenance/upcoming` | Fleet-wide upcoming maintenance (N days) | `view_trucks` | ✅ Functional |
| 22 | `GET` | `/maintenance/overdue` | Fleet-wide overdue maintenance | `view_trucks` | ✅ Functional |

#### Maintenance Records — Service History (3 endpoints)

| # | Method | Path | Description | Permission | Status |
|---|--------|------|-------------|------------|--------|
| 23 | `GET` | `/{vehicle_id}/maintenance/history` | Service history (paginated, type filter) | `view_trucks` | ✅ Functional |
| 24 | `POST` | `/{vehicle_id}/maintenance/log` | Log maintenance service | `manage_fleet` | ✅ Functional |
| 25 | `GET` | `/{vehicle_id}/maintenance/costs` | Cost summary with per-type breakdown | `view_trucks` | ✅ Functional |

#### Mileage (7 endpoints)

| # | Method | Path | Description | Permission | Status |
|---|--------|------|-------------|------------|--------|
| 26 | `GET` | `/{vehicle_id}/mileage` | List mileage logs (paginated) | `view_trucks` | ✅ Functional |
| 27 | `POST` | `/{vehicle_id}/mileage` | Log daily mileage | `log_mileage` | ✅ Functional |
| 28 | `PUT` | `/{vehicle_id}/mileage/{log_id}` | Update mileage log entry | `log_mileage` | ✅ Functional |
| 29 | `GET` | `/{vehicle_id}/mileage/{log_id}/trips` | Get trip legs for a log | `view_trucks` | ✅ Functional |
| 30 | `POST` | `/{vehicle_id}/mileage/{log_id}/trips` | Add trip legs (bulk) | `log_mileage` | ✅ Functional |
| 31 | `GET` | `/mileage/estimate` | Estimate trip mileage | any auth | ✅ Functional |
| 32 | `GET` | `/mileage/summary` | Period summary (vehicle/driver filter) | `view_trucks` | ✅ Functional |

#### Reimbursements (4 endpoints)

| # | Method | Path | Description | Permission | Status |
|---|--------|------|-------------|------------|--------|
| 33 | `GET` | `/reimbursements` | List user's own reimbursements | any auth | ✅ Functional |
| 34 | `GET` | `/reimbursements/pending` | All pending (manager queue) | `approve_reimbursement` | ✅ Functional |
| 35 | `POST` | `/reimbursements` | Create reimbursement request | any auth | ✅ Functional |
| 36 | `PUT` | `/reimbursements/{id}/approve` | Approve or reject | `approve_reimbursement` | ✅ Functional |

#### Warehouse Locations (4 endpoints)

| # | Method | Path | Description | Permission | Status |
|---|--------|------|-------------|------------|--------|
| 37 | `GET` | `/warehouse-locations` | List all locations | `view_trucks` | ✅ Functional |
| 38 | `POST` | `/warehouse-locations` | Create location | `manage_fleet` | ✅ Functional |
| 39 | `PUT` | `/warehouse-locations/{id}` | Update location | `manage_fleet` | ✅ Functional |
| 40 | `DELETE` | `/warehouse-locations/{id}` | Deactivate location | `manage_fleet` | ✅ Functional |

#### Fleet Dashboard (1 endpoint)

| # | Method | Path | Description | Permission | Status |
|---|--------|------|-------------|------------|--------|
| 41 | `GET` | `/fleet/dashboard` | Fleet KPIs and summary stats | `manage_fleet` | ✅ Functional |

#### Single-Vehicle Catch-All (3 endpoints — MUST BE LAST)

| # | Method | Path | Description | Permission | Status |
|---|--------|------|-------------|------------|--------|
| 42 | `GET` | `/{vehicle_id}` | Get vehicle details | `view_trucks` | ✅ Functional |
| 43 | `PUT` | `/{vehicle_id}` | Update vehicle | `manage_fleet` | ✅ Functional |
| 44 | `DELETE` | `/{vehicle_id}` | Deactivate vehicle (soft-delete) | `manage_fleet` | ✅ Functional |

**Total endpoints: 44**

### Service: `backend/app/services/vehicle_service.py` (~525 lines)

Core vehicle lifecycle and inventory management. Dependencies:
- `VehicleRepo`, `VehicleAssignmentRepo`, `WarehouseLocationRepo`
- `StockRepo` — for stock movements when transferring parts to/from vehicles

Key business logic:
- Vehicle create: validates vehicle_number uniqueness
- Assign driver: enforces one primary assignment per vehicle
- Vehicle inventory: triggers stock movements (warehouse→truck, truck→warehouse)
- Fleet dashboard: aggregates vehicle counts, active assignments, maintenance health, mileage stats

### Service: `backend/app/services/delivery_service.py` (~287 lines)

Job-bound delivery item workflows. Dependencies:
- `VehicleDeliveryRepo`
- `StockRepo` — for stock movements on deliver/return

Key business logic:
- Assign delivery items: bulk creation for a specific job
- Mark delivered: triggers stock movement truck→job
- Return undelivered: optionally routes back to warehouse or stays on truck

### Service: `backend/app/services/maintenance_service.py` (~439 lines)

Full maintenance lifecycle. Dependencies:
- `MaintenanceTypeRepo`, `MaintenanceScheduleRepo`, `MaintenanceRecordRepo`
- `VehicleRepo` — for odometer reads

Key business logic:
- Schedule management: per-vehicle, per-type schedules with interval (miles or days)
- Next-due calculation: compares last service date/mileage + interval to current
- Alert generation: upcoming (within N days) and overdue (past due)
- Cost summary: aggregates by maintenance type within a date range

### Service: `backend/app/services/mileage_service.py` (~683 lines)

Largest fleet service. Dependencies:
- `MileageLogRepo`, `TripLegRepo`, `ReimbursementRepo`
- `VehicleAssignmentRepo` — for drive context (take-home, etc.)
- `SettingsRepo` — for mileage rate configuration

Key business logic:
- Daily mileage: one log per vehicle per day, start/end odometer
- Trip legs: breakdown of a day's driving (home→shop, shop→job, etc.)
- Mileage estimation: uses stored distances + assignment context
- Reimbursement: calculates amount from miles × rate, approval workflow
- Summary: aggregates mileage by period with vehicle/driver filtering

### Repository: `backend/app/repositories/vehicle_repo.py` (~915 lines)

**Largest repository in the codebase.** Contains 10 focused repos:

| Repo | Table | Purpose |
|------|-------|---------|
| `VehicleRepo` | `vehicles` | CRUD, detail queries with joined fields |
| `VehicleAssignmentRepo` | `vehicle_assignments` | Driver assignments, active-only queries |
| `VehicleDeliveryRepo` | `vehicle_delivery_items` | Delivery item tracking |
| `MaintenanceTypeRepo` | `maintenance_types` | Oil change, tire rotation, etc. |
| `MaintenanceScheduleRepo` | `vehicle_maintenance_schedules` | Per-vehicle intervals |
| `MaintenanceRecordRepo` | `vehicle_maintenance_records` | Service history logs |
| `MileageLogRepo` | `vehicle_mileage_logs` | Daily odometer entries |
| `TripLegRepo` | `vehicle_trip_legs` | Individual trip segments |
| `ReimbursementRepo` | `mileage_reimbursements` | Mileage reimbursement requests |
| `WarehouseLocationRepo` | `warehouse_locations` | Shop/warehouse addresses |

### Models: `backend/app/models/vehicles.py` (~604 lines)

30+ Pydantic models organized by subdomain:

**Vehicles:** `VehicleCreate`, `VehicleUpdate`, `VehicleResponse`, `VehicleListItem`
- Fields: vehicle_number, vehicle_name, vehicle_type, make, model, year, VIN, license_plate, color, status, current_odometer, insurance info, registration info, notes
- `VehicleListItem` has joined fields: `primary_driver_name`, `primary_driver_id`, `next_maintenance_due`, `overdue_maintenance_count`

**Assignments:** `VehicleAssignmentCreate`, `VehicleAssignmentUpdate`, `VehicleAssignmentResponse`
- Assignment types: `primary | authorized | temporary`
- Take-home fields: is_take_home, home_to_shop_miles, home address
- Joined: user_name, vehicle_name, vehicle_number

**Warehouse Locations:** `WarehouseLocationCreate`, `WarehouseLocationUpdate`, `WarehouseLocationResponse`
- Fields: name, address, GPS coordinates, is_primary, company_profile_id, phone, notes

**Delivery Items:** `DeliveryItemCreate`, `DeliveryItemBulkCreate`, `DeliveryItemResponse`
- Statuses: `pending | loaded | in_transit | delivered | returned`

**Maintenance Types:** `MaintenanceTypeCreate`, `MaintenanceTypeResponse`
**Maintenance Schedules:** `MaintenanceScheduleCreate`, `MaintenanceScheduleResponse`
- Interval types: miles-based or days-based
**Maintenance Records:** `MaintenanceRecordCreate`, `MaintenanceRecordResponse`
**Maintenance Alerts:** `MaintenanceAlert`

**Mileage Logs:** `MileageLogCreate`, `MileageLogUpdate`, `MileageLogResponse`
- Start/end odometer, total miles, is_personal flag
**Trip Legs:** `TripLegCreate`, `TripLegBulkCreate`, `TripLegResponse`
- Leg types: home_to_shop, shop_to_job, job_to_shop, shop_to_home, job_to_job, etc.
**Mileage Estimate:** `MileageEstimate`
**Mileage Summary:** `MileageSummary`

**Reimbursements:** `ReimbursementCreate`, `ReimbursementApproval`, `ReimbursementResponse`
- Statuses: `pending | approved | rejected | paid`

**Dashboard:** `MyVehicleDashboard`, `FleetDashboardStats`

### API Client: `frontend/src/api/vehicles.ts` (~624 lines)

| Function | Endpoint | Returns |
|----------|----------|---------|
| `getVehicles(params)` | `GET /trucks` | `PaginatedResponse<VehicleListItem>` |
| `getVehicle(id)` | `GET /trucks/:id` | `Vehicle` |
| `createVehicle(data)` | `POST /trucks` | `Vehicle` |
| `updateVehicle(id, data)` | `PUT /trucks/:id` | `Vehicle` |
| `deactivateVehicle(id)` | `DELETE /trucks/:id` | `Vehicle` |
| `getMyVehicle()` | `GET /trucks/my-vehicle` | `MyVehicleDashboard` |
| `getAssignments(vehicleId)` | `GET /trucks/:id/assignments` | `Assignment[]` |
| `assignDriver(vehicleId, data)` | `POST /trucks/:id/assign` | `Assignment` |
| `unassignDriver(vehicleId, userId)` | `DELETE /trucks/:id/assign/:userId` | `void` |
| `toggleTakeHome(vehicleId, val)` | `PUT /trucks/:id/take-home` | `Assignment` |
| `getVehicleInventory(id, search)` | `GET /trucks/:id/inventory` | `InventoryItem[]` |
| `addToInventory(id, partId, qty)` | `POST /trucks/:id/inventory/add` | `dict` |
| `removeFromInventory(id, partId, qty)` | `POST /trucks/:id/inventory/remove` | `dict` |
| `getDeliveries(id, status)` | `GET /trucks/:id/deliveries` | `DeliveryItem[]` |
| `assignDeliveryItems(id, data)` | `POST /trucks/:id/deliveries` | `DeliveryItem[]` |
| `updateDeliveryStatus(vId, iId, status)` | `PUT /trucks/:vId/deliveries/:iId/status` | `DeliveryItem` |
| `markDelivered(vId, iId, qty)` | `PUT /trucks/:vId/deliveries/:iId/deliver` | `DeliveryItem` |
| `returnUndelivered(vId, iId, to, notes)` | `PUT /trucks/:vId/deliveries/:iId/return` | `DeliveryItem` |
| `getMaintenanceTypes(activeOnly)` | `GET /trucks/maintenance-types` | `MaintenanceType[]` |
| `createMaintenanceType(data)` | `POST /trucks/maintenance-types` | `MaintenanceType` |
| `updateMaintenanceType(id, data)` | `PUT /trucks/maintenance-types/:id` | `MaintenanceType` |
| `getVehicleSchedule(id)` | `GET /trucks/:id/maintenance/schedule` | `Schedule[]` |
| `setMaintenanceSchedule(id, data)` | `POST /trucks/:id/maintenance/schedule` | `Schedule` |
| `getUpcomingMaintenance(days)` | `GET /trucks/maintenance/upcoming` | `Alert[]` |
| `getOverdueMaintenance()` | `GET /trucks/maintenance/overdue` | `Alert[]` |
| `getServiceHistory(id, params)` | `GET /trucks/:id/maintenance/history` | `Record[]` |
| `logMaintenance(id, data)` | `POST /trucks/:id/maintenance/log` | `Record` |
| `getMaintenanceCosts(id, params)` | `GET /trucks/:id/maintenance/costs` | `CostSummary` |
| `getMileageLogs(id, params)` | `GET /trucks/:id/mileage` | `MileageLog[]` |
| `logMileage(id, data)` | `POST /trucks/:id/mileage` | `MileageLog` |
| `updateMileageLog(vId, logId, data)` | `PUT /trucks/:vId/mileage/:logId` | `MileageLog` |
| `getTripLegs(vId, logId)` | `GET /trucks/:vId/mileage/:logId/trips` | `TripLeg[]` |
| `addTripLegs(vId, logId, data)` | `POST /trucks/:vId/mileage/:logId/trips` | `int[]` |
| `estimateMileage(params)` | `GET /trucks/mileage/estimate` | `MileageEstimate` |
| `getMileageSummary(params)` | `GET /trucks/mileage/summary` | `MileageSummary` |
| `getReimbursements(status)` | `GET /trucks/reimbursements` | `Reimbursement[]` |
| `getPendingReimbursements()` | `GET /trucks/reimbursements/pending` | `Reimbursement[]` |
| `createReimbursement(data)` | `POST /trucks/reimbursements` | `Reimbursement` |
| `approveReimbursement(id, data)` | `PUT /trucks/reimbursements/:id/approve` | `Reimbursement` |
| `getWarehouseLocations()` | `GET /trucks/warehouse-locations` | `Location[]` |
| `createWarehouseLocation(data)` | `POST /trucks/warehouse-locations` | `Location` |
| `updateWarehouseLocation(id, data)` | `PUT /trucks/warehouse-locations/:id` | `Location` |
| `deactivateWarehouseLocation(id)` | `DELETE /trucks/warehouse-locations/:id` | `void` |
| `getFleetDashboard()` | `GET /trucks/fleet/dashboard` | `FleetDashboardStats` |

---

## 2. Frontend Inventory

### Directory: `frontend/src/features/trucks/`

#### Pages

| File | Lines | Type | Status |
|------|-------|------|--------|
| `pages/FleetDashboardPage.tsx` | ~313 | Manager fleet KPIs | ✅ Functional |
| `pages/AllTrucksPage.tsx` | ~197 | Vehicle list with status | ✅ Functional |
| `pages/VehicleDetailPage.tsx` | ~1,092 | Full detail with all tabs | ✅ Functional |
| `pages/MyTruckPage.tsx` | ~317 | Personal vehicle dashboard | ✅ Functional |
| `pages/MileagePage.tsx` | ~661 | Mileage log management | ✅ Functional |
| `pages/MaintenancePage.tsx` | ~657 | Maintenance management | ✅ Functional |
| `pages/ToolsPage.tsx` | ~664 | Tool assignments on vehicles | ✅ Functional |

#### Components

| File | Lines | Type | Status |
|------|-------|------|--------|
| `components/VehicleCard.tsx` | ~111 | Compact vehicle card for lists | ✅ Functional |
| `components/VehicleStatusBadge.tsx` | ~47 | Status badge (active/maintenance/inactive) | ✅ Functional |
| `components/CreateVehicleModal.tsx` | ~230 | Full create vehicle form | ✅ Functional |
| `components/AssignDriverModal.tsx` | ~179 | Driver assignment form | ✅ Functional |

**Total: 7 pages + 4 components, ~4,468 lines**

### Navigation Config (`frontend/src/lib/navigation.ts`)

```typescript
{
  id: 'trucks',
  label: 'Trucks',
  icon: 'Truck',
  path: '/trucks',
  permission: 'view_trucks',
  tabs: [
    { id: 'my-vehicle', label: 'My Vehicle', path: '/trucks/my-vehicle' },
    { id: 'all', label: 'All Vehicles', path: '/trucks/all' },
    { id: 'tools', label: 'Tools', path: '/trucks/tools' },
    { id: 'maintenance', label: 'Maintenance', path: '/trucks/maintenance' },
    { id: 'mileage', label: 'Mileage', path: '/trucks/mileage' },
    { id: 'fleet', label: 'Fleet', path: '/trucks/fleet', permission: 'manage_fleet' },
  ],
}
```

6 tabs, gated by `view_trucks` at the module level. Fleet Dashboard tab additionally requires `manage_fleet`.

### Page Details

**FleetDashboardPage** (~313 lines):
- Manager-level fleet KPI dashboard
- Cards: Total Vehicles (active/inactive/maintenance), Active Assignments, Upcoming Maintenance, Overdue Maintenance, Mileage This Month, Pending Reimbursements
- Requires `manage_fleet` permission — not visible to regular users
- Uses `getFleetDashboard()` API call

**AllTrucksPage** (~197 lines):
- Simple vehicle list with VehicleCard components
- Shows vehicle_number, name, type, status badge, primary driver
- "Create Vehicle" button → CreateVehicleModal
- Click row → VehicleDetailPage

**VehicleDetailPage** (~1,092 lines):
- **Largest frontend page in the fleet module**
- Header: Vehicle info (number, name, type, make/model/year, VIN, plate, status)
- Tabbed sections:
  - **Info**: Vehicle details with edit form, insurance/registration fields
  - **Assignments**: Current driver assignments, assign/unassign/take-home controls
  - **Inventory**: Parts loaded on vehicle, add/remove with part search
  - **Deliveries**: Active delivery items with status workflows
  - **Maintenance**: Schedule + service history for this vehicle
  - **Mileage**: Mileage logs + trip legs for this vehicle

**MyTruckPage** (~317 lines):
- Personal dashboard for the current user's assigned vehicle
- Shows vehicle info, quick actions (log mileage, check deliveries)
- "No vehicle assigned" message if no active assignment
- Uses `getMyVehicle()` API call

**MileagePage** (~661 lines):
- Mileage log list with date range filter
- Add/edit mileage log modals (start/end odometer)
- Trip leg detail view per log entry
- Mileage summary section with period stats
- Reimbursement section (create request, view status)

**MaintenancePage** (~657 lines):
- Fleet-wide maintenance view (not per-vehicle)
- Upcoming maintenance alerts with days/miles remaining
- Overdue maintenance alerts highlighted
- Maintenance type management (create/edit)
- Log maintenance service records

**ToolsPage** (~664 lines):
- Vehicle tool/equipment assignments
- Integrates with the Tools & Kits module (Phase 9)
- Tool checkout/return tracked per vehicle

### Component Details

**VehicleCard** (~111 lines): Compact card for list views — shows vehicle number, name, status badge, primary driver name.

**VehicleStatusBadge** (~47 lines): Color-coded badge — green for active, amber for maintenance, gray for inactive.

**CreateVehicleModal** (~230 lines): Full vehicle creation form — vehicle_number, name, type dropdown, make/model/year, VIN, license plate, color, notes.

**AssignDriverModal** (~179 lines): Employee selector + assignment type (primary/authorized/temporary) + take-home toggle + home address fields.

---

## 3. Feature Completeness

### Vehicle Management

| Feature | Status | Notes |
|---------|--------|-------|
| Vehicle list with status badges | ✅ Complete | Paginated, status-filtered |
| Vehicle CRUD (create/read/update/deactivate) | ✅ Complete | Soft-delete pattern |
| Vehicle detail with all fields | ✅ Complete | Insurance, registration, VIN, plate, etc. |
| My Vehicle personal dashboard | ✅ Complete | Shows assigned vehicle + quick actions |

### Driver Assignments

| Feature | Status | Notes |
|---------|--------|-------|
| Assign/unassign drivers | ✅ Complete | Primary, authorized, temporary types |
| Take-home vehicle toggle | ✅ Complete | Any auth user for their own assignment |
| Home address tracking | ✅ Complete | For take-home mileage calculation |
| One primary driver enforcement | ✅ Complete | Service-level validation |

### Vehicle Inventory

| Feature | Status | Notes |
|---------|--------|-------|
| View parts on vehicle | ✅ Complete | Search supported |
| Add parts (warehouse→truck) | ✅ Complete | Triggers stock movement |
| Remove parts (truck→warehouse) | ✅ Complete | Triggers stock movement |

### Delivery Items

| Feature | Status | Notes |
|---------|--------|-------|
| Assign delivery items to vehicle | ✅ Complete | Bulk assignment per job |
| Delivery status tracking | ✅ Complete | pending → loaded → in_transit → delivered |
| Mark delivered (truck→job) | ✅ Complete | Triggers stock movement |
| Return undelivered | ✅ Complete | Return to truck or warehouse |

### Maintenance

| Feature | Status | Notes |
|---------|--------|-------|
| Maintenance type management | ✅ Complete | Admin CRUD (oil change, tires, etc.) |
| Per-vehicle schedules | ✅ Complete | Miles-based or days-based intervals |
| Service logging | ✅ Complete | Date, mileage, cost, notes, performed_by |
| Fleet-wide upcoming alerts | ✅ Complete | Configurable days-ahead |
| Fleet-wide overdue alerts | ✅ Complete | Past-due based on schedule |
| Service history | ✅ Complete | Paginated, type-filtered |
| Cost summary per vehicle | ✅ Complete | Per-type breakdown with date range |

### Mileage

| Feature | Status | Notes |
|---------|--------|-------|
| Daily mileage logging | ✅ Complete | Start/end odometer |
| Trip leg breakdown | ✅ Complete | Leg types with from/to labels |
| Mileage estimation | ✅ Complete | Uses stored distances + context |
| Period summary | ✅ Complete | Vehicle/driver filtering |
| Reimbursement requests | ✅ Complete | Create, view status |
| Reimbursement approval | ✅ Complete | Manager queue with approve/reject |

### Fleet Dashboard & Warehouse

| Feature | Status | Notes |
|---------|--------|-------|
| Fleet KPI dashboard | ✅ Complete | Manager-only |
| Warehouse location CRUD | ✅ Complete | Address, GPS, primary flag |
| Responsive layout | ✅ Complete | All pages use responsive Tailwind |

**Overall: 100% functional — no stubs, no placeholders**

---

## 4. Cross-References

### Backend Dependencies

| Fleet Feature | External Service/Repo | Table(s) |
|---------------|----------------------|-----------|
| Vehicle inventory | `StockRepo` (warehouse module) | `stock`, `stock_movements` |
| Delivery items | `StockRepo` | `stock`, `stock_movements` |
| Mileage rate | `SettingsRepo` (settings module) | `app_settings` |
| Fast Drive | `MileageService` (from dashboard router) | `vehicle_mileage_logs`, `vehicle_trip_legs` |
| Assignment lookup | `VehicleAssignmentRepo` | `vehicle_assignments`, `users` |

### Consumers of Fleet Data

| External Module | How It Uses Fleet |
|-----------------|-------------------|
| **Dashboard** | Fast Drive widget calls `MileageService` to log trips + reads vehicle assignments |
| **Dashboard** | `GET /trucks/my-vehicle` data used for Fast Drive context |
| **Warehouse** | Stock movements reference vehicle locations |
| **Tools & Kits** | ToolsPage integrates with vehicle tool assignments |

### Frontend Dependencies

| Fleet Feature | API Client | Shared Components |
|---------------|------------|-------------------|
| Vehicle list | `api/vehicles.ts` | `Card`, `Badge`, `Spinner`, `VehicleCard`, `VehicleStatusBadge` |
| Vehicle detail | `api/vehicles.ts` | `Card`, `Tabs`, `Badge`, `Button`, `Dialog` |
| Maintenance | `api/vehicles.ts` | `Card`, `Badge`, `Button`, `Dialog`, `Input` |
| Mileage | `api/vehicles.ts` | `Card`, `Badge`, `Button`, `Dialog`, `Input` |
| Fleet dashboard | `api/vehicles.ts` | `Card`, `Badge` |

### Navigation Cross-references

- Dashboard Fast Drive uses vehicle assignment data from `/trucks/my-vehicle`
- Tools module pages exist under `/trucks/tools` (co-located in trucks nav)
- Warehouse location management lives under trucks (`/trucks/warehouse-locations` API) though it serves the warehouse module conceptually

---

## 5. Issues & TODOs

### No TODO/FIXME Comments Found

Zero TODO, FIXME, HACK, or TEMP comments in any fleet file (backend or frontend).

### Architectural Notes

1. **Monolithic repository** — `vehicle_repo.py` at 915 lines is the largest repo in the codebase. It contains 10 separate repo classes. Consider splitting into separate files (e.g., `mileage_repo.py`, `maintenance_repo.py`) for maintainability.
Do this we want to be able to hadel larg fleeats 100+ vehicles and 1000+ mileage logs and 1000+ maintenance records. We want to be able to scale the codebase to handle this volume without hitting maintainability issues. The current monolithic repo is already at 915 lines, which is quite large. By splitting into separate repos, we can keep each file focused and easier to navigate. For example, `mileage_repo.py` would contain all mileage-related database interactions, while `maintenance_repo.py` would handle maintenance records and schedules. This separation would make it easier for developers to find and work with the relevant code when making changes or debugging issues related to specific features.

2. **Monolithic router** — `trucks.py` at 974 lines is the largest router. The route-ordering constraint (catch-all `/{vehicle_id}` must be last) adds fragility. Any new endpoint must be placed before the catch-all section. Consider splitting into sub-routers (e.g., `trucks_maintenance.py`, `trucks_mileage.py`).
The `trucks.py` router currently handles all 44 endpoints, which makes it quite large and potentially difficult to maintain. The catch-all routes for vehicle details at the bottom create a risk of route collisions if new endpoints are added above them. By splitting the router into sub-routers based on feature areas (e.g., `trucks_maintenance.py` for maintenance-related endpoints, `trucks_mileage.py` for mileage-related endpoints), we can reduce the size of each router and eliminate the risk of route collisions. Each sub-router would be mounted in `main.py` with its own prefix (e.g., `/api/trucks/maintenance`, `/api/trucks/mileage`), allowing for better organization and maintainability. Do this to improve code organization and reduce the risk of route collisions. With 44 endpoints, the router is already quite large, and as we add more features in the future, it could become unwieldy. By splitting into sub-routers, we can keep each file focused on a specific area of functionality, making it easier for developers to find and work with the relevant code when making changes or adding new features.

3. **Four services for one router** — The trucks router instantiates `VehicleService`, `DeliveryService`, `MaintenanceService`, and `MileageService` depending on the endpoint group. This is good separation but there's no shared initialization — each endpoint creates its own service instance.
Consider a service factory or dependency injection to manage this more cleanly. For example, we could have a `FleetServiceFactory` that initializes and provides instances of each service

4. **Warehouse locations under trucks** — `WarehouseLocationRepo` and the `/warehouse-locations` endpoints live in the fleet module, but warehouse locations are conceptually part of the warehouse/inventory system. This creates a cross-cutting concern where the warehouse module depends on fleet data.
Consider moving warehouse location management to the warehouse module, or at least abstracting it behind a service interface that both modules can use. This would reduce coupling between the fleet and warehouse modules and better align with the conceptual domain boundaries. The fleet module should focus on vehicles and their management, while the warehouse module should handle inventory and location management. By moving warehouse location management to the warehouse module, we can keep the responsibilities of each module clear and reduce the risk of unintended side effects when making changes to one module that affect the other.

5. **Mileage rate from settings** — `MileageService` reads the reimbursement rate from `SettingsRepo`/`app_settings`. If the rate changes, historical reimbursements are unaffected (amount is stored at creation), which is correct behavior.
However, there's no audit trail for rate changes. Consider adding a `MileageRateChangeLog` table to track when and how the rate changes over time for better transparency and historical analysis. This would allow us to see when the mileage reimbursement rate was changed, what the previous and new rates were, and who made the change. This audit trail would be valuable for understanding trends in reimbursement costs and for accountability in case of disputes or questions about past reimbursements.

**Gas Receipt Fast-Capture for Reimbursements:** Add a quick-capture photo flow when submitting a mileage reimbursement request. The user snaps a photo of their gas receipt, which is stored in the database and linked to the reimbursement record. Managers can then review the expense alongside supporting documentation during approval. Make an attached receipt image **mandatory** for all reimbursement submissions.

6. **No vehicle image/photo** — Vehicle records have no image field. VehicleCard shows a truck icon placeholder.
Add an optional `image_url` field to the `vehicles` table and expose it in the API. The VehicleCard and VehicleDetailPage should display the uploaded photo when available, falling back to the truck icon placeholder.

7. **Route collision risk** — The `/{vehicle_id}` catch-all at the bottom means any future top-level path (e.g., `/fuel-logs`) must be added above it. A code comment warns about this, but it's an ongoing maintenance concern.

**Fuel Logging Enhancements:** Track fuel purchases per vehicle. When logging a fuel record, require the user to input the vehicle's current odometer reading — this serves as a soft mileage checkpoint that's more accurate than calculated estimates. If the recorded odometer reading exceeds the expected mileage (based on logged trips), surface an informational note in the log highlighting the discrepancy. Additionally, use the most recent manually-input mileage reading as a soft reset baseline for maintenance schedule calculations — the automated mileage tracking provides guidance, but the manual odometer input provides ground-truth accuracy.

### Feature Gaps

Add all of the gaps 

- **No vehicle photo/image upload** — Just metadata, no visual identification.
- **No fuel tracking** — Mileage is tracked but fuel consumption/cost is not. Combined with maintenance costs, this would give a true total cost of ownership.
- **No GPS/telematics integration** — No real-time vehicle location tracking.
- **No vehicle inspection checklist** — Pre-trip/post-trip inspection forms are not implemented.
- **No fleet utilization reports** — Vehicle utilization (days used vs. idle) is not tracked or reported.
- **No maintenance vendor tracking** — Service records don't track which shop/vendor performed the work.
- **No insurance/registration expiry alerts** — Unlike cert alerts for employees, there are no proactive alerts for vehicle insurance or registration expiring.
- **No vehicle transfer between shops** — In a multi-location setup, there's no workflow for transferring a vehicle between warehouse locations.
