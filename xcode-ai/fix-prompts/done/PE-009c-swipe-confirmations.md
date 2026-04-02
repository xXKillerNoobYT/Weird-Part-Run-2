# Fix Prompt PE-009c: Swipe-to-Delete Confirmation Dialogs

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.

---

## The Problem (User Perspective)

5 pages let users swipe-to-delete without any confirmation. One accidental swipe permanently deletes a report, checklist item, or storage unit with no way to undo. This is a data safety issue.

**GitHub Issue:** #13
**PE Tracker:** PE-009c

---

## The Pattern to Follow

Use the pattern already established in `IOSReportTemplatesPage.swift`:

```swift
// 1. Add a state variable for the candidate item
@State private var deleteCandidate: YourItemType? = nil

// 2. In the swipe action, set the candidate instead of deleting directly
.swipeActions(edge: .trailing, allowsFullSwipe: false) {
    Button(role: .destructive) {
        deleteCandidate = item  // set candidate, DON'T delete yet
    } label: {
        Label("Delete", systemImage: "trash")
    }
}

// 3. Add an alert that fires when candidate is set
.alert("Delete \(deleteCandidate?.name ?? "Item")?", isPresented: Binding(
    get: { deleteCandidate != nil },
    set: { if !$0 { deleteCandidate = nil } }
)) {
    Button("Delete", role: .destructive) {
        if let item = deleteCandidate {
            deleteItem(item)  // actual deletion
        }
        deleteCandidate = nil
    }
    Button("Cancel", role: .cancel) {
        deleteCandidate = nil
    }
} message: {
    Text("This cannot be undone.")
}
```

---

## Files to Fix

### 1. IOSReportsRouter.swift — line ~362

Deletes saved reports immediately on swipe. Apply the pattern above.
- The item type is a saved report (has a `name` or `title` property)
- Alert message: `"Delete Report?"` / `"This report will be permanently deleted."`

### 2. IOSPreTripChecklistPage.swift — line ~176

Deletes checklist items immediately on swipe.
- Item type is a checklist item (has a `question` or `title` property)
- Alert message: `"Remove Checklist Item?"` / `"This item will be removed from the template."`

### 3. AddNotebookEntrySheet.swift — line ~173

Removes checklist items immediately on swipe within a notebook entry.
- Alert message: `"Remove Item?"` / `"This checklist item will be removed."`

### 4. WarehouseWizardStep2.swift — line ~49

Deletes storage units immediately during warehouse setup.
- This is during setup/wizard flow — still needs confirmation since it removes configuration
- Alert message: `"Delete Storage Unit?"` / `"This unit and its configuration will be removed."`

### 5. IOSClockOutQuestionsPage.swift — line ~59

Deletes clock-out questions immediately. There is already an alert at line ~104 but it is bypassed by the direct deletion at line 59.
- Fix: remove the direct deletion at line 59 and route through the existing confirmation alert

---

## What NOT to Change

- IOSReportTemplatesPage.swift — already uses the correct pattern (this is your reference)
- Any `.onDelete` handlers that are already guarded by an alert
- Non-destructive swipe actions (e.g. "Archive", "Edit")

---

## Verification

After all fixes:
1. Build — 0 errors
2. In simulator: swipe to delete on each fixed page — an alert should appear before anything is deleted
3. Tap Cancel — nothing should be deleted
4. Tap Delete — item is deleted

---

## Done Criteria

- All 5 identified swipe-to-delete actions require explicit confirmation
- Cancel discards the deletion
- No immediate deletions remain in these files
- Project builds without errors
