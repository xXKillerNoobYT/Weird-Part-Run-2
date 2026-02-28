-- ═══════════════════════════════════════════════════════════════════════
-- Migration 011: Bill Rate Types + Job Cleanup
--
-- 1. Create bill_rate_types lookup table (boss-customizable)
-- 2. Add bill_rate_type_id FK to jobs
-- 3. Drop unused billing_rate and estimated_hours from jobs
-- ═══════════════════════════════════════════════════════════════════════

-- ── Bill Rate Types ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bill_rate_types (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    name            TEXT    NOT NULL UNIQUE,
    description     TEXT,
    sort_order      INTEGER NOT NULL DEFAULT 0,
    is_active       INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- Seed defaults
INSERT OR IGNORE INTO bill_rate_types (name, sort_order) VALUES
    ('Time & Material', 1),
    ('Construction',    2),
    ('Bid',             3),
    ('Emergency',       4),
    ('Service Call',    5);

-- ── Add FK to jobs ──────────────────────────────────────────────────
ALTER TABLE jobs ADD COLUMN bill_rate_type_id INTEGER REFERENCES bill_rate_types(id);

-- ── Drop unused billing columns ─────────────────────────────────────
-- (billing_rate and estimated_hours were removed from the UI;
--  now cleaning up the data layer. SQLite 3.35+ supports DROP COLUMN.)
ALTER TABLE jobs DROP COLUMN billing_rate;
ALTER TABLE jobs DROP COLUMN estimated_hours;
