# AI Page Context Coverage Inventory

Issue: WEI-1112 / WEI-1194 / GitHub #86 T1-19
Updated: 2026-05-23

## Success Condition

Complete the 87-page page-context coverage set by adding read-only page-active/page-inactive notifications, wiring the AI panel to consume those notifications, and mapping page-active notifications to `HelpContentRegistry` page IDs where help content exists.

## Current Coverage

Implemented page-context notifications observed by `IOSAIAssistantPanel`: 50 page contexts.

Help registry mappings with matching help entries: 50 page contexts.

The previous `settingsPageActive` / `settings-app-config` gap is closed. The static check in `tests/static/test_ai_help_context_coverage.py` now prevents tracked page IDs, `HelpContentRegistry.notificationToPageId`, and representative beta pages from drifting silently.

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
| Tools | Tool Registry | `toolRegistryPageActive` | `tools-registry` |
| Notebooks | Notebooks List | `notebooksListPageActive` | `notebooks-all` |
| Office | Office Dashboard | `officeDashboardPageActive` | `office-dashboard` |
| Reports | Timesheets | `reportsTimesheetsPageActive` | `reports-timesheets` |
| Settings | Settings/App Config | `settingsPageActive` | `settings-app-config` |

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

## Next Highest-Traffic Remaining Slices

1. People/Office/Reports: Contacts, customers, contractors, teams, office dashboard, approvals, spending, warehouse exec, all report pages.
2. Settings: add missing help entries and page context for the high-use settings pages before mapping them to help content.

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

Static validation:

```bash
python3 tests/static/test_ai_help_context_coverage.py
rg -n "PageActive|PageInactive|post\\(name: \\." "Weird Parts IOS/Weird Parts IOS" -g "*.swift"
ruby -ne 'puts $1 if /pageId: "([^"]+)"/' "Weird Parts IOS/Weird Parts IOS/Shared/HelpContentRegistry.swift" | sort > /tmp/helpids.txt
ruby -ne 'puts $1 if /"WiredPart\\.[^"]+": "([^"]+)"/' "Weird Parts IOS/Weird Parts IOS/Shared/HelpContentRegistry.swift" | sort | uniq > /tmp/mapids.txt
comm -13 /tmp/helpids.txt /tmp/mapids.txt
```

Representative coverage table for GH #650:

| Representative area | Page | HelpContentRegistry | Page context freshness |
| --- | --- | --- | --- |
| Dashboard | Dashboard Home | `dashboard-home` registered and mapped | Existing active/inactive context observed by AI panel |
| Jobs | Jobs List | `jobs-list` registered and mapped | Existing list/filter context observed by AI panel |
| Jobs | Clock-Out Questionnaire | `jobs-questionnaire` registered and mapped | Existing questionnaire context observed by AI panel |
| Warehouse | Inventory Grid | `warehouse-inventory` registered and mapped | Existing inventory/filter context observed by AI panel |
| Fleet | Vehicles | `fleet-vehicles` registered and mapped | Existing vehicle context observed by AI panel; no extra fleet page notification currently maps to missing help |
| People | Employees | `people-employees` registered and mapped | Existing employee/search context observed by AI panel |
| Office | Office Dashboard | `office-dashboard` registered and mapped | New office dashboard context posts on appear/load and is observed by AI panel |
| Reports | Timesheets | `reports-timesheets` registered and mapped | New timesheets context posts on appear/load/search/date changes and is observed by AI panel |
| Settings | Settings/App Config | `settings-app-config` registered and mapped | Existing settings context now resolves matching help content |

Build validation:

```bash
xcodebuild -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
