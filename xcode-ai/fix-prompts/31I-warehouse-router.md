# 31I — Warehouse Router: Fix Unknown Route Handling

> **Plan:** `docs/plans/ios-warehouse-pages.md`

## Instructions

Read the file, fix, wait for confirmation.

## Context

The warehouse router shows plain `Text("Unknown...")` for unrecognized tab IDs. Should use ErrorStateView for consistency. Also verify all 10 warehouse sub-pages are routed correctly.

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/WarehouseRouter.swift` (47 lines)

## Task

1. **Replace plain Text fallback** with ErrorStateView:
   ```swift
   default:
       ErrorStateView(message: "Unknown warehouse page: \(tabId)") { }
   ```

2. **Verify all routes exist** — ensure these tab IDs all route correctly:
   - `dashboard` → WarehouseDashboardPage
   - `movements` → WarehouseMovementsPage
   - `locations` → WarehouseLocationsPage
   - `staging` → IOSStagingPage
   - `receiving` → IOSReceivingPage
   - `returns` → IOSWarehouseReturnsPage
   - `audit` → IOSAuditPage
   - `inventory` → IOSInventoryGridPage
   - `tools` → IOSWarehouseToolsPage
   - `network` → IOSWarehouseNetworkPage
   - `settings` → IOSWarehouseSettingsPage

3. **Add missing routes** if any of the above aren't handled

## Success Criteria

- [ ] Unknown routes show ErrorStateView
- [ ] All 11 sub-pages routed correctly
- [ ] Project builds with no errors

**Warehouse prompt chain complete.**
