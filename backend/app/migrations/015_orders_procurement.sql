-- ═══════════════════════════════════════════════════════════════════════
-- Migration 015: Orders & Procurement
-- Phase 5 — Two-level ordering (JPO → PO), staging zones, returns,
--           notifications, company profiles, supplier communication ratings,
--           price history, and full chain-of-custody tracking.
-- ═══════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════
-- 1. JOB PARTS ORDERS (Level 1: field-worker requests)
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS job_parts_orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id INTEGER NOT NULL REFERENCES jobs(id),
    order_number TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN (
            'draft', 'pending_approval', 'approved', 'ordering',
            'partially_ordered', 'ordered', 'partially_received',
            'received', 'closed'
        )),
    priority TEXT DEFAULT 'normal'
        CHECK (priority IN ('normal', 'urgent')),
    requested_by INTEGER NOT NULL REFERENCES users(id),
    approved_by INTEGER REFERENCES users(id),
    approved_at TEXT,
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_jpo_job ON job_parts_orders(job_id);
CREATE INDEX IF NOT EXISTS idx_jpo_status ON job_parts_orders(status);
CREATE INDEX IF NOT EXISTS idx_jpo_requested_by ON job_parts_orders(requested_by);


-- ═══════════════════════════════════════════════
-- 2. JPO LINE ITEMS
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS jpo_line_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    jpo_id INTEGER NOT NULL REFERENCES job_parts_orders(id) ON DELETE CASCADE,
    part_id INTEGER NOT NULL REFERENCES parts(id),
    qty_requested INTEGER NOT NULL DEFAULT 1,
    qty_ordered INTEGER NOT NULL DEFAULT 0,
    qty_received INTEGER NOT NULL DEFAULT 0,
    priority TEXT DEFAULT 'normal'
        CHECK (priority IN ('normal', 'urgent', 'critical')),
    entry_id INTEGER REFERENCES notebook_entries(id),
    suggested_supplier_id INTEGER REFERENCES suppliers(id),
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_jpo_lines_jpo ON jpo_line_items(jpo_id);
CREATE INDEX IF NOT EXISTS idx_jpo_lines_part ON jpo_line_items(part_id);


-- ═══════════════════════════════════════════════
-- 3. PURCHASE ORDERS (Level 2: supplier-facing POs)
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS purchase_orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    po_number TEXT NOT NULL UNIQUE,
    supplier_id INTEGER NOT NULL REFERENCES suppliers(id),
    status TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN (
            'draft', 'submitted', 'acknowledged',
            'partially_received', 'received', 'closed', 'cancelled'
        )),
    order_date TEXT,
    expected_delivery TEXT,
    actual_delivery TEXT,
    shipping_method TEXT,
    tracking_number TEXT,
    subtotal REAL DEFAULT 0,
    tax_amount REAL DEFAULT 0,
    shipping_cost REAL DEFAULT 0,
    total_cost REAL DEFAULT 0,
    notes TEXT,
    internal_notes TEXT,
    pdf_path TEXT,
    pdf_generated_at TEXT,
    submitted_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_po_supplier ON purchase_orders(supplier_id);
CREATE INDEX IF NOT EXISTS idx_po_status ON purchase_orders(status);
CREATE INDEX IF NOT EXISTS idx_po_number ON purchase_orders(po_number);


-- ═══════════════════════════════════════════════
-- 4. PO LINE ITEMS
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS po_line_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    po_id INTEGER NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    jpo_line_id INTEGER REFERENCES jpo_line_items(id),
    part_id INTEGER NOT NULL REFERENCES parts(id),
    qty_ordered INTEGER NOT NULL,
    qty_received INTEGER NOT NULL DEFAULT 0,
    unit_cost REAL,
    received_unit_cost REAL,
    status TEXT DEFAULT 'pending'
        CHECK (status IN ('pending', 'partial', 'received', 'backordered', 'cancelled')),
    backorder_expected_date TEXT,
    received_at TEXT,
    received_by INTEGER REFERENCES users(id),
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_po_lines_po ON po_line_items(po_id);
CREATE INDEX IF NOT EXISTS idx_po_lines_part ON po_line_items(part_id);
CREATE INDEX IF NOT EXISTS idx_po_lines_jpo_line ON po_line_items(jpo_line_id);


-- ═══════════════════════════════════════════════
-- 5. RETURNS
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS returns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    return_number TEXT NOT NULL UNIQUE,
    return_type TEXT NOT NULL
        CHECK (return_type IN ('job_to_warehouse', 'warehouse_to_supplier')),
    po_id INTEGER REFERENCES purchase_orders(id),
    supplier_id INTEGER REFERENCES suppliers(id),
    job_id INTEGER REFERENCES jobs(id),
    status TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN (
            'draft', 'pending_approval', 'approved', 'shipped',
            'received_by_supplier', 'credited', 'closed'
        )),
    rma_number TEXT,
    reason TEXT NOT NULL
        CHECK (reason IN ('defective', 'wrong_item', 'surplus', 'damaged', 'unused')),
    shipping_carrier TEXT,
    tracking_number TEXT,
    credit_amount REAL DEFAULT 0,
    notes TEXT,
    initiated_by INTEGER NOT NULL REFERENCES users(id),
    approved_by INTEGER REFERENCES users(id),
    approved_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_returns_supplier ON returns(supplier_id);
