# 61G — Fix 2 Placeholder NavigationLinks

> **Chain position:** **61G** (standalone)
> **Issue:** T2-09
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT leave any NavigationLink pointing to a bare `Text()` placeholder
2. Each link must navigate to a REAL, EXISTING page
3. Pass the correct parameters to the destination page
4. Project must build with zero errors when done

## Context

Two NavigationLinks currently navigate to bare `Text("Coming Soon")` or similar placeholder views instead of real pages. The destination pages already exist — the links just weren't wired to them.

## Files to Fix

### 1. IOSFleetDashboardPage — "Fleet Reports" Link

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Fleet/IOSFleetDashboardPage.swift`

**Current (broken):**
```swift
NavigationLink {
    Text("Fleet Reports")  // or Text("Coming Soon")
} label: {
    Label("Fleet Reports", systemImage: "chart.bar")
}
```

**Fix:** Navigate to `IOSReportsRouter` with the Fleet category pre-selected:
```swift
NavigationLink {
    IOSReportsRouter(initialCategory: "Fleet")
} label: {
    Label("Fleet Reports", systemImage: "chart.bar")
}
```

If `IOSReportsRouter` doesn't accept an `initialCategory` parameter, add one:
```swift
struct IOSReportsRouter: View {
    var initialCategory: String? = nil  // ADD THIS

    // In the body, use initialCategory to pre-select the category:
    .onAppear {
        if let category = initialCategory {
            selectedCategory = category
        }
    }
}
```

Check `IOSReportsRouter` to see what categories exist. The Fleet category should include reports like Fleet Utilization, Maintenance Trends, Mileage Summary, Fuel Cost.

### 2. IOSPODetailPage — "Supplier Profile" Link

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPODetailPage.swift`

**Current (broken):**
```swift
NavigationLink {
    Text("Supplier Profile")  // or Text("Coming Soon")
} label: {
    Label("View Supplier", systemImage: "building.2")
}
```

**Fix:** Navigate to `PartsSuppliersPage` filtered to the specific supplier:
```swift
NavigationLink {
    PartsSuppliersPage(highlightSupplierId: purchaseOrder.supplierId)
} label: {
    Label("View Supplier", systemImage: "building.2")
}
```

If `PartsSuppliersPage` doesn't accept a `highlightSupplierId` parameter, add one:
```swift
struct PartsSuppliersPage: View {
    var highlightSupplierId: Int64? = nil  // ADD THIS

    // In the body, scroll to and highlight the supplier:
    .onAppear {
        if let supplierId = highlightSupplierId {
            selectedSupplierId = supplierId
            // Optionally scroll to the supplier in the list
        }
    }
}
```

Alternatively, if there's a supplier detail page (IOSSupplierDetailPage or similar), navigate there directly with the supplier ID.

## Verification

After fixing both links:
1. Search the entire project for `NavigationLink` destinations that are bare `Text(` views
2. If any others exist, fix them too using the same pattern
3. Run a build to verify no type mismatches

```
Search pattern: NavigationLink.*\{.*Text\("
```

## Success Criteria

- [ ] "Fleet Reports" navigates to IOSReportsRouter with Fleet category
- [ ] "Supplier Profile" navigates to PartsSuppliersPage filtered to the supplier
- [ ] Both destination pages receive correct parameters
- [ ] No remaining NavigationLinks pointing to bare Text() placeholders
- [ ] Project builds with zero errors
