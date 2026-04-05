---
source: dev-improvement-scanner (2026-04-04)
severity: Medium
category: Performance — Closure Reference Cycles
status: open
github_issue: PENDING (gh not available, file manually)
---

# DIS-007: IOSMainView NotificationCenter Closure Captures Strong References

## Problem
`IOSMainView` subscribes to `NotificationCenter.default.publisher(for: .navigateToModule)` via `.onReceive` (around line 108). The closure captures `tabPrefs` and `appCore` by strong reference. SwiftUI's `.onReceive` modifier holds this closure for the lifetime of the view — which, for `IOSMainView` (the root), is the lifetime of the app.

While this is unlikely to cause an actual retain cycle in practice (since `IOSMainView` IS the root and never deallocated), it does mean `tabPrefs` and `appCore` cannot be freed until the app terminates. For a root view this is acceptable, but it's worth auditing whether the subscription is properly deregistered when the user logs out and the view hierarchy changes.

## File
`Weird Parts IOS/Weird Parts IOS/Navigation/IOSMainView.swift` — lines ~108-121

## Suggested Fix

Add `[weak tabPrefs, weak appCore]` capture list to the `.onReceive` closure if the compiler allows it (struct-based environment objects cannot be weakly captured). If not:

1. Convert to an explicit `AnyCancellable` stored as `@State` and cancel it in `.onDisappear`
2. Or confirm the root view is never recreated after logout (if so, the strong reference is benign)

## Questions for Owner
1. Is `IOSMainView` recreated after logout, or does it persist for the full app lifetime?
2. If it persists, the strong capture is fine — no fix needed.
3. If it is recreated, the subscription should be explicitly cancelled on disappear.

## Verification
1. Log in, navigate around
2. Log out
3. Confirm `navigateToModule` notifications no longer trigger handler from previous session
