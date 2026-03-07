# Wired-Part — Development Handoff / Implementation Guide

> Last updated: 2026-03-06
> Audience: Any coding agent or developer picking up work from current state.

---

## 1) Start Here (Mandatory Read Order)

1. `directives/v1-development-prompt.md`
2. `CLAUDE.md`
3. `MEMORY.md`
4. `docs/implementation-plan.md`
5. `docs/plans/deployment-master-plan.md`

Do not begin coding until all five are reviewed.

---

## 2) Current Priority Stack

### Priority 0 — Production Readiness Hotfix Pack
Implement these first:
- Supplier deletion FK guard
- Photo sync strategy definition in Phase C sync plan
- Clock-out photo capture input
- Self-service profile + PIN change
- Dispatch/time-off notifications
- Auto-init employee schedule
- Vehicle expiry alerts (insurance/registration)

### Priority 1 — Mobile/Offline Packaging (Phase B onward)
- Capacitor init
- API adapter layer
- Lean TS local services
- Local SQLite + migration strategy

### Priority 2 — Sync + Delivery
- Change-log sync engine
- Conflict merge logic
- Retry queue + status indicators
- iOS/Android packaging and test matrix

### Gap-Triage Rule (Validated Planning)
- Treat audit findings as input, not ground truth — verify against live code before adding to hotfix scope.
- Keep **P0/P1** release-gating; keep **P2** in backlog buckets unless they create immediate production risk.
- Record false positives explicitly so they are not reintroduced (example: Job Tools tab audit finding was stale; tab already exists in `JobDetailPage.tsx`).
- When a P2 is promoted to P1/P0, document why (data integrity, broken workflow, or security impact).

---

## 3) File-by-File Implementation Targets

## Backend
- `backend/app/routers/parts.py` — supplier FK delete guard
- `backend/app/routers/auth.py` + `backend/app/models/auth.py` — self profile/PIN endpoints
- `backend/app/services/scheduling_service.py` — notification hooks
- `backend/app/services/people_service.py` — default schedule init on create
- `backend/app/services/vehicle_service.py` + `backend/app/routers/dashboard.py` — vehicle expiry alerts

## Frontend
- `frontend/src/features/jobs/components/ClockOutFlow.tsx` — photo answer input UI
- `frontend/src/features/settings/pages/` — profile self-service page
- `frontend/src/api/auth.ts` — profile and PIN client functions
- `frontend/src/features/dashboard/` — vehicle alerts card

## Architecture Docs
- `docs/plans/deployment-master-plan.md` — explicit media sync strategy under Phase C

---

## 4) Definition of Done (Release-Gating)

A task is complete only when all are true:
- Business behavior implemented and manually verified
- Permission gating applied (backend + UI)
- Responsive checks pass (375x812, 768x1024, 1280x800)
- Dark mode visually valid
- No regression in related routes/endpoints
- Tests added/updated where critical path is impacted
- Status updated in `directives/v1-development-prompt.md` and `docs/implementation-plan.md`

---

## 5) Minimal Validation Checklist Before Shipping

- [ ] Supplier deletion with references returns controlled 409
- [ ] Clock-out photo questions accept camera/file input
- [ ] Users can update own profile + own PIN securely
- [ ] Dispatch/time-off changes generate notifications
- [ ] New employees get default weekday schedule automatically
- [ ] Dashboard surfaces upcoming vehicle expiry alerts
- [ ] Sync architecture includes binary media/photo handling
- [ ] Mobile build can run offline and re-sync over LAN

---

## 6) Commands

```bash
# Backend
cd backend
pip install -r requirements.txt
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload

# Frontend
cd frontend
npm install
npm run dev

# Tests
cd backend
python -m pytest tests/ -v
```
