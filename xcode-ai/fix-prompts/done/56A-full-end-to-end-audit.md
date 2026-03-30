# 56A — Full End-to-End Audit + Fix All Problems

> **Chain position:** Standalone — run this FIRST before any other pending prompts
> **Prerequisite:** None
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**THIS IS A COMPREHENSIVE AUDIT.** Read EVERY Swift file in the project. Find EVERY problem. Fix EVERY problem. Do not skip files. Do not leave issues for later. Be thorough, methodical, and fix everything in one pass.

**Read these files for context on program standards:**
- `CLAUDE.md` — project rules and architecture
- `docs/plans/ios-page-review-tracker.md` — program-wide standards section
- `docs/plans/implementation-roadmap.md` — all 15 program standards

## What to Check and Fix

### 1. GRDB in UI Files (ZERO TOLERANCE)

Search ALL files under `Weird Parts IOS/Weird Parts IOS/Features/` for `import GRDB`. If found:
- Read the file, identify every raw SQL query (`db.writer.read`, `db.writer.write`, `Row.fetchAll`)
- Check if a service method already exists for that query
- If YES → replace raw SQL with the service call
- If NO → add the method to the appropriate service, then call it
- Remove `import GRDB`

**Known remaining files:** IOSDashboardQRScannerPage, IOSEmployeeDetailPage, PartsCatalogPage, PartsForecastingPage, IOSClockPage. There may be more.

### 2. Empty Catch Blocks (ZERO TOLERANCE)

Search ALL Swift files for `catch { }` and `catch {` followed by only `print(`. Every catch must either:
- Set a `@State` error variable that shows in the UI, OR
- Call a proper error handler

Never silently swallow errors. Never use `print()` as the only error handling.

### 3. Silent Guard Returns (ZERO TOLERANCE)

Search for `guard let service = appCore.` patterns. Every guard-let-service must:
- Set `loadError = "Service not available"`
- Set `isLoading = false`
- Return AFTER setting error state

Never silently return with no user feedback.

### 4. Platform Guards (ZERO TOLERANCE)

Search for `#if os(iOS)` and `#elseif os(macOS)`. The app is iOS-only. Remove ALL platform guards. Keep only:
- `#if os(iOS) && !targetEnvironment(macCatalyst)` for VisionKit/DataScanner (these are OK)
- `#if DEBUG` blocks (these are OK)

### 5. Sheet Management

Search for multiple `.sheet(` modifiers on the same view. Each view should have exactly ONE `.sheet(item:)` using an `ActiveSheet` enum. Convert any `@State private var showXxx = false` with `.sheet(isPresented:)` to the ActiveSheet pattern.

### 6. Missing Error State Display

For every page that has `@State private var loadError: String?`, verify there's a corresponding UI element that SHOWS the error (ErrorStateView, ContentUnavailableView, or alert). If loadError exists but is never displayed, add the display.

### 7. Missing .refreshable

Every `List` view should have `.refreshable { loadData() }` or equivalent. If missing, add it.

### 8. Missing .searchable

Every list page with 10+ potential items should have `.searchable(text: $searchText, prompt: "Search...")`. If missing, add it.

### 9. Missing Help Button

Every feature page should have a help/info button in the toolbar that presents `PageHelpSheet`. Check that `PageHelpSheet` is wired up on every page. If missing, add it with appropriate help content for that page.

### 10. Force Unwraps

Search for `!` force unwraps (excluding `!=` and string interpolation). Replace with safe unwrapping (`if let`, `guard let`, `??`).

### 11. DispatchQueue.main.asyncAfter

Search for `DispatchQueue.main.asyncAfter`. Replace with `Task { try? await Task.sleep(for: .seconds(X)); await MainActor.run { } }`.

### 12. Navigation and Routing

Verify ALL routes in these routers actually resolve to real pages:
- `IOSContentRouter.swift`
- `SettingsRouter.swift`
- `OfficeRouter.swift`
- `OrdersRouter.swift`
- `WarehouseRouter.swift`
- `FleetRouter.swift`
- `IOSToolsRouter.swift`
- `PeopleRouter.swift`
- `IOSChatRouter.swift`
- `SchedulingRouter.swift`
- `IOSReportsRouter.swift`
- `IOSNotebooksRouter.swift`
- `PartsRouter.swift`
- `JobsRouter.swift`

Any route that resolves to a placeholder or "unknown" should be either wired to a real page or show a proper "Coming Soon" placeholder with an explanation.

### 13. Migration Safety

Verify ALL migrations in `AppDatabase+Migrations.swift`:
- Every migration is called from `registerMigrations()`
- No migration is nested inside another migration's function
- No duplicate `CREATE TABLE` for the same table name
- `eraseDatabaseOnSchemaChange` is wrapped in `#if DEBUG`

### 14. Service Layer Completeness

For each service file in `core/Sources/WiredPartCore/Services/`:
- Check that `isTableNotFoundError` fallbacks exist for queries on tables that may not exist yet
- Check that all public methods have proper error handling
- Check that no service method uses force unwraps

### 15. Compilation Check

After ALL fixes are applied, verify the project builds with zero errors and zero warnings. If there are warnings, fix those too.

## Process

1. Start with a full `grep` scan for each issue category
2. Count total issues found per category
3. Fix them systematically, one category at a time
4. After all fixes, do a second pass to verify nothing was missed
5. Build the project and fix any compilation errors
6. Log everything in the results

## Success Criteria

- [ ] ZERO `import GRDB` in any file under `Features/`
- [ ] ZERO empty catch blocks in any Swift file
- [ ] ZERO silent guard-let-service returns
- [ ] ZERO unnecessary `#if os(iOS)` platform guards
- [ ] ZERO multiple `.sheet()` modifiers on same view
- [ ] ZERO `loadError` state variables that aren't displayed in UI
- [ ] ALL List views have `.refreshable`
- [ ] ALL list pages have `.searchable` where appropriate
- [ ] ALL feature pages have help button
- [ ] ZERO force unwraps in non-test code
- [ ] ZERO `DispatchQueue.main.asyncAfter` (use async/await)
- [ ] ALL router routes resolve to real pages
- [ ] ALL migrations properly registered and ordered
- [ ] ALL service methods have proper error handling
- [ ] Project builds with ZERO errors and ZERO warnings

## Log Entry

```
## Prompt 56A Results (YYYY-MM-DD)

### Issues Found
- import GRDB in UI: X files
- Empty catch blocks: X instances
- Silent guard returns: X instances
- Platform guards: X instances
- Multiple .sheet(): X files
- Undisplayed loadError: X files
- Missing .refreshable: X lists
- Missing .searchable: X pages
- Missing help buttons: X pages
- Force unwraps: X instances
- DispatchQueue usage: X instances
- Broken routes: X routes
- Migration issues: X issues
- Service issues: X issues

### Fixes Applied
- [list every file modified and what was changed]

### Build Result
- Errors: X (should be 0)
- Warnings: X (should be 0)

### Second Pass
- Issues remaining after fixes: X (should be 0)
```

**This prompt is complete when the project builds clean with zero issues across all 15 categories.**
