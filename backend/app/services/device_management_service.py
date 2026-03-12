"""
Device Management Service — admin operations for paired devices.

Handles:
- Device detail retrieval with health + error summary
- Primary user reassignment
- Override flags (force_logout, force_wipe, force_sync, disable/enable)
- Device error log CRUD (upload, view, resolve)
- Device health telemetry (upload, history, latest)
- BT encounter logging and queries
- Media delivery tracking
- Shop cluster management
- Log retention enforcement (3 months on device, 1 year on shop)
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, timedelta
from typing import Any

import aiosqlite

logger = logging.getLogger(__name__)


class DeviceManagementService:
    """Admin-level device management operations (shop-side)."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    # ── Device List & Detail ────────────────────────────────────────

    async def list_devices(self, *, include_disabled: bool = True) -> list[dict]:
        """List all registered devices with latest health snapshot."""
        where = "" if include_disabled else "WHERE dr.is_disabled = 0"
        cursor = await self.db.execute(f"""
            SELECT dr.*,
                   dsp.storage_policy,
                   dsp.media_policy,
                   dsp.media_retention_days,
                   u.display_name AS primary_user_name,
                   (SELECT COUNT(*) FROM _device_error_log del
                     WHERE del.device_id = dr.device_id AND del.resolved_at IS NULL) AS unresolved_errors,
                   dhs.battery_level,
                   dhs.battery_charging,
                   dhs.storage_used_mb,
                   dhs.storage_total_mb,
                   dhs.app_version AS health_app_version,
                   dhs.os_version AS health_os_version,
                   dhs.pending_sync_count,
                   dhs.pending_media_count,
                   dhs.snapshot_at AS last_health_at
              FROM _device_registry dr
              LEFT JOIN _device_sync_profiles dsp ON dsp.device_id = dr.device_id
              LEFT JOIN users u ON u.id = dr.primary_user_id
              LEFT JOIN (
                  SELECT device_id,
                         battery_level, battery_charging,
                         storage_used_mb, storage_total_mb,
                         app_version, os_version,
                         pending_sync_count, pending_media_count,
                         snapshot_at,
                         ROW_NUMBER() OVER (PARTITION BY device_id ORDER BY snapshot_at DESC) AS rn
                    FROM _device_health_snapshots
              ) dhs ON dhs.device_id = dr.device_id AND dhs.rn = 1
              {where}
             ORDER BY dr.last_sync_at DESC NULLS LAST
        """)
        rows = await cursor.fetchall()
        return [dict(r) for r in rows]

    async def get_device(self, device_id: str) -> dict | None:
        """Get full device detail including health, profiles, cert info."""
        cursor = await self.db.execute("""
            SELECT dr.*,
                   dsp.primary_user_id AS profile_primary_user_id,
                   dsp.storage_policy,
                   dsp.media_policy,
                   dsp.media_retention_days,
                   dsp.force_carry_undelivered_media,
                   dsp.allow_borrowed_user_overrides,
                   dsp.active_only_sync,
                   u.display_name AS primary_user_name
              FROM _device_registry dr
              LEFT JOIN _device_sync_profiles dsp ON dsp.device_id = dr.device_id
              LEFT JOIN users u ON u.id = dr.primary_user_id
             WHERE dr.device_id = ?
        """, (device_id,))
        row = await cursor.fetchone()
        if not row:
            return None

        device = dict(row)

        # Latest health snapshot
        hcur = await self.db.execute("""
            SELECT * FROM _device_health_snapshots
             WHERE device_id = ? ORDER BY snapshot_at DESC LIMIT 1
        """, (device_id,))
        health = await hcur.fetchone()
        device["latest_health"] = dict(health) if health else None

        # Certificate info
        ccur = await self.db.execute("""
            SELECT id, device_id, company_id, issued_at, expires_at, revoked_at,
                   crypto_version
              FROM _device_certificates
             WHERE device_id = ?
             ORDER BY issued_at DESC LIMIT 1
        """, (device_id,))
        cert = await ccur.fetchone()
        device["certificate"] = dict(cert) if cert else None

        # Error count
        ecur = await self.db.execute("""
            SELECT COUNT(*) AS cnt FROM _device_error_log
             WHERE device_id = ? AND resolved_at IS NULL
        """, (device_id,))
        er = await ecur.fetchone()
        device["unresolved_error_count"] = er["cnt"] if er else 0

        return device

    async def rename_device(self, device_id: str, name: str) -> bool:
        """Rename a device."""
        cursor = await self.db.execute(
            "UPDATE _device_registry SET device_name = ? WHERE device_id = ?",
            (name, device_id),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    # ── Primary User Management ─────────────────────────────────────

    async def set_primary_user(self, device_id: str, user_id: int, *, actor_id: int) -> bool:
        """Reassign the primary user for a device."""
        # Update both registry and sync profile
        await self.db.execute(
            "UPDATE _device_registry SET primary_user_id = ? WHERE device_id = ?",
            (user_id, device_id),
        )
        await self.db.execute("""
            INSERT INTO _device_sync_profiles (device_id, primary_user_id, updated_by)
            VALUES (?, ?, ?)
            ON CONFLICT(device_id)
            DO UPDATE SET primary_user_id = excluded.primary_user_id,
                          updated_by = excluded.updated_by,
                          updated_at = datetime('now')
        """, (device_id, user_id, actor_id))
        await self.db.commit()
        logger.info("Primary user for device %s set to user %d by user %d",
                     device_id[:8], user_id, actor_id)
        return True

    # ── Override Actions ────────────────────────────────────────────

    async def set_override(
        self, device_id: str, action: str, *, actor_id: int, reason: str | None = None,
    ) -> bool:
        """Set an override flag on a device: force_logout, force_wipe, force_sync."""
        valid_actions = ("force_logout", "force_wipe", "force_sync")
        if action not in valid_actions:
            raise ValueError(f"Invalid override action: {action}. Must be one of {valid_actions}")

        await self.db.execute("""
            UPDATE _device_registry
               SET override_action = ?,
                   override_set_at = datetime('now'),
                   override_set_by = ?
             WHERE device_id = ?
        """, (action, actor_id, device_id))
        await self.db.commit()

        # Audit log
        await self._audit("override_set", device_id=device_id, actor=actor_id,
                          details={"action": action, "reason": reason})
        return True

    async def clear_override(self, device_id: str, *, actor_id: int) -> bool:
        """Clear any pending override on a device."""
        await self.db.execute("""
            UPDATE _device_registry
               SET override_action = NULL,
                   override_set_at = NULL,
                   override_set_by = NULL
             WHERE device_id = ?
        """, (device_id,))
        await self.db.commit()
        await self._audit("override_cleared", device_id=device_id, actor=actor_id)
        return True

    async def check_override(self, device_id: str) -> dict | None:
        """Check if device has a pending override. Returns override info or None."""
        cursor = await self.db.execute("""
            SELECT override_action, override_set_at, override_set_by, is_disabled, disabled_reason
              FROM _device_registry WHERE device_id = ?
        """, (device_id,))
        row = await cursor.fetchone()
        if not row:
            return None
        d = dict(row)
        if d.get("is_disabled"):
            return {"action": "disabled", "reason": d.get("disabled_reason"),
                    "set_at": None}
        if d.get("override_action"):
            return {"action": d["override_action"], "set_at": d.get("override_set_at")}
        return None

    async def consume_override(self, device_id: str) -> str | None:
        """Read and clear the override (device acknowledges it). Returns the action or None."""
        override = await self.check_override(device_id)
        if not override or override["action"] == "disabled":
            return override["action"] if override else None

        # Clear after consuming
        await self.db.execute("""
            UPDATE _device_registry
               SET override_action = NULL,
                   override_set_at = NULL,
                   override_set_by = NULL
             WHERE device_id = ?
        """, (device_id,))
        await self.db.commit()
        return override["action"]

    async def disable_device(self, device_id: str, reason: str, *, actor_id: int) -> bool:
        """Disable a device (lost/stolen). Blocks sync and forces logout."""
        await self.db.execute("""
            UPDATE _device_registry
               SET is_disabled = 1, disabled_reason = ?,
                   override_action = 'force_logout',
                   override_set_at = datetime('now'),
                   override_set_by = ?
             WHERE device_id = ?
        """, (reason, actor_id, device_id))
        await self.db.commit()
        await self._audit("device_disabled", device_id=device_id, actor=actor_id,
                          details={"reason": reason})
        return True

    async def enable_device(self, device_id: str, *, actor_id: int) -> bool:
        """Re-enable a previously disabled device."""
        await self.db.execute("""
            UPDATE _device_registry
               SET is_disabled = 0, disabled_reason = NULL,
                   override_action = NULL
             WHERE device_id = ?
        """, (device_id,))
        await self.db.commit()
        await self._audit("device_enabled", device_id=device_id, actor=actor_id)
        return True

    async def force_wipe(self, device_id: str, *, actor_id: int) -> bool:
        """Flag a device for a full wipe on next check-in."""
        return await self.set_override(device_id, "force_wipe", actor_id=actor_id,
                                       reason="Admin-initiated wipe")

    async def force_sync(self, device_id: str, *, actor_id: int) -> bool:
        """Flag a device to sync immediately on next check-in."""
        await self.db.execute("""
            UPDATE _device_registry SET force_sync_flag = 1 WHERE device_id = ?
        """, (device_id,))
        await self.db.commit()
        await self._audit("force_sync_flagged", device_id=device_id, actor=actor_id)
        return True

    async def push_config(self, device_id: str, *, actor_id: int) -> bool:
        """Increment config_version to force device config refresh."""
        await self.db.execute("""
            UPDATE _device_registry
               SET config_version = COALESCE(config_version, 0) + 1
             WHERE device_id = ?
        """, (device_id,))
        await self.db.commit()
        await self._audit("config_pushed", device_id=device_id, actor=actor_id)
        return True

    # ── Device Error Logs ───────────────────────────────────────────

    async def upload_errors(self, device_id: str, errors: list[dict]) -> int:
        """Bulk-upload error logs from a device. Returns count inserted."""
        inserted = 0
        for err in errors:
            await self.db.execute("""
                INSERT INTO _device_error_log
                    (device_id, severity, error_type, message, stack_trace,
                     context_json, environment_json, occurred_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                device_id,
                err.get("severity", "error"),
                err.get("error_type", "unknown"),
                err.get("message", ""),
                err.get("stack_trace"),
                err.get("context_json"),
                err.get("environment_json"),
                err.get("occurred_at", datetime.utcnow().isoformat()),
            ))
            inserted += 1
        await self.db.commit()
        return inserted

    async def list_errors(
        self, *, device_id: str | None = None, severity: str | None = None,
        unresolved_only: bool = False, limit: int = 100, offset: int = 0,
    ) -> list[dict]:
        """List device error logs with filtering."""
        conditions: list[str] = []
        params: list[Any] = []

        if device_id:
            conditions.append("del.device_id = ?")
            params.append(device_id)
        if severity:
            conditions.append("del.severity = ?")
            params.append(severity)
        if unresolved_only:
            conditions.append("del.resolved_at IS NULL")

        where = f"WHERE {' AND '.join(conditions)}" if conditions else ""
        cursor = await self.db.execute(f"""
            SELECT del.*, dr.device_name
              FROM _device_error_log del
              LEFT JOIN _device_registry dr ON dr.device_id = del.device_id
             {where}
             ORDER BY del.occurred_at DESC
             LIMIT ? OFFSET ?
        """, (*params, limit, offset))
        rows = await cursor.fetchall()
        return [dict(r) for r in rows]

    async def resolve_error(self, error_id: int, *, actor_id: int, note: str | None = None) -> bool:
        """Mark an error as resolved."""
        cursor = await self.db.execute("""
            UPDATE _device_error_log
               SET resolved_at = datetime('now'),
                   resolved_by = ?,
                   resolution_note = ?
             WHERE id = ? AND resolved_at IS NULL
        """, (actor_id, note, error_id))
        await self.db.commit()
        return cursor.rowcount > 0

    async def resolve_all_for_device(self, device_id: str, *, actor_id: int) -> int:
        """Resolve all unresolved errors for a device."""
        cursor = await self.db.execute("""
            UPDATE _device_error_log
               SET resolved_at = datetime('now'),
                   resolved_by = ?,
                   resolution_note = 'Bulk resolved'
             WHERE device_id = ? AND resolved_at IS NULL
        """, (actor_id, device_id))
        await self.db.commit()
        return cursor.rowcount

    # ── Device Health Telemetry ─────────────────────────────────────

    async def upload_health(self, device_id: str, snapshot: dict) -> int:
        """Upload a health snapshot from a device."""
        cursor = await self.db.execute("""
            INSERT INTO _device_health_snapshots
                (device_id, battery_level, battery_charging, storage_used_mb,
                 storage_total_mb, app_version, os_version, pending_sync_count,
                 pending_media_count, last_sync_at, memory_used_mb)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            device_id,
            snapshot.get("battery_level"),
            1 if snapshot.get("battery_charging") else 0,
            snapshot.get("storage_used_mb"),
            snapshot.get("storage_total_mb"),
            snapshot.get("app_version"),
            snapshot.get("os_version"),
            snapshot.get("pending_sync_count", 0),
            snapshot.get("pending_media_count", 0),
            snapshot.get("last_sync_at"),
            snapshot.get("memory_used_mb"),
        ))
        await self.db.commit()

        # Also update app/os version in registry for quick access
        await self.db.execute("""
            UPDATE _device_registry
               SET app_version = COALESCE(?, app_version),
                   os_version = COALESCE(?, os_version)
             WHERE device_id = ?
        """, (snapshot.get("app_version"), snapshot.get("os_version"), device_id))
        await self.db.commit()

        return cursor.lastrowid or 0

    async def get_health_history(
        self, device_id: str, *, hours: int = 48, limit: int = 200,
    ) -> list[dict]:
        """Get health snapshot history for a device."""
        since = (datetime.utcnow() - timedelta(hours=hours)).isoformat()
        cursor = await self.db.execute("""
            SELECT * FROM _device_health_snapshots
             WHERE device_id = ? AND snapshot_at >= ?
             ORDER BY snapshot_at DESC
             LIMIT ?
        """, (device_id, since, limit))
        rows = await cursor.fetchall()
        return [dict(r) for r in rows]

    async def get_latest_health(self, device_id: str) -> dict | None:
        """Get the most recent health snapshot for a device."""
        cursor = await self.db.execute("""
            SELECT * FROM _device_health_snapshots
             WHERE device_id = ? ORDER BY snapshot_at DESC LIMIT 1
        """, (device_id,))
        row = await cursor.fetchone()
        return dict(row) if row else None

    # ── Bluetooth Encounters ────────────────────────────────────────

    async def log_bt_encounter(self, encounter: dict) -> int:
        """Log a BT device-to-device encounter."""
        cursor = await self.db.execute("""
            INSERT INTO _bt_encounters
                (local_device_id, remote_device_id, encounter_start, encounter_end,
                 changes_sent, changes_received, media_bytes_sent, media_bytes_received,
                 signal_strength, status, failure_reason)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            encounter["local_device_id"],
            encounter["remote_device_id"],
            encounter["encounter_start"],
            encounter.get("encounter_end"),
            encounter.get("changes_sent", 0),
            encounter.get("changes_received", 0),
            encounter.get("media_bytes_sent", 0),
            encounter.get("media_bytes_received", 0),
            encounter.get("signal_strength"),
            encounter.get("status", "completed"),
            encounter.get("failure_reason"),
        ))
        await self.db.commit()
        return cursor.lastrowid or 0

    async def list_bt_encounters(
        self, *, device_id: str | None = None, limit: int = 50,
    ) -> list[dict]:
        """List BT encounters, optionally filtered by device."""
        if device_id:
            cursor = await self.db.execute("""
                SELECT be.*, dr1.device_name AS local_name, dr2.device_name AS remote_name
                  FROM _bt_encounters be
                  LEFT JOIN _device_registry dr1 ON dr1.device_id = be.local_device_id
                  LEFT JOIN _device_registry dr2 ON dr2.device_id = be.remote_device_id
                 WHERE be.local_device_id = ? OR be.remote_device_id = ?
                 ORDER BY be.encounter_start DESC
                 LIMIT ?
            """, (device_id, device_id, limit))
        else:
            cursor = await self.db.execute("""
                SELECT be.*, dr1.device_name AS local_name, dr2.device_name AS remote_name
                  FROM _bt_encounters be
                  LEFT JOIN _device_registry dr1 ON dr1.device_id = be.local_device_id
                  LEFT JOIN _device_registry dr2 ON dr2.device_id = be.remote_device_id
                 ORDER BY be.encounter_start DESC
                 LIMIT ?
            """, (limit,))
        rows = await cursor.fetchall()
        return [dict(r) for r in rows]

    # ── Media Delivery Tracking ─────────────────────────────────────

    async def register_media(self, media: dict) -> int:
        """Register a media file for delivery tracking."""
        cursor = await self.db.execute("""
            INSERT OR IGNORE INTO _media_delivery
                (media_path, media_hash, origin_device_id, media_size_bytes)
            VALUES (?, ?, ?, ?)
        """, (
            media["media_path"],
            media["media_hash"],
            media["origin_device_id"],
            media.get("media_size_bytes", 0),
        ))
        await self.db.commit()
        return cursor.lastrowid or 0

    async def confirm_media_delivery(self, media_hashes: list[str]) -> int:
        """Confirm that media has been delivered to the shop."""
        if not media_hashes:
            return 0
        placeholders = ",".join("?" * len(media_hashes))
        cursor = await self.db.execute(f"""
            UPDATE _media_delivery
               SET delivered_to_shop = 1, shop_confirmed_at = datetime('now')
             WHERE media_hash IN ({placeholders}) AND delivered_to_shop = 0
        """, media_hashes)
        await self.db.commit()
        return cursor.rowcount

    async def get_pending_media(self, device_id: str) -> list[dict]:
        """List media that this device's origin hasn't been confirmed by shop."""
        cursor = await self.db.execute("""
            SELECT * FROM _media_delivery
             WHERE origin_device_id = ? AND delivered_to_shop = 0
             ORDER BY created_at ASC
        """, (device_id,))
        rows = await cursor.fetchall()
        return [dict(r) for r in rows]

    # ── Shop Cluster Management ─────────────────────────────────────

    async def register_cluster_node(self, node_info: dict) -> str:
        """Register or update a shop cluster node."""
        node_id = node_info.get("node_id") or str(uuid.uuid4())
        await self.db.execute("""
            INSERT INTO _shop_cluster_nodes
                (node_id, hostname, local_ip, port, app_version, db_version,
                 last_seen_at, status)
            VALUES (?, ?, ?, ?, ?, ?, datetime('now'), 'online')
            ON CONFLICT(node_id)
            DO UPDATE SET hostname = excluded.hostname,
                          local_ip = excluded.local_ip,
                          port = excluded.port,
                          app_version = excluded.app_version,
                          db_version = excluded.db_version,
                          last_seen_at = datetime('now'),
                          status = 'online'
        """, (
            node_id,
            node_info.get("hostname"),
            node_info.get("local_ip"),
            node_info.get("port", 8000),
            node_info.get("app_version"),
            node_info.get("db_version"),
        ))
        await self.db.commit()
        return node_id

    async def list_cluster_nodes(self) -> list[dict]:
        """List all shop cluster nodes."""
        cursor = await self.db.execute("""
            SELECT * FROM _shop_cluster_nodes
             ORDER BY is_primary DESC, last_seen_at DESC
        """)
        rows = await cursor.fetchall()
        return [dict(r) for r in rows]

    async def set_cluster_primary(self, node_id: str) -> bool:
        """Designate a node as the primary shop PC."""
        await self.db.execute("UPDATE _shop_cluster_nodes SET is_primary = 0")
        cursor = await self.db.execute(
            "UPDATE _shop_cluster_nodes SET is_primary = 1 WHERE node_id = ?",
            (node_id,),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def mark_cluster_sync(self, node_id: str) -> None:
        """Record that a cluster node just synced."""
        await self.db.execute("""
            UPDATE _shop_cluster_nodes
               SET last_sync_at = datetime('now'), status = 'online'
             WHERE node_id = ?
        """, (node_id,))
        await self.db.commit()

    # ── Log Retention / Cleanup ─────────────────────────────────────

    async def run_log_retention(self) -> dict[str, int]:
        """Purge old log entries based on retention config. Returns count purged per type."""
        cursor = await self.db.execute("SELECT * FROM _log_retention_config")
        configs = [dict(r) for r in await cursor.fetchall()]
        results: dict[str, int] = {}

        table_map = {
            "sync_batches": "_sync_batches",
            "conflict_log": "_conflict_log",
            "error_log": "_device_error_log",
            "health_snapshots": "_device_health_snapshots",
            "bt_encounters": "_bt_encounters",
            "security_audit": "_security_audit_log",
            "relay_events": "_mesh_relay_events",
        }

        timestamp_col_map = {
            "sync_batches": "started_at",
            "conflict_log": "resolved_at",
            "error_log": "uploaded_at",
            "health_snapshots": "snapshot_at",
            "bt_encounters": "created_at",
            "security_audit": "recorded_at",
            "relay_events": "recorded_at",
        }

        for cfg in configs:
            log_type = cfg["log_type"]
            table = table_map.get(log_type)
            ts_col = timestamp_col_map.get(log_type)
            if not table or not ts_col:
                continue

            days = cfg["shop_retention_days"]
            cutoff = (datetime.utcnow() - timedelta(days=days)).isoformat()

            try:
                cur = await self.db.execute(
                    f"DELETE FROM {table} WHERE {ts_col} < ?",  # noqa: S608
                    (cutoff,),
                )
                results[log_type] = cur.rowcount
            except Exception as e:
                logger.warning("Log retention failed for %s: %s", log_type, e)
                results[log_type] = 0

        await self.db.commit()
        return results

    async def get_retention_config(self) -> list[dict]:
        """Get all retention configurations."""
        cursor = await self.db.execute(
            "SELECT * FROM _log_retention_config ORDER BY log_type"
        )
        return [dict(r) for r in await cursor.fetchall()]

    async def update_retention(self, log_type: str, device_days: int, shop_days: int) -> bool:
        """Update retention policy for a log type."""
        cursor = await self.db.execute("""
            UPDATE _log_retention_config
               SET device_retention_days = ?,
                   shop_retention_days = ?,
                   updated_at = datetime('now')
             WHERE log_type = ?
        """, (device_days, shop_days, log_type))
        await self.db.commit()
        return cursor.rowcount > 0

    # ── Storage Info ────────────────────────────────────────────────

    async def get_device_storage(self, device_id: str) -> dict:
        """Get storage configuration and latest usage for a device."""
        prof_cur = await self.db.execute("""
            SELECT * FROM _device_sync_profiles WHERE device_id = ?
        """, (device_id,))
        profile = await prof_cur.fetchone()

        health_cur = await self.db.execute("""
            SELECT storage_used_mb, storage_total_mb
              FROM _device_health_snapshots
             WHERE device_id = ? ORDER BY snapshot_at DESC LIMIT 1
        """, (device_id,))
        health = await health_cur.fetchone()

        media_cur = await self.db.execute("""
            SELECT COUNT(*) AS pending_count,
                   COALESCE(SUM(media_size_bytes), 0) AS pending_bytes
              FROM _media_delivery
             WHERE origin_device_id = ? AND delivered_to_shop = 0
        """, (device_id,))
        media = await media_cur.fetchone()

        return {
            "profile": dict(profile) if profile else None,
            "storage_used_mb": dict(health).get("storage_used_mb") if health else None,
            "storage_total_mb": dict(health).get("storage_total_mb") if health else None,
            "pending_media_count": dict(media)["pending_count"] if media else 0,
            "pending_media_bytes": dict(media)["pending_bytes"] if media else 0,
        }

    # ── Private Helpers ─────────────────────────────────────────────

    async def _audit(
        self, event_type: str, *, device_id: str | None = None,
        actor: int | None = None, details: dict | None = None,
    ) -> None:
        """Write to security audit log."""
        import json
        try:
            await self.db.execute("""
                INSERT INTO _security_audit_log
                    (event_type, device_id, actor_user_id, details_json, recorded_at)
                VALUES (?, ?, ?, ?, datetime('now'))
            """, (
                event_type,
                device_id,
                actor,
                json.dumps(details) if details else None,
            ))
            await self.db.commit()
        except Exception as e:
            logger.warning("Failed to write audit log: %s", e)
