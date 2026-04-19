# iOS Fleet Pages — Design Plan

## Navigation
Fleet: My Vehicle, Vehicles, Trailers, Usage Log (combined fuel+mileage), Inspections, Maintenance, Tracking, Management

## Key Design Decisions

### My Vehicle = Primary Worker View
- Opens first when field workers tap Fleet
- Shows their assigned vehicle as mobile workspace
- Smart cards: Tools On Board, Parts On Board, Tank, Maintenance Due

### Two Types of Truck Inventory
1. **Truck Stock** (permanent): Parts kept on truck for field use. Has MIN/TARGET/MAX. Common vs Critical. Managed by assigned driver. Gets restocked from shop.
2. **Transfer Area** (temporary): General storage for boxes/parts in transit TO a job or RETURNING from a job. Not inventory — it's logistics. Shows as movement records with source/destination.

### Trailers = Mini Warehouses
- Have shelves, drawers, storage units (tracked in warehouse location system)
- Own MIN/TARGET/MAX per part
- First source = main warehouse (linked for management)
- AT SHOP: ignore MIN/MAX, use target value (tight restocking)
- NOT AT SHOP: use full MIN/MAX (bigger buffers)
- Own floor plan section in Locations page
- Own transfer area for parts being moved to/from

### Vehicle Detail — 7 Tabs
Overview, Parts, Tools, Assignments, Maintenance, Usage, Inspections

### Pre-Trip Inspections
- Residential-sized checklist (simpler than DOT commercial)
- Customizable per vehicle type and trailer type
- Ties into clock-in: "Complete pre-trip before clocking in?"
- Sections: Exterior, Interior, Equipment, Notes
- Result: Pass / Fail / Conditional

### Fleet Dashboard KPIs
Smart cards: Vehicles, Active, Maintenance Due, Overdue Inspect, Trailers, Fuel This Month, Miles This Month, Maintenance Cost
Plus: vehicle status list, cost summary (hat-gated), upcoming maintenance

### Fleet Reports → Reports Section (not Fleet)
Total fuel cost by vehicle, maintenance cost trends, vehicle utilization, cost per mile

### Code Quality
Fleet is the CLEANEST section — zero GRDB imports, zero raw SQL, zero platform guards, zero empty catches. All 17 files use service layer properly. Work here is design enhancement only.

---

## Current State (as of 2026-04-19 — AUTO GO C1 audit)

### iOS Files (18)
| File | Purpose |
|---|---|
| `IOSFleetDashboardPage.swift` | Fleet dashboard KPIs: vehicles, active, maintenance due, overdue inspections, trailers, fuel/miles/cost |
| `IOSMyTruckPage.swift` | My Vehicle: assigned vehicle workspace with smart cards (tools on board, parts, tank, maintenance) |
| `IOSTruckToolsPage.swift` | Tools currently on the truck |
| `IOSVehiclesPage.swift` | All vehicles list with status filter |
| `IOSVehicleDetailPage.swift` | 7-tab vehicle detail: Overview, Parts, Tools, Assignments, Maintenance, Usage, Inspections |
| `IOSTrailersPage.swift` | Trailers list |
| `IOSTrailerDetailPage.swift` | Trailer detail: stock, storage units |
| `IOSTrailerLocationsPage.swift` | Trailer location history |
| `IOSFuelPage.swift` | Fuel log entries |
| `IOSMileagePage.swift` | Mileage/usage log |
| `IOSInspectionsPage.swift` | Inspection records list |
| `IOSMaintenancePage.swift` | Maintenance records list |
| `IOSTelematicsPage.swift` | GPS/telematics tracking view |
| `PreTripInspectionView.swift` | Pre-trip inspection checklist flow |
| `IOSCreateVehicleSheet.swift` | Add vehicle sheet |
| `IOSCreateTrailerSheet.swift` | Add trailer sheet |
| `IOSAssignDriverSheet.swift` | Assign driver to vehicle sheet |
| `FleetRouter.swift` | NavigationStack routing |

### FleetService API Surface (33 public methods)

| Section | Methods |
|---|---|
| 1. Vehicles | `listVehicles(status:)`, `getVehicleDetail(id:)` |
| 2. Maintenance Records | `listMaintenanceRecords(vehicleId:limit:)` |
| 3. Mileage Logs | `listMileageLogs(vehicleId:userId:limit:)` |
| 4. Fuel Logs | `listFuelLogs(vehicleId:limit:)` |
| 5. Trailers | `listTrailers(status:)` |
| 6. Fleet Stats | `getFleetStats()` |
| 6b. Fleet Dashboard | `getFleetDashboardStats()`, `getVehicleStatusList()`, `getUpcomingFleetMaintenance(limit:)` |
| 7. Inspections | `listInspections(limit:)` |
| 8. Telematics | `listTelematicsData()` |
| 9. Create/Mutate | `createVehicle(...)`, `createTrailer(...)`, `assignDriver(...)` |
| 10. My Vehicle | `getMyVehicleStats(userId:)` |
| 11. Vehicle Stock | `getVehicleStock(vehicleId:stockType:)` |
| 12. Vehicle Tools | `getVehicleTools(vehicleId:)` |
| 13. Stock Mutations | `addVehicleStockItem(...)`, `logFuelLevel(...)` |
| 14. Trailer Detail | `getTrailerDetail(trailerId:)` |
| 15. Trailer Stock | `getTrailerStock(trailerId:)` |
| 16. Trailer Storage | `getTrailerStorageUnits(trailerId:)` |
| 17. Trailer Location | `getTrailerLocationHistory(...)`, `updateTrailerLocation(...)` |
| 18. Pre-Trip Inspection | `getInspectionChecklist(...)`, `saveInspection(...)`, `checkInspectionRequired(...)`, `getInspectionRecords(...)` |
| 19. Reports | `getFuelCostReport(...)`, `getMaintenanceTrendsReport(...)`, `getMileageSummaryReport(...)`, `getVehicleUtilizationReport(...)` |

### Database Foundation
- Migration `006_fleet_tools_scheduling` — vehicles + vehicle_assignments + tools core tables
- Migration `013_tools_supplier_extras` — additional vehicle/fleet extras
- Additional migrations for inspection templates, telematics, trailer stock

### Implementation Status
Phase 6 (Fleet & Vehicle Management) is complete per CLAUDE.md. All 18 iOS files are present and FleetService has 33 public methods across 19 feature sections. Pre-trip inspection checklist, trailer mini-warehouse, telematics/GPS tracking, and fleet reports are all implemented.
