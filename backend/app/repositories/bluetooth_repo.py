"""
Bluetooth repository — Database access for BT pairing and connection logs.

Manages bt_paired_devices and bt_connection_log tables.
Does NOT inherit from BaseRepo because these tables are local
infrastructure (not synced between devices).
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

import aiosqlite

logger = logging.getLogger(__name__)


class BluetoothRepo:
    """Direct DB access for Bluetooth pairing and connection tracking."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    # ── Helpers ───────────────────────────────────────────────────

    def _now_iso(self) -> str:
        return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

    def _row_to_dict(self, row: aiosqlite.Row) -> dict[str, Any]:
        return dict(row)

    # ── Paired Devices ────────────────────────────────────────────

    async def list_paired_devices(
        self, *, active_only: bool = True
    ) -> list[dict[str, Any]]:
        """Return all (or just active) paired BT devices."""
        sql = "SELECT * FROM bt_paired_devices"
        if active_only:
            sql += " WHERE is_active = 1"
        sql += " ORDER BY paired_at DESC"
        async with self.db.execute(sql) as cur:
            rows = await cur.fetchall()
            return [self._row_to_dict(r) for r in rows]

    async def get_paired_device(self, device_id: int) -> dict[str, Any] | None:
        """Get a single paired device by ID."""
        sql = "SELECT * FROM bt_paired_devices WHERE id = ?"
        async with self.db.execute(sql, (device_id,)) as cur:
            row = await cur.fetchone()
            return self._row_to_dict(row) if row else None

    async def get_paired_device_by_address(
        self, bt_address: str
    ) -> dict[str, Any] | None:
        """Get the active paired device for a given BT address."""
        sql = """
            SELECT * FROM bt_paired_devices
            WHERE bt_address = ? AND is_active = 1
        """
        async with self.db.execute(sql, (bt_address,)) as cur:
            row = await cur.fetchone()
            return self._row_to_dict(row) if row else None

    async def create_paired_device(
        self,
        bt_address: str,
        display_name: str,
        role: str = "secondary",
        pairing_code: str | None = None,
        device_id: str | None = None,
    ) -> dict[str, Any]:
        """Insert a new paired device record.

        Deactivates any existing active pairing for the same address
        before inserting (one active pair per address).
        """
        now = self._now_iso()

        # Deactivate stale active pairing if any
        await self.db.execute(
            "UPDATE bt_paired_devices SET is_active = 0, updated_at = ? "
            "WHERE bt_address = ? AND is_active = 1",
            (now, bt_address),
        )

        sql = """
            INSERT INTO bt_paired_devices
                (device_id, bt_address, display_name, role, pairing_code,
                 is_active, paired_at, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?)
        """
        async with self.db.execute(
            sql,
            (device_id, bt_address, display_name, role, pairing_code,
             now, now, now),
        ) as cur:
            new_id = cur.lastrowid

        await self.db.commit()
        return (await self.get_paired_device(new_id)) or {"id": new_id}

    async def update_paired_device(
        self, device_id: int, **fields: Any
    ) -> dict[str, Any] | None:
        """Update fields on a paired device record."""
        if not fields:
            return await self.get_paired_device(device_id)

        fields["updated_at"] = self._now_iso()
        set_clause = ", ".join(f"{k} = ?" for k in fields)
        values = [*fields.values(), device_id]

        await self.db.execute(
            f"UPDATE bt_paired_devices SET {set_clause} WHERE id = ?",
            values,
        )
        await self.db.commit()
        return await self.get_paired_device(device_id)

    async def deactivate_paired_device(self, device_id: int) -> bool:
        """Mark a paired device as inactive (soft-unpair)."""
        now = self._now_iso()
        cur = await self.db.execute(
            "UPDATE bt_paired_devices SET is_active = 0, updated_at = ? "
            "WHERE id = ? AND is_active = 1",
            (now, device_id),
        )
        await self.db.commit()
        return cur.rowcount > 0

    async def touch_connected(self, device_id: int) -> None:
        """Update last_connected_at timestamp on a paired device."""
        now = self._now_iso()
        await self.db.execute(
            "UPDATE bt_paired_devices SET last_connected_at = ?, updated_at = ? "
            "WHERE id = ?",
            (now, now, device_id),
        )
        await self.db.commit()

    async def touch_synced(self, device_id: int) -> None:
        """Update last_sync_at timestamp on a paired device."""
        now = self._now_iso()
        await self.db.execute(
            "UPDATE bt_paired_devices SET last_sync_at = ?, updated_at = ? "
            "WHERE id = ?",
            (now, now, device_id),
        )
        await self.db.commit()

    # ── Connection Log ────────────────────────────────────────────

    async def log_connection_start(
        self,
        remote_bt_address: str,
        local_device_id: str | None = None,
        remote_device_id: str | None = None,
    ) -> int:
        """Create a new connection log entry and return its ID."""
        now = self._now_iso()
        sql = """
            INSERT INTO bt_connection_log
                (local_device_id, remote_device_id, remote_bt_address,
                 connected_at, created_at)
            VALUES (?, ?, ?, ?, ?)
        """
        async with self.db.execute(
            sql, (local_device_id, remote_device_id, remote_bt_address, now, now)
        ) as cur:
            log_id = cur.lastrowid

        await self.db.commit()
        return log_id or 0

    async def log_connection_end(
        self,
        log_id: int,
        *,
        bytes_sent: int = 0,
        bytes_received: int = 0,
        requests_forwarded: int = 0,
        changes_synced: int = 0,
        disconnect_reason: str = "clean",
        error_message: str | None = None,
    ) -> None:
        """Finalize a connection log entry with disconnect stats."""
        now = self._now_iso()
        sql = """
            UPDATE bt_connection_log
            SET disconnected_at = ?,
                duration_seconds = (julianday(?) - julianday(connected_at)) * 86400,
                bytes_sent = ?,
                bytes_received = ?,
                requests_forwarded = ?,
                changes_synced = ?,
                disconnect_reason = ?,
                error_message = ?
            WHERE id = ?
        """
        await self.db.execute(
            sql,
            (now, now, bytes_sent, bytes_received, requests_forwarded,
             changes_synced, disconnect_reason, error_message, log_id),
        )
        await self.db.commit()

    async def get_connection_log(
        self,
        *,
        limit: int = 50,
        offset: int = 0,
        bt_address: str | None = None,
    ) -> list[dict[str, Any]]:
        """Return recent connection log entries."""
        sql = "SELECT * FROM bt_connection_log"
        params: list[Any] = []

        if bt_address:
            sql += " WHERE remote_bt_address = ?"
            params.append(bt_address)

        sql += " ORDER BY connected_at DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])

        async with self.db.execute(sql, params) as cur:
            rows = await cur.fetchall()
            return [self._row_to_dict(r) for r in rows]

    async def get_connection_log_count(
        self, *, bt_address: str | None = None
    ) -> int:
        """Count total connection log entries (for pagination)."""
        sql = "SELECT COUNT(*) FROM bt_connection_log"
        params: list[Any] = []

        if bt_address:
            sql += " WHERE remote_bt_address = ?"
            params.append(bt_address)

        async with self.db.execute(sql, params) as cur:
            row = await cur.fetchone()
            return row[0] if row else 0

    # ── Settings ──────────────────────────────────────────────────

    async def get_bt_settings(self) -> dict[str, str]:
        """Read all Bluetooth settings from the settings table."""
        sql = "SELECT key, value FROM settings WHERE category = 'bluetooth'"
        async with self.db.execute(sql) as cur:
            rows = await cur.fetchall()
            return {r["key"]: r["value"] for r in rows}

    async def update_bt_setting(self, key: str, value: str) -> None:
        """Update a single Bluetooth setting."""
        now = self._now_iso()
        await self.db.execute(
            "UPDATE settings SET value = ?, updated_at = ? "
            "WHERE key = ? AND category = 'bluetooth'",
            (value, now, key),
        )
        await self.db.commit()

    async def update_bt_settings(self, settings_dict: dict[str, str]) -> None:
        """Bulk-update Bluetooth settings."""
        now = self._now_iso()
        for key, value in settings_dict.items():
            await self.db.execute(
                "UPDATE settings SET value = ?, updated_at = ? "
                "WHERE key = ? AND category = 'bluetooth'",
                (value, now, key),
            )
        await self.db.commit()
