-- =================================================================
-- Migration 007: Part Companions (category-level linking) &
--                Part Alternatives (part-level cross-linking)
--
-- Companions: Link categories that commonly go together on jobs.
--   Example: Outlets + Switches → suggests Cover Plates.
--   Includes rule engine, suggestion board, co-occurrence learning.
--
-- Alternatives: Link individual parts that serve the same function.
--   Example: DRC 50 ↔ TT500 (substitute, TT500 preferred).
-- =================================================================

-- ═══════════════════════════════════════════════════════════════
-- COMPANION RULES — user-defined category relationships
-- ═══════════════════════════════════════════════════════════════

-- Companion rules — user-defined relationships
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

-- Rule sources — which categories trigger the rule
CREATE TABLE IF NOT EXISTS companion_rule_sources (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id         INTEGER NOT NULL REFERENCES companion_rules(id) ON DELETE CASCADE,
    category_id     INTEGER NOT NULL REFERENCES part_categories(id),
    style_id        INTEGER REFERENCES part_styles(id)
);

-- Rule targets — which categories get suggested
CREATE TABLE IF NOT EXISTS companion_rule_targets (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id         INTEGER NOT NULL REFERENCES companion_rules(id) ON DELETE CASCADE,
    category_id     INTEGER NOT NULL REFERENCES part_categories(id),
    style_id        INTEGER REFERENCES part_styles(id)
);

-- ═══════════════════════════════════════════════════════════════
-- COMPANION SUGGESTIONS — generated pending/approved/discarded
-- ═══════════════════════════════════════════════════════════════

-- Generated suggestions (pending → approved | discarded)
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

-- Source items that triggered each suggestion
CREATE TABLE IF NOT EXISTS companion_suggestion_sources (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    suggestion_id       INTEGER NOT NULL REFERENCES companion_suggestions(id) ON DELETE CASCADE,
    category_id         INTEGER NOT NULL REFERENCES part_categories(id),
    category_name       TEXT,
    style_id            INTEGER REFERENCES part_styles(id),
    style_name          TEXT,
    qty                 INTEGER NOT NULL
);

-- ═══════════════════════════════════════════════════════════════
-- CO-OCCURRENCE LEARNING — from historical job consumption
-- ═══════════════════════════════════════════════════════════════

-- Learned co-occurrence from job consumption history
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

-- Feedback tracking for learning
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

-- ═══════════════════════════════════════════════════════════════
-- PART ALTERNATIVES — individual part cross-linking
-- ═══════════════════════════════════════════════════════════════

-- Bidirectional alternative links between individual parts
-- relationship: substitute (same job), upgrade (better version), compatible (works alongside)
-- preference: 0 = no preference, 1+ = higher is more preferred
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

-- ═══════════════════════════════════════════════════════════════
-- INDEXES
-- ═══════════════════════════════════════════════════════════════

-- Companion rules
CREATE UNIQUE INDEX IF NOT EXISTS idx_crs_unique ON companion_rule_sources(rule_id, category_id, COALESCE(style_id, 0));
CREATE INDEX IF NOT EXISTS idx_crs_rule ON companion_rule_sources(rule_id);
CREATE INDEX IF NOT EXISTS idx_crs_category ON companion_rule_sources(category_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_crt_unique ON companion_rule_targets(rule_id, category_id, COALESCE(style_id, 0));
CREATE INDEX IF NOT EXISTS idx_crt_rule ON companion_rule_targets(rule_id);

-- Suggestions
CREATE INDEX IF NOT EXISTS idx_suggestions_status ON companion_suggestions(status);
CREATE INDEX IF NOT EXISTS idx_suggestions_created ON companion_suggestions(created_at);
CREATE INDEX IF NOT EXISTS idx_css_suggestion ON companion_suggestion_sources(suggestion_id);

-- Co-occurrence
CREATE INDEX IF NOT EXISTS idx_cooccurrence_a ON co_occurrence_pairs(category_a_id);
CREATE INDEX IF NOT EXISTS idx_cooccurrence_b ON co_occurrence_pairs(category_b_id);

-- Feedback
CREATE INDEX IF NOT EXISTS idx_feedback_rule ON companion_feedback(rule_id);

-- Alternatives
CREATE INDEX IF NOT EXISTS idx_part_alt_part ON part_alternatives(part_id);
CREATE INDEX IF NOT EXISTS idx_part_alt_alt ON part_alternatives(alternative_part_id);
