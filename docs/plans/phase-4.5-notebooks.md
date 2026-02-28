# Phase 4.5 — Unified Notebook System

## Context

The app needs a **notebook system** serving two purposes:

1. **Job Notebooks** — every job (active, on_call, warranty, completed, cancelled) gets a notebook auto-created from a template with structured info fields, free-form notes, and task/todo tracking.
2. **General Notebooks** — standalone notebooks for company-wide notes, procedures, etc.

**Core design decisions (confirmed with user):**

| Decision | Choice |
|----------|--------|
| Todo system | Integrated INTO notebooks (not separate). Task entries with 5 stages. |
| Task stages | Planned → Parts Ordered → Parts Delivered → In Progress → Done |
| Parts note | Text field on task when marking "Parts Ordered" (describe what's needed) |
| Job visibility | On Call/Warranty with open tasks dual-listed in Active with badges |
| All-tasks-done | Shows "Ready to Complete" badge. Office manually marks job complete. |
| Waiting on parts | On-hold/warranty jobs waiting on parts STILL show in Active with amber badge |
| On Call/Warranty | Open tasks → job also appears in Active list (dual listing) |
| Notebook scope | ALL jobs get notebooks (including completed/cancelled — for reference) |
| Existing jobs | Notebooks created lazily on first access (no bulk migration) |
| Template format | Hybrid: structured form fields (Job Info) + free-form notes + task sections |
| Info field editing | First fill by anyone; once filled, only managers can change |
| Task creation | Anyone creates tasks; only managers assign to specific workers. Workers can self-assign. |
| Task-to-PO linking | Manual stage transitions for now; PO linking table created but unused until Phase 5 |
| Completed jobs | Notebooks always editable (workers can add info if returning to site) |
| Permissions | OneNote-like: all viewable, creator edits own, managers edit all, delegated edit, soft/hard delete |
| Default tab | JobDetailPage opens to Notebook tab first (field worker priority) |
| Templates location | Office module ("Job Notebook Templates") — not in Jobs |
| Todo sections | Template provides defaults + workers can add custom sections (by room, area, etc.) |
| Todos in notebook | Tasks are ALWAYS visible within the notebook — never hidden or filtered out |

Full plan details in `.claude/plans/quizzical-wobbling-garden.md`.

## Implementation Order

| # | Task | Depends On |
|---|------|-----------|
| 1 | Migration `013_notebooks.sql` (8 tables + seed) | — |
| 2 | `models/notebooks.py` | — |
| 3 | `services/notebook_service.py` | 1, 2 |
| 4 | `routers/notebooks.py` + job shortcuts | 3 |
| 5 | Register router in `main.py` | 4 |
| 6 | Modify `job_service.py` — add task-based job visibility + open_task_count | 3 |
| 7 | Add `open_task_count` to job models | 6 |
| 8 | Frontend types in `types.ts` | 2 |
| 9 | `api/notebooks.ts` | 8 |
| 10 | Notebook components (11 components) | 9 |
| 11-14 | Pages (Notebooks, Detail, Templates, JobDetail tab) | 10 |
| 15 | Task badges on ActiveJobsPage + ManageJobsPage | 7 |
| 16 | Navigation + routes | 11-14 |
| 17 | Verify: `tsc --noEmit`, `vite build`, visual test | All |

## Files

| File | Action |
|------|--------|
| `backend/app/migrations/013_notebooks.sql` | **NEW** — 8 tables + indexes + seed |
| `backend/app/models/notebooks.py` | **NEW** — template + notebook + entry models |
| `backend/app/services/notebook_service.py` | **NEW** — full CRUD + permissions |
| `backend/app/routers/notebooks.py` | **NEW** — all endpoints |
| `backend/app/routers/jobs.py` | **MODIFY** — add `/jobs/{id}/notebook` and `/jobs/{id}/tasks` |
| `backend/app/services/job_service.py` | **MODIFY** — task-based job visibility |
| `backend/app/models/jobs.py` | **MODIFY** — add `open_task_count`, `task_summary` |
| `backend/app/main.py` | **MODIFY** — register notebooks router |
| `frontend/src/lib/types.ts` | **MODIFY** — add notebook types |
| `frontend/src/lib/navigation.ts` | **MODIFY** — add notebooks module |
| `frontend/src/App.tsx` | **MODIFY** — add routes |
| `frontend/src/api/notebooks.ts` | **NEW** — all API functions |
| `frontend/src/features/notebooks/` | **NEW** — 2 pages, 11 components |
| `frontend/src/features/office/pages/JobNotebookTemplatePage.tsx` | **NEW** |
| `frontend/src/features/jobs/pages/JobDetailPage.tsx` | **MODIFY** — Notebook tab |
| `frontend/src/features/jobs/pages/ActiveJobsPage.tsx` | **MODIFY** — task badges |
| `frontend/src/features/office/pages/ManageJobsPage.tsx` | **MODIFY** — task badges |
