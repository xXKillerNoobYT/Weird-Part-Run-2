# PE-029 — Parts Pricing UI (Inline Cascade Editor)

**GitHub Issue:** #48
**Plan:** `docs/plans/ios-pricing-ui.md`
**Priority:** High — managers can't set or view part prices from the app

---

## Context

The pricing schema (Migration 025) and `PricingService` exist in core but the iOS Parts → Pricing page has almost no working UI. This prompt adds inline pricing to the Parts Catalog page using a cascading approach (Type level sets default → Color level can override → per-supplier cost per color).

---

## Owner Decisions (from Q&A)

- **Most critical first:** View current prices + set general (Type-level) cost + per-supplier cost per color
- **Location:** Editable inline in the Parts Catalog page (cascading: Type default → Color override)
- **Price history:** System auto-builds as orders are placed — this prompt just sets initial prices
- **Cascade logic:**
  - Type level → sets default cost for all colors of this type
  - Color level → overrides the type default for this specific color
  - Color × Supplier → supplier's specific cost for this color (used on POs)

---

## Task 1 — Verify PricingService Methods

**File:** `core/Sources/WiredPartCore/Services/PricingService.swift`

Verify (or add if missing):
```swift
public func getEffectivePrice(colorId: Int64, supplierId: Int64?) throws -> Double?
    // Cascades: color override → type default → nil

public func setPriceForType(typeId: Int64, unitCost: Double) throws
    // Sets the default cost for all colors of this type

public func setPriceForColor(colorId: Int64, unitCost: Double) throws
    // Overrides cost for this specific color

public func setSupplierCostForColor(colorId: Int64, supplierId: Int64, cost: Double) throws
    // Sets the cost when ordering this color from a specific supplier

public func getPriceHistory(colorId: Int64) throws -> [PriceHistoryRow]
    // Returns history sorted by date desc (auto-built from orders)
```

All methods need `isTableNotFoundError` guards.

---

## Task 2 — Parts Catalog Page: Pricing Chips on Color Rows

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/IOSPartsCatalogPage.swift`

On **color rows** inside the hierarchy, add:
1. A price chip showing the effective price: `"$4.25"` or `"No price"` in gray
2. Tapping the price chip opens `PriceEditSheet` (see Task 3)
3. The chip should reflect the cascade: if a color override exists, show it; else show the type default (italicized with "(default)" suffix)

---

## Task 3 — PriceEditSheet (New Component)

**Create:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/PriceEditSheet.swift`

Sheet contents:
1. **Header:** "Pricing — [Color Name]"

2. **Type Default section:**
   - Label: "Type Default (applies to all colors of this type unless overridden)"
   - TextField: shows current type default cost, editable
   - Save button → calls `setPriceForType(typeId:unitCost:)`

3. **Color Override section:**
   - Label: "This Color Override"
   - TextField: editable, shows current color override if set
   - If empty: color inherits from type default (show "(inheriting $X.XX from type)" hint)
   - Save button → calls `setPriceForColor(colorId:unitCost:)`
   - Clear button → removes color override (color returns to type default)

4. **Supplier Costs section:**
   - Header: "Cost Per Supplier"
   - List of suppliers linked to this color, each with an editable cost field
   - Each supplier row: supplier name + TextField for that supplier's cost
   - Save per supplier → `setSupplierCostForColor(colorId:supplierId:cost:)`
   - Collapsed in a `DisclosureGroup` by default

5. **Price History section (optional — show if data exists):**
   - Header: "Price History"
   - List from `getPriceHistory(colorId:)` — date + cost per unit
   - Collapsed in a `DisclosureGroup` by default

---

## Task 4 — IOSPricingPage.swift (Existing Dedicated Page)

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/IOSPricingPage.swift`

If this page is mostly empty, add:
1. A searchable list of all types with their current prices
2. Tap a type → expands to show colors with their effective prices + override indicators
3. Tap a color → opens `PriceEditSheet`

This gives managers a dedicated pricing overview in addition to the inline editing in the catalog.

---

## Task 5 — Tests

**File:** `core/Tests/WiredPartCoreTests/PricingServiceTests.swift`

Add:
1. `testSetTypePrice` — set type price, verify `getEffectivePrice` returns it for a color of that type
2. `testColorOverride` — set type price then color override, verify color override wins
3. `testSupplierCostOverride` — set all three levels, verify `getEffectivePrice(supplierId:)` returns supplier cost
4. `testCascadeFallback` — only type price set, verify color + supplier queries fall back to type price

---

## Verification Checklist

- [ ] Color rows in catalog show price chip ("$X.XX" or "No price")
- [ ] Tap price chip → PriceEditSheet opens
- [ ] Set type default price → shows on all colors of that type (with "(default)" label)
- [ ] Set color override → shows without "(default)" label, overrides type
- [ ] Set supplier cost → shown in Supplier Costs section
- [ ] IOSPricingPage shows searchable type list with prices
- [ ] Build: 0 errors, 0 warnings
- [ ] Tests: all existing + 4 new passing
