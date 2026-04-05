# iOS Clock In/Out Bug Fix Plan

## What This Does (Plain English)
The Clock In/Out page exists but workers report it does nothing when they tap "Clock In". This plan is to find out exactly WHY it fails and fix it so workers can reliably clock in and out.

## Why We Need This
Workers cannot track their time. This is emergency priority — production users are affected and payroll data is not being captured.

## Current State
- `IOSClockPage.swift` exists with a full clock-in UI (GPS-sorted job list, Shop option, flex pool)
- `JobsService.clockIn()` / `clockOut()` exist in core with proper SQL
- Error handling exists: `errorMessage` state + `userFriendlyError()` function
- Page load (`loadJobsAndClockStatus`) is wrapped in do/catch — errors set `errorMessage` but do NOT prevent the UI from showing

## Known Possible Root Causes

### Root Cause A — Location Permission Race
The `.task { locationManager.requestPermission() }` modifier fires async. The `clockIn()` function checks `locationManager.permissionDenied` immediately. On first launch (`.notDetermined` state), `permissionDenied` may be `false` even though permission hasn't been granted yet. The system then pops a permission dialog AFTER the user taps clock in, `getCurrentLocation()` returns nil, and the clock in proceeds with nil GPS — which is fine. But the permission dialog interrupting the flow may confuse users into thinking it failed.

**Fix A:** Show a clear location permission request BEFORE the clock button is tappable for the first time. If permission is `.notDetermined`, show an informational sheet explaining why GPS is needed before requesting.

### Root Cause B — alreadyClockedIn Throw
`clockIn()` checks for existing `status = 'clocked_in'` rows. If a prior test session or crash left a dangling clock entry (not clocked out), the service throws `JobsError.alreadyClockedIn`. The `userFriendlyError()` function maps this to a message — but if the error message is not visible (scrolled away, or error appears on a different section), user sees nothing.

**Fix B:** When `alreadyClockedIn` is thrown during a clock-in attempt, prominently surface it and offer a "Clock Out Previous Entry" recovery option.

### Root Cause C — Missing labor_entries Table on Fresh Install
If migrations have not run yet, `getActiveClockEntry()` handles this via `isTableNotFoundError → nil`. But `getTodaysClockEntries()` does NOT have this guard — it may throw if the table doesn't exist. This would set `errorMessage` on page load, which shows as a red banner. The clock buttons would still be visible, but an error banner may cause users to think the whole page is broken.

**Fix C:** Add `isTableNotFoundError` guard to `getTodaysClockEntries()`. Return `[]` on table-not-found.

### Root Cause D — listLaborEntries No isTableNotFoundError Guard
Same as C — `listLaborEntries()` may throw on fresh install.

**Fix D:** Verify `listLaborEntries()` has `isTableNotFoundError → []` guard. Add if missing.

## Investigation Steps Required

```
STEP 1: Add Logger.info() calls to clockIn() button action in IOSClockPage:
  - Log: "Clock in tapped: permissionDenied=\(locationManager.permissionDenied) userId=\(appCore.currentUser?.id)"
  - Log before and after service.clockIn() call
  - Log the caught error: "Clock in error: \(error)"

STEP 2: Check JobsService.listLaborEntries() for isTableNotFoundError guard.

STEP 3: Check JobsService.getTodaysClockEntries() for isTableNotFoundError guard.

STEP 4: On a clean simulator, check Console for the Logger output when tapping Clock In.
```

## Files to Modify

### Core Fixes (Immediate)
- `core/Sources/WiredPartCore/Services/JobsService.swift`
  - `getTodaysClockEntries()` — add `isTableNotFoundError → return []` catch wrapper
  - `listLaborEntries()` — verify/add `isTableNotFoundError → return []`

### iOS Fixes (Direct Edit)
- `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSClockPage.swift`
  - Add `Logger.info()` calls to `clockIn()` function for diagnosis
  - Improve `alreadyClockedIn` error handling — show recovery button
  - Add `isLoading || locationManager.authorizationStatus == .notDetermined` guard before showing clock buttons (show "Location permission required" prompt instead)

## Data Flow
User taps "Clock In" on job row
→ `clockIn(jobId:isShop:)` called
→ Check `locationManager.permissionDenied` → if denied, show alert
→ `locationManager.getCurrentLocation()` async (5s timeout)
→ Check payment hold if non-shop job
→ `service.clockIn(userId:jobId:gpsLat:gpsLng:)`
→ SQL: INSERT INTO labor_entries (user_id, job_id, clock_in, ...) VALUES (...)
→ On success: reload page data
→ On error: set errorMessage, display in red banner

## Test Plan
1. Fresh simulator — tap Clock In — verify it shows "location required" prompt
2. Grant location permission — tap Shop/Warehouse — verify clock entry created in DB
3. Tap Clock In again while already clocked in — verify `alreadyClockedIn` message with recovery
4. Deny location permission — tap Clock In — verify permission denied alert shown

## Owner Decisions Applied
- GPS precise location IS required (company option set during admin setup)
- System suggests job based on location, allows user to change
- Priority: EMERGENCY — workers are blocked

## Priority
🚨 **EMERGENCY** — production users cannot clock in. Fix immediately.
