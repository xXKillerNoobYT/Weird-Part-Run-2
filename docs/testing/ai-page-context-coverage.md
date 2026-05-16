# AI Page Context Coverage Inventory

Issue: WEI-1112 / WEI-1194 / GitHub #86 T1-19
Updated: 2026-05-15

## Success Condition

Complete the 87-page page-context coverage set by adding read-only page-active/page-inactive notifications, wiring the AI panel to consume those notifications, and mapping page-active notifications to `HelpContentRegistry` page IDs where help content exists.

## Current Coverage

Implemented page-context notifications observed by `IOSAIAssistantPanel`: 72 page contexts.

Help registry mappings with matching help entries: 72 page contexts.

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
| People | People Dashboard | `peopleDashboardPageActive` | `people-dashboard` |
| People | Employees | `employeesPageActive` | `people-employees` |
| People | Customers | `customersPageActive` | `people-customers` |
| People | Contacts | `contactsPageActive` | `people-contacts` |
| People | Contractors | `contractorsPageActive` | `people-contractors` |
| People | Teams | `teamsPageActive` | `people-teams` |
| People | Hats & Roles | `hatsPageActive` | `people-hats` |
| People | Permissions | `permissionsPageActive` | `people-permissions` |
| Office | Office Dashboard | `officeDashboardPageActive` | `office-dashboard` |
| Office | Unified Approvals | `officeApprovalsPageActive` | `office-approvals` |
| Office | Spending Dashboard | `officeSpendingPageActive` | `office-spending` |
| Office | Manage Jobs | `officeManageJobsPageActive` | `office-manage-jobs` |
| Office | Estimation Questions | `officeEstimationSettingsPageActive` | `office-estimation-settings` |
| Office | Pipeline Hub | `officePipelinePageActive` | `office-pipeline` |
| Office | Warehouse Exec | `officeWarehouseExecPageActive` | `office-warehouse-exec` |
| Office | Teams Route Alias | `officeTeamsRoutePageActive` | `office-teams` |
| Office | Reports Hub Route | `officeReportsHubPageActive` | `office-reports` |
| Reports | Labor Overview | `reportsLaborPageActive` | `reports-labor` |
| Reports | Spending | `reportsSpendingPageActive` | `reports-spending` |
| Reports | Profitability | `reportsProfitabilityPageActive` | `reports-profitability` |
| Reports | Timesheets | `reportsTimesheetsPageActive` | `reports-timesheets` |
| Reports | Pre-Billing | `reportsPrebillingPageActive` | `reports-prebilling` |
| Reports | Bookkeeper Export | `reportsBookkeeperPageActive` | `reports-bookkeeper` |
| Reports | Daily Reports Summary | `reportsDailySummaryPageActive` | `reports-daily-summary` |
| Reports | Reports Hub | `reportsHubPageActive` | `reports-hub` |
| Reports | Report Builder | `reportsBuilderPageActive` | `reports-builder` |
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

## People/Office/Reports Slice

Added the next People, Office, and Reports page-context slice:

- `IOSPeopleDashboardPage`: working-now, off-today, certification, team assignment, and overdue customer counts.
- `IOSCustomersPage`: loaded/visible customer counts and search state.
- `IOSContactsPage`: active/inactive contact counts, selected type filter, sort, and search state.
- `IOSOfficeDashboardPage`: smart card, attention item, schedule, financial snapshot, and background task row counts.
- `IOSUnifiedApprovalsPage`: pending/visible approval counts, selected filter, and search state.
- `IOSSpendingDashboardPage`: selected range, parts cost, labor hours, active job count, and total job count.
- `IOSLaborOverviewPage`: selected range, total/overtime hours, active worker count, and visible row count.
- `IOSSpendingPage`: selected range/period, total spend, PO count, and top supplier.
- `IOSProfitabilityPage`: selected range, loaded/visible job counts, total profit, and search state.
- `IOSTimesheetsPage`: selected dates, employee count, visible row count, total hours, and overtime.
- `IOSPreBillingPage`: selected dates, job count, visible row count, regular hours, and overtime.
- `IOSBookkeeperExportPage`: selected dates, labor/material row counts, material total, and search state.
- `IOSDailyReportsSummaryPage`: selected date, job/visible row counts, worker count, and total hours.

