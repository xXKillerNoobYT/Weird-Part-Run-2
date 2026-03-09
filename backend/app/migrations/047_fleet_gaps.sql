-- Migration 047: Fleet Feature Gaps
-- Adds: fuel tracking, telematics, inspections, vehicle transfers, utilization support
-- Date: 2026-03-08

-- ═══════════════════════════════════════════════════════════════
-- 1. Fuel Logs — track fuel purchases per vehicle
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS vehicle_fuel_logs (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    vehicle_id      INTEGER NOT NULL REFERENCES vehicles(id),
    driver_id       INTEGER NOT NULL REFERENCES users(id),
    fill_date       TEXT    NOT NULL DEFAULT (date('now')),
    odometer_reading INTEGER NOT NULL,
    gallons         REAL    NOT NULL,
    price_per_gallon REAL   NOT NULL,
    total_cost      REAL    GENERATED ALWAYS AS (gallons * price_per_gallon) STORED,
    fuel_type       TEXT    NOT NULL DEFAULT 'regular' CHECK(fuel_type IN ('regular','midgrade','premium','diesel','e85')),
    station_name    TEXT,
    receipt_photo   TEXT,      -- base64 data URI
    notes           TEXT,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_fuel_logs_vehicle ON vehicle_fuel_logs(vehicle_id, fill_date);
CREATE INDEX IF NOT EXISTS idx_fuel_logs_driver  ON vehicle_fuel_logs(driver_id);

-- updated_at trigger
CREATE TRIGGER IF NOT EXISTS trg_vehicle_fuel_logs_updated_at
    AFTER UPDATE ON vehicle_fuel_logs
    FOR EACH ROW
BEGIN
    UPDATE vehicle_fuel_logs SET updated_at = datetime('now') WHERE id = NEW.id;
END;


-- ═══════════════════════════════════════════════════════════════
-- 2. Telematics Devices — registered GPS/OBD2 hardware
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS telematics_devices (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    vehicle_id      INTEGER NOT NULL REFERENCES vehicles(id),
    device_type     TEXT    NOT NULL DEFAULT 'gps_tracker'
                            CHECK(device_type IN ('obd2','gps_tracker','dash_cam')),
    device_serial   TEXT    NOT NULL UNIQUE,
    device_name     TEXT,
    auth_token      TEXT    NOT NULL UNIQUE,
    is_active       INTEGER NOT NULL DEFAULT 1,
    last_seen_at    TEXT,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_telematics_devices_vehicle ON telematics_devices(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_telematics_devices_token   ON telematics_devices(auth_token);

CREATE TRIGGER IF NOT EXISTS trg_telematics_devices_updated_at
    AFTER UPDATE ON telematics_devices
    FOR EACH ROW
BEGIN
    UPDATE telematics_devices SET updated_at = datetime('now') WHERE id = NEW.id;
END;


-- ═══════════════════════════════════════════════════════════════
-- 3. Telematics Positions — GPS breadcrumbs
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS telematics_positions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id       INTEGER NOT NULL REFERENCES telematics_devices(id),
    vehicle_id      INTEGER NOT NULL REFERENCES vehicles(id),
    lat             REAL    NOT NULL,
    lng             REAL    NOT NULL,
    speed_mph       REAL,
    heading         REAL,
    altitude_ft     REAL,
    odometer_reading INTEGER,
    engine_on       INTEGER DEFAULT 1,
    recorded_at     TEXT    NOT NULL,
    received_at     TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_telem_pos_vehicle_time
    ON telematics_positions(vehicle_id, recorded_at);


-- ═══════════════════════════════════════════════════════════════
-- 4. Telematics Events — alerts and diagnostics
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS telematics_events (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id       INTEGER NOT NULL REFERENCES telematics_devices(id),
    vehicle_id      INTEGER NOT NULL REFERENCES vehicles(id),
    event_type      TEXT    NOT NULL
                            CHECK(event_type IN (
                                'ignition_on','ignition_off',
                                'hard_brake','hard_accel','speeding',
                                'idle','dtc_code',
                                'geofence_enter','geofence_exit'
                            )),
    event_data      TEXT,   -- JSON payload
    lat             REAL,
    lng             REAL,
    recorded_at     TEXT    NOT NULL,
    received_at     TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_telem_events_vehicle_time
    ON telematics_events(vehicle_id, recorded_at);


-- ═══════════════════════════════════════════════════════════════
-- 5. Inspection Templates — admin-defined checklists
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS inspection_templates (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    name            TEXT    NOT NULL,
    description     TEXT,
    vehicle_type    TEXT,   -- NULL = all vehicle types
    inspection_type TEXT    NOT NULL DEFAULT 'pre_trip'
                            CHECK(inspection_type IN ('pre_trip','post_trip','monthly','annual')),
    is_active       INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TRIGGER IF NOT EXISTS trg_inspection_templates_updated_at
    AFTER UPDATE ON inspection_templates
    FOR EACH ROW
BEGIN
    UPDATE inspection_templates SET updated_at = datetime('now') WHERE id = NEW.id;
END;


-- ═══════════════════════════════════════════════════════════════
-- 6. Inspection Template Items — items within a template
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS inspection_template_items (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    template_id     INTEGER NOT NULL REFERENCES inspection_templates(id) ON DELETE CASCADE,
    sort_order      INTEGER NOT NULL DEFAULT 0,
    category        TEXT    NOT NULL DEFAULT 'General',
    item_name       TEXT    NOT NULL,
    description     TEXT,
    severity        TEXT    NOT NULL DEFAULT 'warning'
                            CHECK(severity IN ('info','warning','critical')),
    requires_photo  INTEGER NOT NULL DEFAULT 0,
    is_active       INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_insp_template_items_template
    ON inspection_template_items(template_id, sort_order);


-- ═══════════════════════════════════════════════════════════════
-- 7. Inspection Records — completed inspections
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS inspection_records (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    vehicle_id      INTEGER NOT NULL REFERENCES vehicles(id),
    template_id     INTEGER NOT NULL REFERENCES inspection_templates(id),
    inspector_id    INTEGER NOT NULL REFERENCES users(id),
    inspection_type TEXT    NOT NULL,
    inspection_date TEXT    NOT NULL DEFAULT (date('now')),
    odometer_reading INTEGER,
    overall_result  TEXT    DEFAULT 'pending'
                            CHECK(overall_result IN ('pending','pass','fail','needs_attention')),
    notes           TEXT,
    completed_at    TEXT,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_insp_records_vehicle
    ON inspection_records(vehicle_id, inspection_date);

CREATE TRIGGER IF NOT EXISTS trg_inspection_records_updated_at
    AFTER UPDATE ON inspection_records
    FOR EACH ROW
BEGIN
    UPDATE inspection_records SET updated_at = datetime('now') WHERE id = NEW.id;
END;


-- ═══════════════════════════════════════════════════════════════
-- 8. Inspection Record Items — individual check results
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS inspection_record_items (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    record_id       INTEGER NOT NULL REFERENCES inspection_records(id) ON DELETE CASCADE,
    template_item_id INTEGER REFERENCES inspection_template_items(id),
    item_name       TEXT    NOT NULL,
    category        TEXT    NOT NULL DEFAULT 'General',
    status          TEXT    NOT NULL DEFAULT 'pending'
                            CHECK(status IN ('pending','pass','fail','na')),
    severity        TEXT    NOT NULL DEFAULT 'warning'
                            CHECK(severity IN ('info','warning','critical')),
    photo           TEXT,   -- base64 data URI
    notes           TEXT,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_insp_record_items_record
    ON inspection_record_items(record_id);


-- ═══════════════════════════════════════════════════════════════
-- 9. Vehicle Transfers — inter-location transfer workflow
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS vehicle_transfers (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    vehicle_id              INTEGER NOT NULL REFERENCES vehicles(id),
    from_location_id        INTEGER NOT NULL REFERENCES warehouse_locations(id),
    to_location_id          INTEGER NOT NULL REFERENCES warehouse_locations(id),
    requested_by            INTEGER NOT NULL REFERENCES users(id),
    approved_by             INTEGER REFERENCES users(id),
    status                  TEXT    NOT NULL DEFAULT 'requested'
                                    CHECK(status IN ('requested','approved','in_transit','completed','cancelled')),
    transfer_date           TEXT,
    estimated_arrival       TEXT,
    actual_arrival          TEXT,
    require_post_inspection INTEGER NOT NULL DEFAULT 1,
    post_inspection_id      INTEGER REFERENCES inspection_records(id),
    notes                   TEXT,
    created_at              TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at              TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_transfers_vehicle ON vehicle_transfers(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_transfers_status  ON vehicle_transfers(status);

CREATE TRIGGER IF NOT EXISTS trg_vehicle_transfers_updated_at
    AFTER UPDATE ON vehicle_transfers
    FOR EACH ROW
BEGIN
    UPDATE vehicle_transfers SET updated_at = datetime('now') WHERE id = NEW.id;
END;
