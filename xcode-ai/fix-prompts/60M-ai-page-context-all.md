# 60M — AI Page Context Notifications for All Feature Pages

> **Chain position:** Standalone
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

Currently only 5 Parts pages send context notifications to the AI assistant (catalogPageActive, pricingPageActive, suppliersPageActive, companionsPageActive, forecastingPageActive). The AI is blind on the other 82+ pages. Every feature page needs to post a notification with summary data when it appears and clear it when it disappears, so the AI knows what page the user is on and what data is visible.

**Read first:**
- `Weird Parts IOS/Weird Parts IOS/Navigation/NavigationConfig.swift` — see existing notification names (lines 196-233)
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsCatalogPage.swift` — see the `.onAppear`/`.onDisappear` pattern posting `.catalogPageActive`/`.catalogPageInactive`
- `Weird Parts IOS/Weird Parts IOS/AI/IOSAIAssistantPanel.swift` — see how it listens for page context notifications

## Task

### Step 1: Add notification names to NavigationConfig.swift

In `NavigationConfig.swift`, inside the `extension Notification.Name` block (after the existing forecasting entries around line 232), add paired active/inactive notifications for every major feature area:

```swift
    // Jobs
    static let jobsListPageActive = Notification.Name("WiredPart.jobsListPageActive")
    static let jobsListPageInactive = Notification.Name("WiredPart.jobsListPageInactive")
    static let jobDetailPageActive = Notification.Name("WiredPart.jobDetailPageActive")
    static let jobDetailPageInactive = Notification.Name("WiredPart.jobDetailPageInactive")
    static let clockPageActive = Notification.Name("WiredPart.clockPageActive")
    static let clockPageInactive = Notification.Name("WiredPart.clockPageInactive")

    // Orders
    static let jposPageActive = Notification.Name("WiredPart.jposPageActive")
    static let jposPageInactive = Notification.Name("WiredPart.jposPageInactive")
    static let purchaseOrdersPageActive = Notification.Name("WiredPart.purchaseOrdersPageActive")
    static let purchaseOrdersPageInactive = Notification.Name("WiredPart.purchaseOrdersPageInactive")

    // Warehouse
    static let warehouseDashboardActive = Notification.Name("WiredPart.warehouseDashboardActive")
    static let warehouseDashboardInactive = Notification.Name("WiredPart.warehouseDashboardInactive")
    static let inventoryGridActive = Notification.Name("WiredPart.inventoryGridActive")
    static let inventoryGridInactive = Notification.Name("WiredPart.inventoryGridInactive")

    // Scheduling
    static let dispatchPageActive = Notification.Name("WiredPart.dispatchPageActive")
    static let dispatchPageInactive = Notification.Name("WiredPart.dispatchPageInactive")
    static let scheduleCalendarActive = Notification.Name("WiredPart.scheduleCalendarActive")
    static let scheduleCalendarInactive = Notification.Name("WiredPart.scheduleCalendarInactive")

    // People
    static let employeesPageActive = Notification.Name("WiredPart.employeesPageActive")
    static let employeesPageInactive = Notification.Name("WiredPart.employeesPageInactive")

    // Fleet
    static let fleetDashboardActive = Notification.Name("WiredPart.fleetDashboardActive")
    static let fleetDashboardInactive = Notification.Name("WiredPart.fleetDashboardInactive")

    // Dashboard
    static let mainDashboardActive = Notification.Name("WiredPart.mainDashboardActive")
    static let mainDashboardInactive = Notification.Name("WiredPart.mainDashboardInactive")

    // Office
    static let officeDashboardActive = Notification.Name("WiredPart.officeDashboardActive")
    static let officeDashboardInactive = Notification.Name("WiredPart.officeDashboardInactive")

    // Tools
    static let toolsDashboardActive = Notification.Name("WiredPart.toolsDashboardActive")
    static let toolsDashboardInactive = Notification.Name("WiredPart.toolsDashboardInactive")

    // Notebooks
    static let notebooksPageActive = Notification.Name("WiredPart.notebooksPageActive")
    static let notebooksPageInactive = Notification.Name("WiredPart.notebooksPageInactive")

    // Reports
    static let reportsPageActive = Notification.Name("WiredPart.reportsPageActive")
    static let reportsPageInactive = Notification.Name("WiredPart.reportsPageInactive")

    // Settings
    static let settingsPageActive = Notification.Name("WiredPart.settingsPageActive")
    static let settingsPageInactive = Notification.Name("WiredPart.settingsPageInactive")
