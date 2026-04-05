# PE-034: Quick UX/HIG Fixes (DIS-001 through DIS-004)

**Priority:** Medium
**Source:** dev-improvement-scanner run 7 & 8 (2026-04-04)
**GitHub issues:** PENDING — file manually (DIS-001 through DIS-004)
**Plan:** `docs/DevTODO/DIS-001-loading-indicators.md` through `DIS-004-timer-leak-dashboard.md`

---

## Overview

Four small UI improvements identified by the improvement scanner. All are quick, self-contained changes with no data model or service changes required.

---

## Fix 1 of 4 — DIS-001: Missing Loading Indicators (3 Pages)

**Files to change:**
- `Features/People/IOSContractorDetailPage.swift`
- `Features/Jobs/IOSEstimationReviewPage.swift`
- `Features/Office/IOSEstimationSettingsPage.swift`

**Problem:** These pages flash empty content before `.task { }` finishes loading. Users see "No ratings yet", "No entries" before data arrives.

**Fix pattern** (apply to all 3 files):

1. Add `@State private var isLoading = true` to the view's state properties.

2. Wrap the main content `body` with:
```swift
if isLoading {
    ProgressView("Loading...")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
} else {
    // existing content
}
```

3. In the `.task { }` modifier (or `loadData()` function), at the END of both the success path and the catch/error path, add:
```swift
isLoading = false
```

**Reference pattern:** `IOSNotebookDetailPage.swift` already uses this exact pattern correctly.

---

## Fix 2 of 4 — DIS-002: Missing Pull-to-Refresh on Daily Report Templates Page

**File:** `Features/Settings/IOSDailyReportTemplatesPage.swift`

**Problem:** Page loads live data with a spinner but no `.refreshable` — users can't retry if data is stale or a load fails.

**Fix:** Add `.refreshable { await loadData() }` (or `loadData()` if sync) to the top-level `List` that wraps the template sections. If there are two separate `List` views, add `.refreshable` to the outer container or both lists.

Example:
```swift
List {
    // ... existing template sections
}
.refreshable {
    loadData() // or: await loadData() if async
}
```

---

## Fix 3 of 4 — DIS-003: 7 Sheets Missing .presentationDetents

**Files to change:**
- `Features/People/IOSContactDetailPage.swift` — edit form sheet → `.large`
- `Features/Parts/PartsCatalogPage.swift` — edit form sheet → `.large`
- `Features/People/IOSHatsPage.swift` — add employee sheet → `.large`
- `Navigation/IOSMainView.swift` — user menu sheet → `.medium` or `.fraction(0.4)`
- `Navigation/IOSMainView.swift` — tab editor sheet → `.large`
- `Navigation/IOSMainView.swift` — conflict review sheet → `.large`
- `Navigation/IOSMainView.swift` — AI assistant sheet → `.large`

**Fix:** For each `.sheet(isPresented:) { ... }` or `.sheet(item:) { ... }` in the listed files, add `.presentationDetents([.large])` inside the sheet's content view. Use `.medium` for the compact user menu.

Example:
```swift
.sheet(item: $activeSheet) { _ in
    SomeFormView()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
}
```

For the user menu specifically:
```swift
.sheet(isPresented: $showUserMenu) {
    UserMenuContent()
        .presentationDetents([.medium, .fraction(0.4)])
        .presentationDragIndicator(.visible)
}
```

---

## Fix 4 of 4 — DIS-004: Timer Continues Firing After DashboardDailyReportPage Is Popped

**File:** `Features/Jobs/DashboardDailyReportPage.swift` (lines ~44, ~131)

**Problem:** A `Timer.publish(every: 60, ...).autoconnect()` timer fires and spawns `Task { await loadData() }` even after the user navigates away from this page.

**Fix:** Replace the current `.onReceive(refreshTimer)` pattern with an explicit Combine cancellable stored in `@State`:

```swift
@State private var timerCancellable: AnyCancellable?

// Replace the .onReceive modifier with:
.onAppear {
    timerCancellable = refreshTimer.sink { _ in
        Task { await loadData() }
    }
}
.onDisappear {
    timerCancellable?.cancel()
    timerCancellable = nil
}
```

Import `Combine` at the top if not already imported:
```swift
import Combine
```

Remove the old `.onReceive(refreshTimer)` modifier after adding the above.

---

## Verification

After implementing all 4 fixes, verify:

1. **DIS-001:** Open Contractor Detail, Estimation Review, Estimation Settings — confirm a spinner shows briefly before content appears. No empty-state flash.
2. **DIS-002:** Open Settings → Daily Report Templates → pull down to refresh → spinner appears and data reloads.
3. **DIS-003:** Open each sheet listed above — confirm it opens at the declared detent size (large for forms, medium for user menu).
4. **DIS-004:** Navigate to DashboardDailyReportPage, then navigate away. Add a temporary `print("timer fired")` — confirm it stops printing after you leave the page.

Build: zero errors, zero warnings.
