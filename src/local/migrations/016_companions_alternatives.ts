/**
 * Migration 016: Type-Color Links, Type-Brand Links, Companions & Alternatives
 *
 * Tables ported from:
 * - backend/app/migrations/003_hierarchy_images_and_type_colors.sql
 * - backend/app/migrations/004_type_brand_links.sql
 * - backend/app/migrations/007_companions.sql
 */

export const migration = {
  name: '016_companions_alternatives',
  sql: `
-- ─── TYPE ↔ COLOR LINKS ─────────────────────────────────────
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

-- ─── TYPE ↔ BRAND LINKS ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS type_brand_links (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    type_id    INTEGER NOT NULL REFERENCES part_types(id) ON DELETE CASCADE,
    brand_id   INTEGER REFERENCES brands(id) ON DELETE CASCADE,
    created_at TEXT    DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_tbl_type  ON type_brand_links(type_id);
CREATE INDEX IF NOT EXISTS idx_tbl_brand ON type_brand_links(brand_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_tbl_unique_type_brand
    ON type_brand_links(type_id, COALESCE(brand_id, 0));

-- ─── COMPANION RULES ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS companion_rules (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    name            TEXT NOT NULL,
    description     TEXT,
    style_match     TEXT NOT NULL DEFAULT 'auto'
                    CHECK(style_match IN ('auto', 'any', 'explicit')),
    qty_mode        TEXT NOT NULL DEFAULT 'sum'
                    CHECK(qty_mode IN ('sum', 'max', 'ratio')),
    qty_ratio       REAL DEFAULT 1.0,
    is_active       INTEGER DEFAULT 1,
    created_by      INTEGER REFERENCES users(id),
    created_at      TEXT DEFAULT (datetime('now')),
    updated_at      TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS companion_rule_sources (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id         INTEGER NOT NULL REFERENCES companion_rules(id) ON DELETE CASCADE,
    category_id     INTEGER NOT NULL REFERENCES part_categories(id),
    style_id        INTEGER REFERENCES part_styles(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_crs_unique ON companion_rule_sources(rule_id, category_id, COALESCE(style_id, 0));
CREATE INDEX IF NOT EXISTS idx_crs_rule ON companion_rule_sources(rule_id);

CREATE TABLE IF NOT EXISTS companion_rule_targets (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id         INTEGER NOT NULL REFERENCES companion_rules(id) ON DELETE CASCADE,
    category_id     INTEGER NOT NULL REFERENCES part_categories(id),
    style_id        INTEGER REFERENCES part_styles(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_crt_unique ON companion_rule_targets(rule_id, category_id, COALESCE(style_id, 0));
CREATE INDEX IF NOT EXISTS idx_crt_rule ON companion_rule_targets(rule_id);

-- ─── COMPANION SUGGESTIONS ──────────────────────────────────
CREATE TABLE IF NOT EXISTS companion_suggestions (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id             INTEGER REFERENCES companion_rules(id) ON DELETE SET NULL,
    target_category_id  INTEGER NOT NULL REFERENCES part_categories(id),
    target_style_id     INTEGER REFERENCES part_styles(id),
    target_description  TEXT NOT NULL,
    suggested_qty       INTEGER NOT NULL,
    approved_qty        INTEGER,
    reason_type         TEXT NOT NULL DEFAULT 'rule'
                        CHECK(reason_type IN ('rule', 'learned', 'mixed')),
    reason_text         TEXT NOT NULL,
    status              TEXT NOT NULL DEFAULT 'pending'
                        CHECK(status IN ('pending', 'approved', 'discarded')),
    triggered_by        INTEGER REFERENCES users(id),
    decided_by          INTEGER REFERENCES users(id),
    decided_at          TEXT,
    order_id            INTEGER,
    notes               TEXT,
    created_at          TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_suggestions_status ON companion_suggestions(status);
CREATE INDEX IF NOT EXISTS idx_suggestions_created ON companion_suggestions(created_at);

CREATE TABLE IF NOT EXISTS companion_suggestion_sources (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    suggestion_id       INTEGER NOT NULL REFERENCES companion_suggestions(id) ON DELETE CASCADE,
    category_id         INTEGER NOT NULL REFERENCES part_categories(id),
    category_name       TEXT,
    style_id            INTEGER REFERENCES part_styles(id),
    style_name          TEXT,
    qty                 INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_css_suggestion ON companion_suggestion_sources(suggestion_id);

-- ─── CO-OCCURRENCE LEARNING ─────────────────────────────────
CREATE TABLE IF NOT EXISTS co_occurrence_pairs (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    category_a_id       INTEGER NOT NULL REFERENCES part_categories(id),
    category_b_id       INTEGER NOT NULL REFERENCES part_categories(id),
    co_occurrence_count INTEGER NOT NULL DEFAULT 0,
    total_jobs_a        INTEGER NOT NULL DEFAULT 0,
    total_jobs_b        INTEGER NOT NULL DEFAULT 0,
    avg_ratio_a_to_b    REAL DEFAULT 1.0,
    confidence          REAL DEFAULT 0.0,
    last_computed       TEXT DEFAULT (datetime('now')),
    UNIQUE(category_a_id, category_b_id),
    CHECK(category_a_id < category_b_id)
);
CREATE INDEX IF NOT EXISTS idx_cooccurrence_a ON co_occurrence_pairs(category_a_id);
CREATE INDEX IF NOT EXISTS idx_cooccurrence_b ON co_occurrence_pairs(category_b_id);

CREATE TABLE IF NOT EXISTS companion_feedback (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    suggestion_id       INTEGER NOT NULL REFERENCES companion_suggestions(id),
    rule_id             INTEGER REFERENCES companion_rules(id),
    action              TEXT NOT NULL CHECK(action IN ('approved', 'discarded')),
    suggested_qty       INTEGER NOT NULL,
    final_qty           INTEGER,
    source_categories   TEXT,
    target_category_id  INTEGER,
    target_style_id     INTEGER,
    user_id             INTEGER REFERENCES users(id),
    created_at          TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_feedback_rule ON companion_feedback(rule_id);

-- ─── PART ALTERNATIVES ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS part_alternatives (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id             INTEGER NOT NULL REFERENCES parts(id) ON DELETE CASCADE,
    alternative_part_id INTEGER NOT NULL REFERENCES parts(id) ON DELETE CASCADE,
    relationship        TEXT NOT NULL DEFAULT 'substitute'
                        CHECK(relationship IN ('substitute', 'upgrade', 'compatible')),
    preference          INTEGER NOT NULL DEFAULT 0,
    notes               TEXT,
    created_by          INTEGER REFERENCES users(id),
    created_at          TEXT DEFAULT (datetime('now')),
    UNIQUE(part_id, alternative_part_id),
    CHECK(part_id != alternative_part_id)
);
CREATE INDEX IF NOT EXISTS idx_part_alt_part ON part_alternatives(part_id);
CREATE INDEX IF NOT EXISTS idx_part_alt_alt ON part_alternatives(alternative_part_id);
  `,
};
