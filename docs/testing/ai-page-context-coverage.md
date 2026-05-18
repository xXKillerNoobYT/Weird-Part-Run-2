# AI Page Context Coverage Inventory

Issue: WEI-1112 / WEI-1194 / GitHub #86 T1-19
Updated: 2026-05-17

## Success Condition

Complete the 87-page page-context coverage set by adding read-only page-active/page-inactive notifications, wiring the AI panel to consume those notifications, and mapping page-active notifications to `HelpContentRegistry` page IDs where help content exists.

## Current Coverage

Implemented page-context notifications observed by `IOSAIAssistantPanel`: 87 page contexts.

Help registry mappings with matching help entries: 61 page contexts. The final tools/notebooks tail added active-page tracking but no shared help mappings because those page IDs do not yet have shared `HelpContentRegistry` entries.

Known gaps: `settingsPageActive`, People long-tail notifications (`contractorsPageActive`, `teamsPageActive`, `hatsPageActive`, `permissionsPageActive`), and the scheduling long-tail notifications added in WEI-1544 are observed by the AI panel and active-page tracker, but `HelpContentRegistry` does not yet contain matching shared entries for `settings-app-config`, `people-contractors`, `people-teams`, `people-hats`, `people-permissions`, `scheduling-flex-pool`, `scheduling-time-off`, `scheduling-templates`, `scheduling-availability`, `scheduling-sub-schedule`, `scheduling-pipeline`, `scheduling-long-pipeline`, or `scheduling-config`; final tools/notebooks tail notifications (`toolsDashboardPageActive`, `toolCheckoutsPageActive`, `toolKitsPageActive`, `toolMaintenancePageActive`, `toolAdminPageActive`, `notebookTemplatesPageActive`, `jobNotebooksPageActive`) likewise have active page IDs but no shared help entries yet. These pages keep their existing local `PageHelpSheet` help until a dedicated help-registry parity slice adds shared help entries.

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
| Scheduling | Flex Pool | `schedulingFlexPoolPageActive` | missing help entry |
| Scheduling | Time Off | `schedulingTimeOffPageActive` | missing help entry |
| Scheduling | Dispatch Templates | `schedulingTemplatesPageActive` | missing help entry |
| Scheduling | Weekly Availability | `schedulingAvailabilityPageActive` | missing help entry |
| Scheduling | Sub Schedule | `schedulingSubSchedulePageActive` | missing help entry |
| Scheduling | Short-Term Pipeline | `schedulingPipelinePageActive` | missing help entry |
| Scheduling | Long-Term Pipeline | `schedulingLongPipelinePageActive` | missing help entry |
| Scheduling | Schedule Config | `schedulingConfigPageActive` | missing help entry |
| People | Employees | `employeesPageActive` | `people-employees` |
| People | Contractors | `contractorsPageActive` | missing help entry |
| People | Teams | `teamsPageActive` | missing help entry |
| People | Hats & Roles | `hatsPageActive` | missing help entry |
| People | Permissions | `permissionsPageActive` | missing help entry |
| Fleet | Vehicles | `vehiclesPageActive` | `fleet-vehicles` |
| Tools | Tool Registry | `toolRegistryPageActive` | `tools-registry` |
| Tools | Tools Dashboard | `toolsDashboardPageActive` | missing help entry |
| Tools | Tool Checkouts | `toolCheckoutsPageActive` | missing help entry |
| Tools | Tool Kits | `toolKitsPageActive` | missing help entry |
| Tools | Tool Maintenance | `toolMaintenancePageActive` | missing help entry |
| Tools | Tool Admin | `toolAdminPageActive` | missing help entry |
| Notebooks | Notebooks List | `notebooksListPageActive` | `notebooks-all` |
| Notebooks | Notebook Templates | `notebookTemplatesPageActive` | missing help entry |
| Notebooks | Job Notebooks | `jobNotebooksPageActive` | missing help entry |
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

Also wired these notifications through:

- `IOSAIAssistantPanel` context observers and navigation-context prompt assembly.
- Active page tracker IDs for fleet tabs.
- `HelpContentRegistry` active-page mappings where help entries already exist (`fleet-dashboard`, `fleet-maintenance`).

