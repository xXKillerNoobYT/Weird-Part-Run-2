-- =============================================================
-- MIGRATION 023: People (Full)
-- =============================================================
-- Adds 4 companion tables for the People module:
--   certifications  — certification tracking with expiry dates
--   wage_history    — pay rate audit trail
--   employee_notes  — HR-style notes per employee
--   user_skills     — skills and proficiency tracking
--
-- These all reference the existing `users` table from migration 001.
-- =============================================================


-- ─── CERTIFICATIONS ───────────────────────────────────────────
-- Tracks certifications, licenses, and training completions.
-- Supports expiry-date alerting (amber < 60 days, red < 30 days).
CREATE TABLE IF NOT EXISTS certifications (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id             INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    cert_type           TEXT    NOT NULL
                        CHECK(cert_type IN (
                            'journeyman', 'apprentice', 'master',
                            'osha_10', 'osha_30',
                            'first_aid', 'cpr',
                            'forklift', 'confined_space',
                            'custom'
                        )),
    cert_name           TEXT    NOT NULL,          -- display name, e.g. "OSHA 30-Hour"
    issuing_authority   TEXT,                       -- "OSHA", "Red Cross", etc.
    cert_number         TEXT,                       -- credential number
    issued_date         TEXT,                       -- ISO date
    expiry_date         TEXT,                       -- NULL = never expires
    is_active           INTEGER DEFAULT 1,
    notes               TEXT,
    created_at          TEXT    DEFAULT (datetime('now')),
    updated_at          TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_certifications_user    ON certifications(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_certifications_expiry  ON certifications(expiry_date);
CREATE INDEX IF NOT EXISTS idx_certifications_type    ON certifications(cert_type);


-- ─── WAGE HISTORY ─────────────────────────────────────────────
-- Immutable audit trail of pay rate changes.
-- Each insert also updates users.pay_rate to the new value.
CREATE TABLE IF NOT EXISTS wage_history (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    pay_rate        REAL    NOT NULL,
    effective_date  TEXT    NOT NULL,               -- ISO date: when this rate takes effect
    reason          TEXT    CHECK(reason IN (
                        'hire', 'raise', 'promotion', 'demotion',
                        'adjustment', 'correction', NULL
                    )),
    changed_by      INTEGER REFERENCES users(id),  -- who made the change
    created_at      TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_wage_history_user ON wage_history(user_id, effective_date DESC);


-- ─── EMPLOYEE NOTES ───────────────────────────────────────────
-- HR-style record keeping. Notes can be flagged as private
-- (only visible to users with manage_people permission).
CREATE TABLE IF NOT EXISTS employee_notes (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    note_type   TEXT    DEFAULT 'general'
                CHECK(note_type IN (
                    'general', 'performance', 'incident',
                    'commendation', 'training', 'disciplinary'
                )),
    title       TEXT    NOT NULL,
    body        TEXT    NOT NULL,
    is_private  INTEGER DEFAULT 0,                 -- 1 = manage_people eyes only
    created_by  INTEGER REFERENCES users(id),
    created_at  TEXT    DEFAULT (datetime('now')),
    updated_at  TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_employee_notes_user ON employee_notes(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_employee_notes_type ON employee_notes(note_type);


-- ─── USER SKILLS ──────────────────────────────────────────────
-- Tracks skills and proficiency levels per employee.
-- One row per (user, skill_name) — UNIQUE constraint enforced.
CREATE TABLE IF NOT EXISTS user_skills (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id          INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    skill_name       TEXT    NOT NULL,
    proficiency      TEXT    DEFAULT 'intermediate'
                     CHECK(proficiency IN (
                         'beginner', 'intermediate', 'advanced', 'expert'
                     )),
    years_experience REAL,                          -- decimal years
    verified_by      INTEGER REFERENCES users(id),  -- who verified this skill
    verified_at      TEXT,                           -- when verified
    created_at       TEXT    DEFAULT (datetime('now')),
    UNIQUE(user_id, skill_name)
);

CREATE INDEX IF NOT EXISTS idx_user_skills_user  ON user_skills(user_id);
CREATE INDEX IF NOT EXISTS idx_user_skills_skill ON user_skills(skill_name);
