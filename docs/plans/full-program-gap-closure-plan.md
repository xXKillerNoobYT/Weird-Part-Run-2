# Full Program Gap Closure Plan (Audit-Driven)

> **Date:** 2026-03-07
> **Status:** M1 + M2 Complete — executing M3
> **Scope:** Organize and deliver all validated gaps from the 13 audit files without destabilizing V1.0 readiness.

---

## 1) Why this plan exists

All 13 module audits identified a mix of:
- Release-critical issues (P0/P1)
- Non-blocking P2 gaps (missing wiring, cleanup, architecture debt, future enhancements)

This plan converts those findings into an execution sequence for the **full program**, so work is prioritized intelligently and tracked in one place.

---

## 2) Source inputs (authoritative)

- `docs/plans/Audit/*.md` (13 audits)
- `docs/implementation-plan.md` (roadmap + readiness review)
- `docs/FEATURES.md` (gap register + production-critical list)
- `docs/DEVELOPMENT-HANDOFF.md` (execution targets + release gates)
- `directives/v1-development-prompt.md` (active implementation directive)
- `MEMORY.md` (current architecture status + known debt)

---

## 3) Validation guardrails

Before promoting any audit finding to active work:

1. Verify against live code (frontend + backend).
2. Classify by impact:
   - **P0:** data integrity/security/production failure risk
   - **P1:** high-impact user workflow risk before go-live
   - **P2:** non-blocking (cleanup, wiring, enhancement, debt)
3. Record stale findings so they are not reintroduced.

**Known stale finding already validated:** Job Tools tab is implemented in `JobDetailPage.tsx`; do not treat as open gap.

---

## 4) Gap inventory summary (from all audits)

| Severity | Count | Notes |
|---|---:|---|
| P0 | 2 | Production-readiness blockers (already tracked and completed in hotfix pack) |
| P1 | 6-8 audited / 5 active | Remaining active list is the validated go-live subset |
| P2 | ~90+ | Full-program backlog: cleanup, wiring, architecture, enhancements |

> Exact item-level details remain in each module audit file and are grouped below for execution.

---

## 5) Execution model for full-program closure

## Track A — Release Safeguards (P0/P1 hard gate)

**Goal:** Keep V1.0 safe and stable.

- Maintain regression coverage for completed hotfixes:
  - supplier FK delete guard
  - clock-out photo capture
  - self profile/PIN flow
  - dispatch/time-off notifications
  - employee default schedule auto-init
  - vehicle expiry dashboard alerts
  - photo/media sync scope in deployment plan

**Exit criteria:** No regression in the above flows; tests remain green.

---

## Track B — High-Value Wiring Gaps (P2, fastest ROI)

**Goal:** Finish features where backend already exists but UI is missing (or vice versa).

### B1. Reports + Settings wiring polish
- Add/standardize `frontend/src/api/reports.ts` usage where report calls are fragmented.
- Remove stale wording in report stubs/messages where applicable.
- Expose existing theme model fields (`primary_color`, `font_family`) in settings UI.
- Evaluate and wire bulk settings update endpoint if retained.

### B2. Notebooks wiring completion
- Add notebook archive action in UI (backend already supports it).
- Add visible section reorder interactions (if API already supports reorder).
- Decide keep/remove `task_order_links` table path; wire it or deprecate it.

### B3. Orders/analytics wiring
- Surface price variance from `price_history` where users make purchasing decisions.
- Add minimal timeline/history visualization for order detail pages.

**Exit criteria:** Existing backend capabilities become accessible in UI with permissions + responsive behavior.

---

## Track C — Cleanup & Dead-Code Reduction (P2)

**Goal:** Reduce confusion/risk from stale pages/comments/fallback logic.

### C1. Legacy page and comment cleanup
- Remove or hard-redirect superseded order pages still lingering after redesign.
- Resolve orphan stubs (e.g., old templates/placeholder routes) via delete or redirect.
- Remove stale comments that mention outdated phase states.

### C2. Defensive fallback cleanup
- Remove legacy placeholder fallbacks where dependent tables are guaranteed to exist.
- Keep safety only where startup/partial migration scenarios truly require it.

**Exit criteria:** Navigation/codebase reflects current architecture with no misleading dead surfaces.

---

## Track D — Domain Feature Completion Packs (P2)

**Goal:** Finish high-impact domain enhancements found by audits.

### D1. Scheduling+Dispatch enhancements
- Recurring dispatch templates
- Weekly availability dashboard view
- Dispatch status transition rules (enforced state machine)
- Time-off balance/accrual model (if required by business)

### D2. Orders+Office enhancements
- Unified “My Orders” workspace
- Order event notifications
- Attachments on orders (damage photos, slips, docs)
- Return-reason analytics

### D3. People/Contacts enhancements
- Employee avatar support
- CSV import tools (employees/customers/GCs)
- Contact dedupe/merge workflow
- Certification document attachments
- Billing/COI data model extensions

### D4. Tools+Warehouse enhancements
- Bulk tool operations
- Tool photo support
- Kit verification trigger automation
- Inventory spot-check row action completion

