# Colors & Parts Redesign — Variants, Per-SKU Brand Linkage, General Mode

> **Status:** Phase 1 (schema + CRUD) ✅ DONE (migration 074 + PartsService CRUD, commit 13cd7b2). Phase 2 (Categories UI) pending — PE-046–049 queued in `00-fix-order.md`. Phase 3 (General Mode orders UI) pending — tracked as GitHub #242, #243.
> **Supersedes:** Ad-hoc Q&A discussions in `docs/dev-qa.md` (now processed).
> **GitHub Issues:** #98, #99, #100, #105, #106, #107
> **Pipeline item:** `PE-COLORS`

---

## Context

The Parts → Categories page surfaces a hierarchical tree (Category → Type → Brand → Color) that is the master editor for the catalog. Its current presentation implies "colors live underneath specific (type, brand) combos," which has led to:

- Color rows being duplicated when multiple brands carry the same physical color
- Part numbers stored at inconsistent levels (some brand-level, some type-level, some color-level)
- No path for a "no brand yet, decide at ordering time" workflow that matches real-world supply chain behavior
- New-type forms that require manually picking a brand even when the common case is "whichever brand comes from whichever supplier we pick at PO time"

The owner's intent — captured through `dev-qa.md` Q1–Q6 on 2026-04-14 — is to rebuild the color/brand relationship around three concepts:

1. **Variants** (a broader concept than "colors")
2. **Distinct SKU per (variant + brand)** (matching how real parts retailers structure catalogs)
3. **General Mode** on order line items (brand deferred to supplier time)

---

## Ground Truth (pre-implementation)

From `AppDatabase+Migrations.swift`:

- `part_colors` (line ~796) is ALREADY a standalone table with columns `id`, `name`, `hex_code`, `part_number` (migration 065), `unit_cost` (migration 067), `sort_order`, `is_active`, `deleted_at`, `created_at`.
- `type_color_links` (line ~2420) joins types ↔ colors (many-to-many).
- `type_brand_links` (line ~2432) joins types ↔ brands (many-to-many).
- **There is no color↔brand linkage anywhere in the schema today.** This is the gap the new `color_brand_skus` table fills.
- There is NO "General" row in `parts_brands` — "General" is a concept the user wants to add as a mode flag, not a brand entity.

---

## Design

### Concept 1 — "Variants" (Q1) — EXPANDED 2026-04-18

The existing `part_colors` table IS the shared pool. We keep the table name short-term (renaming is a follow-up migration) but update the UI terminology and expand the schema additively to support six variant kinds PLUS a substitution cross-reference.

**2026-04-18 refinement (from per-POV re-ratification):** the original 2026-04-14 scope named only two kinds (color-based, named-only). Owner clarified that real variant behavior in an electrical-parts catalog requires more dimensions AND a way to express interchangeability between parts.

#### The six variant kinds on each row

A single `part_colors` row can carry any combination of:

1. **Color-based** — `name` + `hex_code` filled (e.g. "Gray", "Red", "White" outlets / wires).
2. **Named-only** — `name` filled, `hex_code` NULL (e.g. "Standard", "Fire-Rated", "Metal" boxes).
3. **Named + optional color tag** — `name` + `hex_code` both filled, but `hex_code` is a UI chip for visual distinction, NOT the product's physical color (e.g. standard box shown in blue chip, fire-rated in red chip).
4. **Size / dimension** — optional `size` column (e.g. "1/2\"", "3/4\"", "1\"" for conduit; "12 AWG", "10 AWG" for wire; "single-gang" / "double-gang" for boxes).
5. **Rating / spec** — optional `rating` column (e.g. "15A", "20A", "30A" for outlets/breakers; "120V", "240V" for devices).
6. **Material** — optional `material` column (e.g. "PVC" / "EMT" / "Rigid"; "Copper" / "Aluminum"; "Plastic" / "Metal").

All of #4–6 start NULL; populate where meaningful for the variant.

#### Schema change for the expansion

```sql
ALTER TABLE part_colors ADD COLUMN size TEXT;
ALTER TABLE part_colors ADD COLUMN rating TEXT;
ALTER TABLE part_colors ADD COLUMN material TEXT;
```

#### Substitute relationship (NEW)

Many-to-many cross-reference so one part can flag another as a suitable substitute when more than one part serves the same function:

```sql
CREATE TABLE variant_substitutes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    a_color_id INTEGER NOT NULL REFERENCES part_colors(id) ON DELETE CASCADE,
    b_color_id INTEGER NOT NULL REFERENCES part_colors(id) ON DELETE CASCADE,
    bidirectional INTEGER DEFAULT 1,     -- 1 = a↔b, 0 = a→b only
    context TEXT,                        -- e.g. "emergency only", "same function different brand"
    notes TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    UNIQUE(a_color_id, b_color_id)
);
CREATE INDEX idx_variant_substitutes_a ON variant_substitutes(a_color_id);
CREATE INDEX idx_variant_substitutes_b ON variant_substitutes(b_color_id);
```

