/**
 * Migration 004: Notebooks
 *
 * Templates, notebooks, sections, entries, permissions, task-order links.
 * Consolidated from: backend migration 013
 */

export const migration = {
  name: '004_notebooks',
  sql: `
-- ─── NOTEBOOK TEMPLATES ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS notebook_templates (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL,
    description TEXT,
    job_type    TEXT,
    is_default  INTEGER NOT NULL DEFAULT 0,
    created_by  INTEGER REFERENCES users(id),
    created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS template_sections (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    template_id  INTEGER NOT NULL REFERENCES notebook_templates(id) ON DELETE CASCADE,
    name         TEXT    NOT NULL,
    section_type TEXT    NOT NULL DEFAULT 'notes'
        CHECK (section_type IN ('info','notes','tasks')),
    sort_order   INTEGER NOT NULL DEFAULT 0,
    is_locked    INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS template_entries (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    section_id     INTEGER NOT NULL REFERENCES template_sections(id) ON DELETE CASCADE,
    title          TEXT    NOT NULL,
    default_content TEXT,
    entry_type     TEXT    NOT NULL DEFAULT 'note'
        CHECK (entry_type IN ('note','task','field')),
    field_type     TEXT    CHECK (field_type IN ('text','checkbox','textarea')),
    field_required INTEGER NOT NULL DEFAULT 0,
    sort_order     INTEGER NOT NULL DEFAULT 0
);

-- ─── NOTEBOOKS ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notebooks (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    title       TEXT    NOT NULL,
    description TEXT,
    job_id      INTEGER REFERENCES jobs(id),
    template_id INTEGER REFERENCES notebook_templates(id),
    created_by  INTEGER NOT NULL REFERENCES users(id),
    is_archived INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_notebooks_job ON notebooks(job_id);

-- ─── NOTEBOOK SECTIONS ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS notebook_sections (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    notebook_id  INTEGER NOT NULL REFERENCES notebooks(id) ON DELETE CASCADE,
    name         TEXT    NOT NULL,
    section_type TEXT    NOT NULL DEFAULT 'notes'
        CHECK (section_type IN ('info','notes','tasks')),
    sort_order   INTEGER NOT NULL DEFAULT 0,
    is_locked    INTEGER NOT NULL DEFAULT 0,
    created_at   TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_nb_sections_notebook ON notebook_sections(notebook_id);

-- ─── NOTEBOOK ENTRIES ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS notebook_entries (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    section_id       INTEGER NOT NULL REFERENCES notebook_sections(id) ON DELETE CASCADE,
    title            TEXT    NOT NULL,
    content          TEXT,
    entry_type       TEXT    NOT NULL DEFAULT 'note'
        CHECK (entry_type IN ('note','task','field')),
    field_type       TEXT    CHECK (field_type IN ('text','checkbox','textarea')),
    field_required   INTEGER NOT NULL DEFAULT 0,
    field_filled_by  INTEGER REFERENCES users(id),
    task_status      TEXT
        CHECK (task_status IN ('planned','parts_ordered','parts_delivered','in_progress','done')),
    task_due_date    TEXT,
    task_assigned_to INTEGER REFERENCES users(id),
    task_parts_note  TEXT,
    created_by       INTEGER NOT NULL REFERENCES users(id),
    updated_by       INTEGER REFERENCES users(id),
    is_deleted       INTEGER NOT NULL DEFAULT 0,
    deleted_by       INTEGER REFERENCES users(id),
    deleted_at       TEXT,
    sort_order       INTEGER NOT NULL DEFAULT 0,
    created_at       TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at       TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_nb_entries_section ON notebook_entries(section_id);
CREATE INDEX IF NOT EXISTS idx_nb_entries_task_status ON notebook_entries(task_status)
    WHERE entry_type = 'task' AND is_deleted = 0;

-- ─── ENTRY PERMISSIONS ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS notebook_entry_permissions (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id   INTEGER NOT NULL REFERENCES notebook_entries(id) ON DELETE CASCADE,
    user_id    INTEGER NOT NULL REFERENCES users(id),
    granted_by INTEGER NOT NULL REFERENCES users(id),
    granted_at TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE(entry_id, user_id)
);

-- ─── TASK-ORDER LINKS ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS task_order_links (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id   INTEGER NOT NULL REFERENCES notebook_entries(id) ON DELETE CASCADE,
    po_id      INTEGER,
    status     TEXT    DEFAULT 'linked',
    created_at TEXT    NOT NULL DEFAULT (datetime('now'))
);
  `,
};
