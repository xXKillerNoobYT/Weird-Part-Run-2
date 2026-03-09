-- 045: Backup tracking table
-- Records all automated and manual backups for retention management.

CREATE TABLE IF NOT EXISTS _backups (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    backup_type TEXT    NOT NULL,                           -- 'db' or 'app'
    file_path   TEXT    NOT NULL,
    file_name   TEXT    NOT NULL,
    size_bytes  INTEGER,
    created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_backups_type_created
    ON _backups (backup_type, created_at DESC);
