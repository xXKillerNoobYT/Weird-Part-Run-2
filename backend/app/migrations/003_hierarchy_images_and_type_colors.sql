-- =============================================================
-- MIGRATION 003: Hierarchy Images & Type-Color Links
-- =============================================================
-- Two additions:
--   1. image_url on all hierarchy tables (cascade pattern)
--      Resolved image = type_color.image_url → type.image_url
--                      → style.image_url → category.image_url
--   2. type_color_links junction table (which colors are valid
--      per part type — prevents impossible combos in the UI)
-- =============================================================


-- ─── Add image_url to hierarchy tables ────────────────────────
ALTER TABLE part_categories ADD COLUMN image_url TEXT;
ALTER TABLE part_styles ADD COLUMN image_url TEXT;
ALTER TABLE part_types ADD COLUMN image_url TEXT;
ALTER TABLE part_colors ADD COLUMN image_url TEXT;


-- ─── TYPE ↔ COLOR LINKS ──────────────────────────────────────
-- Junction table: explicitly defines which colors are valid for
-- each part type. E.g., Outlet > Decora > GFI comes in White,
-- Black, and Almond — but NOT Red or Orange.
--
-- Without this, the UI would show all 50+ colors in every dropdown.
-- With it, the color picker is scoped to valid options only.
--
-- image_url here is the most granular override in the cascade:
-- a specific type+color combo can have its own product photo.
CREATE TABLE IF NOT EXISTS type_color_links (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    type_id     INTEGER NOT NULL REFERENCES part_types(id) ON DELETE CASCADE,
    color_id    INTEGER NOT NULL REFERENCES part_colors(id) ON DELETE CASCADE,
    image_url   TEXT,
    sort_order  INTEGER DEFAULT 0,
    created_at  TEXT    DEFAULT (datetime('now')),
    UNIQUE(type_id, color_id)
);

CREATE INDEX IF NOT EXISTS idx_tcl_type ON type_color_links(type_id);
CREATE INDEX IF NOT EXISTS idx_tcl_color ON type_color_links(color_id);


-- ─── Seed: Link common colors to existing types ───────────────
-- Outlet > Decora types get White, Black, Light Almond, Ivory
INSERT OR IGNORE INTO type_color_links (type_id, color_id, sort_order)
    SELECT pt.id, pc.id, pc.sort_order
    FROM part_types pt
    JOIN part_styles ps ON ps.id = pt.style_id
    JOIN part_categories cat ON cat.id = ps.category_id
    CROSS JOIN part_colors pc
    WHERE cat.name IN ('Outlet', 'Switch', 'Cover Plate')
      AND pc.name IN ('White', 'Black', 'Light Almond', 'Ivory');