When ordering or procurement is blocked (out of stock, backordered), the UI can surface the substitute chain so the user picks an interchangeable variant. Orthogonal to existing `companion-rules-system` (which handles "these go together" not "these can replace each other").

#### UI surfacing

- The tree UI (`TypeBrandColorSection.swift`, `CategoriesColorPicker.swift`) renders each variant as a chip:
  - If `hex_code` present → colored chip with `name` inside.
  - If `hex_code` NULL → text-only pill.
  - Size / rating / material appear as secondary text on the row (e.g. "Gray · 3/4\" · PVC").
- The picker presents the full `part_colors` pool, not a type-scoped subset — users pick from or extend the shared pool.
- Variant detail sheet exposes all six fields plus the substitute picker (add/remove substitute relations).

**Future migration:** Rename `part_colors` → `part_variants`, `type_color_links` → `type_variant_links`. Tracked as a separate follow-up so this plan can ship without a rename migration.

### Concept 2 — Distinct SKU per (variant + brand) (Q2 + Q4)

New table `color_brand_skus` — one row per real-world SKU:

```sql
-- Migration N (next available number)
CREATE TABLE color_brand_skus (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    color_id INTEGER NOT NULL REFERENCES part_colors(id) ON DELETE CASCADE,
    brand_id INTEGER NOT NULL REFERENCES parts_brands(id) ON DELETE CASCADE,
    type_id INTEGER NOT NULL REFERENCES parts_types(id) ON DELETE CASCADE,
    part_number TEXT,              -- manufacturer part number for this specific SKU
    unit_cost DOUBLE,              -- optional brand-specific override of color-level cost
    stock_qty INTEGER DEFAULT 0,   -- brand-specific on-hand
    is_active INTEGER DEFAULT 1,
    deleted_at TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    UNIQUE(color_id, brand_id, type_id)
);
CREATE INDEX idx_color_brand_skus_lookup ON color_brand_skus(type_id, brand_id, color_id);
CREATE INDEX idx_color_brand_skus_color ON color_brand_skus(color_id);
```

**Why the three-column unique:** the same (color, brand) pair can legitimately exist under multiple types (e.g. "Cantex Gray" appears under both "PVC Conduit" and "PVC Fittings"). The `type_id` disambiguates.

**Backfill:** None. Table starts empty. On first real use, the editor creates rows as the user assigns brands to color/type combinations.

### Concept 3 — "General Mode" on order line items (Q3)

"General" is NOT a brand row. It's a per-line-item flag on JPO (Job Pre-Order) and PO tables that says: "no brand lock — resolve it at supplier selection time."

Schema change on `jpo_line_items` and `po_line_items`:

```sql
ALTER TABLE jpo_line_items ADD COLUMN brand_selection_mode TEXT DEFAULT 'specific'
    CHECK (brand_selection_mode IN ('specific', 'general'));
ALTER TABLE po_line_items  ADD COLUMN brand_selection_mode TEXT DEFAULT 'specific'
    CHECK (brand_selection_mode IN ('specific', 'general'));
```

When `brand_selection_mode = 'general'`:

- The line item carries `color_id` + `type_id` but `brand_id` is NULL.
- At PO creation time, the selected supplier drives brand resolution:
  1. Look up which brands the chosen supplier carries (`brand_supplier_links.brand_id` for `supplier_id`).
  2. If exactly one → auto-fill brand.
  3. If multiple → look up prior orders of this (type, color, supplier) and pick the brand most-recently ordered (supply-chain consistency rule).
  4. If none match → flag the line for supplier replacement.

**Affected files:**
- `OrdersService.swift` — new `resolveGeneralLineItem(lineId:supplierId:)` method.
- JPO creation UI — toggle or picker mode "General / Specific Brand" on each line.
- PO creation UI — resolve + display `(resolved: Brand X)` pill when mode=general and brand auto-filled.

### Concept 4 — Simple counterpart picker (Q5)

Existing `BrandSupplierPickerSheet.swift` already supports picking from the existing pool. We confirm this is the right design — NOT upgrading to inline-create.

- New Brand sheet → "Add suppliers?" → opens `BrandSupplierPickerSheet` → lists existing suppliers → multi-select → closes.
- New Supplier sheet → mirror flow with brands.
- If the user needs a counterpart that doesn't exist: navigate to the other page (Brands or Suppliers), create it there, return, and pick it. Keeps the new-record sheets uncluttered.

### Concept 5 — Color-level part_number SUPPLEMENTS type-level (Q6) — FLIPPED 2026-04-18

**2026-04-18 refinement (flipped from 2026-04-14 "Replace"):** Keep type-level `part_number` as an optional group-default / fallback. Color-level overrides for display when present. Both columns are indexed for search.

- Three layers of part_number resolution (most specific wins):
  1. `color_brand_skus.part_number` (Concept 2) — the per-(color, brand, type) SKU number.
  2. `part_colors.part_number` — the color-level part_number across all brands.
  3. `parts_types.part_number` — the type-level group default.
- Display: Layer 1 wins if set; else Layer 2; else Layer 3; else blank.
- Search (`PartsService.searchParts(query:)`) queries ALL THREE via UNION so users find parts whether they search a SKU number, a color-level number, or a type-level group default.

