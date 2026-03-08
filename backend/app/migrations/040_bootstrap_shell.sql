-- Migration 040: Mobile Bootstrap Shell Support (V1.0.0)
-- Adds pairing, artifact manifest, and install event logging tables.

CREATE TABLE IF NOT EXISTS _bootstrap_pairing_codes (
    code TEXT PRIMARY KEY,
    created_by INTEGER REFERENCES users(id),
    device_id TEXT,
    device_name TEXT,
    platform TEXT,
    bootstrap_version TEXT,
    public_key TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    expires_at TEXT NOT NULL,
    used_at TEXT,
    notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_bootstrap_pairing_expires
  ON _bootstrap_pairing_codes(expires_at);

CREATE INDEX IF NOT EXISTS idx_bootstrap_pairing_used
  ON _bootstrap_pairing_codes(used_at);

CREATE TABLE IF NOT EXISTS _bootstrap_artifacts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    platform TEXT NOT NULL CHECK(platform IN ('ios','android','windows','macos')),
    version TEXT NOT NULL,
    manifest_json TEXT NOT NULL,
    download_url TEXT NOT NULL,
    checksum_sha256 TEXT NOT NULL,
    signature TEXT,
    min_bootstrap_version TEXT DEFAULT '0.0.0-bootstrap',
    is_active INTEGER NOT NULL DEFAULT 1,
    created_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_bootstrap_artifacts_platform
  ON _bootstrap_artifacts(platform, is_active, created_at DESC);

CREATE TABLE IF NOT EXISTS _bootstrap_install_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL,
    platform TEXT NOT NULL,
    artifact_id INTEGER REFERENCES _bootstrap_artifacts(id),
    status TEXT NOT NULL CHECK(status IN ('requested','downloaded','installed','failed')),
    error_message TEXT,
    metadata_json TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_bootstrap_events_device
  ON _bootstrap_install_events(device_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_bootstrap_events_status
  ON _bootstrap_install_events(status, created_at DESC);
