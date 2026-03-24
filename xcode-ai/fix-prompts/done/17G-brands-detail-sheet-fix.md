# 17G — Fix BrandDetailSheet Double .sheet Conflict

> **Chain position:** 17A → 17B → 17C → 17D → 17E → 17F → **17G** → 17H
> **Prerequisite:** 17F complete
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

`PartsBrandsPage.swift` has a `BrandDetailSheet` with **two `.sheet` modifiers** (around lines 476-487). SwiftUI only respects the first `.sheet` on a view — the second one (supplier picker) will never present. This is the same bug pattern fixed throughout the app in prompt 01.

Also: `supplierCount: 0` is hardcoded in `loadData()` (around line 233) instead of querying the actual count.

**Key file:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsBrandsPage.swift` — `BrandDetailSheet` (around line 400+)

## Task

### Step 1: Fix the double .sheet in BrandDetailSheet

Replace the two separate `.sheet(isPresented:)` modifiers with a single `.sheet(item:)` using an enum pattern:

In `BrandDetailSheet`, add an enum:

```swift
private enum DetailActiveSheet: Identifiable {
    case editBrand
    case supplierPicker

    var id: String {
        switch self {
        case .editBrand: return "editBrand"
        case .supplierPicker: return "supplierPicker"
        }
    }
}

@State private var activeDetailSheet: DetailActiveSheet?
```

Remove the two `@State private var showEditForm` and `@State private var showSupplierPicker` booleans.

Update the buttons that set these:
```swift
// Edit button:
Button { activeDetailSheet = .editBrand } label: { Image(systemName: "pencil") }

// Manage Suppliers button:
Button { activeDetailSheet = .supplierPicker } label: { /* existing label */ }
```

Replace both `.sheet(isPresented:)` modifiers with one `.sheet(item:)`:

```swift
.sheet(item: $activeDetailSheet) { sheet in
    switch sheet {
    case .editBrand:
        BrandFormSheet(brand: brand) {
            await onUpdate()
        }
        .environmentObject(appCore)
    case .supplierPicker:
        BrandSupplierPickerSheet(brandId: brand.id) {
            loadSuppliers()
        }
        .environmentObject(appCore)
    }
}
```

### Step 2: Fix hardcoded supplierCount

In `loadData()` on `PartsBrandsPage`, find where `BrandListRow` is constructed. The `supplierCount` should come from a query, not be hardcoded to 0.

Update the brand query to include supplier count:

```swift
// Add to the SELECT for brands:
(SELECT COUNT(*) FROM brand_suppliers WHERE brand_id = brands.id AND deleted_at IS NULL) AS supplier_count
```

Map it:
```swift
supplierCount: row["supplier_count"] ?? 0
```

If `loadData()` currently uses a `PartsService` method (per prompt 15A), update that service method to include the supplier count subquery. If it's still using raw SQL, update the SQL directly.

### Step 3: Verify BrandFormSheet dismissal

After fixing the `.sheet` pattern, ensure that when `BrandFormSheet` saves and dismisses, the brand detail refreshes. The `onUpdate` closure should trigger a reload of the brand list.

Check that the `.sheet(item:)` closure properly passes `onUpdate`:
```swift
case .editBrand:
    BrandFormSheet(brand: brand) {
        await onUpdate()
    }
    .environmentObject(appCore)
```

## Important Notes

- This is the same fix pattern used in prompt 01 across 7 other files. The single `.sheet(item:)` with an enum is the standard pattern.
- The `BrandDetailSheet` is itself shown inside a `.sheet` on the parent `PartsBrandsPage`. Having a second-level `.sheet(item:)` inside it is fine — the conflict was two `.sheet` on the SAME view, not nested sheets.
- After this fix, both the edit form AND the supplier picker will correctly present from the brand detail sheet.

## Success Criteria

- [ ] `BrandDetailSheet` has exactly ONE `.sheet(item:)` modifier
- [ ] Edit brand form presents correctly from detail sheet
- [ ] Supplier picker presents correctly from detail sheet
- [ ] `supplierCount` shows actual count, not hardcoded 0
- [ ] Brand detail refreshes after editing
- [ ] Project builds with no errors

## Log Entry

Append to `xcode-ai/prompt-results-log.md`:
```
## Prompt 17G Results (YYYY-MM-DD)
- BrandDetailSheet: fixed double .sheet → single .sheet(item:) enum pattern
- supplierCount: fixed hardcoded 0 → actual query count
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 17H.**
