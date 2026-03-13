/**
 * Migration 005: Orders & Procurement
 *
 * JPOs, POs, returns, staging, status history, special items, job preferences.
 * Consolidated from: backend migrations 015, 018, 019, 020, 021, 022
 */

export const migration = {
  name: '005_orders',
  sql: `
-- ─── JOB PARTS ORDERS (field worker requests) ───────────────
CREATE TABLE IF NOT EXISTS job_parts_orders (
    id                        INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id                    INTEGER REFERENCES jobs(id),
    order_number              TEXT    NOT NULL UNIQUE,
    status                    TEXT    NOT NULL DEFAULT 'draft'
        CHECK (status IN (
            'draft','pending_approval','approved','ordering',
            'partially_ordered','ordered','partially_received',
            'received','closed'
        )),
    priority                  TEXT    DEFAULT 'normal'
        CHECK (priority IN ('normal','urgent')),
    order_type                TEXT    NOT NULL DEFAULT 'job'
        CHECK (order_type IN ('job','warehouse')),
    has_special_items         INTEGER NOT NULL DEFAULT 0,
    smart_suggestions_enabled INTEGER NOT NULL DEFAULT 1,
    requested_by              INTEGER NOT NULL REFERENCES users(id),
    approved_by               INTEGER REFERENCES users(id),
    approved_at               TEXT,
    notes                     TEXT,
    created_at                TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_jpo_job ON job_parts_orders(job_id);
CREATE INDEX IF NOT EXISTS idx_jpo_status ON job_parts_orders(status);
CREATE INDEX IF NOT EXISTS idx_jpo_requested_by ON job_parts_orders(requested_by);

-- ─── JPO LINE ITEMS ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS jpo_line_items (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    jpo_id                INTEGER NOT NULL REFERENCES job_parts_orders(id) ON DELETE CASCADE,
    part_id               INTEGER NOT NULL REFERENCES parts(id),
    qty_requested         INTEGER NOT NULL DEFAULT 1,
    qty_ordered           INTEGER NOT NULL DEFAULT 0,
    qty_received          INTEGER NOT NULL DEFAULT 0,
    priority              TEXT    DEFAULT 'normal'
        CHECK (priority IN ('normal','urgent','critical')),
    entry_id              INTEGER REFERENCES notebook_entries(id),
    suggested_supplier_id INTEGER REFERENCES suppliers(id),
    notes                 TEXT,
    created_at            TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_jpo_lines_jpo ON jpo_line_items(jpo_id);

-- ─── PURCHASE ORDERS (supplier-facing) ──────────────────────
CREATE TABLE IF NOT EXISTS purchase_orders (
    id                     INTEGER PRIMARY KEY AUTOINCREMENT,
    po_number              TEXT    NOT NULL UNIQUE,
    supplier_id            INTEGER NOT NULL REFERENCES suppliers(id),
    status                 TEXT    NOT NULL DEFAULT 'draft'
        CHECK (status IN (
            'draft','submitted','acknowledged',
            'partially_received','received','closed','cancelled'
        )),
    order_date             TEXT,
    expected_delivery      TEXT,
    actual_delivery        TEXT,
    shipping_method        TEXT,
    tracking_number        TEXT,
    subtotal               REAL    DEFAULT 0,
    tax_amount             REAL    DEFAULT 0,
    shipping_cost          REAL    DEFAULT 0,
    total_cost             REAL    DEFAULT 0,
    notes                  TEXT,
    internal_notes         TEXT,
    pdf_path               TEXT,
    pdf_generated_at       TEXT,
    confirmation_checklist TEXT,
    supplier_notes         TEXT,
    submitted_by           INTEGER REFERENCES users(id),
    created_at             TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at             TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_po_supplier ON purchase_orders(supplier_id);
CREATE INDEX IF NOT EXISTS idx_po_status ON purchase_orders(status);

-- ─── PO LINE ITEMS ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS po_line_items (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    po_id                   INTEGER NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    jpo_line_id             INTEGER REFERENCES jpo_line_items(id),
    part_id                 INTEGER NOT NULL REFERENCES parts(id),
    qty_ordered             INTEGER NOT NULL,
    qty_received            INTEGER NOT NULL DEFAULT 0,
    unit_cost               REAL,
    received_unit_cost      REAL,
    status                  TEXT    DEFAULT 'pending'
        CHECK (status IN ('pending','partial','received','backordered','cancelled')),
    backorder_expected_date TEXT,
    received_at             TEXT,
    received_by             INTEGER REFERENCES users(id),
    notes                   TEXT,
    created_at              TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_po_lines_po ON po_line_items(po_id);

-- ─── RETURNS ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS returns (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    return_number   TEXT    NOT NULL UNIQUE,
    return_type     TEXT    NOT NULL
        CHECK (return_type IN ('job_to_warehouse','warehouse_to_supplier')),
    po_id           INTEGER REFERENCES purchase_orders(id),
    supplier_id     INTEGER REFERENCES suppliers(id),
    job_id          INTEGER REFERENCES jobs(id),
    status          TEXT    NOT NULL DEFAULT 'draft'
        CHECK (status IN (
            'draft','pending_approval','approved','shipped',
            'received_by_supplier','credited','closed'
        )),
    rma_number      TEXT,
    reason          TEXT    NOT NULL
        CHECK (reason IN ('defective','wrong_item','surplus','damaged','unused')),
    shipping_carrier TEXT,
    tracking_number TEXT,
    credit_amount   REAL    DEFAULT 0,
    notes           TEXT,
    initiated_by    INTEGER NOT NULL REFERENCES users(id),
    approved_by     INTEGER REFERENCES users(id),
    approved_at     TEXT,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- ─── RETURN LINE ITEMS ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS return_line_items (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    return_id   INTEGER NOT NULL REFERENCES returns(id) ON DELETE CASCADE,
    part_id     INTEGER NOT NULL REFERENCES parts(id),
    po_line_id  INTEGER REFERENCES po_line_items(id),
    qty         INTEGER NOT NULL,
    condition   TEXT    DEFAULT 'new'
        CHECK (condition IN ('new','used','damaged','defective')),
    disposition TEXT    NOT NULL
        CHECK (disposition IN ('return_to_supplier','restock','write_off')),
    unit_cost   REAL,
    notes       TEXT,
    created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- ─── ORDER STATUS HISTORY ───────────────────────────────────
CREATE TABLE IF NOT EXISTS order_status_history (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type TEXT    NOT NULL
        CHECK (entity_type IN ('jpo','po','return')),
    entity_id   INTEGER NOT NULL,
    old_status  TEXT,
    new_status  TEXT    NOT NULL,
    changed_by  INTEGER NOT NULL REFERENCES users(id),
    notes       TEXT,
    created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_order_history_entity ON order_status_history(entity_type, entity_id);

-- ─── SPECIAL ITEMS ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS special_items (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    jpo_id           INTEGER NOT NULL REFERENCES job_parts_orders(id) ON DELETE CASCADE,
    description      TEXT    NOT NULL,
    part_number      TEXT,
    quantity         INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit             TEXT    NOT NULL DEFAULT 'each',
    estimated_cost   REAL,
    notes            TEXT,
    is_flagged       INTEGER NOT NULL DEFAULT 1,
    flag_resolved_by INTEGER REFERENCES users(id),
    flag_resolved_at TEXT,
    linked_part_id   INTEGER REFERENCES parts(id),
    created_at       TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_special_items_jpo ON special_items(jpo_id);

-- ─── JOB PREFERENCES ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS job_preferences (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id           INTEGER NOT NULL REFERENCES jobs(id),
    preference_type  TEXT    NOT NULL
        CHECK (preference_type IN ('brand','color','supplier','part')),
    entity_id        INTEGER,
    text_value       TEXT,
    category         TEXT,
    is_active        INTEGER NOT NULL DEFAULT 1,
    auto_learned     INTEGER NOT NULL DEFAULT 1,
    confidence_score REAL    NOT NULL DEFAULT 0.5,
    last_used_at     TEXT,
    created_at       TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at       TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE(job_id, preference_type, entity_id, text_value, category)
);
  `,
};
