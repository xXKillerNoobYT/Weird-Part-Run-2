-- Migration 043: Update Protocol
--
-- Implements the shop-centric, mesh-propagated update pipeline.
-- Shop PCs are the only source of truth — they fetch from GitHub,
-- validate in a sandbox, publish to the field, and track fleet rollout.
--
-- Tables:
--   _update_registry        — master list of known update versions
--   _update_validations     — per-version, per-platform sandbox test results
--   _fleet_targets          — per-platform fleet rollout targets
--   _device_update_status   — per-device current version + pending queue
--   _update_backup_snapshots— shop backup records before applying an update

-- ── Update Registry ─────────────────────────────────────────────
-- One row per version released on GitHub (or manually added).

CREATE TABLE IF NOT EXISTS _update_registry (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    version             TEXT NOT NULL UNIQUE,                  -- semver string, e.g. '1.4.0'
    previous_version    TEXT,                                  -- strict chain: install only from this version
    release_notes       TEXT,
    checksum_sha256     TEXT,                                  -- of the update package
    signature           TEXT,                                  -- optional cryptographic signature
    package_url         TEXT,                                  -- where to download (shop-local path or GitHub URL)
    package_size_bytes  INTEGER,
    migration_scripts   TEXT NOT NULL DEFAULT '[]',            -- JSON array of migration filenames
    rollback_scripts    TEXT NOT NULL DEFAULT '[]',            -- JSON array of rollback filenames
    min_compatible_version TEXT,                               -- oldest version this release can coexist with
    max_compatible_version TEXT,                               -- newest version this release can coexist with
    criticality         TEXT NOT NULL DEFAULT 'normal',        -- 'critical' | 'normal' | 'optional'
    source              TEXT NOT NULL DEFAULT 'github',        -- 'github' | 'manual' | 'rollup'
    fetched_at          TEXT NOT NULL DEFAULT (datetime('now')),
    published_at        TEXT,                                  -- NULL until approved and published to fleet
    created_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_update_registry_version
    ON _update_registry(version);


-- ── Update Validations ──────────────────────────────────────────
-- Per-platform sandbox test results.  A version is only published
-- when it passes validation for all targeted platforms.

CREATE TABLE IF NOT EXISTS _update_validations (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    version             TEXT NOT NULL REFERENCES _update_registry(version),
    platform            TEXT NOT NULL,                          -- 'windows' | 'macos' | 'ios' | 'android'
    status              TEXT NOT NULL DEFAULT 'pending',        -- 'pending' | 'running' | 'passed' | 'failed' | 'blocked'
    schema_diff_ok      INTEGER,                               -- 1/0 per compat check
    migration_test_ok   INTEGER,
    rollback_test_ok    INTEGER,
    backward_compat_ok  INTEGER,
    error_log           TEXT,                                   -- full error details on failure
    validated_by        INTEGER REFERENCES users(id),
    started_at          TEXT,
    completed_at        TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),

    UNIQUE(version, platform)
);


-- ── Fleet Targets ───────────────────────────────────────────────
-- Per-platform fleet rollout state.  The shop advances the target
-- only when all devices on that platform have reached the current target.

CREATE TABLE IF NOT EXISTS _fleet_targets (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    platform            TEXT NOT NULL UNIQUE,                   -- 'windows' | 'macos' | 'ios' | 'android'
    current_target      TEXT NOT NULL DEFAULT '0.0.0',         -- version all devices should be at
    latest_validated    TEXT,                                   -- newest version that passed validation
    devices_at_target   INTEGER NOT NULL DEFAULT 0,            -- count of devices at current_target
    devices_total       INTEGER NOT NULL DEFAULT 0,            -- total devices on this platform
    devices_behind      INTEGER NOT NULL DEFAULT 0,            -- devices still on older version
    auto_advance        INTEGER NOT NULL DEFAULT 1,            -- 1 = auto-advance when all caught up
    updated_at          TEXT NOT NULL DEFAULT (datetime('now')),
    updated_by          INTEGER REFERENCES users(id)
);


-- ── Device Update Status ────────────────────────────────────────
-- Tracks each device's installed version, pending updates, and install history.

CREATE TABLE IF NOT EXISTS _device_update_status (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id           TEXT NOT NULL REFERENCES _device_registry(device_id) ON DELETE CASCADE,
    platform            TEXT NOT NULL,
    current_version     TEXT NOT NULL DEFAULT '0.0.0',
    target_version      TEXT,                                  -- what the fleet target says it should be at
    pending_versions    TEXT NOT NULL DEFAULT '[]',            -- JSON array of versions queued for install
    last_install_version TEXT,                                 -- last successfully installed version
    last_install_at     TEXT,
    last_install_status TEXT,                                  -- 'success' | 'failed' | 'rolled_back'
    install_error       TEXT,                                  -- error message if last install failed
    backup_taken        INTEGER NOT NULL DEFAULT 0,            -- 1 if pre-update backup was created
    reported_at         TEXT NOT NULL DEFAULT (datetime('now')),

    UNIQUE(device_id)
);

CREATE INDEX IF NOT EXISTS idx_device_update_status_platform
    ON _device_update_status(platform);
CREATE INDEX IF NOT EXISTS idx_device_update_status_version
    ON _device_update_status(current_version);


-- ── Update Backup Snapshots ─────────────────────────────────────
-- Records of backups taken before applying an update (shop-side).
-- Enables full rollback if a validated update still causes issues in prod.

CREATE TABLE IF NOT EXISTS _update_backup_snapshots (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    version_before      TEXT NOT NULL,                         -- version at time of backup
    version_target      TEXT NOT NULL,                         -- version we're updating to
    backup_path         TEXT NOT NULL,                         -- filesystem path to the backup file
    backup_size_bytes   INTEGER,
    checksum_sha256     TEXT,
    includes_db         INTEGER NOT NULL DEFAULT 1,
    includes_config     INTEGER NOT NULL DEFAULT 1,
    includes_binary     INTEGER NOT NULL DEFAULT 1,
    status              TEXT NOT NULL DEFAULT 'created',       -- 'created' | 'verified' | 'restored' | 'expired'
    restored_at         TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    created_by          INTEGER REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_update_backups_version
    ON _update_backup_snapshots(version_before);
