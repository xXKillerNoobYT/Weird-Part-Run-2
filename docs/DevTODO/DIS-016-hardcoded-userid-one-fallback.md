---
source: dev-improvement-scanner (2026-04-10)
severity: High
category: Code Quality — Hardcoded User ID Fallback (?? 1 variant)
status: fixed — page-rebuild-enforcer run 2026-04-10
github_issue: "#140 — filed 2026-04-10, fix applied directly"
---

# DIS-016: `currentUser?.id ?? 1` Anti-Pattern in 7 Write-Operation Files

## Problem

Seven iOS files use `appCore.currentUser?.id ?? 1` where `1` is passed to a DB write
operation as `userId`, `createdBy`, `performedBy`, or `resolvedBy`. This is **worse** than
the `?? 0` pattern fixed in DIS-015: the fallback `1` is the admin user's actual ID, meaning
unauthenticated writes are silently attributed to the admin, corrupting audit trails.

## Affected Locations

| File | Line | Operation |
|------|------|-----------|
| `Features/Chat/IOSMessageThreadView.swift` | 370 | `autoSaveToJobNotebook(userId:)` — redundant re-fetch; outer `sendMessage()` already guards `let userId` at line 347. Just use `userId` directly. |
| `Features/People/IOSCustomerDetailPage.swift` | 535 | `addCommunicationEntry(createdBy:)` — hard write |
| `Features/People/IOSCustomerDetailPage.swift` | 607 | `createPaymentRecord(createdBy:)` — hard write |
| `Features/People/IOSContractorDetailPage.swift` | 343 | `addContractorNote(createdBy:)` — hard write |
| `Features/Orders/IOSProcurementPage.swift` | 934 | warehouse pull write operation |
| `Features/Notebooks/IOSNotebookDetailPage.swift` | 887 | `createBlockEntry(createdBy:)` — hard write |
| `Features/Warehouse/IOSAuditSetupView.swift` | 211 | `createAuditSession(userId:)` — hard write |

## Fix Pattern

For each write path replace:
```swift
let userId = appCore.currentUser?.id ?? 1
```
With:
```swift
guard let userId = appCore.currentUser?.id else {
    errorMessage = "Not logged in. Please log in and try again."
    return
}
```

**Special case — IOSMessageThreadView line 370:**
The outer `sendMessage()` function already captures `userId` via `guard let userId = appCore.currentUser?.id` at line 347. Change:
```swift
try? service.autoSaveToJobNotebook(channelId: channelId, attachment: saved, userId: appCore.currentUser?.id ?? 1)
```
To:
```swift
try? service.autoSaveToJobNotebook(channelId: channelId, attachment: saved, userId: userId)
```

## Xcode AI Prompt

Paste into Xcode AI to fix all 7 locations:

```
Fix the `currentUser?.id ?? 1` anti-pattern in these iOS files.

For each location, replace `let userId = appCore.currentUser?.id ?? 1` with a proper guard
that returns early and shows an error if the user is not logged in.

Files to update:
- Features/People/IOSCustomerDetailPage.swift lines 535 and 607 (AddCommunicationSheet.save() and AddPaymentSheet.save())
- Features/People/IOSContractorDetailPage.swift line 343 (AddContractorNoteSheet.save())
- Features/Orders/IOSProcurementPage.swift line 934 (pullFromWarehouse())
- Features/Notebooks/IOSNotebookDetailPage.swift line 887 (savePanelSchedule())
- Features/Warehouse/IOSAuditSetupView.swift line 211 (createAudit())

Special case:
- Features/Chat/IOSMessageThreadView.swift line 370 — the outer sendMessage() already has
  `guard let userId = appCore.currentUser?.id` at line 347. Change the inner ?? 1 call to
  just use `userId` (the already-captured guard variable) without re-fetching.

For all write paths use `guard let userId = appCore.currentUser?.id else { ... }`.
Use the context-appropriate error field name (errorMessage, actionError, etc.).
```

## Verification

1. All 7 files compile with no new errors
2. The `?? 1` pattern no longer appears in any write path in these files
3. Each write operation now shows an error to the user when session is unavailable
4. IOSMessageThreadView line 370 uses the captured `userId` from the outer guard
