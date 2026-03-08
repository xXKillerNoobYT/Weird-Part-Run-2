-- Migration 042: Device Security Protocols
--
-- Implements per-company key hierarchy, device certificates, and cross-company
-- isolation infrastructure.  The shop is the only CA — it signs device certs,
-- holds the root key, and enforces company boundaries in every sync handshake.
--
-- Tables:
--   _company_keys          — company identity + root/sync key material
--   _device_certificates   — signed certificates issued to devices at pairing
--   _shared_channels       — cross-company sharing agreements (backbone, future)
--   _shared_channel_members— companies participating in a shared channel
--   _security_audit_log    — all security-relevant events (pairing, revocations, cert failures)

-- ── Company Keys ────────────────────────────────────────────────
-- Each deployment is a single company.  Multi-company support is baked in
-- so two crews in the same parking lot never leak data to each other.

CREATE TABLE IF NOT EXISTS _company_keys (
    company_id          TEXT PRIMARY KEY,                     -- globally unique (UUID)
    company_name        TEXT NOT NULL DEFAULT 'My Company',
    root_key_public     TEXT NOT NULL,                        -- Ed25519 public key (base64)
    root_key_encrypted  TEXT NOT NULL,                        -- root private key, encrypted with passphrase
    sync_key            TEXT NOT NULL,                        -- derived symmetric key for device comms (base64)
    shop_node_public    TEXT NOT NULL,                        -- this shop node's Ed25519 public key
    shop_node_encrypted TEXT NOT NULL,                        -- shop node private key, encrypted
    key_version         INTEGER NOT NULL DEFAULT 1,           -- bumped on rotation
    rotated_at          TEXT,                                 -- last key rotation timestamp
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT NOT NULL DEFAULT (datetime('now'))
);


-- ── Device Certificates ─────────────────────────────────────────
-- Issued by the shop at pairing time.  Every sync handshake starts with
-- "show me your certificate + company_id" — mismatches = no data.

CREATE TABLE IF NOT EXISTS _device_certificates (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id           TEXT NOT NULL REFERENCES _device_registry(device_id) ON DELETE CASCADE,
    company_id          TEXT NOT NULL REFERENCES _company_keys(company_id),
    device_public_key   TEXT NOT NULL,                        -- device's Ed25519 public key (base64)
    certificate_data    TEXT NOT NULL,                        -- JSON: {device_id, company_id, device_public_key, issued_at, expires_at}
    signature           TEXT NOT NULL,                        -- shop's Ed25519 signature over certificate_data (base64)
    issued_at           TEXT NOT NULL DEFAULT (datetime('now')),
    expires_at          TEXT NOT NULL,                        -- cert validity window
    revoked_at          TEXT,                                 -- NULL = active, non-NULL = revoked
    revoke_reason       TEXT,                                 -- e.g. 'device_lost', 'employee_terminated', 'key_rotation'
    issued_by           INTEGER REFERENCES users(id),

    UNIQUE(device_id, company_id)                            -- one active cert per device per company
);

CREATE INDEX IF NOT EXISTS idx_device_certs_device
    ON _device_certificates(device_id);
CREATE INDEX IF NOT EXISTS idx_device_certs_company
    ON _device_certificates(company_id);
CREATE INDEX IF NOT EXISTS idx_device_certs_expires
    ON _device_certificates(expires_at);


-- ── Shared Channels (Cross-Company Backbone) ────────────────────
-- Future feature: opt-in, scoped, time-bounded data sharing between companies.
-- The schema is reserved now so we never have to restructure later.

CREATE TABLE IF NOT EXISTS _shared_channels (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_name        TEXT NOT NULL,
    owner_company_id    TEXT NOT NULL REFERENCES _company_keys(company_id),
    scope_json          TEXT NOT NULL DEFAULT '{}',           -- {job_ids:[], data_types:[], ...}
    permissions_json    TEXT NOT NULL DEFAULT '{}',           -- {read:true, write:false, media:false, ...}
    expires_at          TEXT,                                 -- NULL = no expiry
    is_active           INTEGER NOT NULL DEFAULT 1,
    created_by          INTEGER REFERENCES users(id),
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS _shared_channel_members (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id          INTEGER NOT NULL REFERENCES _shared_channels(id) ON DELETE CASCADE,
    company_id          TEXT NOT NULL REFERENCES _company_keys(company_id),
    role                TEXT NOT NULL DEFAULT 'participant',  -- 'owner' | 'participant' | 'observer'
    accepted_at         TEXT,                                 -- NULL = pending invitation
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),

    UNIQUE(channel_id, company_id)
);


-- ── Security Audit Log ──────────────────────────────────────────
-- Immutable append-only log of security events (pairing, revocations,
-- handshake failures, cert expirations, key rotations, etc.)

CREATE TABLE IF NOT EXISTS _security_audit_log (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type          TEXT NOT NULL,                        -- pairing_success, pairing_failed, cert_issued,
                                                             -- cert_revoked, cert_expired, handshake_failed,
                                                             -- key_rotated, device_revoked, sync_rejected
    device_id           TEXT,
    company_id          TEXT,
    actor_user_id       INTEGER,                             -- who triggered the event (NULL for system)
    details_json        TEXT NOT NULL DEFAULT '{}',           -- event-specific payload
    ip_address          TEXT,
    recorded_at         TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_security_audit_type
    ON _security_audit_log(event_type);
CREATE INDEX IF NOT EXISTS idx_security_audit_device
    ON _security_audit_log(device_id);
CREATE INDEX IF NOT EXISTS idx_security_audit_time
    ON _security_audit_log(recorded_at);
