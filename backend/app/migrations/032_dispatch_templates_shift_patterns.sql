-- 032: Dispatch templates + Shift patterns
-- GAP-020: Recurring dispatch templates
-- GAP-022: Shift pattern model

-- ── Dispatch Templates ──────────────────────────────────────
-- A saved crew/job assignment pattern that can be applied to generate
-- actual dispatch records for a date range.

CREATE TABLE IF NOT EXISTS dispatch_templates (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL,
    job_id      INTEGER NOT NULL REFERENCES jobs(id),
    shift_start TEXT,              -- default shift start time
    shift_end   TEXT,              -- default shift end time
    role_on_job TEXT    NOT NULL DEFAULT 'worker',
    -- Days this template applies (bitmask: bit 0=Sun, bit 6=Sat)
    -- e.g. Mon-Fri = 0b0111110 = 62
    days_of_week INTEGER NOT NULL DEFAULT 62,
    notes       TEXT,
    is_active   INTEGER NOT NULL DEFAULT 1,
    created_by  INTEGER REFERENCES users(id),
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Members assigned to a template
CREATE TABLE IF NOT EXISTS dispatch_template_members (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    template_id INTEGER NOT NULL REFERENCES dispatch_templates(id) ON DELETE CASCADE,
    user_id     INTEGER NOT NULL REFERENCES users(id),
    role_on_job TEXT    NOT NULL DEFAULT 'worker',
    UNIQUE(template_id, user_id)
);

-- ── Shift Patterns ──────────────────────────────────────────
-- Named schedule patterns (e.g., "4x10", "Rotating 5/2", "Summer Hours")

CREATE TABLE IF NOT EXISTS shift_patterns (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL UNIQUE,
    description TEXT,
    is_active   INTEGER NOT NULL DEFAULT 1,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Each pattern has 7 day entries (like default_schedules but reusable)
CREATE TABLE IF NOT EXISTS shift_pattern_days (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    pattern_id      INTEGER NOT NULL REFERENCES shift_patterns(id) ON DELETE CASCADE,
    day_of_week     INTEGER NOT NULL CHECK(day_of_week BETWEEN 0 AND 6),
    start_time      TEXT    NOT NULL DEFAULT '07:00',
    end_time        TEXT    NOT NULL DEFAULT '15:30',
    is_working_day  INTEGER NOT NULL DEFAULT 1,
    UNIQUE(pattern_id, day_of_week)
);

-- Seed common patterns
INSERT OR IGNORE INTO shift_patterns (name, description) VALUES
    ('Standard 5x8', 'Monday-Friday 07:00-15:30'),
    ('4x10',         'Monday-Thursday 06:00-16:30'),
    ('Summer Hours', 'Monday-Friday 06:00-14:30');

-- Standard 5x8 days
INSERT OR IGNORE INTO shift_pattern_days (pattern_id, day_of_week, start_time, end_time, is_working_day)
SELECT p.id, d.dow, d.st, d.et, d.working
FROM shift_patterns p,
     (SELECT 0 AS dow, '07:00' AS st, '15:30' AS et, 0 AS working UNION ALL
      SELECT 1, '07:00', '15:30', 1 UNION ALL
      SELECT 2, '07:00', '15:30', 1 UNION ALL
      SELECT 3, '07:00', '15:30', 1 UNION ALL
      SELECT 4, '07:00', '15:30', 1 UNION ALL
      SELECT 5, '07:00', '15:30', 1 UNION ALL
      SELECT 6, '07:00', '15:30', 0) d
WHERE p.name = 'Standard 5x8';

-- 4x10 days
INSERT OR IGNORE INTO shift_pattern_days (pattern_id, day_of_week, start_time, end_time, is_working_day)
SELECT p.id, d.dow, d.st, d.et, d.working
FROM shift_patterns p,
     (SELECT 0 AS dow, '06:00' AS st, '16:30' AS et, 0 AS working UNION ALL
      SELECT 1, '06:00', '16:30', 1 UNION ALL
      SELECT 2, '06:00', '16:30', 1 UNION ALL
      SELECT 3, '06:00', '16:30', 1 UNION ALL
      SELECT 4, '06:00', '16:30', 1 UNION ALL
      SELECT 5, '06:00', '16:30', 0 UNION ALL
      SELECT 6, '06:00', '16:30', 0) d
WHERE p.name = '4x10';

-- Summer Hours days
INSERT OR IGNORE INTO shift_pattern_days (pattern_id, day_of_week, start_time, end_time, is_working_day)
SELECT p.id, d.dow, d.st, d.et, d.working
FROM shift_patterns p,
     (SELECT 0 AS dow, '06:00' AS st, '14:30' AS et, 0 AS working UNION ALL
      SELECT 1, '06:00', '14:30', 1 UNION ALL
      SELECT 2, '06:00', '14:30', 1 UNION ALL
      SELECT 3, '06:00', '14:30', 1 UNION ALL
      SELECT 4, '06:00', '14:30', 1 UNION ALL
      SELECT 5, '06:00', '14:30', 1 UNION ALL
      SELECT 6, '06:00', '14:30', 0) d
WHERE p.name = 'Summer Hours';
