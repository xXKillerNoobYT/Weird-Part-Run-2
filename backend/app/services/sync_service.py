"""
Sync service — handles device ↔ shop data synchronization.

Implements the V1.0 sync protocol:
1. Device pushes local changes to shop (POST /api/sync/push)
2. Shop applies changes, resolves conflicts (last-writer-wins)
3. Shop returns its own changes since device's last sync
4. Device applies shop changes locally
5. Device acknowledges (POST /api/sync/ack)

Conflict resolution: last-writer-wins with shop as tiebreaker.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

import aiosqlite

logger = logging.getLogger(__name__)

# Tables that are synced between shop and devices.
# Admin-only tables (cost tracking, approvals, etc.) are excluded.
# Tables synced between shop and devices.
# Order matters for initial sync — parent tables before children (FK deps).
# Admin-only tables (cost tracking, approvals, PDF reports) are excluded.
SYNCED_TABLES_ORDERED: list[str] = [
    # Foundation
    "users", "hats", "hat_permissions", "user_hats",
    "devices", "settings",
    "notifications", "notification_preferences", "notification_sounds",
    "company_profiles",
    # People & Skills
    "certifications", "user_skills", "employee_notes",
    # Parts & Inventory
    "part_categories", "part_styles", "part_types", "part_colors",
    "type_color_links", "type_brand_links",
    "brands", "suppliers", "parts",
    "brand_supplier_links", "part_supplier_links",
    "warehouse_locations",
    "stock", "stock_movements", "pulled_staging_tags",
    # Jobs & Labor
    "bill_rate_types", "jobs", "job_parts",
    "labor_entries", "clock_out_questions", "clock_out_responses",
    "one_time_questions", "daily_reports",
    "job_lead_elevations",
    # People ↔ Jobs
    "customers", "general_contractors",
    "entity_contacts",
    "job_customers", "job_general_contractors",
    # Notebooks
    "notebook_templates", "template_sections", "template_entries",
    "notebooks", "notebook_sections", "notebook_entries",
    "notebook_entry_permissions",
    "notebook_attachments",
    # "task_order_links" — deprecated: Phase 5 implemented its own order model; table unused
    # Orders
    "job_parts_orders", "jpo_line_items",
    "purchase_orders", "po_line_items",
    "returns", "return_line_items",
    "order_status_history", "special_items", "job_preferences",
    # Fleet & Vehicles
    "vehicles", "vehicle_assignments",
    "job_trailers", "trailer_location_events",
    "trailer_stock_templates", "trailer_stock_template_lines",
    "vehicle_delivery_items",
    "maintenance_types", "vehicle_maintenance_schedules",
    "vehicle_maintenance_records",
    "vehicle_mileage_logs", "vehicle_trip_legs",
    # Tools & Kits
    "tools", "kit_templates", "tool_movements",
    "kit_verification_sessions", "kit_verification_items",
    "tool_maintenance_types", "tool_maintenance_schedules",
    "tool_maintenance_records",
    # Scheduling
    "employee_default_schedules", "schedule_exceptions",
    "job_dispatch", "subcontractor_schedules",
    "dispatch_templates", "dispatch_template_members",
    "shift_patterns", "shift_pattern_days",
    # Attachments
    "order_attachments",
    # Reports
    "period_locks",
    # Chat & Q&A (Phase 9)
    "chat_channels", "chat_channel_members",
    "qa_threads", "chat_messages",
    "chat_read_receipts", "chat_mentions",
    "rfi_objects",
]

# Set for O(1) lookup
SYNCED_TABLES = set(SYNCED_TABLES_ORDERED)


class SyncService:
    """Handles sync operations between shop and devices."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    # ── Device Registration ──────────────────────────────────────

    async def register_device(
        self, device_id: str, device_name: str, platform: str, user_id: int | None = None,
    ) -> dict:
        """Register or update a device in the sync registry."""
        await self.db.execute(
            """INSERT INTO _device_registry (device_id, device_name, platform, user_id)
               VALUES (?, ?, ?, ?)
               ON CONFLICT(device_id) DO UPDATE SET
                 device_name = excluded.device_name,
                 platform = excluded.platform,
                 user_id = COALESCE(excluded.user_id, _device_registry.user_id)""",
            (device_id, device_name, platform, user_id),
        )
        await self.db.commit()

        # Ensure device sync profile exists (primary-user-owned behavior defaults)
        await self.db.execute(
            """
            INSERT OR IGNORE INTO _device_sync_profiles
            (device_id, primary_user_id, updated_by)
            VALUES (?, ?, ?)
            """,
            (device_id, user_id, user_id),
        )
        await self.db.commit()

        cursor = await self.db.execute(
            "SELECT * FROM _device_registry WHERE device_id = ?", (device_id,),
        )
        return dict(await cursor.fetchone())

    async def get_device_sync_profile(self, device_id: str) -> dict | None:
        cursor = await self.db.execute(
            "SELECT * FROM _device_sync_profiles WHERE device_id = ?",
            (device_id,),
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

    async def upsert_device_sync_profile(
        self,
        *,
        device_id: str,
        updated_by: int | None,
        fields: dict,
    ) -> dict:
        existing = await self.get_device_sync_profile(device_id)
        if not existing:
            await self.db.execute(
                """
                INSERT INTO _device_sync_profiles (device_id, primary_user_id, updated_by)
                VALUES (?, ?, ?)
                """,
                (device_id, updated_by, updated_by),
            )

        allowed = {
            "primary_user_id",
            "storage_policy",
            "media_policy",
            "media_retention_days",
            "force_carry_undelivered_media",
            "allow_borrowed_user_overrides",
            "active_only_sync",
        }
        patch = {k: v for k, v in fields.items() if k in allowed}
        patch["updated_by"] = updated_by

        set_sql = ", ".join([f"{k} = ?" for k in patch] + ["updated_at = datetime('now')"])
        values = list(patch.values()) + [device_id]
        await self.db.execute(
            f"UPDATE _device_sync_profiles SET {set_sql} WHERE device_id = ?",
            values,
        )
        await self.db.commit()

        result = await self.get_device_sync_profile(device_id)
        return result or {}

    async def log_mesh_relay_event(
        self,
        *,
        source_device_id: str,
        peer_device_id: str,
        relay_type: str = "gossip",
        carried_change_count: int = 0,
        carried_media_count: int = 0,
        undelivered_after_count: int = 0,
        metadata: dict | None = None,
    ) -> dict:
        cursor = await self.db.execute(
            """
            INSERT INTO _mesh_relay_events (
                source_device_id, peer_device_id, relay_type,
                carried_change_count, carried_media_count,
                undelivered_after_count, metadata_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                source_device_id,
                peer_device_id,
                relay_type,
                carried_change_count,
                carried_media_count,
                undelivered_after_count,
                json.dumps(metadata or {}),
            ),
        )
        event_id = cursor.lastrowid
        await self.db.commit()
        cursor = await self.db.execute("SELECT * FROM _mesh_relay_events WHERE id = ?", (event_id,))
        row = await cursor.fetchone()
        data = dict(row) if row else {}
        if data:
            data["metadata"] = json.loads(data.get("metadata_json") or "{}")
        return data

    async def get_mesh_relay_events(
        self,
        *,
        device_id: str | None = None,
        limit: int = 100,
    ) -> list[dict]:
        sql = "SELECT * FROM _mesh_relay_events"
        params: list[Any] = []
        if device_id:
            sql += " WHERE source_device_id = ? OR peer_device_id = ?"
            params.extend([device_id, device_id])
        sql += " ORDER BY recorded_at DESC, id DESC LIMIT ?"
        params.append(limit)

        cursor = await self.db.execute(sql, tuple(params))
        rows = await cursor.fetchall()
        out: list[dict] = []
        for r in rows:
            d = dict(r)
            d["metadata"] = json.loads(d.get("metadata_json") or "{}")
            out.append(d)
        return out

    async def get_device_status(self, device_id: str) -> dict | None:
        """Get a device's sync status."""
        cursor = await self.db.execute(
            "SELECT * FROM _device_registry WHERE device_id = ?", (device_id,),
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

    async def list_devices(self) -> list[dict]:
        """List all registered sync devices."""
        cursor = await self.db.execute(
            "SELECT * FROM _device_registry ORDER BY registered_at DESC",
        )
        return [dict(r) for r in await cursor.fetchall()]

    # ── Hard Sync Backup / Recovery ─────────────────────────────

    async def request_hard_sync(
        self,
        *,
        device_id: str,
        requested_by: int | None,
        reason_code: str | None = None,
        pending_outbound_hashes: list[str] | None = None,
        include_tables: list[str] | None = None,
        preserve_pending_data: bool = True,
        notes: str | None = None,
    ) -> dict:
        """Prepare a deterministic hard-sync package for a device.

        The package is a full table snapshot (or scoped table subset) using the
        existing initial-sync ordering so FK integrity is preserved.
        """
        # Ensure device is known for auditability.
        status = await self.get_device_status(device_id)
        if not status:
            await self.register_device(
                device_id=device_id,
                device_name="Hard Sync Device",
                platform="unknown",
                user_id=requested_by,
            )

        batch_id = await self.create_batch(device_id=device_id, direction="full")
        tables = await self.get_initial_sync_data(include_tables)
        total_rows = sum(len(rows) for rows in tables.values())

        summary = {
            "table_count": len(tables),
            "total_rows": total_rows,
            "generated_at": datetime.now(timezone.utc).isoformat(),
        }

        cursor = await self.db.execute(
            """
            INSERT INTO _hard_sync_events (
                device_id, requested_by, reason_code,
                pending_outbound_hashes, include_tables,
                preserve_pending_data, sync_batch_id,
                package_summary, status, notes
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'package_ready', ?)
            """,
            (
                device_id,
                requested_by,
                reason_code,
                json.dumps(pending_outbound_hashes or []),
                json.dumps(include_tables or []),
                1 if preserve_pending_data else 0,
                batch_id,
                json.dumps(summary),
                notes,
            ),
        )
        hard_sync_id = cursor.lastrowid

        await self.update_batch(
            batch_id,
            sent=total_rows,
            received=0,
            conflicts=0,
        )
        await self.db.execute(
            """
            UPDATE _sync_batches
            SET status = 'completed', completed_at = datetime('now')
            WHERE id = ?
            """,
            (batch_id,),
        )
        await self.db.commit()

        return {
            "hard_sync_id": hard_sync_id,
            "sync_batch_id": batch_id,
            "device_id": device_id,
            "tables": tables,
            "table_count": len(tables),
            "total_rows": total_rows,
            "preserve_pending_data": preserve_pending_data,
            "server_time": datetime.now(timezone.utc).isoformat(),
        }

    async def complete_hard_sync(
        self,
        *,
        hard_sync_id: int,
        device_id: str,
        sync_batch_id: str,
        completed_by: int | None,
        applied_tables: list[str] | None = None,
        restored_pending_count: int = 0,
        notes: str | None = None,
    ) -> dict | None:
        """Mark a hard sync as completed by the device."""
        cursor = await self.db.execute(
            "SELECT * FROM _hard_sync_events WHERE id = ? AND device_id = ?",
            (hard_sync_id, device_id),
        )
        existing = await cursor.fetchone()
        if not existing:
            return None

        await self.db.execute(
            """
            UPDATE _hard_sync_events
            SET status = 'completed',
                started_at = COALESCE(started_at, datetime('now')),
                completed_at = datetime('now'),
                notes = COALESCE(?, notes)
            WHERE id = ?
            """,
            (notes, hard_sync_id),
        )

        await self.mark_device_synced(device_id, sync_batch_id)

        return {
            "hard_sync_id": hard_sync_id,
            "device_id": device_id,
            "sync_batch_id": sync_batch_id,
            "applied_tables": applied_tables or [],
            "restored_pending_count": restored_pending_count,
            "completed_by": completed_by,
            "completed_at": datetime.now(timezone.utc).isoformat(),
        }

    async def get_hard_sync_history(
        self,
        *,
        device_id: str | None = None,
        limit: int = 50,
    ) -> list[dict]:
        sql = "SELECT * FROM _hard_sync_events"
        params: list[Any] = []
        if device_id:
            sql += " WHERE device_id = ?"
            params.append(device_id)
        sql += " ORDER BY requested_at DESC LIMIT ?"
        params.append(limit)

        cursor = await self.db.execute(sql, tuple(params))
        rows = await cursor.fetchall()
        return [dict(r) for r in rows]

    # ── Shop-Side Change Tracking ────────────────────────────────

    async def log_shop_change(
        self,
        table_name: str,
        record_id: int,
        operation: str,
        changed_fields: dict | None = None,
        source_device_id: str | None = None,
    ) -> None:
        """Log a change on the shop side for future sync to devices."""
        if table_name not in SYNCED_TABLES:
            return
        await self.db.execute(
            """INSERT INTO _shop_change_log
               (source_device_id, table_name, record_id, operation, changed_fields)
               VALUES (?, ?, ?, ?, ?)""",
            (
                source_device_id,
                table_name,
                record_id,
                operation,
                json.dumps(changed_fields) if changed_fields else None,
            ),
        )

    # ── Sync Push (Device → Shop) ────────────────────────────────

    async def apply_device_changes(
        self,
        device_id: str,
        changes: list[dict],
    ) -> tuple[list[dict], list[dict]]:
        """Apply a batch of changes from a device to the shop DB.

        Returns (applied, conflicts) where:
        - applied: changes that were successfully applied
        - conflicts: changes that conflicted with shop data
        """
        applied: list[dict] = []
        conflicts: list[dict] = []

        for change in changes:
            table = change["table_name"]
            record_id = change["record_id"]
            operation = change["operation"]
            changed_fields = json.loads(change.get("changed_fields") or "{}")
            device_timestamp = change.get("timestamp", "")

            if table not in SYNCED_TABLES:
                logger.warning("Ignoring sync for non-synced table: %s", table)
                continue

            try:
                # Check for conflicts — was this record changed on the shop
                # since the device last synced?
                cursor = await self.db.execute(
                    """SELECT * FROM _shop_change_log
                       WHERE table_name = ? AND record_id = ?
                         AND source_device_id != ? AND timestamp > ?
                       ORDER BY timestamp DESC LIMIT 1""",
                    (table, record_id, device_id, device_timestamp),
                )
                shop_change = await cursor.fetchone()

                if shop_change:
                    # Conflict! Last-writer-wins with shop as tiebreaker
                    conflict = await self._resolve_conflict(
                        table, record_id, device_id,
                        changed_fields, device_timestamp,
                        dict(shop_change),
                    )
                    conflicts.append(conflict)
                else:
                    # No conflict — apply the device's change
                    await self._apply_change(
                        table, record_id, operation, changed_fields, device_id,
                    )
                    applied.append(change)

            except Exception as exc:
                logger.error(
                    "Failed to apply sync change: table=%s id=%d op=%s — %s",
                    table, record_id, operation, exc,
                )
                conflicts.append({
                    "table_name": table,
                    "record_id": record_id,
                    "resolution": "error",
                    "error": str(exc),
                })

        return applied, conflicts

    async def _apply_change(
        self,
        table: str,
        record_id: int,
        operation: str,
        changed_fields: dict,
        device_id: str,
    ) -> None:
        """Apply a single change from a device to the shop DB."""
        if operation == "INSERT":
            # Check if record already exists (ID collision)
            cursor = await self.db.execute(
                f"SELECT id FROM {table} WHERE id = ?", (record_id,),
            )
            existing = await cursor.fetchone()
            if existing:
                # Record already exists — treat as UPDATE
                await self._apply_update(table, record_id, changed_fields)
            else:
                # Insert new record
                keys = list(changed_fields.keys())
                if "id" not in keys:
                    keys.insert(0, "id")
                    changed_fields["id"] = record_id
                placeholders = ", ".join("?" for _ in keys)
                values = [changed_fields[k] for k in keys]
                await self.db.execute(
                    f"INSERT INTO {table} ({', '.join(keys)}) VALUES ({placeholders})",
                    values,
                )

        elif operation == "UPDATE":
            await self._apply_update(table, record_id, changed_fields)

        elif operation == "DELETE":
            await self.db.execute(
                f"DELETE FROM {table} WHERE id = ?", (record_id,),
            )

        # Log the change so other devices can pull it
        await self.log_shop_change(
            table, record_id, operation, changed_fields, source_device_id=device_id,
        )
        await self.db.commit()

    async def _apply_update(
        self, table: str, record_id: int, changed_fields: dict,
    ) -> None:
        """Apply an UPDATE to a specific record."""
        if not changed_fields:
            return
        set_parts = [f"{k} = ?" for k in changed_fields]
        values = list(changed_fields.values()) + [record_id]
        await self.db.execute(
            f"UPDATE {table} SET {', '.join(set_parts)} WHERE id = ?",
            values,
        )

    async def _resolve_conflict(
        self,
        table: str,
        record_id: int,
        device_id: str,
        device_fields: dict,
        device_timestamp: str,
        shop_change: dict,
    ) -> dict:
        """Resolve a conflict using last-writer-wins (shop as tiebreaker)."""
        shop_timestamp = shop_change.get("timestamp", "")

        # Last-writer-wins: compare timestamps
        if device_timestamp > shop_timestamp:
            resolution = "device_wins"
            # Apply device's version
            await self._apply_update(table, record_id, device_fields)
            await self.log_shop_change(
                table, record_id, "UPDATE", device_fields, source_device_id=device_id,
            )
            await self.db.commit()
        else:
            resolution = "shop_wins"
            # Shop's version stays — device will get it on pull

        # Fetch current shop values for the conflict log
        cursor = await self.db.execute(
            f"SELECT * FROM {table} WHERE id = ?", (record_id,),
        )
        shop_row = await cursor.fetchone()
        shop_values = dict(shop_row) if shop_row else {}

        # Log the conflict
        await self.db.execute(
            """INSERT INTO _conflict_log
               (table_name, record_id, device_a_id, resolution,
                device_values, shop_values, resolved_values)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (
                table, record_id, device_id, resolution,
                json.dumps(device_fields),
                json.dumps(shop_values, default=str),
                json.dumps(shop_values, default=str),
            ),
        )
        await self.db.commit()

        logger.info(
            "Sync conflict: %s.%d — %s (device=%s vs shop=%s)",
            table, record_id, resolution, device_timestamp, shop_timestamp,
        )

        return {
            "table_name": table,
            "record_id": record_id,
            "resolution": resolution,
            "shop_values": shop_values,
        }

    # ── Sync Pull (Shop → Device) ────────────────────────────────

    async def get_changes_since(
        self,
        since: str,
        exclude_device: str | None = None,
    ) -> list[dict]:
        """Get shop changes since a timestamp, excluding a device's own changes."""
        sql = """SELECT * FROM _shop_change_log
                 WHERE timestamp > ?"""
        params: list[Any] = [since]

        if exclude_device:
            sql += " AND (source_device_id IS NULL OR source_device_id != ?)"
            params.append(exclude_device)

        sql += " ORDER BY timestamp ASC"

        cursor = await self.db.execute(sql, params)
        rows = await cursor.fetchall()

        # For each change, include the current record data so the device
        # can apply it directly (avoids needing field-level diffs)
        changes = []
        for row in rows:
            change = dict(row)
            if row["operation"] != "DELETE":
                cursor2 = await self.db.execute(
                    f"SELECT * FROM {row['table_name']} WHERE id = ?",
                    (row["record_id"],),
                )
                record = await cursor2.fetchone()
                change["record_data"] = dict(record) if record else None
            changes.append(change)

        return changes

    # ── Initial Sync (Full Pull) ─────────────────────────────────

    async def get_initial_sync_data(
        self,
        tables: list[str] | None = None,
        *,
        only_active_jobs: bool = False,
    ) -> dict:
        """Get full table data for initial device setup.

        Returns all rows from synced tables. Used when a device first
        connects and needs to populate its local DB from scratch.
        """
        target_tables = tables or SYNCED_TABLES_ORDERED
        data: dict[str, list[dict]] = {}

        active_job_ids: list[int] = []
        if only_active_jobs:
            cursor = await self.db.execute("SELECT id FROM jobs WHERE status = 'active'")
            active_job_ids = [int(r["id"]) for r in await cursor.fetchall()]

        for table in target_tables:
            if table not in SYNCED_TABLES:
                continue
            try:
                # Core rule: only active jobs on devices when requested.
                if only_active_jobs and table == "jobs":
                    cursor = await self.db.execute(
                        "SELECT * FROM jobs WHERE status = 'active'",
                    )
                elif only_active_jobs and active_job_ids:
                    # Generic filter for tables that carry a direct job_id FK.
                    info_cur = await self.db.execute(f"PRAGMA table_info({table})")
                    cols = [r["name"] for r in await info_cur.fetchall()]
                    if "job_id" in cols:
                        placeholders = ",".join("?" for _ in active_job_ids)
                        cursor = await self.db.execute(
                            f"SELECT * FROM {table} WHERE job_id IS NULL OR job_id IN ({placeholders})",
                            tuple(active_job_ids),
                        )
                    else:
                        cursor = await self.db.execute(f"SELECT * FROM {table}")
                else:
                    cursor = await self.db.execute(f"SELECT * FROM {table}")
                rows = await cursor.fetchall()
                data[table] = [dict(r) for r in rows]
            except Exception as exc:
                logger.warning("Skipping table %s during initial sync: %s", table, exc)
                data[table] = []

        return data

    # ── Sync Acknowledgment ──────────────────────────────────────

    async def mark_device_synced(
        self, device_id: str, batch_id: str,
    ) -> None:
        """Mark a device as synced after it confirms applying shop changes."""
        now = datetime.now(timezone.utc).isoformat()
        await self.db.execute(
            """UPDATE _device_registry
               SET last_sync_at = ?, last_sync_batch_id = ?, pending_changes = 0
               WHERE device_id = ?""",
            (now, batch_id, device_id),
        )
        # Mark the sync batch as completed
        await self.db.execute(
            """UPDATE _sync_batches SET status = 'completed', completed_at = ?
               WHERE id = ?""",
            (now, batch_id),
        )
        await self.db.commit()

    # ── Batch Management ─────────────────────────────────────────

    async def create_batch(self, device_id: str, direction: str) -> str:
        """Create a new sync batch and return its ID."""
        batch_id = str(uuid4())
        await self.db.execute(
            """INSERT INTO _sync_batches (id, device_id, direction)
               VALUES (?, ?, ?)""",
            (batch_id, device_id, direction),
        )
        await self.db.commit()
        return batch_id

    async def update_batch(
        self, batch_id: str, sent: int = 0, received: int = 0, conflicts: int = 0,
    ) -> None:
        """Update batch statistics."""
        await self.db.execute(
            """UPDATE _sync_batches
               SET changes_sent = ?, changes_received = ?, conflicts_resolved = ?
               WHERE id = ?""",
            (sent, received, conflicts, batch_id),
        )
        await self.db.commit()

    # ── Admin / Debug ────────────────────────────────────────────

    async def get_sync_history(
        self, device_id: str | None = None, limit: int = 50,
    ) -> list[dict]:
        """Get recent sync batches for admin review."""
        if device_id:
            cursor = await self.db.execute(
                """SELECT * FROM _sync_batches
                   WHERE device_id = ?
                   ORDER BY started_at DESC LIMIT ?""",
                (device_id, limit),
            )
        else:
            cursor = await self.db.execute(
                "SELECT * FROM _sync_batches ORDER BY started_at DESC LIMIT ?",
                (limit,),
            )
        return [dict(r) for r in await cursor.fetchall()]

    async def get_conflict_log(self, limit: int = 50) -> list[dict]:
        """Get recent conflicts for admin review."""
        cursor = await self.db.execute(
            "SELECT * FROM _conflict_log ORDER BY resolved_at DESC LIMIT ?",
            (limit,),
        )
        return [dict(r) for r in await cursor.fetchall()]

    async def cleanup_old_logs(self, days: int = 365) -> dict:
        """Clean up old sync logs. Called by scheduler."""
        cursor = await self.db.execute(
            "DELETE FROM _shop_change_log WHERE timestamp < datetime('now', '-' || ? || ' days')",
            (days,),
        )
        changes_deleted = cursor.rowcount or 0

        cursor = await self.db.execute(
            "DELETE FROM _conflict_log WHERE resolved_at < datetime('now', '-' || ? || ' days')",
            (days,),
        )
        conflicts_deleted = cursor.rowcount or 0

        await self.db.commit()
        return {
            "change_log_entries_deleted": changes_deleted,
            "conflicts_deleted": conflicts_deleted,
        }

    # ── Peer-to-Peer Relay Transport ─────────────────────────────

    async def upsert_relay_manifest(
        self,
        *,
        device_id: str,
        pending_change_count: int = 0,
        pending_media_count: int = 0,
        change_hashes: list[str] | None = None,
        media_hashes: list[str] | None = None,
        origin_device_ids: list[str] | None = None,
    ) -> dict:
        """Create or update a device's relay manifest.

        A relay manifest advertises what undelivered data a device is
        carrying so peers can decide what to accept during BT handshakes.
        """
        await self.db.execute(
            """
            INSERT INTO _relay_manifests (
                device_id, pending_change_count, pending_media_count,
                change_hashes_json, media_hashes_json, origin_device_ids_json,
                updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
            ON CONFLICT(device_id) DO UPDATE SET
                pending_change_count = excluded.pending_change_count,
                pending_media_count  = excluded.pending_media_count,
                change_hashes_json   = excluded.change_hashes_json,
                media_hashes_json    = excluded.media_hashes_json,
                origin_device_ids_json = excluded.origin_device_ids_json,
                updated_at           = datetime('now')
            """,
            (
                device_id,
                pending_change_count,
                pending_media_count,
                json.dumps(change_hashes or []),
                json.dumps(media_hashes or []),
                json.dumps(origin_device_ids or []),
            ),
        )
        await self.db.commit()

        cursor = await self.db.execute(
            "SELECT * FROM _relay_manifests WHERE device_id = ?", (device_id,)
        )
        row = await cursor.fetchone()
        return self._manifest_to_dict(row)

    async def get_relay_manifest(self, device_id: str) -> dict | None:
        """Get a device's current relay manifest."""
        cursor = await self.db.execute(
            "SELECT * FROM _relay_manifests WHERE device_id = ?", (device_id,)
        )
        row = await cursor.fetchone()
        return self._manifest_to_dict(row) if row else None

    async def list_relay_manifests(self) -> list[dict]:
        """List all relay manifests (admin oversight)."""
        cursor = await self.db.execute(
            "SELECT * FROM _relay_manifests ORDER BY updated_at DESC"
        )
        return [self._manifest_to_dict(r) for r in await cursor.fetchall()]

    @staticmethod
    def _manifest_to_dict(row: Any) -> dict:
        d = dict(row)
        d["change_hashes"] = json.loads(d.pop("change_hashes_json", "[]") or "[]")
        d["media_hashes"] = json.loads(d.pop("media_hashes_json", "[]") or "[]")
        d["origin_device_ids"] = json.loads(d.pop("origin_device_ids_json", "[]") or "[]")
        return d

    # ── Relay Packages (P2P data transfer audit) ─────────────────

    async def create_relay_package(
        self,
        *,
        sender_device_id: str,
        receiver_device_id: str,
        origin_device_id: str,
        change_count: int = 0,
        media_count: int = 0,
        package_hash: str | None = None,
    ) -> dict:
        """Record a relay package as it's created for peer transfer.

        Called when one device prepares a data bundle to hand off to
        another device via BT or LAN.
        """
        cursor = await self.db.execute(
            """
            INSERT INTO _relay_packages (
                sender_device_id, receiver_device_id, origin_device_id,
                change_count, media_count, package_hash
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                sender_device_id,
                receiver_device_id,
                origin_device_id,
                change_count,
                media_count,
                package_hash,
            ),
        )
        pkg_id = cursor.lastrowid
        await self.db.commit()

        cursor = await self.db.execute(
            "SELECT * FROM _relay_packages WHERE id = ?", (pkg_id,)
        )
        return dict(await cursor.fetchone())

    async def update_relay_package_status(
        self,
        package_id: int,
        status: str,
        failure_reason: str | None = None,
    ) -> dict | None:
        """Update status of a relay package.

        status: 'transferred' | 'confirmed' | 'failed'
        """
        ts_col = {
            "transferred": "transferred_at",
            "confirmed": "confirmed_at",
        }.get(status)

        sql_parts = ["status = ?"]
        params: list[Any] = [status]

        if ts_col:
            sql_parts.append(f"{ts_col} = datetime('now')")
        if failure_reason:
            sql_parts.append("failure_reason = ?")
            params.append(failure_reason)

        params.append(package_id)
        await self.db.execute(
            f"UPDATE _relay_packages SET {', '.join(sql_parts)} WHERE id = ?",
            params,
        )
        await self.db.commit()

        cursor = await self.db.execute(
            "SELECT * FROM _relay_packages WHERE id = ?", (package_id,)
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

    async def list_relay_packages(
        self,
        *,
        device_id: str | None = None,
        status: str | None = None,
        limit: int = 100,
    ) -> list[dict]:
        """List relay packages, optionally filtered by device or status."""
        sql = "SELECT * FROM _relay_packages"
        conditions: list[str] = []
        params: list[Any] = []

        if device_id:
            conditions.append(
                "(sender_device_id = ? OR receiver_device_id = ? OR origin_device_id = ?)"
            )
            params.extend([device_id, device_id, device_id])
        if status:
            conditions.append("status = ?")
            params.append(status)

        if conditions:
            sql += " WHERE " + " AND ".join(conditions)
        sql += " ORDER BY created_at DESC LIMIT ?"
        params.append(limit)

        cursor = await self.db.execute(sql, tuple(params))
        return [dict(r) for r in await cursor.fetchall()]

    # ── Delivery Receipts ────────────────────────────────────────

    async def issue_delivery_receipt(
        self,
        *,
        origin_device_id: str,
        delivered_by_device_id: str,
        receipt_type: str = "changes",
        change_count: int = 0,
        media_count: int = 0,
        delivered_hashes: list[str] | None = None,
        relay_chain: list[str] | None = None,
    ) -> dict:
        """Issue a delivery receipt when relayed data reaches the shop.

        The receipt confirms that data originally from `origin_device_id`
        was delivered to the shop by `delivered_by_device_id`.  The receipt
        must flow back to the origin device so it can safely purge its
        local copies of the relayed data.
        """
        cursor = await self.db.execute(
            """
            INSERT INTO _delivery_receipts (
                origin_device_id, delivered_by_device_id, receipt_type,
                change_count, media_count, delivered_hashes_json,
                relay_chain_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                origin_device_id,
                delivered_by_device_id,
                receipt_type,
                change_count,
                media_count,
                json.dumps(delivered_hashes or []),
                json.dumps(relay_chain or []),
            ),
        )
        receipt_id = cursor.lastrowid
        await self.db.commit()

        cursor = await self.db.execute(
            "SELECT * FROM _delivery_receipts WHERE id = ?", (receipt_id,)
        )
        row = await cursor.fetchone()
        return self._receipt_to_dict(row)

    async def get_pending_receipts(
        self,
        origin_device_id: str,
        limit: int = 100,
    ) -> list[dict]:
        """Get unacknowledged delivery receipts destined for a device.

        Called when a device syncs and asks "what receipts do I need to
        acknowledge?" — this allows the device to purge relayed data.
        """
        cursor = await self.db.execute(
            """
            SELECT * FROM _delivery_receipts
            WHERE origin_device_id = ? AND acknowledged_by_origin = 0
            ORDER BY issued_at DESC LIMIT ?
            """,
            (origin_device_id, limit),
        )
        return [self._receipt_to_dict(r) for r in await cursor.fetchall()]

    async def acknowledge_receipt(self, receipt_id: int) -> dict | None:
        """Acknowledge a delivery receipt — origin device confirms it
        can safely purge the delivered data."""
        cursor = await self.db.execute(
            "SELECT * FROM _delivery_receipts WHERE id = ?", (receipt_id,)
        )
        existing = await cursor.fetchone()
        if not existing:
            return None

        await self.db.execute(
            """
            UPDATE _delivery_receipts
            SET acknowledged_by_origin = 1, acknowledged_at = datetime('now')
            WHERE id = ?
            """,
            (receipt_id,),
        )
        await self.db.commit()

        cursor = await self.db.execute(
            "SELECT * FROM _delivery_receipts WHERE id = ?", (receipt_id,)
        )
        row = await cursor.fetchone()
        return self._receipt_to_dict(row) if row else None

    async def acknowledge_receipts_bulk(
        self,
        receipt_ids: list[int],
    ) -> int:
        """Acknowledge multiple delivery receipts at once.

        Returns count of receipts acknowledged.
        """
        if not receipt_ids:
            return 0
        placeholders = ",".join("?" for _ in receipt_ids)
        cursor = await self.db.execute(
            f"""
            UPDATE _delivery_receipts
            SET acknowledged_by_origin = 1, acknowledged_at = datetime('now')
            WHERE id IN ({placeholders}) AND acknowledged_by_origin = 0
            """,
            tuple(receipt_ids),
        )
        count = cursor.rowcount or 0
        await self.db.commit()
        return count

    async def list_delivery_receipts(
        self,
        *,
        device_id: str | None = None,
        acknowledged: bool | None = None,
        limit: int = 100,
    ) -> list[dict]:
        """List delivery receipts for admin review."""
        sql = "SELECT * FROM _delivery_receipts"
        conditions: list[str] = []
        params: list[Any] = []

        if device_id:
            conditions.append(
                "(origin_device_id = ? OR delivered_by_device_id = ?)"
            )
            params.extend([device_id, device_id])
        if acknowledged is not None:
            conditions.append("acknowledged_by_origin = ?")
            params.append(1 if acknowledged else 0)

        if conditions:
            sql += " WHERE " + " AND ".join(conditions)
        sql += " ORDER BY issued_at DESC LIMIT ?"
        params.append(limit)

        cursor = await self.db.execute(sql, tuple(params))
        return [self._receipt_to_dict(r) for r in await cursor.fetchall()]

    async def get_relay_stats(self, device_id: str | None = None) -> dict:
        """Get aggregate relay statistics for the dashboard.

        Returns counts of relay events, packages, and receipts grouped
        by type and status.
        """
        stats: dict[str, Any] = {}

        # Relay events by type
        if device_id:
            cursor = await self.db.execute(
                """
                SELECT relay_type, COUNT(*) as cnt,
                       SUM(carried_change_count) as total_changes,
                       SUM(carried_media_count) as total_media
                FROM _mesh_relay_events
                WHERE source_device_id = ? OR peer_device_id = ?
                GROUP BY relay_type
                """,
                (device_id, device_id),
            )
        else:
            cursor = await self.db.execute(
                """
                SELECT relay_type, COUNT(*) as cnt,
                       SUM(carried_change_count) as total_changes,
                       SUM(carried_media_count) as total_media
                FROM _mesh_relay_events
                GROUP BY relay_type
                """
            )
        stats["events_by_type"] = [dict(r) for r in await cursor.fetchall()]

        # Relay packages by status
        if device_id:
            cursor = await self.db.execute(
                """
                SELECT status, COUNT(*) as cnt
                FROM _relay_packages
                WHERE sender_device_id = ? OR receiver_device_id = ?
                GROUP BY status
                """,
                (device_id, device_id),
            )
        else:
            cursor = await self.db.execute(
                "SELECT status, COUNT(*) as cnt FROM _relay_packages GROUP BY status"
            )
        stats["packages_by_status"] = [dict(r) for r in await cursor.fetchall()]

        # Delivery receipts: pending vs acknowledged
        if device_id:
            cursor = await self.db.execute(
                """
                SELECT acknowledged_by_origin, COUNT(*) as cnt,
                       SUM(change_count) as total_changes,
                       SUM(media_count) as total_media
                FROM _delivery_receipts
                WHERE origin_device_id = ? OR delivered_by_device_id = ?
                GROUP BY acknowledged_by_origin
                """,
                (device_id, device_id),
            )
        else:
            cursor = await self.db.execute(
                """
                SELECT acknowledged_by_origin, COUNT(*) as cnt,
                       SUM(change_count) as total_changes,
                       SUM(media_count) as total_media
                FROM _delivery_receipts
                GROUP BY acknowledged_by_origin
                """
            )
        stats["receipts_by_status"] = [dict(r) for r in await cursor.fetchall()]

        # Active manifest count
        cursor = await self.db.execute(
            "SELECT COUNT(*) as cnt FROM _relay_manifests WHERE pending_change_count > 0 OR pending_media_count > 0"
        )
        row = await cursor.fetchone()
        stats["active_manifests"] = row["cnt"] if row else 0

        return stats

    @staticmethod
    def _receipt_to_dict(row: Any) -> dict:
        d = dict(row)
        d["delivered_hashes"] = json.loads(d.pop("delivered_hashes_json", "[]") or "[]")
        d["relay_chain"] = json.loads(d.pop("relay_chain_json", "[]") or "[]")
        return d
