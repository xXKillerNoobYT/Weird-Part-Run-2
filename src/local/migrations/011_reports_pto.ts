/**
 * Migration 011: Reports & PTO
 *
 * Adds:
 * - report_annotations — post-generation notes on any report
 * - report_share_tokens — shareable links for external parties
 * - report_templates — saved filter presets
 * - pto_policies — per-employee PTO policy configuration
 * - pto_transactions — PTO accruals, usage, adjustments, carryover
 *
 * Source: backend migration 049
 */

export const migration = {
  name: '011_reports_pto',
  sql: `
-- ═══════════════════════════════════════════════════════════════════
-- REPORT ANNOTATIONS — post-generation notes on any report
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS report_annotations (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    report_type TEXT NOT NULL,
    context_key TEXT NOT NULL,
    content     TEXT NOT NULL,
    author_id   INTEGER NOT NULL REFERENCES users(id),
    deleted_at  TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_report_annotations_lookup
    ON report_annotations(report_type, context_key);


-- ═══════════════════════════════════════════════════════════════════
-- REPORT SHARE TOKENS — shareable links for external parties
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS report_share_tokens (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    token           TEXT NOT NULL UNIQUE,
    report_type     TEXT NOT NULL,
    context_params  TEXT NOT NULL DEFAULT '{}',
    label           TEXT,
    created_by      INTEGER NOT NULL REFERENCES users(id),
    expires_at      TEXT,
    last_accessed_at TEXT,
    is_active       INTEGER NOT NULL DEFAULT 1,
    deleted_at      TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_report_share_tokens_token
    ON report_share_tokens(token);


-- ═══════════════════════════════════════════════════════════════════
-- REPORT TEMPLATES — saved filter presets
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS report_templates (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    report_type TEXT NOT NULL,
    config_json TEXT NOT NULL DEFAULT '{}',
    created_by  INTEGER NOT NULL REFERENCES users(id),
    deleted_at  TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);


-- ═══════════════════════════════════════════════════════════════════
-- PTO POLICIES — per-employee PTO policy configuration
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS pto_policies (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id        INTEGER NOT NULL REFERENCES users(id),
    policy_name    TEXT NOT NULL DEFAULT 'Standard PTO',
    accrual_rate   REAL NOT NULL DEFAULT 3.33,
    accrual_period TEXT NOT NULL DEFAULT 'biweekly'
        CHECK(accrual_period IN ('weekly', 'biweekly', 'monthly')),
    max_balance     REAL,
    carryover_limit REAL,
    start_date      TEXT NOT NULL,
    is_active       INTEGER NOT NULL DEFAULT 1,
    deleted_at      TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_pto_policies_user_active
    ON pto_policies(user_id) WHERE is_active = 1;


-- ═══════════════════════════════════════════════════════════════════
-- PTO TRANSACTIONS — accruals, usage, adjustments, carryover
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS pto_transactions (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id          INTEGER NOT NULL REFERENCES users(id),
    transaction_type TEXT NOT NULL
        CHECK(transaction_type IN ('accrual', 'usage', 'adjustment', 'carryover', 'forfeit')),
    hours            REAL NOT NULL,
    balance_after    REAL NOT NULL,
    reference_id     INTEGER,
    reference_type   TEXT,
    note             TEXT,
    effective_date   TEXT NOT NULL,
    created_by       INTEGER REFERENCES users(id),
    deleted_at       TEXT,
    created_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_pto_transactions_user
    ON pto_transactions(user_id, effective_date);
  `,
};