All payloads are read-only summaries of visible state, selected filters, lifecycle state, and report totals. They do not expose mutating commands, action IDs, or write intents.

## Settings Gap Closure Slice

Closed the known settings mapping gap:

- `AppConfigPage`: auto-lock, stale-data warning, archive retention, warranty default, payment tracking, validation, saved/error state.

The payload is a read-only summary of visible settings and validation state. It does not expose mutating commands, action IDs, or write intents.

## People/Office Tail Slice

Added the next People and Office tail page-context slice:

- `IOSContractorsPage`: loaded contractor count, search state, and contact-info coverage counts.
- `IOSTeamsPage`: loaded/visible team counts, selected smart-card filter, total members, and leader coverage.
- `IOSHatsPage`: loaded/visible hat counts, assigned hat count, total assignments, search state, and detail-sheet state.
- `IOSPermissionsPage`: loaded hats, selected hat, permission group/key counts, enabled permission count, and legacy PIN upgrade count.
- `IOSManageJobsPage`: loaded/visible job counts, selected status filter, search state, status counts, and summary stats.
- `IOSEstimationSettingsPage`: question counts by active state, stage, and answer type, effectiveness rows, and visible error state.
- `OfficePipelineView`: read-only hub context for Short-Term Pipeline, Long-Term Pipeline, and Dispatch Board entry points.

All payloads are read-only summaries of visible state, selected filters, lifecycle state, and available entry points. They do not expose mutating commands, action IDs, or write intents.

## Office/Reports Route Slice

Added the next Office/Reports route-context slice:

- `IOSWarehouseExecPage`: low stock, movement, total stock, pending staging KPIs, and quick-action entry points.
- `OfficeTeamsRouteView`: route-alias context for `office-teams` pointing to shared teams management.
- `OfficeReportsLinkView`: reports hub entry context for custom builder vs categorized reports.
- `IOSReportsRouter`: selected category and permission-filtered visible category context.
- `ReportBuilderView`: selected type, step, columns, date range, generated row state, and save/error context.

All payloads are read-only summaries of visible state, route scope, selected filters, lifecycle state, and available entry points. They do not expose mutating commands, action IDs, or write intents.

## Next Highest-Traffic Remaining Slices

1. Specialized report pages: fleet, scheduling, and warehouse report detail pages still not observed by AI page-context notifications.
2. Settings: add missing help entries and page context for high-use settings subpages before mapping them to help content.

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

Validated People/Office/Reports slice in the shared workspace on 2026-05-15:

- People/Office/Reports notification names are declared, posted by their pages, observed by `IOSAIAssistantPanel`, tracked for active help page selection, and mapped in `HelpContentRegistry`.
- Help registry mapping check returned no missing mapped page IDs.
- `xcodebuild -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` passed. Remaining output was pre-existing warnings only.

Validated Settings gap closure slice in the clean WEI-1112 settings worktree on 2026-05-15:

- `settingsPageActive` is posted by `AppConfigPage`, observed by `IOSAIAssistantPanel`, tracked for active help page selection, and mapped in `HelpContentRegistry`.
- Help registry mapping check returned no missing mapped page IDs.
- First build exposed a recovered-branch compile issue in `IOSOfficeDashboardPage` background task status rows; the page now uses existing `BackgroundTaskService.TaskLogEntry` data instead of unavailable types.
- `xcodebuild -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` passed. Remaining output was pre-existing warnings only.

Validated People/Office tail slice in the clean WEI-1112 tail worktree on 2026-05-15:

- Tail slice notification names are declared, posted by their pages, observed by `IOSAIAssistantPanel`, tracked for active help page selection, and mapped in `HelpContentRegistry`.
- Help registry mapping check returned no missing mapped page IDs.
- `xcodebuild -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` passed. Remaining output was pre-existing warnings only.

Validated Office/Reports route slice in the clean WEI-1112 tail worktree on 2026-05-15:

- Route slice notification names are declared, posted by Office/Reports route pages, observed by `IOSAIAssistantPanel`, tracked for active help page selection, and mapped in `HelpContentRegistry`.
- Help registry mapping check returned no missing mapped page IDs.
- `xcodebuild -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` passed. Remaining output was pre-existing warnings only.

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
