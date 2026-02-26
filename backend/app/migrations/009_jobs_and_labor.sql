-- ═══════════════════════════════════════════════════════════════════════
-- Migration 009: Jobs & Labor
-- Phase 4 — Job CRUD, parts consumption tracking, labor clock in/out
-- ═══════════════════════════════════════════════════════════════════════

-- ═══ JOBS ═══════════════════════════════════════════════════════════════
-- Core job entity. Referenced by stock_movements.job_id, job_lead_elevations,
-- and warehouse location lookups. This table resolves those foreign key stubs.
CREATE TABLE IF NOT EXISTS jobs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_number TEXT NOT NULL UNIQUE,
    job_name TEXT NOT NULL,
    customer_name TEXT NOT NULL,

    -- Address & GPS
    address_line1 TEXT,
    address_line2 TEXT,
    city TEXT,
    state TEXT,
    zip TEXT,
    gps_lat REAL,
    gps_lng REAL,

    -- Status & Classification
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'on_hold', 'completed', 'cancelled')),
    priority TEXT NOT NULL DEFAULT 'normal'
        CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    job_type TEXT NOT NULL DEFAULT 'service'
        CHECK (job_type IN ('service', 'new_construction', 'remodel', 'maintenance', 'emergency')),

    -- Financial
    billing_rate REAL,              -- $/hr for this job
    estimated_hours REAL,

    -- People
    lead_user_id INTEGER REFERENCES users(id),

    -- Metadata
    start_date TEXT,
    due_date TEXT,
    completed_date TEXT,
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_number ON jobs(job_number);


-- ═══ JOB PARTS (consumption tracking) ══════════════════════════════════
-- Tracks parts consumed on a job. Snapshots cost at time of consumption
-- so historical reporting stays accurate even if prices change later.
CREATE TABLE IF NOT EXISTS job_parts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id INTEGER NOT NULL REFERENCES jobs(id),
    part_id INTEGER NOT NULL REFERENCES parts(id),
    qty_consumed INTEGER NOT NULL DEFAULT 0,
    qty_returned INTEGER NOT NULL DEFAULT 0,
    unit_cost_at_consume REAL,      -- snapshot of cost at consumption time
    unit_sell_at_consume REAL,      -- snapshot of sell price at consumption time
    consumed_by INTEGER REFERENCES users(id),
    consumed_at TEXT NOT NULL DEFAULT (datetime('now')),
    notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_job_parts_job ON job_parts(job_id);
CREATE INDEX IF NOT EXISTS idx_job_parts_part ON job_parts(part_id);


-- ═══ LABOR ENTRIES ═════════════════════════════════════════════════════
-- One row per clock-in/clock-out session per worker per job.
-- Hours are calculated on clock-out. GPS captured at both events.
CREATE TABLE IF NOT EXISTS labor_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id),
    job_id INTEGER NOT NULL REFERENCES jobs(id),

    -- Clock times (ISO 8601 strings)
    clock_in TEXT NOT NULL,
    clock_out TEXT,

    -- Calculated hours (set on clock-out)
    regular_hours REAL,
    overtime_hours REAL,
    drive_time_minutes INTEGER DEFAULT 0,

    -- Location tracking
    clock_in_gps_lat REAL,
    clock_in_gps_lng REAL,
    clock_out_gps_lat REAL,
    clock_out_gps_lng REAL,

    -- Photo evidence
    clock_in_photo_path TEXT,
    clock_out_photo_path TEXT,

    -- Status lifecycle
    status TEXT NOT NULL DEFAULT 'clocked_in'
        CHECK (status IN ('clocked_in', 'clocked_out', 'edited', 'approved')),
    edited_by INTEGER REFERENCES users(id),
    approved_by INTEGER REFERENCES users(id),
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_labor_user ON labor_entries(user_id);
CREATE INDEX IF NOT EXISTS idx_labor_job ON labor_entries(job_id);
CREATE INDEX IF NOT EXISTS idx_labor_clock_in ON labor_entries(clock_in);
CREATE INDEX IF NOT EXISTS idx_labor_status ON labor_entries(status);
