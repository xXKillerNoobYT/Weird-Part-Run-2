"""
Sync routes — device ↔ shop data synchronization over LAN.

Endpoints:
  POST /api/sync/push       → Device sends local changes to shop
  POST /api/sync/ack        → Device confirms it applied shop changes
  GET  /api/sync/pull       → Device pulls changes since last sync
  POST /api/sync/initial    → Device requests full initial data load
  POST /api/sync/register   → Register a device for sync
  GET  /api/sync/status/:id → Get a device's sync status
  GET  /api/sync/devices    → List all registered sync devices (admin)
  GET  /api/sync/history    → Sync batch history (admin)
  GET  /api/sync/conflicts  → Conflict log (admin)
"""

from __future__ import annotations

from datetime import datetime

import aiosqlite
from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse
from app.services.sync_service import SyncService

router = APIRouter(prefix="/api/sync", tags=["Sync"])


# ── Request / Response Models ────────────────────────────────────


class SyncPushPayload(BaseModel):
    """Device sends its local changes to the shop."""
    device_id: str
    last_sync_at: str = ""
    changes: list[dict] = Field(default_factory=list)


class SyncAckPayload(BaseModel):
    """Device confirms it applied the shop's changes."""
    device_id: str
    sync_batch_id: str


class DeviceRegisterPayload(BaseModel):
    """Register a device for sync."""
    device_id: str
    device_name: str = "Unknown Device"
    platform: str = "unknown"


class InitialSyncRequest(BaseModel):
    """Request full data for initial device setup."""
    device_id: str
    tables: list[str] | None = None


# ── Endpoints ────────────────────────────────────────────────────


@router.post("/push")
async def sync_push(
    payload: SyncPushPayload,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Receive changes from a device, resolve conflicts, return shop changes.

    This is the primary sync endpoint. The device sends its pending
    changes, and the shop returns:
    - How many changes were applied
    - Any conflicts and their resolutions
    - Shop changes the device hasn't seen yet
    - A batch ID for acknowledgment
    """
    svc = SyncService(db)

    # Create a sync batch
    batch_id = await svc.create_batch(payload.device_id, "push")

    # Apply device changes
    applied, conflicts = await svc.apply_device_changes(
        payload.device_id, payload.changes,
    )

    # Get shop changes since device's last sync
    shop_changes = await svc.get_changes_since(
        payload.last_sync_at or "1970-01-01",
        exclude_device=payload.device_id,
    )

    # Update batch stats
    await svc.update_batch(
        batch_id,
        sent=len(shop_changes),
        received=len(applied),
        conflicts=len(conflicts),
    )

    return ApiResponse(
        data={
            "applied": len(applied),
            "conflicts": conflicts,
            "shop_changes": shop_changes,
            "sync_batch_id": batch_id,
            "server_time": datetime.utcnow().isoformat(),
        },
        message=f"Sync: {len(applied)} applied, {len(conflicts)} conflicts, {len(shop_changes)} to pull",
    )


@router.post("/ack")
async def sync_ack(
    payload: SyncAckPayload,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Device confirms it applied the shop's changes."""
    svc = SyncService(db)
    await svc.mark_device_synced(payload.device_id, payload.sync_batch_id)
    return ApiResponse(message="Sync acknowledged")


@router.get("/pull")
async def sync_pull(
    device_id: str = Query(...),
    since: str = Query("1970-01-01"),
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Pull shop changes since a timestamp. Lighter than full push flow."""
    svc = SyncService(db)
    changes = await svc.get_changes_since(since, exclude_device=device_id)
    return ApiResponse(
        data={
            "changes": changes,
            "server_time": datetime.utcnow().isoformat(),
        },
        message=f"{len(changes)} changes since {since}",
    )


@router.post("/initial")
async def initial_sync(
    payload: InitialSyncRequest,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Full data load for initial device setup.

    Returns all rows from synced tables. Used when a device first
    connects and needs to populate its local DB from scratch.
    """
    svc = SyncService(db)

    # Register the device
    await svc.register_device(
        payload.device_id, "Initial Sync", "unknown", user.get("id"),
    )

    data = await svc.get_initial_sync_data(payload.tables)

    total_rows = sum(len(rows) for rows in data.values())
    return ApiResponse(
        data={
            "tables": data,
            "server_time": datetime.utcnow().isoformat(),
        },
        message=f"Initial sync: {total_rows} rows across {len(data)} tables",
    )


@router.post("/register")
async def register_device(
    payload: DeviceRegisterPayload,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Register or update a device in the sync registry."""
    svc = SyncService(db)
    device = await svc.register_device(
        payload.device_id, payload.device_name, payload.platform, user.get("id"),
    )
    return ApiResponse(data=device, message="Device registered for sync")


@router.get("/status/{device_id}")
async def get_device_sync_status(
    device_id: str,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a device's sync status."""
    svc = SyncService(db)
    status = await svc.get_device_status(device_id)
    if not status:
        return ApiResponse(data=None, message="Device not registered")
    return ApiResponse(data=status)


@router.get("/devices")
async def list_sync_devices(
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all registered sync devices (admin)."""
    svc = SyncService(db)
    devices = await svc.list_devices()
    return ApiResponse(data=devices, message=f"{len(devices)} devices")


@router.get("/history")
async def sync_history(
    device_id: str | None = Query(None),
    limit: int = Query(50, ge=1, le=200),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Sync batch history for admin review."""
    svc = SyncService(db)
    history = await svc.get_sync_history(device_id=device_id, limit=limit)
    return ApiResponse(data=history, message=f"{len(history)} sync batches")


@router.get("/conflicts")
async def conflict_log(
    limit: int = Query(50, ge=1, le=200),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Conflict log for admin review."""
    svc = SyncService(db)
    conflicts = await svc.get_conflict_log(limit=limit)
    return ApiResponse(data=conflicts, message=f"{len(conflicts)} conflicts")
