-- =============================================================
-- MIGRATION 024: Tools & Kits
-- Phase 9 — Tool registry, kit verification checklists,
--           checkout/return flow, maintenance tracking,
--           cross-module visibility (warehouse, trucks, jobs),
--           and QR code tracking support.
-- =============================================================


-- ═══ 1. TOOLS — Core registry ════════════════════════════════════════
-- Individual tracked assets (not bulk inventory like parts).
-- Each tool has a current location using the same polymorphic
-- (location_type, location_id) pattern as the stock table.

CREATE TABLE IF NOT EXISTS tools (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_number         TEXT    NOT NULL UNIQUE,          -- "T-001", "DRL-005"
    name                TEXT    NOT NULL,                 -- "Milwaukee M18 Impact Driver"
    category            TEXT    NOT NULL DEFAULT 'general'
        CHECK (category IN (
            'power_tool', 'hand_tool', 'meter', 'safety',
            'conduit', 'cable', 'lighting', 'general'
        )),

    -- Manufacturer info
    brand               TEXT,                             -- "Milwaukee", "DeWalt"
    model_number        TEXT,
    serial_number       TEXT,

    -- Financials
    purchase_date       TEXT,                             -- ISO date
    purchase_cost       REAL,
    warranty_expiry     TEXT,                             -- ISO date

    -- Current location (polymorphic)
    location_type       TEXT    NOT NULL DEFAULT 'warehouse'
        CHECK (location_type IN ('warehouse', 'truck', 'job')),
    location_id         INTEGER,                          -- FK to warehouse_locations, vehicles, or jobs

    -- Who currently has the tool
    assigned_to         INTEGER REFERENCES users(id),

    -- Status tracking
    status              TEXT    NOT NULL DEFAULT 'available'
        CHECK (status IN (
            'available', 'checked_out', 'in_maintenance',
            'lost', 'retired', 'damaged'
        )),
    condition_rating    INTEGER DEFAULT 5
        CHECK (condition_rating BETWEEN 1 AND 5),         -- 1=poor, 5=excellent

    -- Kit flag: tool has required components
    has_kit             INTEGER NOT NULL DEFAULT 0,

    -- Metadata
    notes               TEXT,
    photo_path          TEXT,
    barcode             TEXT,                              -- QR code value (e.g. "/tools/scan/T-001")

    is_active           INTEGER NOT NULL DEFAULT 1,
    created_at          TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_tools_number     ON tools(tool_number);
CREATE INDEX IF NOT EXISTS idx_tools_category   ON tools(category);
CREATE INDEX IF NOT EXISTS idx_tools_location   ON tools(location_type, location_id);
CREATE INDEX IF NOT EXISTS idx_tools_assigned   ON tools(assigned_to);
CREATE INDEX IF NOT EXISTS idx_tools_status     ON tools(status);
CREATE INDEX IF NOT EXISTS idx_tools_barcode    ON tools(barcode);
CREATE INDEX IF NOT EXISTS idx_tools_active     ON tools(is_active);


-- ═══ 2. KIT TEMPLATES — Required components per tool ═════════════════
-- Defines what must travel with a tool case: charger, batteries,
-- bits, blades, accessories. Used to generate verification checklists.

CREATE TABLE IF NOT EXISTS kit_templates (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id             INTEGER NOT NULL REFERENCES tools(id) ON DELETE CASCADE,
    component_name      TEXT    NOT NULL,                  -- "M18 Charger", "5.0Ah Battery"
    component_type      TEXT    NOT NULL DEFAULT 'accessory'
        CHECK (component_type IN (
            'charger', 'battery', 'blade', 'bit_set',
            'case', 'accessory', 'cable', 'adapter', 'other'
        )),
    qty_required        INTEGER NOT NULL DEFAULT 1
        CHECK (qty_required >= 1),                        -- e.g. 2 batteries
    brand               TEXT,
    model_number        TEXT,
    is_critical         INTEGER NOT NULL DEFAULT 0,       -- 1 = tool unusable without this
    sort_order          INTEGER DEFAULT 0,
    notes               TEXT
);

CREATE INDEX IF NOT EXISTS idx_kit_templates_tool ON kit_templates(tool_id);


-- ═══ 3. TOOL MOVEMENTS — Immutable audit log ═════════════════════════
-- Every checkout, return, transfer, registration, retirement is
-- permanently logged here. Insert-only — never updated or deleted.

CREATE TABLE IF NOT EXISTS tool_movements (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id             INTEGER NOT NULL REFERENCES tools(id),

    -- From / To locations (NULL for register → first location, retire → nowhere)
    from_location_type  TEXT
        CHECK (from_location_type IS NULL OR from_location_type IN ('warehouse', 'truck', 'job')),
    from_location_id    INTEGER,
    to_location_type    TEXT
        CHECK (to_location_type IS NULL OR to_location_type IN ('warehouse', 'truck', 'job')),
    to_location_id      INTEGER,

    movement_type       TEXT    NOT NULL
        CHECK (movement_type IN (
            'register', 'checkout', 'return', 'transfer',
            'maintenance_in', 'maintenance_out', 'retire', 'lost'
        )),
    reason              TEXT,

    -- Optional job context (e.g. "checked out for Job #1234")
    job_id              INTEGER REFERENCES jobs(id),

    -- Who performed and who verified
    performed_by        INTEGER NOT NULL REFERENCES users(id),
    verified_by         INTEGER REFERENCES users(id),

    -- Condition at time of movement
    condition_at_move   INTEGER CHECK (condition_at_move IS NULL OR condition_at_move BETWEEN 1 AND 5),

    created_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_tool_movements_tool      ON tool_movements(tool_id);
CREATE INDEX IF NOT EXISTS idx_tool_movements_type      ON tool_movements(movement_type);
CREATE INDEX IF NOT EXISTS idx_tool_movements_from      ON tool_movements(from_location_type, from_location_id);
CREATE INDEX IF NOT EXISTS idx_tool_movements_to        ON tool_movements(to_location_type, to_location_id);
CREATE INDEX IF NOT EXISTS idx_tool_movements_job       ON tool_movements(job_id);
CREATE INDEX IF NOT EXISTS idx_tool_movements_by        ON tool_movements(performed_by);
CREATE INDEX IF NOT EXISTS idx_tool_movements_date      ON tool_movements(created_at);


-- ═══ 4. KIT VERIFICATION SESSIONS ════════════════════════════════════
-- Created on checkout/return when a tool has a kit. Tracks the
-- overall session state: who verified, what triggered it, completeness.

CREATE TABLE IF NOT EXISTS kit_verification_sessions (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id             INTEGER NOT NULL REFERENCES tools(id),
    movement_id         INTEGER REFERENCES tool_movements(id),  -- link to triggering movement
    verified_by         INTEGER NOT NULL REFERENCES users(id),
    trigger_type        TEXT    NOT NULL
        CHECK (trigger_type IN ('checkout', 'return', 'audit', 'manual')),
    is_complete         INTEGER NOT NULL DEFAULT 0,       -- 1 when all items checked off
    missing_count       INTEGER NOT NULL DEFAULT 0,       -- count of missing critical items
    notes               TEXT,
    created_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_kit_vsess_tool    ON kit_verification_sessions(tool_id);
CREATE INDEX IF NOT EXISTS idx_kit_vsess_date    ON kit_verification_sessions(created_at);


-- ═══ 5. KIT VERIFICATION ITEMS ═══════════════════════════════════════
-- Per-component checklist entries within a verification session.
-- Pre-populated from kit_templates when a session starts.

CREATE TABLE IF NOT EXISTS kit_verification_items (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id          INTEGER NOT NULL REFERENCES kit_verification_sessions(id) ON DELETE CASCADE,
    template_item_id    INTEGER NOT NULL REFERENCES kit_templates(id),
    is_present          INTEGER NOT NULL DEFAULT 0,       -- 1 = checked off / present
    condition_rating    INTEGER CHECK (condition_rating IS NULL OR condition_rating BETWEEN 1 AND 5),
    notes               TEXT
);

CREATE INDEX IF NOT EXISTS idx_kit_vitems_session ON kit_verification_items(session_id);


-- ═══ 6. TOOL MAINTENANCE TYPES ═══════════════════════════════════════
-- Configurable service categories for tools. Seeded with common
-- tool maintenance activities (calibration, battery replacement, etc.).
-- Separate from vehicle maintenance_types to avoid mixing concerns.

CREATE TABLE IF NOT EXISTS tool_maintenance_types (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    name                TEXT    NOT NULL UNIQUE,
    description         TEXT,
    default_interval_days INTEGER,                        -- e.g. 365 for annual calibration
    sort_order          INTEGER DEFAULT 0,
    is_active           INTEGER NOT NULL DEFAULT 1,
    created_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);


-- ═══ 7. TOOL MAINTENANCE SCHEDULES ═══════════════════════════════════
-- Per-tool customization of maintenance intervals. Same cascade
-- pattern as vehicle_maintenance_schedules from migration 017.

CREATE TABLE IF NOT EXISTS tool_maintenance_schedules (
    id                       INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id                  INTEGER NOT NULL REFERENCES tools(id) ON DELETE CASCADE,
    maintenance_type_id      INTEGER NOT NULL REFERENCES tool_maintenance_types(id),
    interval_days            INTEGER,                     -- override default from type
    last_performed_at        TEXT,                        -- ISO date of last service
    next_due_date            TEXT,                        -- calculated: last + interval
    is_enabled               INTEGER NOT NULL DEFAULT 1,
    notes                    TEXT,
    created_at               TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at               TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE(tool_id, maintenance_type_id)
);

CREATE INDEX IF NOT EXISTS idx_tool_msched_tool     ON tool_maintenance_schedules(tool_id);
CREATE INDEX IF NOT EXISTS idx_tool_msched_due      ON tool_maintenance_schedules(next_due_date);


-- ═══ 8. TOOL MAINTENANCE RECORDS ═════════════════════════════════════
-- Immutable service history. Each record captures what was done,
-- when, cost, vendor, and who logged it. Follows the same pattern
-- as vehicle_maintenance_records.

CREATE TABLE IF NOT EXISTS tool_maintenance_records (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id             INTEGER NOT NULL REFERENCES tools(id),
    maintenance_type_id INTEGER NOT NULL REFERENCES tool_maintenance_types(id),
    service_date        TEXT    NOT NULL DEFAULT (date('now')),
    cost                REAL    DEFAULT 0,
    vendor              TEXT,
    description         TEXT,
    performed_by        INTEGER REFERENCES users(id),
    notes               TEXT,
    created_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_tool_mrec_tool   ON tool_maintenance_records(tool_id);
CREATE INDEX IF NOT EXISTS idx_tool_mrec_type   ON tool_maintenance_records(maintenance_type_id);
CREATE INDEX IF NOT EXISTS idx_tool_mrec_date   ON tool_maintenance_records(service_date);


-- ═══════════════════════════════════════════════════════════════════════
-- UPDATED_AT TRIGGERS
-- Following migration 017 pattern (no WHEN guard — simpler, always fires)
-- ═══════════════════════════════════════════════════════════════════════

CREATE TRIGGER IF NOT EXISTS trg_tools_updated_at
AFTER UPDATE ON tools
FOR EACH ROW
BEGIN
    UPDATE tools SET updated_at = datetime('now') WHERE id = OLD.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_tool_maint_schedules_updated_at
AFTER UPDATE ON tool_maintenance_schedules
FOR EACH ROW
BEGIN
    UPDATE tool_maintenance_schedules SET updated_at = datetime('now') WHERE id = OLD.id;
END;


-- ═══════════════════════════════════════════════════════════════════════
-- SEED: TOOL MAINTENANCE TYPES
-- Common maintenance activities for power tools, meters, and equipment.
-- ═══════════════════════════════════════════════════════════════════════

INSERT OR IGNORE INTO tool_maintenance_types (name, description, default_interval_days, sort_order) VALUES
    ('Calibration',          'Meter/instrument calibration verification',       365,  1),
    ('Battery Replacement',  'Replace worn or degraded batteries',              365,  2),
    ('Blade Replacement',    'Replace saw blades, cutting wheels',              180,  3),
    ('General Service',      'Lubrication, cleaning, general maintenance',      180,  4),
    ('Safety Inspection',    'Check guards, cords, grounding, GFI',            90,   5),
    ('Warranty Service',     'Manufacturer warranty repair or replacement',     NULL,  6);


-- ═══════════════════════════════════════════════════════════════════════
-- SEED: TOOL SETTINGS
-- ═══════════════════════════════════════════════════════════════════════

INSERT OR IGNORE INTO settings (key, value, category) VALUES
    ('tool_maintenance_alert_days_ahead',       '14',    'tools'),
    ('require_kit_verification_on_checkout',    '1',     'tools'),
    ('require_kit_verification_on_return',      '1',     'tools');


-- ═══════════════════════════════════════════════════════════════════════
-- PERMISSIONS
-- ═══════════════════════════════════════════════════════════════════════

-- manage_tools: Register/edit/retire tools, manage kit templates, maintenance types
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'manage_tools' FROM hats WHERE name IN ('Admin', 'Manager');

-- checkout_tools: Check out and return tools, perform kit verification
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'checkout_tools' FROM hats WHERE name IN ('Admin', 'Manager', 'Lead', 'Worker');

-- view_tools: See tool registry, locations, maintenance status
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'view_tools' FROM hats WHERE name IN ('Admin', 'Manager', 'Lead', 'Worker');
