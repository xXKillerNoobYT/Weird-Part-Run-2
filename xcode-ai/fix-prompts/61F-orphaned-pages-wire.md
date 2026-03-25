# 61F — Wire 9 Orphaned/Unreachable Pages

> **Chain position:** **61F** (standalone)
> **Issue:** T2-08
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT delete any orphaned pages — wire them into navigation OR mark as sub-components
2. DO NOT create duplicate routes — check existing routes first
3. Every wired page must be reachable from at least ONE navigation path
4. If a page is actually a sub-component (not a standalone page), rename it to remove "Page" suffix
5. Project must build with zero errors when done

## Context

9 pages exist in the codebase but cannot be reached through any navigation path. They are fully built but orphaned — no route, no tab, no NavigationLink points to them. Each needs to be wired into the appropriate router or navigation structure.

## Pages to Wire

### 1. IOSSpendingDashboardPage
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Office/IOSSpendingDashboardPage.swift`
**Wire to:** Office module → add as a tab or NavigationLink from IOSOfficeDashboardPage. Label: "Spending Overview". Or wire from IOSReportsRouter under the "Financial" category.

### 2. IOSWarehouseLeaderboardPage
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSWarehouseLeaderboardPage.swift`
**Wire to:** Warehouse module → add as a tab in the warehouse section, or as a NavigationLink from WarehouseDashboardPage. Label: "Leaderboard".

### 3. WarehouseOnboardingWizard
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/WarehouseOnboardingWizard.swift`
**Wire to:** This is likely a first-run wizard for warehouse setup. Wire it to show automatically when the warehouse has zero locations configured. Add a check in WarehouseDashboardPage:
```swift
.task {
    let locations = try? appCore.warehouseService?.getLocations()
    if locations?.isEmpty ?? true {
        showOnboardingWizard = true
    }
}
.sheet(isPresented: $showOnboardingWizard) {
    WarehouseOnboardingWizard()
}
```
Also add a "Setup Wizard" button in warehouse settings for re-running it.

### 4. IOSPublicReportView
**File:** Find this file in the project (likely in Features/Reports/).
**Wire to:** This may be a shareable report view. Wire from IOSReportsRouter — add a "Share Report" button that presents this view. Or wire from any report page's share action.

### 5. OfficePlaceholderView
**File:** Find this file in Features/Office/.
**Action:** This is a placeholder — NOT a real page. Either:
- Replace it with actual content and wire it as a real page, OR
- Remove the "View" suffix and mark it as a stub component used inside other views
- If it's used as a destination for unimplemented features, add a clear message: "This feature is under development"

### 6. IOSDeletionApprovalsPage
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Office/IOSDeletionApprovalsPage.swift`
**Wire to:** Office module → add to the office router. This page shows items pending deletion approval. Add a route case and NavigationLink from the office dashboard or management area. Label: "Deletion Approvals".

### 7. IOSOrganizationAuditPage
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSOrganizationAuditPage.swift`
**Wire to:** Warehouse module → add as a sub-page of the audit section. Wire from the warehouse audit tab or from IOSAuditPage. Label: "Organization Audit".

### 8. PanelScheduleBuilder
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Notebooks/PanelScheduleBuilder.swift`
**Wire to:** This is a specialized notebook tool for electrical panel schedules. Wire from the notebook detail page — add a toolbar button "Panel Schedule" that presents this as a sheet when the notebook type is "panel_schedule" or similar. Or wire from CreateNotebookSheet as an option.

### 9. IOSPeopleDashboardPage
**File:** `Weird Parts IOS/Weird Parts IOS/Features/People/IOSPeopleDashboardPage.swift`
**Wire to:** People module → this is handled by prompt 61H (adding the tab to NavigationConfig). If 61H hasn't run yet, add the route here. The People router needs a "dashboard" case that shows this page.

## How to Wire Each Page

### Step 1: Find the Router
Each module has a router file (e.g., `WarehouseRouter.swift`, `OfficeRouter.swift`, `PeopleRouter.swift`). Find the appropriate router.

### Step 2: Add Route Case
```swift
enum WarehouseRoute {
    // existing cases...
    case leaderboard  // ADD THIS
}
```

### Step 3: Add Switch Case in Router Body
```swift
switch route {
    // existing cases...
    case .leaderboard:
        IOSWarehouseLeaderboardPage()
}
```

### Step 4: Add NavigationLink from Parent Page
In the module's main page or dashboard, add a NavigationLink:
```swift
NavigationLink(value: WarehouseRoute.leaderboard) {
    Label("Leaderboard", systemImage: "trophy")
}
```

### Step 5: Verify NavigationConfig
If the page should appear as a TAB (not just a navigable sub-page), add it to NavigationConfig's module definition.

## Success Criteria

- [ ] All 9 pages are reachable through at least one navigation path
- [ ] No orphaned pages remain
- [ ] Routes added to appropriate routers
- [ ] NavigationLinks or tabs point to each page
- [ ] Placeholder views show clear "under development" message
- [ ] Project builds with zero errors