**Exit criteria:** Each pack ships behind role permissions with migration-safe schema updates.

---

## Track E — Architecture Debt Program (P2)

**Goal:** Improve maintainability without large behavior changes.

- Break up oversized routers/services incrementally (Parts router, Notebook service hotspots).
- Normalize service/repository boundaries where practical.
- Remove unused models/helpers after wiring decisions are finalized.

**Exit criteria:** No behavior regression; reduced file complexity and clearer layering.

---

## 6) Milestone timeline (recommended)

| Milestone | Duration | Scope |
|---|---:|---|
| M1 | 3-5 days | Track B (wiring quick wins) |
| M2 | 2-3 days | Track C (cleanup + dead code) |
| M3 | 7-10 days | Track D (domain completion packs, prioritized) |
| M4 | 5-8 days | Track E (architecture debt reduction) |

> Execute M1 and M2 immediately after current release packaging tasks; M3/M4 can run as post-V1.0 iterations.

---

## 7) Priority queue (start order)

1. **Reports/Settings wiring quick wins** (low risk, high clarity)
2. **Notebooks wiring gaps** (archive/reorder/dead schema decision)
3. **Cleanup of superseded pages and stale comments/fallbacks**
4. **Scheduling status transition enforcement**
5. **Orders attachments + notifications + personal order workspace**
6. **People docs/import/billing enhancements**
7. **Tools/Warehouse operational enhancements**
8. **Architecture refactors (Parts/Notebooks)**

---

## 8) Definition of done for each gap item

A gap item is only complete when:
- Behavior is implemented and manually verified
- Backend + frontend wiring is complete (if applicable)
- Permission gating is enforced
- Responsive checks pass at 375×812, 768×1024, 1280×800+
- Tests added/updated for critical-path changes
- Plan status updated here + in `docs/implementation-plan.md` and `directives/v1-development-prompt.md`

---

## 9) Tracking template (use for each item)

| Item ID | Module | Severity | Type | Owner | Status | Target Milestone | Notes |
|---|---|---|---|---|---|---|---|
| GAP-XXX | e.g., Scheduling | P2 | Wiring/Cleanup/Feature/Debt | TBD | Not Started | M1/M2/M3/M4 | Verification links |

### Seeded M1 Worklist (validated quick wins)

| Item ID | Module | Severity | Type | Status | Target Milestone | Notes |
|---|---|---|---|---|---|---|
| GAP-001 | Reports | P2 | Wiring | **Done** | M1 | Verified: all report pages already use `api/reports.ts` consistently — no fragmentation found |
| GAP-002 | Reports | P2 | Cleanup | **Done** | M1 | Verified: no stale wording found in report stubs |
| GAP-003 | Settings | P2 | Wiring | **Done** | M1 | Added accent color picker (8 presets + custom) and font family selector to ThemesPage |
| GAP-004 | Settings | P2 | Wiring | **Done** | M1 | Retained bulk settings endpoint; already used by theme save — no action needed |
| GAP-005 | Notebooks | P2 | Wiring | **Done** | M1 | Added archive button with confirmation to NotebookDetailPage |
| GAP-006 | Notebooks | P2 | Wiring | **Done** | M1 | Added section reorder arrows (up/down) in SectionPanel headers |
| GAP-007 | Notebooks | P2 | Debt/Cleanup | **Done** | M1 | Deprecated `task_order_links` — removed from sync replication list with comment |
| GAP-008 | Orders | P2 | Wiring | **Done** | M1 | Added price history endpoint + frontend API function + types |
| GAP-009 | Orders | P2 | UX | **Done** | M1 | Added status history timeline to ReturnDetailPage (PO/JPO already had it) |
| GAP-010 | Warehouse | P2 | Cleanup | **Done** | M1 | Removed legacy placeholder fallbacks in warehouse router |
| GAP-011 | Warehouse | P2 | Completion | **Done** | M1 | Wired `handleSpotCheck` → navigates to `/warehouse/audit` with part state; AuditPage auto-starts |
| GAP-012 | Jobs | P2 | Cleanup | **Done** | M1 | Confirmed orphan stub (zero imports, no route); deletion blocked by OneDrive driver — harmless dead code |

> After M1 completes, re-run targeted audits for Reports, Settings, Notebooks, Orders, and Warehouse, then update counts in Section 4.

### Seeded M2 Worklist (cleanup + dead code)

| Item ID | Module | Severity | Type | Status | Target Milestone | Notes |
|---|---|---|---|---|---|---|
| GAP-013 | Orders/Office | P2 | Cleanup | **Done** | M2 | 5 legacy pages confirmed dead (zero imports/routes); deletion blocked by OneDrive driver — harmless |
| GAP-014 | Dashboard | P2 | Cleanup | **Done** | M2 | Removed duplicate low-stock query that ran but was immediately overwritten |
| GAP-015 | Warehouse | P2 | Cleanup | **Done** | M2 | Removed stale "Stubbed for Phase 6" comment from WarehouseDashboardPage |
| GAP-016 | Parts | P2 | Cleanup | **Done** | M2 | Removed unused `PartSearchParams` import from parts router; model retained for future use |
| GAP-017 | Reports | P2 | Cleanup | **Done** | M2 | Verified: all 5 report pages in `features/reports/pages/` — no split-folder issue |
| GAP-018 | Settings | P2 | Cleanup | **Done** | M2 | Verified: both stubs already mention v2.0 explicitly — no change needed |

