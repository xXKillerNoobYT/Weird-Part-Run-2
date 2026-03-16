# Scheduling Enhancements: Lunch Breaks, Multi-Job Dispatch, Supervisor Role

> **Date:** 2026-03-07
> **Status:** ✅ Complete — All 7 steps implemented and verified (0 TS errors, all Python files parse OK)
> **Scope:** Add lunch break scheduling, improve multi-job dispatch UX, add supervisor role
> **Migration:** 035_scheduling_enhancements.sql

---

## Context

The scheduling module (Phase 10) was fully functional but missing three capabilities:

1. **Lunch breaks** — Schedule hours didn't account for lunch. Added `lunch_start`/`lunch_end` fields on default schedules, dispatch records, templates, shift patterns, and schedule exceptions.
2. **Multi-job dispatch per day** — Schema supported it but UI didn't show existing assignments. Added enriched conflict detection with "Today's Assignments" panel and time overlap warnings.
3. **Supervisor/floater role** — People who bounce between job sites. Added `'supervisor'` to `role_on_job` with amber color styling.

---

## Implementation Summary

### Migration 035
- ALTER TABLE for lunch columns on: employee_default_schedules, schedule_exceptions, shift_pattern_days, dispatch_templates
- Full job_dispatch table recreation (SQLite can't ALTER CHECK constraints) with lunch columns + 'supervisor' role

### Backend (3 files)
- `models/scheduling.py`: 'supervisor' in DISPATCH_ROLES, lunch fields on 14 models, enriched ScheduleConflict, role_on_job on CalendarEntry
- `repositories/scheduling_repo.py`: Extended bulk_upsert columns, enriched conflict queries
- `services/scheduling_service.py`: Lunch propagation in 8 service methods, role_on_job in calendar assembly

### Frontend Types
- `lib/types.ts`: 18 edits — 'supervisor' in DispatchRoleOnJob, lunch fields on 14 interfaces, enriched ScheduleConflict, CalendarEntry

### Frontend Pages (4 pages modified)
- `DailyDispatchPage.tsx`: Supervisor role labels/colors, lunch inputs in modal, "Today's Assignments" panel, time overlap warning
- `ScheduleConfigPage.tsx`: Lunch start/end columns in default schedule grid (desktop + mobile), hours calculation subtracts lunch
- `DispatchTemplatesPage.tsx`: Lunch state/inputs on template forms, lunch display on cards
- `ScheduleCalendarPage.tsx`: Role-based color overrides (supervisor=amber, lead=indigo), role badges

### Local Capacitor Migration
- `006_fleet_tools_scheduling.ts`: Lunch columns + supervisor CHECK on employee_default_schedules, schedule_exceptions, job_dispatch

### Key Learnings
- Plan referenced WeeklyAvailabilityPage for lunch columns, but actual default schedule editor is ScheduleConfigPage
- All scheduling service methods use explicit insert dicts (not model_dump()), requiring manual field threading
- dispatch_templates has NO CHECK constraint on role_on_job, so 'supervisor' worked without SQL changes

---

## Files Modified

| File | Changes |
|------|---------|
| `backend/app/migrations/035_scheduling_enhancements.sql` | **NEW** — lunch columns + job_dispatch recreation |
| `backend/app/models/scheduling.py` | 'supervisor' + lunch fields on 14 models + enriched conflict/calendar |
| `backend/app/repositories/scheduling_repo.py` | Extended bulk_upsert + enriched conflict queries |
| `backend/app/services/scheduling_service.py` | Lunch propagation in 8 methods + calendar role_on_job |
| `frontend/src/lib/types.ts` | 18 edits — supervisor, lunch, enriched conflicts |
| `frontend/src/features/scheduling/pages/DailyDispatchPage.tsx` | Supervisor, lunch inputs, assignments panel |
| `frontend/src/features/scheduling/pages/ScheduleConfigPage.tsx` | Lunch columns in default schedule grid |
| `frontend/src/features/scheduling/pages/DispatchTemplatesPage.tsx` | Lunch on template forms/cards |
| `frontend/src/features/scheduling/pages/ScheduleCalendarPage.tsx` | Role-based colors + badges |
| `frontend/src/local/migrations/006_fleet_tools_scheduling.ts` | Lunch + supervisor on 3 tables |
