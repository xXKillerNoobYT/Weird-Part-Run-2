# 60G — Help Buttons Visible on All Pages
> Chain position: Standalone
> Log file: xcode-ai/prompt-results-log.md

## Instructions

Two problems: (1) Pages that DO have help buttons put them in `.secondaryAction` placement, which buries them in the "..." overflow menu — users never find them. (2) 58+ pages have NO help button at all. Fix both: move all existing help buttons to `.primaryAction` and add help buttons to every page that's missing one, using the existing `PageHelpSheet` component.

## Task

### Step 1: Fix existing help buttons — move from secondaryAction to primaryAction

Search all `.swift` files for `placement: .secondaryAction` where the button shows `questionmark.circle`. Change every instance to `placement: .primaryAction`.

**Before pattern:**
```swift
ToolbarItem(placement: .secondaryAction) {
    Button { activeSheet = .help } label: {
        Image(systemName: "questionmark.circle")
    }
}
```

**After pattern:**
```swift
ToolbarItem(placement: .primaryAction) {
    Button { activeSheet = .help } label: {
        Image(systemName: "questionmark.circle")
    }
}
```

Search for ALL instances across the project. Files that currently have this pattern include (but may not be limited to):
- `IOSJobDetailTabView.swift` (line ~93)
- Check every file with `secondaryAction` + `questionmark`

### Step 2: Add help buttons to pages that are missing them

For each page listed below, add:

1. A `case help` to the page's `ActiveSheet` enum (create the enum if it doesn't exist)
2. An `@State private var activeSheet: ActiveSheet?` property (if not already present)
3. A toolbar button with `.primaryAction` placement
4. A `.sheet(item: $activeSheet)` modifier showing `PageHelpSheet` with practical help content

**Template for adding help to a page that has no sheet management:**

```swift
// Add at the struct level:
private enum ActiveSheet: Identifiable {
    case help
    var id: String { String(describing: self) }
}
@State private var activeSheet: ActiveSheet?

// Add to the body's toolbar:
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button { activeSheet = .help } label: {
            Image(systemName: "questionmark.circle")
        }
    }
}

// Add sheet modifier:
.sheet(item: $activeSheet) { sheet in
    switch sheet {
    case .help:
        PageHelpSheet(
            title: "PAGE_NAME Help",
            sections: [
                ("Section1", "Description1"),
                ("Section2", "Description2")
            ]
        )
    }
}
```

**Template for adding help to a page that already has an ActiveSheet enum:**

Add `case help` to the existing enum. Add the toolbar button. Add the `.help` case to the existing sheet switch.

### Pages that need help buttons added (with suggested help content):

| # | File | Help Title | Sections |
|---|------|-----------|----------|
| 1 | `IOSJPOsPage.swift` | "Job Purchase Orders Help" | ("Creating JPOs", "Tap + to build a new parts order for a job. The cart builder lets you search parts and add quantities."), ("Status Filters", "Filter by draft, pending, submitted, approved, or rejected status."), ("QR Scanning", "Scan a PO QR code to quickly find the linked order.") |
| 2 | `IOSPurchaseOrdersPage.swift` | "Purchase Orders Help" | ("PO Lifecycle", "POs start as Draft, then Submitted, Ordered, and finally Received."), ("Actions", "Swipe a PO row to see quick actions like edit, duplicate, or cancel.") |
| 3 | `IOSPODetailPage.swift` | "PO Detail Help" | ("Status Actions", "Different buttons appear based on PO status. Draft POs can be submitted or deleted."), ("Line Items", "Shows all parts on this PO with quantities, prices, and delivery status."), ("Notes", "Add notes visible to your team. Supplier notes are shared when you contact them.") |
| 4 | `IOSReceiveShipmentPage.swift` | "Receiving Help" | ("Starting a Session", "Tap Receive on a PO to start entering quantities."), ("Routing", "After entering quantities, route each item to a shelf, staging area, or mark for return."), ("Completing", "Tap Complete when all items are received and routed.") |
| 5 | `JobsListPage.swift` | "Jobs List Help" | ("Finding Jobs", "Use search to find jobs by name or number. Filter by status using the chips."), ("Creating Jobs", "Tap + to create a new job with customer info, address, and estimated hours.") |
| 6 | `IOSClockPage.swift` | "Clock In/Out Help" | ("Clocking In", "Select a job and tap Clock In. GPS location is recorded automatically."), ("Breaks", "Use the Break button to pause your clock. Break time is tracked separately."), ("History", "View your recent clock entries below the clock controls.") |
| 7 | `IOSDispatchPage.swift` | "Dispatch Help" | ("Assignments", "View and manage crew assignments for today's jobs."), ("Templates", "Use dispatch templates to quickly assign regular crews to recurring jobs.") |
| 8 | `IOSScheduleCalendarPage.swift` | "Schedule Help" | ("Calendar View", "Tap a day to see who's scheduled. Drag entries to reschedule."), ("Creating Entries", "Tap + to add a new schedule entry for an employee.") |
| 9 | `PartsCatalogPage.swift` | "Parts Catalog Help" | ("Browsing", "Search or browse parts by category. Tap a part for details, stock levels, and pricing."), ("Categories", "Use the category tree on the left (iPad) or category filter (iPhone) to narrow results.") |
| 10 | `IOSInventoryGridPage.swift` | "Inventory Grid Help" | ("Stock Levels", "Each cell shows current stock. Red = below minimum, yellow = below target, green = at or above target."), ("Quick Actions", "Tap a cell to adjust quantity, view history, or start a movement.") |
| 11 | `IOSEmployeesPage.swift` | "Employees Help" | ("Managing", "Tap an employee to view details, certifications, skills, and time records."), ("Adding", "Tap + to add a new employee with their role, contact info, and pay rate.") |
| 12 | `IOSVehiclesPage.swift` | "Fleet Help" | ("Vehicles", "View all company vehicles with their assignment status and maintenance schedule."), ("Inspections", "Each vehicle should have a pre-trip inspection before daily use.") |
| 13 | `IOSNotebooksListPage.swift` | "Notebooks Help" | ("General Notebooks", "Create notebooks for notes, checklists, and to-dos not tied to a specific job."), ("Templates", "Use templates to quickly create notebooks with pre-filled sections.") |
| 14 | `IOSToolRegistryPage.swift` | "Tool Registry Help" | ("Tracking", "All company tools are tracked here with serial numbers, assigned users, and maintenance status."), ("Checkout", "Workers check out tools before use and return them after. Overdue tools are flagged.") |
| 15 | `DashboardView.swift` | "Dashboard Help" | ("KPI Cards", "Tap any KPI card for a detailed breakdown."), ("Charts", "Shows labor trends, stock levels, and spending categories."), ("Quick Actions", "Use the shortcuts at the bottom to clock in, scan QR codes, or view reports.") |

