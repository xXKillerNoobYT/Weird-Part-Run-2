# iOS Pricing UI Plan

## What This Does (Plain English)
The Parts Catalog needs inline pricing — you can view and set prices directly from the catalog, cascading from Type level down to Color level. Each color can also have a different cost per supplier. The system builds price history automatically as orders are placed.

## Why We Need This
Currently there's no way to edit prices from the UI. The migration and PricingService exist but the iOS front-end is missing. Workers can't see costs, managers can't set pricing tiers.

## Current State (updated 2026-04-04)
- Migration 025 added base pricing schema; migration 067 adds `default_unit_cost` on `part_types`
- `PricingService` exists in core with cascade resolution
- `CascadePriceEditSheet.swift` (359 lines) — cascade price editor wired in `CategoriesTreeView` ✅
- `PricingBulkEditSheet.swift`, `PricingSettingsSheet.swift` — covered by ios-pricing-system.md ✅
- `PricingOverrideFlow.swift` — **unplanned addition** — hierarchy-level bulk price override (Category/Style/Type/Brand → markup/margin/fixed price with affected-parts preview). No plan reference; extends PE-029 scope. Document for audit trail.
- Remaining gap: **catalog color row price chips** — color rows in `IOSPartsCatalogPage` do not show the current effective price or allow inline editing

## Owner Decisions Applied
- **Most critical first:** View current prices + set general cost + per-supplier cost
- **Location:** Editable inline in the Parts Catalog page using cascading method (Type level sets default, Color level can override)
- **Cascading:** Type sets the initial/default price → Color inherits unless overridden → Supplier link has its own cost
- **Price history:** System builds automatically as orders are placed — initial manual entry is just a starting point
- **Color-level supplier cost:** Each color × supplier combination can have its own cost (matches how real wholesale pricing works — Supplier A charges different than Supplier B for the same part)

## Cascading Price Logic
```
Category → Brand → Type: set DEFAULT cost for all colors of this type
                   ↓ inherits unless overridden
Color: set OVERRIDE cost for this specific color
       ↓ inherits unless overridden
Color × Supplier: set SUPPLIER COST for this color from this supplier
```

When ordering: PO line item uses Color × Supplier cost if set, falls back to Color cost, falls back to Type default cost.

## Files to Modify

### Core — PricingService
**File:** `core/Sources/WiredPartCore/Services/PricingService.swift`

Review and verify these methods exist with correct SQL:
- `getPriceForColor(colorId: Int64) throws -> PriceRow?` — gets effective price (with cascade)
- `setPriceForType(typeId: Int64, unitCost: Double) throws` — sets default for all colors of type
- `setPriceForColor(colorId: Int64, unitCost: Double) throws` — sets override for specific color
- `setSupplierCostForColor(colorId: Int64, supplierId: Int64, cost: Double) throws`
- `getEffectivePrice(colorId: Int64, supplierId: Int64?) throws -> Double` — resolves cascade

### iOS UI — Parts Catalog Page
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/IOSPartsCatalogPage.swift`

Add pricing inline to color rows:
- Color row shows: color name, part number (from #46), and price chip (e.g., "$4.25/ea")
- Tap price chip → inline edit field appears (or price edit sheet)
- Type row shows: default cost badge + "all colors inherit unless overridden"
- Supplier sub-section under color (if expanded): per-supplier cost

Add a "Pricing" section to color detail sheet:
- "General Cost: $___" (editable)
- "Type Default: $___" (read-only, shown for context)
- Per-Supplier Costs: list of linked suppliers with their cost each

Xcode prompt: `PE-029-pricing-ui.md`

### iOS UI — Parts Pricing Page
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/IOSPricingPage.swift`

Rebuild as a proper pricing overview:
- Group by Category → Brand → Type → Color (same hierarchy)
- Each row shows: name, current effective price, source (type/color/supplier)
- Filter: "All", "Missing Price", "Supplier-specific prices"
- Tap row → price edit sheet

## Data Flow
User opens Parts Catalog → sees color row with "$4.25" price chip
User taps price chip → sheet opens with: General Cost field, Type default shown, per-supplier costs list
User types new cost → taps Save → `setPriceForColor(colorId:unitCost:)` called → price updated

When creating a PO line item:
→ `getEffectivePrice(colorId:supplierId:)` called → resolves to Color×Supplier cost → fills PO line amount

## How It Links to Other Features
- Connects to #46 (Part Number Hierarchy) — part numbers on same color rows as pricing
- Connects to #47 (Brand-Supplier relationships) — which supplier to price against
- Connects to Orders — PO creation uses effective price to calculate totals
- Connects to Inventory Intelligence — target/min/max levels use cost for reorder budget calc

## Test Plan
1. Set type default cost $5.00 — create 3 colors — verify all inherit $5.00
2. Override color 1 to $4.50 — verify color 1 = $4.50, others still $5.00
3. Set supplier cost for color 1 from Supplier A to $4.25 — verify `getEffectivePrice(colorId:1, supplierId:A)` = $4.25
4. `getEffectivePrice(colorId:1, supplierId:nil)` = $4.50 (color override)
5. `getEffectivePrice(colorId:2, supplierId:nil)` = $5.00 (type default)
