# PE-028 — Brands & Suppliers Editing + Brand-Supplier Linking

**GitHub Issue:** #47
**Plan:** `docs/plans/ios-brands-suppliers-editing.md`
**Priority:** High — users can't manage which suppliers carry which brands

---

## Context

The Brands page and Suppliers page need:
1. Visible edit flows (currently may only be via swipe-left which is hard to discover)
2. Two-way brand-supplier linking:
   - Brands page: see/edit which suppliers carry this brand
   - Suppliers page: see/edit which brands they carry (with "carry on shelf" vs "need to order" flag)
3. Warning when a brand has no supplier linked

---

## Owner Decisions (from Q&A)

- **Brands page:** Shows editable list of suppliers who carry that brand (easy to update)
- **New brand flow:** Prompt "which suppliers carry this brand?" — orange warning if skipped (no supplier selected)
- **Suppliers page:** Show editable list of brands they carry, with a per-brand toggle: `carry_on_shelf` vs `need_to_order`
- `BrandSupplierPickerSheet` already exists — wire it from the Brands page

---

## Task 1 — Core DB Migration

**New table:**
```sql
CREATE TABLE IF NOT EXISTS brand_supplier_relationships (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    brand_id INTEGER NOT NULL REFERENCES parts_brands(id) ON DELETE CASCADE,
    supplier_id INTEGER NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
    carry_status TEXT DEFAULT 'carry_on_shelf'
        CHECK (carry_status IN ('carry_on_shelf', 'need_to_order')),
    created_at TEXT DEFAULT (datetime('now')),
    UNIQUE(brand_id, supplier_id)
);
```

Register in migrations list.

---

## Task 2 — Update PartsService / SupplierService

**File:** `core/Sources/WiredPartCore/Services/PartsService.swift` (or create a SupplierService extension)

Add:
```swift
public struct BrandSupplierRow: Sendable {
    public var id: Int64
    public var brandId: Int64
    public var supplierId: Int64
    public var supplierName: String
    public var carryStatus: String  // "carry_on_shelf" | "need_to_order"
}

public func getBrandSuppliers(brandId: Int64) throws -> [BrandSupplierRow]
public func addBrandSupplier(brandId: Int64, supplierId: Int64, status: String = "carry_on_shelf") throws
public func removeBrandSupplier(brandId: Int64, supplierId: Int64) throws
public func updateBrandSupplierStatus(brandId: Int64, supplierId: Int64, status: String) throws
public func getSupplierBrands(supplierId: Int64) throws -> [BrandSupplierRow]  // returns brandId, brandName, carryStatus
```

All methods need `isTableNotFoundError → return [] / return` guards.

---

## Task 3 — Brands Page (PartsBrandsPage.swift)

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsBrandsPage.swift`

### Brand Row
- Make brand rows tappable → opens `BrandDetailSheet` (create or update)
- Row shows: brand name, color swatch, **+ orange warning dot if no suppliers linked**

### BrandDetailSheet
Include a "Suppliers Carrying This Brand" section:
1. List of linked suppliers (from `getBrandSuppliers(brandId:)`)
   - Each row: supplier name + `carry_on_shelf` / `need_to_order` chip
   - Swipe left → Remove from list
2. `+` button → opens existing `BrandSupplierPickerSheet` to add more suppliers
3. If list is empty: show orange warning banner "No supplier linked — add at least one"

### Add Brand Flow
When user taps "New Brand" → create brand → then show prompt:
```
"Which suppliers carry [BrandName]?"
[Supplier picker list with checkboxes]
[Skip for now]  <- if skipped, brand shows orange warning
```

---

## Task 4 — Suppliers Page (PartsSuppliersPage.swift)

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsSuppliersPage.swift`

### Supplier Row
- Rows already tappable → ensure `SupplierDetailSheet` exists and is wired

### SupplierDetailSheet
Add a "Brands Carried" section:
1. List from `getSupplierBrands(supplierId:)`
   - Each row: brand name + toggle `carry_on_shelf` ↔ `need_to_order`
   - Toggle tap → calls `updateBrandSupplierStatus()`
   - Swipe left → Remove brand from this supplier
2. `+` button → brand picker (list of all brands) → `addBrandSupplier()`

---

## Task 5 — Tests

**File:** `core/Tests/WiredPartCoreTests/PartsServiceTests.swift`

Add:
1. `testAddBrandSupplier` — add brand-supplier relationship, fetch with `getBrandSuppliers`, verify
2. `testUpdateBrandSupplierStatus` — change carry status, verify updated
3. `testRemoveBrandSupplier` — add then remove, verify gone
4. `testGetSupplierBrands` — link 2 brands to supplier, fetch with `getSupplierBrands`, verify both returned

---

## Verification Checklist

- [ ] `brand_supplier_relationships` table created by migration
- [ ] Brand row shows orange warning when no supplier linked
- [ ] Tap brand row → BrandDetailSheet shows supplier list
- [ ] Add supplier from BrandDetailSheet → appears in list
- [ ] Skip supplier prompt → orange warning visible on brand row
- [ ] Supplier detail shows brands with carry status toggles
- [ ] Toggle carry status → saved
- [ ] Build: 0 errors, 0 warnings
- [ ] Tests: all existing + 4 new passing
