/**
 * Migration 012: Warehouse Extras & Order Attachments
 *
 * Adds:
 * - job_trailers — trailer master records
 * - trailer_location_events — trailer location history
 * - order_attachments — polymorphic attachments for JPOs, POs, Returns
 *
 * Source: backend migrations 036, 033
 */

export const migration = {
  name: '012_warehouse_attachments',
  sql: `
-- ═══════════════════════════════════════════════════════════════════
-- JOB TRAILERS — trailer master records
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS job_trailers (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    trailer_code            TEXT NOT NULL UNIQUE,
    name                    TEXT NOT NULL,
    status                  TEXT NOT NULL DEFAULT 'active'
                            CHECK(status IN ('active', 'in_transit', 'maintenance', 'inactive')),
    current_job_id          INTEGER REFERENCES jobs(id),
    assigned_driver_user_id INTEGER REFERENCES users(id),
    notes                   TEXT,
    is_active               INTEGER NOT NULL DEFAULT 1,
    deleted_at              TEXT,
    created_at              TEXT DEFAULT (datetime('now')),
    updated_at              TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_job_trailers_code ON job_trailers(trailer_code);
CREATE INDEX IF NOT EXISTS idx_job_trailers_status ON job_trailers(status);
CREATE INDEX IF NOT EXISTS idx_job_trailers_current_job ON job_trailers(current_job_id);
CREATE INDEX IF NOT EXISTS idx_job_trailers_active ON job_trailers(is_active);


-- ═══════════════════════════════════════════════════════════════════
-- TRAILER LOCATION EVENTS — current + history location tracking
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS trailer_location_events (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    trailer_id    INTEGER NOT NULL REFERENCES job_trailers(id) ON DELETE CASCADE,
    event_type    TEXT NOT NULL DEFAULT 'manual_update'
                  CHECK(event_type IN ('check_in', 'departed', 'arrived_job', 'arrived_warehouse', 'manual_update')),
    location_kind TEXT NOT NULL DEFAULT 'other'
                  CHECK(location_kind IN ('warehouse', 'job', 'road', 'other')),
    job_id        INTEGER REFERENCES jobs(id),
    lat           REAL,
    lng           REAL,
    recorded_by   INTEGER NOT NULL REFERENCES users(id),
    recorded_at   TEXT DEFAULT (datetime('now')),
    notes         TEXT
);

CREATE INDEX IF NOT EXISTS idx_trailer_loc_events_trailer ON trailer_location_events(trailer_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_trailer_loc_events_kind ON trailer_location_events(location_kind);
CREATE INDEX IF NOT EXISTS idx_trailer_loc_events_job ON trailer_location_events(job_id);


-- ═══════════════════════════════════════════════════════════════════
-- ORDER ATTACHMENTS — polymorphic attachments for JPOs, POs, Returns
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS order_attachments (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type TEXT    NOT NULL CHECK(entity_type IN ('jpo', 'po', 'return')),
    entity_id   INTEGER NOT NULL,
    file_path   TEXT    NOT NULL,
    file_name   TEXT    NOT NULL,
    file_type   TEXT,
    file_size   INTEGER,
    description TEXT,
    uploaded_by INTEGER REFERENCES users(id),
    deleted_at  TEXT,
    created_at  TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_order_attachments_entity
    ON order_attachments(entity_type, entity_id);
  `,
};
