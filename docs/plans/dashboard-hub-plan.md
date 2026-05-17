# Dashboard Hub Plan — User's Command Center

> **Created:** 2026-03-18
> **Status:** PLANNING
> **Depends on:** Core app, Jobs/Labor, Warehouse, QR scanning
> **Previous phases:** All 1-10 complete. Tauri migration complete.

---

## Vision

The Dashboard is the **worker's home base**. It's the first thing they see when they open the app, and it should answer every question they have in the first 5 seconds:
- Am I clocked in? To which job?
- What needs my attention today?
- Let me scan something quick.
- Let me file a report.

Currently: Dashboard has 1 tab ("Overview") with KPIs, charts, alerts, and quick action buttons. Clock is buried under Jobs. Daily Report is a sub-page only reachable via a quick action button. QR scanner is a simple scan-and-lookup.

**After this plan:** Dashboard becomes a 4-tab hub with GPS-aware clock management, a command-center daily report, and a fast continuous QR scanner.

---

## Architecture Changes

### Navigation: Dashboard Gets 4 Sidebar Tabs

**`NavigationConfig.swift`** — change Dashboard module from:
```swift
AppModule(id: "dashboard", label: "Dashboard", icon: "square.grid.2x2.fill", tabs: [
    AppTab(id: "dashboard-home", label: "Overview", icon: "chart.bar.fill", path: "/dashboard"),
])
```

To:
```swift
AppModule(id: "dashboard", label: "Dashboard", icon: "square.grid.2x2.fill", tabs: [
    AppTab(id: "dashboard-home", label: "Overview", icon: "chart.bar.fill", path: "/dashboard"),
    AppTab(id: "dashboard-clock", label: "Clock", icon: "clock.badge.checkmark.fill", path: "/dashboard/clock", permission: "clock_in_out"),
    AppTab(id: "dashboard-report", label: "Daily Report", icon: "doc.text.magnifyingglass", path: "/dashboard/report"),
    AppTab(id: "dashboard-scanner", label: "QR Scanner", icon: "qrcode.viewfinder", path: "/dashboard/scanner"),
])
```

**`IOSContentRouter.swift`** — add routes:
```swift
case "/dashboard/clock":    IOSClockPage()
case "/dashboard/report":   DashboardDailyReportPage()
case "/dashboard/scanner":  IOSDashboardQRScannerPage()
```

### Jobs Module: Remove Clock Tab

**`NavigationConfig.swift`** — remove from Jobs:
```swift
// REMOVE:
AppTab(id: "jobs-clock", label: "Clock", icon: "clock.badge.checkmark.fill", path: "/jobs/clock", permission: "clock_in_out"),
```

Keep `IOSClockPage.swift` in `Features/Jobs/` (it still references JobsService) — just change where it's navigated from.

---

## Feature 1: Clock Status Banner on Dashboard Overview

### What the User Sees

At the top of the Dashboard Overview page, below the greeting, a prominent banner shows:

**When clocked in:**
```
[green dot] Clocked in to Job #1234 — Smith Residence    3h 22m
                                                    [tap to manage →]
```

**When not clocked in:**
```
[gray dot] Not clocked in                    [Clock In button]
```

Tapping the banner navigates to Dashboard > Clock page.

### Implementation

Add to `DashboardView.swift`:
- New state: `@State private var clockStatus: ClockStatusData?`
- Load in `loadData()`: query active labor entry for current user
- New `clockStatusBanner` view between `greeting` and `kpiSection`

### Data Query
```sql
SELECT le.id, le.clock_in, j.job_name, j.job_number
FROM labor_entries le
LEFT JOIN jobs j ON j.id = le.job_id
WHERE le.user_id = ? AND le.clock_out IS NULL AND le.deleted_at IS NULL
ORDER BY le.clock_in DESC LIMIT 1
```

---

## Feature 2: Inline Clock with Location-Sorted Jobs

### What Changes From Current Clock Page

Currently: Tap "Clock In" → sheet opens with job list → pick job → done.

New behavior: No sheet. Job list is **inline on the page**, always visible when not clocked in. Jobs sorted by distance from the user's current location.

### Job List Order

1. **"Shop / Warehouse"** — always first (pinned)
2. **Active jobs sorted by distance** from user's GPS coordinates
3. Each row shows: Job name, job number, distance ("0.3 mi"), address
4. Jobs without coordinates sort to the bottom

