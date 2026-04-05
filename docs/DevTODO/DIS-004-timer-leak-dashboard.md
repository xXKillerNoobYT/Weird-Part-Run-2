---
source: dev-improvement-scanner (2026-04-04)
severity: Medium
category: Performance — Timer Lifecycle
status: open
github_issue: PENDING (gh not available, file manually)
---

# DIS-004: Timer Continues Firing After DashboardDailyReportPage Is Popped

## Problem
`DashboardDailyReportPage` creates a `Timer.publish(every: 60, ...).autoconnect()` timer at the type level (line 44) and spawns `Task { await loadData() }` on each tick. When the page is pushed via navigation and then popped, the timer continues to fire (since the tab bar keeps the parent alive), spawning orphan Tasks against a deallocated view context.

## File
`Features/Jobs/DashboardDailyReportPage.swift:44, 131`

## Fix (paste into Xcode AI)

Add an `.onDisappear` modifier to `DashboardDailyReportPage`'s main view to cancel the timer subscription:

```swift
// Store the timer cancellable
@State private var timerCancellable: Cancellable?

// In .onAppear:
.onAppear {
    timerCancellable = refreshTimer.sink { _ in
        Task { await loadData() }
    }
}
// In .onDisappear:
.onDisappear {
    timerCancellable?.cancel()
    timerCancellable = nil
}
```

Replace the current `.onReceive(refreshTimer)` pattern with the above Combine sink/cancellable approach so the timer subscription can be explicitly cancelled on disappear.

## Verification
1. Open the dashboard page
2. Navigate away (push another page)
3. Confirm no further loadData() calls are made (add a print statement temporarily)
4. Return to the page — confirm loadData() resumes
