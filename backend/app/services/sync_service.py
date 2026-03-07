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
from datetime import datetime
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
        cursor = await self.db.execute(
            "SELECT * FROM _device_registry WHERE device_id = ?", (device_id,),
        )
        return dict(await cursor.fetchone())

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

    async def get_initial_sync_data(self, tables: list[str] | None = None) -> dict:
        """Get full table data for initial device setup.

        Returns all rows from synced tables. Used when a device first
        connects and needs to populate its local DB from scratch.
        """
        target_tables = tables or SYNCED_TABLES_ORDERED
        data: dict[str, list[dict]] = {}

        for table in target_tables:
            if table not in SYNCED_TABLES:
                continue
            try:
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
        now = datetime.utcnow().isoformat()
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

    async def cleanup_old_logs(self, days: int = 90) -> dict:
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
