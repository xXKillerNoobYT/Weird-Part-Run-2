-- Migration 038: Hard Sync Backup / Recovery
-- Adds hard-sync event tracking for deterministic device re-alignment.

CREATE TABLE IF NOT EXISTS _hard_sync_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL,
    requested_by INTEGER REFERENCES users(id),
    reason_code TEXT,
    pending_outbound_hashes TEXT,
    include_tables TEXT,
    preserve_pending_data INTEGER NOT NULL DEFAULT 1,
    sync_batch_id TEXT,
    package_summary TEXT,
    status TEXT NOT NULL DEFAULT 'requested'
      CHECK (status IN ('requested','package_ready','in_progress','completed','failed')),
    requested_at TEXT NOT NULL DEFAULT (datetime('now')),
    started_at TEXT,
    completed_at TEXT,
    notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_hard_sync_events_device
  ON _hard_sync_events(device_id, requested_at DESC);

CREATE INDEX IF NOT EXISTS idx_hard_sync_events_status
  ON _hard_sync_events(status, requested_at DESC);
