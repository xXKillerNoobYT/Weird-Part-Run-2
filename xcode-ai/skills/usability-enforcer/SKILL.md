# Usability Enforcer Agent

**Schedule:** Daily at 2:00 PM
**Priority:** High — ensures the app is usable as planned
**Tracker:** `docs/usability-tracker.md`

---

## Purpose

This agent ensures that **every page in the iOS app is functional, navigable, and usable as designed**. It goes beyond compile/test checks — it validates the actual user experience by tracing every page load path, verifying every button does something, confirming every modal can be dismissed, and ensuring every page has a way out.

---

## 6 Scanners

### Scanner 1: Page Load Integrity
**Goal:** Every page loads without crashing on both empty AND populated databases.

**Process:**
1. Find all SwiftUI page files: `Weird Parts IOS/Weird Parts IOS/Features/**/*Page.swift`
2. For each page, trace the `loadData()` / `.task {}` chain:
   - What service methods are called?
   - Do those methods have `isTableNotFoundError` handling?
   - Do the SQL queries use correct table/column names vs `AppDatabase+Migrations.swift`?
3. Check that every page has:
   - An `isLoading` state with ProgressView
   - An `ErrorStateView` for error display
   - An `EmptyStateView` or `ContentUnavailableView` for zero records
4. Flag any page where `loadData()` calls a service method that can throw without error handling.

**Output:** List of pages with broken load paths.

### Scanner 2: Button & Action Verification
**Goal:** Every button, toolbar item, and interactive element actually does something.

**Process:**
1. Scan all page files for `Button {` blocks
2. Check for empty action closures: `Button { }` or `Button { /* TODO */ }`
3. Look for buttons whose action sets a `@State` variable that nothing reads
4. Verify toolbar buttons (`.toolbar { ToolbarItem }`) have real actions
5. Check `.swipeActions` have working handlers
6. Flag any `NavigationLink` whose destination view doesn't exist

**Output:** List of dead/broken buttons with file + line.

### Scanner 3: Modal & Sheet Dismiss
**Goal:** Every modal, sheet, and alert can be properly dismissed.

**Process:**
1. Find all `.sheet(isPresented:)` and `.sheet(item:)` modifiers
2. For `isPresented:` sheets — verify the presented view has a way to set the binding to false (Cancel button, Done button, or `@Environment(\.dismiss)`)
3. For `item:` sheets — verify the presented view can set the item to nil
4. Check all `.alert()` modifiers have at least one dismiss/cancel action
5. Check all `.confirmationDialog()` have a cancel option
6. Flag multiple `.sheet()` modifiers on the same view (SwiftUI bug: only first fires)
7. Verify every full-screen cover has a close/back button

**Output:** List of sheets/modals that trap the user.

### Scanner 4: Navigation & Exit Paths
**Goal:** Every page has a way to navigate away — no dead ends.

**Process:**
1. Check every page is reachable from the navigation structure (Router files, tab bars, sidebar)
2. Verify every `NavigationLink(value:)` has a corresponding `.navigationDestination(for:)`
3. Verify every `NavigationLink(destination:)` points to a view that exists
4. Check that detail pages have back navigation (NavigationStack provides this, but verify)
5. Look for pages that programmatically push but never pop
6. Check that modal flows (multi-step wizards) have Cancel/Close at every step

**Output:** List of unreachable pages and dead-end navigation.

### Scanner 5: SQL vs Schema Audit
**Goal:** Zero column/table mismatches between service SQL and migration schema.

**Process:**
1. For each service file in `core/Sources/WiredPartCore/Services/`:
   - Extract all raw SQL strings
   - Parse table names and column names referenced
   - Cross-check against `AppDatabase+Migrations.swift`
2. Check for known problem patterns:
   - `unit_price` vs `unit_cost`
   - `part_number` vs `code`
   - `audit_sessions` vs `audit_sessions_v2`
   - Missing `created_by` on NOT NULL columns
   - `updated_at` on tables that don't have it
3. Check `isTableNotFoundError` covers "no such column" too (not just "no such table")

**Output:** List of SQL mismatches with file, line, and correct column.

### Scanner 6: Plan Alignment
**Goal:** Verify implemented features match what the plans describe.

**Process:**
1. Read `docs/plans/ios-page-review-tracker.md` for page-level status
2. Compare against actual page files — are "complete" pages actually complete?
3. Check `docs/plans/master-issue-list.md` for items marked DONE — verify they're actually done
4. Cross-reference GitHub issues — are any closed issues still broken?
5. Check `docs/DevTODO/` for stale tasks

**Output:** List of plan-vs-reality discrepancies.

### Scanner 7: Defensive UX Patterns
**Goal:** Catch usability problems the user wouldn't think to test.