For pages NOT listed above that are missing help buttons, add a generic help sheet:
```swift
PageHelpSheet(
    title: "\(PAGE_NAME) Help",
    sections: [
        ("Overview", "This page manages \(FEATURE_DESCRIPTION). Use the controls above to search, filter, and manage items."),
        ("Need Help?", "Contact your administrator or check the app documentation for detailed instructions.")
    ]
)
```

### Step 3: Full file list for help button additions

Run this grep to find ALL pages missing help buttons:
```bash
# Find Swift files with navigationTitle but no questionmark.circle
grep -rL "questionmark.circle" "Weird Parts IOS/Weird Parts IOS/Features/" --include="*.swift" | xargs grep -l "navigationTitle" | sort
```

Add help buttons to EVERY file returned by that command.

## Files to Modify

**Move existing help from secondaryAction to primaryAction:**
- `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSJobDetailTabView.swift`
- Any other files found with `secondaryAction` + `questionmark`

**Add help buttons (minimum list — the grep in Step 3 may find more):**
1. `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPOsPage.swift`
2. `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPurchaseOrdersPage.swift`
3. `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPODetailPage.swift`
4. `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSReceivingPage.swift`
5. `Weird Parts IOS/Weird Parts IOS/Features/Jobs/JobsListPage.swift`
6. `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSClockPage.swift`
7. `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSDispatchPage.swift`
8. `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSScheduleCalendarPage.swift`
9. `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsCatalogPage.swift`
10. `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSInventoryGridPage.swift`
11. `Weird Parts IOS/Weird Parts IOS/Features/People/IOSEmployeesPage.swift`
12. `Weird Parts IOS/Weird Parts IOS/Features/Fleet/IOSVehiclesPage.swift`
13. `Weird Parts IOS/Weird Parts IOS/Features/Notebooks/IOSNotebooksListPage.swift`
14. `Weird Parts IOS/Weird Parts IOS/Features/Tools/IOSToolRegistryPage.swift`
15. `Weird Parts IOS/Weird Parts IOS/Features/Dashboard/DashboardView.swift`
16. All other pages found by the grep command in Step 3

## Success Criteria

- [ ] ZERO pages have help buttons in `.secondaryAction` (overflow menu)
- [ ] Every page with a `navigationTitle` has a visible help button in the toolbar
- [ ] Help button uses `questionmark.circle` SF Symbol consistently
- [ ] Each `PageHelpSheet` has at least 2 sections with practical, non-generic content
- [ ] `PageHelpSheet` component works correctly (it already exists in `Weird Parts IOS/Weird Parts IOS/Shared/PageHelpSheet.swift`)
- [ ] No compilation errors
- [ ] No duplicate `.sheet()` modifiers on any single view
