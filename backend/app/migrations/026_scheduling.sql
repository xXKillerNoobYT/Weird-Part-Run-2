-- =============================================================
-- MIGRATION 026: Scheduling & Dispatch
-- =============================================================
-- Phase 10: Adds employee scheduling, time-off management,
-- job dispatch, and subcontractor scheduling.
--
-- Tables created:
--   employee_default_schedules — weekly work pattern (7 day slots)
--   schedule_exceptions        — time off, sick days, modified hours
--   job_dispatch               — employee ↔ job daily assignments
--   subcontractor_schedules    — GC/sub visits to our job sites
-- =============================================================


-- ─── EMPLOYEE DEFAULT SCHEDULES ─────────────────────────────
-- Weekly work pattern: one row per (employee, day_of_week).
-- 0=Sunday through 6=Saturday.
-- start_time/end_time are "HH:MM" text (e.g. "07:00", "15:30").
-- is_working_day=0 means the employee doesn't work that day.
CREATE TABLE IF NOT EXISTS employee_default_schedules (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    day_of_week     INTEGER NOT NULL CHECK(day_of_week BETWEEN 0 AND 6),
    start_time      TEXT    DEFAULT '07:00',
    end_time        TEXT    DEFAULT '15:30',
    is_working_day  INTEGER DEFAULT 1,
    notes           TEXT,

    UNIQUE(user_id, day_of_week)
);

CREATE INDEX IF NOT EXISTS idx_default_sched_user ON employee_default_schedules(user_id);


-- ─── SCHEDULE EXCEPTIONS ────────────────────────────────────
-- Single-day overrides: time off, sick days, holidays, etc.
-- For full-day exceptions, start_time/end_time are NULL.
-- For modified hours, both are set (e.g. leaving early).
-- Approval workflow: is_approved starts 0, approved_by records who approved.
CREATE TABLE IF NOT EXISTS schedule_exceptions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    exception_date  TEXT    NOT NULL,                  -- ISO date: "2026-03-15"
    exception_type  TEXT    NOT NULL
                    CHECK(exception_type IN (
                        'time_off', 'sick', 'vacation', 'holiday',
                        'modified_hours', 'unpaid_leave',
                        'jury_duty', 'bereavement'
                    )),
    start_time      TEXT,                              -- NULL = full day off
    end_time        TEXT,                              -- NULL = full day off
    is_approved     INTEGER DEFAULT 0,
    approved_by     INTEGER REFERENCES users(id),
    approved_at     TEXT,                              -- ISO datetime
    reason          TEXT,
    notes           TEXT,
    created_at      TEXT    DEFAULT (datetime('now')),

    UNIQUE(user_id, exception_date)
);

CREATE INDEX IF NOT EXISTS idx_sched_exc_user   ON schedule_exceptions(user_id, exception_date);
CREATE INDEX IF NOT EXISTS idx_sched_exc_date   ON schedule_exceptions(exception_date);
CREATE INDEX IF NOT EXISTS idx_sched_exc_pending ON schedule_exceptions(is_approved, exception_date);


-- ─── JOB DISPATCH ───────────────────────────────────────────
-- Daily assignment of employees to jobs.
-- Dispatched by a manager/admin, confirmed by the employee.
-- status tracks the lifecycle: scheduled → confirmed → on_site → completed.
-- role_on_job describes what the employee is doing on that job.
CREATE TABLE IF NOT EXISTS job_dispatch (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id          INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    dispatch_date   TEXT    NOT NULL,                  -- ISO date
    shift_start     TEXT,                              -- "HH:MM" or NULL for default
    shift_end       TEXT,                              -- "HH:MM" or NULL for default
    role_on_job     TEXT    DEFAULT 'worker'
                    CHECK(role_on_job IN (
                        'lead', 'worker', 'apprentice', 'helper'
                    )),
    status          TEXT    DEFAULT 'scheduled'
                    CHECK(status IN (
                        'scheduled', 'confirmed', 'on_site',
                        'completed', 'no_show', 'cancelled'
                    )),
    dispatched_by   INTEGER REFERENCES users(id),
    notes           TEXT,
    created_at      TEXT    DEFAULT (datetime('now')),
    updated_at      TEXT    DEFAULT (datetime('now')),

    UNIQUE(user_id, dispatch_date, job_id)
);

CREATE INDEX IF NOT EXISTS idx_dispatch_date    ON job_dispatch(dispatch_date);
CREATE INDEX IF NOT EXISTS idx_dispatch_user    ON job_dispatch(user_id, dispatch_date);
CREATE INDEX IF NOT EXISTS idx_dispatch_job     ON job_dispatch(job_id, dispatch_date);
CREATE INDEX IF NOT EXISTS idx_dispatch_status  ON job_dispatch(status, dispatch_date);

-- updated_at trigger
CREATE TRIGGER IF NOT EXISTS trg_dispatch_updated_at
    AFTER UPDATE ON job_dispatch
    FOR EACH ROW
BEGIN
    UPDATE job_dispatch SET updated_at = datetime('now') WHERE id = NEW.id;
END;


-- ─── SUBCONTRACTOR SCHEDULES ────────────────────────────────
-- Tracks when GCs we've hired (relationship='we_hired_them')
-- are scheduled to come to our job sites.
-- Also usable for tracking when we need to be at a GC's site.
CREATE TABLE IF NOT EXISTS subcontractor_schedules (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id          INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    gc_id           INTEGER NOT NULL REFERENCES general_contractors(id) ON DELETE CASCADE,
    scheduled_date  TEXT    NOT NULL,                  -- ISO date
    arrival_time    TEXT,                              -- "HH:MM"
    departure_time  TEXT,                              -- "HH:MM"
    work_description TEXT,                             -- what they're doing on site
    status          TEXT    DEFAULT 'scheduled'
                    CHECK(status IN (
                        'scheduled', 'confirmed', 'on_site',
                        'completed', 'cancelled', 'no_show'
                    )),
    notes           TEXT,
    created_at      TEXT    DEFAULT (datetime('now')),
    updated_at      TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_sub_sched_job    ON subcontractor_schedules(job_id, scheduled_date);
CREATE INDEX IF NOT EXISTS idx_sub_sched_gc     ON subcontractor_schedules(gc_id, scheduled_date);
CREATE INDEX IF NOT EXISTS idx_sub_sched_date   ON subcontractor_schedules(scheduled_date);
CREATE INDEX IF NOT EXISTS idx_sub_sched_status ON subcontractor_schedules(status, scheduled_date);

-- updated_at trigger
CREATE TRIGGER IF NOT EXISTS trg_sub_sched_updated_at
    AFTER UPDATE ON subcontractor_schedules
    FOR EACH ROW
BEGIN
    UPDATE subcontractor_schedules SET updated_at = datetime('now') WHERE id = NEW.id;
END;
