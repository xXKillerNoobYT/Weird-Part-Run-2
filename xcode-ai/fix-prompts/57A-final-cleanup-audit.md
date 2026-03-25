# 57A — Final Cleanup Audit: Fix All Remaining Issues

> **Chain position:** Standalone — run after 56A or independently
> **Prerequisite:** None
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**Fix ALL issues listed below.** These were found by a comprehensive audit of every Swift file in the project. Work through each category systematically. After all fixes, verify the project builds with zero errors.

## Category 1: Force Unwrap (1 instance — CRASH RISK)

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSReceiveShipmentPage.swift`
**Line:** 328
**Issue:** `let result = items.first!`
**Fix:** Replace with safe unwrap:
```swift
guard let result = items.first else { return }
```

## Category 2: Direct `appCore.db` Access in UI Files (5 instances)

These files bypass the service layer by accessing the database directly. Replace with service method calls.

| File | Lines | Fix |
|------|-------|-----|
| `Features/Dashboard/DashboardDailyReportPage.swift` | 892, 911 | Replace `appCore.db` with `appCore.jobsService` calls |
| `Features/Dashboard/IOSDashboardQRScannerPage.swift` | 467 | Replace `appCore.db` with appropriate service call |
| `Features/Settings/IOSDatabaseResetPage.swift` | 199, 226 | OK to keep — this page intentionally accesses DB for reset operations |

For each, read the surrounding code to understand what query is being run, then find or create a service method that does the same thing.

## Category 3: Empty Catch Blocks (11 instances)

Every `catch { }` must either set a `@State` error variable or handle the error meaningfully. Replace each empty catch:

| File | Line | Fix |
|------|------|-----|
| `Dashboard/DashboardView.swift` | 528 | Set `loadError` or use `try?` with nil-coalescing |
| `Parts/CompanionSandboxSheet.swift` | 308 | Set error state |
| `Parts/PartsCompanionsPage.swift` | 171, 185, 1203, 1209, 1215, 1221 | Set error state for each |
| `Orders/IOSJPODetailPage.swift` | 747, 773, 788 | Set error state for each |

Pattern for fixing:
```swift
// BEFORE:
} catch { }

// AFTER (if error is non-critical):
} catch {
    // Non-critical: [explain why]
}

// AFTER (if error should show to user):
} catch {
    loadError = error.localizedDescription
}
```

## Category 4: Silent Guard Returns (~130 instances — bulk fix)

This is the biggest issue. Every `guard let service = appCore.xxxService else { return }` silently fails without telling the user anything.

**The pattern to apply everywhere:**

```swift
// BEFORE:
guard let service = appCore.jobsService else { return }

// AFTER (in loadData-type methods):
guard let service = appCore.jobsService else {
    loadError = "Service not available"
    isLoading = false
    return
}

