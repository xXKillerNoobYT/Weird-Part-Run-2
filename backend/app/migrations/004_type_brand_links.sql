-- =============================================================
-- MIGRATION 004: Type ↔ Brand Links
-- =============================================================
-- Tracks which brands (and "General"/unbranded) are enabled for
-- each part type. This drives the Categories tree UI:
--   Type (GFI) → ☑ General, ☑ Leviton, ☐ Square D …
--
-- A link existing means "this brand makes this type of part."
-- Actual Part records are created separately per color under
-- each enabled brand/General node.
--
-- brand_id = NULL means "General" (unbranded commodity item).
-- =============================================================

CREATE TABLE IF NOT EXISTS type_brand_links (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    type_id    INTEGER NOT NULL REFERENCES part_types(id) ON DELETE CASCADE,
    brand_id   INTEGER REFERENCES brands(id) ON DELETE CASCADE,  -- NULL = General
    created_at TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_tbl_type  ON type_brand_links(type_id);
CREATE INDEX IF NOT EXISTS idx_tbl_brand ON type_brand_links(brand_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_tbl_unique_type_brand
    ON type_brand_links(type_id, COALESCE(brand_id, 0));
