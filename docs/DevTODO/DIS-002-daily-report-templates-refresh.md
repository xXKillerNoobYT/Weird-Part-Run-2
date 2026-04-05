---
source: dev-improvement-scanner (2026-04-04)
severity: Medium
category: UX — Pull-to-Refresh
status: open
github_issue: PENDING (gh not available, file manually)
---

# DIS-002: Missing Pull-to-Refresh on Daily Report Templates Page

## Problem
`IOSDailyReportTemplatesPage` loads live template data and shows a ProgressView on first load, but has no `.refreshable`. If data is stale or a load fails, users can't retry without leaving the page.

## File
`Features/Settings/IOSDailyReportTemplatesPage.swift` — two List views at lines 78 and 166

## Fix (paste into Xcode AI)

Add `.refreshable { loadData() }` to the top-level `List` or `Group` that wraps both lists in `IOSDailyReportTemplatesPage`.

If the page uses two separate `List` views rather than one, wrap them in a `List { }` or add `.refreshable` to both individually.

## Verification
1. Open Settings → Daily Report Templates
2. Pull down on the list
3. Confirm it triggers a reload and the spinner appears
