-- =============================================================
-- MIGRATION 001: Foundation
-- =============================================================
-- Creates the core tables for users, hats (roles), permissions,
-- devices, settings, activity log, and notifications.
-- Seeds 7 built-in hats with ~30 permission keys.
-- Creates a default Admin user (PIN: 1234).
-- =============================================================

-- ─── USERS ──────────────────────────────────────────────────────
-- Core user table. Every person who uses the app has a row here.
-- Hats are assigned via the user_hats junction table.
CREATE TABLE IF NOT EXISTS users (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    display_name            TEXT    NOT NULL,
    email                   TEXT,
    phone                   TEXT,
    pin_hash                TEXT    NOT NULL,               -- bcrypt hash of 4-6 digit PIN
    default_truck_id        INTEGER,                        -- FK to trucks (Phase 4+)
    emergency_contact_name  TEXT,
    emergency_contact_phone TEXT,
    certification           TEXT    CHECK(certification IN ('journeyman', 'apprentice', 'master', NULL)),
    hire_date               TEXT,                           -- ISO date string
    pay_rate                REAL,                           -- hourly rate for labor cost calc
    is_active               INTEGER DEFAULT 1,              -- 1=active, 0=deactivated
    avatar_url              TEXT,
    created_at              TEXT    DEFAULT (datetime('now')),
    updated_at              TEXT    DEFAULT (datetime('now'))
);


-- ─── HATS (Roles) ──────────────────────────────────────────────
-- A "hat" is a role. Users can wear multiple hats (additive union).
-- 7 built-in hats ship with the app; admins can create custom ones.
CREATE TABLE IF NOT EXISTS hats (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL UNIQUE,
    description TEXT,
    level       INTEGER DEFAULT 0,                          -- 0=highest (Admin), 6=lowest (Grunt)
    is_builtin  INTEGER DEFAULT 0,                          -- 1=cannot be deleted
    created_at  TEXT    DEFAULT (datetime('now'))
);


-- ─── HAT PERMISSIONS ────────────────────────────────────────────
-- Maps permission keys to hats. A user's effective permissions are
-- the UNION of all permissions from all their hats.
CREATE TABLE IF NOT EXISTS hat_permissions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    hat_id          INTEGER NOT NULL REFERENCES hats(id) ON DELETE CASCADE,
    permission_key  TEXT    NOT NULL,
    UNIQUE(hat_id, permission_key)
);

CREATE INDEX IF NOT EXISTS idx_hat_perms_hat ON hat_permissions(hat_id);
CREATE INDEX IF NOT EXISTS idx_hat_perms_key ON hat_permissions(permission_key);


-- ─── USER ↔ HAT JUNCTION ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_hats (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    hat_id  INTEGER NOT NULL REFERENCES hats(id) ON DELETE CASCADE,
    UNIQUE(user_id, hat_id)
);

CREATE INDEX IF NOT EXISTS idx_user_hats_user ON user_hats(user_id);


-- ─── JOB LEAD ELEVATIONS ───────────────────────────────────────
-- Temporary per-job permission grants. A Worker can be elevated
-- to Lead for a specific job with scoped extra permissions.
CREATE TABLE IF NOT EXISTS job_lead_elevations (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    job_id          INTEGER NOT NULL,                       -- FK to jobs (Phase 4+)
    permission_key  TEXT    NOT NULL,
    granted_by      INTEGER REFERENCES users(id),
    granted_at      TEXT    DEFAULT (datetime('now')),
    expires_at      TEXT,                                   -- NULL = until job closes
    UNIQUE(user_id, job_id, permission_key)
);


