-- Migration 035: Scheduling Enhancements
-- Adds lunch break fields (lunch_start, lunch_end) to scheduling tables
-- Adds 'supervisor' role to job_dispatch CHECK constraint
-- Date: 2026-03-07

-- ── 1. Lunch columns on employee_default_schedules ───────────
ALTER TABLE employee_default_schedules ADD COLUMN lunch_start TEXT DEFAULT NULL;
ALTER TABLE employee_default_schedules ADD COLUMN lunch_end TEXT DEFAULT NULL;

-- ── 2. Lunch columns on schedule_exceptions ──────────────────
ALTER TABLE schedule_exceptions ADD COLUMN lunch_start TEXT DEFAULT NULL;
ALTER TABLE schedule_exceptions ADD COLUMN lunch_end TEXT DEFAULT NULL;

-- ── 3. Recreate job_dispatch (add lunch + 'supervisor' role) ─
-- SQLite cannot ALTER CHECK constraints, so full table recreation is required.
CREATE TABLE job_dispatch_new (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id          INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    dispatch_date   TEXT    NOT NULL,
    shift_start     TEXT,
    shift_end       TEXT,
    lunch_start     TEXT,
    lunch_end       TEXT,
    role_on_job     TEXT    DEFAULT 'worker'
        CHECK(role_on_job IN ('lead','worker','apprentice','helper','supervisor')),
    status          TEXT    DEFAULT 'scheduled'
        CHECK(status IN (
            'scheduled','confirmed','on_site',
            'completed','no_show','cancelled'
        )),
    dispatched_by   INTEGER REFERENCES users(id),
    notes           TEXT,
    created_at      TEXT    DEFAULT (datetime('now')),
    updated_at      TEXT    DEFAULT (datetime('now')),
    UNIQUE(user_id, dispatch_date, job_id)
);

INSERT INTO job_dispatch_new (
    id, job_id, user_id, dispatch_date, shift_start, shift_end,
    lunch_start, lunch_end, role_on_job, status,
    dispatched_by, notes, created_at, updated_at
)
SELECT
    id, job_id, user_id, dispatch_date, shift_start, shift_end,
    NULL, NULL, role_on_job, status,
    dispatched_by, notes, created_at, updated_at
FROM job_dispatch;

DROP TABLE job_dispatch;
ALTER TABLE job_dispatch_new RENAME TO job_dispatch;

CREATE INDEX idx_dispatch_date ON job_dispatch(dispatch_date);
CREATE INDEX idx_dispatch_user ON job_dispatch(user_id, dispatch_date);
CREATE INDEX idx_dispatch_job ON job_dispatch(job_id, dispatch_date);

CREATE TRIGGER IF NOT EXISTS trg_job_dispatch_updated
AFTER UPDATE ON job_dispatch
BEGIN
    UPDATE job_dispatch SET updated_at = datetime('now') WHERE id = NEW.id;
END;

-- ── 4. Lunch columns on shift_pattern_days ───────────────────
ALTER TABLE shift_pattern_days ADD COLUMN lunch_start TEXT DEFAULT NULL;
ALTER TABLE shift_pattern_days ADD COLUMN lunch_end TEXT DEFAULT NULL;

-- ── 5. Lunch columns on dispatch_templates ───────────────────
ALTER TABLE dispatch_templates ADD COLUMN lunch_start TEXT DEFAULT NULL;
ALTER TABLE dispatch_templates ADD COLUMN lunch_end TEXT DEFAULT NULL;
