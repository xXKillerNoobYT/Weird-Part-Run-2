# 62A — Add .refreshable to 39 List Views Missing Pull-to-Refresh
> Chain position: Standalone

## Task

Add `.refreshable { await loadData() }` (or the equivalent reload function) to every List/ScrollView page that currently lacks pull-to-refresh. Each page already has a `loadData()` or equivalent function called in `.task {}` — the `.refreshable` modifier simply invokes the same function.

### Step-by-step for EVERY file listed below:

1. Open the file.
2. Find the outermost `List` or `ScrollView` that displays the page content.
3. Immediately after the closing brace of that `List`/`ScrollView` (before any `.navigationTitle` or other modifiers), add:
   ```swift
   .refreshable {
       loadData()
   }
   ```
   If `loadData()` is `async`, use `await loadData()`. If the function is named differently (e.g., `loadDetails()`, `fetchData()`, `reload()`), use the name that matches the `.task {}` call already in the file.
4. Do NOT add `.refreshable` if the view is a form/sheet/wizard — only list/dashboard pages.

### Files to add .refreshable to (39 files):

**Dashboard:**
- `Features/Dashboard/DashboardDailyReportPage.swift`

**Chat:**
- `Features/Chat/IOSQuestionsPage.swift`
- `Features/Chat/IOSRFIListPage.swift`

**Fleet:**
- `Features/Fleet/IOSFleetDashboardPage.swift`
- `Features/Fleet/IOSFuelPage.swift`
- `Features/Fleet/IOSInspectionsPage.swift`
- `Features/Fleet/IOSMaintenancePage.swift`
- `Features/Fleet/IOSMileagePage.swift`
- `Features/Fleet/IOSMyTruckPage.swift`
- `Features/Fleet/IOSTelematicsPage.swift`
- `Features/Fleet/IOSTrailerDetailPage.swift`
- `Features/Fleet/IOSTrailerLocationsPage.swift`
- `Features/Fleet/IOSTrailersPage.swift`
- `Features/Fleet/IOSTruckToolsPage.swift`

**Jobs:**
- `Features/Jobs/IOSDailyReportsPage.swift`
- `Features/Jobs/IOSJobDetailPage.swift`

**Notebooks:**
- `Features/Notebooks/IOSNotebookDetailPage.swift`
- `Features/Notebooks/IOSNotebookTemplatesPage.swift`

**Office:**
- `Features/Office/IOSOfficeDashboardPage.swift`
- `Features/Office/IOSSpendingDashboardPage.swift`
- `Features/Office/IOSWarehouseExecPage.swift`

**Orders:**
- `Features/Orders/IOSApprovalsPage.swift`
- `Features/Orders/IOSProcurementPage.swift`
- `Features/Orders/IOSReturnsPage.swift`

**Parts:**
- `Features/Parts/PartsCategoriesPage.swift`

**People:**
- `Features/People/IOSContactsPage.swift`
- `Features/People/IOSContractorDetailPage.swift`
- `Features/People/IOSContractorsPage.swift`
- `Features/People/IOSCustomerDetailPage.swift`
- `Features/People/IOSCustomersPage.swift`
- `Features/People/IOSEmployeesPage.swift`
- `Features/People/IOSPeopleDashboardPage.swift`
- `Features/People/IOSTeamsPage.swift`

**Reports:**
- `Features/Reports/IOSDailyReportsSummaryPage.swift`
- `Features/Reports/IOSLaborOverviewPage.swift`
- `Features/Reports/IOSProfitabilityPage.swift`
- `Features/Reports/IOSSpendingPage.swift`

**Scheduling:**
- `Features/Scheduling/IOSDispatchTemplatesPage.swift`
- `Features/Scheduling/IOSLongTermPipelinePage.swift`

**Tools:**
- `Features/Tools/IOSToolCheckoutsPage.swift`
- `Features/Tools/IOSToolKitsPage.swift`
- `Features/Tools/IOSToolMaintenancePage.swift`
- `Features/Tools/IOSToolsDashboardPage.swift`

**Warehouse:**
- `Features/Warehouse/WarehouseMovementsPage.swift`

### Pattern to follow (existing working example):

```swift
// In JobsListPage.swift (already has .refreshable):
List {
    // ... content ...
}
.refreshable {
    loadData()
}
.task {
    loadData()
}
```

## Files to Modify

All 39+ files listed above, located under:
`Weird Parts IOS/Weird Parts IOS/Features/`

## Success Criteria
- [ ] Every List/ScrollView page in the app has `.refreshable` — pull down on any list and it reloads
- [ ] No compile errors introduced
- [ ] The reload function called in `.refreshable` matches the one called in `.task {}`
- [ ] No `.refreshable` added to sheets, forms, or wizard pages (only list/dashboard pages)
