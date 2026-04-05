# iOS Categories Page — Design Plan

> **Status:** Design CONFIRMED — Prompts 14A-14G all DONE
> **Prompts:** `xcode-ai/fix-prompts/done/` (14A-14G archived)
> **Last updated:** 2026-03-21

---

## Design Decisions

### Hierarchy Structure (Prompt 14A)
- **5-level hierarchy:** Category → Style → Type → Brand → Color
- **Colors nest under Brands** (not flat siblings) — must select a brand before picking colors
- **"General" brand always present** under every type — represents "no specific brand"
- **"None" color always available** in every color picker — color is optional, synthetic option at top

### Tree View UX (Prompts 14B, 14C)
- **Alphabetical sort A-Z at every level** — consistency, user expectation
- **Count badges on collapsed nodes only** — styles under category, types under style, brands under type
- **Tree search filters to matching nodes** + preserves parent chain — "If Type matches, show its parent Style and Category"
- Add buttons use bigger touch targets with icon + label

### Form Feedback (Prompt 14D)
- **Inline error feedback in all 4 form sheets** — user sees exactly what failed
- No print() error statements — all errors visible to user
- **Save button shows spinner** + disabled during save — prevents double-taps

### Smart Delete System (Prompt 14E)
- **Can't delete with active inventory** — system blocks immediate deletion
- **Empty Shelf Mode:** Schedule deletion after stock depletes naturally
- Uses `scheduled_deletions` table (migration 024)
- **30-day drain timer** after stock hits 0 — admin approval required after
- **Alternative part recommendations** during deletion — "Please switch to [Part X]"
- If inventory rises above 0 during draining → auto-cancel the scheduled deletion

### Deletion Approval (Prompt 14F)
- **Office page for approving scheduled deletions** (IOSDeletionApprovalsPage)
- Separation of concerns: warehouse/shop initiates, office approves
- Two sections: "Pending Approval" (draining complete) and "Currently Draining"
- Added to Office tab in navigation

### User Guidance (Prompt 14G)
- **Help button** in categories toolbar opens HierarchyHelpView
- 5-level hierarchy explainer for new users
- Enhanced empty state with "how to get started" guidance
- Each level explained: what it does, example, when to use

---

## Open Questions (Medium)

- **Brand deletion rules:** If a brand is linked to a type with active parts, can it be deleted? (Currently relies on smart delete system)
- **Cascading deletes:** If you delete a Category, what happens to Styles/Types/Brands/Colors? (Currently: soft delete blocks if any child has inventory)
- **Orphan handling:** If a style is deleted, do its types become orphaned? (Currently: blocked by inventory check)
- **"General" brand display:** Uses "circle.dashed" icon. Should it say "General" or "No Brand" or "Unspecified"?

---

## GitHub #46 Decisions (2026-04-04)

> Q&A answered. Partial implementation in commit 826dd18. Remaining items are future prompts.

### Part Numbers at Color Level
- Part numbers belong at the **Color** level — each color variant has its own unique part number from the manufacturer/supplier
- This is NOT a constructed prefix+suffix; it is a direct, opaque part number entered by the user
- **Optional Supplier Part Number** also at Color level, per supplier — makes ordering easier (the supplier may use a different code than the manufacturer)
- Implementation status: **not yet built** — needs DB schema change + UI prompt

### Tree Expansion State — Session Persistence
- Tree expansion state should be **per-session** (not persisted to DB or UserDefaults across restarts)
- **✅ Implemented in commit 826dd18** — `CategoriesTreeView` expanded sets lifted from `@State` to `@Binding`, owned by `PartsCategoriesPage`. Survives `.id(dataVersion)` refreshes within a session.

### Search Behavior
- Users should be able to search by any combination: `[color + part number]`, `[category drill-down]`, trade names, abbreviations (e.g., "RD" for red, "GFCI red outlet")
- Implementation status: **not yet built** — needs enhanced search logic at Color level

### Pending Prompt Work
- `PE-046a` (planned): Add `part_number` + `supplier_part_numbers` fields to Color level in schema, migration, and UI editor
- `PE-046b` (planned): Wire part-number-aware search to Color level in CatalogSearch

---

*Design confirmed from prompts 14A-14G · All DONE · #46 Q&A decisions added 2026-04-04*
