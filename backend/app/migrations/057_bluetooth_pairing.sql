-- Migration 057: Bluetooth Device Pairing (Phase 11A)
--
-- Adds:
--   bt_paired_devices   — Bluetooth pairing records between PCs
--   bt_connection_log   — Connection session audit trail
--   bt_sync_config      — Per-device BT sync role configuration
--
-- This supports two-device (PC ↔ PC) sync over Bluetooth RFCOMM.
-- The primary (shop-role) PC acts as the truth anchor; the secondary
-- (field-role) PC syncs TO the primary when no LAN is available.

-- ═══════════════════════════════════════════════════════════════════
-- Bluetooth Paired Devices
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS bt_paired_devices (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id       TEXT,                              -- FK to _device_registry (nullable for initial pairing)
    bt_address      TEXT NOT NULL,                     -- "AA:BB:CC:DD:EE:FF"
    display_name    TEXT NOT NULL DEFAULT 'Unknown',   -- Human-readable name
    role            TEXT NOT NULL DEFAULT 'secondary'
        CHECK(role IN ('primary', 'secondary')),       -- Relationship role
    pairing_code    TEXT,                              -- 6-digit confirmation code
    is_active       INTEGER DEFAULT 1,                 -- 1 = active pair, 0 = unpaired
    last_connected_at TEXT,                            -- Last successful BT connection
    last_sync_at    TEXT,                              -- Last successful sync over BT
    paired_at       TEXT DEFAULT (datetime('now')),
    created_at      TEXT DEFAULT (datetime('now')),
    updated_at      TEXT DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_bt_paired_addr
    ON bt_paired_devices(bt_address) WHERE is_active = 1;

-- ═══════════════════════════════════════════════════════════════════
-- Bluetooth Connection Log
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS bt_connection_log (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    local_device_id     TEXT,                          -- This PC's device ID
    remote_device_id    TEXT,                          -- Paired device's ID
    remote_bt_address   TEXT NOT NULL,                 -- BT address of peer
    connected_at        TEXT NOT NULL,
    disconnected_at     TEXT,
    duration_seconds    REAL,                          -- Computed on disconnect
    bytes_sent          INTEGER DEFAULT 0,
    bytes_received      INTEGER DEFAULT 0,
    requests_forwarded  INTEGER DEFAULT 0,             -- HTTP requests tunneled
    changes_synced      INTEGER DEFAULT 0,             -- Sync changes exchanged
    disconnect_reason   TEXT,                          -- 'clean', 'timeout', 'error', 'manual'
    error_message       TEXT,
    created_at          TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_bt_conn_log_time
    ON bt_connection_log(connected_at DESC);
CREATE INDEX IF NOT EXISTS idx_bt_conn_log_remote
    ON bt_connection_log(remote_bt_address, connected_at DESC);

-- ═══════════════════════════════════════════════════════════════════
-- Bluetooth Sync Configuration (stored in settings table)
-- ═══════════════════════════════════════════════════════════════════
-- Uses the existing settings table with category 'bluetooth'
INSERT OR IGNORE INTO settings (key, value, category, description) VALUES
    ('bt_enabled',        'true',      'bluetooth', 'Enable Bluetooth sync features'),
    ('bt_device_role',    'auto',      'bluetooth', 'Device sync role: primary, secondary, or auto'),
    ('bt_auto_connect',   'true',      'bluetooth', 'Auto-connect to paired devices on startup'),
    ('bt_sync_interval',  '120',       'bluetooth', 'Sync interval in seconds when BT connected (default 120)'),
    ('bt_tunnel_port',    '9000',      'bluetooth', 'Local TCP port for BT tunnel (secondary mode)');

-- ═══════════════════════════════════════════════════════════════════
-- Bluetooth Sync State (local key-value store for sync tracking)
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS _bt_sync_state (
    key     TEXT PRIMARY KEY,
    value   TEXT,
    updated_at TEXT DEFAULT (datetime('now'))
);

-- ═══════════════════════════════════════════════════════════════════
-- Seed permission for Bluetooth management
-- ═══════════════════════════════════════════════════════════════════
INSERT OR IGNORE INTO permissions (key, label, description, category)
VALUES ('manage_bluetooth', 'Manage Bluetooth', 'Scan, pair, and manage Bluetooth device connections', 'admin');
