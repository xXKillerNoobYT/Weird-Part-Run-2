-- Migration 048: Supplier Portal tokens
-- Allows generating unique access tokens for suppliers to view their POs,
-- acknowledge orders, and provide delivery updates.

CREATE TABLE IF NOT EXISTS supplier_portal_tokens (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    supplier_id INTEGER NOT NULL REFERENCES suppliers(id),
    token       TEXT    NOT NULL UNIQUE,
    note        TEXT,
    is_active   INTEGER NOT NULL DEFAULT 1,
    expires_at  TEXT,           -- ISO 8601 datetime
    last_used_at TEXT,
    created_by  INTEGER REFERENCES users(id),
    created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_supplier_portal_tokens_supplier
    ON supplier_portal_tokens(supplier_id);

CREATE INDEX IF NOT EXISTS idx_supplier_portal_tokens_token
    ON supplier_portal_tokens(token);

-- Track supplier acknowledgments of POs
CREATE TABLE IF NOT EXISTS supplier_po_acknowledgments (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    po_id              INTEGER NOT NULL REFERENCES purchase_orders(id),
    supplier_id        INTEGER NOT NULL REFERENCES suppliers(id),
    token_id           INTEGER REFERENCES supplier_portal_tokens(id),
    estimated_delivery TEXT,
    supplier_notes     TEXT,
    acknowledged_at    TEXT NOT NULL DEFAULT (datetime('now')),

    UNIQUE(po_id)  -- one acknowledgment per PO
);
