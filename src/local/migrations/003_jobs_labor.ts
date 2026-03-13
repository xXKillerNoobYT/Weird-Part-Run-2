/**
 * Migration 003: Jobs & Labor
 *
 * Jobs, labor entries, clock-out questions/responses, daily reports.
 * Consolidated from: backend migrations 009, 010, 011, 012
 */

export const migration = {
  name: '003_jobs_labor',
  sql: `
-- ─── BILL RATE TYPES ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bill_rate_types (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL UNIQUE,
    description TEXT,
    sort_order  INTEGER DEFAULT 0,
    is_active   INTEGER DEFAULT 1,
    created_at  TEXT    DEFAULT (datetime('now'))
);

-- ─── JOBS ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS jobs (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_number      TEXT    NOT NULL UNIQUE,
    job_name        TEXT    NOT NULL,
    customer_name   TEXT,
    address_line1   TEXT,
    address_line2   TEXT,
    city            TEXT,
    state           TEXT,
    zip             TEXT,
    gps_lat         REAL,
    gps_lng         REAL,
    status          TEXT    NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','on_hold','completed','cancelled',
                          'continuous_maintenance','on_call','pending')),
    priority        TEXT    NOT NULL DEFAULT 'normal'
        CHECK (priority IN ('low','normal','high','urgent')),
    job_type        TEXT    NOT NULL DEFAULT 'service'
        CHECK (job_type IN ('service','new_construction','remodel','maintenance','emergency')),
    bill_rate_type_id INTEGER REFERENCES bill_rate_types(id),
    billing_rate    REAL,
    estimated_hours REAL,
    lead_user_id    INTEGER REFERENCES users(id),
    on_call_type    TEXT,
    warranty_start_date TEXT,
    warranty_end_date   TEXT,
    start_date      TEXT,
    due_date        TEXT,
    completed_date  TEXT,
    notes           TEXT,
    created_by      INTEGER REFERENCES users(id),
    created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_number ON jobs(job_number);

-- ─── JOB PARTS (consumption tracking) ──────────────────────
CREATE TABLE IF NOT EXISTS job_parts (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id                INTEGER NOT NULL REFERENCES jobs(id),
    part_id               INTEGER NOT NULL REFERENCES parts(id),
    qty_consumed          INTEGER NOT NULL DEFAULT 0,
    qty_returned          INTEGER NOT NULL DEFAULT 0,
    unit_cost_at_consume  REAL,
    unit_sell_at_consume  REAL,
    consumed_by           INTEGER REFERENCES users(id),
    consumed_at           TEXT    NOT NULL DEFAULT (datetime('now')),
    notes                 TEXT
);
CREATE INDEX IF NOT EXISTS idx_job_parts_job ON job_parts(job_id);

-- ─── LABOR ENTRIES ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS labor_entries (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id              INTEGER NOT NULL REFERENCES users(id),
    job_id               INTEGER NOT NULL REFERENCES jobs(id),
    clock_in             TEXT    NOT NULL,
    clock_out            TEXT,
    regular_hours        REAL    DEFAULT 0,
    overtime_hours       REAL    DEFAULT 0,
    drive_time_minutes   INTEGER DEFAULT 0,
    clock_in_gps_lat     REAL,
    clock_in_gps_lng     REAL,
    clock_out_gps_lat    REAL,
    clock_out_gps_lng    REAL,
    clock_in_photo_path  TEXT,
    clock_out_photo_path TEXT,
    status               TEXT    NOT NULL DEFAULT 'clocked_in'
        CHECK (status IN ('clocked_in','clocked_out','edited','approved')),
    edited_by            INTEGER REFERENCES users(id),
    approved_by          INTEGER REFERENCES users(id),
    notes                TEXT,
    created_at           TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_labor_user ON labor_entries(user_id);
CREATE INDEX IF NOT EXISTS idx_labor_job ON labor_entries(job_id);
CREATE INDEX IF NOT EXISTS idx_labor_status ON labor_entries(status);

-- ─── CLOCK-OUT QUESTIONS ────────────────────────────────────
CREATE TABLE IF NOT EXISTS clock_out_questions (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    question_text TEXT    NOT NULL,
    answer_type   TEXT    NOT NULL DEFAULT 'text'
        CHECK (answer_type IN ('text','yes_no','photo')),
    is_required   INTEGER NOT NULL DEFAULT 1,
    sort_order    INTEGER NOT NULL DEFAULT 0,
    is_active     INTEGER NOT NULL DEFAULT 1,
    created_by    INTEGER REFERENCES users(id),
    created_at    TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at    TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- ─── CLOCK-OUT RESPONSES ────────────────────────────────────
CREATE TABLE IF NOT EXISTS clock_out_responses (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    labor_entry_id  INTEGER NOT NULL REFERENCES labor_entries(id),
    question_id     INTEGER NOT NULL REFERENCES clock_out_questions(id),
    answer_text     TEXT,
    answer_bool     INTEGER,
    photo_path      TEXT,
    answered_at     TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_cor_labor ON clock_out_responses(labor_entry_id);

-- ─── ONE-TIME PER-JOB QUESTIONS ─────────────────────────────
CREATE TABLE IF NOT EXISTS one_time_questions (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id             INTEGER NOT NULL REFERENCES jobs(id),
    target_user_id     INTEGER REFERENCES users(id),
    question_text      TEXT    NOT NULL,
    answer_type        TEXT    NOT NULL DEFAULT 'text'
        CHECK (answer_type IN ('text','yes_no','photo')),
    status             TEXT    NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','answered','expired','cancelled')),
    created_by         INTEGER NOT NULL REFERENCES users(id),
    answered_by        INTEGER REFERENCES users(id),
    answer_text        TEXT,
    answer_photo_path  TEXT,
    shown_at_clock_in  INTEGER NOT NULL DEFAULT 0,
    created_at         TEXT    NOT NULL DEFAULT (datetime('now')),
    answered_at        TEXT
);
CREATE INDEX IF NOT EXISTS idx_otq_job ON one_time_questions(job_id);

-- ─── DAILY REPORTS ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS daily_reports (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id         INTEGER NOT NULL REFERENCES jobs(id),
    report_date    TEXT    NOT NULL,
    report_json    TEXT    NOT NULL,
    status         TEXT    NOT NULL DEFAULT 'generated'
        CHECK (status IN ('generated','reviewed','locked')),
    generated_at   TEXT    NOT NULL DEFAULT (datetime('now')),
    reviewed_by    INTEGER REFERENCES users(id),
    reviewed_at    TEXT,
    UNIQUE(job_id, report_date)
);
CREATE INDEX IF NOT EXISTS idx_dr_job_date ON daily_reports(job_id, report_date);
  `,
};
