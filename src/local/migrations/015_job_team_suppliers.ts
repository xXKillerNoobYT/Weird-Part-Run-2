/**
 * Migration 015: Job Team Members & Preferred Suppliers
 *
 * Tables ported from:
 * - backend/app/migrations/037_job_team_members.sql
 * - Preferred suppliers (stored in job_preferences with preference_type = 'supplier')
 *   but explicit preferred suppliers need a dedicated table for rank ordering.
 */

export const migration = {
  name: '015_job_team_suppliers',
  sql: `
-- ─── JOB TEAM MEMBERS ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS job_team_members (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id      INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    user_id     INTEGER NOT NULL REFERENCES users(id),
    role        TEXT    NOT NULL DEFAULT 'member'
                  CHECK (role IN ('lead', 'member')),
    assigned_at TEXT    NOT NULL DEFAULT (datetime('now')),
    assigned_by INTEGER REFERENCES users(id),
    notes       TEXT,
    deleted_at  TEXT,
    UNIQUE (job_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_jtm_job ON job_team_members(job_id);
CREATE INDEX IF NOT EXISTS idx_jtm_user ON job_team_members(user_id);

-- ─── EXPLICIT PREFERRED SUPPLIERS PER JOB ─────────────────────
-- Separate from job_preferences which tracks auto-learned prefs.
-- This stores manually-set supplier rankings (primary, backup1, backup2).
CREATE TABLE IF NOT EXISTS job_preferred_suppliers (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id      INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    supplier_id INTEGER NOT NULL REFERENCES suppliers(id),
    rank        INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
    deleted_at  TEXT,
    UNIQUE (job_id, supplier_id)
);
CREATE INDEX IF NOT EXISTS idx_jps_job ON job_preferred_suppliers(job_id);
  `,
};
