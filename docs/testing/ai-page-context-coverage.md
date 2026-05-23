# AI Page Context Coverage Inventory

Issue: WEI-1112 / WEI-1194 / GitHub #86 T1-19
Updated: 2026-05-17

## Success Condition

Complete the 87-page page-context coverage set by adding read-only page-active/page-inactive notifications, wiring the AI panel to consume those notifications, and mapping page-active notifications to `HelpContentRegistry` page IDs where help content exists.

## Current Coverage

Implemented page-context notifications observed by `IOSAIAssistantPanel`: 57 page contexts.

Help registry mappings with matching help entries: 49 page contexts. Fleet tab contexts are observed by the AI panel; dedicated help-entry extraction remains for Fleet tabs beyond Dashboard and Maintenance.

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
| Jobs | Job Detail | `jobDetailPageActive` | `jobs-detail` |
| Jobs | Labor | `laborPageActive` | `jobs-labor` |
| Jobs | Daily Reports | `dailyReportsPageActive` | `jobs-daily-reports` |
| Jobs | Clock-Out Questionnaire | `questionnairePageActive` | `jobs-questionnaire` |
| Jobs | Estimation Questionnaire | `estimationQuestionnairePageActive` | `jobs-estimation-questionnaire` |
| Jobs | Estimation Review | `estimationReviewPageActive` | `jobs-estimation-review` |
| Jobs | Job Reports | `jobReportsPageActive` | `jobs-reports` |
| Orders | JPOs | `jposPageActive` | `orders-jpos` |
| Orders | Purchase Orders | `purchaseOrdersPageActive` | `orders-pos` |
| Orders | PO Detail | `poDetailPageActive` | `orders-po-detail` |
| Orders | Receive Shipment | `receiveShipmentPageActive` | `orders-receiving` |
| Orders | Procurement | `procurementPageActive` | `orders-procurement` |
| Orders | Returns | `returnsPageActive` | `orders-returns` |
| Orders | JPO Creation | `jpoCreationPageActive` | `orders-jpo-create` |
| Orders | JPO Detail | `jpoDetailPageActive` | `orders-jpo-detail` |
| Orders | Order Staging | `orderStagingPageActive` | `orders-staging` |
| Orders | Parts Order Management | `partsOrderManagementPageActive` | `orders-parts` |
| Orders | Wishlist | `ordersWishlistPageActive` | `orders-wishlist` |
| Orders | Unified Order (retired) | `unifiedOrderPageActive` | `orders-unified` |
| Warehouse | Warehouse Dashboard | `warehouseDashboardPageActive` | `warehouse-dashboard` |
| Warehouse | Inventory Grid | `inventoryGridPageActive` | `warehouse-inventory` |
| Warehouse | Warehouse Locations | `warehouseLocationsPageActive` | `warehouse-locations` |
| Warehouse | Warehouse Movements | `warehouseMovementsPageActive` | `warehouse-movements` |
| Warehouse | Warehouse Receiving | `warehouseReceivingPageActive` | `warehouse-receiving` |
| Warehouse | Warehouse Staging | `warehouseStagingPageActive` | `warehouse-staging` |
| Warehouse | Warehouse Audit | `warehouseAuditPageActive` | `warehouse-audit` |
| Warehouse | Warehouse Returns | `warehouseReturnsPageActive` | `warehouse-returns` |
| Warehouse | Warehouse Tools | `warehouseToolsPageActive` | `warehouse-tools` |
| Warehouse | Warehouse Network | `warehouseNetworkPageActive` | `warehouse-network` |
| Warehouse | Warehouse Settings | `warehouseSettingsPageActive` | `warehouse-settings` |
| Warehouse | Organization Audit | `warehouseOrganizationAuditPageActive` | `warehouse-organization` |
| Warehouse | Warehouse Leaderboard | `warehouseLeaderboardPageActive` | `warehouse-leaderboard` |
| Scheduling | Dispatch | `dispatchPageActive` | `scheduling-dispatch` |
| Scheduling | Schedule Calendar | `scheduleCalendarPageActive` | `scheduling-calendar` |
| People | Employees | `employeesPageActive` | `people-employees` |
| Fleet | Vehicles | `vehiclesPageActive` | `fleet-vehicles` |
| Fleet | Dashboard | `fleetDashboardPageActive` | `fleet-dashboard` |
| Fleet | Trailers | `fleetTrailersPageActive` | `fleet-trailers` |
| Fleet | Maintenance | `fleetMaintenancePageActive` | `fleet-maintenance` |
| Fleet | Mileage | `fleetMileagePageActive` | `fleet-mileage` |
| Fleet | Fuel | `fleetFuelPageActive` | `fleet-fuel` |
| Fleet | Inspections | `fleetInspectionsPageActive` | `fleet-inspections` |
| Fleet | Tracking | `fleetTrackingPageActive` | `fleet-tracking` |
| Fleet | My Truck | `fleetMyTruckPageActive` | `fleet-my-truck` |
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

