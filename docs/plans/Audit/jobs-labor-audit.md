# Jobs & Labor Audit

> **Date:** 2026-03-06
> **Status:** ✅ Complete — E2E responsive validated at mobile/tablet/desktop (2026-03-07).
> **Scope:** Full audit of Jobs & Labor module (Job CRUD, Clock In/Out, Questionnaire, Daily Reports, Preferences, Contacts)
> **Phases:** Phase 4 (core jobs + labor), Phase 4.5 (notebook integration), Phase 7A (job preferences), Phase 10 (customer/GC linking)

---

## 1. Backend Inventory

### Files & Line Counts

| File | Lines | Role |
|------|------:|------|
| `routers/jobs.py` | 738 | Single router for all job/labor/question/report endpoints |
| `services/job_service.py` | 459 | Job CRUD, status lifecycle, bill rate types, parts consumption |
| `services/labor_service.py` | 256 | Clock in/out, hours calculation, GPS capture |
| `services/job_preferences_service.py` | 460 | Smart suggestion memory per job (Phase 7A) |
| `services/questionnaire_service.py` | 208 | Global + one-time clock-out questions |
| `services/report_service.py` | 439 | Daily report generation + retrieval |
| `models/jobs.py` | 303 | Pydantic models for all job-related types |
| `scheduler.py` | ~50 | APScheduler midnight report generation |
| **Total backend** | **~2,913** | |

### Endpoints (40 total)

| Section | # | Method | Path | Description |
|---------|---|--------|------|-------------|
| **Bill Rate Types** | 1 | GET | `/api/jobs/bill-rate-types` | List bill rate types |
| | 2 | POST | `/api/jobs/bill-rate-types` | Create bill rate type |
| | 3 | PUT | `/api/jobs/bill-rate-types/{id}` | Update bill rate type |
| | 4 | DELETE | `/api/jobs/bill-rate-types/{id}` | Deactivate bill rate type |
| **Job CRUD** | 5 | GET | `/api/jobs/active` | List active jobs with filters |
| | 6 | POST | `/api/jobs` | Create a new job |
| | 7 | GET | `/api/jobs/{id}` | Full job detail with aggregated stats |
| | 8 | PUT | `/api/jobs/{id}` | Update job |
| | 9 | PATCH | `/api/jobs/{id}/status` | Change job status |
| **Notebook** | 10 | GET | `/api/jobs/{id}/notebook` | Get or lazy-create job notebook |
| | 11 | GET | `/api/jobs/{id}/tasks` | Tasks across all sections |
| **Labor/Clock** | 12 | POST | `/api/jobs/{id}/clock-in` | Clock in with GPS |
| | 13 | POST | `/api/jobs/clock-out` | Clock out with GPS + questionnaire |
| | 14 | GET | `/api/jobs/my-clock` | Current active clock |
| | 15 | GET | `/api/jobs/{id}/labor` | Labor entries for a job |
| | 16 | GET | `/api/jobs/my-labor` | Current user's labor history |
| **Parts** | 17 | GET | `/api/jobs/{id}/parts` | Parts consumed on a job |
| | 18 | POST | `/api/jobs/{id}/parts/consume` | Record part consumption |
| **Questions** | 19-23 | CRUD | `/api/jobs/questions/global/*` | Global clock-out questions |
| | 24-26 | | `/api/jobs/{id}/questions/one-time/*` | One-time per-job questions |
| | 27 | GET | `/api/jobs/{id}/clock-out-bundle` | Assembled questionnaire |
| **Reports** | 28 | GET | `/api/jobs/reports/all` | All reports across jobs |
| | 29 | GET | `/api/jobs/{id}/reports` | Reports for a specific job |
| | 30 | GET | `/api/jobs/{id}/reports/{date}` | Full daily report |
| | 31 | POST | `/api/jobs/reports/generate-now` | Manual admin trigger |
| **Preferences** | 32 | GET | `/api/jobs/{id}/preferences` | Learned preferences |
| | 33 | GET | `/api/jobs/{id}/suggestions` | Ranked smart suggestions |
| | 34 | PUT | `/api/jobs/{id}/preferences/{id}` | Toggle preference on/off |
| **Contacts** | 35-37 | | `/api/jobs/{id}/customers/*` | Customer linking |
| | 38-40 | | `/api/jobs/{id}/general-contractors/*` | GC linking |

---

## 2. Frontend Inventory

### Pages (5 functional + 1 stub)

| File | Lines | Route | Status |
|------|------:|-------|--------|
| `ActiveJobsPage.tsx` | 350 | `/jobs/active` | ✅ Functional — filterable job list + create modal |
| `JobDetailPage.tsx` | 1,343 | `/jobs/:id` | ✅ Functional — 8 sub-tabs (notebook, overview, people, labor, parts, tools, questions, costs) |
| `MyClockPage.tsx` | 211 | `/jobs/my-clock` | ✅ Functional — clock in/out with GPS, running timer |
| `DailyReportView.tsx` | 425 | `/reports/daily-reports/:jobId/:date` | ✅ Functional — read-only rendered report |
| `JobReportsListPage.tsx` | 175 | `/reports/daily-reports` | ✅ Functional — all reports with date filters |
| `TemplatesPage.tsx` | 16 | *(not routed)* | ❌ **STUB** — "Coming soon" empty state |

