-- =============================================================
-- MIGRATION 036: Multi-Warehouse + Job Trailers (Phase 16B)
-- =============================================================
-- Adds:
--   1) job_trailers                - Trailer master records
--   2) trailer_location_events     - Current/history location events
--
-- Extends stock polymorphism:
--   location_type now supports 'trailer' in:
--     - stock.location_type
--     - stock_movements.from_location_type / to_location_type
--
-- NOTE: SQLite cannot ALTER CHECK constraints in-place, so stock and
-- stock_movements are rebuilt preserving existing data.
-- =============================================================

PRAGMA foreign_keys = OFF;

-- ─────────────────────────────────────────────────────────────
-- 1) Trailer master + location events
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS job_trailers (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    trailer_code            TEXT NOT NULL UNIQUE,
    name                    TEXT NOT NULL,
    status                  TEXT NOT NULL DEFAULT 'active'
                            CHECK(status IN ('active', 'in_transit', 'maintenance', 'inactive')),
    home_warehouse_id       INTEGER REFERENCES warehouse_locations(id),
    current_job_id          INTEGER REFERENCES jobs(id),
    assigned_driver_user_id INTEGER REFERENCES users(id),
    notes                   TEXT,
    is_active               INTEGER NOT NULL DEFAULT 1,
    created_at              TEXT DEFAULT (datetime('now')),
    updated_at              TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_job_trailers_code ON job_trailers(trailer_code);
CREATE INDEX IF NOT EXISTS idx_job_trailers_status ON job_trailers(status);
CREATE INDEX IF NOT EXISTS idx_job_trailers_home_wh ON job_trailers(home_warehouse_id);
CREATE INDEX IF NOT EXISTS idx_job_trailers_current_job ON job_trailers(current_job_id);
CREATE INDEX IF NOT EXISTS idx_job_trailers_active ON job_trailers(is_active);

CREATE TABLE IF NOT EXISTS trailer_location_events (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    trailer_id      INTEGER NOT NULL REFERENCES job_trailers(id) ON DELETE CASCADE,
    event_type      TEXT NOT NULL DEFAULT 'manual_update'
                    CHECK(event_type IN ('check_in', 'departed', 'arrived_job', 'arrived_warehouse', 'manual_update')),
    location_kind   TEXT NOT NULL DEFAULT 'other'
                    CHECK(location_kind IN ('warehouse', 'job', 'road', 'other')),
    warehouse_id    INTEGER REFERENCES warehouse_locations(id),
    job_id          INTEGER REFERENCES jobs(id),
    lat             REAL,
    lng             REAL,
    recorded_by     INTEGER NOT NULL REFERENCES users(id),
    recorded_at     TEXT DEFAULT (datetime('now')),
    notes           TEXT
);

CREATE INDEX IF NOT EXISTS idx_trailer_loc_events_trailer ON trailer_location_events(trailer_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_trailer_loc_events_kind ON trailer_location_events(location_kind);
CREATE INDEX IF NOT EXISTS idx_trailer_loc_events_wh ON trailer_location_events(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_trailer_loc_events_job ON trailer_location_events(job_id);

-- ─────────────────────────────────────────────────────────────
-- 2) Rebuild stock with expanded location_type CHECK
-- ─────────────────────────────────────────────────────────────
ALTER TABLE stock RENAME TO stock_old_036;

CREATE TABLE stock (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id         INTEGER NOT NULL REFERENCES parts(id) ON DELETE CASCADE,
    location_type   TEXT    NOT NULL CHECK(location_type IN ('warehouse','pulled','truck','trailer','job')),
    location_id     INTEGER NOT NULL DEFAULT 1,
    qty             INTEGER NOT NULL DEFAULT 0 CHECK(qty >= 0),
    supplier_id     INTEGER REFERENCES suppliers(id),
    last_counted    TEXT,
    updated_at      TEXT    DEFAULT (datetime('now')),
    UNIQUE(part_id, location_type, location_id, supplier_id)
);

INSERT INTO stock (
    id, part_id, location_type, location_id, qty, supplier_id, last_counted, updated_at
)
SELECT
    id, part_id, location_type, location_id, qty, supplier_id, last_counted, updated_at
FROM stock_old_036;

DROP TABLE stock_old_036;

CREATE INDEX IF NOT EXISTS idx_stock_part ON stock(part_id);
CREATE INDEX IF NOT EXISTS idx_stock_location ON stock(location_type, location_id);
CREATE INDEX IF NOT EXISTS idx_stock_supplier ON stock(supplier_id);

-- Recreate updated_at trigger lost during table rebuild
DROP TRIGGER IF EXISTS trg_stock_updated_at;
CREATE TRIGGER IF NOT EXISTS trg_stock_updated_at
    AFTER UPDATE ON stock
    FOR EACH ROW
    WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE stock SET updated_at = datetime('now') WHERE id = NEW.id;
END;

-- ─────────────────────────────────────────────────────────────
-- 3) Rebuild stock_movements with expanded location_type CHECK
-- ─────────────────────────────────────────────────────────────
ALTER TABLE stock_movements RENAME TO stock_movements_old_036;

CREATE TABLE stock_movements (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id             INTEGER NOT NULL REFERENCES parts(id),
    qty                 INTEGER NOT NULL CHECK(qty > 0),

    from_location_type  TEXT    CHECK(from_location_type IN ('warehouse','pulled','truck','trailer','job') OR from_location_type IS NULL),
    from_location_id    INTEGER,

    to_location_type    TEXT    CHECK(to_location_type IN ('warehouse','pulled','truck','trailer','job') OR to_location_type IS NULL),
    to_location_id      INTEGER,

    supplier_id         INTEGER REFERENCES suppliers(id),

    movement_type       TEXT    NOT NULL DEFAULT 'transfer'
                                CHECK(movement_type IN (
                                    'receive', 'transfer', 'consume',
                                    'return', 'adjust', 'write_off'
                                )),
    reason              TEXT,
    job_id              INTEGER,

    performed_by        INTEGER NOT NULL REFERENCES users(id),
    verified_by         INTEGER REFERENCES users(id),
    photo_path          TEXT,
    scan_confirmed      INTEGER DEFAULT 0,
    gps_lat             REAL,
    gps_lng             REAL,

    unit_cost_at_move   REAL,
    unit_sell_at_move   REAL,

    created_at          TEXT DEFAULT (datetime('now')),

    -- Added in Migration 006
    reference_number    TEXT,
    notes               TEXT
);

INSERT INTO stock_movements (
    id, part_id, qty,
    from_location_type, from_location_id,
    to_location_type, to_location_id,
    supplier_id,
    movement_type, reason, job_id,
    performed_by, verified_by, photo_path, scan_confirmed,
    gps_lat, gps_lng,
    unit_cost_at_move, unit_sell_at_move,
    created_at,
    reference_number, notes
)
SELECT
    id, part_id, qty,
    from_location_type, from_location_id,
    to_location_type, to_location_id,
    supplier_id,
    movement_type, reason, job_id,
    performed_by, verified_by, photo_path, scan_confirmed,
    gps_lat, gps_lng,
    unit_cost_at_move, unit_sell_at_move,
    created_at,
    reference_number, notes
FROM stock_movements_old_036;

DROP TABLE stock_movements_old_036;

CREATE INDEX IF NOT EXISTS idx_movements_part ON stock_movements(part_id);
CREATE INDEX IF NOT EXISTS idx_movements_type ON stock_movements(movement_type);
CREATE INDEX IF NOT EXISTS idx_movements_from ON stock_movements(from_location_type, from_location_id);
CREATE INDEX IF NOT EXISTS idx_movements_to ON stock_movements(to_location_type, to_location_id);
CREATE INDEX IF NOT EXISTS idx_movements_job ON stock_movements(job_id);
CREATE INDEX IF NOT EXISTS idx_movements_user ON stock_movements(performed_by);
CREATE INDEX IF NOT EXISTS idx_movements_date ON stock_movements(created_at);

PRAGMA foreign_keys = ON;
