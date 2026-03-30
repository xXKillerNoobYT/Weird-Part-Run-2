# 67A — Fix User Attribution in Audit Session and Chat→Notebook Auto-Save

## Problem

Two iOS call sites pass user actions to core services that now accept a `userId` parameter, but the caller doesn't yet supply it. Both currently fall back to the default `userId = 1` (admin), attributing the action to the wrong user.

### Call Site 1: `IOSAuditSetupView.swift` line ~203

```swift
let sessionId = try service.createAuditSession(
    scope: auditScope.scopeKey,
    zone: selectedZone.isEmpty ? nil : selectedZone,
    sampleSize: auditScope == .spotCheck ? spotCheckCount : nil,
    includeZeroStock: includeZeroStock,
    notes: notes.isEmpty ? nil : notes
    // ← missing: userId: appCore.session?.userId ?? 1
)
```

**Fix:** Add `userId: appCore.session?.userId ?? 1` as the last argument.

### Call Site 2: `IOSMessageThreadView.swift` line ~362

```swift
try? service.autoSaveToJobNotebook(channelId: channelId, attachment: saved)
// ← missing: userId: appCore.session?.userId ?? 1
```

**Fix:** Add `userId: appCore.session?.userId ?? 1` as the last argument.

## Files to Edit

- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSAuditSetupView.swift` (~line 203)
- `Weird Parts IOS/Weird Parts IOS/Features/Chat/IOSMessageThreadView.swift` (~line 362)

## Session Access Pattern

Both views use `@EnvironmentObject var appCore: AppCore` (or `@StateObject`). Check the existing pattern in the file for how `appCore.session` is accessed — it varies slightly but is always available on views that require login.

Common patterns found in the codebase:
```swift
appCore.session?.userId        // optional Int64
appCore.currentUserId          // non-optional if available
```

Use whichever pattern matches what's already in the file. Default to `?? 1` if optional.

## Why This Matters

- Audit sessions show "started by" on the audit dashboard — wrong user makes it look like admin ran everything
- Notebook entries show authorship for change tracking and sync attribution — wrong user breaks the accountability trail

## Apple HIG / Code Quality

No HIG concerns. Pure data integrity fix.

## Verification

After fixing, start an audit as a non-admin user and verify the session shows the correct user's name in the audit log.
