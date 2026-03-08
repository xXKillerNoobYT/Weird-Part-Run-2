# Mobile Device Bootstrap Plan (V1.0.0)

> **Date:** 2026-03-07
> **Status:** ✅ Complete (V1.0.0 baseline)
> **Version target:** V1.0.0
> **Purpose:** App-store bootstrap shell pairs with shop and receives fleet-approved program package.

---

## 1) Architecture intent

Bootstrap app is intentionally minimal:
- pairing and handshake only,
- receives shop-approved artifact manifest,
- installs real app package,
- reports install progress/errors.

Bootstrap does **not** carry business logic, sync business tables, or module UI.

---

## 2) V1.0.0 backend implementation delivered

### 2.1 Schema

Migration added:
- `backend/app/migrations/040_bootstrap_shell.sql`

Tables:
- `_bootstrap_pairing_codes`
- `_bootstrap_artifacts`
- `_bootstrap_install_events`

### 2.2 Service

Service added:
- `backend/app/services/bootstrap_service.py`

Capabilities:
- pairing code create/validate/consume
- active artifact register and lookup
- bootstrap handshake orchestration
- install event logging + history

### 2.3 API Router

Router added and mounted:
- `backend/app/routers/bootstrap.py`
- mounted in `backend/app/main.py`

Endpoints:
- `POST /api/bootstrap/pairing-codes` (admin)
- `POST /api/bootstrap/handshake` (bootstrap client)
- `POST /api/bootstrap/artifacts` (admin)
- `GET /api/bootstrap/artifacts` (admin)
- `POST /api/bootstrap/install-events` (bootstrap client)
- `GET /api/bootstrap/install-events` (admin)

### 2.4 Frontend API contract helpers

Added to:
- `frontend/src/api/bootstrap.ts`

Typed bootstrap helpers are available for pairing, handshake, artifact management, and install telemetry wiring.

---

## 3) Bootstrap first-run protocol (V1)

1. Admin generates pairing code at shop.
2. Bootstrap app enters pairing code + device metadata.
3. `POST /api/bootstrap/handshake` validates and consumes code.
4. Shop registers device and returns active platform artifact + sync endpoint map.
5. Bootstrap app downloads, verifies checksum/signature, installs real app.
6. Bootstrap app posts install event status (`requested/downloaded/installed/failed`).

---

## 4) Security / safety constraints

- Pairing codes are one-time and expiry-bound.
- Admin permission required for code/artifact management.
- Bootstrap handshake never grants business data directly.
- Artifact delivery is platform-scoped and fleet-controlled by shop.
- Install telemetry is auditable per-device.

---

## 5) Test coverage

Added test file:
- `backend/tests/test_bootstrap_router.py`

Covers:
- pairing code creation,
- artifact registration,
- unauthenticated bootstrap handshake with valid pairing code,
- install event logging,
- admin event listing.

---

## 6) Implementation status

### 6.1 Bootstrap client UI/app flow (implemented)
- Pairing screen + code entry
- Device identity bootstrap (public key + metadata inputs)
- Install progress/status controls (`requested`, `downloaded`, `installed`, `failed`)

Implemented as **Bootstrap Client Flow (Simulator)** in:
- `frontend/src/features/settings/pages/BootstrapAdminPage.tsx`

### 6.2 Shop admin UI (implemented)
- Artifact upload/activation screen
- Pairing code management screen
- Bootstrap install telemetry dashboard

Implemented in:
- `frontend/src/features/settings/pages/BootstrapAdminPage.tsx`
- `frontend/src/api/bootstrap.ts`
- Route: `/settings/bootstrap`
- Settings navigation tab: **Bootstrap**

### 6.3 Backend management support (expanded)
- Added pairing code listing endpoint for admin management:
	- `GET /api/bootstrap/pairing-codes`
- Added test coverage for pairing code listing.

---

## 7) Remaining planned work (future hardening)

### 7.1 Artifact delivery hardening
- Signed manifest verification on client
- Resume/chunked download support
- Rollback bundle fallback

### 7.2 Production bootstrap shell packaging
- Move simulator flow into dedicated standalone bootstrap shell build target (separate app-store package)
- Add OTA-safe installer orchestration per platform

---

## 8) Definition of done (V1.0.0)

- [x] Shop-side pairing + handshake backend exists
- [x] Platform artifact manifest registry exists
- [x] Install event telemetry exists
- [x] Router mounted and tested
- [x] Bootstrap client screens implemented
- [ ] Artifact download/install verification integrated on mobile shells

---

## 9) Notes

This plan intentionally keeps the bootstrap backend independent from app-store release cadence. Shop remains authoritative for what version enters the fleet.