CREATE INDEX IF NOT EXISTS idx_returns_job ON returns(job_id);
CREATE INDEX IF NOT EXISTS idx_returns_status ON returns(status);
CREATE INDEX IF NOT EXISTS idx_returns_type ON returns(return_type);


-- ═══════════════════════════════════════════════
-- 6. RETURN LINE ITEMS
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS return_line_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    return_id INTEGER NOT NULL REFERENCES returns(id) ON DELETE CASCADE,
    part_id INTEGER NOT NULL REFERENCES parts(id),
    po_line_id INTEGER REFERENCES po_line_items(id),
    qty INTEGER NOT NULL,
    condition TEXT DEFAULT 'new'
        CHECK (condition IN ('new', 'used', 'damaged', 'defective')),
    disposition TEXT NOT NULL
        CHECK (disposition IN ('return_to_supplier', 'restock', 'write_off')),
    unit_cost REAL,
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_return_lines_return ON return_line_items(return_id);
CREATE INDEX IF NOT EXISTS idx_return_lines_part ON return_line_items(part_id);


-- ═══════════════════════════════════════════════
-- 7. STAGING ZONES (physical QR-coded areas)
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS staging_zones (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    label TEXT NOT NULL,
    qr_code TEXT UNIQUE,
    zone_type TEXT DEFAULT 'general'
        CHECK (zone_type IN ('general', 'job_assigned', 'returns', 'overflow')),
    current_job_id INTEGER REFERENCES jobs(id),
    is_active INTEGER NOT NULL DEFAULT 1,
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_staging_zone_type ON staging_zones(zone_type);
CREATE INDEX IF NOT EXISTS idx_staging_zone_active ON staging_zones(is_active);


-- ═══════════════════════════════════════════════
-- 8. STAGING ZONE ASSIGNMENTS (job ↔ zone many-to-many)
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS staging_zone_assignments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    zone_id INTEGER NOT NULL REFERENCES staging_zones(id),
    job_id INTEGER NOT NULL REFERENCES jobs(id),
    assigned_at TEXT NOT NULL DEFAULT (datetime('now')),
    released_at TEXT,
    UNIQUE(zone_id, job_id)
);

CREATE INDEX IF NOT EXISTS idx_staging_assignments_zone ON staging_zone_assignments(zone_id);
CREATE INDEX IF NOT EXISTS idx_staging_assignments_job ON staging_zone_assignments(job_id);


-- ═══════════════════════════════════════════════
-- 9. ORDER STATUS HISTORY (full audit trail)
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS order_status_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type TEXT NOT NULL
        CHECK (entity_type IN ('jpo', 'po', 'return')),
    entity_id INTEGER NOT NULL,
    old_status TEXT,
    new_status TEXT NOT NULL,
    changed_by INTEGER NOT NULL REFERENCES users(id),
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_order_history_entity ON order_status_history(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_order_history_changed_by ON order_status_history(changed_by);


-- ═══════════════════════════════════════════════
-- 10. NOTIFICATIONS — extend existing table from 001
-- The notifications table already exists (001_foundation.sql).
-- Add columns needed for Phase 5: type, message, entity_type, entity_id.
-- ═══════════════════════════════════════════════

ALTER TABLE notifications ADD COLUMN type TEXT DEFAULT 'system';
ALTER TABLE notifications ADD COLUMN message TEXT;
ALTER TABLE notifications ADD COLUMN entity_type TEXT;
ALTER TABLE notifications ADD COLUMN entity_id INTEGER;

CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at);
CREATE INDEX IF NOT EXISTS idx_notifications_entity ON notifications(entity_type, entity_id);


-- ═══════════════════════════════════════════════
-- 11. NOTIFICATION PREFERENCES (per-user)
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS notification_preferences (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id),
    notification_type TEXT NOT NULL,
    is_enabled INTEGER NOT NULL DEFAULT 0,
    UNIQUE(user_id, notification_type)
);

CREATE INDEX IF NOT EXISTS idx_notif_prefs_user ON notification_preferences(user_id);


-- ═══════════════════════════════════════════════
-- 12. COMPANY PROFILES (for PO PDFs / branding)
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS company_profiles (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    address_street TEXT,
    address_city TEXT,
    address_state TEXT,
    address_zip TEXT,
    phone TEXT,
    email TEXT,
    website TEXT,
    logo_path TEXT,
    contractor_license TEXT,
    insurance_info TEXT,
    tax_id TEXT,
    is_primary INTEGER NOT NULL DEFAULT 0,
    branch_name TEXT,
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);


