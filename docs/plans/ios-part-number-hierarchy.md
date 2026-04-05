# iOS Part Number Hierarchy Plan

## What This Does (Plain English)
Part numbers belong to the COLOR level of the parts hierarchy (not brand, not type). Each color variant has its own manufacturer part number AND an optional supplier-specific part number per supplier. The hierarchy tree on iOS also needs to stop collapsing every time data changes.

## Why We Need This
Currently part numbers sit at the wrong level — the app may be displaying brand-level part numbers but the manufacturer and suppliers use color-level part numbers (e.g., "Romex 12/2 White" is a different part number from "Romex 12/2 Gray"). This causes ordering errors and lookup confusion.

## Current State
- Parts hierarchy: Category → Brand → Type → Color
- Part numbers may be stored/displayed at Brand or Type level
- Hierarchy tree expansion state resets on every data change (SwiftUI re-render)
- Search works on name but not on part number + abbreviations

## Owner Decisions Applied
- **Part numbers at Color level** — each color variant has its own part number from the manufacturer
- **Optional Supplier Part Number per color per supplier** — when ordering from Supplier A, the Supplier A part number is used; when ordering from Supplier B, Supplier B's part number is used
- **Hierarchy tree expansion** — persisted per session (UserDefaults, not DB)
- **Search** — user should be able to search by: `[color name] [part number]`, abbreviations (RD for red), or trade names — NOT necessarily in order

## Files to Modify

### Core — Schema Changes
**New DB Migration:**
- Remove `part_number` from `parts_types` or `parts_brands` (wherever it currently lives incorrectly)
- Add to `parts_colors` table: `part_number TEXT` (internal company part number)
- Add to `part_supplier_links` table: `supplier_part_number TEXT` (supplier's own SKU/part number for this color)
- Both nullable — not every color needs a part number immediately

### Core — Service Changes
**File:** `core/Sources/WiredPartCore/Services/PartsService.swift`
- Update all queries that read/write part numbers to use `parts_colors.part_number`
- Add `supplierPartNumber` to `ColorRow` struct
- Update `createColor()`/`updateColor()` to accept `partNumber: String?`
- Update `linkColorToSupplier()` or equivalent to accept `supplierPartNumber: String?`
- Update search: `searchParts(query:)` should search `parts_colors.part_number`, `part_supplier_links.supplier_part_number`, `parts_colors.name`, `parts_types.name`, `parts_brands.name`

### iOS UI — Parts Hierarchy Tree
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/IOSPartsHierarchyPage.swift` (or similar)

**Tree expansion state persistence:**
- Store expanded node IDs in `@AppStorage("parts_tree_expanded_ids")` as a JSON-encoded `Set<String>`
- Key format: `"brand-\(id)"`, `"type-\(id)"`, `"color-\(id)"`
- On expand/collapse: update the `@AppStorage` value
- On data reload: restore expansion state from `@AppStorage` before rendering

**Color row UI:**
- Show `part_number` field (editable inline or via detail sheet)
- Show supplier part numbers per supplier (small list under color row, collapsible)
- Edit color → edit part number + edit per-supplier part numbers

**Search improvements:**
- Search bar queries all levels simultaneously
- Highlight matching text in results
- Support abbreviations: RD/red, WH/white, GR/gray, BK/black (configurable in Settings)

Xcode prompt: `PE-027-part-number-hierarchy.md`

## Data Flow
User opens Parts Hierarchy → tree loads with expansion state from UserDefaults
User taps Color row → color detail sheet opens → shows: color name, internal part number, supplier part numbers list
User edits internal part number → `updateColor(id:partNumber:)` called → saves to `parts_colors.part_number`
User adds supplier part number → `updateSupplierLink(colorId:supplierId:supplierPartNumber:)` called → saves to `part_supplier_links.supplier_part_number`

When ordering → Order form pulls `supplier_part_number` for selected supplier → pre-fills PO line item

## How It Links to Other Features
- Connects to #47 (Brands/Suppliers editing) — supplier part numbers link to `part_supplier_links`
- Connects to Orders — PO line items should reference supplier part numbers
- Connects to Search — full part search should include part numbers

## Test Plan
1. Migration runs — verify `parts_colors.part_number` column exists
2. Create color with part number — verify saved
3. Link color to supplier with supplier part number — verify `part_supplier_links.supplier_part_number` saved
4. Search "12/2" — verify color with matching part number appears
5. Expand tree, change data, verify expansion state preserved in same session
6. Restart app — verify expansion state resets (session-only per owner)

## Apple HIG Notes
- Part number field on color rows should be styled as secondary info (caption, gray)
- Supplier part numbers can collapse into a disclosure group under the color row
