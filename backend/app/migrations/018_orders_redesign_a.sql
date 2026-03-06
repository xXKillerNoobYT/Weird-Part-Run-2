-- ═══════════════════════════════════════════════════════════════════════
-- Migration 018: Orders Redesign Phase 7A — Core Ordering Experience
--
-- New tables: job_preferences, special_items
-- Altered: job_parts_orders (add order_type, has_special_items,
--          smart_suggestions_enabled; make job_id nullable for warehouse restocks)
--
-- NOTE: SQLite cannot ALTER a NOT NULL constraint, so we recreate the
-- job_parts_orders table with job_id nullable.  Foreign-key checks are
-- disabled during the swap to keep referencing tables (jpo_line_items,
-- order_status_history, task_order_links) intact.
-- ═══════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════
-- 0. SAFETY — disable FK enforcement during table swap
-- ═══════════════════════════════════════════════════════════

PRAGMA foreign_keys = OFF;


-- ═══════════════════════════════════════════════════════════
-- 1. RECREATE job_parts_orders — make job_id NULLABLE,
--    add order_type / has_special_items / smart_suggestions_enabled
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS job_parts_orders_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id INTEGER REFERENCES jobs(id),          -- NOW NULLABLE for warehouse restocks
    order_number TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN (
            'draft', 'pending_approval', 'approved', 'ordering',
            'partially_ordered', 'ordered', 'partially_received',
            'received', 'closed'
        )),
    priority TEXT DEFAULT 'normal'
        CHECK (priority IN ('normal', 'urgent')),
    order_type TEXT NOT NULL DEFAULT 'job'
        CHECK (order_type IN ('job', 'warehouse')),
    has_special_items INTEGER NOT NULL DEFAULT 0,
    smart_suggestions_enabled INTEGER NOT NULL DEFAULT 1,
    requested_by INTEGER NOT NULL REFERENCES users(id),
    approved_by INTEGER REFERENCES users(id),
    approved_at TEXT,
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Copy existing data (new columns get defaults)
INSERT INTO job_parts_orders_new (
    id, job_id, order_number, status, priority,
    order_type, has_special_items, smart_suggestions_enabled,
    requested_by, approved_by, approved_at, notes,
    created_at, updated_at
)
SELECT
    id, job_id, order_number, status, priority,
    'job',      -- all existing orders are job orders
    0,          -- no special items on legacy orders
    1,          -- smart suggestions default on
    requested_by, approved_by, approved_at, notes,
    created_at, updated_at
FROM job_parts_orders;

-- Drop old table and rename
DROP TABLE IF EXISTS job_parts_orders;
ALTER TABLE job_parts_orders_new RENAME TO job_parts_orders;

-- Recreate indexes (originals from migration 015)
CREATE INDEX IF NOT EXISTS idx_jpo_job ON job_parts_orders(job_id);
CREATE INDEX IF NOT EXISTS idx_jpo_status ON job_parts_orders(status);
CREATE INDEX IF NOT EXISTS idx_jpo_requested_by ON job_parts_orders(requested_by);
-- New indexes for redesign
CREATE INDEX IF NOT EXISTS idx_jpo_order_type ON job_parts_orders(order_type);

-- Recreate updated_at trigger
DROP TRIGGER IF EXISTS trg_job_parts_orders_updated_at;
CREATE TRIGGER IF NOT EXISTS trg_job_parts_orders_updated_at
AFTER UPDATE ON job_parts_orders
FOR EACH ROW
BEGIN
    UPDATE job_parts_orders SET updated_at = datetime('now') WHERE id = OLD.id;
END;


-- ═══════════════════════════════════════════════════════════
-- 2. JOB PREFERENCES — smart suggestion memory per job
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS job_preferences (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id INTEGER NOT NULL REFERENCES jobs(id),
    preference_type TEXT NOT NULL
        CHECK (preference_type IN ('brand', 'color', 'supplier', 'part')),
    entity_id INTEGER,              -- part_id or supplier_id (nullable for text-only prefs)
    text_value TEXT,                -- brand name, color name, or other text value
    category TEXT,                  -- part category this applies to (e.g. 'outlets', 'switches')
    is_active INTEGER NOT NULL DEFAULT 1,
    auto_learned INTEGER NOT NULL DEFAULT 1,   -- 1 = system learned, 0 = manually set
    confidence_score REAL NOT NULL DEFAULT 0.5, -- 0.0–1.0 ranking weight
    last_used_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(job_id, preference_type, entity_id, text_value, category)
);

CREATE INDEX IF NOT EXISTS idx_job_prefs_job ON job_preferences(job_id, is_active);
CREATE INDEX IF NOT EXISTS idx_job_prefs_type ON job_preferences(preference_type, entity_id);

-- Updated_at trigger
CREATE TRIGGER IF NOT EXISTS trg_job_preferences_updated_at
AFTER UPDATE ON job_preferences
FOR EACH ROW
BEGIN
    UPDATE job_preferences SET updated_at = datetime('now') WHERE id = OLD.id;
END;


-- ═══════════════════════════════════════════════════════════
-- 3. SPECIAL ITEMS — non-catalog items on an order
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS special_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    jpo_id INTEGER NOT NULL REFERENCES job_parts_orders(id) ON DELETE CASCADE,
    description TEXT NOT NULL,
    part_number TEXT,              -- optional manufacturer part #
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit TEXT NOT NULL DEFAULT 'each',
    estimated_cost REAL,
    notes TEXT,
    is_flagged INTEGER NOT NULL DEFAULT 1,   -- auto-flagged for office review
    flag_resolved_by INTEGER REFERENCES users(id),
    flag_resolved_at TEXT,
    linked_part_id INTEGER REFERENCES parts(id), -- if office matches to catalog
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_special_items_jpo ON special_items(jpo_id);
CREATE INDEX IF NOT EXISTS idx_special_items_flagged ON special_items(is_flagged);


-- ═══════════════════════════════════════════════════════════
-- 4. RE-ENABLE FOREIGN KEYS
-- ═══════════════════════════════════════════════════════════

PRAGMA foreign_keys = ON;


-- ═══════════════════════════════════════════════════════════
-- 5. VERIFY FK INTEGRITY (informational — failures logged by runner)
-- ═══════════════════════════════════════════════════════════

PRAGMA foreign_key_check;