### Shop + Optional Job Link

When user taps "Shop / Warehouse":
1. Clocks in to shop/overhead
2. Below the clock-in confirmation, shows a collapsible **"Link time to a job (optional)"** section
3. If expanded: shows the same distance-sorted job list
4. Tapping a job links the current clock session to that job
5. **Fast switching**: A small floating "Change Job Link" button stays visible. Tapping it shows the job list again. Previous job link time is recorded, new link starts.
6. **Fast clock out from job link**: Tap "End Job Link" to stop linking to a job but stay clocked into the shop.

### GPS Distance Calculation

Use the `LocationManager` (already exists in `App/LocationManager.swift`) to get current coordinates. Compare against job addresses using stored lat/lng from the jobs table.

Distance formula (Haversine, or simple Euclidean for short distances):
```swift
func distanceMiles(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
    let loc1 = CLLocation(latitude: from.latitude, longitude: from.longitude)
    let loc2 = CLLocation(latitude: to.latitude, longitude: to.longitude)
    return loc1.distance(from: loc2) / 1609.34 // meters to miles
}
```

---

## Feature 3: GPS Geofencing — Auto-Detect Job Transitions

### The Big Idea

When a worker is clocked into a job and their GPS shows they've left the 1-mile radius of that job site, the app notices and asks: "What happened?"

### Flow

1. While clocked in, app checks GPS every 5 minutes (using significant location changes to save battery)
2. If distance from clocked-in job > 1 mile:
   - **Lock the app** — show a full-screen modal, can't navigate away
   - Show: "You've left the area of [Job Name]. What happened?"
   - Options:
     - **Supply Run** — "I'm getting supplies. Clock keeps running." Records as travel/supply time in the labor entry notes. Worker stays clocked in.
     - **Going to Another Job** — Shows list of other active jobs. "Clock out of [Job A] at [leave time] and clock in at [Job B] at [arrive time]?" Uses GPS timestamps for leave/arrive.
     - **Lunch Break** — Clocks out for lunch. Reminder to clock back in.
     - **Done for the Day** — Clocks out completely.
     - **Other** — Free text explanation. Clock keeps running.
3. Until the worker answers, other features are locked (can't browse parts, can't do anything else). This prevents data gaps.
4. If they go to a DIFFERENT active job (GPS detects arrival at another job site): pre-fill the "Going to Another Job" option with that job.

### Data Model Impact

Add to `labor_entries` (or a new `labor_events` table):
- `event_type`: 'geofence_exit', 'supply_run', 'job_transition', 'lunch', 'break'
- `event_time`: when the geofence triggered
- `latitude`, `longitude`: where they were
- `notes`: free text
- `linked_job_id`: for supply runs tagged to a job

### Battery Consideration

- Use `CLLocationManager.startMonitoringSignificantLocationChanges()` — wakes app on ~500m movement
- OR set up `CLCircularRegion` geofences (iOS supports up to 20 simultaneously)
- Geofence approach is better: register a 1-mile region around the clocked-in job, get a callback when they exit

---

## Feature 4: Enhanced Daily Report (Command Center)

### New Sections (Added to Existing)

**Existing sections (keep):**
- Pending Actions (JPOs, POs, returns, overdue)
- Today's Activity (orders created, items received, returns)
- Expected Deliveries This Week
- Budget Alerts

**New sections:**

#### "My Hours Today" (personal)
- Clock in time
- Current duration (live counter)
- Total hours today
- Break time taken
- Job(s) worked on with time per job

#### "Who's Clocked In" (team — managers only, gated by permission)
- List of all currently clocked-in employees
- Each row: name, job name, duration, avatar
- Sorted by duration (longest first)

#### Fast Actions Bar
A horizontal scroll of action buttons at the top of the page:

| Action | Icon | What It Does |
|--------|------|-------------|
| Start Lunch | fork.knife | Clock out for lunch, set reminder |
| End Lunch | arrow.forward.circle | Clock back in from lunch |
| Start Break | cup.and.saucer | Generic break start |
| End Break | arrow.forward.circle | Clock back in from break |
| Report Problem | exclamationmark.triangle | Quick form: pick job → describe issue → optional photo → creates notebook entry |
| Submit Daily Report | doc.text | End-of-day summary form → what was done, issues, notes for tomorrow |
| Supply Run | truck.box | Mark current time as supply run start. When they return to geofence, auto-end it |

