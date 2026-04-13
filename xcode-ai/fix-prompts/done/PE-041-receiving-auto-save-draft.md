# PE-041 — Receiving Session Auto-Save Draft Persistence
# Plan: docs/plans/ios-receiving-draft-persistence.md
# GitHub Issue: #36

## Summary
Receiving sessions hold scanned quantities in @State. Any Back navigation discards all work
silently. Fix: write each quantity change to the DB immediately so sessions are always
resumable. Remove the discard confirmation dialog (auto-save makes it unnecessary).

## Files to Modify

### `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSReceiveShipmentPage.swift`

#### Step 1: Auto-save every quantity change

Find the function or code path that updates `receivedQtys` (the dictionary mapping itemId → qty).
This is used in stepper buttons, text fields, or scanner callbacks that set quantities.

After every line that mutates `receivedQtys[itemId]`, add a silent background save:

```swift
// After: receivedQtys[itemId] = newQty
Task {
    guard let svc = appCore.warehouseService, let sid = activeSessionId else { return }
    try? svc.updateReceivingItemQty(sessionId: sid, itemId: itemId, receivedQty: newQty)
}
```

If `WarehouseService` does not have `updateReceivingItemQty(sessionId:itemId:receivedQty:)` as a
standalone method, use the existing update method (see WarehouseService.swift ~line 1047-1065)
which accepts sessionId, itemId, and qty. Match the actual method signature.

#### Step 2: Verify restore-on-resume works

Find `loadSessionItems()` (or whatever function populates `sessionItems` from the DB).
Ensure it includes this restore step:

```swift
sessionItems.forEach { item in
    receivedQtys[item.id] = item.receivedQty
}
```

If this line is already present, no change needed here. If missing, add it.

#### Step 3: Remove the discard confirmation dialog

Find `showDiscardConfirmation` state variable and all usages:
- Remove `@State private var showDiscardConfirmation = false`
- Remove the `.confirmationDialog(...)` modifier that uses `showDiscardConfirmation`
- Change any code that sets `showDiscardConfirmation = true` to instead just dismiss directly
  (e.g., `dismiss()` or allow navigation to proceed)

Keep `isCompleting` guard as-is — we still want to block dismiss during the final completion
network/DB write. Only remove the discard confirmation.

## Verification

1. Build — zero errors
2. Test: Start a receiving session → set qty for 2+ items → navigate Back
3. Reopen the same session from the sessions list → quantities should still be present
4. Test app backgrounding: set a qty → background the app → reopen → qty preserved

## Notes

- The `receiving_sessions` table already persists the session status as 'in_progress'
- The `receiving_session_items` table already has `received_qty` column
- This is a safe change — we're just moving the write earlier, not changing the data model
- If `updateReceivingItemQty` doesn't exist as a standalone method, look for:
  - `updateReceivingItem(sessionId:itemId:receivedQty:notes:)`
  - Or any method that writes `received_qty` to `receiving_session_items`
  - Match the actual method signature found in WarehouseService.swift
