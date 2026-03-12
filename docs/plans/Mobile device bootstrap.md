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
- Resume/chunked download support (currently full re-download on failure)
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
- [x] Artifact download/install verification integrated on mobile shells

---

## 9) Artifact download/install verification (implemented 2026-03-07)

### 9.1 Backend additions

**Migration:**
- `backend/app/migrations/045_bootstrap_verification.sql` — Expanded `_bootstrap_install_events` with 8-state lifecycle (`requested|downloading|downloaded|verifying|verified|installing|installed|failed`), progress tracking (`progress_pct`, `bytes_downloaded`, `bytes_total`), and verification fields (`checksum_computed`, `checksum_verified`, `signature_verified`).

**Service (bootstrap_service.py):**
- `verify_artifact(artifact_id, client_checksum_sha256)` — Compares client SHA-256 against stored checksum, optionally verifies Ed25519 signature using shop's `shop_node_public` key. Returns `{valid, checksum_match, signature_valid, artifact_id, version, detail}`.
- `sign_artifact(artifact_id)` — Signs artifact checksum with shop's Ed25519 node private key. Signature covers `"{platform}:{version}:{checksum_sha256}"`. Updates artifact record.
- `log_install_event()` — Extended with progress + verification fields.

**Router (bootstrap.py):**
- `POST /api/bootstrap/artifacts/verify` — No auth (device-facing), returns verification result
- `GET /api/bootstrap/artifacts/active/{platform}` — No auth, returns active artifact for platform
- `POST /api/bootstrap/artifacts/{artifact_id}/sign` — Admin-only, signs artifact with shop Ed25519 key

### 9.2 Frontend additions

**API (bootstrap.ts):**
- `getActiveArtifact(platform)` — Fetch active artifact metadata
- `verifyArtifact(payload)` — Server-side checksum + signature verification
- `signArtifact(artifactId)` — Admin artifact signing
- Expanded types: `ArtifactVerifyPayload`, `ArtifactVerifyResult`, 8-state `InstallStatus`

**Local service (bootstrap-client.ts):**
- `runBootstrapInstall(opts)` — Complete orchestrator: fetch artifact → download with streaming progress → SHA-256 checksum → server verification → save to device → report telemetry
- `ChunkedHasher` — Streaming SHA-256 via Web Crypto API
- `saveFile()` — Native: `@capacitor/filesystem` into `bootstrap/` dir; Web: blob URL fallback
- `getRetryableDownload()` — Resume interrupted downloads
- Progress persistence via `@capacitor/preferences`
- `getStatusLabel()` / `getStatusVariant()` — UI helpers

**Admin UI (BootstrapAdminPage.tsx):**
- Artifact table now shows signature status + "Sign" button per artifact
- Client flow card upgraded from manual simulator to automated download/verify/install with real-time progress panel
- Install telemetry table shows progress %, checksum verified ✓, signature verified ✓
- `BootstrapProgressPanel` component with progress bar, verification status indicators, SHA-256 display

### 9.3 Vite config
- Added `@capacitor/filesystem` to `CAPACITOR_PACKAGES` array (externalized for web build, available at runtime on native)

### 9.4 Test coverage (10 tests)
- Original 3 flow tests
- `test_artifact_verify_correct_checksum` — Correct checksum returns valid
- `test_artifact_verify_wrong_checksum` — Wrong checksum returns invalid
- `test_artifact_verify_nonexistent_artifact` — Missing artifact returns not found
- `test_active_artifact_by_platform` — Platform-specific artifact lookup
- `test_active_artifact_404_for_missing_platform` — 404 for missing platform
- `test_artifact_sign_flow` — End-to-end sign + verify signature populated
- `test_extended_install_event_fields` — Progress, checksum, signature fields recorded

---

## 10) Notes

This plan intentionally keeps the bootstrap backend independent from app-store release cadence. Shop remains authoritative for what version enters the fleet.
