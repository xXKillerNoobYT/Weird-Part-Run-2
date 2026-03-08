-- =============================================================
-- MIGRATION 037: Job Team Members
-- =============================================================
-- Adds job_team_members junction table so any number of employees
-- can be assigned to a job with a role (lead / member).
--
-- The existing jobs.lead_user_id column is kept for backwards
-- compatibility and is still the "primary" lead. Team members
-- are the broader assigned crew.

CREATE TABLE IF NOT EXISTS job_team_members (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id      INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    user_id     INTEGER NOT NULL REFERENCES users(id),
    role        TEXT NOT NULL DEFAULT 'member'
                  CHECK (role IN ('lead', 'member')),
    assigned_at TEXT NOT NULL DEFAULT (datetime('now')),
    assigned_by INTEGER REFERENCES users(id),
    notes       TEXT,
    UNIQUE (job_id, user_id)    -- one row per person per job
);

CREATE INDEX IF NOT EXISTS idx_job_team_job  ON job_team_members(job_id);
CREATE INDEX IF NOT EXISTS idx_job_team_user ON job_team_members(user_id);
