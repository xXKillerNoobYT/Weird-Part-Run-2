"""
Pydantic models for the sync engine.

Defines request/response shapes for device ↔ shop synchronisation.
Devices push their _change_log entries to the shop, and the shop responds
with its own changes since the device's last sync timestamp.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field


# ── Change log entry (shared shape for both device and shop) ──────

class ChangeLogEntry(BaseModel):
    """One row from a device's _change_log table."""
    id: int | None = None
    table_name: str
    record_id: int
    operation: str  # INSERT, UPDATE, DELETE
    changed_fields: str | None = None  # JSON string of {col: new_value}
    old_values: str | None = None      # JSON string of {col: old_value}
    timestamp: str


# ── Push request (device → shop) ─────────────────────────────────

class SyncPushPayload(BaseModel):
    """Payload sent by a device when pushing local changes to the shop."""
    device_id: str
    device_name: str | None = None
    platform: str | None = None        # 'ios', 'android', 'web'
    last_sync_at: str | None = None    # ISO timestamp of device's last successful sync
    changes: list[ChangeLogEntry] = Field(default_factory=list)


class ConflictRecord(BaseModel):
    """Describes a conflict that occurred during sync push."""
    table_name: str
    record_id: int
    resolution: str            # 'device_wins', 'shop_wins'
    device_values: dict[str, Any] | None = None
    shop_values: dict[str, Any] | None = None
    resolved_values: dict[str, Any] | None = None


class ShopChange(BaseModel):
    """One change the shop is sending back to the device."""
    table_name: str
    record_id: int
    operation: str             # INSERT, UPDATE, DELETE
    row_data: dict[str, Any] | None = None   # Full row for INSERT/UPDATE
    changed_fields: str | None = None
    timestamp: str


class SyncPushResponse(BaseModel):
    """Response the shop sends after processing a device push."""
    applied: int = 0
    conflicts: list[ConflictRecord] = Field(default_factory=list)
    shop_changes: list[ShopChange] = Field(default_factory=list)
    sync_batch_id: str
    server_time: str


# ── Acknowledge request (device → shop) ──────────────────────────

class SyncAckPayload(BaseModel):
    """Device confirms it successfully applied the shop's changes."""
    device_id: str
    sync_batch_id: str


# ── Initial sync (full download) ────────────────────────────────

class InitialSyncRequest(BaseModel):
    """Request for a full database download (first sync for a new device)."""
    device_id: str
    device_name: str | None = None
    platform: str | None = None


class TableDump(BaseModel):
    """All rows from a single table, for initial sync."""
    table_name: str
    rows: list[dict[str, Any]] = Field(default_factory=list)


class InitialSyncResponse(BaseModel):
    """Full database download for a new device."""
    tables: list[TableDump] = Field(default_factory=list)
    sync_batch_id: str
    server_time: str


# ── Device status ────────────────────────────────────────────────

class DeviceStatus(BaseModel):
    """Current sync state of a registered device."""
    device_id: str
    device_name: str | None = None
    platform: str | None = None
    user_id: int | None = None
    last_sync_at: str | None = None
    last_sync_batch_id: str | None = None
    pending_changes: int = 0
    registered_at: str | None = None
