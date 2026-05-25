# PE-047 — PE-COLORS Phase 2B: CategoriesColorPicker Named-Only Variants

> **Status:** ✅ DONE 2026-05-25 — direct Swift edit (all 5 regression tests pass; copilot/98-5 branch)
> **Plan:** `docs/plans/colors-parts-redesign.md` Concept 1 (Variants)
> **GitHub Issue:** #238 (subsumed #99)
> **Depends on:** PE-046 (CategoriesTreeView SKU rows), #234 (PartColor.hexCode becomes optional)
> **Target files:**
> - `Weird Parts IOS/Weird Parts IOS/Features/Parts/CategoriesColorPicker.swift`
> - `Weird Parts IOS/Weird Parts IOS/Features/Parts/CategoriesFormSheets.swift`

---

## Problem

The variant picker in `CategoriesColorPicker` only rendered colored circles. There was no path to
create a "named-only" variant (e.g. "Standard", "Fire-Rated", "Metal") where `hex_code IS NULL`.
The `ColorFormSheet` defaulted to always requiring a color, and the model had `hexCode` as always
a non-nil String in usage even though the DB column allows NULL.

---

## Changes Made

### `CategoriesColorPicker.swift`

- **`namedOnlyPill(_:)`** — new private helper that renders a `Capsule`-backed text pill (instead
  of a `Circle` fill) whenever `color.hexCode` is nil or empty. Pill shows the variant name, or
  "Named-only variant" when empty.
- **`colorTile(_:)`** — updated to branch on `hex_code`:
  - hex present and non-empty → `Circle().fill(Color(hex: hex))` (existing behavior preserved)
  - hex nil/empty → `namedOnlyPill(color.name)`
- **Terminology** — all copy updated from "color"→"variant": heading "Shared variants", button
  "Add New Variant", empty state "No variants in the shared pool…", sheet enum `case addVariant`.

### `CategoriesFormSheets.swift` — `ColorFormSheet`

- **`@State private var hasColor = false`** — starts off for new variants; `.onAppear` sets to
  `true` only when editing an existing color that already has a non-empty hex string.
- **"Has a visible color" `Toggle`** — when off, the hex picker section is hidden and the Preview
  section shows a `nosign` icon with "Named-only · no hex value" subtitle.
- **`hex: String? = hasColor ? hexStringFromColor(selectedColor) : nil`** — `hex` is explicitly
  nil for named-only variants.
- **`createColor(…hexCode: hex, …)`** — passes `nil` (not `""`) so the DB column is NULL.
- **`updateColor(…hexCode: hex ?? "", …)`** — passes `""` to `updateColor` when clearing; the
  service treats `""` as "set to NULL" (see `PartsService.updateColor` — `hexCode.isEmpty ? nil`).
- **`.navigationTitle(color == nil ? "New Variant" : "Edit Variant")`** — terminology updated.
- **`.onAppear`** uses `!hex.trimmingCharacters(in: .whitespaces).isEmpty` to avoid treating
  whitespace-only hex strings as a valid color.
- **Named-only preview** — when `hasColor` is false the preview shows a greyed-out circle with a
  `nosign` SF Symbol, plus the variant name (or "Named-only variant" placeholder).

### Model (already done in #234)

`PartColor.hexCode: String?` — already nullable in the model; no further changes needed.

---

## Acceptance Criteria Verified

| Criterion | How |
|-----------|-----|
| Can create a variant without a hex code | `hasColor = false` → `hex = nil` → `createColor(hexCode: nil)` |
| Variant renders as text-only pill in tree | `namedOnlyPill()` called when `hex_code` nil/empty in `colorTile()` |
| Existing colors with hex unchanged | hex path unchanged; only branching added |
| Editing hex-having color removes hex correctly | `updateColor(hexCode: "")` → service sets NULL |

---

## Tests

`tests/test_pe047_categories_color_picker.py` — 5 tests, all passing:

- `test_named_only_variants_render_as_text_pills_not_no_color_circles`
- `test_picker_copy_refers_to_shared_variants_pool`
- `test_picker_sheet_state_uses_variant_terminology`
- `test_color_form_creates_hex_null_for_named_only_variants`
- `test_color_form_uses_variant_title_and_treats_empty_hex_as_named_only`

---

## Subsumed Issue #99

Issue #99 (Colors saveable across types/brands) is subsumed by this work: the picker already
presents the full shared `part_colors` pool (not type-scoped), so any color created here can be
linked to multiple types via `type_color_links`. The "save a color once, use it everywhere"
contract is fully satisfied by the existing `listColors()` + `linkTypeToColor()` service methods.