```

### Step 2: Add .onAppear/.onDisappear to each feature page

For EVERY page listed below, add the notification pattern. Follow the exact pattern from PartsCatalogPage:

```swift
.onAppear {
    NotificationCenter.default.post(
        name: .jobsListPageActive,  // use matching notification name
        object: nil,
        userInfo: [
            "context": "Brief description of what's on screen",
            // include relevant summary data the AI can use
        ]
    )
}
.onDisappear {
    NotificationCenter.default.post(name: .jobsListPageInactive, object: nil)
}
```

**Pages to update (minimum set — do ALL of these):**

| Page File | Active Notification | Context userInfo |
|-----------|-------------------|-----------------|
| `JobsListPage.swift` | `.jobsListPageActive` | `"jobCount"`, `"statusFilter"` |
| `IOSJobDetailTabView.swift` | `.jobDetailPageActive` | `"jobName"`, `"jobStatus"`, `"currentTab"` |
| `IOSClockPage.swift` | `.clockPageActive` | `"isClockedIn"`, `"currentJobName"` |
| `IOSJPOsPage.swift` | `.jposPageActive` | `"jpoCount"`, `"statusFilter"` |
| `IOSPurchaseOrdersPage.swift` | `.purchaseOrdersPageActive` | `"poCount"`, `"statusFilter"` |
| `DashboardView.swift` | `.mainDashboardActive` | `"userName"`, `"alertCount"` |
| `IOSDispatchPage.swift` | `.dispatchPageActive` | `"assignmentCount"`, `"selectedDate"` |
| `IOSScheduleCalendarPage.swift` | `.scheduleCalendarActive` | `"selectedDate"` |
| `IOSInventoryGridPage.swift` | `.inventoryGridActive` | `"partCount"`, `"searchQuery"` |
| `IOSEmployeesPage.swift` (if exists) | `.employeesPageActive` | `"employeeCount"` |
| `IOSVehiclesPage.swift` | `.fleetDashboardActive` | `"vehicleCount"` |
| `IOSNotebooksListPage.swift` | `.notebooksPageActive` | `"notebookCount"` |
| `IOSReportsRouter.swift` | `.reportsPageActive` | `"currentReport"` |

For each page, post contextually useful data that the AI can reference when answering questions. The `"context"` key should be a human-readable description like `"User is viewing 24 active jobs, filtered to 'In Progress'"`.

### Step 3: Update IOSAIAssistantPanel to listen for all new notifications

In `IOSAIAssistantPanel.swift`, find where it listens for `.catalogPageActive`. Add `.onReceive` handlers for ALL new notification names. Store the page context in a `@State private var currentPageContext: [String: Any] = [:]` dictionary. When any `*Active` notification fires, update this dictionary. When any `*Inactive` fires, clear it.

Include the current page context in the AI's system prompt so it knows what page the user is viewing and what data is on screen.

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/Navigation/NavigationConfig.swift` — add ~30 new notification names
- `Weird Parts IOS/Weird Parts IOS/AI/IOSAIAssistantPanel.swift` — listen for all new notifications, include in AI context
- `Weird Parts IOS/Weird Parts IOS/Features/Jobs/JobsListPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSJobDetailTabView.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSClockPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPOsPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPurchaseOrdersPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Dashboard/DashboardView.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSDispatchPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSScheduleCalendarPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSInventoryGridPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Fleet/IOSVehiclesPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Notebooks/IOSNotebooksListPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Reports/IOSReportsRouter.swift`

## Success Criteria

- [ ] All notification names defined in NavigationConfig.swift extension
- [ ] At least 13 feature pages post active/inactive notifications
- [ ] Each notification includes a `"context"` key with human-readable description
- [ ] IOSAIAssistantPanel listens for ALL new notifications
- [ ] AI system prompt includes current page context
- [ ] No `.onAppear` without a matching `.onDisappear`
- [ ] Builds without errors
