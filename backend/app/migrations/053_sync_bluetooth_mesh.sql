-- Migration 053: Sync Engine & Bluetooth Mesh (Phase 11)
--
-- Adds:
--   _device_error_log        — error reports uploaded from devices
--   _device_health_snapshots — periodic health telemetry (battery, storage, version)
--   _bt_encounters           — Bluetooth device-to-device sync encounter log
--   _media_delivery          — mandatory media delivery tracking
--   _shop_cluster_nodes      — multi-shop-PC cluster management
--   _log_retention_config    — per-log-type retention policy
--   ALTER _device_registry   — override flags, primary user, health fields

-- ═══════════════════════════════════════════════════════════════════
-- Device Error Log
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS _device_error_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id   TEXT NOT NULL,
    severity    TEXT NOT NULL CHECK(severity IN ('info','warning','error','critical')),
    error_type  TEXT NOT NULL,
    message     TEXT NOT NULL,
    stack_trace TEXT,
    context_json    TEXT,                       -- arbitrary JSON payload (screen, action, etc.)
    environment_json TEXT,                      -- OS, app version, memory, etc.
    occurred_at TEXT NOT NULL,
    uploaded_at TEXT DEFAULT (datetime('now')),
    resolved_at TEXT,
    resolved_by INTEGER REFERENCES users(id),
    resolution_note TEXT
);

CREATE INDEX IF NOT EXISTS idx_device_error_device_time
    ON _device_error_log(device_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_device_error_unresolved
    ON _device_error_log(severity) WHERE resolved_at IS NULL;

-- ═══════════════════════════════════════════════════════════════════
-- Device Health Snapshots (telemetry)
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS _device_health_snapshots (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id       TEXT NOT NULL,
    battery_level   INTEGER,                   -- 0-100
    battery_charging INTEGER DEFAULT 0,
    storage_used_mb  REAL,
    storage_total_mb REAL,
    app_version     TEXT,
    os_version      TEXT,
    pending_sync_count  INTEGER DEFAULT 0,
    pending_media_count INTEGER DEFAULT 0,
    last_sync_at    TEXT,
    memory_used_mb  REAL,
    snapshot_at     TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_device_health_device_time
    ON _device_health_snapshots(device_id, snapshot_at DESC);

-- ═══════════════════════════════════════════════════════════════════
-- Bluetooth Encounter Log
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS _bt_encounters (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    local_device_id     TEXT NOT NULL,
    remote_device_id    TEXT NOT NULL,
    encounter_start     TEXT NOT NULL,
    encounter_end       TEXT,
    changes_sent        INTEGER DEFAULT 0,
    changes_received    INTEGER DEFAULT 0,
    media_bytes_sent    INTEGER DEFAULT 0,
    media_bytes_received INTEGER DEFAULT 0,
    signal_strength     INTEGER,               -- RSSI in dBm
    status              TEXT DEFAULT 'completed'
        CHECK(status IN ('in_progress','completed','failed','aborted')),
    failure_reason      TEXT,
    created_at          TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_bt_encounters_local_time
    ON _bt_encounters(local_device_id, encounter_start DESC);
CREATE INDEX IF NOT EXISTS idx_bt_encounters_remote_time
    ON _bt_encounters(remote_device_id, encounter_start DESC);

-- ═══════════════════════════════════════════════════════════════════
-- Media Delivery Tracking
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS _media_delivery (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    media_path      TEXT NOT NULL,
    media_hash      TEXT NOT NULL,              -- SHA-256 of content
    origin_device_id TEXT NOT NULL,
    media_size_bytes INTEGER DEFAULT 0,
    delivered_to_shop INTEGER DEFAULT 0,
    shop_confirmed_at TEXT,
    created_at      TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_media_delivery_pending
    ON _media_delivery(delivered_to_shop) WHERE delivered_to_shop = 0;
CREATE INDEX IF NOT EXISTS idx_media_delivery_origin
    ON _media_delivery(origin_device_id);

-- ═══════════════════════════════════════════════════════════════════
-- Shop Cluster Nodes (multi-PC management)
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS _shop_cluster_nodes (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    node_id     TEXT NOT NULL UNIQUE,           -- UUID for this shop PC
    hostname    TEXT,
    local_ip    TEXT,
    port        INTEGER DEFAULT 8000,
    last_seen_at TEXT DEFAULT (datetime('now')),
    last_sync_at TEXT,
    is_primary  INTEGER DEFAULT 0,
    status      TEXT DEFAULT 'online'
        CHECK(status IN ('online','offline','syncing')),
    app_version TEXT,
    db_version  INTEGER,
    created_at  TEXT DEFAULT (datetime('now'))
);

-- ═══════════════════════════════════════════════════════════════════
-- Log Retention Configuration
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS _log_retention_config (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    log_type             TEXT NOT NULL UNIQUE,
    device_retention_days INTEGER DEFAULT 90,   -- 3 months on devices
    shop_retention_days   INTEGER DEFAULT 365,  -- 1 year on shop
    updated_at           TEXT DEFAULT (datetime('now'))
);

INSERT OR IGNORE INTO _log_retention_config (log_type, device_retention_days, shop_retention_days) VALUES
    ('sync_batches',    90, 365),
    ('conflict_log',    90, 365),
    ('error_log',       90, 180),
    ('health_snapshots', 2,  90),
    ('bt_encounters',   90, 365),
    ('security_audit',  90, 365),
    ('relay_events',    90, 365);

-- ═══════════════════════════════════════════════════════════════════
-- Extend _device_registry with override flags and health fields
-- ═══════════════════════════════════════════════════════════════════
ALTER TABLE _device_registry ADD COLUMN override_action TEXT;          -- 'force_logout','force_wipe','force_sync'
ALTER TABLE _device_registry ADD COLUMN override_set_at TEXT;
ALTER TABLE _device_registry ADD COLUMN override_set_by INTEGER;
ALTER TABLE _device_registry ADD COLUMN is_disabled INTEGER DEFAULT 0;
ALTER TABLE _device_registry ADD COLUMN disabled_reason TEXT;
ALTER TABLE _device_registry ADD COLUMN primary_user_id INTEGER REFERENCES users(id);
ALTER TABLE _device_registry ADD COLUMN force_sync_flag INTEGER DEFAULT 0;
ALTER TABLE _device_registry ADD COLUMN config_version INTEGER DEFAULT 1;
ALTER TABLE _device_registry ADD COLUMN app_version TEXT;
ALTER TABLE _device_registry ADD COLUMN os_version TEXT;

-- Copy existing primary user IDs from sync profiles (back-fill)
UPDATE _device_registry
   SET primary_user_id = (
       SELECT primary_user_id FROM _device_sync_profiles
        WHERE _device_sync_profiles.device_id = _device_registry.device_id
   )
 WHERE primary_user_id IS NULL
   AND EXISTS (
       SELECT 1 FROM _device_sync_profiles
        WHERE _device_sync_profiles.device_id = _device_registry.device_id
          AND _device_sync_profiles.primary_user_id IS NOT NULL
   );

-- Seed manage_devices permission
INSERT OR IGNORE INTO permissions (key, label, description, category)
VALUES ('manage_devices', 'Manage Devices', 'View and manage paired devices, overrides, error logs, health telemetry', 'admin');
