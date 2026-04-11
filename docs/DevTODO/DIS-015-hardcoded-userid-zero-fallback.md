---
source: dev-improvement-scanner (2026-04-09)
severity: Medium
category: Code Quality — Hardcoded User ID Fallback
status: partially-fixed — write paths resolved 2026-04-10 (hunt-fix-verify run 36)
github_issue: "#139 — filed 2026-04-09, write-path fix comment posted 2026-04-10"
---

# DIS-015: `currentUser?.id ?? 0` Anti-Pattern in Write Operations

## Problem

Six files use `appCore.currentUser?.id ?? 0` where `0` is passed to a DB write operation
as a `userId`, `completedBy`, or `resolvedBy` parameter. A fallback of `0` silently records
a non-existent user as the author of an action, violating data integrity. The project's
anti-pattern rule (feedback_hardcoded_user_ids.md) explicitly forbids this.

**Already fixed:** `IOSReceiveShipmentPage.swift:922` — `completeSession(completedBy:)` now
uses `guard let userId = appCore.currentUser?.id else { actionError = ...; return }`.

## Fixed (hunt-fix-verify run 36, 2026-04-10)

| File | Line | Status |
|------|------|--------|
| `Features/Jobs/IOSWeeklyReviewSheet.swift` | 336 | ✅ Fixed — `guard let userId` with `submitError` display |
| `Features/Warehouse/IOSAuditSummaryView.swift` | 337 | ✅ Fixed — merged into existing guard block |
| `Features/Warehouse/ReceivingRoutingFlow.swift` | 1043, 1072, 1103, 1132 | ✅ Fixed — all 4 routing writes use guard, ternary error message |

## Remaining Locations (read-only — acceptable)

| File | Line | Write Operation |
|------|------|-----------------|
| `AI/IOSAIAssistantPanel.swift` | 546 | AI session/history query — read, returns empty if uid=0 |
| `Features/Scheduling/IOSFlexPoolPage.swift` | 34 | Load flex pool items — read, returns empty list |
| `Features/Parts/PartsCompanionsPage.swift` | 872 | `getActivePolls`/`getLastWeekResults` — read, returns empty |

## Suggested Fix (per file)

For each write path, replace:
```swift
let userId = appCore.currentUser?.id ?? 0
```
With:
```swift
guard let userId = appCore.currentUser?.id else {
    // show error or return silently depending on context
    someErrorState = "Not logged in. Please log in and try again."
    return
}
```

For reads (IOSFlexPoolPage line 34), the pattern is acceptable since it's filtering
results for a user — an unauthenticated state would show an empty result, not corrupt data.

## Xcode AI Prompt

Paste into Xcode AI to fix all remaining locations in one pass:

```
Fix the `currentUser?.id ?? 0` anti-pattern in these 6 iOS files.

For each write operation, replace `let userId = appCore.currentUser?.id ?? 0`
with a proper guard that returns early and shows an error if the user is not logged in.

Files to update:
- AI/IOSAIAssistantPanel.swift:546
- Features/Jobs/IOSWeeklyReviewSheet.swift:336
- Features/Warehouse/ReceivingRoutingFlow.swift:1043, 1072, 1103, 1132
- Features/Warehouse/IOSAuditSummaryView.swift:337
- Features/Parts/PartsCompanionsPage.swift:872

Skip: IOSFlexPoolPage.swift:34 — that's a read operation, `?? 0` returns an empty list, no data corruption.

Use `guard let userId = appCore.currentUser?.id else { ... }` for all write paths.
For the routing flow (4 locations in ReceivingRoutingFlow), show a dismissal or route to
an error state since the routing sheet can't easily show an inline error.
```

## Verification

1. All 6 files compile with no new errors
2. For each fixed write operation, verify the auth guard fires when `currentUser` is nil
3. Confirm that the `?? 0` pattern no longer appears in any write path in these files
