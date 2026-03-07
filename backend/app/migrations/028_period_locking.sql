-- ═══════════════════════════════════════════════════════════════════════
-- Migration 028: Billing Period Locking
--
-- Allows locking billing periods so labor entries, stock movements,
-- and cost adjustments within a locked date range cannot be modified.
-- Supports per-job locks (job_id set) or company-wide locks (job_id NULL).
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS billing_periods (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id          INTEGER REFERENCES jobs(id),        -- NULL = company-wide lock
    period_start    TEXT    NOT NULL,                    -- ISO date
    period_end      TEXT    NOT NULL,                    -- ISO date
    locked_at       TEXT,                                -- NULL = open, timestamp = locked
    locked_by       INTEGER REFERENCES users(id),
    notes           TEXT,
    created_at      TEXT    DEFAULT (datetime('now')),
    updated_at      TEXT    DEFAULT (datetime('now'))
);

-- Prevent duplicate periods for the same job + date range
CREATE UNIQUE INDEX IF NOT EXISTS idx_billing_periods_job_range
    ON billing_periods(COALESCE(job_id, 0), period_start, period_end);

-- Fast lookup by job
CREATE INDEX IF NOT EXISTS idx_billing_periods_job
    ON billing_periods(job_id);
