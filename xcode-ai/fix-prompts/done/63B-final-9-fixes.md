# 63B — Final 9 Audit Fixes + Popup Dismiss Fix

> **Chain position:** After 63A final gate
> **Priority:** CRITICAL — these are the last items blocking 100% audit pass
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

Fix ALL 9 remaining audit failures plus the popup dismiss issue reported by the user. Verify the project builds after all fixes.

## Fix 1: Dashboard QR Scanner — Empty Button (W1)

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Dashboard/IOSDashboardQRScannerPage.swift`
**Line:** ~409
**Issue:** `DSQuickActionButton(title: "Details", icon: "info.circle", color: .blue) {}` — empty closure
**Fix:** Wire to show a detail sheet for the scanned item, or remove the button if it's redundant with other actions.

## Fix 2: AI Dispatch Not Surfaced in UI (FF2)

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSShortTermPipelinePage.swift`
**Issue:** "AI Suggest" toolbar button has an empty placeholder closure. AIDispatchService exists in core but is not called from the UI.
**Fix:** Wire the AI Suggest button to call `AIDispatchService.generateSuggestions()` and display results in a sheet. If AIDispatchService is not in AppCore, add it (property + initialization in bootstrap).

## Fix 3: Panel Schedule Persistence (GG3)

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Notebooks/IOSNotebookDetailPage.swift`
**Line:** ~684
**Issue:** `// TODO: Persist panel schedule data to notebook metadata`
**Fix:** Save panel schedule data to the notebook entry's metadata field via `notebooksService.updateEntry()`.

## Fix 4: Old Chip Patterns → SmartFilterCard (LL1)

**Files:**
- `Features/Tools/IOSToolRegistryPage.swift`
- `Features/People/IOSEmployeesPage.swift`
- `Features/Notebooks/IOSJobNotebooksPage.swift`

**Issue:** These 3 pages still use old-style capsule chip filter bars instead of `SmartFilterCard`.
**Fix:** Replace the horizontal ScrollView with capsule buttons with `SmartFilterCard` components showing counts, following the same pattern used in IOSPurchaseOrdersPage or IOSVehiclesPage.

## Fix 5: Error Messages — User-Friendly Wrapping (LL9)

**Issue:** ~50+ occurrences of `loadError = error.localizedDescription` expose raw Swift/SQLite error text to users.
**Fix:** Create a helper function in `Shared/`:

```swift
/// Wraps a raw error into a user-friendly message.
func userFriendlyError(_ error: Error, context: String = "load data") -> String {
    let raw = error.localizedDescription
    if raw.contains("no such table") {
        return "This feature isn't set up yet. Contact your admin."
    }
    if raw.contains("UNIQUE constraint") {
        return "This item already exists. Try a different name or code."
    }
    if raw.contains("FOREIGN KEY constraint") {
        return "Can't complete this action — a related item is missing."
    }
    if raw.contains("database is locked") {
        return "The database is busy. Please try again in a moment."
    }
    return "Couldn't \(context). Pull down to retry."
}
```

Then replace ALL `loadError = error.localizedDescription` with `loadError = userFriendlyError(error, context: "load parts")` (use appropriate context per page). Do NOT change action-error alerts (like save/delete failures) — only loadData error handlers.

## Fix 6: Silent Guard Returns (LL15)

**Files with silent guards:**
- `Features/Orders/IOSWishlistPage.swift` (5 instances)
- `Features/Orders/IOSPODetailPage.swift` (1 instance)
- `Features/Dashboard/IOSDashboardQRScannerPage.swift` (1 instance)

**Fix:** Every `guard let service = appCore.xxxService else { return }` must set `loadError` and `isLoading = false`:

```swift
guard let service = appCore.ordersService else {
    loadError = "Service not available"
    isLoading = false
    return
}
```

## Fix 7: Popup Dismiss — Program-Wide Fix

**Issue:** User reports that popups (sheets) don't close properly throughout the program. The Done/Cancel/Close buttons on sheet views are not dismissing.

**Root cause investigation:** Check ALL sheet views for:
1. Missing `@Environment(\.dismiss) private var dismiss`
2. Done/Cancel buttons that don't call `dismiss()`
3. `.interactiveDismissDisabled(true)` without a working cancel button
4. Sheets that use `isPresented` binding but the binding doesn't get set to `false`

**Fix approach:** Search ALL files for `.sheet(` and verify every sheet has a working dismiss mechanism. Key files to check:
- All `*Sheet.swift` files
- All files with `ActiveSheet` enum + `.sheet(item:)`
- Verify the `item` binding gets set to `nil` on dismiss

Common pattern that should work everywhere:
```swift
.sheet(item: $activeSheet) { sheet in
    NavigationStack {
        // content
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { activeSheet = nil }
            }
        }
    }
}
```

If sheets use `@Environment(\.dismiss)`, make sure the sheet is presented in a `NavigationStack` — `dismiss()` only works inside a `NavigationStack` for sheets.

## Fix 8: OfficePlaceholderView — Dead Code Removal

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Office/OfficePlaceholderView.swift`
**Issue:** This file is never referenced anywhere in the codebase. It's dead code.
**Fix:** Delete the file entirely. Remove from the Xcode project.

## Fix 9: Office Dashboard — AttentionItem Navigation

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Office/IOSOfficeDashboardPage.swift`
**Issue:** `selectedAttentionItem` state was added but the `.onChange` or alert to show the item detail is not wired yet.
**Fix:** Add an `.alert` or `.sheet` that shows when `selectedAttentionItem` is set, displaying the item's title, subtitle, and a suggestion for where to go to address it.

## Success Criteria

- [ ] ZERO empty button closures in any Features file
- [ ] AI Dispatch button on Short-Term Pipeline is functional
- [ ] Panel schedule data persists to notebook
- [ ] All 3 pages use SmartFilterCard instead of old chips
- [ ] Error messages are user-friendly (no raw localizedDescription in loadData)
- [ ] ZERO silent guard-let-service returns
- [ ] ALL popups close properly (Done/Cancel/Close buttons work)
- [ ] OfficePlaceholderView deleted
- [ ] Office attention items navigate or show detail
- [ ] Project builds with zero errors

## Log Entry

```
## Prompt 63B Results (YYYY-MM-DD)
- Empty buttons fixed: X
- AI Dispatch wired: Yes/No
- Panel schedule persistence: Yes/No
- SmartFilterCard migration: 3 pages
- Error messages wrapped: X occurrences
- Silent guards fixed: 7 instances
- Popup dismiss fixed: X sheets
- Dead code removed: OfficePlaceholderView
- Attention items wired: Yes/No
- Build: PASS/FAIL
```