### Components (3 files)

| File | Lines | Description |
|------|------:|-------------|
| `JobCard.tsx` | 143 | Card for jobs list (status, address, workers, tasks) |
| `EditJobModal.tsx` | 438 | Full job create/edit form modal |
| `ClockOutFlow.tsx` | 431 | Multi-step clock-out flow with questionnaire |

### Stores & API Client

| File | Lines |
|------|------:|
| `stores/clock-store.ts` | 135 |
| `api/jobs.ts` | 393 |

### Navigation Config

Jobs module — 2 sidebar tabs:
- Active Jobs, My Clock
- Module permission: `view_jobs`
- Note: Daily Reports live under separate "Reports" module
- Related Office tabs: "Manage Jobs" (`manage_jobs`), "Notebook Templates" (`manage_notebooks`), "Clock-Out Questions" (`manage_settings`)

### Frontend Summary

| Metric | Count |
|--------|------:|
| Page files | 6 (5 functional + 1 stub) |
| Component files | 3 |
| Store + API files | 2 |
| **Total frontend lines** | **~4,060** |

---

## 3. Feature Completeness

### ✅ Fully Functional

| Feature | Notes |
|---------|-------|
| Job CRUD | Create, edit, all field types including on-call/warranty |
| Job status lifecycle | 7 statuses: pending, active, on_hold, completed, cancelled, continuous_maintenance, on_call |
| Bill rate types | Boss-managed lookup with CRUD |
| Clock in/out | GPS capture, double-clock prevention, running timer |
| Hours calculation | Auto OT at 8-hour threshold, drive time subtraction |
| Clock-out questionnaire | Global + one-time per-job questions in multi-step flow |
| Parts consumption | Record parts with cost snapshot at consumption time |
| Daily reports | Auto-generated at midnight via APScheduler, manual trigger |
| Job notebook integration | Lazy-created from templates, full section/entry/task system |
| Job detail sub-tabs | 8 tabs including costs (permission-gated) |
| Job preferences/suggestions | Auto-learned from orders, toggleable, per-category ranking |
| Customer/GC linking | Link/unlink customers and general contractors |

### ❌ Stubs

| Feature | Status | Notes |
|---------|--------|-------|
| Notebook templates | **Stub** | `TemplatesPage.tsx` = 16-line placeholder. Templates are used via the Office module but have no dedicated management UI |

---

## 4. Cross-References

| Direction | Connection |
|-----------|-----------|
| **Clock-out flow** | Bundles global + one-time questions via `clock-out-bundle` endpoint |
| **Daily reports** | Aggregates labor entries, questionnaire responses, parts consumed, cost summaries |
| **APScheduler** | `scheduler.py` triggers `ReportService.generate_all_pending_reports()` at 00:05 daily |
| **Job preferences** | Learns from order history (Phase 7A integration) |
| **Job detail page** | Imports from notebooks, costs, tools, and contacts features |
| **Warehouse** | Active jobs are valid movement destinations |
| **Movement service** | Tracks job-bound movements for forecast calculations |
| **Office module** | "Manage Jobs" page with admin capabilities |

---

## 5. Issues & Observations
Fix this all of these need fixed

| # | Issue | Severity | Notes |
|---|-------|----------|-------|
| 1 | **TemplatesPage.tsx** — Full stub, 16 lines | Medium | Template management doesn't exist as a standalone page; office has some template functionality |
| 2 | **ClockOutFlow.tsx:132** — Photo question type uses text input instead of camera/upload | Medium | `placeholder="Photo URL or description..."` — no actual camera integration |
| 3 | **Labor entries are immutable** — no edit/delete capability after clock-out | Info | By design, but admin override may be needed |
| 4 | **Job preferences** — Only learned from orders; no manual preference creation UI | Low | Toggle on/off only |
| 5 | **No job archiving** — Jobs can be "completed" or "cancelled" but no archive/purge | Low | Long-lived job list will grow indefinitely |
| 6 | **Jobs nav has only 2 tabs** — Daily Reports is under Reports module; Templates isn't routed | Info | Could consolidate |
| 7 | **Zero TODO/FIXME comments** in core job files | ✅ | Code is clean |

---

## 6. Grand Total

| Metric | Count |
|--------|------:|
| API endpoints | 40 |
| Routed pages | 6 (5 functional + 1 stub) |
| Total backend lines | ~2,913 |
| Total frontend lines | ~4,060 |
| **Grand total** | **~6,973** |
