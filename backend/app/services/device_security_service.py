"""
Device Security Service — company keys, device certificates, and security audit.

Implements the V1.1 device security protocol:
1. Company initialisation — generate Ed25519 root keypair, derive sync key
2. Device certificate issuance — signed at pairing time (Ed25519 signatures)
3. Certificate verification — validate cert + company_id match
4. Certificate revocation — block a device immediately
5. Key rotation — rotate company keys + re-issue certs
6. Cross-company isolation — enforce company_id boundaries
7. Security audit logging — immutable event trail
8. Bluetooth handshake — mutual cert exchange for mesh sync
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import os
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

import aiosqlite

from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.exceptions import InvalidSignature

logger = logging.getLogger(__name__)

# ── Ed25519 crypto helpers (V1.1) ───────────────────────────────
# Upgraded from HMAC-SHA256 (V1.0) to Ed25519 asymmetric signatures.
# The service interface is unchanged — only the underlying primitives differ.
#
# Key format: base64-encoded raw bytes
#   - Private key: 32 bytes (Ed25519 seed)
#   - Public key:  32 bytes (Ed25519 compressed point)
#
# Backward compatibility: _verify_legacy_hmac() handles certs signed
# with the old HMAC-SHA256 scheme during a migration window.

CRYPTO_VERSION = 2  # 1 = HMAC-SHA256 (v1.0), 2 = Ed25519 (v1.1)


def _generate_keypair() -> tuple[str, str]:
    """Generate an Ed25519 keypair.

    Returns (public_b64, private_b64) where both are base64-encoded
    raw 32-byte keys.
    """
    private_key = Ed25519PrivateKey.generate()
    private_bytes = private_key.private_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PrivateFormat.Raw,
        encryption_algorithm=serialization.NoEncryption(),
    )
    public_bytes = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    return base64.b64encode(public_bytes).decode(), base64.b64encode(private_bytes).decode()


def _derive_sync_key(root_secret_b64: str, label: str = "sync-v1") -> str:
    """Derive a symmetric sync key from the root secret via HKDF-SHA256.

    Used for encrypting sync payloads in transit (AES-GCM in future).
    """
    root_secret = base64.b64decode(root_secret_b64)
    hkdf = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=None,
        info=label.encode(),
    )
    derived = hkdf.derive(root_secret)
    return base64.b64encode(derived).decode()


def _sign(private_key_b64: str, message: str) -> str:
    """Ed25519 signature over a message string.

    Returns a base64-encoded 64-byte signature.
    """
    private_bytes = base64.b64decode(private_key_b64)
    private_key = Ed25519PrivateKey.from_private_bytes(private_bytes)
    sig = private_key.sign(message.encode())
    return base64.b64encode(sig).decode()


def _verify(public_key_b64: str, message: str, signature_b64: str) -> bool:
    """Verify an Ed25519 signature against a public key.

    Returns True if the signature is valid, False otherwise.
    """
    try:
        public_bytes = base64.b64decode(public_key_b64)
        public_key = Ed25519PublicKey.from_public_bytes(public_bytes)
        sig = base64.b64decode(signature_b64)
        public_key.verify(sig, message.encode())
        return True
    except (InvalidSignature, ValueError, Exception):
        return False


# ── Legacy HMAC-SHA256 helpers (V1.0 backward compat) ────────────
# During migration, certs signed with HMAC can still be verified.
# New certs always use Ed25519.

def _sign_hmac(secret_b64: str, message: str) -> str:
    """HMAC-SHA256 signature (legacy V1.0)."""
    secret = base64.b64decode(secret_b64)
    sig = hmac.new(secret, message.encode(), hashlib.sha256).digest()
    return base64.b64encode(sig).decode()


def _verify_hmac(secret_b64: str, message: str, signature_b64: str) -> bool:
    """Verify an HMAC-SHA256 signature (legacy V1.0)."""
    expected = _sign_hmac(secret_b64, message)
    return hmac.compare_digest(expected, signature_b64)


class DeviceSecurityService:
    """Handles company key management, device certificates, and security audit."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    # ── Company Initialisation ───────────────────────────────────

    async def initialise_company(
        self,
        *,
        company_id: str,
        company_name: str = "My Company",
    ) -> dict:
        """Generate Ed25519 keys for a new company and store them.

        Idempotent — if the company already exists, return it unchanged.
        """
        existing = await self.get_company(company_id)
        if existing:
            return existing

        root_pub, root_secret = _generate_keypair()
        shop_pub, shop_secret = _generate_keypair()
        sync_key = _derive_sync_key(root_secret)

        await self.db.execute(
            """
            INSERT INTO _company_keys (
                company_id, company_name,
                root_key_public, root_key_encrypted,
                sync_key,
                shop_node_public, shop_node_encrypted,
                crypto_version
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (company_id, company_name, root_pub, root_secret, sync_key,
             shop_pub, shop_secret, CRYPTO_VERSION),
        )
        await self.db.commit()

        await self._audit("company_initialised", company_id=company_id, details={
            "company_name": company_name,
            "crypto_version": CRYPTO_VERSION,
        })

        return await self.get_company(company_id)  # type: ignore[return-value]

    async def get_company(self, company_id: str) -> dict | None:
        cursor = await self.db.execute(
            "SELECT * FROM _company_keys WHERE company_id = ?", (company_id,),
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

    async def list_companies(self) -> list[dict]:
        cursor = await self.db.execute(
            "SELECT company_id, company_name, key_version, created_at, updated_at "
            "FROM _company_keys ORDER BY created_at",
        )
        return [dict(r) for r in await cursor.fetchall()]

    # ── Device Certificate Issuance ──────────────────────────────

    async def issue_certificate(
        self,
        *,
        device_id: str,
        company_id: str,
        device_public_key: str,
        issued_by: int | None = None,
        validity_days: int = 365,
    ) -> dict:
        """Issue an Ed25519-signed certificate for a device.

        The certificate binds (device_id, company_id, device_public_key)
        and is signed by the shop's root private key.
        """
        company = await self.get_company(company_id)
        if not company:
            raise ValueError(f"Company {company_id} not found — initialise it first")

        # Revoke any existing cert for this device+company
        await self.db.execute(
            """
            UPDATE _device_certificates
            SET revoked_at = datetime('now'), revoke_reason = 'superseded'
            WHERE device_id = ? AND company_id = ? AND revoked_at IS NULL
            """,
            (device_id, company_id),
        )

        expires_at = (datetime.now(timezone.utc) + timedelta(days=validity_days)).isoformat()
        issued_at = datetime.now(timezone.utc).isoformat()

        cert_payload = json.dumps({
            "device_id": device_id,
            "company_id": company_id,
            "device_public_key": device_public_key,
            "issued_at": issued_at,
            "expires_at": expires_at,
            "key_version": company["key_version"],
            "crypto_version": CRYPTO_VERSION,
        }, separators=(",", ":"), sort_keys=True)

        # Sign with root private key (Ed25519)
        signature = _sign(company["root_key_encrypted"], cert_payload)

        cursor = await self.db.execute(
            """
            INSERT INTO _device_certificates (
                device_id, company_id, device_public_key,
                certificate_data, signature,
                issued_at, expires_at, issued_by
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (device_id, company_id, device_public_key,
             cert_payload, signature, issued_at, expires_at, issued_by),
        )
        cert_id = cursor.lastrowid
        await self.db.commit()

        await self._audit("cert_issued", device_id=device_id, company_id=company_id,
                          actor=issued_by, details={"cert_id": cert_id, "expires_at": expires_at})

        return await self._get_cert(cert_id)

    async def verify_certificate(
        self,
        *,
        device_id: str,
        company_id: str,
        certificate_data: str,
        signature: str,
    ) -> dict:
        """Verify a device certificate against the company root key.

        Supports both Ed25519 (crypto_version=2) and legacy HMAC-SHA256
        (crypto_version=1) signatures for backward compatibility during
        migration.  Returns ``valid``: bool and ``reason`` on failure.
        """
        company = await self.get_company(company_id)
        if not company:
            return {"valid": False, "reason": "unknown_company"}

        crypto_ver = company.get("crypto_version", 1)

        # 1. Signature check — try Ed25519 first, fall back to legacy HMAC
        sig_valid = False
        if crypto_ver >= 2:
            # Ed25519: verify with root public key
            sig_valid = _verify(company["root_key_public"], certificate_data, signature)
        if not sig_valid:
            # Fall back: legacy HMAC (root_key_encrypted was the HMAC secret)
            sig_valid = _verify_hmac(company["root_key_encrypted"], certificate_data, signature)
        if not sig_valid:
            await self._audit("handshake_failed", device_id=device_id, company_id=company_id,
                              details={"reason": "invalid_signature"})
            return {"valid": False, "reason": "invalid_signature"}

        # 2. Parse and check fields
        try:
            payload = json.loads(certificate_data)
        except (json.JSONDecodeError, TypeError):
            return {"valid": False, "reason": "malformed_cert"}

        if payload.get("device_id") != device_id:
            return {"valid": False, "reason": "device_id_mismatch"}
        if payload.get("company_id") != company_id:
            await self._audit("handshake_failed", device_id=device_id, company_id=company_id,
                              details={"reason": "company_id_mismatch"})
            return {"valid": False, "reason": "company_id_mismatch"}

        # 3. Expiry check
        expires = payload.get("expires_at", "")
        if expires and expires < datetime.now(timezone.utc).isoformat():
            await self._audit("cert_expired", device_id=device_id, company_id=company_id)
            return {"valid": False, "reason": "expired"}

        # 4. Revocation check (DB-side)
        cursor = await self.db.execute(
            """
            SELECT revoked_at FROM _device_certificates
            WHERE device_id = ? AND company_id = ? AND revoked_at IS NULL
            ORDER BY issued_at DESC LIMIT 1
            """,
            (device_id, company_id),
        )
        row = await cursor.fetchone()
        if not row:
            return {"valid": False, "reason": "cert_revoked_or_missing"}

        return {"valid": True, "payload": payload}

    async def get_device_certificate(self, device_id: str, company_id: str) -> dict | None:
        """Get the current (non-revoked) cert for a device."""
        cursor = await self.db.execute(
            """
            SELECT * FROM _device_certificates
            WHERE device_id = ? AND company_id = ? AND revoked_at IS NULL
            ORDER BY issued_at DESC LIMIT 1
            """,
            (device_id, company_id),
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

    # ── Certificate Revocation ───────────────────────────────────

    async def revoke_certificate(
        self,
        *,
        device_id: str,
        company_id: str,
        reason: str = "manual",
        actor_user_id: int | None = None,
    ) -> bool:
        """Revoke all active certificates for a device.

        Returns True if at least one cert was revoked.
        """
        cursor = await self.db.execute(
            """
            UPDATE _device_certificates
            SET revoked_at = datetime('now'), revoke_reason = ?
            WHERE device_id = ? AND company_id = ? AND revoked_at IS NULL
            """,
            (reason, device_id, company_id),
        )
        await self.db.commit()
        revoked = (cursor.rowcount or 0) > 0

        if revoked:
            await self._audit("cert_revoked", device_id=device_id, company_id=company_id,
                              actor=actor_user_id, details={"reason": reason})
        return revoked

    # ── Key Rotation ─────────────────────────────────────────────

    async def rotate_keys(
        self,
        company_id: str,
        *,
        actor_user_id: int | None = None,
    ) -> dict:
        """Rotate company root + shop Ed25519 keys and derive a new sync key.

        All existing device certificates are revoked (they'll fail
        verification against the new key version).  Always upgrades
        to the latest crypto_version on rotation.
        """
        company = await self.get_company(company_id)
        if not company:
            raise ValueError(f"Company {company_id} not found")

        new_root_pub, new_root_secret = _generate_keypair()
        new_shop_pub, new_shop_secret = _generate_keypair()
        new_sync_key = _derive_sync_key(new_root_secret)
        new_version = company["key_version"] + 1

        await self.db.execute(
            """
            UPDATE _company_keys
            SET root_key_public = ?, root_key_encrypted = ?,
                sync_key = ?,
                shop_node_public = ?, shop_node_encrypted = ?,
                key_version = ?, crypto_version = ?,
                rotated_at = datetime('now'),
                updated_at = datetime('now')
            WHERE company_id = ?
            """,
            (new_root_pub, new_root_secret, new_sync_key,
             new_shop_pub, new_shop_secret, new_version, CRYPTO_VERSION, company_id),
        )

        # Revoke all existing certs — devices must re-pair
        await self.db.execute(
            """
            UPDATE _device_certificates
            SET revoked_at = datetime('now'), revoke_reason = 'key_rotation'
            WHERE company_id = ? AND revoked_at IS NULL
            """,
            (company_id,),
        )
        await self.db.commit()

        await self._audit("key_rotated", company_id=company_id, actor=actor_user_id,
                          details={"new_version": new_version})

        return await self.get_company(company_id)  # type: ignore[return-value]

    # ── Shared Channels (Cross-Company Backbone) ─────────────────

    async def create_shared_channel(
        self,
        *,
        channel_name: str,
        owner_company_id: str,
        partner_company_ids: list[str],
        scope: dict | None = None,
        permissions: dict | None = None,
        expires_at: str | None = None,
        created_by: int | None = None,
    ) -> dict:
        """Create a cross-company sharing channel (backbone for future GC sharing)."""
        cursor = await self.db.execute(
            """
            INSERT INTO _shared_channels (
                channel_name, owner_company_id, scope_json, permissions_json,
                expires_at, created_by
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                channel_name, owner_company_id,
                json.dumps(scope or {}),
                json.dumps(permissions or {}),
                expires_at, created_by,
            ),
        )
        channel_id = cursor.lastrowid
        await self.db.commit()

        # Add owner + partners as members
        await self.db.execute(
            """
            INSERT INTO _shared_channel_members (channel_id, company_id, role, accepted_at)
            VALUES (?, ?, 'owner', datetime('now'))
            """,
            (channel_id, owner_company_id),
        )
        for pid in partner_company_ids:
            await self.db.execute(
                "INSERT INTO _shared_channel_members (channel_id, company_id, role) VALUES (?, ?, 'participant')",
                (channel_id, pid),
            )
        await self.db.commit()

        await self._audit("shared_channel_created", company_id=owner_company_id,
                          actor=created_by, details={"channel_id": channel_id, "partners": partner_company_ids})

        return await self._get_channel(channel_id)

    async def list_shared_channels(self, company_id: str | None = None) -> list[dict]:
        if company_id:
            cursor = await self.db.execute(
                """
                SELECT sc.* FROM _shared_channels sc
                JOIN _shared_channel_members scm ON sc.id = scm.channel_id
                WHERE scm.company_id = ? AND sc.is_active = 1
                ORDER BY sc.created_at DESC
                """,
                (company_id,),
            )
        else:
            cursor = await self.db.execute(
                "SELECT * FROM _shared_channels WHERE is_active = 1 ORDER BY created_at DESC",
            )
        rows = await cursor.fetchall()
        channels = []
        for r in rows:
            ch = dict(r)
            ch["scope"] = json.loads(ch.get("scope_json") or "{}")
            ch["permissions"] = json.loads(ch.get("permissions_json") or "{}")
            channels.append(ch)
        return channels

    async def _get_channel(self, channel_id: int) -> dict:
        cursor = await self.db.execute(
            "SELECT * FROM _shared_channels WHERE id = ?", (channel_id,),
        )
        row = await cursor.fetchone()
        ch = dict(row) if row else {}
        if ch:
            ch["scope"] = json.loads(ch.get("scope_json") or "{}")
            ch["permissions"] = json.loads(ch.get("permissions_json") or "{}")
            # Fetch members
            cursor2 = await self.db.execute(
                "SELECT * FROM _shared_channel_members WHERE channel_id = ?", (channel_id,),
            )
            ch["members"] = [dict(m) for m in await cursor2.fetchall()]
        return ch

    # ── Bluetooth Handshake Protocol ─────────────────────────────
    # Mutual certificate exchange for device-to-device mesh sync.
    #
    # Protocol flow (3-step):
    #   1. Initiator sends BT_HELLO: {device_id, company_id, cert_data, signature, nonce}
    #   2. Responder verifies cert, sends BT_HELLO_ACK: {device_id, company_id, cert_data, signature, nonce_response}
    #   3. Initiator verifies responder cert → mutual trust established
    #
    # Both sides must present a valid, non-revoked cert for the same company_id.
    # Cross-company device-to-device sync is NOT allowed.

    async def bt_create_hello(
        self,
        *,
        device_id: str,
        company_id: str,
    ) -> dict | None:
        """Create a BT_HELLO payload for initiating a Bluetooth handshake.

        Returns the hello payload dict, or None if the device has no valid cert.
        """
        cert = await self.get_device_certificate(device_id, company_id)
        if not cert:
            return None

        nonce = secrets.token_hex(16)  # 128-bit nonce to prevent replay
        return {
            "type": "BT_HELLO",
            "device_id": device_id,
            "company_id": company_id,
            "certificate_data": cert["certificate_data"],
            "signature": cert["signature"],
            "nonce": nonce,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    async def bt_verify_hello(
        self,
        *,
        hello: dict,
        responder_device_id: str,
        responder_company_id: str,
    ) -> dict:
        """Verify an incoming BT_HELLO and produce a BT_HELLO_ACK if valid.

        Enforces same-company requirement for device-to-device sync.
        Returns ``{valid, reason?, ack?}`` where ack is the response payload.
        """
        remote_device_id = hello.get("device_id", "")
        remote_company_id = hello.get("company_id", "")

        # Same-company check
        if remote_company_id != responder_company_id:
            await self._audit(
                "bt_handshake_rejected",
                device_id=remote_device_id,
                company_id=remote_company_id,
                details={"reason": "company_mismatch", "responder": responder_device_id},
            )
            return {"valid": False, "reason": "company_mismatch"}

        # Verify the initiator's certificate
        cert_result = await self.verify_certificate(
            device_id=remote_device_id,
            company_id=remote_company_id,
            certificate_data=hello.get("certificate_data", ""),
            signature=hello.get("signature", ""),
        )
        if not cert_result["valid"]:
            await self._audit(
                "bt_handshake_rejected",
                device_id=remote_device_id,
                company_id=remote_company_id,
                details={"reason": cert_result.get("reason"), "responder": responder_device_id},
            )
            return {"valid": False, "reason": cert_result.get("reason", "invalid_cert")}

        # Build our ACK with our own cert
        our_cert = await self.get_device_certificate(responder_device_id, responder_company_id)
        if not our_cert:
            return {"valid": False, "reason": "responder_no_cert"}

        ack_payload = {
            "type": "BT_HELLO_ACK",
            "device_id": responder_device_id,
            "company_id": responder_company_id,
            "certificate_data": our_cert["certificate_data"],
            "signature": our_cert["signature"],
            "nonce_response": hello.get("nonce", ""),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

        await self._audit(
            "bt_handshake_success",
            device_id=remote_device_id,
            company_id=remote_company_id,
            details={
                "responder": responder_device_id,
                "initiator_nonce": hello.get("nonce"),
            },
        )

        return {"valid": True, "ack": ack_payload}

    async def bt_verify_ack(
        self,
        *,
        ack: dict,
        initiator_device_id: str,
        initiator_company_id: str,
        original_nonce: str,
    ) -> dict:
        """Verify a BT_HELLO_ACK from the responder.

        Checks the responder's cert, nonce round-trip, and company match.
        Returns ``{valid, reason?}`` — if valid, mutual trust is established.
        """
        remote_device_id = ack.get("device_id", "")
        remote_company_id = ack.get("company_id", "")

        # Company match
        if remote_company_id != initiator_company_id:
            return {"valid": False, "reason": "company_mismatch"}

        # Nonce round-trip
        if ack.get("nonce_response") != original_nonce:
            return {"valid": False, "reason": "nonce_mismatch"}

        # Verify responder's cert
        cert_result = await self.verify_certificate(
            device_id=remote_device_id,
            company_id=remote_company_id,
            certificate_data=ack.get("certificate_data", ""),
            signature=ack.get("signature", ""),
        )
        if not cert_result["valid"]:
            return {"valid": False, "reason": cert_result.get("reason", "invalid_responder_cert")}

        await self._audit(
            "bt_handshake_complete",
            device_id=initiator_device_id,
            company_id=initiator_company_id,
            details={
                "peer_device": remote_device_id,
                "nonce": original_nonce,
            },
        )

        return {"valid": True, "peer_device_id": remote_device_id}

    # ── Shared Channel Management ────────────────────────────────

    async def deactivate_shared_channel(self, channel_id: int, *, actor_user_id: int | None = None) -> bool:
        """Deactivate a shared channel (soft-delete)."""
        cursor = await self.db.execute(
            "UPDATE _shared_channels SET is_active = 0, updated_at = datetime('now') WHERE id = ? AND is_active = 1",
            (channel_id,),
        )
        await self.db.commit()
        deactivated = (cursor.rowcount or 0) > 0
        if deactivated:
            await self._audit("shared_channel_deactivated", details={"channel_id": channel_id}, actor=actor_user_id)
        return deactivated

    async def accept_channel_invitation(self, channel_id: int, company_id: str) -> bool:
        """Accept a pending channel invitation."""
        cursor = await self.db.execute(
            """
            UPDATE _shared_channel_members
            SET accepted_at = datetime('now')
            WHERE channel_id = ? AND company_id = ? AND accepted_at IS NULL
            """,
            (channel_id, company_id),
        )
        await self.db.commit()
        return (cursor.rowcount or 0) > 0

    # ── Security Audit Log ───────────────────────────────────────

    async def get_audit_log(
        self,
        *,
        event_type: str | None = None,
        device_id: str | None = None,
        company_id: str | None = None,
        limit: int = 100,
    ) -> list[dict]:
        sql = "SELECT * FROM _security_audit_log WHERE 1=1"
        params: list[Any] = []
        if event_type:
            sql += " AND event_type = ?"
            params.append(event_type)
        if device_id:
            sql += " AND device_id = ?"
            params.append(device_id)
        if company_id:
            sql += " AND company_id = ?"
            params.append(company_id)
        sql += " ORDER BY recorded_at DESC, id DESC LIMIT ?"
        params.append(limit)

        cursor = await self.db.execute(sql, tuple(params))
        rows = await cursor.fetchall()
        out: list[dict] = []
        for r in rows:
            d = dict(r)
            d["details"] = json.loads(d.get("details_json") or "{}")
            out.append(d)
        return out

    # ── Internal helpers ─────────────────────────────────────────

    async def _get_cert(self, cert_id: int) -> dict:
        cursor = await self.db.execute(
            "SELECT * FROM _device_certificates WHERE id = ?", (cert_id,),
        )
        row = await cursor.fetchone()
        return dict(row) if row else {}

    async def _audit(
        self,
        event_type: str,
        *,
        device_id: str | None = None,
        company_id: str | None = None,
        actor: int | None = None,
        details: dict | None = None,
        ip_address: str | None = None,
    ) -> None:
        """Append an event to the immutable security audit log."""
        await self.db.execute(
            """
            INSERT INTO _security_audit_log (
                event_type, device_id, company_id,
                actor_user_id, details_json, ip_address
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            (event_type, device_id, company_id, actor,
             json.dumps(details or {}), ip_address),
        )
        await self.db.commit()
