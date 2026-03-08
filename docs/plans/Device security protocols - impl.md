# Device Security Protocols — Implementation Plan V1.0.0

> **Status:** ✅ Backend implemented (migration, service, router, tests)
> **Migration:** `042_device_security.sql`
> **Service:** `device_security_service.py`
> **Router:** `security.py` (mounted at `/api/security`)
> **Tests:** `test_device_security.py` (4 tests)

---

## 1. Overview

Per-company key hierarchy, device certificates, and cross-company isolation.
The shop is the sole Certificate Authority — it holds root keys, signs device
certificates at pairing, and enforces company boundaries in every sync handshake.

---

## 2. Database Tables

| Table | Purpose |
|-------|---------|
| `_company_keys` | Company identity + root/sync key material (Ed25519 → HMAC-SHA256 in V1.0) |
| `_device_certificates` | Signed certs issued to devices, one active per device+company |
| `_shared_channels` | Cross-company sharing agreements (backbone, future) |
| `_shared_channel_members` | Companies participating in shared channels |
| `_security_audit_log` | Immutable append-only security event trail |

---

## 3. Crypto Model (V1.0)

V1.0 uses **HMAC-SHA256** for signing and **HKDF-like derivation** (no external
crypto library needed). Future upgrade path: swap `_generate_keypair()` and
`_sign()` / `_verify()` for Ed25519 via `cryptography` or `PyNaCl` without
changing the service interface.

| Operation | V1.0 Implementation | Future (V2.0) |
|-----------|---------------------|---------------|
| Keypair generation | `os.urandom(32)` + SHA256 | Ed25519 |
| Signing | HMAC-SHA256 | Ed25519 detached signature |
| Sync key derivation | HMAC(root_secret, "sync-v1") | HKDF-SHA256 |
| Cert verification | HMAC compare_digest | Ed25519 verify |

---

## 4. API Endpoints (12 total)

### Company Management
| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/api/security/company/init` | admin | Initialise company keys (idempotent) |
| GET | `/api/security/company` | admin | Get company key metadata |
| GET | `/api/security/companies` | admin | List all companies (summary) |
| POST | `/api/security/company/rotate` | admin | Rotate root+shop keys, revoke all certs |

### Certificate Lifecycle
| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/api/security/certs/issue` | admin | Issue signed cert for device |
| POST | `/api/security/certs/verify` | user | Verify cert in sync handshake |
| GET | `/api/security/certs/{device_id}` | user | Get active cert for device |
| POST | `/api/security/certs/revoke` | admin | Revoke device cert immediately |

### Cross-Company Channels (Backbone)
| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/api/security/channels` | admin | Create sharing channel |
| GET | `/api/security/channels` | admin | List active channels |

### Audit
| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/api/security/audit` | admin | Security audit log (filterable) |

---

## 5. Key Lifecycle

1. **Company init** → root keypair + shop keypair + derived sync key generated
2. **Device pairing** → device presents `public_key`, shop signs cert binding
   `(device_id, company_id, public_key, expiry)`
3. **Every sync** → device presents cert + company_id → shop verifies signature,
   expiry, revocation status
4. **Key rotation** → new keypair, new sync key, all existing certs revoked
   (devices must re-pair)

---

## 6. Company Isolation

- Every sync handshake starts with cert exchange
- Cert verification checks: signature → device_id match → company_id match → expiry → revocation
- Mismatched company_id = **no sync, no gossip, no data transfer**
- Even if two companies are in the same parking lot, their devices are cryptographically isolated

---

## 7. Cross-Company Sharing (Future)

Schema is reserved via `_shared_channels` + `_shared_channel_members`.
When ready, the sharing backbone provides:

- Explicit opt-in, scoped, time-bounded data sharing
- Shop↔shop only (no device-to-device cross-company)
- Per-field redaction rules
- Supervisors/managers create channels, workers just see shared data

---

## 8. Security Audit Events

All security operations are logged immutably:

| Event Type | Trigger |
|------------|---------|
| `company_initialised` | New company keys generated |
| `cert_issued` | Device certificate signed |
| `cert_revoked` | Certificate manually revoked |
| `cert_expired` | Expired cert detected during verification |
| `handshake_failed` | Signature or company_id mismatch |
| `key_rotated` | Company keys rotated |
| `shared_channel_created` | New cross-company channel |

---

## 9. Remaining Work

### Completed (2026-03-08)

- [x] **Bootstrap integration** — auto-issue cert during pairing handshake
  - `BootstrapService.bootstrap_handshake()` now calls `DeviceSecurityService.issue_certificate()`
    when the device provides a `public_key`
  - Idempotent: auto-creates `"default"` company if none exists
  - Certificate included in handshake response so device can authenticate from first sync
  - Best-effort: if cert issuance fails, handshake still succeeds (backward compat)

- [x] **Sync push cert verification** — gate sync behind cert check
  - `SyncPushPayload` extended with optional `company_id`, `certificate_data`, `signature`
  - When any company exists in `_company_keys`, sync push requires a valid cert
  - Invalid/revoked/missing cert → rejection with reason
  - No companies configured → sync proceeds unauthenticated (backward compat)

- [x] **Sync pull/initial cert verification parity** — full handshake coverage
  - `/api/sync/pull` now accepts optional `company_id`, `certificate_data`, `signature`
  - `InitialSyncRequest` now supports optional cert fields for secure initial bootstrap sync
  - When any company exists in `_company_keys`, both endpoints require a valid cert
  - Invalid/revoked/missing cert → rejection with reason
  - No companies configured → endpoints remain backward compatible

- [x] **Frontend admin pages** — company setup wizard, cert management, audit viewer
  - `frontend/src/api/security.ts` — 12 API client functions with TypeScript interfaces
  - `frontend/src/features/settings/pages/SecurityAdminPage.tsx` — 4 card-sections:
    1. **Company Setup** — initialise company, view key details
    2. **Device Certificates** — per-device cert status, revoke button
    3. **Key Rotation** — danger-zone with 2-step confirmation
    4. **Security Audit Log** — filterable event table
  - Route: `/settings/security` (requires `manage_people` permission)

- [x] **datetime.utcnow() cleanup** — replaced across 6 files:
  - `sync_service.py` (4 occurrences)
  - `sync.py` router (3 occurrences)
  - `labor_service.py` (2 occurrences, with TZ-aware subtraction fix)
  - `job_preferences_service.py` (1 occurrence)
  - `po_conversation_service.py` (1 occurrence)

- [x] **Security integration tests expanded**
  - `test_security_integration.py` now covers:
    - bootstrap auto-cert issuance
    - sync push certificate gate
    - **sync pull certificate gate**
    - **initial sync certificate gate**
    - revoked certificate rejection

### Still Future

- [ ] **Upgrade to Ed25519** — swap HMAC for asymmetric signatures (add `cryptography` lib)
- [ ] **Bluetooth handshake** — cert exchange protocol for mesh sync (Phase 11)
- [ ] **Device-at-rest encryption** — OS keystore integration on mobile (Capacitor only)
- [ ] **Cross-company sharing UI** — supervisor-facing channel management (backend done, frontend deferred)
