---
source: dev-improvement-scanner (2026-04-04)
severity: Medium
category: Performance — Closure Reference Cycles
status: closed — non-issue (owner confirmed 2026-04-04)
github_issue: N/A — resolved, no fix needed
---

# DIS-007: IOSMainView NotificationCenter Closure Captures Strong References

## Problem
`IOSMainView` subscribes to `NotificationCenter.default.publisher(for: .navigateToModule)` via `.onReceive` (around line 108). The closure captures `tabPrefs` and `appCore` by strong reference. SwiftUI's `.onReceive` modifier holds this closure for the lifetime of the view — which, for `IOSMainView` (the root), is the lifetime of the app.

While this is unlikely to cause an actual retain cycle in practice (since `IOSMainView` IS the root and never deallocated), it does mean `tabPrefs` and `appCore` cannot be freed until the app terminates. For a root view this is acceptable, but it's worth auditing whether the subscription is properly deregistered when the user logs out and the view hierarchy changes.

## File
`Weird Parts IOS/Weird Parts IOS/Navigation/IOSMainView.swift` — lines ~108-121

## Resolution (2026-04-04)

**Owner confirmed:** `IOSMainView` IS destroyed on logout. `WiredPartIOSApp.swift` uses a conditional `if/else` on `appCore.currentUser` — when `logout()` sets `currentUser = nil`, SwiftUI removes `IOSMainView` entirely and shows `LoginView`. On next login, a fresh `IOSMainView` is created.

**Result:** The `.onReceive` subscription is automatically cancelled when the view is deallocated. No code change required.

**Remaining action:** Add a code comment in `IOSMainView.swift` near the `.onReceive` block explaining this is safe because the view is torn down on logout via the conditional rebuild in `WiredPartIOSApp.swift`. This prevents future developers from re-flagging it.
