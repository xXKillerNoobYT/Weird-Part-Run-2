-- ═══════════════════════════════════════════════════════════════════════
-- Migration 020: Orders Redesign Phase 7C — Warehouse Workflow
--
-- New tables: receiving_sessions, receiving_session_items
-- Altered: return_line_items (add returnable_to_supplier,
--          non_return_reason, below_target_flag)
--
-- Provides: session-based receiving (packing slip + scan modes) and
-- enhanced return sorting with eligibility/below-target indicators.
-- ═══════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════
-- 1. RECEIVING SESSIONS — session-based receiving workflow
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS receiving_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    po_id INTEGER NOT NULL REFERENCES purchase_orders(id),
    started_by INTEGER NOT NULL REFERENCES users(id),
    mode TEXT NOT NULL DEFAULT 'packing_slip'
        CHECK (mode IN ('packing_slip', 'scan')),
    status TEXT NOT NULL DEFAULT 'in_progress'
        CHECK (status IN ('in_progress', 'completed', 'cancelled')),
    completed_at TEXT,
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_recv_sessions_po ON receiving_sessions(po_id);
CREATE INDEX IF NOT EXISTS idx_recv_sessions_status ON receiving_sessions(status);
CREATE INDEX IF NOT EXISTS idx_recv_sessions_started_by ON receiving_sessions(started_by);


-- ═══════════════════════════════════════════════════════════
-- 2. RECEIVING SESSION ITEMS — per-line receiving entries
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS receiving_session_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL REFERENCES receiving_sessions(id) ON DELETE CASCADE,
    po_line_id INTEGER NOT NULL REFERENCES po_line_items(id),
    expected_qty INTEGER NOT NULL DEFAULT 0,
    received_qty INTEGER NOT NULL DEFAULT 0,
    actual_cost REAL,
    staging_zone_id INTEGER REFERENCES staging_zones(id),
    scanned_at TEXT,
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_recv_items_session ON receiving_session_items(session_id);
CREATE INDEX IF NOT EXISTS idx_recv_items_po_line ON receiving_session_items(po_line_id);


-- ═══════════════════════════════════════════════════════════
-- 3. ALTER return_line_items — sorting guidance columns
-- ═══════════════════════════════════════════════════════════

-- Whether the item can be returned to the supplier
ALTER TABLE return_line_items ADD COLUMN returnable_to_supplier INTEGER DEFAULT 1;

-- If not returnable, the reason (used, damaged, custom_modified, opened, etc.)
ALTER TABLE return_line_items ADD COLUMN non_return_reason TEXT;

-- Whether the part is below its restock target quantity
ALTER TABLE return_line_items ADD COLUMN below_target_flag INTEGER DEFAULT 0;
