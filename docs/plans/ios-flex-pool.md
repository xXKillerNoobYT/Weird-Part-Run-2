# iOS Flex Pool — Self-Assign Jobs Plan

## What This Does (Plain English)
Workers can see a list of "flex pool" jobs — jobs that managers have made available for any qualified worker to claim. Workers tap a job, confirm they want it, and it becomes their active assigned job. Managers control which jobs go into the pool and can filter by team or person.

## Why We Need This
Some jobs don't need a specific person — they just need to get done. Managers can put these in the flex pool and workers can self-assign, reducing dispatcher overhead for routine tasks.

## Current State
- `self_assign_flex` permission key exists in `AuthService.defaultPermissionMap()` ✅
- `jobs` table has NO `is_flex_pool` column — needs DB migration
- `SchedulingService` has NO `fetchFlexPool()` or `claimFlexJob()` methods
- `IOSSchedulingPage.swift` has Dispatch and Calendar tabs — no Flex Pool tab yet

## Owner Decisions Applied
- **Location:** Separate tab on the Scheduling page (not Dashboard) — "everything in one place"
- **Who marks a job flex?** Only managers/dispatchers, from Job Detail page
- **Manager filtering:** When adding a job to pool, manager can filter to specific teams or people who can take it (not everyone is qualified for every job)
- **Worker view:** Workers see ALL jobs available TO THEM (filtered by manager before pool entry — so no additional skill filter needed on worker side)
- **Claim makes them lead:** Claiming sets the worker as job lead (can be changed later by manager)
- **Claim creates dispatch entry:** Yes — claiming writes a `dispatch_entries` row
- **Confirmation required:** Yes — "Are you sure?" dialog before claiming
- **After claiming:** Navigate to job detail page (with dashboard, details, notebook, order history tabs)
- **Manager override:** Manager can override/unclaim at any time
- **Company option:** Admin can require "Manager must approve first" — when enabled, claim shows "Pending approval" instead of immediately assigning
- **Once claimed:** Becomes active job — can be put on hold or cancelled with proper permissions
- **After claiming:** Goes to job detail with all tabs (dashboard, details, notebook, order history, all tied info)

## Files to Create

### 1. DB Migration
**File:** `core/Sources/WiredPartCore/Migrations/Migration_NNN_flex_pool.swift`
```swift
// Adds is_flex_pool column to jobs table
// Adds flex_pool_team_filter column (JSON array of team IDs, or NULL for all)
// Adds flex_pool_user_filter column (JSON array of user IDs, or NULL for all)
```

### 2. SchedulingService Methods
**File:** `core/Sources/WiredPartCore/Services/SchedulingService.swift`

New method `fetchFlexPool(userId: Int64) throws -> [FlexPoolJob]`:
- Query: `SELECT j.*, u.display_name AS lead_name FROM jobs j LEFT JOIN ... WHERE j.is_flex_pool = 1 AND j.deleted_at IS NULL AND j.status NOT IN ('completed', 'cancelled')`
- Filter: If `flex_pool_user_filter` is not null, check userId is in the list; if `flex_pool_team_filter` is not null, check userId is on one of the teams
- Returns `FlexPoolJob` struct (id, jobName, jobNumber, address, description, teamsNeeded, skillsNeeded, estimatedHours)

New method `claimFlexJob(jobId: Int64, userId: Int64) throws`:
1. Check company setting `flex_pool_requires_approval` — if true, create pending dispatch entry (status: 'pending_approval') and return
2. BEGIN TRANSACTION
3. UPDATE jobs SET is_flex_pool = 0, lead_user_id = userId WHERE id = jobId
4. INSERT INTO dispatch_entries (job_id, user_id, role, status, dispatched_at) VALUES (jobId, userId, 'lead', 'active', datetime('now'))
5. END TRANSACTION

New method `markJobFlexPool(jobId: Int64, isFlexPool: Bool, teamFilter: [Int64]?, userFilter: [Int64]?) throws`:
- For managers to toggle a job's flex pool status

New struct `FlexPoolJob`:
```swift
public struct FlexPoolJob: Identifiable {
    public let id: Int64
    public let jobName: String
    public let jobNumber: String
    public let address: String?
    public let description: String?
    public let estimatedHours: Double?
    public let isApprovalRequired: Bool
}
```

## Files to Modify

### iOS UI — Scheduling Page
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSSchedulingPage.swift`
- Add third tab: "Flex Pool"
- Flex Pool tab shows: list of available jobs filtered for this user
- Each row: job name, job number, address, estimated hours, "Claim" button
- Claim button → confirmation dialog → `schedulingService.claimFlexJob(jobId:userId:)`
- After claim: navigate to job detail page
- If approval required: show "Pending Approval" row in a separate section

Xcode prompt: `PE-026-flex-pool-scheduling-tab.md`

### iOS UI — Job Detail Page (Manager action)
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSJobDetailPage.swift` (or similar)
- Manager option in job actions: "Add to Flex Pool" / "Remove from Flex Pool"
- When adding: show team/user filter picker
- Gate this action on `manage_flex_pool` permission (new key to add to AuthService)

## Data Flow
**Manager flow:** Job Detail → tap "Add to Flex Pool" → pick team/user filters (optional) → confirm → `markJobFlexPool()` called → job appears in flex pool for filtered workers

**Worker flow:** Scheduling page → Flex Pool tab → see available jobs → tap "Claim" → "Are you sure you want to claim [job name]?" → confirm → `claimFlexJob()` called → become lead → navigate to job detail → (if approval required: show pending state)

## How It Links to Other Features
- Uses `dispatch_entries` table (Phase 10 — Scheduling)
- Uses `user_hats` / `employee_teams` for team-based filtering
- `self_assign_flex` permission gates the tab visibility
- New permission `manage_flex_pool` needed for managers to toggle job pool status

## Test Plan
1. Add `is_flex_pool` column via migration — verify compile
2. Call `markJobFlexPool(jobId:1, isFlexPool:true, teamFilter:nil, userFilter:nil)` — verify column set
3. Call `fetchFlexPool(userId:1)` — verify job appears
4. Call `claimFlexJob(jobId:1, userId:1)` — verify dispatch entry created, `is_flex_pool = 0`
5. Call `fetchFlexPool(userId:1)` again — verify job no longer in pool
6. Test with `flex_pool_requires_approval = true` — verify pending state

## Apple HIG Notes
- Flex Pool tab should use same visual language as Dispatch tab (list rows with job cards)
- "Claim" button should be prominent (primary color, or use action button ring style from PE-026)
- "Pending approval" row should use orange indicator (color + label for accessibility)
