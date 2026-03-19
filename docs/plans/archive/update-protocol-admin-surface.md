# Update Protocol Admin Surface (Plan + Implementation)

> **Date:** 2026-03-07
> **Status:** ✅ Initial slice implemented
> **Primary architecture doc:** `docs/plans/Update protocol.md`

---

## Objective

Convert update protocol architecture from docs into an operational in-app admin surface so shops can:

- manage version registry
- publish approved versions
- monitor per-platform fleet targets
- see device rollout status
- see backup snapshot records

This applies to desktop and mobile fleets (Windows, macOS, iOS, Android).

---

## Existing baseline discovered

Already implemented in backend before this task:

- Migration: `043_update_protocol.sql`
- Service: `backend/app/services/update_protocol_service.py`
- Router: `backend/app/routers/updates.py`
- Tests: `backend/tests/test_update_protocol.py`

Missing piece was an admin UI in frontend settings.

---

## Implemented in this slice

### Frontend API client
- Added: `frontend/src/api/updates.ts`
- Includes typed wrappers for:
  - versions
  - validations
  - fleet targets
  - device statuses
  - backup snapshots

### Frontend settings page
- Added: `frontend/src/features/settings/pages/UpdateProtocolPage.tsx`
- Includes:
  - Manual version registration form
  - Version registry list + publish action
  - Fleet targets list + target edit + refresh counts
  - Device update status panel
  - Backup snapshot panel
  - Protocol guardrail note (desktop + mobile parity)

### Navigation and routes
- Updated `frontend/src/lib/navigation.ts`:
  - New settings tab: **Update Protocol** (`/settings/updates`)
- Updated `frontend/src/App.tsx`:
  - New route: `/settings/updates`

---

## Next steps (recommended)

1. Add validation control actions in UI (`create_validation`, `update_validation` forms)
2. Add publish guard in backend (block publish unless required platforms passed)
3. Add device pending-chain viewer (`/devices/{id}/pending`) in UI
4. Add backup create/restore action controls in UI
5. Add failure-report action hook (email/issue dispatch) after blocked validation

---

## Outcome

The update protocol is now both:

- **Documented** (architecture and safety rules)
- **Operable** (shop admin surface in Settings)

This establishes the control plane needed for staged, platform-aware, chain-safe updates across both desktop and mobile devices.
