# PE-003: Flex Pool — Scheduling Tab UI

**Priority:** Medium
**Plan:** `docs/plans/ios-flex-pool.md`
**GitHub Issue:** #44
**Core Status:** ✅ DONE — Migration 071 + SchedulingService methods + 6 tests (2026-04-04)

---

## What This Does

Workers can browse and self-claim "flex pool" jobs — jobs that managers have made available for anyone qualified to pick up. This reduces dispatcher overhead for routine tasks.

All core Swift code is already done:
- Migration 071: `is_flex_pool`, `flex_pool_team_filter`, `flex_pool_user_filter` columns on jobs table
- `FlexPoolJob` struct in `SchedulingModels.swift`
- `fetchFlexPool(userId:)`, `claimFlexJob(jobId:userId:)`, `markJobFlexPool(...)` in `SchedulingService.swift`

**This prompt is UI only.**

---

## Files to Modify

### 1. `Features/Scheduling/IOSDispatchPage.swift` (or IOSSchedulingPage.swift — whichever is the active scheduling view)

Locate the Scheduling page. It currently has Dispatch and Calendar tabs. **Add a third tab: "Flex Pool"**.

The Flex Pool tab shows:
- List of `FlexPoolJob` items, loaded via `schedulingService.fetchFlexPool(userId: appCore.currentUser?.id ?? 0)`
- Each row: job name (headline), job number (caption), address if present, estimated hours if present
- **"Claim" button** on the trailing side of each row (prominent, primary color)
- Tapping "Claim" shows a confirmation dialog: "Claim [job name]? You will be assigned as lead." with Confirm and Cancel buttons
- On Confirm: call `schedulingService.claimFlexJob(jobId: job.id, userId: appCore.currentUser?.id ?? 0)`
- After successful claim: navigate to job detail page for that job, or show a success alert
- If `job.isApprovalRequired == true`: show "Request Sent" / "Pending Approval" row after claiming (use orange tint + text label for accessibility)

If the list is empty: show an empty state — "No flex pool jobs available right now. Check back later."

Gate the tab visibility with: `appCore.currentUser?.hasPermission("self_assign_flex") == true` (if false, hide the tab entirely).

Add `.refreshable` to the flex pool list.

### 2. `Features/Jobs/IOSJobDetailTabView.swift` (or wherever job detail actions live)

In the job action menu (the ellipsis/gear menu on job detail), add a **"Flex Pool"** section visible only to users with `manage_flex_pool` permission:

- Show current status: "In Pool" (green) or "Not in Pool" (gray) based on the job's `isFlexPool` field
- Action: "Add to Flex Pool" / "Remove from Flex Pool" toggle button
- When adding: optionally show a sheet to pick team/user filter (can be skipped — leave filter as nil = all users)
- On confirm: call `schedulingService.markJobFlexPool(jobId: job.id, isFlexPool: !currentlyInPool)`
- Use `.role(.destructive)` on "Remove from Flex Pool"

The `manage_flex_pool` permission key is already in `AuthService.defaultPermissionMap()`.

---

## Reference Patterns

- **Tab structure:** Copy the pattern from the existing Dispatch/Calendar tab layout in this file
- **Action button ring:** Use `ActionIndicator` or `.actionRing` modifier (from PE-026) on the Claim button if available
- **Claim confirmation:** Use `.confirmationDialog("Claim job?", isPresented: $showClaimConfirm)` pattern (same as swipe-to-delete pattern in the codebase)
- **Empty state:** Copy pattern from `IOSJobsListPage` empty state

---

## Service Calls

```swift
// Fetch flex pool (in .task or loadData)
let jobs = try schedulingService.fetchFlexPool(userId: currentUserId)

// Claim a job
try schedulingService.claimFlexJob(jobId: job.id, userId: currentUserId)

// Manager: toggle pool status
try schedulingService.markJobFlexPool(jobId: job.id, isFlexPool: true)
```

All methods are on `SchedulingService` which is already available via `appCore.schedulingService` or `@EnvironmentObject`.

---

## Verification

1. As a worker: Open Scheduling → Flex Pool tab — confirm it loads (empty state is fine)
2. Have a manager add a job to the pool via job detail actions
3. Reload Flex Pool tab — confirm job appears
4. Tap Claim → confirm dialog → confirm — verify job disappears from pool and user is navigated to job detail
5. As a manager: Confirm job detail shows "In Pool" after adding, "Not in Pool" after removing

Build: zero errors, zero warnings.
