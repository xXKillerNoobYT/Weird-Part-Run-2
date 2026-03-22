# iOS Warehouse Pages Design

> **Files:** 15 files in `Features/Warehouse/`
> **Nav:** Warehouse → (Dashboard, Movements, Locations, Staging, Receiving, Audit, Inventory, Tools, Returns, Network, Settings)
> **Status:** Review complete, design decisions captured (2026-03-22)

## Design Decisions (Confirmed)

### Dashboard → Smart Cards (Program Standard)
Cards for: Movements Today, Receiving Active, Audit Due, Staging Ready. Tap to filter, tap again for All.

### Inventory Grid Page — NOT redundant
This is a **parts-by-type grouped view** for quick stock lookup at a specific location. Shows stock levels grouped by part type. Default location = last one visited (if multiple locations exist).

NOT the same as Locations page.

### Locations Page — Physical Floor Plan (Future Design)
This is a **top-down floor layout** of the warehouse with:
- Storage units: shelves, gang boxes, pipe racks, staging area, returns area
- Storage level % per unit
- Click into a unit → see shelves, areas, bins
- Bins hold ONE part only. Areas hold bins and/or parts.
- Bins are movable between locations
- Parts linked to areas or bins with numbering system
- Per-shop-location floor plans

**NOTE:** This needs detailed design when we get to it. Not covered in current prompts.

### Network Page — Keep, Remove Dummy Data
Keep the page as a placeholder but remove the fake data and "Phase 16" text. Will be one of the last things implemented.

### Warehouse Tools — Stays Separate
Warehouse-specific view of tools in the warehouse. Not a redirect to the Tools section.

### Warehouse Returns vs Orders Returns — Needs Comparison
User needs to see both pages' functionality compared before deciding if they merge or stay separate. **TODO: Present comparison when we do the detailed Returns design.**

### Audit ↔ Forecasting Integration — Yes
Audit should tie into the forecasting system's certainty ratings. When certainty drops below 80%, auto-add parts to the audit queue. **Detailed design needed when we get to the audit flow.**

## Issues Found (All Pages)

### Critical (3 pages with `import GRDB`)
1. WarehouseDashboardPage — raw SQL in UI
2. WarehouseMovementsPage — raw SQL in UI
3. WarehouseLocationsPage — raw SQL in UI

### High (display-only / non-functional)
4. IOSReceivingPage — can't start or continue receiving session
5. IOSAuditSetupView — startAudit() is a stub (dismisses without creating session)
6. IOSAuditSummaryView — no Finalize/Adjust actions
7. IOSStagingPage — no confirmation on swipe-to-clear (destructive)
8. IOSWarehouseReturnsPage — display-only, no approve/ship/complete
9. IOSWarehouseToolsPage — display-only, no checkout/return/maintenance
10. IOSInventoryGridPage — hardcoded to location ID 1

### Medium
11. IOSWarehouseNetworkPage — non-functional placeholder with fake data
12. All pages — platform guards (#if os(iOS))
13. IOSWarehouseSettingsPage — string-based settings, no type safety, print() errors
14. WarehouseDashboardPage — both quick action buttons navigate to same place

## Prompt Chain

| Prompt | What | Status |
|--------|------|--------|
| 31A | Dashboard: remove GRDB, smart cards, fix quick actions, platform guard | Queued |
| 31B | Movements: remove GRDB, ActiveSheet pattern, platform guard | Queued |
| 31C | Locations: remove GRDB, platform guard, add action buttons to detail sheet | Queued |
| 31D | Staging: add swipe confirmation, batch clear, platform guard | Queued |
| 31E | Receiving: add start/continue session actions, platform guard | Queued |
| 31F | Audit: fix setup stub, add finalize/adjust actions, platform guard, certainty tie-in | Queued |
| 31G | Inventory Grid: remove hardcoded location, group by type, location picker | Queued |
| 31H | Returns + Tools + Network + Settings: display→actionable, platform guards, cleanup | Queued |
| 31I | Router update: fix unknown route handling | Queued |
