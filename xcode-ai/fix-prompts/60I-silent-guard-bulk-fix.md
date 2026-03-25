# 60I — Silent Guard-Let-Service Bulk Fix
> Chain position: Standalone
> Log file: xcode-ai/prompt-results-log.md

## Instructions

Across the entire app, there are approximately 130 instances of `guard let service = appCore.xxxService else { return }` that silently fail. When a service is nil (e.g., due to a DB initialization failure), the page shows a spinner forever or goes blank with no error message. Every single one of these guards must set `loadError` and `isLoading = false` before returning so the user sees a meaningful error state.

## Task

### Step 1: Find all instances

Run this grep to find every silent guard:

```bash
grep -rn "guard let.*= appCore\.\w*[Ss]ervice.*else.*{.*return" "Weird Parts IOS/Weird Parts IOS/" --include="*.swift"
```

Also check for multi-line variants:
```bash
grep -rn -A1 "guard let.*= appCore\.\w*[Ss]ervice" "Weird Parts IOS/Weird Parts IOS/" --include="*.swift" | grep "return"
```

### Step 2: Apply the fix pattern

For EVERY instance found, change from this pattern:

```swift
guard let service = appCore.xxxService else { return }
```

To this pattern:

```swift
guard let service = appCore.xxxService else {
    loadError = "Service not available"
    isLoading = false
    return
}
```

**Important nuances:**

**2a. If the guard is inside a `loadData()` function** (most common case):
```swift
// BEFORE:
private func loadData() {
    guard let service = appCore.jobsService else { return }
    isLoading = true
    // ...
}

// AFTER:
private func loadData() {
    guard let service = appCore.jobsService else {
        loadError = "Jobs service not available"
        isLoading = false
        return
    }
    isLoading = true
    // ...
}
```

**2b. If the guard is inside a `Task { }` block:**
```swift
// BEFORE:
Task {
    guard let service = appCore.partsService else { return }
    // ...
}

// AFTER:
Task { @MainActor in
    guard let service = appCore.partsService else {
        loadError = "Parts service not available"
        isLoading = false
        return
    }
    // ...
}
```

**2c. If the guard is inside an action function (not a data load):**
These are functions like `deleteItem()`, `submitForm()`, `toggleStatus()`. These should set `actionError` instead of `loadError`:

```swift
// BEFORE:
private func deleteItem(_ id: Int64) {
    guard let service = appCore.ordersService else { return }
    // ...
}

// AFTER:
private func deleteItem(_ id: Int64) {
    guard let service = appCore.ordersService else {
        actionError = "Service not available"
        return
    }
    // ...
}
```

If the page does not have an `actionError` property, use `loadError` instead.

**2d. If the page does NOT have a `loadError` property:**
Check if the page has any error display variable (e.g., `errorMessage`, `error`, `loadError`). If it does, use that. If it does NOT have any error state at all, ADD one:

```swift
@State private var loadError: String?
```

And add an error display in the body if none exists:

```swift
if let error = loadError {
    ContentUnavailableView(
        "Error",
        systemImage: "exclamationmark.triangle",
        description: Text(error)
    )
}
```

**2e. If there are multiple guards in the same function:**
```swift
// BEFORE:
guard let service = appCore.jobsService,
      let auth = appCore.authService else { return }

// AFTER:
guard let service = appCore.jobsService,
      let auth = appCore.authService else {
    loadError = "Service not available"
    isLoading = false
    return
}
```

### Step 3: Make error messages specific

Use the actual service name in the error message so developers can debug:

| Service variable | Error message |
|-----------------|---------------|
| `jobsService` | "Jobs service not available" |
| `ordersService` | "Orders service not available" |
| `partsService` | "Parts service not available" |
| `warehouseService` | "Warehouse service not available" |
| `peopleService` | "People service not available" |
| `authService` | "Auth service not available" |
| `reportsService` | "Reports service not available" |
| `chatService` | "Chat service not available" |
| `fleetService` | "Fleet service not available" |
| `schedulingService` | "Scheduling service not available" |
| `toolsService` | "Tools service not available" |
| `settingsService` | "Settings service not available" |
| `notebookService` | "Notebooks service not available" |
| `dashboardService` | "Dashboard service not available" |
| `foundationModelsService` | "AI service not available" |

### Step 4: Verify error display exists

For each file modified, verify that `loadError` is actually displayed somewhere in the `body`. Most pages already have an `ErrorStateView` or similar. If a page sets `loadError` but never shows it, add a display:

```swift
// In the body, near the top of the content:
if let error = loadError {
    ErrorStateView(message: error) { loadData() }
}
```

## Files to Modify

Every file returned by the grep command in Step 1. Expected files include (non-exhaustive):

1. `Weird Parts IOS/Weird Parts IOS/Features/Reports/IOSLaborOverviewPage.swift`
2. `Weird Parts IOS/Weird Parts IOS/Features/Reports/IOSDailyReportsSummaryPage.swift`
3. `Weird Parts IOS/Weird Parts IOS/Features/Reports/IOSBookkeeperExportPage.swift`
4. `Weird Parts IOS/Weird Parts IOS/Auth/BusinessProfileSetupView.swift`
5. `Weird Parts IOS/Weird Parts IOS/App/GeofenceAlertView.swift`
6. `Weird Parts IOS/Weird Parts IOS/Auth/LoginView.swift`
7. `Weird Parts IOS/Weird Parts IOS/Features/People/IOSPermissionsPage.swift`
8. `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPOsPage.swift`
9. `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPODetailPage.swift`
10. `Weird Parts IOS/Weird Parts IOS/Features/Jobs/LaborPage.swift`
11. `Weird Parts IOS/Weird Parts IOS/Features/Dashboard/IOSDashboardQRScannerPage.swift`
12. `Weird Parts IOS/Weird Parts IOS/Features/Office/IOSSpendingDashboardPage.swift`
13. Plus all other files found by the grep (approximately 130 instances total across ~40-60 files)

## Success Criteria

- [ ] ZERO instances of `guard let service = appCore.xxxService else { return }` remain (silent returns)
- [ ] Every guard-let-service sets `loadError` (or `actionError`) with a descriptive message
- [ ] Every guard-let-service sets `isLoading = false` (in load functions)
- [ ] Every file that sets `loadError` also displays it somewhere in the body
- [ ] Error messages are specific to the service name (not generic)
- [ ] No compilation errors across the entire project
- [ ] The grep command from Step 1 returns zero results after the fix
