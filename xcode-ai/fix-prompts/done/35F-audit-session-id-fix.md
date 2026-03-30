# 35F — Fix Hardcoded Audit Session ID + PO Delete Navigation

> **Chain position:** **35F** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Context

**Bug 1:** IOSAuditSummaryView calls `service.finalizeAuditSession(sessionId: 0)` — hardcoded session ID 0 means it finalizes the WRONG session. Should use the actual active session ID.

**Bug 2:** IOSPODetailPage — after `deleteDraftPO()` succeeds, the page shows "Draft deleted" but doesn't navigate back. User is stuck on a detail page for a deleted PO.

**Bug 3:** IOSApprovalsPage — `rejectJPO()` accepts a `reason` parameter but never passes it to the service. Rejection reasons are discarded.

## Files to Modify

1. `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSAuditSummaryView.swift` — fix session ID
2. `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPODetailPage.swift` — navigate back after delete
3. `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSApprovalsPage.swift` — pass rejection reason

## Task

### 1. Fix Audit Session ID
The summary view should receive the active session ID from the parent (IOSAuditPage):
```swift
// IOSAuditSummaryView should have:
let sessionId: Int64  // passed from parent

// Replace:
try service.finalizeAuditSession(sessionId: 0)
// With:
try service.finalizeAuditSession(sessionId: sessionId)
```

### 2. Navigate Back After PO Delete
After `deleteDraftPO()` succeeds, dismiss the detail page:
```swift
private func deleteDraftPO() async {
    // ... existing delete logic ...
    // After success:
    await MainActor.run {
        dismiss()  // Go back to PO list
    }
}
```

### 3. Pass Rejection Reason
In `rejectJPO()`, pass the reason to the service:
```swift
try service.updateJPOStatus(id: jpoId, status: "rejected", reason: reason)
```
If the service method doesn't accept a `reason` parameter, add it.

## Success Criteria

- [ ] Audit finalize uses actual session ID, not 0
- [ ] PO detail navigates back after draft deletion
- [ ] JPO rejection reason saved to database
- [ ] Project builds with no errors