// AFTER (in action methods like save/delete):
guard let service = appCore.jobsService else {
    actionError = "Service not available"
    return
}
```

**Most affected files (fix these first):**
- `Parts/PartsCatalogPage.swift` (7 instances)
- `Parts/PartsCompanionsPage.swift` (7 instances)
- `Jobs/IOSJobDetailTabView.swift` (8 instances)
- `Warehouse/IOSStagingPage.swift` (6 instances)
- `Warehouse/WarehouseLocationsPage.swift` (6 instances)
- `Orders/IOSPODetailPage.swift` (5 instances)
- `Jobs/IOSClockPage.swift` (5 instances)

Then fix ALL remaining instances across all files. Search for `guard let service = appCore.` and `guard let.*= appCore.*else { return }` to find them all.

## Category 5: Undisplayed `loadError` (7 files)

These files have `@State private var loadError: String?` but never show it in the UI. Add an `ErrorStateView` or alert display:

| File | Fix |
|------|-----|
| `Parts/CompanionSandboxSheet.swift` | Add ErrorStateView in the body |
| `Parts/PricingOverrideFlow.swift` | Add error alert |
| `Parts/PartHistoryView.swift` | Add ErrorStateView |
| `Parts/CompanionAdminDashboardSheet.swift` | Add ErrorStateView |
| `Orders/CreatePOSheet.swift` | Add error alert |
| `Fleet/IOSAssignDriverSheet.swift` | Add error alert |
| `Warehouse/WarehouseOnboardingWizard.swift` | Add ErrorStateView |

Pattern:
```swift
if let error = loadError {
    ErrorStateView(message: error) { loadData() }
} else {
    // ... normal content
}
```

## Category 6: Multiple `.sheet()` Modifiers (17 files)

SwiftUI only respects the FIRST `.sheet()` modifier on a view. Convert all to single `.sheet(item:)` with `ActiveSheet` enum.

**High priority (adjacent line numbers — definitely broken):**
- `Fleet/IOSVehicleDetailPage.swift` (lines 61, 64)
- `Scheduling/IOSShortTermPipelinePage.swift` (lines 75, 87)
- `Dashboard/DashboardView.swift` (lines 90, 100)
- `Jobs/IOSEstimationReviewPage.swift` (lines 67, 70)
- `Jobs/LaborPage.swift` (lines 65, 77)
- `Office/IOSManageJobsPage.swift` (lines 44, 65)
- `Office/IOSEstimationSettingsPage.swift` (lines 80, 83)
- `Warehouse/IOSStagingPage.swift` (lines 133, 136)
- `Notebooks/PanelScheduleBuilder.swift` (lines 23, 30)
- `Settings/IOSDailyReportTemplatesPage.swift` (lines 63, 77)
- `Settings/IOSReportTemplatesPage.swift` (lines 69, 83)

**For each file:**
1. Create an `ActiveSheet` enum with cases for each sheet type
2. Replace all `@State private var showXxx = false` with single `@State private var activeSheet: ActiveSheet?`
3. Replace all `.sheet(isPresented:)` with single `.sheet(item: $activeSheet)`
4. Add a `sheetContent(for:)` method

**Lower priority (likely in sub-views — verify first):**
- `Jobs/IOSJobDetailTabView.swift` (lines 99, 796)
- `Jobs/JobsListPage.swift` (lines 92, 103)
- `Parts/PartsCatalogPage.swift` (lines 165, 1452)
- `Parts/PartsBrandsPage.swift` (lines 61, 488)
- `Parts/PartsForecastingPage.swift` (lines 48, 89)
- `Parts/PartsSuppliersPage.swift` (lines 106, 694)

Check if the second `.sheet()` is on a different struct/view within the file. If so, it's fine. If both are on the same view, fix it.

## Category 7: Platform Guards (9 instances, 1 file)

**File:** `Features/Dashboard/IOSDashboardQRScannerPage.swift`
Remove all `#if os(iOS)` / `#elseif os(macOS)` / `#endif` blocks. Keep only:
- `#if os(iOS) && !targetEnvironment(macCatalyst)` for VisionKit (these are OK)

## Category 8: Missing `.refreshable` (39 files)

Add `.refreshable { loadData() }` (or equivalent) to every `List` view that loads data. Skip settings pages where refresh doesn't make sense.

## Category 9: Missing `.searchable` (28 files)

Add `.searchable(text: $searchText, prompt: "Search...")` to list pages with 10+ potential items.

## Category 10: Services Missing `isTableNotFoundError` (4 services)

Add `isTableNotFoundError` fallback to these services for methods that query tables from later migrations:

- `BreakService.swift` — queries `break_policies`, `break_records` etc.
- `DailyReportGenerator.swift` — queries multiple tables from different migrations
- `AIDispatchService.swift` — queries `ai_dispatch_choices` etc.
- `JobEstimationService.swift` — queries `estimation_questions` etc.

Pattern:
```swift
} catch {
    if isTableNotFoundError(error) { return [] }
    throw error
}
```

## Success Criteria

- [ ] ZERO force unwraps in Features files
- [ ] ZERO `appCore.db` in Features files (except IOSDatabaseResetPage)
- [ ] ZERO empty `catch { }` blocks
- [ ] ZERO silent guard-let-service returns
- [ ] ZERO undisplayed `loadError` variables
- [ ] ZERO multiple `.sheet()` on same view
- [ ] ZERO unnecessary `#if os(iOS)` guards
- [ ] ALL List views have `.refreshable`
- [ ] ALL appropriate list pages have `.searchable`
- [ ] ALL 4 services have `isTableNotFoundError` fallback
- [ ] Project builds with ZERO errors

## Log Entry

```
## Prompt 57A Results (YYYY-MM-DD)

### Fixes Applied
- Force unwraps fixed: X
- appCore.db replaced: X
- Empty catches fixed: X
- Silent guards fixed: X
- loadError displayed: X files
- Multiple .sheet() fixed: X files
- Platform guards removed: X
- .refreshable added: X files
- .searchable added: X files
- isTableNotFoundError added: X services

### Build Result
- Errors: X (should be 0)
- Warnings: X
```

**This prompt is complete when the project builds clean with zero issues across all 10 categories.**
