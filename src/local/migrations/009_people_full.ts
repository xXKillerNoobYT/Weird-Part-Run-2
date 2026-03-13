/**
 * Migration 009: People Full
 *
 * Adds employee companion tables:
 * - certifications — certification tracking with expiry dates
 * - wage_history — immutable pay rate audit trail
 * - employee_notes — HR-style notes per employee
 * - user_skills — skills and proficiency tracking
 * - employee_teams — global team definitions
 * - employee_team_members — team membership junction
 *
 * Also adds document_path to certifications.
 *
 * Source: backend migrations 023, 046, 033 (cert document_path)
 */

export const migration = {
  name: '009_people_full',
  sql: `
-- ═══════════════════════════════════════════════════════════════════
-- CERTIFICATIONS — tracking with expiry dates
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS certifications (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id           INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    cert_type         TEXT    NOT NULL
                      CHECK(cert_type IN (
                          'journeyman', 'apprentice', 'master',
                          'osha_10', 'osha_30',
                          'first_aid', 'cpr',
                          'forklift', 'confined_space',
                          'custom'
                      )),
    cert_name         TEXT    NOT NULL,
    issuing_authority TEXT,
    cert_number       TEXT,
    issued_date       TEXT,
    expiry_date       TEXT,
    is_active         INTEGER DEFAULT 1,
    notes             TEXT,
    document_path     TEXT,
    deleted_at        TEXT,
    created_at        TEXT    DEFAULT (datetime('now')),
    updated_at        TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_certifications_user   ON certifications(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_certifications_expiry ON certifications(expiry_date);
CREATE INDEX IF NOT EXISTS idx_certifications_type   ON certifications(cert_type);


-- ═══════════════════════════════════════════════════════════════════
-- WAGE HISTORY — immutable pay rate audit trail
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS wage_history (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id        INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    pay_rate       REAL    NOT NULL,
    effective_date TEXT    NOT NULL,
    reason         TEXT    CHECK(reason IN (
                       'hire', 'raise', 'promotion', 'demotion',
                       'adjustment', 'correction', NULL
                   )),
    changed_by     INTEGER REFERENCES users(id),
    created_at     TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_wage_history_user ON wage_history(user_id, effective_date DESC);


-- ═══════════════════════════════════════════════════════════════════
-- EMPLOYEE NOTES — HR-style record keeping
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS employee_notes (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    note_type  TEXT    DEFAULT 'general'
               CHECK(note_type IN (
                   'general', 'performance', 'incident',
                   'commendation', 'training', 'disciplinary'
               )),
    title      TEXT    NOT NULL,
    body       TEXT    NOT NULL,
    is_private INTEGER DEFAULT 0,
    created_by INTEGER REFERENCES users(id),
    deleted_at TEXT,
    created_at TEXT    DEFAULT (datetime('now')),
    updated_at TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_employee_notes_user ON employee_notes(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_employee_notes_type ON employee_notes(note_type);


-- ═══════════════════════════════════════════════════════════════════
-- USER SKILLS — proficiency tracking per employee
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS user_skills (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id          INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    skill_name       TEXT    NOT NULL,
    proficiency      TEXT    DEFAULT 'intermediate'
                     CHECK(proficiency IN (
                         'beginner', 'intermediate', 'advanced', 'expert'
                     )),
    years_experience REAL,
    verified_by      INTEGER REFERENCES users(id),
    verified_at      TEXT,
    deleted_at       TEXT,
    created_at       TEXT    DEFAULT (datetime('now')),
    UNIQUE(user_id, skill_name)
);

CREATE INDEX IF NOT EXISTS idx_user_skills_user  ON user_skills(user_id);
CREATE INDEX IF NOT EXISTS idx_user_skills_skill ON user_skills(skill_name);


-- ═══════════════════════════════════════════════════════════════════
-- EMPLOYEE TEAMS — global team definitions
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS employee_teams (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    name         TEXT NOT NULL UNIQUE,
    description  TEXT,
    lead_user_id INTEGER REFERENCES users(id),
    is_active    INTEGER NOT NULL DEFAULT 1,
    deleted_at   TEXT,
    created_at   TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at   TEXT NOT NULL DEFAULT (datetime('now'))
);


-- ═══════════════════════════════════════════════════════════════════
-- EMPLOYEE TEAM MEMBERS — team membership junction
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS employee_team_members (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    team_id   INTEGER NOT NULL REFERENCES employee_teams(id) ON DELETE CASCADE,
    user_id   INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role      TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('lead', 'member')),
    joined_at  TEXT NOT NULL DEFAULT (datetime('now')),
    deleted_at TEXT,
    UNIQUE(team_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_team_members_team ON employee_team_members(team_id);
CREATE INDEX IF NOT EXISTS idx_team_members_user ON employee_team_members(user_id);
  `,
};
