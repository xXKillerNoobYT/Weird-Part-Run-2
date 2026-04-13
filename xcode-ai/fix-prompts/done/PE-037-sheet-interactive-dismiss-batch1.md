# PE-037: Sheet Safety Batch 1 — Add interactiveDismissDisabled to 9 Create/Form Sheets

**Priority:** High (Usability — prevents accidental data loss during active saves)
**Source:** usability-hunter run 2026-04-05
**GitHub Issue:** #123 (systemic — 163 sheets missing interactiveDismissDisabled)
**Files:** 9 sheets (all already have `isSaving` — just missing the guard)

---

## Problem

These 9 sheets all have `@State private var isSaving = false` but are missing `.interactiveDismissDisabled(isSaving)`. This means users can swipe down and dismiss the sheet while a save is in progress, losing their data and potentially leaving partial records.

`IOSCreateJobSheet.swift` is already correct and serves as the reference pattern.

---

## The Fix Pattern

In each file, find the main view's body modifier chain (usually after `.navigationTitle(...)`) and add:

```swift
.interactiveDismissDisabled(isSaving)
```

This is a **one-line change per file**. The `isSaving` variable already exists and is already toggled correctly in each file's save function.

---

## Files to Modify

### 1. `Features/Orders/CreatePOSheet.swift`
Add `.interactiveDismissDisabled(isSaving)` to the NavigationStack or Form modifier chain.

### 2. `Features/Scheduling/CreateDispatchSheet.swift`
Add `.interactiveDismissDisabled(isSaving)` to the Form or NavigationStack modifier chain.

### 3. `Features/Fleet/IOSCreateVehicleSheet.swift`
Add `.interactiveDismissDisabled(isSaving)` to the Form or NavigationStack modifier chain.

### 4. `Features/Orders/CreateReturnSheet.swift`
Add `.interactiveDismissDisabled(isSaving)` to the Form or NavigationStack modifier chain.

### 5. `Features/Notebooks/CreateNotebookSheet.swift`
Add `.interactiveDismissDisabled(isSaving)` to the Form or NavigationStack modifier chain.

### 6. `Features/Fleet/IOSCreateTrailerSheet.swift`
Add `.interactiveDismissDisabled(isSaving)` to the Form or NavigationStack modifier chain.

### 7. `Features/Scheduling/RequestTimeOffSheet.swift`
Add `.interactiveDismissDisabled(isSaving)` to the Form or NavigationStack modifier chain.

### 8. `Features/Parts/CascadePriceEditSheet.swift`
Add `.interactiveDismissDisabled(isSaving)` to the Form or NavigationStack modifier chain.

### 9. `Features/Chat/CreateChannelSheet.swift`
Add `.interactiveDismissDisabled(isSaving)` to the Form or NavigationStack modifier chain.

---

## Reference: IOSCreateJobSheet.swift (already correct)

This file already has the pattern. Use it as a reference for placement. Look for where it places `.interactiveDismissDisabled(isSaving)` in the view hierarchy.

---

## What NOT to Change

- Do NOT change `isSaving` toggle logic — it's already correct in each file
- Do NOT change button disable states — those are already in place
- Do NOT change any form fields, sections, or navigation logic
- Only add the single `.interactiveDismissDisabled(isSaving)` modifier

---

## Verification

For each file, confirm:
1. The modifier is present in the view hierarchy
2. It references the existing `isSaving` variable (not a new variable)
3. Build still compiles with 0 errors

---

## Notes

- This is Batch 1 of the systemic fix for GitHub #123 (163 sheets need this)
- Batch 2 (PE-038, future) will cover Edit sheets and settings pages
- The systemic issue tracker: GitHub #121 (try?), #122 (guard-let), #123 (sheets)
