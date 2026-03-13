/**
 * Migration 010: Costs & Receiving
 *
 * Adds:
 * - billing_periods — period locking for labor/cost freezing
 * - receiving_sessions — session-based receiving workflow
 * - receiving_session_items — per-line receiving entries
 * - ALTER return_line_items — sorting guidance columns
 *
 * Source: backend migrations 028, 020
 */

export const migration = {
  name: '010_costs_receiving',
  sql: `
-- ═══════════════════════════════════════════════════════════════════
-- BILLING PERIODS — period locking
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS billing_periods (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id       INTEGER REFERENCES jobs(id),
    period_start TEXT    NOT NULL,
    period_end   TEXT    NOT NULL,
    locked_at    TEXT,
    locked_by    INTEGER REFERENCES users(id),
    notes        TEXT,
    deleted_at   TEXT,
    created_at   TEXT    DEFAULT (datetime('now')),
    updated_at   TEXT    DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_billing_periods_job_range
    ON billing_periods(COALESCE(job_id, 0), period_start, period_end);
CREATE INDEX IF NOT EXISTS idx_billing_periods_job
    ON billing_periods(job_id);


-- ═══════════════════════════════════════════════════════════════════
-- RECEIVING SESSIONS — session-based receiving workflow
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS receiving_sessions (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    po_id       INTEGER NOT NULL REFERENCES purchase_orders(id),
    started_by  INTEGER NOT NULL REFERENCES users(id),
    mode        TEXT NOT NULL DEFAULT 'packing_slip'
                CHECK (mode IN ('packing_slip', 'scan')),
    status      TEXT NOT NULL DEFAULT 'in_progress'
                CHECK (status IN ('in_progress', 'completed', 'cancelled')),
    completed_at TEXT,
    notes       TEXT,
    deleted_at  TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_recv_sessions_po ON receiving_sessions(po_id);
CREATE INDEX IF NOT EXISTS idx_recv_sessions_status ON receiving_sessions(status);


-- ═══════════════════════════════════════════════════════════════════
-- RECEIVING SESSION ITEMS — per-line receiving entries
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS receiving_session_items (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id   INTEGER NOT NULL REFERENCES receiving_sessions(id) ON DELETE CASCADE,
    po_line_id   INTEGER NOT NULL REFERENCES po_line_items(id),
    expected_qty INTEGER NOT NULL DEFAULT 0,
    received_qty INTEGER NOT NULL DEFAULT 0,
    actual_cost  REAL,
    scanned_at   TEXT,
    notes        TEXT,
    deleted_at   TEXT,
    created_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_recv_items_session ON receiving_session_items(session_id);
CREATE INDEX IF NOT EXISTS idx_recv_items_po_line ON receiving_session_items(po_line_id);


-- ═══════════════════════════════════════════════════════════════════
-- ALTER return_line_items — sorting guidance columns
-- ═══════════════════════════════════════════════════════════════════
ALTER TABLE return_line_items ADD COLUMN returnable_to_supplier INTEGER DEFAULT 1;
ALTER TABLE return_line_items ADD COLUMN non_return_reason TEXT;
ALTER TABLE return_line_items ADD COLUMN below_target_flag INTEGER DEFAULT 0;
  `,
};
