---
source: dev-improvement-scanner (2026-04-05)
severity: Low
category: Code Quality — Force Unwraps
status: CLOSED — already fixed in code (verified 2026-04-06, hunt-fix iteration 30)
github_issue: PENDING (gh not available, file manually)
---

# DIS-011: Force Unwraps Guarded by Ternary Nil Checks

## Problem
Two files use force-unwrap (`!`) in ternary conditions that pre-check for `nil`.
While technically safe (the condition guarantees non-nil), this is fragile — if the
ternary condition is ever refactored, the force unwrap becomes a crash risk.

| File | Line | Code |
|------|------|------|
| `Features/Warehouse/WizardStepPlacement.swift` | 142 | `placedUnit != nil ? "\(placedUnit!.name)..."` |
| `Features/Scheduling/IOSScheduleConfigPage.swift` | 122 | `existing != nil ? { deleteShiftTemplate(existing!.id) } : nil` |
| `Features/Scheduling/IOSScheduleConfigPage.swift` | 129 | `existing != nil ? { deleteHoliday(existing!.id) } : nil` |

## Fix (paste into Xcode AI)

### WizardStepPlacement.swift:142

```swift
// BEFORE
.accessibilityLabel(placedUnit != nil ? "\(placedUnit!.name) at row \(row), column \(col)" : "Empty cell at row \(row), column \(col)")

// AFTER
.accessibilityLabel(placedUnit.map { "\($0.name) at row \(row), column \(col)" } ?? "Empty cell at row \(row), column \(col)")
```

### IOSScheduleConfigPage.swift:122 and 129

```swift
// BEFORE
onDelete: existing != nil ? { deleteShiftTemplate(existing!.id) } : nil

// AFTER
onDelete: existing.map { tpl in { deleteShiftTemplate(tpl.id) } }
```

```swift
// BEFORE
onDelete: existing != nil ? { deleteHoliday(existing!.id) } : nil

// AFTER
onDelete: existing.map { hol in { deleteHoliday(hol.id) } }
```

## Verification
All three usages compile without `!` and behave identically.
