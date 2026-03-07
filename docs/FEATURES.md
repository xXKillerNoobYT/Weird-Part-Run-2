# Wired-Part — Master Features List

> Last updated: 2026-03-06
> Purpose: Single source of truth for what is built, what is production-critical, and what is planned next.

---

## 1) Program Scope (What this app does)

Wired-Part is an offline-first field service management platform for electrical contractors.

Core capability areas:
- Parts & inventory hierarchy (category/style/type/color) + pricing + supplier intelligence
- Warehouse movement control (guided wizard, audits, staging, movement logs)
- Trucks/fleet management (assignments, maintenance, mileage, deliveries)
- Jobs & labor (clock-in/out with GPS, questionnaires, daily reports)
- Orders & procurement (JPO → PO lifecycle, receiving, returns, approvals)
- People & permissions (hats/roles, certs, wages, contacts, scheduling)
- Notebooks & templates (job + general notebooks with tasking)
- Reports & pre-billing exports for the bookkeeper

---

## 2) Current Build Status

### Platform metrics
- Backend routers: 17
- API endpoints: ~440
- Backend services: 28
- Repositories: 19 + base
- Migrations: 27 (001 → 027)
- Frontend routes: ~90
- Functional pages: ~60
- Backend tests: 119 (critical paths)

### Completed feature phases
- Phase 1: Foundation ✅
- Phase 2: Parts & Inventory Core ✅
- Phase 2.5: Parts Hierarchy UX ✅
- Phase 3: Warehouse & Movements ✅
- Phase 3.5: Companions & Enhancements ✅
- Phase 4: Jobs & Labor ✅
- Phase 4.5: Unified Notebook System ✅
- Phase 5: Orders & Procurement ✅
- Phase 6: Fleet & Vehicle Management ✅
- Phase 7A-7E: Orders redesign + office/warehouse/analytics/QoL ✅
- Phase 8: People Full ✅
- Phase 9: Tools & Kits ✅
- Phase 10: People + Contacts + Scheduling ✅

---

## 3) Module Feature List

## Dashboard
- KPI cards + quick actions
- Daily report visibility
- Cert expiry visibility
- Fast-drive shortcuts

## Parts
- Full hierarchy CRUD: categories, styles, types, colors
- Type-color linking
- Catalog dual view (cards + table)
- Brand/supplier linking and contacts
- Pricing + forecasting + CSV import/export
- Pending part-number tracking

## Warehouse
- Warehouse dashboard with tasks
- Guided Movement Wizard (human-confirmed, atomic transfer)
- Staging/pulled flow
- Audit workflow
- Movement history log

## Trucks / Fleet
- Vehicle CRUD + assignments
- Vehicle inventory context
- Delivery tracking
- Maintenance schedules + records
- Mileage logs + trip legs + reimbursements

## Jobs & Labor
- Job CRUD, statuses, location data
- Clock-in/out with GPS tracking
- Clock-out questionnaire system (global + one-time)
- Job detail internal tabs
- Daily report generation + review views

## Orders / Procurement / Office
- JPO to PO lifecycle management
- Approvals and status transitions
- Receiving sessions
- Returns & sorting
- Procurement planning and cost visibility
- Review & Send + PDF bundle behavior

## People / Contacts / Scheduling
- Employee records, certifications, wages, skills
- Hats/roles + permission matrix
- Customer/GC/contact directory
- Schedule defaults/exceptions
- Daily dispatch and time-off flows

## Notebooks
- Job and general notebooks
- Notebook templates
- Sections and entries
- Task staging behavior

## Tools & Kits
- Tool registry + location tracking
- Checkout/return workflow
- Kit verification sessions
- Tool maintenance tracking
- QR label + scan routing

## Reports
- Daily reports functional
- Pre-billing and analytics/report suite planned and in progress per phase plans

---

## 4) Production-Critical Gaps (Must be done before final deployment)

## P0 (blockers)
1. Photo/file sync strategy for offline sync engine
2. Supplier delete FK guard (avoid runtime FK failure)

## P1 (should complete before go-live)
1. Clock-out photo answer capture input (not plain text)
2. Self-service user profile + self PIN change flow
3. Dispatch and time-off notifications
4. Auto-initialize default schedule on employee creation
5. Vehicle insurance/registration expiry dashboard alerts

---

## 5) Audit Gap Register (Validated, 2026-03-06)

Gap hunting was run across all 13 audit files and reconciled against live code before planning updates.

### Reconciliation result
- All active go-live blockers are already represented in the P0/P1 list above.
- Audit false positive removed: **Job tools tab is already implemented** in `JobDetailPage.tsx` (tab exists, renders, and loads tool data).

### Post-go-live backlog buckets (P2)
- **Cleanup / consistency**: stale stub wording, dead comments, obsolete fallbacks, dead pages.
- **Missing wiring**: backend/API exists but UI missing (or reverse).
- **Architecture debt**: oversized routers/services, uneven service/repository layering.
- **Future features**: enhancements intentionally deferred beyond V1.0.

Planning rule: P2 items do not enter the release-critical hotfix pack unless they create production risk, broken user flow, or data integrity concerns.

---

## 6) V1.0 Delivery Sequence (Execution order)

1. Production Readiness Hotfix Pack (P0/P1)
2. Phase B Task 8: Capacitor project init
3. Phase B Task 9: API adapter layer
4. Phase B Task 10: Lean TS local data layer (~11 services)
5. Phase B Task 11: Local SQLite + migrations
6. Phase C: Sync engine, conflict handling, retry queue, network indicators
7. Phase C: iOS/Android builds and device testing
8. Phase D: Setup UI, backup/restore, smoke tests, release packaging

---

## 7) Source-of-Truth Files

- Master roadmap: `docs/implementation-plan.md`
- Deployment architecture: `docs/plans/deployment-master-plan.md`
- Gap closure roadmap: `docs/plans/full-program-gap-closure-plan.md`
- Resume prompt: `directives/v1-development-prompt.md`
- Architecture memory: `MEMORY.md`
- Agent conventions: `CLAUDE.md`