All payloads remain read-only summaries and avoid mutating commands, write action IDs, or workflow state changes.

## WEI-1112 People Long-Tail Slice

Added the next People coverage slice for long-tail router tabs:

- `IOSContractorsPage`: `contractorsPageActive` / `contractorsPageInactive` with read-only contractor counts, search/loading/error state, and available read-only contractor detail categories.
- `IOSTeamsPage`: `teamsPageActive` / `teamsPageInactive` with total/visible/active team counts, selected filter, search/loading/error state, and available read-only team detail categories.
- `IOSHatsPage`: `hatsPageActive` / `hatsPageInactive` with total/visible hats, assigned-hat count, search/loading/error state, and available read-only hat detail categories.
- `IOSPermissionsPage`: `permissionsPageActive` / `permissionsPageInactive` with hat/group/permission-key counts, selected hat, enabled-permission count, legacy PIN upgrade count, loading/error state, and available read-only permission matrix categories.

Also wired these notifications through:

- `IOSAIAssistantPanel` context observers and navigation-context prompt assembly.
- Active page tracker IDs for People long-tail tabs.

Help registry mappings were intentionally not added for this slice because these page IDs do not yet have shared `HelpContentRegistry` entries; each page keeps its existing local `PageHelpSheet` help until a help-registry parity slice adds entries.

All payloads remain read-only summaries and avoid mutating commands, write action IDs, or workflow state changes.

## WEI-1544 Scheduling Long-Tail Slice

Added the next scheduling long-tail page-context slice:

- `IOSFlexPoolPage`: `schedulingFlexPoolPageActive` / `schedulingFlexPoolPageInactive` with available job counts, pending claim state, loading/error state, and read-only claim guidance.
- `IOSTimeOffPage`: `schedulingTimeOffPageActive` / `schedulingTimeOffPageInactive` with total/visible request counts, selected status/date filters, status counts, search state, and loading/error state.
- `IOSDispatchTemplatesPage`: `schedulingTemplatesPageActive` / `schedulingTemplatesPageInactive` with total/visible/active/inactive template counts and search/loading/error state.
- `IOSWeeklyAvailabilityPage`: `schedulingAvailabilityPageActive` / `schedulingAvailabilityPageInactive` with selected week, visible employee counts, search/loading/error state, and availability-grid guidance.
- `IOSSubSchedulePage`: `schedulingSubSchedulePageActive` / `schedulingSubSchedulePageInactive` with selected date, assignment counts, subcontractor status counts, search/loading/error state.
- `IOSShortTermPipelinePage`: `schedulingPipelinePageActive` / `schedulingPipelinePageInactive` with pipeline category counts, callback count, search state, selected-job presence, AI suggestion count, and loading/error state.
- `IOSLongTermPipelinePage`: `schedulingLongPipelinePageActive` / `schedulingLongPipelinePageInactive` with visible month counts, AI warning count, selected-month summary, search/loading/error state.
- `IOSScheduleConfigPage`: `schedulingConfigPageActive` / `schedulingConfigPageInactive` with workday, template, holiday, supervisor, overtime, weekend, saving, and error summaries.

Also wired these notifications through:

- `IOSAIAssistantPanel` context observers and navigation-context prompt assembly.
- Active page tracker IDs for scheduling long-tail tabs.

Help registry mappings were intentionally not added for this slice because these scheduling page IDs do not yet have shared `HelpContentRegistry` entries; each page keeps its existing local `PageHelpSheet` help until a help-registry parity slice adds entries. Sheet-only flows such as `CreateScheduleEntrySheet`, `RequestTimeOffSheet`, and `IOSTemplateBuilderSheet` remain N/A for page-level coverage because they are modal subflows, not router tabs.

All payloads remain read-only summaries and avoid mutating commands, write action IDs, or workflow state changes.

## WEI-1566 Final Tools/Notebooks Tail Slice

Added the final bounded router-tab page-context slice from the 80-context WEI-1544 baseline to the 87-page standard:

- `IOSToolsRouter` posts read-only context for Tools Dashboard, Tool Checkouts, Tool Kits, Tool Maintenance, and Tool Admin.
- `IOSNotebooksRouter` posts read-only context for Notebook Templates and Job Notebooks.
- `NavigationConfig.swift` declares active/inactive notification pairs for the seven added router tabs.
- `IOSAIAssistantPanel` observes those notifications, appends concise READ-ONLY prompt context, and tracks active page IDs for the same seven page IDs.

