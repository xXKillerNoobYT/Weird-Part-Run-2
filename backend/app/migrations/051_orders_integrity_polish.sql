-- Migration 051: Orders Integrity Polish
-- Adds missing CHECK constraints and indexes identified in production readiness audit.
-- All changes are additive (no data modification).

-- ═══════════════════════════════════════════════════════════════
-- 1. Missing indexes on po_groups (Phase 7B)
-- ═══════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_po_groups_created_by
    ON po_groups(created_by);

CREATE INDEX IF NOT EXISTS idx_po_groups_supplier
    ON po_groups(supplier_id);

-- ═══════════════════════════════════════════════════════════════
-- 2. receiving_session_items: Add CHECK constraints to prevent
--    negative quantities, which would indicate bad data.
--    SQLite doesn't support ALTER TABLE ADD CHECK, so we add a
--    trigger-based guard instead.
-- ═══════════════════════════════════════════════════════════════

-- Guard: prevent negative expected_qty on INSERT or UPDATE
CREATE TRIGGER IF NOT EXISTS trg_recv_items_qty_check_insert
BEFORE INSERT ON receiving_session_items
BEGIN
    SELECT CASE
        WHEN NEW.expected_qty < 0 THEN RAISE(ABORT, 'expected_qty cannot be negative')
        WHEN NEW.received_qty < 0 THEN RAISE(ABORT, 'received_qty cannot be negative')
    END;
END;

CREATE TRIGGER IF NOT EXISTS trg_recv_items_qty_check_update
BEFORE UPDATE ON receiving_session_items
BEGIN
    SELECT CASE
        WHEN NEW.expected_qty < 0 THEN RAISE(ABORT, 'expected_qty cannot be negative')
        WHEN NEW.received_qty < 0 THEN RAISE(ABORT, 'received_qty cannot be negative')
    END;
END;
