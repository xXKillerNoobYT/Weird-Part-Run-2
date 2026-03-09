"""
Device Security Service — company keys, device certificates, and security audit.

Implements the V1.0 device security protocol:
1. Company initialisation — generate root keypair, derive sync key
2. Device certificate issuance — signed at pairing time
3. Certificate verification — validate cert + company_id match
4. Certificate revocation — block a device immediately
5. Key rotation — rotate company keys + re-issue certs
6. Cross-company isolation — enforce company_id boundaries
7. Security audit logging — immutable event trail
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

logger = logging.getLogger(__name__)

# ── Lightweight crypto helpers ───────────────────────────────────
# V1.0 uses HMAC-SHA256 for signing and HKDF-like derivation.
# When Ed25519 (PyNaCl / cryptography) is added to requirements
# the helpers can be upgraded without changing the service interface.


def _generate_keypair() -> tuple[str, str]:
    """Generate a random 32-byte keypair (public + secret) encoded as base64.

    For V1.0 we use symmetric secrets and HMAC signing.
    Future: swap for Ed25519 via ``cryptography`` library.
    """
    secret = os.urandom(32)
    public = hashlib.sha256(secret).digest()
    return base64.b64encode(public).decode(), base64.b64encode(secret).decode()


def _derive_sync_key(root_secret_b64: str, label: str = "sync-v1") -> str:
    """Derive a symmetric sync key from the root secret via HKDF-like HMAC."""
    root_secret = base64.b64decode(root_secret_b64)
    derived = hmac.new(root_secret, label.encode(), hashlib.sha256).digest()
    return base64.b64encode(derived).decode()


def _sign(secret_b64: str, message: str) -> str:
    """HMAC-SHA256 signature over a message string."""
    secret = base64.b64decode(secret_b64)
    sig = hmac.new(secret, message.encode(), hashlib.sha256).digest()
    return base64.b64encode(sig).decode()


def _verify(secret_b64: str, message: str, signature_b64: str) -> bool:
    """Verify an HMAC-SHA256 signature."""
    expected = _sign(secret_b64, message)
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
        """Generate keys for a new company and store them.

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
                shop_node_public, shop_node_encrypted
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (company_id, company_name, root_pub, root_secret, sync_key, shop_pub, shop_secret),
        )
        await self.db.commit()

        await self._audit("company_initialised", company_id=company_id, details={
            "company_name": company_name,
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
        """Issue a signed certificate for a device.

        The certificate binds (device_id, company_id, device_public_key)
        and is signed by the shop's root key.
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
        }, separators=(",", ":"), sort_keys=True)

        # Sign with root secret
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

        Returns a dict with ``valid``: bool and ``reason`` on failure.
        """
        company = await self.get_company(company_id)
        if not company:
            return {"valid": False, "reason": "unknown_company"}

        # 1. Signature check
        if not _verify(company["root_key_encrypted"], certificate_data, signature):
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
        """Rotate company root + shop keys and derive a new sync key.

        All existing device certificates are marked as needing re-issue
        (they'll fail verification against the new key version).
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
                key_version = ?, rotated_at = datetime('now'),
                updated_at = datetime('now')
            WHERE company_id = ?
            """,
            (new_root_pub, new_root_secret, new_sync_key,
             new_shop_pub, new_shop_secret, new_version, company_id),
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
