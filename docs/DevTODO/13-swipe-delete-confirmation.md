# Add Confirmation Dialogs for Swipe-to-Delete
**GitHub Issue:** #13
**Priority:** Medium
**Estimated effort:** Quick (10 min)

## What's Wrong
5 pages delete data immediately on swipe without asking "Are you sure?" Users can accidentally delete important data.

## Files to Change

### Pattern to Follow
Look at `IOSReportTemplatesPage.swift` for the correct pattern:
```swift
@State private var deleteCandidate: ItemType? = nil

// In the List row:
.swipeActions(edge: .trailing) {
    Button(role: .destructive) {
        deleteCandidate = item
    } label: {
        Label("Delete", systemImage: "trash")
    }
}

// On the view:
.alert("Delete Item?", isPresented: .init(
    get: { deleteCandidate != nil },
    set: { if !$0 { deleteCandidate = nil } }
)) {
    Button("Delete", role: .destructive) {
        if let item = deleteCandidate {
            // actual delete here
        }
        deleteCandidate = nil
    }
    Button("Cancel", role: .cancel) { deleteCandidate = nil }
} message: {
    Text("This cannot be undone.")
}
```

### 1. `Features/Reports/IOSReportsRouter.swift:362`
**AI Prompt:** `In IOSReportsRouter.swift, find the .onDelete handler that calls deleteReports(at:). Replace it with a swipe-to-delete pattern that sets a deleteCandidate state, shows a confirmation alert, and only deletes on confirm.`

### 2. `Features/Settings/IOSPreTripChecklistPage.swift:176`
**AI Prompt:** `In IOSPreTripChecklistPage.swift, find the .onDelete handler that calls deleteItems. Add a confirmation alert before actually deleting.`

### 3. `Features/Notebooks/AddNotebookEntrySheet.swift:173`
**AI Prompt:** `In AddNotebookEntrySheet.swift, find where checklist items are removed on swipe. Add a confirmation dialog.`

### 4. `Features/Warehouse/WarehouseWizardStep2.swift:49`
**AI Prompt:** `In WarehouseWizardStep2.swift, find deleteUnits and add a confirmation alert before deleting storage units.`

### 5. `Features/Settings/IOSClockOutQuestionsPage.swift:59`
**AI Prompt:** `In IOSClockOutQuestionsPage.swift, the .onDelete at line 59 bypasses the alert at line 104. Fix it so ALL delete paths go through the confirmation alert.`

## How to Verify
1. Build and run
2. On each page, swipe to delete an item
3. A confirmation dialog should appear
4. Press Cancel — item stays
5. Swipe again, press Delete — item is removed

## AI REPORT

All 5 items done, project builds clean. Here's the summary:

| # | File | Change |
|---|------|--------|
| 1 | IOSReportsRouter.swift􀰓 | Already had confirmation dialog — no change needed |
| 2 | IOSPreTripChecklistPage.swift􀰓 | .on​Delete now sets delete​Item​Section​Id/delete​Item​Offsets and shows a "Delete Item?" alert before calling delete​Items |
| 3 | AddNotebookEntrySheet.swift􀰓 | .on​Delete now sets delete​Checklist​Offsets and shows a "Remove Item?" alert before calling checklist​Items​.remove(at​Offsets:) |
| 4 | WarehouseWizardStep2.swift􀰓 | Already had confirmation dialog — no change needed |
| 5 | IOSClockOutQuestionsPage.swift􀰓 | Replaced .on​Delete(perform: delete​Questions) with .delete​Disabled(true) — the swipe-action Delete button at line 142 already routes through the confirmation alert, so this removes the bypass path |