---

## Feature 5: Fast Continuous QR Scanner

### Current State

The QR scanner page has: camera button (tap to scan), manual entry field, result card. One scan at a time.

### New Behavior

**Instant camera**: Navigating to Dashboard > QR Scanner immediately opens the camera viewfinder.

**Continuous scanning**: Camera stays active. When it detects a QR code:
1. Shows the scanned item's info in an overlay card at the bottom of the camera view
2. Camera keeps running — pointing at a new QR immediately shows that item's info instead
3. **Lock button**: Tap to lock the current scan. Camera pauses. Full detail card appears with quick actions.
4. Quick actions are contextual (same as current: Move Stock, View Details, Check Status, etc.)
5. When a quick action is tapped, it **auto-locks** — the camera pauses, the action runs, and when done, camera resumes.
6. **Manual entry**: Available as a small text field below the camera viewfinder.
7. Last scanned item is remembered — if the camera loses the QR (user moves camera), it keeps showing the last result.

### UI Layout
```
┌────────────────────────────┐
│                            │
│     [ CAMERA VIEWFINDER ]  │
│                            │
│    ┌──────────────────┐    │
│    │ Scanned: Part     │    │
│    │ 2" White Elbow    │    │
│    │ Stock: 45 units   │    │
│    │ [Lock] [Details]  │    │
│    └──────────────────┘    │
│                            │
│  [manual entry...] [Look Up]│
└────────────────────────────┘
```

---

## T2-21: Dashboard Quick Actions Above the Fold

**Problem:** Quick Actions were rendered after KPI cards, charts, alerts, and background tasks, which made the most common commands easy to miss on phone-sized screens.

**Spec:** Keep the existing action set unchanged and promote the Quick Actions rail into the first loaded Dashboard content block after the greeting/onboarding/clock-status area. The loaded Dashboard order should be:

1. Quick Actions
2. KPI cards
3. Charts
4. Alerts
5. Background tasks

**Responsive behavior:**
- iPhone 375×812: preserve the current horizontal action rail so each button keeps its existing minimum hit target and the row can be reached immediately without scrolling past charts.
- iPad / desktop: preserve the current horizontal rail behavior; the promoted placement keeps the actions visually grouped above the analytics content without inventing new actions.
- Chart visibility is not sacrificed: charts remain directly after KPI cards, with only the already-existing Quick Actions section moved ahead of them.

**Implementation note:** `DashboardView.swift` now renders `quickActionsSection` before `kpiSection` / `chartsSection`, and the Dashboard help copy describes Quick Actions as near the top instead of at the bottom.

**Evidence to capture when simulator stability permits:** before/after screenshots at phone 375×812, iPad, and desktop/Catalyst if available. The expected after-state is Quick Actions appearing before KPI/charts while retaining the existing five actions: Scan QR, Clock In, Daily Report, Move Stock, New Order.

---

## Prompt Breakdown

| Prompt | What It Does | Files Touched |
|--------|-------------|---------------|
| 12A | Navigation: add 4 Dashboard tabs, remove Clock from Jobs, add routes | NavigationConfig.swift, IOSContentRouter.swift |
| 12B | Clock status banner on Dashboard Overview | DashboardView.swift |
| 12C | Inline clock with GPS-sorted jobs + shop/optional job link | IOSClockPage.swift, LocationManager.swift |
| 12D | GPS geofencing for job transitions | New: GeofenceManager.swift, GeofenceAlertView.swift |
| 12E | Enhanced Daily Report (my hours, team status, fast actions) | DashboardDailyReportPage.swift |
| 12F | Fast continuous QR scanner with lock/auto-lock | IOSDashboardQRScannerPage.swift |

---

## Dependencies Between Prompts

```
12A (nav changes) ← no deps, do first
12B (clock banner) ← needs 12A for routing
12C (inline clock) ← needs 12A for routing, can parallel with 12B
12D (geofencing) ← needs 12C for clock state awareness
12E (daily report) ← needs 12A for routing, can parallel with 12C
12F (QR scanner) ← needs 12A for routing, independent of clock work
```

Recommended order: **12A → 12B → 12C → 12D → 12E → 12F**
