"""
Update Protocol Service — shop-centric update pipeline.

Implements the full update lifecycle:
1. Register new versions from GitHub (or manual upload)
2. Run per-platform validation (schema diff, migration test, rollback test)
3. Publish approved versions to the fleet
4. Track per-platform fleet targets with staged rollout
5. Track per-device install status and pending queues
6. Manage pre-update backup snapshots for rollback safety
7. Auto-advance fleet targets when all devices catch up

The shop is the ONLY place that fetches updates from the internet.
Field devices receive updates via LAN sync or Bluetooth mesh relay.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime
from typing import Any

import aiosqlite

logger = logging.getLogger(__name__)


class UpdateProtocolService:
    """Handles the shop-centric update protocol lifecycle."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    # ── Version Registry ─────────────────────────────────────────

    async def register_version(
        self,
        *,
        version: str,
        previous_version: str | None = None,
        release_notes: str | None = None,
        checksum_sha256: str | None = None,
        signature: str | None = None,
        package_url: str | None = None,
        package_size_bytes: int | None = None,
        migration_scripts: list[str] | None = None,
        rollback_scripts: list[str] | None = None,
        min_compatible_version: str | None = None,
        max_compatible_version: str | None = None,
        criticality: str = "normal",
        source: str = "github",
    ) -> dict:
        """Register a new update version.  Idempotent on version string."""
        existing = await self.get_version(version)
        if existing:
            return existing

        cursor = await self.db.execute(
            """
            INSERT INTO _update_registry (
                version, previous_version, release_notes,
                checksum_sha256, signature, package_url, package_size_bytes,
                migration_scripts, rollback_scripts,
                min_compatible_version, max_compatible_version,
                criticality, source
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                version, previous_version, release_notes,
                checksum_sha256, signature, package_url, package_size_bytes,
                json.dumps(migration_scripts or []),
                json.dumps(rollback_scripts or []),
                min_compatible_version, max_compatible_version,
                criticality, source,
            ),
        )
        await self.db.commit()
        return await self.get_version(version)  # type: ignore[return-value]

    async def get_version(self, version: str) -> dict | None:
        cursor = await self.db.execute(
            "SELECT * FROM _update_registry WHERE version = ?", (version,),
        )
        row = await cursor.fetchone()
        if not row:
            return None
        data = dict(row)
        data["migration_scripts"] = json.loads(data.get("migration_scripts") or "[]")
        data["rollback_scripts"] = json.loads(data.get("rollback_scripts") or "[]")
        return data

    async def list_versions(
        self,
        *,
        published_only: bool = False,
        limit: int = 50,
    ) -> list[dict]:
        sql = "SELECT * FROM _update_registry"
        params: list[Any] = []
        if published_only:
            sql += " WHERE published_at IS NOT NULL"
        sql += " ORDER BY created_at DESC LIMIT ?"
        params.append(limit)

        cursor = await self.db.execute(sql, tuple(params))
        rows = await cursor.fetchall()
        out: list[dict] = []
        for r in rows:
            d = dict(r)
            d["migration_scripts"] = json.loads(d.get("migration_scripts") or "[]")
            d["rollback_scripts"] = json.loads(d.get("rollback_scripts") or "[]")
            out.append(d)
        return out

    async def publish_version(self, version: str) -> dict | None:
        """Mark a version as published to the fleet.

        Should only be called after all targeted platforms have passed validation.
        """
        await self.db.execute(
            "UPDATE _update_registry SET published_at = datetime('now') WHERE version = ?",
            (version,),
        )
        await self.db.commit()
        return await self.get_version(version)

    # ── Per-Platform Validation ──────────────────────────────────

    async def create_validation(
        self,
        *,
        version: str,
        platform: str,
        validated_by: int | None = None,
    ) -> dict:
        """Create a validation record for a version+platform combo."""
        cursor = await self.db.execute(
            """
            INSERT INTO _update_validations (version, platform, validated_by)
            VALUES (?, ?, ?)
            ON CONFLICT(version, platform) DO UPDATE SET
                status = 'pending',
                started_at = NULL, completed_at = NULL,
                error_log = NULL
            """,
            (version, platform, validated_by),
        )
        await self.db.commit()
        return await self.get_validation(version, platform)  # type: ignore[return-value]

    async def update_validation(
        self,
        *,
        version: str,
        platform: str,
        status: str,
        schema_diff_ok: bool | None = None,
        migration_test_ok: bool | None = None,
        rollback_test_ok: bool | None = None,
        backward_compat_ok: bool | None = None,
        error_log: str | None = None,
    ) -> dict | None:
        """Update a validation record with test results."""
        set_parts: list[str] = ["status = ?"]
        values: list[Any] = [status]

        if schema_diff_ok is not None:
            set_parts.append("schema_diff_ok = ?")
            values.append(1 if schema_diff_ok else 0)
        if migration_test_ok is not None:
            set_parts.append("migration_test_ok = ?")
            values.append(1 if migration_test_ok else 0)
        if rollback_test_ok is not None:
            set_parts.append("rollback_test_ok = ?")
            values.append(1 if rollback_test_ok else 0)
        if backward_compat_ok is not None:
            set_parts.append("backward_compat_ok = ?")
            values.append(1 if backward_compat_ok else 0)
        if error_log is not None:
            set_parts.append("error_log = ?")
            values.append(error_log)

        if status == "running":
            set_parts.append("started_at = datetime('now')")
        elif status in ("passed", "failed", "blocked"):
            set_parts.append("completed_at = datetime('now')")

        values.extend([version, platform])
        await self.db.execute(
            f"UPDATE _update_validations SET {', '.join(set_parts)} "
            "WHERE version = ? AND platform = ?",
            tuple(values),
        )
        await self.db.commit()
        return await self.get_validation(version, platform)

    async def get_validation(self, version: str, platform: str) -> dict | None:
        cursor = await self.db.execute(
            "SELECT * FROM _update_validations WHERE version = ? AND platform = ?",
            (version, platform),
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

    async def list_validations(
        self,
        version: str | None = None,
        platform: str | None = None,
    ) -> list[dict]:
        sql = "SELECT * FROM _update_validations WHERE 1=1"
        params: list[Any] = []
        if version:
            sql += " AND version = ?"
            params.append(version)
        if platform:
            sql += " AND platform = ?"
            params.append(platform)
        sql += " ORDER BY created_at DESC"

        cursor = await self.db.execute(sql, tuple(params))
        return [dict(r) for r in await cursor.fetchall()]

    # ── Fleet Targets ────────────────────────────────────────────

    async def get_fleet_target(self, platform: str) -> dict | None:
        cursor = await self.db.execute(
            "SELECT * FROM _fleet_targets WHERE platform = ?", (platform,),
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

    async def upsert_fleet_target(
        self,
        *,
        platform: str,
        current_target: str | None = None,
        latest_validated: str | None = None,
        auto_advance: bool | None = None,
        updated_by: int | None = None,
    ) -> dict:
        """Create or update the fleet target for a platform."""
        existing = await self.get_fleet_target(platform)
        if not existing:
            await self.db.execute(
                """
                INSERT INTO _fleet_targets (platform, current_target, latest_validated, updated_by)
                VALUES (?, ?, ?, ?)
                """,
                (platform, current_target or "0.0.0", latest_validated, updated_by),
            )
        else:
            set_parts: list[str] = ["updated_at = datetime('now')"]
            values: list[Any] = []
            if current_target is not None:
                set_parts.append("current_target = ?")
                values.append(current_target)
            if latest_validated is not None:
                set_parts.append("latest_validated = ?")
                values.append(latest_validated)
            if auto_advance is not None:
                set_parts.append("auto_advance = ?")
                values.append(1 if auto_advance else 0)
            if updated_by is not None:
                set_parts.append("updated_by = ?")
                values.append(updated_by)
            values.append(platform)
            await self.db.execute(
                f"UPDATE _fleet_targets SET {', '.join(set_parts)} WHERE platform = ?",
                tuple(values),
            )
        await self.db.commit()
        return await self.get_fleet_target(platform)  # type: ignore[return-value]

    async def list_fleet_targets(self) -> list[dict]:
        cursor = await self.db.execute(
            "SELECT * FROM _fleet_targets ORDER BY platform",
        )
        return [dict(r) for r in await cursor.fetchall()]

    async def refresh_fleet_counts(self, platform: str) -> dict:
        """Recalculate device counts for a fleet target.

        Call after a device reports in or after advancing the target.
        """
        target = await self.get_fleet_target(platform)
        if not target:
            return {}

        cursor = await self.db.execute(
            "SELECT COUNT(*) as total FROM _device_update_status WHERE platform = ?",
            (platform,),
        )
        total = (await cursor.fetchone())["total"]

        cursor = await self.db.execute(
            "SELECT COUNT(*) as at_target FROM _device_update_status "
            "WHERE platform = ? AND current_version = ?",
            (platform, target["current_target"]),
        )
        at_target = (await cursor.fetchone())["at_target"]

        behind = total - at_target

        await self.db.execute(
            """
            UPDATE _fleet_targets
            SET devices_total = ?, devices_at_target = ?, devices_behind = ?,
                updated_at = datetime('now')
            WHERE platform = ?
            """,
            (total, at_target, behind, platform),
        )
        await self.db.commit()

        # Auto-advance: if all devices are caught up and there's a newer validated version
        if target["auto_advance"] and behind == 0 and target.get("latest_validated"):
            if target["latest_validated"] != target["current_target"]:
                await self._try_advance(platform, target)

        return await self.get_fleet_target(platform)  # type: ignore[return-value]

    async def _try_advance(self, platform: str, target: dict) -> None:
        """Advance fleet target to the next version in the chain.

        Only advances one step at a time (strict version chain).
        """
        # Find the next version after current target
        cursor = await self.db.execute(
            """
            SELECT ur.version FROM _update_registry ur
            JOIN _update_validations uv ON ur.version = uv.version AND uv.platform = ?
            WHERE ur.previous_version = ? AND ur.published_at IS NOT NULL AND uv.status = 'passed'
            LIMIT 1
            """,
            (platform, target["current_target"]),
        )
        row = await cursor.fetchone()
        if row:
            next_version = row["version"]
            logger.info(
                "Auto-advancing fleet target for %s: %s → %s",
                platform, target["current_target"], next_version,
            )
            await self.db.execute(
                "UPDATE _fleet_targets SET current_target = ?, updated_at = datetime('now') WHERE platform = ?",
                (next_version, platform),
            )
            await self.db.commit()

    # ── Device Update Status ─────────────────────────────────────

    async def report_device_version(
        self,
        *,
        device_id: str,
        platform: str,
        current_version: str,
        install_status: str = "success",
        install_error: str | None = None,
    ) -> dict:
        """Device reports its current installed version.

        Called after a device installs an update or on first sync.
        """
        # Get the fleet target for this platform
        target = await self.get_fleet_target(platform)
        target_version = target["current_target"] if target else current_version

        cursor = await self.db.execute(
            """
            INSERT INTO _device_update_status (
                device_id, platform, current_version, target_version,
                last_install_version, last_install_at, last_install_status,
                install_error, reported_at
            ) VALUES (?, ?, ?, ?, ?, datetime('now'), ?, ?, datetime('now'))
            ON CONFLICT(device_id) DO UPDATE SET
                current_version = excluded.current_version,
                target_version = excluded.target_version,
                last_install_version = excluded.current_version,
                last_install_at = datetime('now'),
                last_install_status = excluded.last_install_status,
                install_error = excluded.install_error,
                reported_at = datetime('now')
            """,
            (device_id, platform, current_version, target_version,
             current_version, install_status, install_error),
        )
        await self.db.commit()

        # Refresh fleet counts so auto-advance can trigger
        if target:
            await self.refresh_fleet_counts(platform)

        return await self.get_device_update_status(device_id)  # type: ignore[return-value]

    async def get_device_update_status(self, device_id: str) -> dict | None:
        cursor = await self.db.execute(
            "SELECT * FROM _device_update_status WHERE device_id = ?", (device_id,),
        )
        row = await cursor.fetchone()
        if not row:
            return None
        data = dict(row)
        data["pending_versions"] = json.loads(data.get("pending_versions") or "[]")
        return data

    async def list_device_update_statuses(
        self,
        *,
        platform: str | None = None,
        behind_only: bool = False,
        limit: int = 100,
    ) -> list[dict]:
        sql = "SELECT * FROM _device_update_status WHERE 1=1"
        params: list[Any] = []
        if platform:
            sql += " AND platform = ?"
            params.append(platform)
        if behind_only:
            sql += " AND current_version != target_version"
        sql += " ORDER BY reported_at DESC LIMIT ?"
        params.append(limit)

        cursor = await self.db.execute(sql, tuple(params))
        rows = await cursor.fetchall()
        out: list[dict] = []
        for r in rows:
            d = dict(r)
            d["pending_versions"] = json.loads(d.get("pending_versions") or "[]")
            out.append(d)
        return out

    async def get_pending_updates(self, device_id: str, platform: str) -> list[dict]:
        """Get the ordered list of updates a device should install next.

        Returns updates from the device's current version up to (and including)
        the fleet target, following the strict ``previous_version`` chain.
        """
        status = await self.get_device_update_status(device_id)
        if not status:
            return []

        target = await self.get_fleet_target(platform)
        if not target:
            return []

        current = status["current_version"]
        target_ver = target["current_target"]

        if current == target_ver:
            return []

        # Walk the version chain from current to target
        chain: list[dict] = []
        walk = current
        safety = 0
        while walk != target_ver and safety < 50:
            safety += 1
            cursor = await self.db.execute(
                """
                SELECT ur.* FROM _update_registry ur
                JOIN _update_validations uv ON ur.version = uv.version AND uv.platform = ?
                WHERE ur.previous_version = ? AND ur.published_at IS NOT NULL AND uv.status = 'passed'
                LIMIT 1
                """,
                (platform, walk),
            )
            row = await cursor.fetchone()
            if not row:
                break
            ver = dict(row)
            ver["migration_scripts"] = json.loads(ver.get("migration_scripts") or "[]")
            ver["rollback_scripts"] = json.loads(ver.get("rollback_scripts") or "[]")
            chain.append(ver)
            walk = ver["version"]

        return chain

    # ── Backup Snapshots ─────────────────────────────────────────

    async def create_backup_snapshot(
        self,
        *,
        version_before: str,
        version_target: str,
        backup_path: str,
        backup_size_bytes: int | None = None,
        checksum_sha256: str | None = None,
        includes_db: bool = True,
        includes_config: bool = True,
        includes_binary: bool = True,
        created_by: int | None = None,
    ) -> dict:
        cursor = await self.db.execute(
            """
            INSERT INTO _update_backup_snapshots (
                version_before, version_target, backup_path,
                backup_size_bytes, checksum_sha256,
                includes_db, includes_config, includes_binary,
                created_by
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                version_before, version_target, backup_path,
                backup_size_bytes, checksum_sha256,
                1 if includes_db else 0,
                1 if includes_config else 0,
                1 if includes_binary else 0,
                created_by,
            ),
        )
        snap_id = cursor.lastrowid
        await self.db.commit()

        cursor = await self.db.execute(
            "SELECT * FROM _update_backup_snapshots WHERE id = ?", (snap_id,),
        )
        return dict(await cursor.fetchone())

    async def mark_backup_restored(self, snapshot_id: int) -> dict | None:
        """Mark a backup as restored (used during rollback)."""
        await self.db.execute(
            """
            UPDATE _update_backup_snapshots
            SET status = 'restored', restored_at = datetime('now')
            WHERE id = ?
            """,
            (snapshot_id,),
        )
        await self.db.commit()
        cursor = await self.db.execute(
            "SELECT * FROM _update_backup_snapshots WHERE id = ?", (snapshot_id,),
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

    async def list_backup_snapshots(
        self,
        *,
        version_before: str | None = None,
        limit: int = 50,
    ) -> list[dict]:
        sql = "SELECT * FROM _update_backup_snapshots WHERE 1=1"
        params: list[Any] = []
        if version_before:
            sql += " AND version_before = ?"
            params.append(version_before)
        sql += " ORDER BY created_at DESC LIMIT ?"
        params.append(limit)

        cursor = await self.db.execute(sql, tuple(params))
        return [dict(r) for r in await cursor.fetchall()]
