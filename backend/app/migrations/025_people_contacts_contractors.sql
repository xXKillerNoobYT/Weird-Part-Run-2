-- =============================================================
-- MIGRATION 025: People — Contacts & Contractors
-- =============================================================
-- Phase 10: Adds customers, general contractors, universal
-- flexible contacts, and many-to-many junction tables for
-- linking these entities to jobs.
--
-- Tables created:
--   customers               — customer entities with addresses
--   general_contractors     — GC companies with gc_code for PO naming
--   entity_contacts         — polymorphic contacts (customer/GC/supplier)
--   job_customers           — many-to-many: jobs ↔ customers
--   job_general_contractors — many-to-many: jobs ↔ GCs (bidirectional)
--
-- Also migrates existing supplier hardcoded contacts into
-- entity_contacts rows for backward compatibility.
-- =============================================================


-- ─── CUSTOMERS ──────────────────────────────────────────────
-- Full customer entity replacing the bare jobs.customer_name field.
-- Supports residential (no company) and commercial (company required).
-- display_name is a generated column for consistent display.
CREATE TABLE IF NOT EXISTS customers (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    company_name    TEXT,                              -- nullable for residential customers
    first_name      TEXT    NOT NULL,
    last_name       TEXT    NOT NULL,
    display_name    TEXT    GENERATED ALWAYS AS (
                        COALESCE(company_name, first_name || ' ' || last_name)
                    ) STORED,
    phone           TEXT,
    email           TEXT,
    address_line1   TEXT,
    address_line2   TEXT,
    city            TEXT,
    state           TEXT,
    zip             TEXT,
    customer_type   TEXT    DEFAULT 'residential'
                    CHECK(customer_type IN (
                        'residential', 'commercial', 'government', 'other'
                    )),
    notes           TEXT,
    is_active       INTEGER DEFAULT 1,
    created_at      TEXT    DEFAULT (datetime('now')),
    updated_at      TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_customers_name     ON customers(last_name, first_name);
CREATE INDEX IF NOT EXISTS idx_customers_company  ON customers(company_name);
CREATE INDEX IF NOT EXISTS idx_customers_type     ON customers(customer_type, is_active);
CREATE INDEX IF NOT EXISTS idx_customers_active   ON customers(is_active);

-- updated_at trigger
CREATE TRIGGER IF NOT EXISTS trg_customers_updated_at
    AFTER UPDATE ON customers
    FOR EACH ROW
BEGIN
    UPDATE customers SET updated_at = datetime('now') WHERE id = NEW.id;
END;


-- ─── GENERAL CONTRACTORS ────────────────────────────────────
-- External companies with bidirectional job relationships.
-- gc_code is a short identifier used in PO naming when they
-- hire us: PO=[GC_CODE]+[Job ID]+[Order Number].
-- trade_type categorizes the GC's primary trade.
CREATE TABLE IF NOT EXISTS general_contractors (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    company_name    TEXT    NOT NULL,
    gc_code         TEXT    NOT NULL UNIQUE,           -- short code: "SMITH", "TURNER"
    license_number  TEXT,
    trade_type      TEXT    DEFAULT 'general'
                    CHECK(trade_type IN (
                        'general', 'electrical', 'plumbing', 'hvac',
                        'mechanical', 'fire_protection', 'low_voltage', 'other'
                    )),
    phone           TEXT,
    email           TEXT,
    website         TEXT,
    address_line1   TEXT,
    address_line2   TEXT,
    city            TEXT,
    state           TEXT,
    zip             TEXT,
    insurance_info  TEXT,                              -- free text for cert/policy info
    notes           TEXT,
    is_active       INTEGER DEFAULT 1,
    created_at      TEXT    DEFAULT (datetime('now')),
    updated_at      TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_gc_name    ON general_contractors(company_name);
CREATE INDEX IF NOT EXISTS idx_gc_code    ON general_contractors(gc_code);
CREATE INDEX IF NOT EXISTS idx_gc_trade   ON general_contractors(trade_type, is_active);
CREATE INDEX IF NOT EXISTS idx_gc_active  ON general_contractors(is_active);

-- updated_at trigger
CREATE TRIGGER IF NOT EXISTS trg_gc_updated_at
    AFTER UPDATE ON general_contractors
    FOR EACH ROW
BEGIN
    UPDATE general_contractors SET updated_at = datetime('now') WHERE id = NEW.id;
END;


-- ─── ENTITY CONTACTS ────────────────────────────────────────
-- Universal flexible contacts using polymorphic (entity_type, entity_id).
-- Replaces the rigid 3-tier hardcoded supplier columns and provides
-- dynamic contacts for customers and GCs as well.
--
-- entity_type: 'customer', 'general_contractor', 'supplier'
-- entity_id:   FK to corresponding table (not enforced by SQLite FK,
--              managed in application layer like stock location_type)
--
-- role is freetext to support any contact role:
-- "Owner", "Foreman", "Dispatcher", "Sales Rep", "Driver", etc.
CREATE TABLE IF NOT EXISTS entity_contacts (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type     TEXT    NOT NULL
                    CHECK(entity_type IN (
                        'customer', 'general_contractor', 'supplier'
                    )),
    entity_id       INTEGER NOT NULL,
    first_name      TEXT    NOT NULL,
    last_name       TEXT    NOT NULL DEFAULT '',
    role            TEXT    NOT NULL,                  -- freetext: "Owner", "Foreman", etc.
    phone           TEXT    NOT NULL,                  -- mandatory per user requirement
    email           TEXT,
    is_primary      INTEGER DEFAULT 0,
    notes           TEXT,
    is_active       INTEGER DEFAULT 1,
    created_at      TEXT    DEFAULT (datetime('now')),
    updated_at      TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_entity_contacts_entity ON entity_contacts(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_entity_contacts_name   ON entity_contacts(last_name, first_name);
CREATE INDEX IF NOT EXISTS idx_entity_contacts_role   ON entity_contacts(role);
CREATE INDEX IF NOT EXISTS idx_entity_contacts_active ON entity_contacts(entity_type, entity_id, is_active);

-- updated_at trigger
CREATE TRIGGER IF NOT EXISTS trg_entity_contacts_updated_at
    AFTER UPDATE ON entity_contacts
    FOR EACH ROW
BEGIN
    UPDATE entity_contacts SET updated_at = datetime('now') WHERE id = NEW.id;
END;


-- ─── JOB ↔ CUSTOMERS (many-to-many) ────────────────────────
-- Links customers to jobs with a contact_role describing why
-- they're associated (owner, tenant, property manager, etc.).
-- One customer can appear on multiple jobs; one job can have
-- multiple customers with different roles.
CREATE TABLE IF NOT EXISTS job_customers (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id          INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    customer_id     INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    contact_role    TEXT    DEFAULT 'owner'
                    CHECK(contact_role IN (
                        'owner', 'property_manager', 'tenant',
                        'site_contact', 'billing', 'other'
                    )),
    is_primary      INTEGER DEFAULT 0,
    notes           TEXT,
    created_at      TEXT    DEFAULT (datetime('now')),

    UNIQUE(job_id, customer_id, contact_role)
);

CREATE INDEX IF NOT EXISTS idx_job_customers_job      ON job_customers(job_id);
CREATE INDEX IF NOT EXISTS idx_job_customers_customer  ON job_customers(customer_id);


-- ─── JOB ↔ GENERAL CONTRACTORS (many-to-many) ──────────────
-- Links GCs to jobs with a relationship direction:
--   'they_are_gc'   — they hired us (we're the sub). PO naming applies.
--   'we_hired_them' — we hired them as a sub. No PO integration,
--                     but subcontractor scheduling applies.
--
-- contract_amount and contract_number are optional metadata
-- for tracking the financial/contractual relationship.
CREATE TABLE IF NOT EXISTS job_general_contractors (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id          INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    gc_id           INTEGER NOT NULL REFERENCES general_contractors(id) ON DELETE CASCADE,
    relationship    TEXT    NOT NULL
                    CHECK(relationship IN ('they_are_gc', 'we_hired_them')),
    contract_amount REAL,                              -- nullable
    contract_number TEXT,                              -- nullable
    is_primary      INTEGER DEFAULT 0,
    notes           TEXT,
    created_at      TEXT    DEFAULT (datetime('now')),

    UNIQUE(job_id, gc_id)
);

CREATE INDEX IF NOT EXISTS idx_job_gc_job  ON job_general_contractors(job_id);
CREATE INDEX IF NOT EXISTS idx_job_gc_gc   ON job_general_contractors(gc_id);
CREATE INDEX IF NOT EXISTS idx_job_gc_rel  ON job_general_contractors(relationship);


-- ═══════════════════════════════════════════════════════════════
-- SUPPLIER CONTACT DATA MIGRATION
-- ═══════════════════════════════════════════════════════════════
-- Copy existing hardcoded 3-tier supplier contacts into the new
-- entity_contacts table. Original columns are NOT dropped — they
-- remain for backward compatibility (deprecated).
--
-- Migration strategy:
--   contact_name/phone/email → role 'Business Contact' (is_primary=1)
--   rep_name/email/phone     → role 'Sales Rep'
--   driver_name/phone/email  → role 'Driver'
--
-- Name splitting: first word = first_name, remainder = last_name.
-- If no space, entire name goes to first_name with empty last_name.
-- ═══════════════════════════════════════════════════════════════

-- 1. Business contacts (primary)
INSERT OR IGNORE INTO entity_contacts
    (entity_type, entity_id, first_name, last_name, role, phone, email, is_primary)
SELECT
    'supplier',
    id,
    CASE
        WHEN INSTR(contact_name, ' ') > 0
        THEN SUBSTR(contact_name, 1, INSTR(contact_name, ' ') - 1)
        ELSE contact_name
    END,
    CASE
        WHEN INSTR(contact_name, ' ') > 0
        THEN SUBSTR(contact_name, INSTR(contact_name, ' ') + 1)
        ELSE ''
    END,
    'Business Contact',
    COALESCE(phone, ''),
    email,
    1
FROM suppliers
WHERE contact_name IS NOT NULL AND contact_name != '';

-- 2. Sales reps
INSERT OR IGNORE INTO entity_contacts
    (entity_type, entity_id, first_name, last_name, role, phone, email, is_primary)
SELECT
    'supplier',
    id,
    CASE
        WHEN INSTR(rep_name, ' ') > 0
        THEN SUBSTR(rep_name, 1, INSTR(rep_name, ' ') - 1)
        ELSE rep_name
    END,
    CASE
        WHEN INSTR(rep_name, ' ') > 0
        THEN SUBSTR(rep_name, INSTR(rep_name, ' ') + 1)
        ELSE ''
    END,
    'Sales Rep',
    COALESCE(rep_phone, ''),
    rep_email,
    0
FROM suppliers
WHERE rep_name IS NOT NULL AND rep_name != '';

-- 3. Delivery drivers
INSERT OR IGNORE INTO entity_contacts
    (entity_type, entity_id, first_name, last_name, role, phone, email, is_primary)
SELECT
    'supplier',
    id,
    CASE
        WHEN INSTR(driver_name, ' ') > 0
        THEN SUBSTR(driver_name, 1, INSTR(driver_name, ' ') - 1)
        ELSE driver_name
    END,
    CASE
        WHEN INSTR(driver_name, ' ') > 0
        THEN SUBSTR(driver_name, INSTR(driver_name, ' ') + 1)
        ELSE ''
    END,
    'Driver',
    COALESCE(driver_phone, ''),
    driver_email,
    0
FROM suppliers
WHERE driver_name IS NOT NULL AND driver_name != '';