**No column drops.** The 2026-04-14 plan called for dropping `parts_types.part_number` / `parts_brands.part_number` — the 2026-04-18 Supplement ratification preserves `parts_types.part_number` as the fallback layer. `parts_brands.part_number` (if still present) can still be dropped — it's not part of the 3-layer chain above.

Search precedence is documented in `docs/plans/ios-part-number-hierarchy.md` — update that companion plan to match the 3-layer model.

---

## Affected Pages & Files

### Primary page: Parts → Categories
| File | Change |
|---|---|
| `PartsCategoriesPage.swift` | Update tree data source to use `color_brand_skus` for SKU-level rows |
| `CategoriesTreeView.swift` | Render SKU rows under each (type, brand) node; show variant chip + brand badge + part_number |
| `CategoriesEditorPanel.swift` | Right-panel now edits a `ColorBrandSKU` when a SKU row is selected; shows part_number, unit_cost, stock_qty |
| `CategoriesColorPicker.swift` | Present `part_colors` as shared pool; allow hex=NULL named-only variants |
| `CategoriesBrandSection.swift` | No default brand auto-selection on new type (Q3 reframe — General is not a brand row) |
| `TypeBrandColorSection.swift` | Rewrite — this is the file encoding the old "nested under (type, brand)" mental model |
| `CategoriesFormSheets.swift` | New Variant sheet gains hex-optional flag; New Brand/Supplier sheets wire `BrandSupplierPickerSheet` |

### Sibling pages
| File | Change |
|---|---|
| `PartsBrandsPage.swift` | `BrandSupplierPickerSheet` wired in new-brand flow (Q5) |
| `PartsSuppliersPage.swift` | Same in reverse for new-supplier flow (Q5) |

### Order flows (for General Mode)
| File | Change |
|---|---|
| `OrdersService.swift` | Add `resolveGeneralLineItem()`, update `createPO()` / `createJPO()` to preserve mode |
| `IOSJPOCreationPage.swift` | Per-line "Specific / General" toggle |
| `IOSPOCreationPage.swift` | Show resolved-brand pill when mode=general |

### Core service layer
| File | Change |
|---|---|
| `PartsService.swift` | CRUD for `color_brand_skus`; update `searchParts` to union part_colors + color_brand_skus part_numbers |
| `PartsModels.swift` | New `ColorBrandSKU` struct; `PartColor.hexCode` becomes `String?` (was implied non-null) |

### Database
| File | Change |
|---|---|
| `AppDatabase+Migrations.swift` | New migration adding `color_brand_skus` table + `brand_selection_mode` columns + drop legacy type/brand part_number if present |

---

## Rollout

### Phase 1 — Schema + Service (no UI changes)
1. New migration: `color_brand_skus` table, `brand_selection_mode` columns, legacy part_number column cleanup.
2. `ColorBrandSKU` model + CRUD service methods.
3. `searchParts` union update.
4. Tests for service methods.

### Phase 2 — Categories page rebuild
5. `CategoriesTreeView` + right-panel updated to show SKU rows.
6. `CategoriesColorPicker` supports hex=NULL variants.
7. `CategoriesFormSheets` new-brand/new-supplier picker wiring.

### Phase 3 — Order flows (General Mode)
8. JPO creation: per-line Specific/General toggle.
9. PO creation: `resolveGeneralLineItem()` wired, resolved-brand pill.
10. Tests for General Mode resolution (single supplier → auto; multi → most-recent-wins).

---

## Test Plan

1. Migration runs cleanly on a fresh DB and on existing dev DB without loss.
2. Create a variant with hex_code=NULL, verify it renders as a named-only pill (not a color chip).
3. Create `color_brand_skus` row for (Gray, Cantex, PVC Conduit) with its own part_number — verify it appears in the catalog distinct from (Gray, General, PVC Conduit).
4. Search by the SKU-level `part_number` — verify it returns the specific SKU.
5. Create a JPO line in General Mode with no brand — verify brand_id is NULL but line saves.
6. Convert the JPO line to a PO with Supplier A → verify brand auto-resolves to whichever brand Supplier A carries (or prompts if multiple).
7. Create two sequential POs with Supplier A for the same (type, color) — verify the second PO defaults to the same brand as the first (most-recent-wins).
8. Remove the last brand from a type — verify the tree still functions and the type shows "No brands linked" gracefully.

---

## Cross-References

- `docs/plans/ios-part-number-hierarchy.md` — companion plan for part_number levels and per-supplier part numbers.
- `docs/plans/ios-brands-suppliers-editing.md` — already-approved plan for the new-brand/new-supplier flow that Q5 confirms.
- `docs/plans/ios-pricing-system.md` — pricing tier inheritance that needs to account for SKU-level overrides.
- `docs/plans/ios-categories-page.md` — master plan for the Categories page; this redesign supersedes its "colors nested" assumptions.
- GitHub issues: `#98` (reusable colors), `#99` (per-color part numbers), `#100` (distinct SKU per brand+color), `#105` (linked picker), `#106` (color-level part number on detail), `#107` (General default — now reframed as Mode).