-- ─── DEVICES ────────────────────────────────────────────────────
-- Tracks each device (browser/tablet/phone) that has accessed the app.
-- Non-public devices auto-login their assigned user.
-- Public devices (warehouse tablet, shared computer) require PIN every time.
CREATE TABLE IF NOT EXISTS devices (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    device_name         TEXT    NOT NULL,                    -- "Chrome on Windows", etc.
    device_fingerprint  TEXT    UNIQUE NOT NULL,             -- Unique browser/device ID
    assigned_user_id    INTEGER REFERENCES users(id),       -- NULL = unassigned
    is_public           INTEGER DEFAULT 0,                  -- 1 = requires login every time
    last_seen           TEXT,
    created_at          TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_devices_fp ON devices(device_fingerprint);


-- ─── SETTINGS ───────────────────────────────────────────────────
-- Key-value store for app configuration. Values are JSON strings.
-- Categories: general, theme, sync, ai, device
CREATE TABLE IF NOT EXISTS settings (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    key         TEXT    NOT NULL UNIQUE,
    value       TEXT,                                       -- JSON-encoded value
    category    TEXT    DEFAULT 'general',
    updated_at  TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_settings_cat ON settings(category);


-- ─── ACTIVITY LOG ───────────────────────────────────────────────
-- Immutable audit trail. Every significant action is logged here.
CREATE TABLE IF NOT EXISTS activity_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     INTEGER REFERENCES users(id),
    action      TEXT    NOT NULL,                           -- 'create_part', 'move_stock', etc.
    entity_type TEXT,                                       -- 'part', 'job', 'user', 'movement'
    entity_id   INTEGER,
    details     TEXT,                                       -- JSON with additional context
    ip_address  TEXT,
    timestamp   TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_activity_ts ON activity_log(timestamp);
CREATE INDEX IF NOT EXISTS idx_activity_entity ON activity_log(entity_type, entity_id);


-- ─── NOTIFICATIONS ──────────────────────────────────────────────
-- In-app notifications. NULL user_id = broadcast to all users.
CREATE TABLE IF NOT EXISTS notifications (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     INTEGER REFERENCES users(id),               -- NULL = broadcast
    title       TEXT    NOT NULL,
    body        TEXT,
    severity    TEXT    DEFAULT 'info' CHECK(severity IN ('info','warning','error','critical')),
    source      TEXT    DEFAULT 'system',                   -- 'system', 'ai', 'user'
    link        TEXT,                                       -- Optional: deep link to related page
    is_read     INTEGER DEFAULT 0,
    created_at  TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_notif_user ON notifications(user_id, is_read);


-- =============================================================
-- SEED DATA
-- =============================================================

-- ─── Built-in Hats ──────────────────────────────────────────────
INSERT OR IGNORE INTO hats (name, description, level, is_builtin) VALUES
    ('Admin',       'Full access to everything. System owner.',                                   0, 1),
    ('Manager',     'Manages jobs, people, pricing, and settings. Near-full access.',              1, 1),
    ('Office',      'Office staff. Ordering, scheduling, reports, data entry.',                    2, 1),
    ('Lead',        'Job lead. Elevated permissions scoped to assigned jobs.',                     3, 1),
    ('Worker',      'Standard field worker. Job access, truck, basic parts.',                      4, 1),
    ('Apprentice',  'Learning worker. Restricted access, supervised actions.',                     5, 1),
    ('Grunt',       'Minimal access. View-only on most things, basic clock in/out.',               6, 1);


-- ─── Permission Keys Reference ──────────────────────────────────
-- These are ALL permission keys used throughout the app.
-- Each maps to a specific capability:
--
-- PARTS
--   view_parts_catalog      View the parts catalog table
--   edit_parts_catalog      Create/edit/delete parts
--   edit_pricing            Change cost price and markup
--   show_dollar_values      See dollar columns (cost, sell price)
--   manage_deprecation      Change part deprecation status
--
-- WAREHOUSE
--   view_warehouse          Access warehouse module
--   manage_warehouse        Manage warehouse operations
--   move_stock_warehouse    Initiate moves from warehouse
--
-- TRUCKS
--   view_trucks             Access trucks module
--   manage_trucks           Admin truck fleet
--   move_stock_truck        Initiate moves from truck
--
-- JOBS
--   view_jobs               Access jobs module
--   manage_jobs             Create/edit/close jobs
--   clock_in_out            Clock in/out of jobs
--   consume_parts_any_job   Consume parts on any job (vs. only assigned)
--
-- LABOR
--   view_labor              View labor/timesheet data
--   manage_labor            Edit/void labor entries
--
-- ORDERS
--   view_orders             Access orders module
--   manage_orders           Create/approve POs
--   approve_returns         Approve supplier returns
--
-- PEOPLE
--   view_people             Access people module
--   manage_people           Create/edit users, assign hats
--
-- REPORTS
--   view_reports            Access reports module
--   export_reports          Export data bundles
--
-- SYSTEM
--   manage_settings         Change app settings
--   manage_devices          Manage device assignments
--   manage_templates        Create/edit notebook templates
--   perform_audit           Run inventory audits
--   manager_override        Override enforcement checks with PIN
--   view_activity_log       View the activity log

-- ─── Admin: ALL permissions ─────────────────────────────────────
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT h.id, p.key FROM hats h
CROSS JOIN (
    SELECT 'view_parts_catalog' AS key UNION ALL SELECT 'edit_parts_catalog' UNION ALL
    SELECT 'edit_pricing' UNION ALL SELECT 'show_dollar_values' UNION ALL
    SELECT 'manage_deprecation' UNION ALL SELECT 'view_warehouse' UNION ALL
    SELECT 'manage_warehouse' UNION ALL SELECT 'move_stock_warehouse' UNION ALL
    SELECT 'view_trucks' UNION ALL SELECT 'manage_trucks' UNION ALL
    SELECT 'move_stock_truck' UNION ALL SELECT 'view_jobs' UNION ALL
    SELECT 'manage_jobs' UNION ALL SELECT 'clock_in_out' UNION ALL
    SELECT 'consume_parts_any_job' UNION ALL SELECT 'view_labor' UNION ALL
    SELECT 'manage_labor' UNION ALL SELECT 'view_orders' UNION ALL
    SELECT 'manage_orders' UNION ALL SELECT 'approve_returns' UNION ALL
    SELECT 'view_people' UNION ALL SELECT 'manage_people' UNION ALL
    SELECT 'view_reports' UNION ALL SELECT 'export_reports' UNION ALL
    SELECT 'manage_settings' UNION ALL SELECT 'manage_devices' UNION ALL
    SELECT 'manage_templates' UNION ALL SELECT 'perform_audit' UNION ALL
    SELECT 'manager_override' UNION ALL SELECT 'view_activity_log'
) p WHERE h.name = 'Admin';

-- ─── Manager: Most permissions (no manage_settings, manage_devices) ──
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT h.id, p.key FROM hats h
CROSS JOIN (
    SELECT 'view_parts_catalog' AS key UNION ALL SELECT 'edit_parts_catalog' UNION ALL
    SELECT 'edit_pricing' UNION ALL SELECT 'show_dollar_values' UNION ALL
    SELECT 'manage_deprecation' UNION ALL SELECT 'view_warehouse' UNION ALL
    SELECT 'manage_warehouse' UNION ALL SELECT 'move_stock_warehouse' UNION ALL
    SELECT 'view_trucks' UNION ALL SELECT 'manage_trucks' UNION ALL
    SELECT 'move_stock_truck' UNION ALL SELECT 'view_jobs' UNION ALL
    SELECT 'manage_jobs' UNION ALL SELECT 'clock_in_out' UNION ALL
    SELECT 'consume_parts_any_job' UNION ALL SELECT 'view_labor' UNION ALL
    SELECT 'manage_labor' UNION ALL SELECT 'view_orders' UNION ALL
    SELECT 'manage_orders' UNION ALL SELECT 'approve_returns' UNION ALL
    SELECT 'view_people' UNION ALL SELECT 'manage_people' UNION ALL
    SELECT 'view_reports' UNION ALL SELECT 'export_reports' UNION ALL
    SELECT 'manage_templates' UNION ALL SELECT 'perform_audit' UNION ALL
    SELECT 'manager_override' UNION ALL SELECT 'view_activity_log'
) p WHERE h.name = 'Manager';

-- ─── Office: Ordering, reports, scheduling, data entry ──────────
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT h.id, p.key FROM hats h
CROSS JOIN (
    SELECT 'view_parts_catalog' AS key UNION ALL SELECT 'edit_parts_catalog' UNION ALL
    SELECT 'show_dollar_values' UNION ALL SELECT 'view_warehouse' UNION ALL
    SELECT 'view_trucks' UNION ALL SELECT 'view_jobs' UNION ALL
    SELECT 'manage_jobs' UNION ALL SELECT 'view_labor' UNION ALL
    SELECT 'manage_labor' UNION ALL SELECT 'view_orders' UNION ALL
    SELECT 'manage_orders' UNION ALL SELECT 'view_people' UNION ALL
    SELECT 'view_reports' UNION ALL SELECT 'export_reports'
) p WHERE h.name = 'Office';

-- ─── Lead: Worker + scoped job management ───────────────────────
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT h.id, p.key FROM hats h
CROSS JOIN (
    SELECT 'view_parts_catalog' AS key UNION ALL SELECT 'view_warehouse' UNION ALL
    SELECT 'view_trucks' UNION ALL SELECT 'move_stock_truck' UNION ALL
    SELECT 'view_jobs' UNION ALL SELECT 'manage_jobs' UNION ALL
    SELECT 'clock_in_out' UNION ALL SELECT 'consume_parts_any_job' UNION ALL
    SELECT 'view_labor' UNION ALL SELECT 'view_orders' UNION ALL
    SELECT 'view_reports'
) p WHERE h.name = 'Lead';

-- ─── Worker: Basic field access ─────────────────────────────────
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT h.id, p.key FROM hats h
CROSS JOIN (
    SELECT 'view_parts_catalog' AS key UNION ALL SELECT 'view_warehouse' UNION ALL
    SELECT 'view_trucks' UNION ALL SELECT 'move_stock_truck' UNION ALL
    SELECT 'view_jobs' UNION ALL SELECT 'clock_in_out' UNION ALL
    SELECT 'view_labor' UNION ALL SELECT 'view_orders'
) p WHERE h.name = 'Worker';

-- ─── Apprentice: Restricted field access ────────────────────────
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT h.id, p.key FROM hats h
CROSS JOIN (
    SELECT 'view_parts_catalog' AS key UNION ALL SELECT 'view_trucks' UNION ALL
    SELECT 'view_jobs' UNION ALL SELECT 'clock_in_out' UNION ALL
    SELECT 'view_labor'
) p WHERE h.name = 'Apprentice';

-- ─── Grunt: Minimal access ──────────────────────────────────────
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT h.id, p.key FROM hats h
CROSS JOIN (
    SELECT 'view_parts_catalog' AS key UNION ALL SELECT 'view_trucks' UNION ALL
    SELECT 'view_jobs' UNION ALL SELECT 'clock_in_out'
) p WHERE h.name = 'Grunt';


-- ─── Default Admin User ─────────────────────────────────────────
-- PIN hash is a placeholder — replaced at runtime by the seed script.
-- The actual PIN "1234" is hashed with bcrypt on first startup.
INSERT OR IGNORE INTO users (id, display_name, email, pin_hash)
VALUES (1, 'Admin', 'admin@wiredpart.local', '__PLACEHOLDER_HASH__');

INSERT OR IGNORE INTO user_hats (user_id, hat_id)
SELECT 1, id FROM hats WHERE name = 'Admin';


-- ─── Default Settings ───────────────────────────────────────────
INSERT OR IGNORE INTO settings (key, value, category) VALUES
    ('theme_mode',      '"system"',                     'theme'),
    ('primary_color',   '"#3B82F6"',                    'theme'),
    ('font_family',     '"Inter"',                      'theme'),
    ('company_name',    '"My Electrical Company"',      'general'),
    ('app_version',     '"0.1.0"',                      'general'),
    ('ordering_cost',   '25.0',                         'procurement'),
    ('holding_cost_pct','0.25',                         'procurement'),
    ('safety_stock_days','7',                           'procurement'),
    ('forecast_horizon_days', '30',                     'procurement'),
    ('sync_enabled',    'false',                        'sync'),
    ('ai_enabled',      'false',                        'ai'),
    ('lm_studio_url',   '"http://localhost:1234"',      'ai');
