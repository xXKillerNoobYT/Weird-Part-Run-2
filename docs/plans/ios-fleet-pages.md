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