## Restored Orders/Warehouse Slice

Added the next restored orders/warehouse coverage slice:

- `IOSPODetailPage`: PO number, supplier, status, line/open/received counts, linked jobs, delivery/tracking, receipt sessions.
- `IOSReceiveShipmentPage`: open PO list status counts when idle; active session item, discrepancy, routing, and unrouted counts when receiving.
- `IOSProcurementPage`: demand row counts, source filter/counts, selected rows, supplier selections, PO preview groups, pull decisions.
- `IOSReturnsPage`: total/visible returns, status filter/counts, visible credit total, examples.
- `WarehouseDashboardPage`: stock health KPIs, receiving/staging/returns counts, audit summary, selected activity filter, movement type counts.
- `WarehouseLocationsPage`: floor plans, selected plan, storage unit counts, configured/placed/movable counts, feature/unit type summaries.

All payloads are read-only summaries of visible state and selected filters. They do not expose mutating commands, action IDs, or write intents.

## WEI-1235 Warehouse Completion Slice

Added the warehouse completion page-context slice:

- `WarehouseMovementsPage`: loaded/visible movement counts, date range, selected movement filter, search state, movement type counts.
- `IOSReceivingPage`: loaded/visible receiving session counts, selected status filter, search state, session status counts.
- `IOSStagingPage`: active tab, staged item/box counts, selected destination filter, search state, selection mode, destination/box status counts.
- `IOSAuditPage`: confidence records, recent sessions, active counts, warehouse score, selected audit filter, active count/speed/walking-path state.
- `IOSWarehouseReturnsPage`: loaded/visible return counts, selected status filter, search state, return status counts.
- `IOSWarehouseToolsPage`: loaded/visible tool counts, selected status filter, search state, tool status counts.
- `IOSWarehouseNetworkPage`: local device status and planned network feature context.
- `IOSWarehouseSettingsPage`: visible warehouse settings values and saving state.
- `IOSOrganizationAuditPage`: active tab, org rating/consolidation counts, warehouse organization score, search state.
- `IOSWarehouseLeaderboardPage`: loaded/visible user rating counts, search state, manager detail access, top visible user.

All payloads are read-only summaries of visible state, selected filters, lifecycle state, and available entry points. They do not expose mutating commands, action IDs, or write intents.

## Jobs Completion Slice

Added the jobs completion page-context slice:

- `IOSJobDetailPage`: job identity, status, priority, customer, lead, dates, team count, labor summary, budget/parts cost.
- `LaborPage`: active and recent labor counts, visible hours, date range, search state, clock-in option counts.
- `IOSDailyReportsPage`: selected date, loaded/visible report counts, total workers/hours, status counts.
- `IOSQuestionnairePage`: labor entry id, loaded/required/answered question counts, answer types, break verification, companion polls.
- `IOSEstimationQuestionnairePage`: job/stage, question and answer counts, unknown answers, group counts, estimate confidence/hours, historical average, suggestions.
- `IOSEstimationReviewPage`: job id, review counts/types, latest estimate stage/hours/confidence, average variance, active sheet.
- `JobReportsPage`: loaded/visible report counts, date range, search state, status counts.

All payloads are read-only summaries of visible state, selected filters, lifecycle state, and available entry points. They do not expose mutating commands, action IDs, or write intents.

## WEI-1112 Productivity Restart Slice

Added the two missing active/inactive context posts required to bring declared page-active notifications to full feature-page emission coverage:

- `IOSUnifiedApprovalsPage`: `officeApprovalsPageActive` / `officeApprovalsPageInactive` with read-only summary of total/visible pending approvals, selected filter, search state, and pending counts by approval type.
- `SettingsRouter`: `settingsPageActive` / `settingsPageInactive` with read-only summary of selected settings tab and sync scope classification.

All payloads remain read-only summaries and avoid mutating commands, IDs for write actions, or workflow state changes.

## WEI-1112 Fleet Primary Tabs Slice

Added the next high-traffic Fleet coverage slice across the primary Fleet tabs:

