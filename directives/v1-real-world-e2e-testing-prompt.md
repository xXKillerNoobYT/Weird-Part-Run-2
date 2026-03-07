# V1 Real-World End-to-End Testing + Fix Prompt — Wired-Part

> **Purpose:** Execute real-world workflow testing exactly like a live electrical contractor operation, fix issues properly, and verify the system works end-to-end without regressions.
> **Last updated:** 2026-03-07
> **Usage:** Paste this entire file into a coding-agent session and execute in loops until all completion gates pass.

---

## Mission

Test Wired-Part as it is actually used in the field and office, not as isolated screens.

For every issue found:
1. Reproduce
2. Identify root cause
3. Implement durable fix
4. Add/update tests
5. Retest target flow
6. Run regression checks on related flows
7. Record status and move to next

Continue until no blocking defects remain and all key workflows pass.

---

## 0) Context Recall & Refocus Rule (MANDATORY)

When confidence/context drops below ~80%, STOP and re-read in this order:

1. `directives/v1-development-prompt.md`
2. `directives/v1-real-world-e2e-testing-prompt.md` (this file)
3. `CLAUDE.md`
4. `MEMORY.md`
5. `docs/implementation-plan.md`
6. `docs/plans/full-program-gap-closure-plan.md`
7. `docs/plans/deployment-master-plan.md`
8. Relevant audit file in `docs/plans/Audit/*.md`

Also re-read before any major refactor, migration, or cross-module fix.

---

## 1) Test Like Real Users (Role-Based)

Run scenarios from the perspective of:
- Office Manager
- Warehouse Lead
- Field Technician
- Dispatcher
- Owner/Admin

Validate role permissions and real data flow between those users.

---

## 2) Preflight Setup Gate (Must Pass First)

### Environment + startup
- Backend starts without errors
- Frontend starts without errors
- DB is reachable and migrations are applied

### Build + test gates
- `cd frontend && npm run build`
- `cd backend && python -m pytest tests/ -v`

### Data readiness
Ensure test data exists for realistic workflows:
- Employees + roles/hats
- Active jobs + tasks
- Parts + stock + bins
- Suppliers + brands
- Tools + kits
- Vehicles
- Orders (JPO/PO) baseline records

If preflight fails, fix preflight before functional testing.

---

## 3) End-to-End Scenario Packs (Execute All)

## A) Authentication + Session
- Login via PIN
- Invalid PIN handling
- Session persistence/reload behavior
- Permission-gated nav visibility

## B) Dispatch + Scheduling
- Create dispatch item
- Assign crew/tech
- Progress through valid statuses
- Verify state transition rules
- Validate weekly availability/summary views

## C) Jobs + Labor (Field Flow)
- Open assigned job
- Clock in with GPS
- Work notes/notebook updates
- Clock out with required fields/photo if enforced
- Submit daily report data

## D) Warehouse + Inventory Operations
- Part search
- Movement wizard actions (pull/stage/receive/adjust)
- Inventory check / spot-check action
- Verify quantity correctness + movement history

## E) Orders + Procurement Lifecycle
- Create JPO
- Approval/review flow
- Convert/advance PO lifecycle
- Return flow with reasons
- Verify order timeline + price history displays where implemented

## F) Tools + Kits
- Checkout tool
- Return tool
- Trigger/verify kit verification behavior
- Maintenance path updates

## G) People + Contacts
- Employee/contact/customer CRUD
- Permission checks
- File/doc attachment flows if enabled
- Import/merge workflows if implemented

## H) Fleet
- Vehicle assignment
- Mileage/reimbursement flow (if enabled)
- Expiry/maintenance alert visibility

## I) Reports + Pre-Billing
- Open each report page
- Apply filters (job/date/employee)
- Validate totals against source records
- Run export/PDF path when configured

## J) Settings + Theme + App Config
- Save settings
- Theme changes apply + persist
- AppConfig persistence and effect verification

---

## 4) Cross-Cutting Validation (Every Pack)

For each scenario pack above, also verify:
- Permission enforcement
- Good empty/loading/error states
- No unresolved console/network errors
- No broken routes/links
- Data integrity is preserved
- No duplicate submissions/race-condition side effects

---

## 5) Responsive + Device Validation

Validate key flows at all required breakpoints:
- 375×812 (iPhone)
- 768×1024 (iPad)
- 1280×800+ (desktop)

Required checks:
- No horizontal overflow
- Touch targets >= 44x44
- No hover-only interaction dependency
- Tables/tabs/forms usable on mobile

If mobile devices are available:
- Test offline usage (disconnect network)
- Create/modify data while offline
- Reconnect and verify sync + conflict handling

If not available, explicitly log hardware/tooling blocker.

---

## 6) Bug Triage + Fix Protocol

For each defect found, record:
- Bug ID
- Module
- Severity (P0/P1/P2)
- Repro steps
- Expected vs actual
- Root cause
- Files changed
- Fix summary
- Retest outcome
- Regression outcome

Never mark fixed until retest + regression both pass.

---

## 7) Required Command Set During Testing

Use these repeatedly:

```bash
# Frontend build gate
cd frontend && npm run build

# Backend test gate
cd backend && python -m pytest tests/ -v

# Backend run
cd backend && uvicorn app.main:app --reload --port 8000

# Frontend run
cd frontend && npm run dev
```

For every meaningful fix batch, rerun build/tests before proceeding.

---

## 8) Documentation Sync Protocol

After each completed test/fix batch, update:
- `docs/plans/full-program-gap-closure-plan.md` (status + notes)
- `docs/implementation-plan.md` (milestone-level updates)
- `directives/v1-development-prompt.md` (current active focus)

Do not allow docs to drift from actual code status.

---

## 9) Completion Gates (All Must Pass)

Only declare testing complete when all are true:

1. Scenario packs A–J pass
2. No open P0/P1 defects
3. Build + tests pass after final fixes
4. No unresolved runtime/import/network errors
5. Responsive checks pass at 375/768/1280
6. Offline/sync validation completed or explicitly blocked with reason
7. Plan docs updated to match reality

---

## 10) Execution Loop

Work in this loop until done:

1. Test batch
2. Log defects
3. Fix batch
4. Retest batch
5. Regression batch
6. Docs/status update
7. Repeat

Keep going until all completion gates are green.

---

## 11) Non-Negotiable Distribution Rule Reminder

Maintain $0 distribution model:
- iOS: Sideloadly + AltServer
- Android: APK sideload
- Do not introduce TestFlight / paid Apple Developer dependencies in docs or flow
