# V1 Implementation Prompt — Wired-Part (Execution Mode)

> **Purpose:** Use this as the active implementation directive for coding sessions.
> **Last updated:** 2026-03-07
> **Current status:** ALL GAP MILESTONES COMPLETE (M1 + M2 + M3 + M4 — all 44 gaps closed). **Stage D (device validation) blocked on hardware.** Next active work: Phase 7 Delta or Phase 8 planning.

---

## 0) Context Recall & Refocus Rule (MANDATORY)

When confidence/context drops below ~80%, **stop coding** and re-read in this order:

1. `directives/v1-development-prompt.md` (this file)
2. `CLAUDE.md` (working style + architecture rules)
3. `MEMORY.md` (project memory + patterns)
4. `docs/implementation-plan.md` (master roadmap)
5. `docs/plans/full-program-gap-closure-plan.md` (active gap tracker)
6. `docs/plans/deployment-master-plan.md` (release/deployment flow)

Also re-read before:
- starting a new milestone,
- touching a new module,
- writing migrations,
- making refactors that span backend + frontend.

---

## 1) Mission Definition

Deliver remaining V1 work to proper production quality:

- no open validated gaps,
- no regressions,
- no unresolved errors,
- all critical flows verified,
- documentation and plans synchronized with code reality.

This means complete work across:
1. Release/deployment readiness checks,
2. Gap Milestone M3 (in progress),
3. Gap Milestone M4 (architecture debt),
4. Final full-system verification sweep.

---

## 2) Authoritative Files (Read Before Coding)

### Core planning
- `docs/implementation-plan.md`
- `docs/plans/full-program-gap-closure-plan.md`
- `docs/plans/deployment-master-plan.md`
- `docs/FEATURES.md`

### Module audits (read the one you are touching)
- `docs/plans/Audit/dashboard-audit.md`
- `docs/plans/Audit/parts-inventory-audit.md`
- `docs/plans/Audit/warehouse-audit.md`
- `docs/plans/Audit/fleet-audit.md`
- `docs/plans/Audit/jobs-labor-audit.md`
- `docs/plans/Audit/orders-system-audit.md`
- `docs/plans/Audit/office-audit.md`
- `docs/plans/Audit/people-audit.md`
- `docs/plans/Audit/notebooks-audit.md`
- `docs/plans/Audit/tools-kits-audit.md`
- `docs/plans/Audit/reports-audit.md`
- `docs/plans/Audit/settings-audit.md`
- `docs/plans/Audit/scheduling-audit.md`

---

## 3) Execution Order (Do Not Skip)

### Stage A — Sanity Gate (quick re-verify)

Before continuing feature work, verify these are still true:

1. Backend deps install cleanly (`backend/requirements.txt`, including `fpdf2` if present)
2. Frontend build is clean (`npm run build`)
3. Backend tests pass (`python -m pytest tests/ -v`)
4. Gap tracker still shows M1 + M2 complete and M3 active

If any fail, fix before proceeding.

---

### Stage B — M3 Domain Completion (Current Active Work)

Source of truth: `docs/plans/full-program-gap-closure-plan.md` (M3 items)

#### D1 Scheduling (`GAP-019` → `GAP-022`)
- Dispatch status state machine enforcement
- Recurring dispatch templates
- Weekly availability view
- Shift pattern support

#### D2 Orders (`GAP-023` → `GAP-027`)
- My Orders workspace
- Order event notifications
- Order attachments
- Return-reason analytics
- Procurement quick actions

#### D3 People (`GAP-028` → `GAP-032`)
- Employee avatars
- CSV imports
- Contact dedupe/merge
- Certification attachments
- Billing + COI extensions

#### D4 Tools (`GAP-033` → `GAP-036`)
- Bulk tool operations
- Tool photos
- Kit verification automation
- Maintenance type delete endpoint

For each completed item:
1. Implement backend/frontend wiring,
2. Verify permissions,
3. Verify responsive behavior (375 / 768 / 1280),
4. Update gap status in `docs/plans/full-program-gap-closure-plan.md`.

---

### Stage C — M4 Architecture Debt (`GAP-037` → `GAP-044`)

After M3 complete:

- Split oversized Parts router safely,
- Extract notebook repository layer,
- Deliver notebook enhancement debt items,
- Add About/config completeness,
- Improve cross-module service/repository consistency.

Refactor with behavior parity. No regressions allowed.

---

### Stage D — Release/Device Validation

- Validate release packaging checklist from deployment plan §13
- Validate sideloading flow (`docs/plans/sideloading-guide.md`)
- iOS path (Mac/Xcode required)
- Android APK path
- On-device workflow checks for core job/day flows

If hardware/tooling unavailable, document explicit blocker with exact missing dependency.

---

## 4) Quality Gates (Every PR/Commit)

A task is **not complete** unless all pass:

1. Build/lint/test gate:
	- `cd frontend && npm run build`
	- `cd backend && python -m pytest tests/ -v`
2. No unresolved runtime/import errors
3. Permission checks validated for affected features
4. Responsive checks at:
	- 375×812 (iPhone)
	- 768×1024 (iPad)
	- 1280×800+ (desktop)
5. Plan docs updated to reflect reality

---

## 5) Implementation Standards

### Backend
- Keep `ApiResponse[T]` + `PaginatedData[T]` response contracts
- Respect service/repository boundaries
- Prefer explicit permission guards (`require_permission`)
- Keep migrations additive/safe

### Frontend
- Domain API calls in `frontend/src/api/{domain}.ts`
- Avoid scattered inline HTTP calls where domain API client exists
- Maintain touch-friendly UI (44px targets)
- No horizontal overflow regressions
- Use clear fallback/loading/error states

---

## 6) Update Protocol While Executing

After each meaningful batch:

1. Update `docs/plans/full-program-gap-closure-plan.md` status rows
2. Update `docs/implementation-plan.md` if milestone-level state changed
3. Keep this file (`directives/v1-development-prompt.md`) aligned to current active stage

Do not let prompt/docs drift from code state.

---

## 7) Non-Negotiable Distribution Rules

- $0 distribution model only
- iOS: Sideloadly + AltServer
- Android: direct APK sideload
- Do **not** reference TestFlight / paid Apple developer flow in implementation docs

---

## 8) Session Start Checklist (Copy/Paste for Agent)

At the start of each coding session:

1. Re-read Section 0 files
2. Read active milestone rows in `docs/plans/full-program-gap-closure-plan.md`
3. Pick the next highest-priority open GAP item
4. Implement + verify + test
5. Update gap status + commit
6. If confidence drops below 80%, re-run Section 0 immediately

---

## 9) Current Active Objective

**All 44 gap milestones (M1–M4) are complete. Phase 7 Delta is verified complete.**

Next work:
1. Phase 8: Reports & Pre-Billing (`docs/plans/phase-11-reports-prebilling.md`)
2. Stage D — Device/release validation (blocked on Mac hardware + npm install in OneDrive)
3. Future phases 9–13 (Chat, PWA, Bluetooth, AI, Remote Sync) — not yet started

Target result: V1 with no validated open gaps, no hidden regressions, and all plan files synchronized with actual implementation.
