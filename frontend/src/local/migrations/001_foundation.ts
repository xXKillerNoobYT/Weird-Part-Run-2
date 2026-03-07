/**
 * Migration 001: Foundation
 *
 * Core tables: users, hats, permissions, devices, settings,
 * activity_log, notifications. Seed data for built-in hats
 * and permission keys.
 *
 * Consolidated from: backend migrations 001, 015 (notification cols),
 * 023 (user_hats.is_active)
 */

export const migration = {
  name: '001_foundation',
  sql: `
-- ─── USERS ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    display_name            TEXT    NOT NULL,
    email                   TEXT,
    phone                   TEXT,
    pin_hash                TEXT    NOT NULL,
    default_truck_id        INTEGER,
    emergency_contact_name  TEXT,
    emergency_contact_phone TEXT,
    certification           TEXT    CHECK(certification IN ('journeyman', 'apprentice', 'master', NULL)),
    hire_date               TEXT,
    pay_rate                REAL,
    is_active               INTEGER DEFAULT 1,
    avatar_url              TEXT,
    created_at              TEXT    DEFAULT (datetime('now')),
    updated_at              TEXT    DEFAULT (datetime('now'))
);

-- ─── HATS (Roles) ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS hats (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL UNIQUE,
    description TEXT,
    level       INTEGER DEFAULT 0,
    is_builtin  INTEGER DEFAULT 0,
    created_at  TEXT    DEFAULT (datetime('now'))
);

-- ─── HAT PERMISSIONS ────────────────────────────────────────────
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
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id   INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    hat_id    INTEGER NOT NULL REFERENCES hats(id) ON DELETE CASCADE,
    is_active INTEGER DEFAULT 1,
    UNIQUE(user_id, hat_id)
);
CREATE INDEX IF NOT EXISTS idx_user_hats_user ON user_hats(user_id);

-- ─── JOB LEAD ELEVATIONS ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS job_lead_elevations (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    job_id          INTEGER NOT NULL,
    permission_key  TEXT    NOT NULL,
    granted_by      INTEGER REFERENCES users(id),
    granted_at      TEXT    DEFAULT (datetime('now')),
    expires_at      TEXT,
    UNIQUE(user_id, job_id, permission_key)
);

-- ─── DEVICES ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS devices (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    device_name         TEXT    NOT NULL,
    device_fingerprint  TEXT    UNIQUE NOT NULL,
    assigned_user_id    INTEGER REFERENCES users(id),
    is_public           INTEGER DEFAULT 0,
    last_seen           TEXT,
    created_at          TEXT    DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_devices_fp ON devices(device_fingerprint);

-- ─── SETTINGS ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS settings (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    key         TEXT    NOT NULL UNIQUE,
    value       TEXT,
    category    TEXT    DEFAULT 'general',
    updated_at  TEXT    DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_settings_cat ON settings(category);

-- ─── ACTIVITY LOG ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS activity_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     INTEGER REFERENCES users(id),
    action      TEXT    NOT NULL,
    entity_type TEXT,
    entity_id   INTEGER,
    details     TEXT,
    ip_address  TEXT,
    timestamp   TEXT    DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_activity_ts ON activity_log(timestamp);
CREATE INDEX IF NOT EXISTS idx_activity_entity ON activity_log(entity_type, entity_id);

-- ─── NOTIFICATIONS ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notifications (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     INTEGER REFERENCES users(id),
    title       TEXT    NOT NULL,
    body        TEXT,
    severity    TEXT    DEFAULT 'info' CHECK(severity IN ('info','warning','error','critical')),
    source      TEXT    DEFAULT 'system',
    link        TEXT,
    is_read     INTEGER DEFAULT 0,
    type        TEXT    DEFAULT 'system',
    message     TEXT,
    entity_type TEXT,
    entity_id   INTEGER,
    created_at  TEXT    DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_notif_user ON notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at);
CREATE INDEX IF NOT EXISTS idx_notifications_entity ON notifications(entity_type, entity_id);

-- ─── NOTIFICATION PREFERENCES ───────────────────────────────────
CREATE TABLE IF NOT EXISTS notification_preferences (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id           INTEGER NOT NULL REFERENCES users(id),
    notification_type TEXT    NOT NULL,
    is_enabled        INTEGER NOT NULL DEFAULT 0,
    UNIQUE(user_id, notification_type)
);
CREATE INDEX IF NOT EXISTS idx_notif_prefs_user ON notification_preferences(user_id);
  `,
};
