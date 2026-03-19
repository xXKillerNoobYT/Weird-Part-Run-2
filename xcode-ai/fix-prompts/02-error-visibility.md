# Fix Prompt 02: Error Visibility — Users See Blank Screens

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.

---

## The Problem (User Perspective)

When something goes wrong (database error, network issue, missing data), the app shows a blank screen or "No items" instead of telling the user what happened. The errors are being printed to the console where nobody can see them. Users think the feature is empty when really it's broken.

---

## The Pattern To Fix

Find every `catch { print(...) }` block and replace it with one that sets `loadError`:

```swift
// FIND this pattern (appears ~25 times across the app):
catch {
    print("[SomePage] Error: \(error)")
}

// REPLACE with:
catch {
    loadError = error.localizedDescription
    isLoading = false
}
```

Also find every "no such table" suppression and make it visible:

```swift
// FIND this pattern (~15 times):
catch {
    let msg = error.localizedDescription
    if !msg.contains("no such table") {
        print("[SomePage] Error: \(msg)")
    }
}

// REPLACE with:
catch {
    loadError = error.localizedDescription
    isLoading = false
}
```

---

## Files To Fix (all in `Features/`)

Search each file for `catch {` blocks. If the catch block only does `print(...)` without setting `loadError`, fix it.

1. **Dashboard/DashboardView.swift** — `loadData()` catch block
2. **Dashboard/DashboardKPIDetailSheets.swift** — multiple catch blocks
3. **Jobs/IOSJobDetailPage.swift** — `loadData()` catch
4. **Jobs/IOSClockPage.swift** — `loadData()` and `clockIn()`/`clockOut()` catches
5. **Jobs/IOSDailyReportsPage.swift** — `loadData()` catch
6. **Parts/PartsCatalogPage.swift** — `loadData()` catch
7. **Parts/PartsBrandsPage.swift** — `loadData()` catch
8. **Parts/PartsSuppliersPage.swift** — `loadData()` catch
9. **Parts/PartsPricingPage.swift** — `loadData()` catch
10. **Parts/PartsForecastingPage.swift** — `loadData()` catch
11. **Parts/PartsCompanionsPage.swift** — `loadData()` catch
12. **Warehouse/WarehouseLocationsPage.swift** — `loadData()` catch
13. **Warehouse/WarehouseDashboardPage.swift** — `loadData()` catch
14. **Scheduling/IOSDispatchTemplatesPage.swift** — `loadData()` catch
15. **Scheduling/IOSTimeOffPage.swift** — `loadData()` catch
16. **Tools/IOSToolsDashboardPage.swift** — `loadData()` catch (also suppresses "no such table")
17. **Tools/IOSToolRegistryPage.swift** — same
18. **Tools/IOSToolKitsPage.swift** — same
19. **Tools/IOSToolCheckoutsPage.swift** — same
20. **Tools/IOSToolMaintenancePage.swift** — same
21. **Reports/IOSProfitabilityPage.swift** — same
22. **Reports/IOSPreBillingPage.swift** — same
23. **Reports/IOSBookkeeperExportPage.swift** — same
24. **Reports/IOSDailyReportsSummaryPage.swift** — same
25. **Settings/SyncPage.swift** — `loadSettings()` catch

Also confirm each file's `body` actually displays `loadError` when set:
```swift
} else if let error = loadError {
    ErrorStateView(message: error) { loadData() }
}
```

If the view body doesn't have this branch, add it between the `isLoading` check and the content.

---

## Testing Checklist

1. Force an error (e.g., temporarily break a service call) → you should see a red error message with a "Retry" button, NOT a blank screen
2. The "Retry" button should call `loadData()` and recover
3. No `print(...)` should be the only error handling in any `catch` block

---

## When Done

Start **prompt 03 (Infinite Spinners)** next.
