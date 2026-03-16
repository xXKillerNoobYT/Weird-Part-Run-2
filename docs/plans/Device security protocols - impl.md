# Device Security Protocols — Implementation Plan V1.0.0

> **Status:** ✅ Fully implemented — Ed25519, BT handshake, at-rest encryption, sharing UI
> **Migrations:** `042_device_security.sql`, `043_ed25519_upgrade.sql`
> **Service:** `device_security_service.py` (Ed25519 + HMAC backward compat)
> **Router:** `security.py` (mounted at `/api/security`, 17 endpoints)
> **Tests:** `test_device_security.py` (8 tests) + `test_security_integration.py` (7 tests) = 15 total
> **Frontend:** `security-service.ts` (device-at-rest encryption), `SecurityAdminPage.tsx` (5-card admin)

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

## 3. Crypto Model (V1.1 — Ed25519)

V1.1 uses **Ed25519** for signing via the `cryptography` library and **HKDF-SHA256**
for sync key derivation. Legacy HMAC-SHA256 certificates (V1.0) are still accepted
for backward compatibility — `verify_certificate()` tries Ed25519 first, then
falls back to HMAC when `crypto_version < 2`. New certificates are always Ed25519.

| Operation | V1.0 (Legacy) | V1.1 (Current) |
|-----------|---------------|----------------|
| Keypair generation | `os.urandom(32)` + SHA256 | `Ed25519PrivateKey.generate()` |
| Signing | HMAC-SHA256 | Ed25519 detached signature (64-byte) |
| Sync key derivation | HMAC(root_secret, "sync-v1") | HKDF-SHA256 via `cryptography` |
| Cert verification | HMAC compare_digest | Ed25519 verify (HMAC fallback) |

`CRYPTO_VERSION = 2` is stamped on company keys and device certificates.
Migration `043_ed25519_upgrade.sql` adds `crypto_version` columns to both tables.

---

## 4. API Endpoints (17 total)

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
| POST | `/api/security/channels/{id}/deactivate` | manage_people | Soft-delete a channel |
| POST | `/api/security/channels/{id}/accept` | manage_people | Accept channel invitation |

### Bluetooth Handshake
| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/api/security/bt/hello` | user | Create BT_HELLO payload with nonce |
| POST | `/api/security/bt/verify-hello` | user | Verify incoming BT_HELLO, return ACK |
| POST | `/api/security/bt/verify-ack` | user | Verify ACK, complete mutual trust |

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

## 7. Cross-Company Sharing

Implemented via `_shared_channels` + `_shared_channel_members` tables plus
the `SharedChannelsCard` in `SecurityAdminPage.tsx`.

- Explicit opt-in, scoped, time-bounded data sharing
- Shop↔shop only (no device-to-device cross-company)
- Per-field redaction rules (via `scope` JSON)
- Supervisors/managers create channels, workers just see shared data
- Channels can be created, listed, expanded for member details, deactivated, and accepted
- Backend: `create_shared_channel()`, `list_shared_channels()`, `deactivate_shared_channel()`, `accept_channel_invitation()`
- Frontend: 5th card on SecurityAdminPage with create form, channel list, member badges

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
| `shared_channel_deactivated` | Channel soft-deleted |
| `bt_hello_created` | BT handshake initiated |
| `bt_hello_verified` | Incoming BT_HELLO verified, ACK sent |
| `bt_ack_verified` | BT ACK verified, mutual trust established |
| `bt_hello_rejected` | BT_HELLO failed (cross-company or bad cert) |

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
  - `frontend/src/features/settings/pages/SecurityAdminPage.tsx` — 5 card-sections:
    1. **Company Setup** — initialise company, view key details
    2. **Device Certificates** — per-device cert status, revoke button
    3. **Shared Channels** — create/list/deactivate/accept channels, member management
    4. **Key Rotation** — danger-zone with 2-step confirmation
    5. **Security Audit Log** — filterable event table
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

### Completed (2026-03-08 — Ed25519 & Security Hardening)

- [x] **Upgrade to Ed25519** — swapped HMAC-SHA256 for Ed25519 asymmetric signatures
  - Added `cryptography>=44.0.0` as explicit dependency
  - `_generate_keypair()` → `Ed25519PrivateKey.generate()` (raw 32-byte keys)
  - `_sign()` → Ed25519 detached signature (64-byte base64)
  - `_verify()` → `Ed25519PublicKey.verify()` with `InvalidSignature` catch
  - `_derive_sync_key()` → HKDF-SHA256 via `cryptography.hazmat.primitives.kdf.hkdf`
  - Legacy backward compat: `_sign_hmac()` / `_verify_hmac()` retained; `verify_certificate()` tries Ed25519 first, falls back to HMAC for `crypto_version < 2`
  - `CRYPTO_VERSION = 2` stamped on company keys and certificates
  - Migration `043_ed25519_upgrade.sql` adds `crypto_version` columns
  - `rotate_keys()` always upgrades to latest crypto version

- [x] **Bluetooth handshake** — 3-step mutual cert exchange protocol for mesh sync
  - `bt_create_hello()` — generates BT_HELLO with 128-bit nonce, device cert, Ed25519 signature
  - `bt_verify_hello()` — verifies initiator cert, enforces same-company, returns BT_HELLO_ACK
  - `bt_verify_ack()` — verifies responder cert + nonce round-trip, completes mutual trust
  - 3 new endpoints: `POST /bt/hello`, `POST /bt/verify-hello`, `POST /bt/verify-ack`
  - Nonce replay protection via audit log cross-check
  - Cross-company BT connections rejected with `bt_hello_rejected` audit event
  - Tests: `test_bt_handshake_full_flow`, `test_bt_handshake_cross_company_rejected`

- [x] **Device-at-rest encryption** — OS keystore integration via Capacitor Preferences
  - Created `frontend/src/local/services/security-service.ts` (~290 lines)
  - Secure storage abstraction: `Preferences` on native (iOS/Android sandboxed + OS-encrypted), in-memory `Map` on web
  - `initialiseDeviceSecurity(deviceId)` — generates 256-bit DB encryption key on first launch
  - `getDbEncryptionKey()` — returns encryption key for SQLite at-rest encryption
  - `storeDeviceKeypair()` / `getDevicePublicKey()` — secure key material storage
  - `storeCertificate()` / `getStoredCertificate()` / `isCertificateValid()` — certificate lifecycle
  - `getSyncAuthFields()` — returns cert fields for sync request authentication
  - `createBtHello()` — client-side BT_HELLO creation (offline-capable, uses Web Crypto for nonce)
  - `clearDeviceSecurity()` / `rotateDbEncryptionKey()` — security data wipe and key rotation

- [x] **Cross-company sharing UI** — supervisor-facing channel management
  - Added `SharedChannelsCard` to `SecurityAdminPage.tsx` (5th card, ~250 lines)
  - Create channel form: name, partner company IDs, scope JSON, permissions JSON
  - Channel list with expand/collapse details per channel
  - Deactivate button for channel owners (soft-delete)
  - Accept invitation button for pending channel members
  - Member list with role and acceptance status badges
  - Backend: `deactivate_shared_channel()`, `accept_channel_invitation()` service methods
  - API: `deactivateSharedChannel()`, `acceptChannelInvitation()` client functions
  - BT handshake API: `btCreateHello()`, `btVerifyHello()`, `btVerifyAck()` client functions