-- ═══════════════════════════════════════════════
-- 13. PRICE HISTORY (supplier pricing over time)
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS price_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id INTEGER NOT NULL REFERENCES parts(id),
    supplier_id INTEGER NOT NULL REFERENCES suppliers(id),
    price REAL NOT NULL,
    effective_date TEXT NOT NULL DEFAULT (date('now')),
    source TEXT DEFAULT 'manual'
        CHECK (source IN ('manual', 'po_receive', 'import')),
    reference_id INTEGER,
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_price_history_part_supplier ON price_history(part_id, supplier_id);
CREATE INDEX IF NOT EXISTS idx_price_history_date ON price_history(effective_date);


-- ═══════════════════════════════════════════════
-- 14. SUPPLIER CONTACT RATINGS
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS supplier_contact_ratings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    supplier_id INTEGER NOT NULL REFERENCES suppliers(id),
    contact_type TEXT NOT NULL
        CHECK (contact_type IN ('business', 'rep', 'driver')),
    rated_by INTEGER NOT NULL REFERENCES users(id),
    score INTEGER NOT NULL CHECK (score BETWEEN 1 AND 5),
    category TEXT
        CHECK (category IN ('responsiveness', 'accuracy', 'helpfulness', 'professionalism')),
    notes TEXT,
    interaction_date TEXT NOT NULL DEFAULT (date('now')),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_contact_ratings_supplier ON supplier_contact_ratings(supplier_id);
CREATE INDEX IF NOT EXISTS idx_contact_ratings_date ON supplier_contact_ratings(interaction_date);


-- ═══════════════════════════════════════════════
-- 15. ALTER EXISTING TABLES
-- ═══════════════════════════════════════════════

-- Add communication score to suppliers table
ALTER TABLE suppliers ADD COLUMN communication_score REAL DEFAULT 0.85;
ALTER TABLE suppliers ADD COLUMN rep_communication_notes TEXT;
ALTER TABLE suppliers ADD COLUMN driver_communication_notes TEXT;

-- Add index for task_order_links.po_id (future-proofed in migration 013)
CREATE INDEX IF NOT EXISTS idx_task_order_links_po ON task_order_links(po_id);


-- ═══════════════════════════════════════════════
-- 16. UPDATED_AT TRIGGERS (for new tables)
-- ═══════════════════════════════════════════════

CREATE TRIGGER IF NOT EXISTS trg_job_parts_orders_updated_at
AFTER UPDATE ON job_parts_orders
FOR EACH ROW
BEGIN
    UPDATE job_parts_orders SET updated_at = datetime('now') WHERE id = OLD.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_purchase_orders_updated_at
AFTER UPDATE ON purchase_orders
FOR EACH ROW
BEGIN
    UPDATE purchase_orders SET updated_at = datetime('now') WHERE id = OLD.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_returns_updated_at
AFTER UPDATE ON returns
FOR EACH ROW
BEGIN
    UPDATE returns SET updated_at = datetime('now') WHERE id = OLD.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_staging_zones_updated_at
AFTER UPDATE ON staging_zones
FOR EACH ROW
BEGIN
    UPDATE staging_zones SET updated_at = datetime('now') WHERE id = OLD.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_company_profiles_updated_at
AFTER UPDATE ON company_profiles
FOR EACH ROW
BEGIN
    UPDATE company_profiles SET updated_at = datetime('now') WHERE id = OLD.id;
END;


-- ═══════════════════════════════════════════════
-- 17. SEED DATA
-- ═══════════════════════════════════════════════

-- Default staging zones (physical areas)
INSERT OR IGNORE INTO staging_zones (id, label, qr_code, zone_type, notes)
VALUES
    (1, 'Area 1', 'STG-ZONE-001', 'general', 'Primary staging zone'),
    (2, 'Area 2', 'STG-ZONE-002', 'general', 'Secondary staging zone'),
    (3, 'Returns Zone', 'STG-ZONE-RET', 'returns', 'Dedicated returns staging');

-- Default company profile (placeholder — user fills in Settings)
INSERT OR IGNORE INTO company_profiles (id, name, is_primary, branch_name)
VALUES (1, 'My Electrical Company', 1, 'Main Office');

-- Seed notification types as settings for discoverability
INSERT OR IGNORE INTO settings (key, value, category) VALUES
    ('notification_types', '["jpo_approval","jpo_approved","jpo_rejected","po_submitted","po_received","delivery_expected","partial_receive","backorder_created","low_stock","audit_needed","task_assigned","return_approval","distribution_waiting","job_status_changed"]', 'notifications');
