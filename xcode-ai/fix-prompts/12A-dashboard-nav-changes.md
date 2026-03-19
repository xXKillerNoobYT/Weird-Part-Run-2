# Fix Prompt 12A: Dashboard Navigation Changes

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.

---

## What the User Wants

The Dashboard is becoming the worker's home base. Instead of having just one "Overview" tab, it gets 4 sidebar tabs: Overview, Clock, Daily Report, and QR Scanner. The Clock page moves OUT of the Jobs module and INTO Dashboard. All 4 sub-pages are also accessible via Quick Action buttons on the Overview page.

---

## Files To Edit

### 1. NavigationConfig.swift — Add Dashboard Tabs, Remove Clock from Jobs

**File:** `Weird Parts IOS/Navigation/NavigationConfig.swift`

Find the Dashboard module definition (around line 58):

```swift
AppModule(id: "dashboard", label: "Dashboard", icon: "square.grid.2x2.fill", tabs: [
    AppTab(id: "dashboard-home", label: "Overview", icon: "chart.bar.fill", path: "/dashboard"),
]),
```

Replace with:

```swift
AppModule(id: "dashboard", label: "Dashboard", icon: "square.grid.2x2.fill", tabs: [
    AppTab(id: "dashboard-home", label: "Overview", icon: "chart.bar.fill", path: "/dashboard"),
    AppTab(id: "dashboard-clock", label: "Clock", icon: "clock.badge.checkmark.fill", path: "/dashboard/clock", permission: "clock_in_out"),
    AppTab(id: "dashboard-report", label: "Daily Report", icon: "doc.text.magnifyingglass", path: "/dashboard/report"),
    AppTab(id: "dashboard-scanner", label: "QR Scanner", icon: "qrcode.viewfinder", path: "/dashboard/scanner"),
]),
```

Find the Jobs module definition and **remove** the Clock tab:

```swift
// REMOVE this line from the Jobs tabs array:
AppTab(id: "jobs-clock", label: "Clock", icon: "clock.badge.checkmark.fill", path: "/jobs/clock", permission: "clock_in_out"),
```

### 2. IOSContentRouter.swift — Add New Routes

**File:** `Weird Parts IOS/Navigation/IOSContentRouter.swift`

Find the Dashboard routing section (around line 19-21). After the existing `/dashboard` case, add:

```swift
case "/dashboard/clock":
    IOSClockPage()
case "/dashboard/report":
    DashboardDailyReportPage()
case "/dashboard/scanner":
    IOSDashboardQRScannerPage()
```

Find the Jobs routing section and **remove** or redirect the old clock route:

```swift
// Change this:
case "/jobs/clock":
    JobsRouter(tabId: "jobs-clock")

// To a redirect (so any saved bookmarks still work):
case "/jobs/clock":
    IOSClockPage() // Redirect — Clock now lives under Dashboard
```

### 3. DashboardView.swift — Update Quick Actions to Use New Paths

**File:** `Weird Parts IOS/Features/Dashboard/DashboardView.swift`

The Quick Actions section (around line 244-277) already has NavigationLinks for scanner, clock, and daily report using `DashboardDestination` enum. These use push navigation within the Dashboard's NavigationStack. This still works — the Quick Action buttons push sub-pages, while the sidebar tabs route directly. No change needed here unless you want the quick actions to switch sidebar tabs instead of pushing.

**However**, verify the `DashboardDestination` enum and `.navigationDestination` handler (lines 29-82) still reference the correct views:
- `.scanner` → `IOSDashboardQRScannerPage()`
- `.clock` → `IOSClockPage()`
- `.dailyReport` → `DashboardDailyReportPage()`

These should already be correct. Just confirm they compile.

### 4. JobsRouter.swift — Remove Clock Case

**File:** `Weird Parts IOS/Features/Jobs/JobsRouter.swift`

If this router has a case for `"jobs-clock"` that renders `IOSClockPage`, remove it since the tab no longer exists in Jobs. The router should not crash if it receives an unknown tabId — verify it has a default/fallback case.

---

## Success Criteria

1. Build succeeds with no errors
2. Sidebar shows Dashboard with 4 sub-items: Overview, Clock, Daily Report, QR Scanner
3. Tapping each sub-item in sidebar navigates to the correct page
4. Jobs sidebar NO LONGER shows "Clock" as a sub-item
5. Quick Action buttons on Dashboard Overview still work (push to scanner/clock/report)
6. Old `/jobs/clock` route still works (redirects to IOSClockPage)

---

## When Done

Read and implement **prompt 12B-dashboard-clock-banner.md** next.
