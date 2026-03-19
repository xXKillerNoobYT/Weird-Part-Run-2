# Fix Prompt 03: Infinite Spinners — Pages Get Stuck Loading

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.

---

## The Problem (User Perspective)

Some pages show a loading spinner that never stops. The user stares at a spinning wheel forever. This happens when a service isn't available yet (AppCore hasn't finished initializing it), and the page's `loadData()` function just `return`s without clearing the `isLoading` flag.

---

## The Pattern To Fix

```swift
// FIND this pattern (~10 times):
private func loadData() {
    guard let service = appCore.someService else { return }
    // ...
}

// REPLACE with:
private func loadData() {
    guard let service = appCore.someService else {
        isLoading = false
        loadError = "Service not available yet. Pull down to retry."
        return
    }
    // ...
}
```

---

## Files To Fix

Search each file for `guard let service = appCore.` followed by `else { return }`. Add `isLoading = false` and `loadError = "..."` to each guard's else block.

1. **Features/People/IOSEmployeeDetailPage.swift** — `guard let service = appCore.peopleService`
2. **Features/Tools/IOSToolsDashboardPage.swift** — `guard let service = appCore.toolsService`
3. **Features/Tools/IOSToolRegistryPage.swift** — `guard let service = appCore.toolsService`
4. **Features/Tools/IOSToolCheckoutsPage.swift** — `guard let service = appCore.toolsService`
5. **Features/Tools/IOSToolMaintenancePage.swift** — `guard let service = appCore.toolsService`
6. **Features/Tools/IOSToolAdminPage.swift** — `guard let service = appCore.toolsService`
7. **Features/Reports/IOSSpendingPage.swift** — `guard let service = appCore.reportsService`
8. **Features/Reports/IOSProfitabilityPage.swift** — `guard let service = appCore.reportsService`
9. **Features/Reports/IOSDailyReportsSummaryPage.swift** — `guard let service = appCore.reportsService`

Also check these files have `.refreshable { loadData() }` on their list/scroll view so the user can retry by pulling down.

---

## Testing Checklist

1. Navigate to each page listed above — it should show either content or an error message, NEVER an infinite spinner
2. If the error shows, pull down to refresh — it should retry and either load or show the error again
3. After AppCore finishes bootstrapping, these pages should work normally

---

## When Done

Start **prompt 04 (Stub Sync & Placeholders)** next.
