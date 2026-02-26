-- =============================================================
-- MIGRATION 006: Warehouse Phase 3 — Audits, Staging, Supplier Prefs
-- =============================================================
-- Adds tables for:
--   1. audits / audit_items   — Spot-check, category, and rolling audit sessions
--   2. supplier_preferences   — Preferred supplier cascade (category→style→type→part)
--   3. staging_tags           — Destination tags for pulled/staged stock
--
-- Also adds columns:
--   - stock_movements.reference_number  — For returns and cross-references
--   - stock_movements.notes             — Free-text movement notes
--   - parts.shelf_location              — Physical shelf/bin location
--
-- Plus audit settings seed.
-- =============================================================


-- ─── AUDIT SESSIONS ───────────────────────────────────────────
-- Each audit is a session: spot-check (1 item), category (all items
-- in a category), or rolling (system-suggested rotation batch).
CREATE TABLE IF NOT EXISTS audits (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    audit_type        TEXT NOT NULL CHECK(audit_type IN ('spot_check', 'category', 'rolling')),
    location_type     TEXT NOT NULL DEFAULT 'warehouse'
                      CHECK(location_type IN ('warehouse', 'truck', 'job')),
    location_id       INTEGER NOT NULL DEFAULT 1,
    category_id       INTEGER REFERENCES part_categories(id),
    status            TEXT NOT NULL DEFAULT 'in_progress'
                      CHECK(status IN ('in_progress', 'paused', 'completed', 'cancelled')),
    started_by        INTEGER NOT NULL REFERENCES users(id),
    completed_at      TEXT,
    total_items       INTEGER DEFAULT 0,
    matched_items     INTEGER DEFAULT 0,
    discrepancy_count INTEGER DEFAULT 0,
    skipped_count     INTEGER DEFAULT 0,
    notes             TEXT,
    created_at        TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_audits_type ON audits(audit_type);
CREATE INDEX IF NOT EXISTS idx_audits_status ON audits(status);
CREATE INDEX IF NOT EXISTS idx_audits_started_by ON audits(started_by);


-- ─── AUDIT ITEMS (Individual Counts) ──────────────────────────
-- Each row = one part counted within an audit session.
-- The card-swipe UI iterates through these.
CREATE TABLE IF NOT EXISTS audit_items (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    audit_id          INTEGER NOT NULL REFERENCES audits(id) ON DELETE CASCADE,
    part_id           INTEGER NOT NULL REFERENCES parts(id),
    expected_qty      INTEGER NOT NULL DEFAULT 0,
    actual_qty        INTEGER,
    result            TEXT NOT NULL DEFAULT 'pending'
                      CHECK(result IN ('pending', 'match', 'discrepancy', 'skipped')),
    discrepancy_note  TEXT,
    photo_path        TEXT,
    counted_at        TEXT,
    UNIQUE(audit_id, part_id)
);

CREATE INDEX IF NOT EXISTS idx_audit_items_audit ON audit_items(audit_id);
CREATE INDEX IF NOT EXISTS idx_audit_items_result ON audit_items(result);


-- ─── SUPPLIER PREFERENCES (Cascade) ──────────────────────────
-- Preferred supplier settable at category, style, type, or part level.
-- Resolution order: part → type → style → category → None (FIFO).
CREATE TABLE IF NOT EXISTS supplier_preferences (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    scope_type        TEXT NOT NULL CHECK(scope_type IN ('category', 'style', 'type', 'part')),
    scope_id          INTEGER NOT NULL,
    supplier_id       INTEGER NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
    created_at        TEXT DEFAULT (datetime('now')),
    UNIQUE(scope_type, scope_id)
);

CREATE INDEX IF NOT EXISTS idx_supplier_prefs_scope ON supplier_preferences(scope_type, scope_id);


-- ─── STAGING TAGS ─────────────────────────────────────────────
-- When stock is pulled to staging, it can be tagged with its intended
-- destination (which truck or job it's being prepped for).
-- Aging is calculated from created_at: <24h normal, 24-48h yellow, >48h red.
CREATE TABLE IF NOT EXISTS staging_tags (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    stock_id          INTEGER NOT NULL REFERENCES stock(id) ON DELETE CASCADE,
    destination_type  TEXT NOT NULL CHECK(destination_type IN ('truck', 'job')),
    destination_id    INTEGER NOT NULL,
    destination_label TEXT,
    tagged_by         INTEGER REFERENCES users(id),
    created_at        TEXT DEFAULT (datetime('now')),
    UNIQUE(stock_id)
);

CREATE INDEX IF NOT EXISTS idx_staging_tags_stock ON staging_tags(stock_id);
CREATE INDEX IF NOT EXISTS idx_staging_tags_dest ON staging_tags(destination_type, destination_id);


-- ─── ADD COLUMNS ──────────────────────────────────────────────
-- reference_number: For returns and cross-references (e.g., original movement ID)
ALTER TABLE stock_movements ADD COLUMN reference_number TEXT;

-- notes: Free-text notes on a movement
ALTER TABLE stock_movements ADD COLUMN notes TEXT;

-- shelf_location: Physical bin/shelf location for a part (nullable, populate gradually)
ALTER TABLE parts ADD COLUMN shelf_location TEXT;

CREATE INDEX IF NOT EXISTS idx_parts_shelf ON parts(shelf_location);


-- ─── SETTINGS SEED ────────────────────────────────────────────
-- How many months a full rolling audit should take to cover the entire inventory.
INSERT OR IGNORE INTO settings (key, value, category)
VALUES ('audit_cycle_months', '12', 'warehouse');
