# AI Page Context Coverage Inventory

Issue: WEI-1112 / WEI-1194 / GitHub #86 T1-19
Updated: 2026-05-13

## Success Condition

Complete the 87-page page-context coverage set by adding read-only page-active/page-inactive notifications, wiring the AI panel to consume those notifications, and mapping page-active notifications to `HelpContentRegistry` page IDs where help content exists.

## Current Coverage

Implemented page-context notifications observed by `IOSAIAssistantPanel`: 24 page contexts.

Help registry mappings with matching help entries: 23 page contexts.

Known gap: `settingsPageActive` is observed by the AI panel and active-page tracker, but `HelpContentRegistry` does not yet contain a `settings-app-config` entry. That should be handled in the settings slice rather than mapped to a missing help entry.

## Covered Pages

| Area | Page | Notification | Help page ID |
| --- | --- | --- | --- |
| Parts | Parts Catalog | `catalogPageActive` | `parts-catalog` |
| Parts | Parts Pricing | `pricingPageActive` | `parts-pricing` |
| Parts | Parts Suppliers | `suppliersPageActive` | `parts-suppliers` |
| Parts | Parts Companions | `companionsPageActive` | `parts-companions` |
| Parts | Parts Forecasting | `forecastingPageActive` | `parts-forecasting` |
| Dashboard | Dashboard Home | `dashboardPageActive` | `dashboard-home` |
| Jobs | Jobs List | `jobsListPageActive` | `jobs-list` |
| Jobs | Clock In/Out | `clockPageActive` | `dashboard-clock` |
| Orders | JPOs | `jposPageActive` | `orders-jpos` |
| Orders | Purchase Orders | `purchaseOrdersPageActive` | `orders-pos` |
| Orders | JPO Creation | `jpoCreationPageActive` | `orders-jpo-create` |
| Orders | JPO Detail | `jpoDetailPageActive` | `orders-jpo-detail` |
| Orders | Order Staging | `orderStagingPageActive` | `orders-staging` |
| Orders | Parts Order Management | `partsOrderManagementPageActive` | `orders-parts` |
| Orders | Wishlist | `ordersWishlistPageActive` | `orders-wishlist` |
| Orders | Unified Order (retired) | `unifiedOrderPageActive` | `orders-unified` |
| Warehouse | Inventory Grid | `inventoryGridPageActive` | `warehouse-inventory` |
| Scheduling | Dispatch | `dispatchPageActive` | `scheduling-dispatch` |
| Scheduling | Schedule Calendar | `scheduleCalendarPageActive` | `scheduling-calendar` |
| People | Employees | `employeesPageActive` | `people-employees` |
| Fleet | Vehicles | `vehiclesPageActive` | `fleet-vehicles` |
| Tools | Tool Registry | `toolRegistryPageActive` | `tools-registry` |
| Notebooks | Notebooks List | `notebooksListPageActive` | `notebooks-all` |
| Settings | Settings/App Config observer only | `settingsPageActive` | missing help entry |

## WEI-1194 Slice

Added the next orders page-context slice:

- `IOSJPOCreationPage`: selected job, priority, delivery preference, cart count/quantity, search state.
- `IOSJPODetailPage`: job, JPO status, priority, delivery state, line count, line status counts.
- `IOSOrderStagingPage`: selected job, stages, loaded/filtered part counts, held future-stage count.
- `IOSPartsOrderManagementPage`: selected supplier, supplier count, loaded/filtered/selected row counts, active filters.
- `IOSWishlistPage`: section counts, filtered visible count, search state.
- `IOSUnifiedOrderPage`: explicit retired/replaced context pointing users to JPO creation.

All new payloads are read-only summaries. They report visible data, selected filters, lifecycle state, and replacement guidance only. They do not expose mutating commands, action IDs, or write intents.

## Next Highest-Traffic Remaining Slices

1. Restore/complete prior orders/warehouse slice if absent in the shared branch: PO Detail, Receive Shipment, Procurement, Returns, Warehouse Dashboard, Warehouse Locations.
2. Warehouse completion: Movements, Receiving, Staging, Audit, Returns, Warehouse Tools, Network, Settings, Organization Audit, Leaderboard.
3. Jobs completion: Job Detail, Labor, Daily Reports, Questionnaire, Estimation Questionnaire, Estimation Review, Job Reports.
4. People/Office/Reports: Contacts, customers, contractors, teams, office dashboard, approvals, spending, warehouse exec, all report pages.
5. Settings: add missing help entries and page context for the high-use settings pages before mapping them to help content.

## Validation

Validated in the shared workspace on 2026-05-13:

- New WEI-1194 notification names are declared, posted by their pages, observed by `IOSAIAssistantPanel`, tracked for active help page selection, and mapped in `HelpContentRegistry`.
- Help registry mapping check returned no missing mapped page IDs.
- `xcodebuild -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` passed. Remaining output was warnings only.

Static validation:

```bash
rg -n "PageActive|PageInactive|post\\(name: \\." "Weird Parts IOS/Weird Parts IOS" -g "*.swift"
ruby -ne 'puts $1 if /pageId: "([^"]+)"/' "Weird Parts IOS/Weird Parts IOS/Shared/HelpContentRegistry.swift" | sort > /tmp/helpids.txt
ruby -ne 'puts $1 if /"WiredPart\\.[^"]+": "([^"]+)"/' "Weird Parts IOS/Weird Parts IOS/Shared/HelpContentRegistry.swift" | sort | uniq > /tmp/mapids.txt
comm -13 /tmp/helpids.txt /tmp/mapids.txt
```

Build validation:

```bash
xcodebuild -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