**Process:**
1. **Destructive actions without confirmation** — Any delete, clear, reset, or nuke operation that doesn't show a confirmation dialog first
2. **Data loss on navigation** — Forms/wizards with unsaved data where back/swipe-back discards everything silently
3. **Infinite loading states** — Pages where `isLoading` can get stuck true (e.g., early return without setting `isLoading = false`)
4. **Race conditions in load** — Multiple `.task {}` or `.onAppear {}` that call the same `loadData()` (double-fire on iOS 17+)
5. **Keyboard covers input** — TextField at bottom of screen with no `.scrollDismissesKeyboard()` or keyboard avoidance
6. **Missing pull-to-refresh** — List pages without `.refreshable {}` modifier
7. **Missing search** — List pages with >10 expected items but no `.searchable()` modifier
8. **Tap target size** — Buttons/icons with `.frame(width: N, height: N)` where N < 44
9. **Color-only indicators** — Status shown only with color (no text/icon for colorblind users)
10. **Missing loading indicators** — Pages that fetch data but show no ProgressView during load
11. **Stale data after mutation** — Create/update/delete actions that don't refresh the list afterward
12. **Error messages showing raw errors** — `localizedDescription` shown to users instead of friendly messages
13. **Missing `.environmentObject(appCore)`** on sheets and navigation destinations
14. **Async @State mutations off MainActor** — `@Sendable` functions that modify `@State` without `await MainActor.run {}`
15. **Dismiss-after-await** — `dismiss()` called after `await` in same function (stale `@Environment(\.dismiss)` reference). See #112-#114.
16. **Silent `try?`** — `try?` on save/delete/create operations with no error feedback shown to user. See #121.
17. **Unawaited async saves** — Async save/persist functions called without `await`, dismiss fires before save completes. See #115-#116.
18. **Missing `interactiveDismissDisabled`** — Sheets with form inputs (`TextField`, `TextEditor`) or `isSaving` state but no swipe-dismiss guard. See #123.
19. **Save without feedback** — Save/create/update functions that complete successfully but show no toast, alert, or checkmark to the user.
20. **Delete without confirmation** — Delete operations that execute without a `confirmationDialog` or confirmation alert.

**Output:** List of defensive UX violations with severity.

> **Integration with Usability Hunter:** This agent checks STRUCTURAL correctness (load states, error states, sheet existence). The Usability Hunter (`xcode-ai/skills/usability-hunter/SKILL.md`) checks BEHAVIORAL correctness (dismiss timing, async safety, silent failures, feedback presence). Both share `docs/usability-tracker.md`. Usability Hunter runs at 10 AM; this agent runs at 2 PM. Items 15-20 above mirror the Hunter's top-priority patterns for cross-verification.

### Scanner 8: Feature Completeness
**Goal:** Verify each major feature area has full CRUD and the expected workflow.

**Process:**
For each feature area (Parts, Jobs, People, Warehouse, Orders, Fleet, Tools, Scheduling):
1. **Can list items?** — Main list page loads and shows data
2. **Can create?** — Add/create button exists and the form works
3. **Can view detail?** — Tapping an item opens a detail view
4. **Can edit?** — Detail view has an edit action
5. **Can delete?** — Delete action exists with confirmation
6. **Can search?** — Search bar filters results
7. **Can filter?** — Filter chips/cards narrow results
8. **Can refresh?** — Pull-to-refresh works
9. **Empty state?** — Shows helpful message when no items
10. **Error state?** — Shows retry option when load fails

**Output:** Feature completeness matrix (feature × capability).

---

## Fix Protocol (ENHANCED — Actually Fix, Don't Just Log)

### Severity 1 (Page crashes, data loss, trapped in modal)
**Action: FIX IMMEDIATELY.**
1. Read the plan for the relevant feature
2. Read `AppDatabase+Migrations.swift` for SQL context
3. Fix the root cause in the service/model/UI file
4. Add or update tests to cover the fix
5. Run `cd core && swift build && swift test` — must pass
6. Comment on the GitHub issue with fix details
7. Close the GitHub issue if fully resolved

### Severity 2 (Dead buttons, broken navigation, missing empty states)
**Action: FIX DIRECTLY if service-layer or simple UI. Write Xcode prompt if complex visual.**
1. If it's a service bug, SQL issue, or missing method → fix directly in Swift
2. If it's complex visual UI work → write prompt to `xcode-ai/fix-prompts/`
3. Update `xcode-ai/fix-prompts/00-fix-order.md` if prompt was written
4. Test after each fix: `cd core && swift build && swift test`
5. Comment on GitHub issue with results

### Severity 3 (SQL mismatches, plan drift, minor UX)
**Action: FIX SQL directly. File GitHub issue for plan drift.**
1. Fix SQL column/table mismatches by reading migrations first
2. Add `isTableNotFoundError` wrappers where missing
3. File GitHub issue for anything requiring design decisions
4. Test: `cd core && swift build && swift test`

## After Each Run

1. Update `docs/usability-tracker.md` with findings AND fixes applied
2. **Comment on GitHub issues** for every fix — include files changed, test results
3. **Close GitHub issues** that are fully resolved
4. File new GitHub issues for anything that can't be fixed immediately
5. Create DevTODO files only for complex UI work that needs Xcode AI
6. Update `docs/plans/master-issue-list.md` if items status changed
7. Run `cd /Users/IA/GitHub/Weird-Part-Run-2/core && swift build && swift test` to verify ALL fixes
8. Verify test count ≥ previous (never lose tests)

## Policies

- **FIX first, file second** — always attempt the fix before creating an issue
- **Never break working pages** — if a fix is risky, create a DevTODO instead
- **Always verify SQL against migrations** — never assume column names
- **File GitHub issues for unfixable problems** — single source of truth
- **Check user decisions on DevTODO files** — look for `done` and `Q` tags
- **Unplanned improvements need approval** — ask user with 3 options (keep, remove, plan for later)
- **Read plan before every fix** — `docs/plans/` defines WHAT and WHY
- **Never hardcode user ID `1`** — always flow from session
- **Max 10 fixes per run** — prevent runaway
- **3 consecutive failures on same issue** → skip, comment "Needs manual review"
