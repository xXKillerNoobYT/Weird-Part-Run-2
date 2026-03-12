"""Bootstrap service for App-Store shell pairing and program handoff."""

from __future__ import annotations

import hashlib
import json
import logging
import secrets
from typing import Any

import aiosqlite

from app.services.device_security_service import DeviceSecurityService, _verify
from app.services.sync_service import SyncService

logger = logging.getLogger(__name__)


class BootstrapService:
    """Handles bootstrap pairing, artifact lookup, and install telemetry."""

    # Default company ID for single-shop V1.0 deployments.
    # Multi-company setups can override via settings.
    DEFAULT_COMPANY_ID = "default"

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.sync_service = SyncService(db)
        self.security_service = DeviceSecurityService(db)

    async def create_pairing_code(
        self,
        *,
        created_by: int | None,
        ttl_minutes: int = 15,
        notes: str | None = None,
    ) -> dict:
        code = secrets.token_hex(4).upper()  # 8-char hex code
        await self.db.execute(
            """
            INSERT INTO _bootstrap_pairing_codes (code, created_by, expires_at, notes)
            VALUES (?, ?, datetime('now', '+' || ? || ' minutes'), ?)
            """,
            (code, created_by, ttl_minutes, notes),
        )
        await self.db.commit()
        cursor = await self.db.execute(
            "SELECT * FROM _bootstrap_pairing_codes WHERE code = ?",
            (code,),
        )
        row = await cursor.fetchone()
        return dict(row) if row else {}

    async def validate_pairing_code(self, code: str) -> dict | None:
        cursor = await self.db.execute(
            """
            SELECT * FROM _bootstrap_pairing_codes
            WHERE code = ? AND used_at IS NULL AND expires_at > datetime('now')
            """,
            (code,),
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

    async def list_pairing_codes(self, limit: int = 100) -> list[dict]:
        """List recent pairing codes for admin visibility and troubleshooting."""
        cursor = await self.db.execute(
            """
            SELECT * FROM _bootstrap_pairing_codes
            ORDER BY created_at DESC, code DESC
            LIMIT ?
            """,
            (limit,),
        )
        rows = await cursor.fetchall()
        return [dict(r) for r in rows]

    async def consume_pairing_code(
        self,
        *,
        code: str,
        device_id: str,
        device_name: str | None,
        platform: str,
        bootstrap_version: str | None,
        public_key: str | None,
    ) -> None:
        await self.db.execute(
            """
            UPDATE _bootstrap_pairing_codes
            SET used_at = datetime('now'),
                device_id = ?,
                device_name = ?,
                platform = ?,
                bootstrap_version = ?,
                public_key = ?
            WHERE code = ?
            """,
            (device_id, device_name, platform, bootstrap_version, public_key, code),
        )
        await self.db.commit()

    async def upsert_artifact(
        self,
        *,
        platform: str,
        version: str,
        manifest: dict,
        download_url: str,
        checksum_sha256: str,
        signature: str | None,
        min_bootstrap_version: str,
        created_by: int | None,
    ) -> dict:
        # keep one active artifact per platform
        await self.db.execute(
            "UPDATE _bootstrap_artifacts SET is_active = 0 WHERE platform = ?",
            (platform,),
        )
        cursor = await self.db.execute(
            """
            INSERT INTO _bootstrap_artifacts (
                platform, version, manifest_json, download_url, checksum_sha256,
                signature, min_bootstrap_version, is_active, created_by
            ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)
            """,
            (
                platform,
                version,
                json.dumps(manifest),
                download_url,
                checksum_sha256,
                signature,
                min_bootstrap_version,
                created_by,
            ),
        )
        artifact_id = cursor.lastrowid
        await self.db.commit()
        return await self.get_artifact_by_id(artifact_id)

    async def get_artifact_by_id(self, artifact_id: int) -> dict:
        cursor = await self.db.execute(
            "SELECT * FROM _bootstrap_artifacts WHERE id = ?",
            (artifact_id,),
        )
        row = await cursor.fetchone()
        if not row:
            return {}
        data = dict(row)
        data["manifest"] = json.loads(data.get("manifest_json") or "{}")
        return data

    async def get_active_artifact(self, platform: str) -> dict | None:
        cursor = await self.db.execute(
            """
            SELECT * FROM _bootstrap_artifacts
            WHERE platform = ? AND is_active = 1
            ORDER BY created_at DESC, id DESC
            LIMIT 1
            """,
            (platform,),
        )
        row = await cursor.fetchone()
        if not row:
            return None
        data = dict(row)
        data["manifest"] = json.loads(data.get("manifest_json") or "{}")
        return data

    async def list_artifacts(self, platform: str | None = None, limit: int = 50) -> list[dict]:
        sql = "SELECT * FROM _bootstrap_artifacts"
        params: list[Any] = []
        if platform:
            sql += " WHERE platform = ?"
            params.append(platform)
        sql += " ORDER BY created_at DESC, id DESC LIMIT ?"
        params.append(limit)

        cursor = await self.db.execute(sql, tuple(params))
        rows = await cursor.fetchall()
        out: list[dict] = []
        for r in rows:
            d = dict(r)
            d["manifest"] = json.loads(d.get("manifest_json") or "{}")
            out.append(d)
        return out

    async def log_install_event(
        self,
        *,
        device_id: str,
        platform: str,
        artifact_id: int | None,
        status: str,
        error_message: str | None = None,
        metadata: dict | None = None,
        progress_pct: float = 0,
        bytes_downloaded: int = 0,
        bytes_total: int = 0,
        checksum_computed: str | None = None,
        checksum_verified: bool = False,
        signature_verified: bool | None = None,
    ) -> dict:
        cursor = await self.db.execute(
            """
            INSERT INTO _bootstrap_install_events (
                device_id, platform, artifact_id, status, error_message,
                metadata_json, progress_pct, bytes_downloaded, bytes_total,
                checksum_computed, checksum_verified, signature_verified
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                device_id,
                platform,
                artifact_id,
                status,
                error_message,
                json.dumps(metadata or {}),
                progress_pct,
                bytes_downloaded,
                bytes_total,
                checksum_computed,
                1 if checksum_verified else 0,
                1 if signature_verified is True else (0 if signature_verified is False else None),
            ),
        )
        event_id = cursor.lastrowid
        await self.db.commit()
        cursor = await self.db.execute(
            "SELECT * FROM _bootstrap_install_events WHERE id = ?",
            (event_id,),
        )
        row = await cursor.fetchone()
        out = dict(row) if row else {}
        if out:
            out["metadata"] = json.loads(out.get("metadata_json") or "{}")
        return out

    async def list_install_events(
        self,
        *,
        device_id: str | None = None,
        limit: int = 100,
    ) -> list[dict]:
        sql = "SELECT * FROM _bootstrap_install_events"
        params: list[Any] = []
        if device_id:
            sql += " WHERE device_id = ?"
            params.append(device_id)
        sql += " ORDER BY created_at DESC, id DESC LIMIT ?"
        params.append(limit)

        cursor = await self.db.execute(sql, tuple(params))
        rows = await cursor.fetchall()
        out: list[dict] = []
        for r in rows:
            d = dict(r)
            d["metadata"] = json.loads(d.get("metadata_json") or "{}")
            out.append(d)
        return out

    async def bootstrap_handshake(
        self,
        *,
        pairing_code: str,
        device_id: str,
        device_name: str,
        platform: str,
        bootstrap_version: str,
        public_key: str | None,
    ) -> dict:
        code = await self.validate_pairing_code(pairing_code)
        if not code:
            raise ValueError("Invalid, expired, or used pairing code")

        await self.consume_pairing_code(
            code=pairing_code,
            device_id=device_id,
            device_name=device_name,
            platform=platform,
            bootstrap_version=bootstrap_version,
            public_key=public_key,
        )

        await self.sync_service.register_device(
            device_id=device_id,
            device_name=device_name,
            platform=platform,
            user_id=code.get("created_by"),
        )

        # ── Auto-issue device certificate ────────────────────────
        # If the device provided a public key, issue a signed certificate
        # binding (device_id, company_id, public_key).  The certificate is
        # included in the handshake response so the device can use it for
        # authenticated sync from the very first push.
        certificate = None
        if public_key:
            try:
                # Ensure default company exists (idempotent)
                await self.security_service.initialise_company(
                    company_id=self.DEFAULT_COMPANY_ID,
                    company_name="My Company",
                )
                certificate = await self.security_service.issue_certificate(
                    device_id=device_id,
                    company_id=self.DEFAULT_COMPANY_ID,
                    device_public_key=public_key,
                    issued_by=code.get("created_by"),
                )
                logger.info(
                    "Auto-issued certificate for device %s (company=%s)",
                    device_id, self.DEFAULT_COMPANY_ID,
                )
            except Exception:
                # Certificate issuance is best-effort during bootstrap.
                # Device can still sync unauthenticated until cert is
                # manually issued via the admin UI.
                logger.warning(
                    "Failed to auto-issue certificate for device %s",
                    device_id, exc_info=True,
                )

        artifact = await self.get_active_artifact(platform)
        return {
            "device_id": device_id,
            "platform": platform,
            "bootstrap_version": bootstrap_version,
            "artifact": artifact,
            "certificate": certificate,
            "sync_endpoints": {
                "initial": "/api/sync/initial",
                "push": "/api/sync/push",
                "pull": "/api/sync/pull",
                "ack": "/api/sync/ack",
                "hard_sync_request": "/api/sync/hard-sync/request",
            },
        }

    # ── Artifact Verification ────────────────────────────────────

    async def verify_artifact(
        self,
        *,
        artifact_id: int,
        client_checksum_sha256: str,
    ) -> dict:
        """Verify a downloaded artifact against the registered checksum and optional signature.

        The device computes SHA-256 of the downloaded file and sends it here.
        We compare against the stored checksum_sha256 on the artifact record.
        If the artifact has a signature and it was signed by the shop's key,
        we verify that too.

        Returns:
            {
                "valid": bool,
                "checksum_match": bool,
                "signature_valid": bool | None,  # None when no signature registered
                "artifact_id": int,
                "version": str,
                "detail": str,
            }
        """
        artifact = await self.get_artifact_by_id(artifact_id)
        if not artifact:
            return {
                "valid": False,
                "checksum_match": False,
                "signature_valid": None,
                "artifact_id": artifact_id,
                "version": None,
                "detail": "Artifact not found",
            }

        # Compare checksums (case-insensitive hex comparison)
        stored_checksum = (artifact.get("checksum_sha256") or "").strip().lower()
        client_checksum = client_checksum_sha256.strip().lower()
        checksum_match = stored_checksum == client_checksum and len(stored_checksum) > 0

        # Signature verification (optional — only if artifact has a signature)
        signature_valid: bool | None = None
        if artifact.get("signature"):
            try:
                # Try to get the shop's public key for signature verification
                company_id = self.DEFAULT_COMPANY_ID
                cursor = await self.db.execute(
                    """
                    SELECT shop_node_public
                    FROM _company_keys
                    WHERE company_id = ?
                    """,
                    (company_id,),
                )
                row = await cursor.fetchone()
                if row and row["shop_node_public"]:
                    # The signature covers: "{platform}:{version}:{checksum_sha256}"
                    message = f"{artifact['platform']}:{artifact['version']}:{stored_checksum}"
                    signature_valid = _verify(
                        row["shop_node_public"],
                        message,
                        artifact["signature"],
                    )
                else:
                    # No shop key available — can't verify signature
                    signature_valid = None
            except Exception:
                logger.warning(
                    "Signature verification failed for artifact %d",
                    artifact_id,
                    exc_info=True,
                )
                signature_valid = False

        overall_valid = checksum_match and (signature_valid is not False)

        return {
            "valid": overall_valid,
            "checksum_match": checksum_match,
            "signature_valid": signature_valid,
            "artifact_id": artifact_id,
            "version": artifact.get("version"),
            "detail": (
                "Artifact verified successfully"
                if overall_valid
                else "Checksum mismatch" if not checksum_match
                else "Signature verification failed"
            ),
        }

    async def sign_artifact(
        self,
        *,
        artifact_id: int,
    ) -> dict:
        """Sign an artifact's checksum with the shop's Ed25519 key.

        Generates a signature over "{platform}:{version}:{checksum}"
        using the shop's node private key.  This allows devices to verify
        the artifact came from this shop.

        Returns the updated artifact with signature populated.
        """
        artifact = await self.get_artifact_by_id(artifact_id)
        if not artifact:
            raise ValueError(f"Artifact {artifact_id} not found")

        company_id = self.DEFAULT_COMPANY_ID
        cursor = await self.db.execute(
            """
            SELECT shop_node_encrypted
            FROM _company_keys
            WHERE company_id = ?
            """,
            (company_id,),
        )
        row = await cursor.fetchone()
        if not row or not row["shop_node_encrypted"]:
            raise ValueError("Shop key not initialised — run company security init first")

        from app.services.device_security_service import _sign

        checksum = (artifact.get("checksum_sha256") or "").strip().lower()
        message = f"{artifact['platform']}:{artifact['version']}:{checksum}"
        signature = _sign(row["shop_node_encrypted"], message)

        await self.db.execute(
            "UPDATE _bootstrap_artifacts SET signature = ? WHERE id = ?",
            (signature, artifact_id),
        )
        await self.db.commit()

        return await self.get_artifact_by_id(artifact_id)
