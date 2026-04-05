---
source: dev-improvement-scanner (2026-04-04)
severity: Medium
category: UX — Loading States
status: open
github_issue: PENDING (gh not available, file manually)
---

# DIS-001: Missing Loading Indicators on 3 Pages

## Problem
Three pages flash empty content before data loads. No loading indicator during initial `.task` fetch.

## Affected Files

1. **`Features/People/IOSContractorDetailPage.swift:55`**
   - Loads: rating, jobHistory, notes from DB
   - Has `loadError` state but no spinner on initial load
   - User sees "No ratings yet", "No notes yet" before data arrives

2. **`Features/Jobs/IOSEstimationReviewPage.swift:89`**
   - Loads: `reviews`, `latestEstimate`
   - Renders empty state immediately before data arrives

3. **`Features/Office/IOSEstimationSettingsPage.swift:118`**
   - Loads config data with no spinner shown

## Fix (paste into Xcode AI)

For each of the 3 files above, apply this pattern:

Add `@State private var isLoading = true` to the view's state section.

Wrap the main content body in:
```swift
if isLoading {
    ProgressView("Loading...")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
} else {
    // existing content here
}
```

At the end of the `.task` body, set `isLoading = false` in both the success and error/catch branches.

## Reference Pattern
`IOSNotebookDetailPage.swift:55-63` — already uses this exact pattern correctly.

## Verification
1. Open each page on a device or simulator
2. Confirm a loading spinner shows briefly before content appears
3. Confirm no flash of empty state before data loads
