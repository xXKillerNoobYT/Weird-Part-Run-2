/**
 * Migration 006: Fleet, Tools & Scheduling
 *
 * Vehicles, assignments, tools, kit verification, maintenance,
 * employee schedules, dispatch, time-off, subcontractor schedules.
 * Consolidated from: backend migrations 017, 023, 024, 025, 026, 027
 */

export const migration = {
  name: '006_fleet_tools_scheduling',
  sql: `
-- ═══ FLEET ═══════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS vehicles (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    vehicle_number      TEXT    NOT NULL UNIQUE,
    vehicle_name        TEXT    NOT NULL,
    vehicle_type        TEXT    NOT NULL DEFAULT 'company_truck'
        CHECK (vehicle_type IN ('company_truck','company_van','company_car','private_vehicle')),
    status              TEXT    NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','inactive','maintenance','retired')),
    make                TEXT,
    model               TEXT,
    year                INTEGER,
    color               TEXT,
    vin                 TEXT,
    license_plate       TEXT,
    insurance_policy    TEXT,
    insurance_expiry    TEXT,
    registration_expiry TEXT,
    current_odometer    INTEGER DEFAULT 0,
    owner_user_id       INTEGER REFERENCES users(id),
    notes               TEXT,
    photo_path          TEXT,
    is_active           INTEGER NOT NULL DEFAULT 1,
    created_at          TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_vehicles_active ON vehicles(is_active);

CREATE TABLE IF NOT EXISTS vehicle_assignments (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    vehicle_id          INTEGER NOT NULL REFERENCES vehicles(id),
    user_id             INTEGER NOT NULL REFERENCES users(id),
    assignment_type     TEXT    NOT NULL DEFAULT 'primary'
        CHECK (assignment_type IN ('primary','authorized','temporary')),
    is_take_home        INTEGER NOT NULL DEFAULT 0,
    home_to_shop_miles  REAL,
    start_date          TEXT    NOT NULL DEFAULT (date('now')),
    end_date            TEXT,
    is_active           INTEGER NOT NULL DEFAULT 1,
    notes               TEXT,
    created_at          TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_va_vehicle ON vehicle_assignments(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_va_user ON vehicle_assignments(user_id);

-- ═══ TOOLS ══════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS tools (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_number         TEXT    NOT NULL UNIQUE,
    name                TEXT    NOT NULL,
    category            TEXT    NOT NULL DEFAULT 'general'
        CHECK (category IN (
            'power_tool','hand_tool','meter','safety',
            'conduit','cable','lighting','general'
        )),
    brand               TEXT,
    model_number        TEXT,
    serial_number       TEXT,
    purchase_date       TEXT,
    purchase_cost       REAL,
    warranty_expiry     TEXT,
    location_type       TEXT    NOT NULL DEFAULT 'warehouse'
        CHECK (location_type IN ('warehouse','truck','job')),
    location_id         INTEGER,
    assigned_to         INTEGER REFERENCES users(id),
    status              TEXT    NOT NULL DEFAULT 'available'
        CHECK (status IN (
            'available','checked_out','in_maintenance',
            'lost','retired','damaged'
        )),
    condition_rating    INTEGER DEFAULT 5
        CHECK (condition_rating BETWEEN 1 AND 5),
    has_kit             INTEGER NOT NULL DEFAULT 0,
    notes               TEXT,
    photo_path          TEXT,
    barcode             TEXT,
    is_active           INTEGER NOT NULL DEFAULT 1,
    created_at          TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_tools_number ON tools(tool_number);
CREATE INDEX IF NOT EXISTS idx_tools_location ON tools(location_type, location_id);
CREATE INDEX IF NOT EXISTS idx_tools_assigned ON tools(assigned_to);
CREATE INDEX IF NOT EXISTS idx_tools_status ON tools(status);
CREATE INDEX IF NOT EXISTS idx_tools_barcode ON tools(barcode);

CREATE TABLE IF NOT EXISTS kit_templates (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id         INTEGER NOT NULL REFERENCES tools(id) ON DELETE CASCADE,
    component_name  TEXT    NOT NULL,
    component_type  TEXT    NOT NULL DEFAULT 'accessory'
        CHECK (component_type IN (
            'charger','battery','blade','bit_set',
            'case','accessory','cable','adapter','other'
        )),
    qty_required    INTEGER NOT NULL DEFAULT 1 CHECK (qty_required >= 1),
    brand           TEXT,
    model_number    TEXT,
    is_critical     INTEGER NOT NULL DEFAULT 0,
    sort_order      INTEGER DEFAULT 0,
    notes           TEXT
);
CREATE INDEX IF NOT EXISTS idx_kit_templates_tool ON kit_templates(tool_id);

CREATE TABLE IF NOT EXISTS tool_movements (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id             INTEGER NOT NULL REFERENCES tools(id),
    from_location_type  TEXT,
    from_location_id    INTEGER,
    to_location_type    TEXT,
    to_location_id      INTEGER,
    movement_type       TEXT    NOT NULL
        CHECK (movement_type IN (
            'register','checkout','return','transfer',
            'maintenance_in','maintenance_out','retire','lost'
        )),
    reason              TEXT,
    job_id              INTEGER REFERENCES jobs(id),
    performed_by        INTEGER NOT NULL REFERENCES users(id),
    verified_by         INTEGER REFERENCES users(id),
    condition_at_move   INTEGER CHECK (condition_at_move BETWEEN 1 AND 5),
    created_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_tool_moves_tool ON tool_movements(tool_id);

CREATE TABLE IF NOT EXISTS kit_verification_sessions (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id       INTEGER NOT NULL REFERENCES tools(id),
    movement_id   INTEGER REFERENCES tool_movements(id),
    verified_by   INTEGER NOT NULL REFERENCES users(id),
    trigger_type  TEXT    NOT NULL
        CHECK (trigger_type IN ('checkout','return','audit','manual')),
    is_complete   INTEGER NOT NULL DEFAULT 0,
    missing_count INTEGER NOT NULL DEFAULT 0,
    notes         TEXT,
    created_at    TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS kit_verification_items (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id        INTEGER NOT NULL REFERENCES kit_verification_sessions(id) ON DELETE CASCADE,
    template_item_id  INTEGER NOT NULL REFERENCES kit_templates(id),
    is_present        INTEGER NOT NULL DEFAULT 1,
    condition_rating  INTEGER CHECK (condition_rating BETWEEN 1 AND 5),
    notes             TEXT
);

CREATE TABLE IF NOT EXISTS tool_maintenance_types (
    id                     INTEGER PRIMARY KEY AUTOINCREMENT,
    name                   TEXT    NOT NULL UNIQUE,
    description            TEXT,
    default_interval_days  INTEGER,
    sort_order             INTEGER DEFAULT 0,
    is_active              INTEGER NOT NULL DEFAULT 1,
    created_at             TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS tool_maintenance_schedules (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id             INTEGER NOT NULL REFERENCES tools(id) ON DELETE CASCADE,
    maintenance_type_id INTEGER NOT NULL REFERENCES tool_maintenance_types(id),
    interval_days       INTEGER,
    last_performed_at   TEXT,
    next_due_date       TEXT,
    is_enabled          INTEGER NOT NULL DEFAULT 1,
    notes               TEXT,
    created_at          TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE(tool_id, maintenance_type_id)
);

CREATE TABLE IF NOT EXISTS tool_maintenance_records (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id             INTEGER NOT NULL REFERENCES tools(id),
    maintenance_type_id INTEGER NOT NULL REFERENCES tool_maintenance_types(id),
    service_date        TEXT    NOT NULL,
    cost                REAL,
    vendor              TEXT,
    description         TEXT,
    performed_by        INTEGER REFERENCES users(id),
    notes               TEXT,
    created_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- ═══ PEOPLE / CONTACTS ══════════════════════════════════════

CREATE TABLE IF NOT EXISTS customers (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    name         TEXT    NOT NULL,
    company_name TEXT,
    email        TEXT,
    phone        TEXT,
    address      TEXT,
    city         TEXT,
    state        TEXT,
    zip          TEXT,
    notes        TEXT,
    is_active    INTEGER DEFAULT 1,
    created_at   TEXT    DEFAULT (datetime('now')),
    updated_at   TEXT    DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS general_contractors (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    company_name  TEXT    NOT NULL,
    contact_name  TEXT,
    email         TEXT,
    phone         TEXT,
    address       TEXT,
    city          TEXT,
    state         TEXT,
    zip           TEXT,
    relationship  TEXT    DEFAULT 'we_work_for_them'
        CHECK (relationship IN ('we_work_for_them','we_hired_them','both')),
    notes         TEXT,
    is_active     INTEGER DEFAULT 1,
    created_at    TEXT    DEFAULT (datetime('now')),
    updated_at    TEXT    DEFAULT (datetime('now'))
);

-- ═══ SCHEDULING ═════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS employee_default_schedules (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    day_of_week     INTEGER NOT NULL CHECK(day_of_week BETWEEN 0 AND 6),
    start_time      TEXT    DEFAULT '07:00',
    end_time        TEXT    DEFAULT '15:30',
    is_working_day  INTEGER DEFAULT 1,
    notes           TEXT,
    UNIQUE(user_id, day_of_week)
);
CREATE INDEX IF NOT EXISTS idx_default_sched_user ON employee_default_schedules(user_id);

CREATE TABLE IF NOT EXISTS schedule_exceptions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    exception_date  TEXT    NOT NULL,
    exception_type  TEXT    NOT NULL
        CHECK(exception_type IN (
            'time_off','sick','vacation','holiday',
            'modified_hours','unpaid_leave','jury_duty','bereavement'
        )),
    start_time      TEXT,
    end_time        TEXT,
    is_approved     INTEGER DEFAULT 0,
    approved_by     INTEGER REFERENCES users(id),
    approved_at     TEXT,
    reason          TEXT,
    notes           TEXT,
    created_at      TEXT    DEFAULT (datetime('now')),
    UNIQUE(user_id, exception_date)
);
CREATE INDEX IF NOT EXISTS idx_sched_exc_user ON schedule_exceptions(user_id, exception_date);

CREATE TABLE IF NOT EXISTS job_dispatch (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id          INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    dispatch_date   TEXT    NOT NULL,
    shift_start     TEXT,
    shift_end       TEXT,
    role_on_job     TEXT    DEFAULT 'worker'
        CHECK(role_on_job IN ('lead','worker','apprentice','helper')),
    status          TEXT    DEFAULT 'scheduled'
        CHECK(status IN (
            'scheduled','confirmed','on_site',
            'completed','no_show','cancelled'
        )),
    dispatched_by   INTEGER REFERENCES users(id),
    notes           TEXT,
    created_at      TEXT    DEFAULT (datetime('now')),
    updated_at      TEXT    DEFAULT (datetime('now')),
    UNIQUE(user_id, dispatch_date, job_id)
);
CREATE INDEX IF NOT EXISTS idx_dispatch_date ON job_dispatch(dispatch_date);
CREATE INDEX IF NOT EXISTS idx_dispatch_user ON job_dispatch(user_id, dispatch_date);
CREATE INDEX IF NOT EXISTS idx_dispatch_job ON job_dispatch(job_id, dispatch_date);

CREATE TABLE IF NOT EXISTS subcontractor_schedules (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id          INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    gc_id           INTEGER NOT NULL REFERENCES general_contractors(id) ON DELETE CASCADE,
    scheduled_date  TEXT    NOT NULL,
    arrival_time    TEXT,
    departure_time  TEXT,
    scope_of_work   TEXT,
    status          TEXT    DEFAULT 'scheduled'
        CHECK(status IN ('scheduled','confirmed','completed','cancelled','no_show')),
    notes           TEXT,
    created_by      INTEGER REFERENCES users(id),
    created_at      TEXT    DEFAULT (datetime('now')),
    updated_at      TEXT    DEFAULT (datetime('now')),
    UNIQUE(job_id, gc_id, scheduled_date)
);
  `,
};
