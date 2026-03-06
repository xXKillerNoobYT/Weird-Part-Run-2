-- ═══════════════════════════════════════════════════════════════
-- Migration 021 — Phase 7D: Analytics & Visibility
--
-- New tables:
--   cost_layers           — FIFO/LIFO cost tracking per part receipt
--   company_cost_settings — company-wide cost & margin configuration
--
-- Altered tables:
--   parts  — weighted_avg_cost, custom_margin_percent, cost_last_updated
--   jobs   — budget_limit, budget_alert_percent
-- ═══════════════════════════════════════════════════════════════

-- Cost layers for FIFO/LIFO tracking.
-- Each receive from a PO creates a layer; consumption decrements remaining_qty.
CREATE TABLE IF NOT EXISTS cost_layers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id INTEGER NOT NULL REFERENCES parts(id),
    purchase_date TEXT NOT NULL,
    po_line_id INTEGER REFERENCES po_line_items(id),
    original_qty INTEGER NOT NULL,
    remaining_qty INTEGER NOT NULL,
    unit_cost REAL NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    CHECK(remaining_qty >= 0)
);

CREATE INDEX IF NOT EXISTS idx_cost_layers_part ON cost_layers(part_id, remaining_qty);
CREATE INDEX IF NOT EXISTS idx_cost_layers_date ON cost_layers(part_id, purchase_date);

-- Company-wide cost settings (margin defaults, cost method, auto-pricing).
CREATE TABLE IF NOT EXISTS company_cost_settings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    setting_key TEXT UNIQUE NOT NULL,
    setting_value TEXT NOT NULL,
    updated_by INTEGER REFERENCES users(id),
    updated_at TEXT DEFAULT (datetime('now'))
);

-- Seed default settings (INSERT OR IGNORE for safe re-runs)
INSERT OR IGNORE INTO company_cost_settings (setting_key, setting_value)
VALUES
    ('default_margin_percent', '25'),
    ('cost_method', 'weighted_average'),
    ('auto_update_pricing', 'true');

-- Parts table extensions for cost tracking
ALTER TABLE parts ADD COLUMN weighted_avg_cost REAL DEFAULT 0;
ALTER TABLE parts ADD COLUMN custom_margin_percent REAL;
ALTER TABLE parts ADD COLUMN cost_last_updated TEXT;

-- Jobs table extensions for budget tracking
ALTER TABLE jobs ADD COLUMN budget_limit REAL;
ALTER TABLE jobs ADD COLUMN budget_alert_percent REAL DEFAULT 80;
