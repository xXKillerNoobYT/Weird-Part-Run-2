# PE-051 — Dismiss Guard: Tools Sheets (Phase 1D of Dismiss-Safety Campaign)

> **Campaign**: `docs/plans/dismiss-safety-campaign.md` — Phase 1D (Parts/Tools/Settings — goes last).
> **Reference pilot**: `PE-044` (AddEmployeeSheet in `IOSEmployeesPage.swift`) — the canonical output shape.
> **GitHub issues**: #143 (interactive dismiss), #149 (keyboard dismiss — separate later campaign).
> **Priority**: Sev 2 — user can swipe-dismiss while editing (e.g., `ToolEditSheet`) and lose unsaved changes with no warning.

---

## 1. Page Overview

These sheets live in `Weird Parts IOS/Weird Parts IOS/Features/Tools/IOSToolDetailPage.swift`.
They are opened from `IOSToolDetailPage` via the `ActiveSheet` enum and handle tool checkout,
return, editing, issue reporting, trade, lost/stolen, and maintenance config. These workflows
involve real user input (notes, conditions, field edits) that should not be silently discarded
on an accidental swipe.

---

## 2. Target Sheets (5 sheets with real text input — do these in priority order)

| Sheet | Bound inputs | Why it matters |
|-------|-------------|----------------|
| `ToolEditSheet` (line 958) | `name`, `category`, `brand`, `modelNumber`, `serialNumber`, `notes` (6 TextFields) | Primary edit sheet — all fields are typed. Losing changes silently is a clear bug. |
| `ToolReportIssueSheet` (line 1084) | `issueDescription` (TextField), `severity` (Picker) | Issue descriptions can be lengthy. Silent dismiss loses the report. |
| `LostStolenReportSheet` (line 1515) | `description`, `lastLocation` (2 TextFields), `reportType` (Picker) | High-stakes report — loss is painful. |
| `MaintenanceConfigSheet` (line 1614) | `description` (TextField), numeric inputs (`Stepper`, `Slider`) | Configuration work is deliberate. |
| `ToolTradeSheet` (line 1287) | `notes` (TextField), `condition` (Picker) | Lower stakes but has typed notes. |

Sheets NOT in scope (no meaningful user-typed state to protect):
- `ToolCheckoutSheet` — notes field is optional and very short; `isSaving` guard is sufficient.
- `ToolReturnSheet` — same rationale as checkout.
- `ToolVersionHistorySheet` — read-only, no inputs.
- `ToolApproveEditSheet` — single approval action, no typed fields.
- `TradeResponseSheet` — notes optional, low-value; `isSaving` guard is sufficient.

---

## 3. Current Broken Behavior

All sheets in scope already have `.interactiveDismissDisabled(isSaving)` — which only blocks
during the save network call. A user can type extensively in `ToolEditSheet` (name, brand,
model, serial, notes) and then swipe down. iOS dismisses silently. All typed content is
thrown away with no warning or confirmation.

---

## 4. Goal of the Change

Add per-sheet dirty-tracking (`@State var isDirty`) that flips to `true` when any text field
or picker changes. Block swipe-dismiss when dirty. Show a "Discard changes?" alert when the
user taps Cancel with unsaved edits. Pattern matches PE-044 exactly.

---

## 5. Exact Code Change (apply the same pattern to each in-scope sheet)

For **each in-scope sheet struct**, add these modifications:

### a) State declarations (add near the top of the struct, after existing `@State` vars)

```swift
@State private var isDirty: Bool = false
@State private var showDiscardAlert: Bool = false
```

### b) `.onChange` watchers on every bound input

For `TextField` bindings like `$name`, add:
```swift
TextField("Name", text: $name)
    .onChange(of: name) { _, _ in isDirty = true }
```

For `Picker` selections:
```swift
Picker("Severity", selection: $severity) { ... }
    .onChange(of: severity) { _, _ in isDirty = true }
```

For `Slider` and `Stepper`, same pattern with their binding variable.

### c) Replace `.interactiveDismissDisabled(isSaving)` with:

```swift
.interactiveDismissDisabled(isDirty || isSaving)
```

### d) Rewrite the Cancel toolbar button:

```swift
ToolbarItem(placement: .cancellationAction) {
    Button("Cancel") {
        if isDirty { showDiscardAlert = true } else { dismiss() }
    }
    .disabled(isSaving)
}
```

### e) Add Discard alert (attach to the outermost `NavigationStack`):

```swift
.alert("Discard changes?", isPresented: $showDiscardAlert) {
    Button("Discard", role: .destructive) { dismiss() }
    Button("Keep Editing", role: .cancel) {}
} message: {
    Text("Your unsaved changes will be lost.")
}
```

### f) Reset `isDirty` to `false` just before the successful dismiss in the save method

In the save/submit async function, just before calling `onComplete()` or `dismiss()`,
set `isDirty = false` (prevents the discard alert from blocking programmatic dismiss
after a successful save).

---

## 6. Sheet-by-Sheet Binding Reference

### ToolEditSheet (line 958)

Bound inputs: `$name`, `$category`, `$brand`, `$modelNumber`, `$serialNumber`, `$notes`

All 6 TextFields need `.onChange(of: <binding>) { _, _ in isDirty = true }`.

### ToolReportIssueSheet (line 1084)

Bound inputs: `$issueDescription` (TextField), `$severity` (Picker)

### LostStolenReportSheet (line 1515)

Bound inputs: `$description` (TextField), `$lastLocation` (TextField), `$reportType` (Picker)

### MaintenanceConfigSheet (line 1614)

Bound inputs: `$description` (TextField), `$selectedType` (Picker), plus type-specific inputs:
- `$intervalDays` (Stepper — time_based, schedule_based)
- `$usageThreshold` (TextField — usage_based)
- `$decayRate` and `$decayFloor` (Slider — decreasing_based)
- Toggles in `conditionTriggers` (condition_triggered)

For the `Stepper` and `Slider` controls, `.onChange` works the same way.
For the `Toggle` in conditionTriggers use `.onChange(of: conditionTriggers) { _, _ in isDirty = true }` on the whole set.

### ToolTradeSheet (line 1287)

Bound inputs: `$notes` (TextField), `$condition` (Picker)

---

## 7. DO NOT Change

- Save logic, validation logic, service calls.
- Layout, colors, fonts, section structure.
- The `isSaving` guard — keep it alongside `isDirty`.
- `ToolCheckoutSheet`, `ToolReturnSheet`, `ToolVersionHistorySheet`, `ToolApproveEditSheet`, `TradeResponseSheet` — leave these untouched.

---

## 8. Acceptance Criteria

For each patched sheet:
- [ ] Open sheet, don't type anything, swipe down → dismisses cleanly (no alert, no block).
- [ ] Open sheet, type into any field, swipe down → blocked (sheet stays up).
- [ ] Open sheet, type, tap Cancel → Discard alert appears.
- [ ] Open sheet, type, tap Cancel → Discard → dismisses, data not saved.
- [ ] Open sheet, type, tap Cancel → Keep Editing → stays on sheet, content intact.
- [ ] Open sheet, type, tap Save → saves, dismisses cleanly (no discard alert).
- [ ] Picker change (severity / condition / type) marks sheet dirty just like text input.

---

## 9. Reference File

`Weird Parts IOS/Weird Parts IOS/Features/People/IOSEmployeesPage.swift` (AddEmployeeSheet struct)
is the canonical PE-044 pilot. The output of this prompt should be indistinguishable in shape
from that file's AddEmployeeSheet implementation.