- `IOSFleetDashboardPage`: `fleetDashboardPageActive` / `fleetDashboardPageInactive` with read-only KPI, maintenance, and trailer summary counts.
- `IOSMaintenancePage`: `fleetMaintenancePageActive` / `fleetMaintenancePageInactive` with total/visible records, date range, and search state.
- `IOSMileagePage`: `fleetMileagePageActive` / `fleetMileagePageInactive` with total/visible logs, date range, and search state.
- `IOSFuelPage`: `fleetFuelPageActive` / `fleetFuelPageInactive` with total/visible logs, date range, and search state.
- `IOSTrailersPage`: `fleetTrailersPageActive` / `fleetTrailersPageInactive` with total/visible trailers and search state.
- `IOSInspectionsPage`: `fleetInspectionsPageActive` / `fleetInspectionsPageInactive` with total/visible inspections and search state.
- `IOSTelematicsPage`: `fleetTelematicsPageActive` / `fleetTelematicsPageInactive` with total/visible locations and search state.
- `IOSMyTruckPage`: `fleetMyTruckPageActive` / `fleetMyTruckPageInactive` with assigned vehicle, selected inventory tab, and read-only count summaries.

Also wired these notifications through `IOSAIAssistantPanel` context observers/navigation-context prompt assembly and active page tracker IDs. Existing `fleetTrackingPageActive` router-tab context remains supported for the FleetRouter tracking tab.

All payloads remain read-only summaries and avoid mutating commands, write action IDs, or workflow state changes.

## Next Highest-Traffic Remaining Slices

1. Fleet secondary pages and deep links: trailer locations, truck tools, and detail-heavy flows still need explicit inventory decisions (context post vs N/A).
2. People area long-tail pages: contractors, teams, hats, permissions, and detail flows require the same explicit inventory/mapping treatment.
3. Settings help parity: add missing `settings-app-config` help entry before mapping settings context to help content.

## Validation

Validated in the shared workspace on 2026-05-13:

- New WEI-1194 notification names are declared, posted by their pages, observed by `IOSAIAssistantPanel`, tracked for active help page selection, and mapped in `HelpContentRegistry`.
- Help registry mapping check returned no missing mapped page IDs.
- `xcodebuild -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` passed. Remaining output was warnings only.

Validated restored orders/warehouse slice in the shared workspace on 2026-05-14:

- Restored slice notification names are declared, posted by their pages, observed by `IOSAIAssistantPanel`, tracked for active help page selection, and mapped in `HelpContentRegistry`.
- Help registry mapping check returned no missing mapped page IDs.
- `xcodebuild -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` passed. Remaining output was warnings only.

Validated WEI-1235 warehouse completion slice in the shared workspace on 2026-05-14:

- Warehouse completion notification names are declared, posted by their pages, observed by `IOSAIAssistantPanel`, tracked for active help page selection, and mapped in `HelpContentRegistry`.
- Help registry mapping check returned no missing mapped page IDs.
- First build caught Swift type-checker complexity in the expanded active-page tracker; the tracker was split into smaller modifiers.
- `xcodebuild -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` passed. Remaining output was warnings only.

Validated jobs completion slice in the shared workspace on 2026-05-14:

- Jobs completion notification names are declared, posted by their pages, observed by `IOSAIAssistantPanel`, tracked for active help page selection, and mapped in `HelpContentRegistry`.
- Help registry mapping check returned no missing mapped page IDs.
- `xcodebuild -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` passed. Remaining output was warnings only.

Validated WEI-1112 productivity restart slice in the shared workspace on 2026-05-17:

- Static inventory check confirms parity: declared page-active notifications = 60, pages posting page-active notifications = 60, missing = 0.
- `rg` confirmation shows new posts in `IOSUnifiedApprovalsPage` and `SettingsRouter`.
- `xcodebuild -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` passed. Remaining output was warnings only.

Validated WEI-1112 Fleet primary tabs slice in the shared workspace on 2026-05-17:

- Static parity checks on the recovered main-based branch reported declared page-active notifications = 57 and AI panel observers = 57, with no undeclared references or missing observers. One router-tab notification (`fleetTrackingPageActive`) is emitted through `FleetRouter` indirection rather than a literal `post(name: .fleetTrackingPageActive)` call.
- Fleet notification names are declared, posted by their pages, observed by `IOSAIAssistantPanel`, and tracked for active page selection.
- Help mapping is limited to help entries that currently exist; dedicated help-entry extraction remains for Fleet tabs beyond Dashboard and Maintenance.
- First build attempt hit Swift type-checker complexity in `IOSAIAssistantPanel` active-page tracker; resolved by splitting/consolidating Fleet tracker observers.
- `xcodebuild -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` passed after the split. Remaining output was warnings only.

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
