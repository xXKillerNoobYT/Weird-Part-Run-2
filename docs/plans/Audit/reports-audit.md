# Reports Audit

> **Date:** 2026-03-06
> **Status:** 📋 Audit complete
> **Scope:** Full audit of the Reports module — daily reports, pre-billing, timesheets, labor overview, exports

---

## Table of Contents

1. [Backend Inventory](#1-backend-inventory)
2. [Frontend Inventory](#2-frontend-inventory)
3. [Feature Completeness](#3-feature-completeness)
4. [Cross-References](#4-cross-references)
5. [Issues & TODOs](#5-issues--todos)

---

## 1. Backend Inventory

### Router: `backend/app/routers/reports.py` (~54 lines)

Mounted in `main.py` as `app.routers.reports`.

| # | Method | Path | Permission | Description | Status |
|---|--------|------|------------|-------------|--------|
| 1 | `GET` | `/api/reports/pre-billing` | `view_reports` | Pre-billing reports | ❌ **Stub** — returns "coming in Phase 8" |
| 2 | `GET` | `/api/reports/timesheets` | `view_reports` | Employee timesheets | ❌ **Stub** — returns "coming in Phase 8" |
| 3 | `GET` | `/api/reports/labor-overview` | `view_reports` | Cross-job labor summary | ❌ **Stub** — returns "coming in Phase 8" |
| 4 | `GET` | `/api/reports/exports` | `export_reports` | Export bundles (CSV/PDF) | ❌ **Stub** — returns "coming in Phase 8" |

**Total endpoints: 4 (all stubs)**

All 4 endpoints return `ApiResponse[StatusMessage]` with `status="stub"` and a "coming in Phase 8" message. The router is only 54 lines of minimal placeholder code. No query parameters, no business logic, no data access.

**Note:** The stub messages say "Phase 8" but the actual plan is Phase 11 (`docs/plans/phase-11-reports-prebilling.md`).

### Service: `backend/app/services/report_service.py` (~493 lines)

This is a **fully functional** service, but it serves the **Daily Reports** feature (not the stub reports). It is used by the jobs router, scheduler, and the `daily-reports` tab in the Reports navigation.

| Method | Description | Status |
|--------|-------------|--------|
| `generate_daily_report(job_id, date)` | Generate a daily report for a specific job + date | ✅ Functional |
| `generate_all_pending_reports(date)` | Generate reports for all jobs with activity on a date | ✅ Functional |
| `catch_up_missed_reports()` | Backfill reports for dates where server was down | ✅ Functional |
| `get_report(job_id, date)` | Get report metadata | ✅ Functional |
| `get_report_full(job_id, date)` | Get full report with parsed JSON | ✅ Functional |
| `get_reports_for_job(job_id)` | Get all reports for a job | ✅ Functional |
| `get_all_reports(date_from, date_to)` | Get all reports across all jobs with date filtering | ✅ Functional |

**Daily Report JSON contents** (generated at midnight by scheduler):
- Worker clock data (in/out times, GPS, hours, regular + overtime)
- Question responses (global + one-time)
- Parts consumed (name, code, qty, unit cost, total)
- Vehicle deliveries (parts delivered from trucks to job)
- Trip legs (drive time/mileage to/from job)
- Vehicle usage summary (drivers, total miles, delivered items)
- Summary stats (total labor hours, total parts cost, worker count, delivery items, miles driven, billable drive minutes)

### Backend for Daily Reports tab (NOT in reports router)

The "Daily Reports" tab in the Reports navigation is entirely served by the **jobs router**, not the reports router:

| Method | Path | Source Router | Description |
|--------|------|---------------|-------------|
| `GET` | `/api/jobs/{id}/reports` | `jobs` | Get all daily reports for a job |
| `GET` | `/api/jobs/{id}/reports/{date}` | `jobs` | Get full daily report for job + date |
| `GET` | `/api/jobs/reports` | `jobs` | Get all reports across all jobs (with date filtering) |

### Scheduler Integration

- **Midnight job**: `report_service.generate_all_pending_reports()` runs via `scheduler.py`
- **Startup catch-up**: `catch_up_missed_reports()` runs on app startup to backfill

### API Client

There is **no** `frontend/src/api/reports.ts` file. The daily reports API calls live in `frontend/src/api/jobs.ts`. The 4 stub endpoints have no corresponding frontend API functions since the pages are stubs.

---

## 2. Frontend Inventory

### Directory: `frontend/src/features/reports/`

| File | Lines | Type | Status |
|------|-------|------|--------|
| `pages/PreBillingPage.tsx` | ~18 | Pre-billing report | ❌ Stub |
| `pages/TimesheetsPage.tsx` | ~18 | Timesheet management | ❌ Stub |
| `pages/LaborOverviewPage.tsx` | ~18 | Labor analytics | ❌ Stub |
| `pages/ExportsPage.tsx` | ~18 | Export bundles | ❌ Stub |

**Total: 4 files, ~72 lines (all stubs)**

### Cross-referenced Report Pages (in other modules)

The functional report pages live in the **jobs** feature:

| File | Lines | Type | Status |
|------|-------|------|--------|
| `features/jobs/pages/JobReportsListPage.tsx` | ~190 | All reports list | ✅ Functional |
| `features/jobs/pages/DailyReportView.tsx` | ~465 | Single report detail | ✅ Functional |

**Functional report pages total: 2 files, ~655 lines**

### Navigation Config (`frontend/src/lib/navigation.ts`)

```typescript
{
  id: 'reports',
  label: 'Reports',
  icon: 'BarChart3',
  path: '/reports',
  permission: 'view_reports',
  tabs: [
    { id: 'daily-reports',   label: 'Daily Reports',   path: '/reports/daily-reports' },
    { id: 'pre-billing',     label: 'Pre-Billing',     path: '/reports/pre-billing' },
    { id: 'timesheets',      label: 'Timesheets',      path: '/reports/timesheets' },
    { id: 'labor-overview',  label: 'Labor Overview',   path: '/reports/labor-overview' },
    { id: 'exports',         label: 'Exports',          path: '/reports/exports', permission: 'export_reports' },
  ],
}
```

Module-level permission: `view_reports`.
Exports tab has additional permission: `export_reports`.

### Route Registration (`App.tsx`)

```
/reports                           → Redirect to /reports/daily-reports
/reports/daily-reports             → JobReportsListPage (from jobs feature)
/reports/daily-reports/:jobId/:date → DailyReportView (from jobs feature)
/reports/pre-billing               → PreBillingPage (stub)
/reports/timesheets                → TimesheetsPage (stub)
/reports/labor-overview            → LaborOverviewPage (stub)
/reports/exports                   → ExportsPage (stub)
```

**Note:** The default redirect goes to `daily-reports`, which is the only functional tab.

### Page Details

#### JobReportsListPage (✅ Functional — ~190 lines)
- Shows all daily reports across all jobs
- Date range filtering (from/to date pickers)
- Report cards grouped by date showing: job name, worker count, hours, parts cost
- Status badges: Generated, Reviewed, Locked
- Click-through to DailyReportView for each report
- Uses `getAllReports()` from `api/jobs.ts`

#### DailyReportView (✅ Functional — ~465 lines)
- Read-only rendered daily report for a specific job + date
- Immutable "locked notebook page" — no editing
- Sections:
  - Report header (job name, number, date, status, bill rate type)
  - Workers section (clock in/out times, GPS coordinates, hours breakdown, question responses, photos)
  - Parts consumed (name, code, qty, unit cost, total)
  - Vehicle deliveries (vehicle number, part, qty, delivered by, time)
  - Trip legs (from → to, miles, drive minutes, billable flag)
  - Vehicle usage summary (vehicle number, drivers, total miles, delivered items)
  - Cost summary (total labor hours, total parts cost, worker count)
- Back navigation to reports list

#### PreBillingPage (❌ Stub — ~18 lines)
- `<EmptyState>` with "Review unbilled parts and labor charges before generating invoices. Coming soon."

#### TimesheetsPage (❌ Stub — ~18 lines)
- `<EmptyState>` with "Track employee hours, manage approvals, and monitor overtime. Coming soon."

#### LaborOverviewPage (❌ Stub — ~18 lines)
- `<EmptyState>` with "Analyze labor costs, technician utilization, and productivity trends. Coming soon."

#### ExportsPage (❌ Stub — ~18 lines)
- `<EmptyState>` with "Generate and download reports in CSV, PDF, or Excel format. Coming soon."

---

## 3. Feature Completeness

| Tab/Feature | Frontend | Backend | Notes |
|-------------|----------|---------|-------|
| Daily Reports (list) | ✅ Functional | ✅ Functional | Fully working; date filtering, status badges |
| Daily Reports (detail view) | ✅ Functional | ✅ Functional | Full read-only report with all sections |
| Daily Report generation | N/A (background) | ✅ Functional | Midnight scheduler + startup catch-up |
| Pre-Billing | ❌ Stub | ❌ Stub | Planned for Phase 11 |
| Timesheets | ❌ Stub | ❌ Stub | Planned for Phase 11 |
| Labor Overview | ❌ Stub | ❌ Stub | Planned for Phase 11 |
| Exports | ❌ Stub | ❌ Stub | Planned for Phase 11 |

**Functional: 1/5 tabs (20%)** — only Daily Reports works
**Stubs: 4/5 tabs (80%)**

This is the **most stub-heavy module** in the application. However, this is intentional — Phase 11 (Reports & Pre-Billing) is the planned final feature phase before V1.0 deployment.

---

## 4. Cross-References

### Backend Dependencies

| Reports Feature | Service | Router | Table(s) |
|----------------|---------|--------|-----------|
| Daily Report generation | `ReportService` | `jobs` | `daily_reports`, `labor_entries`, `jobs`, `users`, `clock_out_responses`, `clock_out_questions`, `one_time_questions`, `job_parts`, `parts`, `vehicle_delivery_items`, `vehicles`, `vehicle_trip_legs`, `vehicle_mileage_logs`, `bill_rate_types` |
| Daily Report listing | `ReportService` | `jobs` | `daily_reports`, `jobs` |
| Daily Report detail | `ReportService` | `jobs` | `daily_reports`, `jobs` |
| Midnight scheduling | `ReportService` | `scheduler.py` | `labor_entries`, `daily_reports` |
| Stub endpoints | — | `reports` | — (no data access) |

### Data Available for Phase 11 (no new migrations needed)

| Planned Feature | Existing Data Source |
|----------------|---------------------|
| Pre-Billing | `labor_entries`, `bill_rate_types`, `job_parts`, `cost_layers`, `parts.weighted_avg_cost` |
| Timesheets | `labor_entries`, `users`, `jobs` |
| Labor Overview | `labor_entries`, `bill_rate_types`, `users`, `jobs` |
| Exports | All of the above + `daily_reports`, `purchase_orders`, `stock_movements` |

### Frontend Dependencies

| Reports Feature | API Client | Shared Components |
|----------------|------------|-------------------|
| Daily Reports list | `api/jobs.ts` → `getAllReports()` | `PageSpinner`, `Badge`, `EmptyState` |
| Daily Report view | `api/jobs.ts` → `getReport()` | `PageSpinner`, `Badge`, `Card`, `CardHeader`, `EmptyState` |
| 4 Stub pages | None (no API calls) | `EmptyState` only |

### Navigation Cross-references

- Reports module has `view_reports` permission gate (module-level)
- Exports tab has additional `export_reports` permission
- Daily report cards navigate to `/reports/daily-reports/{jobId}/{date}`
- DailyReportView has back-navigation to reports list
- Dashboard's DailyReportTab (separate feature) also relates to reporting but uses `costs` router

---

## 5. Issues & TODOs

### No TODO/FIXME Comments Found

Zero TODO, FIXME, HACK, or TEMP comments in any reports file.

### Architectural Notes

1. **Stale "Phase 8" references** — The stub endpoints say "coming in Phase 8" but the actual plan is Phase 11. This is cosmetic only (users never see these messages with stub frontends) but should be updated for accuracy.

2. **No `api/reports.ts`** — There's no frontend API client for the reports module. Daily reports use `api/jobs.ts`, and the stubs make no API calls. Phase 11 will need to create this file.

3. **Report pages split across two features** — The functional report pages (`JobReportsListPage`, `DailyReportView`) live in `features/jobs/pages/` rather than `features/reports/`. This made sense when daily reports were a job feature, but now that they're accessed primarily through the Reports nav tab, the file location is misleading.

4. **Backend reports router has zero business logic** — The entire 54-line file is boilerplate stubs. When Phase 11 replaces these, the file will likely grow to 200-400 lines.

5. **Daily Report JSON blobs are comprehensive** — The `report_service.py` generates very rich JSON (workers, parts, deliveries, trips, vehicles, summaries). This data will be valuable for the Pre-Billing and Timesheets features — they can potentially reuse the daily_reports JSON rather than re-querying all the raw tables.

### Phase 11 Readiness Assessment

The Phase 11 plan (`docs/plans/phase-11-reports-prebilling.md`) is detailed and ready:

| Readiness Factor | Status |
|-----------------|--------|
| Plan document exists | ✅ Yes — 322 lines, detailed endpoint specs |
| All data tables exist | ✅ Yes — no new migrations needed |
| Supporting services exist | ✅ Yes — `report_service`, `spending_service`, `cost_tracking_service`, `labor_service` |
| Navigation already wired | ✅ Yes — all 5 tabs configured |
| Routes already registered | ✅ Yes — all paths in App.tsx |
| Permissions already defined | ✅ Yes — `view_reports`, `export_reports` |
| Estimated effort | 3-4 days per plan |

**Conclusion:** The Reports module is the most incomplete feature area but is intentionally so. All infrastructure is in place for Phase 11 to replace stubs with functional pages. The daily reports feature (the only working tab) is comprehensive and production-quality.

### Feature Gaps (beyond Phase 11 scope)

- **No scheduled report emails** — No mechanism to email reports to stakeholders on a schedule
- **No report templates** — No customizable report layouts/templates
- **No report sharing** — No way to share a report link with external parties (GCs, customers)
- **No print-optimized view** — Daily report view is web-optimized but has no print stylesheet
- **No report annotations** — Reports are read-only with no ability to add notes/comments after generation
