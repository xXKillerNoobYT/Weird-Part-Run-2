-- Migration 030: Sync Engine Tables
-- Adds change tracking, device registry, and conflict logging
-- for the V1.0 LAN sync between shop and mobile devices.

-- ── Shop-side change log ──────────────────────────────────────────
-- Every write on the shop DB logs here so devices can pull changes.
-- source_device_id is NULL for shop-originated changes, or the device
-- UUID if the change came from a device (applied during sync push).
CREATE TABLE IF NOT EXISTS _shop_change_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_device_id TEXT,
    table_name TEXT NOT NULL,
    record_id INTEGER NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    changed_fields TEXT,
    timestamp TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_shop_changes_time
    ON _shop_change_log(timestamp);
CREATE INDEX IF NOT EXISTS idx_shop_changes_source
    ON _shop_change_log(source_device_id);

-- ── Device registry ───────────────────────────────────────────────
-- Tracks all known devices and their last sync state.
-- Separate from the existing devices table (which handles auth/assignment).
CREATE TABLE IF NOT EXISTS _device_registry (
    device_id TEXT PRIMARY KEY,
    device_name TEXT,
    platform TEXT,                      -- 'ios', 'android', 'web'
    user_id INTEGER REFERENCES users(id),
    last_sync_at TEXT,
    last_sync_batch_id TEXT,
    pending_changes INTEGER DEFAULT 0,
    registered_at TEXT DEFAULT (datetime('now'))
);

-- ── Conflict log ──────────────────────────────────────────────────
-- Records every conflict that occurred during sync, for admin review.
CREATE TABLE IF NOT EXISTS _conflict_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    table_name TEXT NOT NULL,
    record_id INTEGER NOT NULL,
    device_a_id TEXT,
    device_b_id TEXT,
    resolution TEXT NOT NULL,         -- 'device_wins', 'shop_wins', 'merged'
    device_values TEXT,               -- JSON of what the device had
    shop_values TEXT,                 -- JSON of what the shop had
    resolved_values TEXT,             -- JSON of the final resolved state
    resolved_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_conflict_log_time
    ON _conflict_log(resolved_at);
CREATE INDEX IF NOT EXISTS idx_conflict_log_table
    ON _conflict_log(table_name, record_id);

-- ── Sync batch log ────────────────────────────────────────────────
-- Records each sync session for debugging and audit.
CREATE TABLE IF NOT EXISTS _sync_batches (
    id TEXT PRIMARY KEY,              -- UUID batch ID
    device_id TEXT NOT NULL,
    direction TEXT NOT NULL,          -- 'push', 'pull', 'full'
    changes_sent INTEGER DEFAULT 0,
    changes_received INTEGER DEFAULT 0,
    conflicts_resolved INTEGER DEFAULT 0,
    started_at TEXT NOT NULL DEFAULT (datetime('now')),
    completed_at TEXT,
    status TEXT DEFAULT 'in_progress' -- 'in_progress', 'completed', 'failed'
);