All payloads are intentionally router-level, concise, and non-mutating: current page, visible workflow summary, and read-only review/navigation guidance only. They do not expose mutating commands, write action IDs, or edit intents.

## Final Inventory / Explicit N/A Decisions

WEI-1542 is final for the 87-count functional router-tab standard: the 87 covered contexts above now have declaration/post/AI-observer/active-page parity. Remaining discovered pages are explicitly N/A for this standard unless promoted to first-class router tabs later:

- Tools detail pages and scanner/checkout/return sheets: N/A modal/detail subflows reached from Tool Registry or Tool Checkouts, not independent router tabs.
- Notebook detail pages: N/A detail subflows reached from Notebooks List, Job Notebooks, or Templates, not independent router tabs.
- Parts categories, brands, and import/export flows: N/A for this final 87 standard because they remain secondary/administrative subflows without dedicated shared help entries; Parts Catalog/Suppliers/Pricing/Companions/Forecasting already cover the countable Parts router set.
- Fleet trailer-location, truck-tools, vehicle/trailer detail flows: N/A deep-link/detail/secondary routes, not promoted into the final 87 first-class router-tab count.
- Settings/help parity: not a coverage blocker; missing shared help entries remain a follow-up content-extraction task for settings, People long-tail, scheduling long-tail, and final tools/notebooks tail pages.

## Next Highest-Traffic Remaining Slices

1. Help registry parity/content extraction: add shared help entries before mapping settings, People long-tail, scheduling long-tail, and final tools/notebooks tail contexts to shared help content.
2. If product later promotes any currently N/A detail/modal flow to a first-class router tab, add the same notification/context/observer/active-page pattern at that time.

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

- Static parity checks:
  - declared page-active notifications = 68
  - pages posting page-active notifications = 68
  - AI panel observers for page-active notifications = 68
  - missing declarations/posts/observers = 0
- Help mapping check returned no missing mapped page IDs after adding Fleet dashboard/maintenance mappings.
- First build attempt hit Swift type-checker complexity in `IOSAIAssistantPanel` active-page tracker; resolved by splitting the Fleet tracker chain into additional tail modifiers.
- `xcodebuild -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` passed after the split. Remaining output was warnings only.

Validated WEI-1112 People long-tail slice in the shared workspace on 2026-05-17:

- Static parity checks:
  - declared page-active notifications = 72
  - pages posting page-active notifications = 72
  - AI panel observers for page-active notifications = 72
  - missing declarations/posts/observers = 0
- Help mapping check returned no missing mapped page IDs. People long-tail page IDs were not mapped because shared help entries do not exist yet; those pages keep local `PageHelpSheet` help.
- `xcodebuild -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` passed. Remaining output was warnings only.

Validated WEI-1544 Scheduling long-tail slice in the shared workspace on 2026-05-17:

- Static parity checks:
  - declared page-active notifications = 80
  - pages posting page-active notifications = 80
  - AI panel observers for page-active notifications = 80
  - missing declarations/posts/observers = 0
- Help mapping check returned no missing mapped page IDs. Scheduling long-tail page IDs were not mapped because shared help entries do not exist yet; those pages keep local `PageHelpSheet` help.
- `xcodebuild -project "Weird Parts IOS/Weird Parts.xcodeproj" -scheme "Weird Parts" -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` passed. Remaining output was warnings only.

Validated WEI-1566 final tools/notebooks tail slice in the shared workspace on 2026-05-17:

- Static parity checks:
  - declared page-active notifications = 87
  - pages posting page-active notifications = 87
  - AI panel observers for page-active notifications = 87
  - active page tracker mappings = 87
  - duplicate declarations = 0
  - missing declarations/posts/observers = 0
- Help mapping check remains non-blocking for unmapped pages without shared help entries; no notification was mapped to a missing shared help entry.
- First build attempt hit Swift type-checker complexity in the expanded active-page tracker; resolved by splitting the tools/notebooks/settings tail into smaller tracker modifiers.
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
