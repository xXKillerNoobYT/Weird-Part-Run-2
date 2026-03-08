"""Bootstrap service for App-Store shell pairing and program handoff."""

from __future__ import annotations

import json
import logging
import secrets
from typing import Any

import aiosqlite

from app.services.device_security_service import DeviceSecurityService
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
    ) -> dict:
        cursor = await self.db.execute(
            """
            INSERT INTO _bootstrap_install_events (
                device_id, platform, artifact_id, status, error_message, metadata_json
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                device_id,
                platform,
                artifact_id,
                status,
                error_message,
                json.dumps(metadata or {}),
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
