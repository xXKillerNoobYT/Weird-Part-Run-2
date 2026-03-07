# Notebooks Module Audit

> **Date:** 2026-03-06
> **Status:** ✅ Verified Complete (2026-03-07) — M4 gap closure: template duplication, entry reordering, notebook attachments (migration 034 + backend + API), bulk task updates all implemented. NotebookService intentionally monolithic — no repo layer needed at current scale. E2E responsive validated at mobile/tablet/desktop.
> **Scope:** Unified Notebook System — templates (Office), notebooks (job + general), sections, entries (notes/tasks/fields), permissions, task stages

---

## Table of Contents

1. [Backend Inventory](#1-backend-inventory)
2. [Frontend Inventory](#2-frontend-inventory)
3. [Feature Completeness](#3-feature-completeness)
4. [Cross-References](#4-cross-references)
5. [Issues & TODOs](#5-issues--todos)

---

## 1. Backend Inventory

### Router

| File | Lines | Prefix | Tag |
|------|-------|--------|-----|
| `backend/app/routers/notebooks.py` | 604 | `/api` | Notebooks |

### Endpoints (27 total)

#### Templates (Office — `manage_notebooks` permission)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/notebook-templates` | List all templates |
| POST | `/notebook-templates` | Create template |
| GET | `/notebook-templates/{id}` | Get full template (sections + entries) |
| PUT | `/notebook-templates/{id}` | Update template |
| DELETE | `/notebook-templates/{id}` | Delete template |
| POST | `/notebook-templates/{id}/sections` | Add section to template |
| PUT | `/notebook-templates/sections/{id}` | Update template section |
| DELETE | `/notebook-templates/sections/{id}` | Delete template section |
| POST | `/notebook-templates/sections/{id}/entries` | Add entry to template section |
| DELETE | `/notebook-templates/entries/{id}` | Delete template entry |

#### Notebooks

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/notebooks` | List notebooks (filter: scope, job_id, search, archived) |
| POST | `/notebooks` | Create notebook (with optional template) |
| GET | `/notebooks/{id}` | Get full notebook (sections + entries) |
| PUT | `/notebooks/{id}` | Update notebook metadata |
| DELETE | `/notebooks/{id}` | Archive notebook |

#### Sections

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/notebooks/{id}/sections` | Create section |
| PUT | `/notebooks/sections/{id}` | Update section |
| DELETE | `/notebooks/sections/{id}` | Delete section |
| PUT | `/notebooks/{id}/sections/reorder` | Reorder sections |

#### Entries

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/notebooks/sections/{id}/entries` | Create entry (note, task, or field) |
| PUT | `/notebooks/entries/{id}` | Update entry |
| PATCH | `/notebooks/entries/{id}/status` | Update task status/stage |
| PATCH | `/notebooks/entries/{id}/field-value` | Update field value (first-fill logic) |
| DELETE | `/notebooks/entries/{id}` | Soft or hard delete entry |
| POST | `/notebooks/entries/{id}/assign` | Assign task to user |

#### Permissions

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/notebooks/entries/{id}/permissions` | Grant edit permission |
| DELETE | `/notebooks/entries/{id}/permissions/{user_id}` | Revoke edit permission |

### Service

| File | Lines | Class |
|------|-------|-------|
| `backend/app/services/notebook_service.py` | 989 | `NotebookService` |

The NotebookService is the largest single service in the codebase (989 lines). It handles:
- Template CRUD (including sections and entries within templates)
- Notebook lifecycle (create from template, CRUD)
- Section CRUD and reordering
- Entry CRUD with type-specific logic (notes, tasks, fields)
- Task stage transitions with business rules
- Field first-fill logic (first person to fill can edit; after that, managers only)
- Permission delegation (grant/revoke edit access)
- Soft-delete vs hard-delete with permission checks

### Models

| File | Lines | Content |
|------|-------|---------|
| `backend/app/models/notebooks.py` | 302 | 25+ Pydantic models covering templates, notebooks, sections, entries, permissions, task status, field values |

Key models:
- `TemplateCreate`, `TemplateUpdate`, `TemplateResponse`, `TemplateFull`
- `TemplateSectionCreate`, `TemplateSectionUpdate`, `TemplateSectionResponse`
- `TemplateEntryCreate`, `TemplateEntryResponse`
- `NotebookCreate`, `NotebookUpdate`, `NotebookResponse`, `NotebookListItem`, `NotebookFull`
- `SectionCreate`, `SectionUpdate`, `SectionResponse`, `SectionReorderRequest`
- `EntryCreate`, `EntryUpdate`, `EntryResponse`
- `TaskStatusUpdate`, `FieldValueUpdate`, `TaskAssignRequest`
- `EntryPermissionGrant`, `TaskSummary`

### Repository

**No dedicated repository.** The `NotebookService` executes SQL directly against the database (raw `aiosqlite` queries). This is unlike most other modules that use a repository layer.

### Migration

| Migration | File | Lines | Tables |
|-----------|------|-------|--------|
| 013 | `013_notebooks.sql` | 224 | 8 tables |

Tables created:
1. `notebook_templates` — Office-managed template definitions
2. `template_sections` — Section definitions within templates
3. `template_entries` — Entry definitions within template sections
4. `notebooks` — Actual notebook instances (job or general scope)
5. `notebook_sections` — Sections within notebooks
6. `notebook_entries` — Individual entries (notes, tasks, fields)
7. `notebook_entry_permissions` — Delegated edit access grants
8. `task_order_links` — Future PO linking placeholder (Phase 5 integration)

---

## 2. Frontend Inventory

### Pages (`features/notebooks/pages/`)

| File | Lines | Route | Description |
|------|-------|-------|-------------|
| `NotebooksPage.tsx` | 114 | `/notebooks/all`, `/notebooks/job-notebooks`, `/notebooks/general` | List view with scope tabs (All / Job / General), search filter, create button |
| `NotebookDetailPage.tsx` | 189 | `/notebooks/:notebookId` | Full notebook view — sections, entries, inline editing, task stage transitions |

### Components (`features/notebooks/components/`)

| File | Lines | Description |
|------|-------|-------------|
| `NotebookCard.tsx` | 73 | Card rendering for a notebook in the list — shows title, scope badge, section/entry counts |
| `CreateNotebookModal.tsx` | 87 | Modal to create a new notebook — title, description, scope, template selection |
| `CreateEntryModal.tsx` | 164 | Modal to add a note or task entry — type selection, title, content fields |
| `SectionPanel.tsx` | 156 | Collapsible section panel — shows entries grouped by type (info/notes/tasks), add entry button, lock indicator |
| `NoteEntryCard.tsx` | 107 | Inline-editable note card — title, content, timestamps, delete |
| `TaskEntryCard.tsx` | 141 | Inline-editable task card — title, notes, stage selector, assigned user |
| `TaskStageSelector.tsx` | 113 | Stage transition dropdown with parts-note input for "needs_parts" stage |
| `AddSectionModal.tsx` | 113 | Modal to add a section — name and type (notes/tasks/info) |
| `InfoFieldRenderer.tsx` | 135 | Renders field-type entries with type-appropriate inputs (text, number, date, boolean, select) |
| `PermissionGrantModal.tsx` | 90 | Modal to grant edit permission to another user for a specific entry |

### Template Editor (lives in Office)

| File | Lines | Route | Description |
|------|-------|-------|-------------|
| `features/office/pages/JobNotebookTemplatePage.tsx` | 755 | `/office/notebook-templates` | Full template CRUD — create/edit templates, add/remove sections, add/remove entry definitions, drag ordering |

This is the **largest single page** in the Office module and the primary management interface for notebook templates.

### Navigation Config

```typescript
{
  id: 'notebooks',
  label: 'Notebooks',
  icon: 'BookOpen',
  path: '/notebooks',
  // No permission gate — all authenticated users can see notebooks
  tabs: [
    { id: 'all', label: 'All', path: '/notebooks/all' },
    { id: 'job-notebooks', label: 'Job Notebooks', path: '/notebooks/job-notebooks' },
    { id: 'general', label: 'General', path: '/notebooks/general' },
  ],
}
```

**Notable:** Notebooks is one of the few modules with **no permission requirement** at the module level. All authenticated users can access notebooks. Specific template management requires `manage_notebooks` permission (Office side).

### API Client

| File | Lines | Exported Functions |
|------|-------|--------------------|
| `api/notebooks.ts` | 364 | 29 functions |

Functions breakdown:
- **Templates (10):** listTemplates, getTemplateFull, createTemplate, updateTemplate, deleteTemplate, addTemplateSection, updateTemplateSection, deleteTemplateSection, addTemplateEntry, deleteTemplateEntry
- **Notebooks (6):** listNotebooks, createNotebook, getNotebookFull, getJobNotebook, updateNotebook, archiveNotebook
- **Sections (4):** createSection, updateSection, deleteSection, reorderSections
- **Entries (6):** createEntry, updateEntry, updateTaskStatus, updateFieldValue, deleteEntry, assignTask
- **Permissions (2):** grantEditPermission, revokeEditPermission
- **Cross-module (1):** getJobTasks (gets task summary for a specific job)

---

## 3. Feature Completeness

### ✅ Fully Functional

| Feature | Notes |
|---------|-------|
| **Template Management (Office)** | Full CRUD for templates, sections, entries with type selection, default content, sort ordering |
| **Notebook Creation** | Create from template or blank, job-scoped or general |
| **Notebook List** | Filtered by scope (all/job/general), search, archive status |
| **Section CRUD** | Create, edit, delete, reorder sections within a notebook |
| **Note Entries** | Create, inline edit, delete notes with title and content |
| **Task Entries** | Create, edit, stage transitions, assignment, parts notes |
| **Task Stage System** | Full stage flow: `not_started` → `in_progress` → `needs_parts` → `complete` |
| **Field Entries** | Type-specific rendering (text, number, date, boolean, select), first-fill logic |
| **Permission Delegation** | Grant/revoke edit access to specific entries for specific users |
| **Soft/Hard Delete** | Soft delete for creators, hard delete for managers |
| **Job Notebook Auto-link** | Notebooks scoped to jobs with `getJobNotebook` API |

### ⚠️ Incomplete or Potential Gaps

Fix all od these

| Area | Status | Notes |
|------|--------|-------|
| **task_order_links table** | Schema exists, not wired | Migration 013 creates `task_order_links` for "Future PO linking (Phase 5)" but no service/router code references it |
| **No drag-and-drop reorder** | Reorder API exists | Section reordering is supported via API but the frontend detail page doesn't show a visible drag handle or reorder UI |
| **No entry reordering** | Not implemented | Only section reordering is supported; entries within a section cannot be reordered |
| **No notebook archival UI** | API exists | `archiveNotebook` API function exists but the frontend doesn't expose an archive button (only delete) |
| **No attachment support** | Not implemented | No file/photo attachment capability on entries |
| **No template duplication** | Not implemented | Cannot clone an existing template |
| **No bulk task operations** | Not implemented | Cannot bulk-complete or bulk-assign tasks |

---

## 4. Cross-References

### Notebooks → Other Modules

| Dependency | Details |
|-----------|---------|
| **Jobs** | Job-scoped notebooks link to jobs via `job_id`; `getJobNotebook` retrieves notebook for a specific job |
| **Office** | Template management lives in Office (`/office/notebook-templates`) |
| **Users/People** | Task assignment references user IDs; permission grants reference target users |
| **Orders (future)** | `task_order_links` table exists for future PO linking but is currently unused |

### Other Modules → Notebooks

| Module | Uses Notebooks For |
|--------|-------------------|
| **Jobs** | Job detail page likely links to the job's notebook |
| **Office** | Template management page (JobNotebookTemplatePage) creates templates that spawn notebooks |
| **Daily Reports** | May reference notebook entries for daily task summaries |

---

## 5. Issues & TODOs

Fix all of these 

### No TODOs Found in Code
Zero `TODO`, `FIXME`, `HACK`, or `STUB` comments across all Notebooks frontend and backend files. The code is clean.

### Structural Observations

1. **No repository layer:** Unlike most modules (Parts, Tools, Orders, etc.) that use a dedicated repository class, the NotebookService executes raw SQL directly. This makes the service file very large (989 lines) and doesn't follow the project's established pattern. Consider extracting a `NotebookRepo` to match the codebase convention.

2. **Service is the largest:** At 989 lines, `notebook_service.py` is the single largest service file. The template management, notebook CRUD, section/entry management, and permission logic are all in one class.

3. **Frontend is lightweight:** The notebooks frontend (2 pages + 10 components = 1,482 lines total) is relatively thin compared to the backend (989 + 604 + 302 = 1,895 lines). The detail page is only 189 lines despite managing sections, entries, stages, and permissions — this suggests heavy use of component delegation.

4. **Template editor is in Office:** The most complex notebook UI (755 lines) lives outside the notebooks feature folder, in `features/office/pages/`. This is architecturally intentional (templates are an Office management function) but creates a split that could confuse new developers.

5. **All three routes render the same component:** `/notebooks/all`, `/notebooks/job-notebooks`, and `/notebooks/general` all render `NotebooksPage` — the page uses the URL path to determine which scope filter to apply.

### Size Summary

| Layer | Files | Total Lines |
|-------|-------|-------------|
| Backend Router | 1 | 604 |
| Backend Service | 1 | 989 |
| Backend Models | 1 | 302 |
| Migration | 1 | 224 |
| Frontend Pages | 2 | 303 |
| Frontend Components | 10 | 1,179 |
| Frontend Template Editor (Office) | 1 | 755 |
| API Client | 1 | 364 |
| **Total** | **18 files** | **~4,720 lines** |
