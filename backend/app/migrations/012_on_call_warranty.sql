-- ═══════════════════════════════════════════════════════════════════════
-- Migration 012: On Call / Warranty Sub-type
--
-- Differentiates the "on_call" job status into two sub-types:
--   • on_call   — indefinite standby, no expiration
--   • warranty  — time-bounded post-fix coverage with start/end dates
--
-- Also seeds a global setting for default warranty duration.
-- ═══════════════════════════════════════════════════════════════════════

-- Sub-type column: only meaningful when jobs.status = 'on_call'
ALTER TABLE jobs ADD COLUMN on_call_type TEXT
    CHECK (on_call_type IN ('on_call', 'warranty'));

-- Warranty date tracking (ISO 8601 TEXT, like existing date columns)
ALTER TABLE jobs ADD COLUMN warranty_start_date TEXT;
ALTER TABLE jobs ADD COLUMN warranty_end_date TEXT;

-- Default warranty duration = 1 year (365 days)
INSERT OR IGNORE INTO settings (key, value, category)
    VALUES ('warranty_length_days', '365', 'jobs');
