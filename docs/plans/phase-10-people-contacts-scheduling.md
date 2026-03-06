# Phase 10: People, Contacts, Contractors & Scheduling

> **Date:** 2026-03-05
> **Status:** In Progress
> **Scope:** Customer entities, general contractors, flexible contacts, scheduling/dispatch, job lead elevations UI, cert alerts
> **Follows:** Phase 9 (Tools & Kits) — complete

---

## Context & Problem

Phase 8 (People Full) built employee management (CRUD, certifications, wages, notes, skills, hats, permissions). But the original Phase 7 vision in `docs/implementation-plan.md` included several features that weren't built:

1. **General Contractors** — external companies we work with, bidirectional relationships
2. **Availability Calendar** — employee schedules, time off, dispatch
3. **Job Lead Elevations** — DB table exists (`job_lead_elevations` in migration 001) but has no endpoints or UI
4. **Cert Expiry Dashboard Alerts** — backend query exists but no dashboard card

Additionally, the user identified two critical gaps:

5. **Customer Entity** — jobs only have a bare `customer_name TEXT` field. Need a full `customers` table with flexible contacts and many-to-many job linkage.
6. **Flexible Supplier Contacts** — suppliers have rigid hardcoded 3-tier columns. Need dynamic contacts.

### User's Key Corrections

- **PO naming** (`PO=[GC_CODE]+[Job ID]+[Order Number]`) applies **ONLY** when a GC hires us (relationship = `they_are_gc`). When we hire a sub, NO PO integration — just contact info + scheduling.
- **Subcontractor scheduling** is explicitly included — tracking when GCs we hired are coming to our job sites.
- **Scheduling** is its own top-level sidebar module, not nested under People.
- **People pages**: Hybrid approach — separate pages for Customers and GCs, plus a unified All Contacts directory.

---

## Design Decisions

### Polymorphic Entity Contacts
One `entity_contacts` table serves customers, GCs, and suppliers using `(entity_type, entity_id)` — same polymorphic pattern as tools/stock.

### Bidirectional GC Relationships
`job_general_contractors` junction has a `relationship` column:
- `they_are_gc` — they hired us (we're the sub). PO naming convention applies.
- `we_hired_them` — we hired them as a sub. No PO integration, but scheduling applies.

### Backward Compatibility
- `jobs.customer_name` column stays. New customer linkage is additive.
- Supplier hardcoded contact columns stay (deprecated). Migration copies data to `entity_contacts`.
- Existing PO number format (`PO-NNNN`) unchanged for non-GC jobs.

---

## Deliverables

### Migrations
- `025_people_contacts_contractors.sql` — 5 tables + supplier data migration
- `026_scheduling.sql` — 4 scheduling tables
- `027_phase10_permissions.sql` — 9 permission seeds + default schedules

### Backend (New Files)
- `models/contacts.py` (~20 Pydantic models)
- `models/scheduling.py` (~15 Pydantic models)
- `repositories/contacts_repo.py` (5 repo classes)
- `repositories/scheduling_repo.py` (4 repo classes)
- `services/contacts_service.py` (~20 methods)
- `services/scheduling_service.py` (~20 methods)
- `routers/contacts.py` (~19 endpoints)
- `routers/scheduling.py` (~21 endpoints)

### Frontend (New Files)
- `api/contacts.ts` (~22 API functions)
- `api/scheduling.ts` (~20 API functions)
- 5 People pages: Customers, CustomerDetail, Contractors, ContractorDetail, ContactDirectory
- 5 Scheduling pages: Calendar, DailyDispatch, TimeOff, ScheduleConfig, SubSchedule

### Modified Files
- `main.py`, `people.py` (models/repos/services/routers), `orders_service.py`, `jobs.py` router
- `types.ts`, `navigation.ts`, `constants.ts`, `App.tsx`
- `JobDetailPage.tsx`, `DashboardPage.tsx`, `SuppliersPage.tsx`
