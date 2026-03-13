/**
 * Migration 014: Contacts, Costs, & Company Profiles
 *
 * Adds:
 * - entity_contacts — polymorphic contact people for customers/GCs/suppliers
 * - job_customers — many-to-many job ↔ customer
 * - job_general_contractors — many-to-many job ↔ GC
 * - cost_layers — FIFO/LIFO cost tracking per part
 * - company_cost_settings — margin & pricing defaults
 * - company_profiles — company/branch info for PDF headers
 * - ALTER parts — weighted_avg_cost, custom_margin_percent, cost_last_updated
 * - ALTER jobs — budget_limit, budget_alert_percent
 *
 * Source: backend migrations 025, 021, 015
 */

export const migration = {
  name: '014_contacts_costs_profiles',
  sql: `
-- ═══════════════════════════════════════════════════════════════════
-- ENTITY CONTACTS — contacts for customers, GCs, suppliers
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS entity_contacts (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type TEXT    NOT NULL
                CHECK(entity_type IN ('customer', 'general_contractor', 'supplier')),
    entity_id   INTEGER NOT NULL,
    first_name  TEXT    NOT NULL,
    last_name   TEXT    NOT NULL DEFAULT '',
    role        TEXT    NOT NULL,
    phone       TEXT    NOT NULL,
    email       TEXT,
    is_primary  INTEGER DEFAULT 0,
    notes       TEXT,
    is_active   INTEGER DEFAULT 1,
    deleted_at  TEXT,
    created_at  TEXT    DEFAULT (datetime('now')),
    updated_at  TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_entity_contacts_entity ON entity_contacts(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_entity_contacts_name   ON entity_contacts(last_name, first_name);


-- ═══════════════════════════════════════════════════════════════════
-- JOB ↔ CUSTOMER (many-to-many)
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS job_customers (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id        INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    customer_id   INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    contact_role  TEXT    DEFAULT 'owner'
                  CHECK(contact_role IN (
                      'owner', 'property_manager', 'tenant',
                      'site_contact', 'billing', 'other'
                  )),
    is_primary    INTEGER DEFAULT 0,
    notes         TEXT,
    deleted_at    TEXT,
    created_at    TEXT    DEFAULT (datetime('now')),
    UNIQUE(job_id, customer_id, contact_role)
);

CREATE INDEX IF NOT EXISTS idx_job_customers_job      ON job_customers(job_id);
CREATE INDEX IF NOT EXISTS idx_job_customers_customer  ON job_customers(customer_id);


-- ═══════════════════════════════════════════════════════════════════
-- JOB ↔ GENERAL CONTRACTORS (many-to-many)
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS job_general_contractors (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id          INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    gc_id           INTEGER NOT NULL REFERENCES general_contractors(id) ON DELETE CASCADE,
    relationship    TEXT    NOT NULL
                    CHECK(relationship IN ('they_are_gc', 'we_hired_them')),
    contract_amount REAL,
    contract_number TEXT,
    is_primary      INTEGER DEFAULT 0,
    notes           TEXT,
    deleted_at      TEXT,
    created_at      TEXT    DEFAULT (datetime('now')),
    UNIQUE(job_id, gc_id)
);

CREATE INDEX IF NOT EXISTS idx_job_gc_job  ON job_general_contractors(job_id);
CREATE INDEX IF NOT EXISTS idx_job_gc_gc   ON job_general_contractors(gc_id);
CREATE INDEX IF NOT EXISTS idx_job_gc_rel  ON job_general_contractors(relationship);


-- ═══════════════════════════════════════════════════════════════════
-- COST LAYERS — FIFO/LIFO inventory cost tracking
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS cost_layers (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id       INTEGER NOT NULL REFERENCES parts(id),
    purchase_date TEXT    NOT NULL,
    po_line_id    INTEGER REFERENCES po_line_items(id),
    original_qty  INTEGER NOT NULL,
    remaining_qty INTEGER NOT NULL,
    unit_cost     REAL    NOT NULL,
    created_at    TEXT    DEFAULT (datetime('now')),
    CHECK(remaining_qty >= 0)
);

CREATE INDEX IF NOT EXISTS idx_cost_layers_part ON cost_layers(part_id, remaining_qty);
CREATE INDEX IF NOT EXISTS idx_cost_layers_date ON cost_layers(part_id, purchase_date);


-- ═══════════════════════════════════════════════════════════════════
-- COMPANY COST SETTINGS — margin & pricing defaults
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS company_cost_settings (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    setting_key   TEXT UNIQUE NOT NULL,
    setting_value TEXT NOT NULL,
    updated_by    INTEGER REFERENCES users(id),
    updated_at    TEXT DEFAULT (datetime('now'))
);

INSERT OR IGNORE INTO company_cost_settings (setting_key, setting_value)
VALUES
    ('default_margin_percent', '25'),
    ('cost_method', 'weighted_average'),
    ('auto_update_pricing', 'true');


-- ═══════════════════════════════════════════════════════════════════
-- COMPANY PROFILES — company/branch info for PDF headers
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS company_profiles (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    name               TEXT NOT NULL,
    address_street     TEXT,
    address_city       TEXT,
    address_state      TEXT,
    address_zip        TEXT,
    phone              TEXT,
    email              TEXT,
    website            TEXT,
    logo_path          TEXT,
    contractor_license TEXT,
    insurance_info     TEXT,
    tax_id             TEXT,
    is_primary         INTEGER NOT NULL DEFAULT 0,
    branch_name        TEXT,
    notes              TEXT,
    deleted_at         TEXT,
    created_at         TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at         TEXT NOT NULL DEFAULT (datetime('now'))
);


-- ═══════════════════════════════════════════════════════════════════
-- ALTER PARTS — cost tracking columns
-- ═══════════════════════════════════════════════════════════════════
ALTER TABLE parts ADD COLUMN weighted_avg_cost REAL DEFAULT 0;
ALTER TABLE parts ADD COLUMN custom_margin_percent REAL;
ALTER TABLE parts ADD COLUMN cost_last_updated TEXT;


-- ═══════════════════════════════════════════════════════════════════
-- ALTER JOBS — budget tracking columns
-- ═══════════════════════════════════════════════════════════════════
ALTER TABLE jobs ADD COLUMN budget_limit REAL;
ALTER TABLE jobs ADD COLUMN budget_alert_percent REAL DEFAULT 80;
  `,
};
