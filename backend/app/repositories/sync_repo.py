"""
Repository for sync engine database operations.

Handles:
- _shop_change_log: logging every shop-side write for device pull
- _device_registry: tracking known devices and their sync state
- _conflict_log: recording conflict resolutions for admin review
- _sync_batches: audit trail of sync sessions
"""

from __future__ import annotations

import json
from typing import Any

import aiosqlite


class SyncRepo:
    """Database operations for the sync engine."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    # ── Shop Change Log ──────────────────────────────────────────

    async def log_shop_change(
        self,
        table_name: str,
        record_id: int,
        operation: str,
        changed_fields: dict[str, Any] | None = None,
        source_device_id: str | None = None,
    ) -> int:
        """Record a change in the shop's change log.

        Called on every write (INSERT/UPDATE/DELETE) on the shop DB.
        If the change originated from a device sync, source_device_id is set
        so we can exclude it when sending changes back to that device.
        """
        cursor = await self.db.execute(
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
        return cursor.lastrowid  # type: ignore[return-value]

    async def get_changes_since(
        self,
        since: str | None,
        exclude_device_id: str | None = None,
        limit: int = 5000,
    ) -> list[dict]:
        """Get shop changes since a timestamp.

        Excludes changes that originated from the requesting device
        (so a device doesn't re-apply its own changes).
        """
        conditions = []
        params: list[Any] = []

        if since:
            conditions.append("timestamp > ?")
            params.append(since)

        if exclude_device_id:
            conditions.append(
                "(source_device_id IS NULL OR source_device_id != ?)"
            )
            params.append(exclude_device_id)

        where = f" WHERE {' AND '.join(conditions)}" if conditions else ""
        params.append(limit)

        cursor = await self.db.execute(
            f"SELECT * FROM _shop_change_log{where} ORDER BY timestamp ASC LIMIT ?",
            tuple(params),
        )
        return await cursor.fetchall()

    # ── Device Registry ──────────────────────────────────────────

    async def register_device(
        self,
        device_id: str,
        device_name: str | None = None,
        platform: str | None = None,
        user_id: int | None = None,
    ) -> None:
        """Register or update a device in the registry."""
        await self.db.execute(
            """INSERT INTO _device_registry (device_id, device_name, platform, user_id)
               VALUES (?, ?, ?, ?)
               ON CONFLICT(device_id) DO UPDATE SET
                   device_name = COALESCE(excluded.device_name, device_name),
                   platform = COALESCE(excluded.platform, platform),
                   user_id = COALESCE(excluded.user_id, user_id)""",
            (device_id, device_name, platform, user_id),
        )

    async def update_device_sync(
        self,
        device_id: str,
        sync_batch_id: str,
        pending_changes: int = 0,
    ) -> None:
        """Update a device's last sync state."""
        await self.db.execute(
            """UPDATE _device_registry
               SET last_sync_at = datetime('now'),
                   last_sync_batch_id = ?,
                   pending_changes = ?
               WHERE device_id = ?""",
            (sync_batch_id, pending_changes, device_id),
        )

    async def get_device(self, device_id: str) -> dict | None:
        """Get a device's registry entry."""
        cursor = await self.db.execute(
            "SELECT * FROM _device_registry WHERE device_id = ?",
            (device_id,),
        )
        return await cursor.fetchone()

    async def get_all_devices(self) -> list[dict]:
        """Get all registered devices."""
        cursor = await self.db.execute(
            "SELECT * FROM _device_registry ORDER BY last_sync_at DESC"
        )
        return await cursor.fetchall()

    # ── Conflict Log ─────────────────────────────────────────────

    async def log_conflict(
        self,
        table_name: str,
        record_id: int,
        device_id: str,
        resolution: str,
        device_values: dict | None = None,
        shop_values: dict | None = None,
        resolved_values: dict | None = None,
    ) -> int:
        """Record a sync conflict and its resolution."""
        cursor = await self.db.execute(
            """INSERT INTO _conflict_log
               (table_name, record_id, device_a_id, resolution,
                device_values, shop_values, resolved_values)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (
                table_name,
                record_id,
                device_id,
                resolution,
                json.dumps(device_values) if device_values else None,
                json.dumps(shop_values) if shop_values else None,
                json.dumps(resolved_values) if resolved_values else None,
            ),
        )
        return cursor.lastrowid  # type: ignore[return-value]

    async def get_recent_conflicts(self, limit: int = 50) -> list[dict]:
        """Get recent conflicts for admin review."""
        cursor = await self.db.execute(
            "SELECT * FROM _conflict_log ORDER BY resolved_at DESC LIMIT ?",
            (limit,),
        )
        return await cursor.fetchall()

    # ── Sync Batches ─────────────────────────────────────────────

    async def create_batch(
        self,
        batch_id: str,
        device_id: str,
        direction: str = "full",
    ) -> None:
        """Record a new sync batch."""
        await self.db.execute(
            """INSERT INTO _sync_batches (id, device_id, direction)
               VALUES (?, ?, ?)""",
            (batch_id, device_id, direction),
        )

    async def complete_batch(
        self,
        batch_id: str,
        changes_sent: int = 0,
        changes_received: int = 0,
        conflicts_resolved: int = 0,
    ) -> None:
        """Mark a sync batch as completed."""
        await self.db.execute(
            """UPDATE _sync_batches
               SET status = 'completed',
                   completed_at = datetime('now'),
                   changes_sent = ?,
                   changes_received = ?,
                   conflicts_resolved = ?
               WHERE id = ?""",
            (changes_sent, changes_received, conflicts_resolved, batch_id),
        )

    async def fail_batch(self, batch_id: str) -> None:
        """Mark a sync batch as failed."""
        await self.db.execute(
            """UPDATE _sync_batches
               SET status = 'failed', completed_at = datetime('now')
               WHERE id = ?""",
            (batch_id,),
        )

    # ── Row-level operations (used by sync service) ──────────────

    async def get_row(self, table_name: str, record_id: int) -> dict | None:
        """Fetch a row from any table by ID."""
        cursor = await self.db.execute(
            f"SELECT * FROM [{table_name}] WHERE id = ?",
            (record_id,),
        )
        return await cursor.fetchone()

    async def get_all_rows(self, table_name: str) -> list[dict]:
        """Fetch all rows from a table (for initial sync)."""
        cursor = await self.db.execute(f"SELECT * FROM [{table_name}]")
        return await cursor.fetchall()

    async def upsert_row(
        self,
        table_name: str,
        record_id: int,
        data: dict[str, Any],
    ) -> None:
        """Insert or replace a row in any table.

        Used when applying device changes to the shop.
        The data dict includes the id column.
        """
        columns = list(data.keys())
        placeholders = ", ".join(["?"] * len(columns))
        col_names = ", ".join(columns)
        update_parts = ", ".join(
            f"{c} = excluded.{c}" for c in columns if c != "id"
        )

        await self.db.execute(
            f"""INSERT INTO [{table_name}] ({col_names})
                VALUES ({placeholders})
                ON CONFLICT(id) DO UPDATE SET {update_parts}""",
            tuple(data[c] for c in columns),
        )

    async def delete_row(self, table_name: str, record_id: int) -> None:
        """Delete a row from any table by ID."""
        await self.db.execute(
            f"DELETE FROM [{table_name}] WHERE id = ?",
            (record_id,),
        )

    async def table_exists(self, table_name: str) -> bool:
        """Check if a table exists in the database."""
        cursor = await self.db.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
            (table_name,),
        )
        return await cursor.fetchone() is not None
