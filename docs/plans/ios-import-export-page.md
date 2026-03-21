# iOS Import/Export Page — Design Plan

> **Status:** Design CONFIRMED — Prompt 24A pending
> **Prompts:** `xcode-ai/fix-prompts/24A-import-export-redesign.md`
> **Last updated:** 2026-03-21

---

## Current State

The page works but has architectural violations (raw SQL, `import GRDB`, platform guards) and is missing key features (no duplicate handling, no import preview, limited export fields, no field selection).

### Issues Found

| # | Severity | Issue |
|---|----------|-------|
| 1 | High | `import GRDB` — raw SQL for stats, export, and import |
| 2 | High | Import does raw `INSERT INTO parts` — bypasses service layer, no validation, no change tracking |
| 3 | Medium | 4x `#if os(iOS)` / `#elseif os(macOS)` platform guards |
| 4 | Medium | No loadError display — catch block silently swallows errors |
| 5 | Medium | Import doesn't check for duplicates |
| 6 | Medium | Export doesn't include all fields |
| 7 | Low | Missing columns in import: style, type, color, stock levels |
| 8 | Low | No import preview before committing |

### What's Working Well

- CSV parsing handles quoted fields correctly
- Export confirmation dialog
- Status enum pattern (idle/exporting/success/error)
- Security-scoped resource access for file importer
- Stats section with counts
- CSV format documentation section

---

## Design Decisions

### Export — Selectable Fields

The user can choose which fields to export. "All" is an option.

**Field groups (checkboxes):**

| Group | Fields | Default |
|-------|--------|---------|
| **Basic (always included)** | name, code | Always on |
| **Hierarchy** | category, style, type, brand, color | On |
| **Pricing** | cost_price, markup_percent, sell_price, pricing_tier_level | Off |
| **Stock Levels** | min_stock, target_stock, max_stock, current_stock | Off |
| **Forecast** | forecast_adu_30, forecast_adu_90, forecast_days_until_low, forecast_suggested_order | Off |
| **Details** | description, unit_of_measure, part_type, shelf_location, bin_location | Off |
| **All** | Select all groups | Toggle |

**Export writes to Documents directory** (no share sheet per user decision).

### Import — Preview + Per-Conflict Ask

**Import flow:**

```
1. User picks CSV file
2. System parses CSV, validates headers
3. PREVIEW screen shows:
   - X new parts to create
   - Y existing parts found (matched by code or name)
   - Z rows with errors (missing required fields)
4. For each CONFLICT (existing part):
   - Show side-by-side: Current values vs CSV values
   - User picks: [Update] [Skip] [Update All] [Skip All]
5. User confirms → import runs via service layer
6. Summary: "Created X, Updated Y, Skipped Z, Errors W"
```

**Duplicate matching:** Match by `code` first (exact match). If no code, match by `name` (exact, case-insensitive).

**Required columns:** `name` (always required). `category` required for new parts, optional for updates.

**Import via service layer:** Uses `PartsService` methods (createPart/updatePart), never raw SQL. This ensures change tracking, validation, and proper relationships.

### Import Column Support

| Column | Import Behavior |
|--------|----------------|
| name | Required. Matched for duplicates. |
| code | Optional. Primary duplicate key if present. |
| category | Required for new parts. Creates category if doesn't exist. |
| style | Optional. Creates if doesn't exist under category. |
| type | Optional. Creates if doesn't exist under style. |
| brand | Optional. Creates if doesn't exist. |
| color | Optional. Creates if doesn't exist under brand. |
| cost_price | Optional. Sets company_cost_price. |
| markup_percent | Optional. Sets company_markup_percent. |
| part_type | Optional. Defaults to "standard". |
| description | Optional. |
| unit_of_measure | Optional. |
| min_stock | Optional. Sets min_stock_level. |
| target_stock | Optional. Sets target_stock_level. |
| max_stock | Optional. Sets max_stock_level. |

### Error Handling

- Missing `name` → skip row, add to error list
- Missing `category` on new part → skip row, add to error list
- Invalid cost_price/markup (non-numeric) → skip field, keep rest of row
- Duplicate code pointing to different parts → show conflict

---

## UI Layout

```
┌─ Import / Export ────────────────────────────────┐
│                                                   │
│  ┌─ Catalog Summary ──────────────────────────┐   │
│  │  [Parts: 234] [Categories: 12]              │   │
│  │  [Brands: 18] [Suppliers: 8]                │   │
│  └─────────────────────────────────────────────┘   │
│                                                   │
│  ┌─ Export ────────────────────────────────────┐   │
│  │  Select fields to export:                    │   │
│  │  ☑ Hierarchy  ☐ Pricing  ☐ Stock Levels     │   │
│  │  ☐ Forecast   ☐ Details  ☐ All              │   │
│  │                                              │   │
│  │  [Export 234 Parts to CSV]                   │   │
│  └─────────────────────────────────────────────┘   │
│                                                   │
│  ┌─ Import ────────────────────────────────────┐   │
│  │  [Choose CSV File]                           │   │
│  │                                              │   │
│  │  Required: name                              │   │
│  │  Optional: code, category, brand, style,     │   │
│  │  type, color, cost_price, markup_percent...  │   │
│  └─────────────────────────────────────────────┘   │
│                                                   │
│  ┌─ CSV Format Reference ─────────────────────┐   │
│  │  Required: name                              │   │
│  │  Optional: code, category, brand, ...        │   │
│  └─────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────┘
```

### Import Preview Sheet

```
┌─ Import Preview ─────────────────────────────────┐
│                                                    │
│  Parsed 150 rows from "parts_data.csv"             │
│                                                    │
│  ✅ 120 new parts to create                        │
│  ⚠️  25 existing parts found (duplicates)          │
│  ❌   5 rows with errors                           │
│                                                    │
│  ┌─ Conflicts (25) ───────────────────────────┐   │
│  │                                             │   │
│  │  1/2" Copper Elbow (code: ELB-CU-05)       │   │
│  │  ┌─────────┬───────────┬───────────┐        │   │
│  │  │ Field   │ Current   │ CSV       │        │   │
│  │  ├─────────┼───────────┼───────────┤        │   │
│  │  │ Cost    │ $2.14     │ $2.38     │        │   │
│  │  │ Markup  │ 50%       │ 45%       │        │   │
│  │  └─────────┴───────────┴───────────┘        │   │
│  │  [Update] [Skip] [Update All] [Skip All]    │   │
│  │                                             │   │
│  └─────────────────────────────────────────────┘   │
│                                                    │
│  ┌─ Errors (5) ───────────────────────────────┐   │
│  │  Row 45: Missing "name" — skipped           │   │
│  │  Row 89: Missing "category" (new part)      │   │
│  └─────────────────────────────────────────────┘   │
│                                                    │
│  [Cancel]                    [Import 120 + 0 updates]│
└────────────────────────────────────────────────────┘
```

---

## Service Layer Requirements

PartsService needs these methods (check if they exist, add if missing):

| Method | Purpose |
|--------|---------|
| `getCatalogStats()` | Return counts (parts, categories, brands, suppliers) |
| `exportPartsCSV(fields:)` | Generate CSV string with selected field groups |
| `findPartByCode(code:)` | Exact match lookup for duplicate detection |
| `findPartByName(name:)` | Case-insensitive match for duplicate detection |
| `createPartFromImport(...)` | Create part + auto-create category/brand if needed |
| `updatePartFromImport(id:fields:)` | Update specific fields on existing part |

---

*Design confirmed: 2026-03-21*
