-- Migration 045: Bootstrap artifact verification support
-- Adds 'verified' status to install events and direct-download support.

-- SQLite doesn't support ALTER CHECK constraints, so we recreate the table
-- with the expanded status enum.  Data is preserved via INSERT-SELECT.

-- Step 1: Create new table with 'verified' included in the CHECK
CREATE TABLE IF NOT EXISTS _bootstrap_install_events_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL,
    platform TEXT NOT NULL,
    artifact_id INTEGER REFERENCES _bootstrap_artifacts(id),
    status TEXT NOT NULL CHECK(status IN ('requested','downloading','downloaded','verifying','verified','installing','installed','failed')),
    error_message TEXT,
    metadata_json TEXT,
    progress_pct REAL DEFAULT 0,
    bytes_downloaded INTEGER DEFAULT 0,
    bytes_total INTEGER DEFAULT 0,
    checksum_computed TEXT,
    checksum_verified INTEGER DEFAULT 0,
    signature_verified INTEGER,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Step 2: Copy existing data
INSERT OR IGNORE INTO _bootstrap_install_events_new (
    id, device_id, platform, artifact_id, status,
    error_message, metadata_json, created_at
)
SELECT id, device_id, platform, artifact_id, status,
       error_message, metadata_json, created_at
FROM _bootstrap_install_events;

-- Step 3: Drop old table and rename
DROP TABLE IF EXISTS _bootstrap_install_events;
ALTER TABLE _bootstrap_install_events_new RENAME TO _bootstrap_install_events;

-- Step 4: Recreate indexes
CREATE INDEX IF NOT EXISTS idx_bootstrap_events_device
  ON _bootstrap_install_events(device_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_bootstrap_events_status
  ON _bootstrap_install_events(status, created_at DESC);
