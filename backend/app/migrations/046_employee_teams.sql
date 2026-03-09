-- Migration 046: Global Employee Teams
-- Adds reusable team definitions for bulk job assignment / dispatch.
-- job_team_members (037) handles per-job assignment; this adds global team management.

-- ─── Employee Teams ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS employee_teams (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    name            TEXT NOT NULL UNIQUE,
    description     TEXT,
    lead_user_id    INTEGER REFERENCES users(id),
    is_active       INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ─── Team Membership ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS employee_team_members (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    team_id         INTEGER NOT NULL REFERENCES employee_teams(id) ON DELETE CASCADE,
    user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role            TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('lead', 'member')),
    joined_at       TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(team_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_team_members_team ON employee_team_members(team_id);
CREATE INDEX IF NOT EXISTS idx_team_members_user ON employee_team_members(user_id);

-- ─── Updated-at trigger ─────────────────────────────────────────
CREATE TRIGGER IF NOT EXISTS trg_employee_teams_updated_at
    AFTER UPDATE ON employee_teams
    FOR EACH ROW
BEGIN
    UPDATE employee_teams SET updated_at = datetime('now') WHERE id = OLD.id;
END;
