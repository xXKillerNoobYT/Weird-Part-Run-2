-- ═══════════════════════════════════════════════════════════════════
-- Phase 4.5 — Unified Notebook System
--
-- 8 tables:
--   1. notebook_templates        — Office-managed templates
--   2. template_sections         — Section definitions inside templates
--   3. template_entries          — Entry definitions inside template sections
--   4. notebooks                 — Actual notebooks (job or general)
--   5. notebook_sections         — Sections inside notebooks
--   6. notebook_entries          — Entries (notes, tasks, fields)
--   7. notebook_entry_permissions — Delegated edit access
--   8. task_order_links          — Future PO linking (Phase 5)
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════
-- NOTEBOOK TEMPLATES (managed in Office)
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS notebook_templates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    description TEXT,
    job_type TEXT,                    -- link to job_type, NULL = universal
    is_default INTEGER NOT NULL DEFAULT 0,
    created_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS template_sections (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    template_id INTEGER NOT NULL REFERENCES notebook_templates(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    section_type TEXT NOT NULL DEFAULT 'notes'
        CHECK (section_type IN ('info', 'notes', 'tasks')),
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_locked INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS template_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    section_id INTEGER NOT NULL REFERENCES template_sections(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    default_content TEXT,
    entry_type TEXT NOT NULL DEFAULT 'note'
        CHECK (entry_type IN ('note', 'task', 'field')),
    field_type TEXT CHECK (field_type IN ('text', 'checkbox', 'textarea')),
    field_required INTEGER NOT NULL DEFAULT 0,
    sort_order INTEGER NOT NULL DEFAULT 0
);


-- ═══════════════════════════════════════════════
-- NOTEBOOKS
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS notebooks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT,
    job_id INTEGER REFERENCES jobs(id),        -- NULL = general notebook
    template_id INTEGER REFERENCES notebook_templates(id),
    created_by INTEGER NOT NULL REFERENCES users(id),
    is_archived INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_notebooks_job ON notebooks(job_id);


-- ═══════════════════════════════════════════════
-- SECTIONS
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS notebook_sections (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    notebook_id INTEGER NOT NULL REFERENCES notebooks(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    section_type TEXT NOT NULL DEFAULT 'notes'
        CHECK (section_type IN ('info', 'notes', 'tasks')),
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_locked INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_nb_sections_notebook ON notebook_sections(notebook_id);


-- ═══════════════════════════════════════════════
-- ENTRIES (notes, tasks, and form fields)
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS notebook_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    section_id INTEGER NOT NULL REFERENCES notebook_sections(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    content TEXT,                               -- text / field value / task notes
    entry_type TEXT NOT NULL DEFAULT 'note'
        CHECK (entry_type IN ('note', 'task', 'field')),
    -- Field-specific (entry_type = 'field')
    field_type TEXT CHECK (field_type IN ('text', 'checkbox', 'textarea')),
    field_required INTEGER NOT NULL DEFAULT 0,
    field_filled_by INTEGER REFERENCES users(id),  -- first person to fill (locks for non-managers)
    -- Task-specific (entry_type = 'task')
    task_status TEXT
        CHECK (task_status IN ('planned','parts_ordered','parts_delivered','in_progress','done')),
    task_due_date TEXT,
    task_assigned_to INTEGER REFERENCES users(id),
    task_parts_note TEXT,              -- what parts are needed (filled when marking parts_ordered)
    -- Authorship
    created_by INTEGER NOT NULL REFERENCES users(id),
    updated_by INTEGER REFERENCES users(id),
    -- Soft delete
    is_deleted INTEGER NOT NULL DEFAULT 0,
    deleted_by INTEGER REFERENCES users(id),
    deleted_at TEXT,
    -- Ordering & timestamps
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_nb_entries_section ON notebook_entries(section_id);
CREATE INDEX IF NOT EXISTS idx_nb_entries_type ON notebook_entries(entry_type);
CREATE INDEX IF NOT EXISTS idx_nb_entries_task_status ON notebook_entries(task_status)
    WHERE entry_type = 'task' AND is_deleted = 0;


-- ═══════════════════════════════════════════════
-- ENTRY PERMISSIONS (delegated edit access)
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS notebook_entry_permissions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id INTEGER NOT NULL REFERENCES notebook_entries(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id),
    granted_by INTEGER NOT NULL REFERENCES users(id),
    granted_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(entry_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_nb_perms_entry ON notebook_entry_permissions(entry_id);


-- ═══════════════════════════════════════════════
-- TASK-TO-ORDER LINKS (future — Phase 5 PO system)
-- Many-to-many: one task can need parts from multiple POs,
-- one PO can cover parts for multiple tasks.
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS task_order_links (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id INTEGER NOT NULL REFERENCES notebook_entries(id) ON DELETE CASCADE,
    po_id INTEGER,                   -- will REFERENCES purchase_orders(id) in Phase 5
    status TEXT DEFAULT 'linked',    -- linked, delivered, cancelled
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_tol_entry ON task_order_links(entry_id);
CREATE INDEX IF NOT EXISTS idx_tol_po ON task_order_links(po_id);


-- ═══════════════════════════════════════════════
-- PERMISSION: manage_notebooks (for template management)
-- ═══════════════════════════════════════════════

INSERT OR IGNORE INTO permissions (name, description)
VALUES ('manage_notebooks', 'Create and edit notebook templates, edit any notebook entry');


-- ═══════════════════════════════════════════════
-- SEED: Default Job Notebook Template
-- ═══════════════════════════════════════════════

INSERT INTO notebook_templates (name, description, is_default, created_by)
VALUES ('Standard Job Notebook', 'Default template for all job types', 1, 1);

-- Section 1: Job Info (structured form fields, locked)
INSERT INTO template_sections (template_id, name, section_type, sort_order, is_locked)
VALUES (
    (SELECT id FROM notebook_templates WHERE name = 'Standard Job Notebook'),
    'Job Info', 'info', 0, 1
);

INSERT INTO template_entries (section_id, title, entry_type, field_type, field_required, sort_order) VALUES
    ((SELECT id FROM template_sections WHERE name = 'Job Info'), 'Door / Gate Code',                   'field', 'text',     0, 0),
    ((SELECT id FROM template_sections WHERE name = 'Job Info'), 'Alarm Code',                         'field', 'text',     0, 1),
    ((SELECT id FROM template_sections WHERE name = 'Job Info'), 'WiFi Password',                      'field', 'text',     0, 2),
    ((SELECT id FROM template_sections WHERE name = 'Job Info'), 'Owner Contact Name',                 'field', 'text',     0, 3),
    ((SELECT id FROM template_sections WHERE name = 'Job Info'), 'Owner Contact Phone',                'field', 'text',     0, 4),
    ((SELECT id FROM template_sections WHERE name = 'Job Info'), 'Owner Happy For People To Show Up',  'field', 'checkbox', 0, 5),
    ((SELECT id FROM template_sections WHERE name = 'Job Info'), 'Preferred Arrival Time',             'field', 'text',     0, 6),
    ((SELECT id FROM template_sections WHERE name = 'Job Info'), 'Site Access Hours',                  'field', 'text',     0, 7),
    ((SELECT id FROM template_sections WHERE name = 'Job Info'), 'Key Location',                       'field', 'text',     0, 8),
    ((SELECT id FROM template_sections WHERE name = 'Job Info'), 'Has Dog',                            'field', 'checkbox', 0, 9),
    ((SELECT id FROM template_sections WHERE name = 'Job Info'), 'Parking Instructions',               'field', 'textarea', 0, 10),
    ((SELECT id FROM template_sections WHERE name = 'Job Info'), 'Special Access Notes',               'field', 'textarea', 0, 11);

-- Section 2: General Notes (free-form)
INSERT INTO template_sections (template_id, name, section_type, sort_order)
VALUES (
    (SELECT id FROM notebook_templates WHERE name = 'Standard Job Notebook'),
    'General Notes', 'notes', 1
);

-- Section 3: Daily Logs (locked, auto-populated by daily reports)
INSERT INTO template_sections (template_id, name, section_type, sort_order, is_locked)
VALUES (
    (SELECT id FROM notebook_templates WHERE name = 'Standard Job Notebook'),
    'Daily Logs', 'notes', 2, 1
);

-- Section 4: General Tasks
INSERT INTO template_sections (template_id, name, section_type, sort_order)
VALUES (
    (SELECT id FROM notebook_templates WHERE name = 'Standard Job Notebook'),
    'General Tasks', 'tasks', 3
);

-- Section 5: Punch List
INSERT INTO template_sections (template_id, name, section_type, sort_order)
VALUES (
    (SELECT id FROM notebook_templates WHERE name = 'Standard Job Notebook'),
    'Punch List', 'tasks', 4
);
