# Phase 8: People (Full) — Implementation Plan

> **Date:** 2026-03-04
> **Status:** ✅ COMPLETE
> **Scope:** Complete People module — employee management, certifications, wage history, notes, skills, hat/role management, permission matrix
> **Follows:** Phase 7E (Quality of Life) — complete

---

## Context & Problem

The People module had 3 stub pages (EmployeeListPage, HatsPage, PermissionsPage) displaying "Coming soon" EmptyState components, plus 3 stub backend endpoints returning StatusMessage. The foundation was solid (users table, hats, hat_permissions, user_hats already existed), but no CRUD UI, no certification tracking, no wage history, no HR notes, and no skills tracking.

---

## What Was Built

### Database (Migration 023)
- 4 new tables: `certifications`, `wage_history`, `employee_notes`, `user_skills`
- Proper indexes, foreign keys, CHECK constraints
- Certification types: journeyman, apprentice, master, osha_10, osha_30, first_aid, cpr, forklift, confined_space, custom

### Backend (~28 Endpoints)
- **Models**: ~20 Pydantic models in `backend/app/models/people.py`
- **Repos**: 4 new repo classes in `backend/app/repositories/people_repo.py`, plus UserRepo extensions
- **Service**: `PeopleService` orchestrating cross-repo operations, permission matrix builder
- **Router**: Full rewrite of `backend/app/routers/people.py` with 28 endpoints covering employees, certifications, wages, notes, skills, hats, and permissions

### Frontend (4 Pages, ~2060 LOC)
- **EmployeeListPage** (438 lines): Paginated list with search, filters (active/inactive, hat), create modal
- **EmployeeDetailPage** (763 lines): 5 sub-tabs (Overview, Certifications, Wages, Notes, Skills)
- **HatsPage** (538 lines): Accordion-style hat cards with expandable domain-grouped permission checklists
- **PermissionsPage** (320 lines): Full permission matrix grid (hats × permissions) with domain grouping
- **API module**: 28 typed API functions in `frontend/src/api/people.ts`
- **Types**: ~20 new interfaces in `frontend/src/lib/types.ts`

### Key Design Decisions
1. Wage history has dual permission gating (show_dollar_values OR manage_people)
2. Permission matrix uses "replace all" pattern for permission updates
3. Employee contact info prominently displayed in Overview tab for cross-module reference
4. HatsPage and PermissionsPage provide complementary views (per-hat vs. matrix)

---

## Files Summary

### New Files (6)
- `backend/app/migrations/023_people_full.sql`
- `backend/app/models/people.py`
- `backend/app/repositories/people_repo.py`
- `backend/app/services/people_service.py`
- `frontend/src/api/people.ts`
- `frontend/src/features/people/pages/EmployeeDetailPage.tsx`

### Modified Files (7)
- `backend/app/routers/people.py` — full rewrite from stubs
- `backend/app/repositories/user_repo.py` — added list_employees, count_employees, toggle_active
- `frontend/src/lib/types.ts` — ~20 new interfaces
- `frontend/src/features/people/pages/EmployeeListPage.tsx` — full rewrite
- `frontend/src/features/people/pages/HatsPage.tsx` — full rewrite
- `frontend/src/features/people/pages/PermissionsPage.tsx` — full rewrite
- `frontend/src/App.tsx` — added employee detail route

### Verification
- `npx tsc --noEmit` — zero TypeScript errors ✅
- Python AST parse — all 4 backend files parse OK ✅
