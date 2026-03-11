-- Migration 049: Report features (annotations, share tokens, templates)
--                + Scheduling features (PTO balance tracking)
-- Date: 2026-03-09

-- ═══════════════════════════════════════════════════════════════════
-- REPORT ANNOTATIONS — post-generation notes on any report
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS report_annotations (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    report_type     TEXT NOT NULL,                          -- daily_report | pre_billing | timesheet | labor_overview | profitability
    context_key     TEXT NOT NULL,                          -- unique per report instance: "daily:5:2026-03-01", "prebilling:5:2026-03-01:2026-03-31"
    content         TEXT NOT NULL,
    author_id       INTEGER NOT NULL REFERENCES users(id),
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_report_annotations_lookup
    ON report_annotations(report_type, context_key);


-- ═══════════════════════════════════════════════════════════════════
-- REPORT SHARE TOKENS — shareable links for external parties
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS report_share_tokens (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    token           TEXT NOT NULL UNIQUE,                   -- secrets.token_urlsafe(24)
    report_type     TEXT NOT NULL,                          -- daily_report | pre_billing | timesheet | labor_overview | profitability
    context_params  TEXT NOT NULL DEFAULT '{}',             -- JSON: query params to reconstruct report
    label           TEXT,                                   -- human-friendly label ("March 2026 Pre-Billing for GC Smith")
    created_by      INTEGER NOT NULL REFERENCES users(id),
    expires_at      TEXT,                                   -- NULL = never expires
    last_accessed_at TEXT,
    is_active       INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_report_share_tokens_token
    ON report_share_tokens(token);


-- ═══════════════════════════════════════════════════════════════════
-- REPORT TEMPLATES — saved filter presets
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS report_templates (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    name            TEXT NOT NULL,
    report_type     TEXT NOT NULL,                          -- pre_billing | timesheet | labor_overview | profitability
    config_json     TEXT NOT NULL DEFAULT '{}',             -- JSON: saved filters {job_id, employee_id, cycle, start_date, end_date}
    created_by      INTEGER NOT NULL REFERENCES users(id),
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);


-- ═══════════════════════════════════════════════════════════════════
-- PTO BALANCE TRACKING — accrual-based time-off balances
-- ═══════════════════════════════════════════════════════════════════

-- Per-employee PTO policy configuration
CREATE TABLE IF NOT EXISTS pto_policies (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         INTEGER NOT NULL REFERENCES users(id),
    policy_name     TEXT NOT NULL DEFAULT 'Standard PTO',  -- e.g. "Standard PTO", "Senior PTO"
    accrual_rate    REAL NOT NULL DEFAULT 3.33,            -- hours accrued per pay period (80hrs/yr ÷ 24 periods = 3.33)
    accrual_period  TEXT NOT NULL DEFAULT 'biweekly'
        CHECK(accrual_period IN ('weekly', 'biweekly', 'monthly')),
    max_balance     REAL,                                  -- cap on accrued hours (NULL = unlimited)
    carryover_limit REAL,                                  -- max hours that carry over to next year (NULL = unlimited)
    start_date      TEXT NOT NULL,                         -- when accrual begins
    is_active       INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_pto_policies_user_active
    ON pto_policies(user_id) WHERE is_active = 1;

-- PTO transactions: accruals, usage, adjustments, carryover
CREATE TABLE IF NOT EXISTS pto_transactions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         INTEGER NOT NULL REFERENCES users(id),
    transaction_type TEXT NOT NULL
        CHECK(transaction_type IN ('accrual', 'usage', 'adjustment', 'carryover', 'forfeit')),
    hours           REAL NOT NULL,                         -- positive for accrual/adjustment, negative for usage/forfeit
    balance_after   REAL NOT NULL,                         -- running balance after this transaction
    reference_id    INTEGER,                               -- links to schedule_exceptions.id for time-off usage
    reference_type  TEXT,                                   -- 'time_off' | 'manual' | 'system'
    note            TEXT,                                   -- e.g. "Biweekly accrual", "Vacation 3/1-3/5", "Manual adjustment by admin"
    effective_date  TEXT NOT NULL,                          -- when this transaction is effective
    created_by      INTEGER REFERENCES users(id),          -- NULL for system-generated accruals
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_pto_transactions_user
    ON pto_transactions(user_id, effective_date);
