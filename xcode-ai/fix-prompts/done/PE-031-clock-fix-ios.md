# PE-031 — Clock In/Out Bug Fix (iOS — Root Causes A & B)

**GitHub Issue:** #20
**Plan:** `docs/plans/ios-clock-fix.md`
**Priority:** EMERGENCY — production workers cannot clock in

---

## Context

Workers report that tapping "Clock In" does nothing. Core-side root causes (C: missing `isTableNotFoundError` guard on `getTodaysClockEntries`, D: same on `listLaborEntries`) are already fixed. This prompt fixes the two remaining iOS-side root causes:

- **Root Cause A:** Location permission race — on first launch, `permissionDenied` is `false` but permission hasn't been granted yet. System shows permission dialog AFTER the tap, confusing users.
- **Root Cause B:** `alreadyClockedIn` error — if a prior session left a dangling clock entry, the service throws but the recovery option is unclear or missing.

Also adds better error logging to help diagnose any remaining failures.

---

## Owner Decisions (from Q&A)

- GPS precise location IS required (company option set by admin)
- System suggests a job based on location, allows user to change
- On first launch: show a clear GPS permission explanation BEFORE the clock button is tappable
- If already clocked in: prominently surface the error with a "Clock Out Previous Entry" recovery button

---

## Task 1 — Location Permission Pre-Check

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSClockPage.swift`

1. Import `os.log` (for logging)

2. Add a computed property:
   ```swift
   private var needsLocationPermission: Bool {
       locationManager.authorizationStatus == .notDetermined
   }
   ```

3. In the main body, **before** showing the clock-in button area:
   - If `needsLocationPermission`: show a full-width banner:
     ```
     ⚠️ Location Required
     This company requires GPS check-in for clock entries.
     [Allow Location Access]
     ```
     Tapping "Allow Location Access" calls `locationManager.requestPermission()`
   - Clock-in buttons should be **grayed out / disabled** while `needsLocationPermission` is true
   - Once permission is granted (`.authorizedWhenInUse` or `.authorizedAlways`), banner disappears, buttons become active

4. If permission is `.denied`: show a different banner:
   ```
   Location access denied. Go to Settings to allow location access.
   [Open Settings]
   ```
   "Open Settings" → `UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)`

---

## Task 2 — alreadyClockedIn Recovery

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSClockPage.swift`

When `clockIn()` throws `JobsError.alreadyClockedIn(userId:jobId:)`:

1. Show an **alert** (not just a red banner):
   ```
   "You Are Already Clocked In"
   "You have an active clock entry for [job name or 'a previous job'].
    Would you like to clock out of it first?"

   [Clock Out Previous Entry]  [Cancel]
   ```

2. Tapping "Clock Out Previous Entry":
   - Calls `service.clockOut(userId:gpsLat:gpsLng:)` for the active entry
   - On success: shows brief success toast then re-triggers the clock-in
   - On error: shows the error message

3. If `notClockedIn` is returned unexpectedly: show a recovery alert with a "Refresh" button that reloads the page

---

## Task 3 — Enhanced Error Logging

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSClockPage.swift`

Add `os.Logger` calls throughout the clock-in flow:

```swift
private let logger = Logger(subsystem: "com.wiredpart", category: "ClockPage")

// In clockIn() function:
logger.info("ClockIn tapped — permissionStatus=\(locationManager.authorizationStatus.rawValue) userId=\(userId)")
logger.info("GPS result: lat=\(location?.coordinate.latitude ?? 0) lng=\(location?.coordinate.longitude ?? 0)")
logger.info("Calling service.clockIn(userId: \(userId) jobId: \(jobId ?? -1))")
// In catch block:
logger.error("ClockIn error: \(error.localizedDescription)")
```

These logs will appear in Xcode Console and help diagnose any remaining failures.

---

## Task 4 — Ensure Error Message Is Visible

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSClockPage.swift`

The `errorMessage` state variable shows a red banner. Verify:
1. The red banner appears at the TOP of the visible scroll area (not below the fold)
2. The banner stays visible for at least 5 seconds (don't auto-dismiss too fast)
3. The banner has an `×` dismiss button

If the banner is currently at the bottom of the view or hidden by the tab bar, move it to the top of the `VStack` / above the job list.

---

## Verification Checklist

- [ ] Fresh install: Clock page shows "Location Required" banner, clock button is disabled
- [ ] Tap "Allow Location Access": permission dialog appears
- [ ] After granting permission: banner disappears, clock button active
- [ ] Permission denied: "Open Settings" button shown
- [ ] Clock In works when conditions are met: entry created in DB
- [ ] Tap Clock In while already clocked in: alert shown with "Clock Out Previous Entry" option
- [ ] Error messages appear at the top of the view
- [ ] Logger output visible in Xcode Console during testing
- [ ] Build: 0 errors, 0 warnings
