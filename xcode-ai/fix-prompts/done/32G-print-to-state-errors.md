# 32G — Replace print() Error Logging with UI State (25+ Files)

> **Chain position:** **32G** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `print()` or `debugPrint()` for error logging in UI files
2. ALWAYS set `@State private var loadError: String?` or `@State private var actionError: String?`
3. ALWAYS display errors to the user via `ErrorStateView` or `.alert`

## Instructions

Search ALL `.swift` files in `Weird Parts IOS/Weird Parts IOS/Features/` for:
- `print("[` (the common logging pattern)
- `print("Error`
- `print(error`
- `debugPrint(`

Replace each with proper error state handling.

## Known Files (from audit)

1. IOSLaborOverviewPage.swift — `print("[IOSLaborOverviewPage] Load error:")`
2. IOSAssignDriverSheet.swift — `print("[IOSAssignDriverSheet] Load error:")`
3. IOSMileagePage.swift — `print("[IOSMileagePage] Load error:")`
4. IOSWeeklyAvailabilityPage.swift — `print(...)`
5. IOSTelematicsPage.swift — `print("[IOSTelemeticsPage] Error:")`
6. DashboardView.swift — `print("[DashboardView] Chart data load failed:")`
7. IOSJPOCreationPage.swift — `print("[Feedback] Failed to record:")`
8. IOSFuelPage.swift — `print("[IOSFuelPage] Load error:")`
9. IOSTrailersPage.swift — `print("[IOSTrailersPage] Load error:")`
10. CreatePOSheet.swift — `print("[CreatePOSheet] Load suppliers error:")`
11. PartsCategoriesPage.swift — `print("[PartsCategoriesPage] Load error:")`
12. IOSJobDetailTabView.swift — 6 `print()` calls
13. PartsPricingPage.swift — `print("[PricingEditSheet] Load details error:")`
14. PartsCatalogPage.swift — 3 `print()` calls

Search for MORE — this list may be incomplete.

## Fix Pattern

**For loading errors:**
```swift
// BEFORE
} catch {
    print("[PageName] Load error: \(error)")
}

// AFTER
} catch {
    loadError = error.localizedDescription
    isLoading = false
}
```

**For action errors (save/delete/toggle):**
```swift
// BEFORE
} catch {
    print("[PageName] Save error: \(error)")
}

// AFTER
} catch {
    actionError = error.localizedDescription
}

// Add alert:
.alert("Error", isPresented: .constant(actionError != nil)) {
    Button("OK") { actionError = nil }
} message: {
    Text(actionError ?? "")
}
```

## Success Criteria

- [ ] Zero `print()` error logging in any UI file
- [ ] Every error sets a visible @State variable
- [ ] Every error state has a corresponding UI display (ErrorStateView or alert)
- [ ] Project builds with no errors
