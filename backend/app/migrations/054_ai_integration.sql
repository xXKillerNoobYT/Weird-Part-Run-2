-- Migration 054: AI Integration
--
-- Phase 12 — Local AI assistant via LM Studio.
-- Adds use_ai permission and a table for cached anomaly/prediction results.
-- No new tables for AI conversations — those are ephemeral (in-memory only).

-- ── Permission: use_ai ──────────────────────────────────────────

-- Grant AI access to Admin, Manager, Lead (office + admin roles)
INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
SELECT id, 'use_ai' FROM hats WHERE name IN ('Admin', 'Manager', 'Lead');

-- ── Cached AI results ───────────────────────────────────────────
-- Anomaly detection and ordering predictions run on a schedule.
-- Results are cached here so the frontend can fetch them without
-- hitting the LLM on every page load.

CREATE TABLE IF NOT EXISTS ai_cached_results (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    result_type     TEXT NOT NULL CHECK (result_type IN ('anomaly', 'prediction', 'summary')),
    category        TEXT NOT NULL DEFAULT 'general',  -- e.g. 'labor', 'parts', 'scheduling', 'costs'
    title           TEXT NOT NULL,
    body            TEXT NOT NULL,                     -- The AI-generated text / JSON payload
    severity        TEXT CHECK (severity IN ('info', 'warning', 'critical')) DEFAULT 'info',
    context_json    TEXT,                              -- Optional structured context (job_id, employee_id, etc.)
    is_dismissed    INTEGER NOT NULL DEFAULT 0,
    dismissed_by    INTEGER REFERENCES users(id),
    dismissed_at    TEXT,
    expires_at      TEXT,                              -- Auto-expire stale results
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_ai_cached_type ON ai_cached_results(result_type);
CREATE INDEX IF NOT EXISTS idx_ai_cached_expires ON ai_cached_results(expires_at);

-- Trigger: updated_at auto-update
CREATE TRIGGER IF NOT EXISTS trg_ai_cached_results_updated_at
AFTER UPDATE ON ai_cached_results
FOR EACH ROW
BEGIN
    UPDATE ai_cached_results SET updated_at = datetime('now') WHERE id = NEW.id;
END;
