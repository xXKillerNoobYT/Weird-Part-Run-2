/**
 * Migration 013: Tools & Supplier Extras
 *
 * Adds:
 * - tool_depreciation_entries — annual depreciation schedule
 * - notebook_entry_tools — junction linking notebook tasks to tools
 * - supplier_portal_tokens — access tokens for supplier portal
 * - supplier_po_acknowledgments — supplier PO acknowledgment tracking
 *
 * ALTER existing tables:
 * - tools: depreciation_method, salvage_value, useful_life_years, calibration_due_date
 * - tool_maintenance_records: calibration fields
 *
 * Source: backend migrations 050, 048
 */

export const migration = {
  name: '013_tools_supplier_extras',
  sql: `
-- ═══════════════════════════════════════════════════════════════════
-- ALTER tools — depreciation + calibration columns
-- ═══════════════════════════════════════════════════════════════════
ALTER TABLE tools ADD COLUMN depreciation_method TEXT
    CHECK (depreciation_method IS NULL OR depreciation_method IN (
        'straight_line', 'declining_balance', 'sum_of_years'
    ));
ALTER TABLE tools ADD COLUMN salvage_value REAL DEFAULT 0;
ALTER TABLE tools ADD COLUMN useful_life_years INTEGER;
ALTER TABLE tools ADD COLUMN calibration_due_date TEXT;


-- ═══════════════════════════════════════════════════════════════════
-- ALTER tool_maintenance_records — calibration tracking fields
-- ═══════════════════════════════════════════════════════════════════
ALTER TABLE tool_maintenance_records ADD COLUMN calibration_certificate TEXT;
ALTER TABLE tool_maintenance_records ADD COLUMN calibration_provider TEXT;
ALTER TABLE tool_maintenance_records ADD COLUMN calibration_standard TEXT;
ALTER TABLE tool_maintenance_records ADD COLUMN calibration_result TEXT
    CHECK (calibration_result IS NULL OR calibration_result IN (
        'pass', 'fail', 'adjusted', 'out_of_tolerance'
    ));


-- ═══════════════════════════════════════════════════════════════════
-- TOOL DEPRECIATION ENTRIES — annual depreciation schedule
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS tool_depreciation_entries (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id             INTEGER NOT NULL REFERENCES tools(id) ON DELETE CASCADE,
    year_number         INTEGER NOT NULL,
    fiscal_year         TEXT    NOT NULL,
    beginning_value     REAL    NOT NULL,
    depreciation_amount REAL    NOT NULL,
    accumulated         REAL    NOT NULL,
    ending_value        REAL    NOT NULL,
    deleted_at          TEXT,
    created_at          TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE(tool_id, year_number)
);

CREATE INDEX IF NOT EXISTS idx_tool_depr_tool ON tool_depreciation_entries(tool_id);
CREATE INDEX IF NOT EXISTS idx_tool_depr_year ON tool_depreciation_entries(fiscal_year);


-- ═══════════════════════════════════════════════════════════════════
-- NOTEBOOK ENTRY TOOLS — link notebook tasks to required tools
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS notebook_entry_tools (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id   INTEGER NOT NULL REFERENCES notebook_entries(id) ON DELETE CASCADE,
    tool_id    INTEGER NOT NULL REFERENCES tools(id) ON DELETE CASCADE,
    notes      TEXT,
    created_by INTEGER NOT NULL REFERENCES users(id),
    deleted_at TEXT,
    created_at TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE(entry_id, tool_id)
);

CREATE INDEX IF NOT EXISTS idx_nb_entry_tools_entry ON notebook_entry_tools(entry_id);
CREATE INDEX IF NOT EXISTS idx_nb_entry_tools_tool  ON notebook_entry_tools(tool_id);


-- ═══════════════════════════════════════════════════════════════════
-- SUPPLIER PORTAL TOKENS — access tokens for supplier portal
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS supplier_portal_tokens (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    supplier_id  INTEGER NOT NULL REFERENCES suppliers(id),
    token        TEXT    NOT NULL UNIQUE,
    note         TEXT,
    is_active    INTEGER NOT NULL DEFAULT 1,
    expires_at   TEXT,
    last_used_at TEXT,
    created_by   INTEGER REFERENCES users(id),
    deleted_at   TEXT,
    created_at   TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_supplier_portal_tokens_supplier
    ON supplier_portal_tokens(supplier_id);
CREATE INDEX IF NOT EXISTS idx_supplier_portal_tokens_token
    ON supplier_portal_tokens(token);


-- ═══════════════════════════════════════════════════════════════════
-- SUPPLIER PO ACKNOWLEDGMENTS — supplier acknowledgment tracking
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS supplier_po_acknowledgments (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    po_id              INTEGER NOT NULL REFERENCES purchase_orders(id),
    supplier_id        INTEGER NOT NULL REFERENCES suppliers(id),
    token_id           INTEGER REFERENCES supplier_portal_tokens(id),
    estimated_delivery TEXT,
    supplier_notes     TEXT,
    acknowledged_at    TEXT NOT NULL DEFAULT (datetime('now')),
    deleted_at         TEXT,
    UNIQUE(po_id)
);
  `,
};
