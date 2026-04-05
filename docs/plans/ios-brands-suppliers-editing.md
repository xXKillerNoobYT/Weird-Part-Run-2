# iOS Brands & Suppliers Editing Plan

## What This Does (Plain English)
The Brands and Suppliers pages need full edit capability and a two-way linking system. On the Brand page you can see and edit which suppliers carry that brand. On the Supplier page you can see and edit which brands they carry, plus set whether you "need to order" or "carry on the shelf" for each brand.

## Why We Need This
Currently there's no way to edit brands or suppliers from the UI, and no way to manage the brand-supplier relationship bidirectionally. This blocks accurate ordering (can't know which supplier to call for which brand).

## Current State
- `PartsBrandsPage.swift` and `PartsSuppliersPage.swift` exist
- `BrandSupplierPickerSheet` exists but may not be triggered from correct locations
- No visible edit flow for Brand or Supplier from their respective pages
- `part_supplier_links` table connects colors to suppliers, but brand-level supplier relationships may not be in schema

## Owner Decisions Applied
- **Brands page:** Shows editable list of suppliers that carry each brand
  - Orange warning if no supplier is linked ("you should have at least one supplier for this brand")
  - Can add/remove suppliers from this list inline
  - When adding a new brand, prompt "Which suppliers carry this brand?" (skippable, orange if skipped)
- **Suppliers page:** Shows editable list of brands they carry
  - Per-brand option: "Need to Order" or "Carry on Shelf" toggle
  - This is an overall flag at brand level (not part-by-part — parts build up their own history as orders are placed)
- **BrandSupplierPickerSheet:** Used from Brands page to select which suppliers carry the brand

## Schema Changes Needed

### New DB Migration
```sql
-- Brand-level supplier relationships (separate from part-level supplier links)
CREATE TABLE brand_supplier_relationships (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    brand_id INTEGER NOT NULL REFERENCES parts_brands(id) ON DELETE CASCADE,
    supplier_id INTEGER NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
    carry_status TEXT DEFAULT 'carry_on_shelf' CHECK (carry_status IN ('carry_on_shelf', 'need_to_order')),
    created_at TEXT DEFAULT (datetime('now')),
    UNIQUE(brand_id, supplier_id)
)
```

## Files to Modify

### Core Service
**File:** `core/Sources/WiredPartCore/Services/PartsService.swift` (or `SupplierService.swift`)

New methods:
- `getBrandSuppliers(brandId: Int64) throws -> [BrandSupplierRow]`
- `addBrandSupplier(brandId: Int64, supplierId: Int64, status: String) throws`
- `removeBrandSupplier(brandId: Int64, supplierId: Int64) throws`
- `updateBrandSupplierStatus(brandId: Int64, supplierId: Int64, status: String) throws`
- `getSupplierBrands(supplierId: Int64) throws -> [BrandSupplierRow]`

Struct:
```swift
public struct BrandSupplierRow: Identifiable {
    public let id: Int64
    public let brandId: Int64
    public let brandName: String
    public let supplierId: Int64
    public let supplierName: String
    public let carryStatus: String  // "carry_on_shelf" | "need_to_order"
}
```

### iOS UI — Brands Page
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsBrandsPage.swift`

Brand row edit:
- Tap brand → Brand Detail Sheet opens
- Shows: brand name (editable), logo, and "Suppliers" section
- Suppliers section: list of linked suppliers with status badges ("On Shelf" / "Need to Order")
- Add/remove suppliers from the list (uses BrandSupplierPickerSheet)
- Orange badge on brand row if no supplier linked

New brand flow:
- After saving name, show "Add Suppliers?" prompt (can skip → orange indicator)

### iOS UI — Suppliers Page
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsSuppliersPage.swift`

Supplier detail:
- Shows: supplier info + "Brands Carried" section
- Each brand row: brand name + "Carry on Shelf" / "Need to Order" toggle
- Can add/remove brands from the list

Xcode prompt: `PE-028-brands-suppliers-editing.md`

## Data Flow
User opens Brands page → taps a brand row → Brand Detail Sheet opens → shows linked suppliers
User taps "Add Supplier" → BrandSupplierPickerSheet shows → picks supplier → `addBrandSupplier()` called
User taps supplier row in Brands detail → toggle "Need to Order" / "Carry on Shelf" → `updateBrandSupplierStatus()` called

Reverse: opens Suppliers page → taps supplier → shows brands carried → same edit actions

## How It Links to Other Features
- Connects to #46 (Part Number Hierarchy) — supplier part numbers are at color level, but which supplier to use comes from brand-level relationships
- Connects to #48 (Pricing) — knowing which suppliers carry a brand helps set up pricing tiers
- Connects to Orders — PO creation can use brand-supplier relationships to suggest which supplier to order from

## Test Plan
1. Add brand "Romex" → link suppliers "Graybar", "Home Depot" → verify `brand_supplier_relationships` rows
2. Open Suppliers page → tap "Graybar" → verify "Romex" appears in brands list
3. Toggle "Romex" to "Need to Order" on Graybar → verify carry_status = 'need_to_order'
4. Add new brand without supplier → verify orange indicator shown
