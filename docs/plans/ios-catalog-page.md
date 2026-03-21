# iOS Catalog Page — Design Plan

> **Status:** Design CONFIRMED — Prompts 13A-13E all DONE
> **Prompts:** `xcode-ai/fix-prompts/done/` (13A-13E archived)
> **Last updated:** 2026-03-21

---

## Design Decisions

### Search (Prompt 13A)
- **Search bar always fixed at top** — never scrolls, always visible
- Users search constantly in the field; hiding it wastes a common action

### Filters (Prompt 13B)
- **Filter chips always visible** below search — no toggle button
- Count badges on filter chips show matching parts count
- Filter options: Category, Style, Type, Brand, Color, Low Stock

### Part Detail (Prompt 13C)
- **Detail sheet is read-only** with Edit button to open form
- Delete confirmation required before hard delete
- Shows: name, code, category/brand, stock levels, pricing, image

### Natural Language Search (Prompt 13D)
- NL parser detects color, category, brand, type, style from query
- "Red copper fittings from Lutron" → auto-sets filters (color=red, category=fittings, brand=Lutron)
- Filler word exclusion: "from", "by", "in", "the", "a", "an"
- Multi-word brand matching: tries 2-word combos then 1-word
- Matched filter terms removed from text search query
- Fallback: unmatched words become text search

### AI Integration (Prompt 13E)
- Uses **NotificationCenter** pattern (`.catalogPageActive` / `.catalogPageInactive`)
- Catalog page posts context (current filters, part count) when visible
- AI panel reads context and can set filters via `.aiSetCatalogFilters` notification
- AI can clear all filters, set specific filter values, toggle low stock
- Decoupled design: AI panel doesn't need direct binding to catalog state

---

## Open Questions (Minor)

- Multi-word brand matching: exact strategy for conflicts (e.g., "Charlotte" could match brand "Charlotte Pipe" or color "Charlotte")
- NL parsing fallback: if a word matches both Style AND Color, which takes precedence? (Currently: checked in order Category → Style → Type → Brand → Color)
- AI filter command validation: can AI set non-existent filter values? (Currently: no validation, relies on filter logic to ignore invalid values)

---

*Design confirmed from prompts 13A-13E · All DONE*
