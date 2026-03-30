# 64C — UI Stability: Fix Loading Errors + Stuck Popups

> **Chain position:** CRITICAL — run before 64A/64B
> **Priority:** HIGHEST — the app is unusable if pages throw errors and popups get stuck
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

The user reports that:
1. Several pages are throwing errors loading info
2. UI behavior is shaky — windows, popups, and other things get stuck open
3. Popups don't close properly throughout the program

This is a **full stability pass**. Read EVERY feature page, find EVERY loading error and popup issue, fix them ALL.

## Part 1: Loading Errors — Find and Fix ALL

### Step 1: Scan for all loading errors

Search ALL files under `Features/` for these patterns:

```
guard let service = appCore.xxxService else {
```

For EVERY instance, verify:
1. `loadError` is set (not just `return`)
2. `isLoading` is set to `false`
3. If the service is optional and expected to be nil sometimes (like during bootstrap), use `return` silently — but add a comment explaining why

### Step 2: Check service initialization order

Read `AppCore.swift` `bootstrap()` and verify ALL services are initialized BEFORE the UI loads. If any service is nil when the UI tries to use it, that's a loading error.

Services that must be initialized:
- authService, settingsService, partsService, warehouseService, jobsService
- ordersService, fleetService, peopleService, schedulingService
- chatService, notebooksService, reportsService, toolsService
- dashboardService, breakService, jobEstimationService

### Step 3: Fix isTableNotFoundError fallbacks

Some services query tables from later migrations. If a device has an older schema, these queries crash. Verify ALL service methods that query tables from migrations 032+ have proper `isTableNotFoundError` fallbacks:

```swift
} catch {
    if isTableNotFoundError(error) { return [] }
    throw error
}
```

### Step 4: Fix any raw error messages shown to users

Replace ALL instances of:
```swift
loadError = error.localizedDescription
```

With a user-friendly wrapper. Create `Shared/UserFriendlyError.swift` if it doesn't exist:

```swift
func userFriendlyError(_ error: Error, context: String = "load data") -> String {
    let raw = error.localizedDescription.lowercased()
    if raw.contains("no such table") {
        return "This feature isn't fully set up yet. Try again after the next sync."
    }
    if raw.contains("no such column") {
        return "App update needed. This feature requires a newer version."
    }
    if raw.contains("unique constraint") {
        return "This item already exists. Try a different name."
    }
    if raw.contains("foreign key") {
        return "A related item is missing. Check that all required data exists."
    }
    if raw.contains("database is locked") {
        return "Database is busy. Please try again."
    }
    if raw.contains("disk i/o error") || raw.contains("no space") {
        return "Storage issue. Check your device has enough space."
    }
    return "Couldn't \(context). Pull down to try again."
}
```

## Part 2: Stuck Popups — Fix ALL Sheet/Alert Dismiss Issues

### Step 1: Audit every .sheet() modifier

Search ALL files for `.sheet(`. For EVERY instance:

**If using `.sheet(item: $activeSheet)`:**
- Verify the sheet content has a way to set `activeSheet = nil`
- Every sheet MUST have either:
  - A "Done" button with `activeSheet = nil`
  - A "Cancel" button with `activeSheet = nil`
  - An `@Environment(\.dismiss) private var dismiss` with `dismiss()` in the sheet view

**If using `.sheet(isPresented: $showXxx)`:**
- Verify the sheet content has a way to set `showXxx = false`
- Check that dismiss buttons actually work

### Step 2: Fix the NavigationStack + dismiss pattern

The most common cause of stuck popups: a sheet view uses `@Environment(\.dismiss)` but is NOT wrapped in a `NavigationStack`. In SwiftUI, `dismiss()` only works for:
- Views pushed onto a NavigationStack
- Sheets that are the direct child of the presenting view

**Fix pattern:**
```swift
// BEFORE (broken — dismiss doesn't work without NavigationStack):
.sheet(item: $activeSheet) { sheet in
    SomeSheetView()
}

// AFTER (works — NavigationStack gives dismiss context):
.sheet(item: $activeSheet) { sheet in
    NavigationStack {
        SomeSheetView()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { activeSheet = nil }
                }
            }
    }
}
```

### Step 3: Fix alert dismiss issues

Search for `.alert(` and verify:
- Every alert has a dismiss button (OK, Cancel, Done)
- Destructive alerts have a cancel option
- No alerts have empty closures `{ }`
- Alert bindings get properly reset (the `isPresented` Bool goes back to false)

### Step 4: Fix .confirmationDialog dismiss

Search for `.confirmationDialog(` and verify:
- Every dialog has a Cancel button (SwiftUI adds one by default, but verify)
- The dialog's binding gets reset after selection

### Step 5: Fix .interactiveDismissDisabled

Search for `.interactiveDismissDisabled`. When this is `true`, the user CANNOT swipe to dismiss. Verify there's ALWAYS a visible button to dismiss instead:

```swift
.interactiveDismissDisabled(true)
// MUST have a visible Done/Cancel button in toolbar
```

### Step 6: Fix sheet presentation conflicts

SwiftUI can get confused when:
- A new sheet is presented while another is dismissing
- Multiple state changes happen in the same runloop tick

Add a small delay between dismiss and re-present:
```swift
// BEFORE (can cause stuck sheet):
activeSheet = nil
activeSheet = .newSheet

// AFTER (clean transition):
activeSheet = nil
Task { @MainActor in
    try? await Task.sleep(for: .milliseconds(300))
    activeSheet = .newSheet
}
```

## Part 3: Verify Every Page Loads Without Error

Go through EVERY router and verify each page can load with empty data (no jobs, no parts, no users besides admin). Pages should show EmptyStateView, not crash or show raw error text.

Test these scenarios:
1. Fresh database — no data except admin user
2. Database with only basic data (1 job, 5 parts)
3. Full database with lots of data

For each page that crashes or shows an error with empty data, fix the guard:
```swift
// If the page needs data to function, show empty state:
if items.isEmpty {
    EmptyStateView(icon: "...", title: "...", message: "...")
}

// If the page needs a service that might not exist:
guard let service = appCore.xxxService else {
    loadError = "Service not available. Please restart the app."
    isLoading = false
    return
}
```

## Success Criteria

- [ ] ZERO pages throw loading errors with empty database
- [ ] ZERO pages throw loading errors with populated database
- [ ] EVERY .sheet() can be dismissed via Done/Cancel button
- [ ] EVERY .alert() can be dismissed
- [ ] NO sheets get stuck open
- [ ] NO alerts get stuck open
- [ ] Error messages shown to users are friendly (not raw localizedDescription)
- [ ] ALL services initialized before UI loads
- [ ] ALL later-migration queries have isTableNotFoundError fallback
- [ ] Project builds with zero errors

## Log Entry

```
## Prompt 64C Results (YYYY-MM-DD)

### Loading Errors Fixed
- Silent guard returns fixed: X
- isTableNotFoundError added: X methods
- Error messages wrapped: X occurrences
- Empty-data pages fixed: X

### Popup Issues Fixed
- Sheets missing dismiss: X
- Sheets missing NavigationStack: X
- Alerts with missing buttons: X
- interactiveDismissDisabled without button: X
- Sheet transition conflicts fixed: X

### Verification
- Pages tested with empty DB: X of X pass
- Pages tested with data: X of X pass

### Build
- Errors: 0
- Warnings: X
```

**This prompt is complete when the app is smooth and stable — no loading errors, no stuck popups, every page loads cleanly.**
