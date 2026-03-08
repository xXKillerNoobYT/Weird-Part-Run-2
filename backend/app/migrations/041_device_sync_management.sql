-- Migration 041: Device Sync Management (V1.0.0 subset)
-- Adds:
--  - _device_sync_profiles: primary-user-owned storage/sync preferences
--  - _mesh_relay_events: device-to-device relay telemetry for mesh auditing

CREATE TABLE IF NOT EXISTS _device_sync_profiles (
    device_id TEXT PRIMARY KEY REFERENCES _device_registry(device_id) ON DELETE CASCADE,
    primary_user_id INTEGER REFERENCES users(id),
    storage_policy TEXT NOT NULL DEFAULT 'active_jobs_core_only'
      CHECK(storage_policy IN ('active_jobs_core_only','all_jobs_core','minimal')),
    media_policy TEXT NOT NULL DEFAULT 'assigned_jobs_only'
      CHECK(media_policy IN ('all_jobs','assigned_jobs_only','thumbnails_only','none','last_n_days')),
    media_retention_days INTEGER NOT NULL DEFAULT 30,
    force_carry_undelivered_media INTEGER NOT NULL DEFAULT 1,
    allow_borrowed_user_overrides INTEGER NOT NULL DEFAULT 0,
    active_only_sync INTEGER NOT NULL DEFAULT 1,
    updated_by INTEGER REFERENCES users(id),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS _mesh_relay_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_device_id TEXT NOT NULL,
    peer_device_id TEXT NOT NULL,
    relay_type TEXT NOT NULL DEFAULT 'gossip'
      CHECK(relay_type IN ('gossip','handoff','shop_delivery','shop_ack')),
    carried_change_count INTEGER NOT NULL DEFAULT 0,
    carried_media_count INTEGER NOT NULL DEFAULT 0,
    undelivered_after_count INTEGER NOT NULL DEFAULT 0,
    metadata_json TEXT,
    recorded_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_mesh_relay_source_time
  ON _mesh_relay_events(source_device_id, recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_mesh_relay_peer_time
  ON _mesh_relay_events(peer_device_id, recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_mesh_relay_type_time
  ON _mesh_relay_events(relay_type, recorded_at DESC);
