# PE-027 — Part Number Hierarchy at Color Level

**GitHub Issue:** #46
**Plan:** `docs/plans/ios-part-number-hierarchy.md`
**Priority:** High — ordering errors caused by part numbers at wrong level

---

## Context

Part numbers currently sit at the wrong level of the hierarchy (Brand or Type level). The manufacturer and suppliers identify parts at the Color level — e.g., "Romex 12/2 White" is a completely different SKU from "Romex 12/2 Gray". This prompt moves part numbers to the Color level and adds optional supplier-specific part numbers per color.

The tree expansion state fix (lifting `@State` → `@Binding` from `CategoriesTreeView` to `PartsCategoriesPage`) is already done in commit 826dd18. This prompt covers the remaining #46 work: part numbers at color level.

---

## Owner Decisions (from Q&A)

- Part numbers are **per color variant**, not per type or brand
- Each color has its own **internal company part number** (manufacturer's)
- Each color × supplier combination has an optional **supplier part number** (the SKU Supplier A uses vs Supplier B)
- Tree expansion state: **UserDefaults, per session** (already fixed — don't change)
- Search: users search by `[color name] [part number]`, abbreviations (RD=red, WH=white, GR=gray, BK=black), or trade names — not necessarily in order

---

## Task 1 — Core DB Migration

**File:** `core/Sources/WiredPartCore/Migrations/` — add new migration file

```sql
-- Migration: add part_number to parts_colors and supplier_part_number to part_supplier_links
ALTER TABLE parts_colors ADD COLUMN part_number TEXT;
ALTER TABLE part_supplier_links ADD COLUMN supplier_part_number TEXT;
```

Register this migration in `AppDatabase.swift` migrations list.

---

## Task 2 — Update PartsService.swift

**File:** `core/Sources/WiredPartCore/Services/PartsService.swift`

1. **Update `ColorRow` struct** — add fields:
   ```swift
   public var partNumber: String?
   public var supplierPartNumber: String?  // populated when queried per-supplier
   ```

2. **Update `createColor()`** — accept `partNumber: String?` parameter, include in INSERT

3. **Update `updateColor()`** — accept `partNumber: String?` parameter, include in UPDATE

4. **Update `linkColorToSupplier()` or `updateSupplierLink()`** — accept `supplierPartNumber: String?`, save to `part_supplier_links.supplier_part_number`

5. **Update `searchParts(query:)`** — extend to search `parts_colors.part_number`, `part_supplier_links.supplier_part_number`, and common color abbreviations:
   - "RD" or "red" → match colors named "red" / "Red"
   - "WH" or "white" → match "white" / "White"
   - "GR" or "gray" / "grey" → match "gray" / "grey"
   - "BK" or "black" → match "black"
   - Implement as a `colorAbbreviations: [String: String]` dictionary in the search method

6. **Add `getSupplierPartNumbers(colorId:)`** — returns all `[SupplierId: String]` for a given color (for display in the color detail sheet)

---

## Task 3 — iOS Color Row UI (Parts Hierarchy Page)

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/IOSPartsHierarchyPage.swift`
(also check: `IOSCategoriesPage.swift`, `CategoriesTreeView.swift` — use whichever has the color rows)

**Color row changes:**
1. Below the color name, add a secondary label showing the part number:
   - If `part_number != nil`: show `"PN: \(partNumber)"` in `.caption` / gray
   - If `part_number == nil`: show `"No part number"` in `.caption` / gray / italic
2. The color row remains tappable — tap opens `ColorDetailSheet`

**ColorDetailSheet changes** (create if missing, or update existing):
1. **Internal Part Number section:**
   - Label: "Internal Part Number"
   - TextField: editable, placeholder "e.g. 28031450"
   - Save button or inline `.onChange` → calls `updateColor(partNumber:)`

2. **Supplier Part Numbers section:**
   - Header: "Supplier Part Numbers"
   - For each supplier linked to this color: show supplier name + their part number (editable TextField)
   - `+` button to add a supplier part number for a new supplier (picker from linked suppliers)
   - Save each supplier part number → calls `updateSupplierLink(colorId:supplierId:supplierPartNumber:)`

3. Use a `DisclosureGroup` for the Supplier Part Numbers section (collapsed by default to keep the sheet clean)

---

## Task 4 — Tests

**File:** `core/Tests/WiredPartCoreTests/PartsServiceTests.swift`

Add tests:
1. `testColorPartNumber` — create color with part number, fetch, verify `part_number` field
2. `testSupplierPartNumber` — link color to supplier with supplier part number, fetch supplier links, verify `supplier_part_number`
3. `testSearchByPartNumber` — seed color with `part_number = "28031450"`, search "28031450", verify match
4. `testSearchByAbbreviation` — seed color named "Red", search "RD", verify match

---

## Verification Checklist

- [ ] Migration runs: `parts_colors.part_number` column exists after first launch
- [ ] `part_supplier_links.supplier_part_number` column exists after first launch
- [ ] Create color with part number → appears in color row as "PN: ..."
- [ ] Edit part number in ColorDetailSheet → saved and shown on reload
- [ ] Add supplier part number → shown in Supplier Part Numbers section
- [ ] Search "12/2" → colors with matching part numbers appear
- [ ] Search "RD" → Red colors appear
- [ ] Build: 0 errors, 0 warnings
- [ ] Tests: all existing + 4 new passing

---

## Notes

- Do NOT change the tree expansion state logic (already fixed in 826dd18)
- Do NOT remove part numbers from any existing fields until the migration is confirmed working
- The `part_supplier_links` table already exists — only add the new column, don't recreate it