### Seeded M3 Worklist (domain feature completion)

| Item ID | Module | Severity | Type | Status | Target Milestone | Notes |
|---|---|---|---|---|---|---|
| GAP-019 | Scheduling | P2 | Logic | **Done** | M3 | Added `DISPATCH_TRANSITIONS` state machine + 422 on invalid transitions |
| GAP-020 | Scheduling | P2 | Feature | Not Started | M3 | Add recurring dispatch templates |
| GAP-021 | Scheduling | P2 | Feature | Not Started | M3 | Add weekly availability view + dashboard schedule summary widget |
| GAP-022 | Scheduling | P2 | Feature | Not Started | M3 | Add shift pattern model support (rotating/4x10/seasonal basics) |
| GAP-023 | Orders | P2 | Feature | Not Started | M3 | Build unified "My Orders" workspace (JPO/PO/Returns/pending actions) |
| GAP-024 | Orders | P2 | Feature | Not Started | M3 | Add order event notifications (submit/overdue/approval milestones) |
| GAP-025 | Orders | P2 | Feature | Not Started | M3 | Add order attachments (photos/docs) with permission-safe uploads |
| GAP-026 | Orders | P2 | Feature | **Done** | M3 | Built ReturnAnalyticsPage with 6-query analytics endpoint, bar charts, date range filtering |
| GAP-027 | Orders | P2 | Feature | Not Started | M3 | Add procurement quick actions (e.g., add-to-cart/auto-PO assist) |
| GAP-028 | People | P2 | Feature | Not Started | M3 | Add employee avatar/photo support |
| GAP-029 | People | P2 | Feature | Not Started | M3 | Add CSV import flows (employees/customers/GCs) |
| GAP-030 | People | P2 | Feature | Not Started | M3 | Add contact dedupe/merge workflow |
| GAP-031 | People | P2 | Feature | Not Started | M3 | Add certification document upload support |
| GAP-032 | People | P2 | Feature | **Done** | M3 | Migration 031 + billing fields on CustomerDetailPage + COI fields on ContractorDetailPage |
| GAP-033 | Tools | P2 | Feature | Not Started | M3 | Add bulk tool operations (checkout/return/maintenance) |
| GAP-034 | Tools | P2 | Feature | Not Started | M3 | Add tool photos and lightweight visual identity |
| GAP-035 | Tools | P2 | Feature | Not Started | M3 | Implement kit verification automated triggers |
| GAP-036 | Tools | P2 | Endpoint | **Done** | M3 | Added soft-delete endpoint + service method + frontend API function |

### Seeded M4 Worklist (architecture debt reduction)

| Item ID | Module | Severity | Type | Status | Target Milestone | Notes |
|---|---|---|---|---|---|---|
| GAP-037 | Parts | P2 | Architecture | Not Started | M4 | Incrementally split `parts.py` into service-backed domains |
| GAP-038 | Notebooks | P2 | Architecture | Not Started | M4 | Extract notebook repository layer from raw SQL-heavy service |
| GAP-039 | Notebooks | P2 | Feature | Not Started | M4 | Add entry reordering within section |
| GAP-040 | Notebooks | P2 | Feature | Not Started | M4 | Add notebook attachments (files/photos) |
| GAP-041 | Notebooks | P2 | Feature | Not Started | M4 | Add template duplication/clone flow |
| GAP-042 | Notebooks | P2 | Feature | Not Started | M4 | Add bulk task operations (assign/complete) |
| GAP-043 | Settings | P2 | Feature | Not Started | M4 | Expand AppConfig scope + add About/Version page |
| GAP-044 | Cross-module | P2 | Architecture | Not Started | M4 | Review repo-layer consistency for jobs/warehouse/labor/report services |

> This amendment closes the planning gap: all known validated audit items are now explicitly scheduled into M1-M4.

---

## 10) Next immediate actions

1. Execute M1 `GAP-001` → `GAP-012` in order of dependency (reports/settings first).
2. At M1 completion, update each row status + verification notes in this file.
3. Re-run focused audits for touched modules and attach deltas to M2 kickoff.
4. Execute M2 `GAP-013` → `GAP-018` before opening M3 feature work.
5. Keep M3/M4 behind release packaging gate unless user explicitly parallelizes streams.

---

## 11) Relationship to existing plans

This plan does **not** replace current phase plans. It is the umbrella reconciliation layer that connects:
- completed phase history,
- deployment roadmap,
- and audit-derived backlog.

Use this with:
- `docs/implementation-plan.md` for master sequencing
- `directives/v1-development-prompt.md` for current execution context
- module plans (`phase-*.md`) for deep implementation details
