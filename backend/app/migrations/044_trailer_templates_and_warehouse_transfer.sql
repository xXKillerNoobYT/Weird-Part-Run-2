-- =============================================================
-- MIGRATION 044: Trailer Stock Templates + Warehouse Transfer
-- =============================================================
-- Adds:
--   1) trailer_stock_templates      - Named template configs
--   2) trailer_stock_template_lines - Parts + target qty per template
--
-- Phase 16B completion: these tables support "common grab parts"
-- restock guidance for trailers. Templates can be global (trailer_id
-- NULL) or per-trailer.
-- =============================================================

-- ─────────────────────────────────────────────────────────────
-- 1) Trailer Stock Templates
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS trailer_stock_templates (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    trailer_id  INTEGER REFERENCES job_trailers(id) ON DELETE SET NULL,
    name        TEXT NOT NULL,
    is_default  INTEGER NOT NULL DEFAULT 0,
    notes       TEXT,
    created_at  TEXT DEFAULT (datetime('now')),
    updated_at  TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_trailer_tmpl_trailer
    ON trailer_stock_templates(trailer_id);
CREATE INDEX IF NOT EXISTS idx_trailer_tmpl_default
    ON trailer_stock_templates(is_default);

CREATE TABLE IF NOT EXISTS trailer_stock_template_lines (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    template_id INTEGER NOT NULL REFERENCES trailer_stock_templates(id) ON DELETE CASCADE,
    part_id     INTEGER NOT NULL REFERENCES parts(id) ON DELETE CASCADE,
    target_qty  INTEGER NOT NULL DEFAULT 1 CHECK(target_qty > 0),
    min_qty     INTEGER NOT NULL DEFAULT 0 CHECK(min_qty >= 0),
    UNIQUE(template_id, part_id)
);

CREATE INDEX IF NOT EXISTS idx_trailer_tmpl_lines_tmpl
    ON trailer_stock_template_lines(template_id);
CREATE INDEX IF NOT EXISTS idx_trailer_tmpl_lines_part
    ON trailer_stock_template_lines(part_id);
