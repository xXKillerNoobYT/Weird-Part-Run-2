-- Migration 043: Ed25519 Crypto Upgrade + BT Handshake Support
--
-- Upgrades the device security system from HMAC-SHA256 (V1.0) to Ed25519 (V1.1).
-- Adds crypto_version tracking and Bluetooth handshake audit event types.
--
-- Changes:
--   1. Add crypto_version column to _company_keys (default 1 for existing, 2 for new)
--   2. Add crypto_version column to _device_certificates for per-cert tracking
--   3. Index for BT handshake audit lookups

-- ── Crypto version tracking on company keys ──────────────────────
-- 1 = HMAC-SHA256 (legacy), 2 = Ed25519 (current)
ALTER TABLE _company_keys ADD COLUMN crypto_version INTEGER NOT NULL DEFAULT 1;

-- ── Crypto version on individual certificates ────────────────────
ALTER TABLE _device_certificates ADD COLUMN crypto_version INTEGER NOT NULL DEFAULT 1;

-- ── Index for BT handshake audit queries ─────────────────────────
CREATE INDEX IF NOT EXISTS idx_security_audit_bt
    ON _security_audit_log(event_type)
    WHERE event_type IN ('bt_handshake_success', 'bt_handshake_rejected', 'bt_handshake_complete');
