# PE-036: Wizard Safety Hardening — interactiveDismissDisabled + Validation + Error Feedback

**Priority:** High (Usability — data loss prevention)
**Source:** usability-hunter run 2026-04-05
**GitHub Issues:** #115 (WarehouseOnboardingWizard), #116 (PartsFlowWizard), #119 (IOSMovementWizard)
**Files:** 3 wizard files

---

## Problem Summary

Three wizards have safety gaps that risk data loss or silent failures:

1. **IOSMovementWizard** (#119): The Cancel button dismisses immediately even while `isExecuting = true`. There is also no validation that quantities are > 0 before proceeding to the execute step.

2. **WarehouseOnboardingWizard** (#115): All save calls use `try?` which silently swallows errors. There is no `isSaving` state, no `interactiveDismissDisabled` during saves, and no user feedback on save failure.

3. **PartsFlowWizard** (#116): The wizard auto-dismisses immediately after save without confirming success. There is no error feedback on save failure. Draft saves use `try?` silently.

---

## Fix 1: `IOSMovementWizard.swift`

### A — Disable Cancel during execution

Find the Cancel toolbar button (around line 89):
```swift
Button("Cancel") { dismiss() }
```
Replace with:
```swift
Button("Cancel") { dismiss() }
    .disabled(isExecuting)
```

### B — Add quantity validation before step advance

In the step-advance logic for the parts selection step, before allowing the user to proceed to the review/execute step, validate that at least one part has been selected with a quantity > 0. If not, show an inline error:

Add state variable near other `@State` vars:
```swift
@State private var showQtyValidationError = false
```

In the "Next" button action for the parts step (where `currentStep` is incremented), wrap with validation:
```swift
// Before advancing to step 3 (review/execute):
guard !selectedParts.isEmpty else {
    showQtyValidationError = true
    return
}
guard selectedParts.allSatisfy({ $0.qty > 0 }) else {
    showQtyValidationError = true
    return
}
showQtyValidationError = false
currentStep += 1
```

Add an alert for validation failure after the existing alerts:
```swift
.alert("Quantity Required", isPresented: $showQtyValidationError) {
    Button("OK", role: .cancel) { }
} message: {
    Text("Enter a quantity greater than 0 for each selected part before continuing.")
}
```

---

## Fix 2: `WarehouseOnboardingWizard.swift`

### A — Add isSaving state

Near the top `@State` declarations, add:
```swift
@State private var isSaving = false
@State private var saveError: String?
```

### B — Add interactiveDismissDisabled

On the main view body (the outermost `NavigationStack` or `Form`), add:
```swift
.interactiveDismissDisabled(isSaving)
```

### C — Wrap save calls in proper error handling

Find any `try?` calls for wizard save operations (zone saves, location saves, step completions). Replace the pattern:
```swift
try? service.someWizardSave(...)
```
With:
```swift
do {
    isSaving = true
    try service.someWizardSave(...)
    isSaving = false
} catch {
    isSaving = false
    saveError = error.localizedDescription
}
```

### D — Show save error alert

If no existing alert for `saveError`, add after the view modifiers:
```swift
.alert("Save Failed", isPresented: .init(
    get: { saveError != nil },
    set: { if !$0 { saveError = nil } }
)) {
    Button("OK", role: .cancel) { }
} message: {
    Text(saveError ?? "An error occurred. Please try again.")
}
```

### E — Disable navigation buttons during save

Find the "Next" / "Continue" / "Finish" buttons. Add `.disabled(isSaving)` to each.

---

## Fix 3: `PartsFlowWizard.swift`

### A — Add isSaving state and error state

Near the top `@State` declarations, add:
```swift
@State private var isSaving = false
@State private var saveError: String?
```

### B — Add interactiveDismissDisabled

On the main view body, add:
```swift
.interactiveDismissDisabled(isSaving)
```

### C — Wrap the final save call in proper error handling

Find the `saveAllProgress(clearDraft:)` function and any `dismiss()` calls that follow a save operation. Replace the pattern where save+dismiss happen together (e.g., in the "Save & Exit" toolbar button):

```swift
// BEFORE:
Button("Save & Exit") {
    saveAllProgress(clearDraft: false)
    dismiss()
}

// AFTER:
Button("Save & Exit") {
    Task {
        isSaving = true
        do {
            try saveAllProgressThrowing(clearDraft: false)
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            saveError = error.localizedDescription
        }
    }
}
.disabled(isSaving)
```

If `saveAllProgress` is a sync function that uses `try?` internally, convert it to a throwing function so the error can surface.

### D — Show save error alert

Add after the view modifiers:
```swift
.alert("Save Failed", isPresented: .init(
    get: { saveError != nil },
    set: { if !$0 { saveError = nil } }
)) {
    Button("OK", role: .cancel) { }
} message: {
    Text(saveError ?? "Progress could not be saved. Please try again.")
}
```

---

## Verification

For each wizard:
1. Trigger a save operation and immediately swipe down on the sheet — the sheet should resist dismissal while `isSaving = true`
2. Simulate a failed save (if possible via a test DB state) — an alert should appear with the error
3. For IOSMovementWizard: try tapping "Next" with no parts selected or qty = 0 — the validation alert should appear
4. For IOSMovementWizard: tap "Execute" then immediately try "Cancel" — the Cancel button should be disabled

---

## Notes

- Do NOT change the visual design of the wizards — these are safety guards only
- `interactiveDismissDisabled` should only be true during active saves, not while the user is filling in fields
- Keep all existing step navigation logic intact; only add guards and error feedback
