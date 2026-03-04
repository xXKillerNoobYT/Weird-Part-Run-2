-- ═══════════════════════════════════════════════════════════════════════
-- Migration 017: Fleet & Vehicle Management
-- Phase 6 — Vehicles, assignments, inventory, delivery items,
--           maintenance scheduling & records, mileage tracking with
--           drive-time support, warehouse locations, and reimbursements.
-- ═══════════════════════════════════════════════════════════════════════


-- ═══ 1. VEHICLES ════════════════════════════════════════════════════════
-- Core vehicle entity. Supports company trucks, vans, cars, and
-- private vehicles (employee-owned, tracked for mileage reimbursement).

CREATE TABLE IF NOT EXISTS vehicles (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    vehicle_number      TEXT NOT NULL UNIQUE,          -- e.g. "T-001", "PV-SMITH"
    vehicle_name        TEXT NOT NULL,                 -- "Truck 1", "John's F-150"
    vehicle_type        TEXT NOT NULL DEFAULT 'company_truck'
        CHECK (vehicle_type IN (
            'company_truck', 'company_van', 'company_car', 'private_vehicle'
        )),
    status              TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'inactive', 'maintenance', 'retired')),

    -- Vehicle details
    make                TEXT,                          -- "Ford"
    model               TEXT,                          -- "F-250"
    year                INTEGER,                       -- 2022
    color               TEXT,
    vin                 TEXT,
    license_plate       TEXT,

    -- Insurance & registration
    insurance_policy    TEXT,
    insurance_expiry    TEXT,                          -- ISO date
    registration_expiry TEXT,                          -- ISO date

    -- Current odometer
    current_odometer    INTEGER DEFAULT 0,

    -- For private vehicles only: the employee who owns it
    owner_user_id       INTEGER REFERENCES users(id),

    -- Metadata
    notes               TEXT,
    photo_path          TEXT,
    is_active           INTEGER NOT NULL DEFAULT 1,
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_vehicles_type ON vehicles(vehicle_type);
CREATE INDEX IF NOT EXISTS idx_vehicles_status ON vehicles(status);
CREATE INDEX IF NOT EXISTS idx_vehicles_owner ON vehicles(owner_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicles_active ON vehicles(is_active);


-- ═══ 2. VEHICLE ASSIGNMENTS ═════════════════════════════════════════════
-- Who is currently assigned to drive a vehicle. Supports primary driver,
-- authorized alternate drivers, and temporary assignments.
-- A vehicle can have one primary driver; multiple users can be authorized.
-- Includes take-home flag and driver's home-to-shop distance for mileage
-- estimation (one-time manual entry per assignment).

CREATE TABLE IF NOT EXISTS vehicle_assignments (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    vehicle_id          INTEGER NOT NULL REFERENCES vehicles(id),
    user_id             INTEGER NOT NULL REFERENCES users(id),
    assignment_type     TEXT NOT NULL DEFAULT 'primary'
        CHECK (assignment_type IN ('primary', 'authorized', 'temporary')),
    is_take_home        INTEGER NOT NULL DEFAULT 0,   -- 1 = employee drives vehicle home
    home_to_shop_miles  REAL,                         -- manual entry: commute miles (one-time)

    -- Optional reference address for the driver's home
    home_address_street TEXT,
    home_address_city   TEXT,
    home_address_state  TEXT,
    home_address_zip    TEXT,

    start_date          TEXT NOT NULL DEFAULT (date('now')),
    end_date            TEXT,                          -- NULL = currently assigned
    notes               TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(vehicle_id, user_id, assignment_type)
);

CREATE INDEX IF NOT EXISTS idx_vassign_vehicle ON vehicle_assignments(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vassign_user ON vehicle_assignments(user_id);
CREATE INDEX IF NOT EXISTS idx_vassign_active ON vehicle_assignments(end_date);


-- ═══ 3. WAREHOUSE LOCATIONS ═════════════════════════════════════════════
-- Physical shop/warehouse addresses. The primary location is the default
-- "shop" for mileage estimation (home → shop → job → home). Actual
-- mileage uses manually-entered distances on jobs and assignments, not
-- GPS math — the address is for display/reference.

CREATE TABLE IF NOT EXISTS warehouse_locations (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    name                TEXT NOT NULL,                 -- "Main Shop", "South Warehouse"
    address_street      TEXT,
    address_city        TEXT,
    address_state       TEXT,
    address_zip         TEXT,
    gps_lat             REAL,                         -- optional, for map display
    gps_lng             REAL,
    is_primary          INTEGER NOT NULL DEFAULT 0,   -- main shop for mileage default
    is_active           INTEGER NOT NULL DEFAULT 1,
    company_profile_id  INTEGER REFERENCES company_profiles(id),
    phone               TEXT,
    notes               TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT NOT NULL DEFAULT (datetime('now'))
);


-- ═══ 4. VEHICLE DELIVERY ITEMS ══════════════════════════════════════════
-- Items assigned for delivery on a vehicle, linked to a specific job.
-- DISTINCT from vehicle inventory (general stock at location_type='truck').
-- Delivery items are job-bound: once delivered they move to job stock.

CREATE TABLE IF NOT EXISTS vehicle_delivery_items (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    vehicle_id          INTEGER NOT NULL REFERENCES vehicles(id),
    job_id              INTEGER NOT NULL REFERENCES jobs(id),
    part_id             INTEGER NOT NULL REFERENCES parts(id),
    qty_assigned        INTEGER NOT NULL DEFAULT 1,
    qty_delivered       INTEGER NOT NULL DEFAULT 0,
    assigned_by         INTEGER REFERENCES users(id),
    delivered_by        INTEGER REFERENCES users(id),
    delivered_at        TEXT,
    status              TEXT NOT NULL DEFAULT 'assigned'
        CHECK (status IN ('assigned', 'loaded', 'in_transit', 'delivered', 'returned')),
    notes               TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_vdelivery_vehicle ON vehicle_delivery_items(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vdelivery_job ON vehicle_delivery_items(job_id);
CREATE INDEX IF NOT EXISTS idx_vdelivery_status ON vehicle_delivery_items(status);
CREATE INDEX IF NOT EXISTS idx_vdelivery_part ON vehicle_delivery_items(part_id);


-- ═══ 5. MAINTENANCE TYPES (configurable lookup) ════════════════════════
-- Admin-managed list of service categories. Seeded with common defaults.

CREATE TABLE IF NOT EXISTS maintenance_types (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    name                TEXT NOT NULL UNIQUE,           -- "Oil Change", "Tire Rotation"
    description         TEXT,
    default_interval_miles    INTEGER,                  -- e.g. 5000
    default_interval_months   INTEGER,                  -- e.g. 6
    sort_order          INTEGER DEFAULT 0,
    is_active           INTEGER NOT NULL DEFAULT 1,
    created_at          TEXT NOT NULL DEFAULT (datetime('now'))
);


-- ═══ 6. VEHICLE MAINTENANCE SCHEDULES ═══════════════════════════════════
-- Per-vehicle customization of maintenance intervals. Overrides defaults
-- from maintenance_types for a specific vehicle.

CREATE TABLE IF NOT EXISTS vehicle_maintenance_schedules (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    vehicle_id          INTEGER NOT NULL REFERENCES vehicles(id),
    maintenance_type_id INTEGER NOT NULL REFERENCES maintenance_types(id),
    interval_miles      INTEGER,                       -- override default
    interval_months     INTEGER,                       -- override default
    last_performed_at   TEXT,                          -- ISO date of last service
    last_performed_miles INTEGER,                      -- odometer at last service
    next_due_date       TEXT,                          -- calculated: last + interval months
    next_due_miles      INTEGER,                       -- calculated: last + interval miles
    is_enabled          INTEGER NOT NULL DEFAULT 1,
    notes               TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(vehicle_id, maintenance_type_id)
);

CREATE INDEX IF NOT EXISTS idx_vmsched_vehicle ON vehicle_maintenance_schedules(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vmsched_next_due ON vehicle_maintenance_schedules(next_due_date);
CREATE INDEX IF NOT EXISTS idx_vmsched_next_miles ON vehicle_maintenance_schedules(next_due_miles);


-- ═══ 7. VEHICLE MAINTENANCE RECORDS ═════════════════════════════════════
-- Actual service history entries. Each record captures what was done,
-- when, at what odometer reading, how much it cost, and who logged it.

CREATE TABLE IF NOT EXISTS vehicle_maintenance_records (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    vehicle_id          INTEGER NOT NULL REFERENCES vehicles(id),
    maintenance_type_id INTEGER NOT NULL REFERENCES maintenance_types(id),
    service_date        TEXT NOT NULL DEFAULT (date('now')),
    odometer_reading    INTEGER,
    cost                REAL DEFAULT 0,
    vendor              TEXT,                          -- shop/mechanic name
    invoice_number      TEXT,
    description         TEXT,
    performed_by        INTEGER REFERENCES users(id),  -- who logged it
    photo_path          TEXT,                          -- receipt photo
    notes               TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_vmaint_vehicle ON vehicle_maintenance_records(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vmaint_type ON vehicle_maintenance_records(maintenance_type_id);
CREATE INDEX IF NOT EXISTS idx_vmaint_date ON vehicle_maintenance_records(service_date);


-- ═══ 8. VEHICLE MILEAGE LOGS ════════════════════════════════════════════
-- Daily odometer readings per vehicle, one entry per vehicle per day.
-- total_miles is auto-calculated via SQLite generated column.

CREATE TABLE IF NOT EXISTS vehicle_mileage_logs (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    vehicle_id          INTEGER NOT NULL REFERENCES vehicles(id),
    driver_id           INTEGER NOT NULL REFERENCES users(id),
    log_date            TEXT NOT NULL DEFAULT (date('now')),
    odometer_start      INTEGER,
    odometer_end        INTEGER,
    total_miles         INTEGER GENERATED ALWAYS AS (odometer_end - odometer_start) STORED,
    is_take_home_day    INTEGER DEFAULT 0,             -- drove vehicle home this day
    notes               TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(vehicle_id, log_date)
);

CREATE INDEX IF NOT EXISTS idx_vmileage_vehicle ON vehicle_mileage_logs(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vmileage_driver ON vehicle_mileage_logs(driver_id);
CREATE INDEX IF NOT EXISTS idx_vmileage_date ON vehicle_mileage_logs(log_date);


-- ═══ 9. VEHICLE TRIP LEGS ═══════════════════════════════════════════════
-- Individual trip segments for a day. Tracks both distance and drive time.
-- Drive time is important for payroll (one-way drive = billable).
-- Uses manually-entered estimated values from job/assignment data,
-- plus optional actual overrides when drivers report real numbers.

CREATE TABLE IF NOT EXISTS vehicle_trip_legs (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    mileage_log_id      INTEGER NOT NULL REFERENCES vehicle_mileage_logs(id) ON DELETE CASCADE,
    leg_order           INTEGER NOT NULL DEFAULT 1,
    leg_type            TEXT NOT NULL
        CHECK (leg_type IN (
            'home_to_shop', 'shop_to_job', 'job_to_job',
            'job_to_shop', 'shop_to_home', 'job_to_home', 'other'
        )),
    from_label          TEXT,                          -- "Home", "Main Shop", "Job #1234"
    to_label            TEXT,

    -- Distance
    estimated_miles     REAL,                          -- from job/assignment stored values
    actual_miles        REAL,                          -- manual override if different

    -- Drive time (minutes)
    estimated_drive_minutes INTEGER,                   -- from job stored value
    actual_drive_minutes    INTEGER,                   -- actual reported drive time

    -- Payroll relevance
    is_billable         INTEGER NOT NULL DEFAULT 0,    -- shop→job, job→job = 1; commute = 0

    -- Job references (for job-related legs)
    from_job_id         INTEGER REFERENCES jobs(id),   -- leaving from this job
    to_job_id           INTEGER REFERENCES jobs(id),   -- going to this job

    notes               TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_vtrip_log ON vehicle_trip_legs(mileage_log_id);
CREATE INDEX IF NOT EXISTS idx_vtrip_from_job ON vehicle_trip_legs(from_job_id);
CREATE INDEX IF NOT EXISTS idx_vtrip_to_job ON vehicle_trip_legs(to_job_id);


-- ═══ 10. MILEAGE REIMBURSEMENTS ════════════════════════════════════════
-- For private vehicle users. Tracks reimbursement per period.
-- total_amount auto-calculated via generated column.

CREATE TABLE IF NOT EXISTS mileage_reimbursements (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id             INTEGER NOT NULL REFERENCES users(id),
    vehicle_id          INTEGER NOT NULL REFERENCES vehicles(id),
    period_start        TEXT NOT NULL,                 -- ISO date
    period_end          TEXT NOT NULL,                 -- ISO date
    total_miles         INTEGER NOT NULL DEFAULT 0,
    rate_per_mile       REAL NOT NULL DEFAULT 0.70,    -- IRS standard mileage rate 2025
    total_amount        REAL GENERATED ALWAYS AS (total_miles * rate_per_mile) STORED,
    status              TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'paid', 'rejected')),
    approved_by         INTEGER REFERENCES users(id),
    approved_at         TEXT,
    notes               TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_reimb_user ON mileage_reimbursements(user_id);
CREATE INDEX IF NOT EXISTS idx_reimb_vehicle ON mileage_reimbursements(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_reimb_status ON mileage_reimbursements(status);
CREATE INDEX IF NOT EXISTS idx_reimb_period ON mileage_reimbursements(period_start, period_end);


-- ═══════════════════════════════════════════════════════════════════════
-- UPDATED_AT TRIGGERS
-- Following migration 015 pattern (no WHEN guard — simpler, always fires)
-- ═══════════════════════════════════════════════════════════════════════

CREATE TRIGGER IF NOT EXISTS trg_vehicles_updated_at
AFTER UPDATE ON vehicles
FOR EACH ROW
BEGIN
    UPDATE vehicles SET updated_at = datetime('now') WHERE id = OLD.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_vehicle_assignments_updated_at
AFTER UPDATE ON vehicle_assignments
FOR EACH ROW
BEGIN
    UPDATE vehicle_assignments SET updated_at = datetime('now') WHERE id = OLD.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_warehouse_locations_updated_at
AFTER UPDATE ON warehouse_locations
FOR EACH ROW
BEGIN
    UPDATE warehouse_locations SET updated_at = datetime('now') WHERE id = OLD.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_vehicle_delivery_items_updated_at
AFTER UPDATE ON vehicle_delivery_items
FOR EACH ROW
BEGIN
    UPDATE vehicle_delivery_items SET updated_at = datetime('now') WHERE id = OLD.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_vehicle_maint_schedules_updated_at
AFTER UPDATE ON vehicle_maintenance_schedules
FOR EACH ROW
BEGIN
    UPDATE vehicle_maintenance_schedules SET updated_at = datetime('now') WHERE id = OLD.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_vehicle_mileage_logs_updated_at
AFTER UPDATE ON vehicle_mileage_logs
FOR EACH ROW
BEGIN
    UPDATE vehicle_mileage_logs SET updated_at = datetime('now') WHERE id = OLD.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_mileage_reimb_updated_at
AFTER UPDATE ON mileage_reimbursements
FOR EACH ROW
BEGIN
    UPDATE mileage_reimbursements SET updated_at = datetime('now') WHERE id = OLD.id;
END;


-- ═══════════════════════════════════════════════════════════════════════
-- ALTER EXISTING TABLES
-- ═══════════════════════════════════════════════════════════════════════

-- Jobs: add distance and drive time from shop (manual one-time entry)
ALTER TABLE jobs ADD COLUMN distance_from_shop_miles REAL;
ALTER TABLE jobs ADD COLUMN estimated_drive_minutes_from_shop INTEGER;


-- ═══════════════════════════════════════════════════════════════════════
-- SEED: MAINTENANCE TYPES
-- Common service categories with default intervals
-- ═══════════════════════════════════════════════════════════════════════

INSERT OR IGNORE INTO maintenance_types (name, description, default_interval_miles, default_interval_months, sort_order) VALUES
    ('Oil Change',          'Engine oil and filter change',           5000,   6,  1),
    ('Tire Rotation',       'Rotate and balance tires',              7500,   6,  2),
    ('Brake Inspection',    'Check pads, rotors, fluid',            15000,  12,  3),
    ('Transmission Service','Transmission fluid change/flush',      30000,  24,  4),
    ('Coolant Flush',       'Engine coolant replacement',           30000,  24,  5),
    ('Air Filter',          'Engine air filter replacement',        15000,  12,  6),
    ('Cabin Air Filter',    'Cabin air filter replacement',         15000,  12,  7),
    ('Spark Plugs',         'Spark plug replacement',               60000,  48,  8),
    ('Battery Check',       'Test battery and terminals',            NULL,  12,  9),
    ('Wiper Blades',        'Windshield wiper replacement',          NULL,  12, 10),
    ('State Inspection',    'Annual state safety inspection',        NULL,  12, 11),
    ('DEF Fluid',           'Diesel exhaust fluid refill',           5000,   3, 12),
    ('General Service',     'Miscellaneous service or repair',       NULL, NULL, 99);


-- ═══════════════════════════════════════════════════════════════════════
-- SEED: FLEET SETTINGS
-- ═══════════════════════════════════════════════════════════════════════

INSERT OR IGNORE INTO settings (key, value, category) VALUES
    ('mileage_reimbursement_rate',      '0.70',   'fleet'),
    ('default_warehouse_location_id',   '1',      'fleet'),
    ('maintenance_alert_days_ahead',    '14',     'fleet'),
    ('maintenance_alert_miles_ahead',   '500',    'fleet');


-- ═══════════════════════════════════════════════════════════════════════
-- SEED: DEFAULT WAREHOUSE LOCATION
-- ═══════════════════════════════════════════════════════════════════════

INSERT OR IGNORE INTO warehouse_locations (id, name, is_primary, notes)
VALUES (1, 'Main Shop', 1, 'Primary shop location — update address in Office settings');


-- ═══════════════════════════════════════════════════════════════════════
-- PERMISSIONS
-- ═══════════════════════════════════════════════════════════════════════

-- manage_fleet: Create/edit vehicles, assign drivers, manage maintenance types
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'manage_fleet' FROM hats WHERE name IN ('Admin', 'Manager');

-- log_mileage: Daily mileage logging (all field workers)
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'log_mileage' FROM hats WHERE name IN ('Admin', 'Manager', 'Lead', 'Worker');

-- approve_reimbursement: Approve private vehicle mileage reimbursements
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'approve_reimbursement' FROM hats WHERE name IN ('Admin', 'Manager');
