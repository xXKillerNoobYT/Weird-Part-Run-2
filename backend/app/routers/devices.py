"""
Devices Router — Admin endpoints for device management, health, errors,
overrides, media tracking, and shop cluster management.

Prefix: /api/devices
Requires: manage_devices permission (except device self-report endpoints)
"""

from __future__ import annotations

from typing import Optional

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.services.device_management_service import DeviceManagementService

router = APIRouter(prefix="/api/devices", tags=["Devices"])


# ── Pydantic Models ─────────────────────────────────────────────────

class RenamePayload(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)


class PrimaryUserPayload(BaseModel):
    user_id: int


class OverridePayload(BaseModel):
    action: str = Field(..., pattern="^(force_logout|force_wipe|force_sync)$")
    reason: Optional[str] = None


class DisablePayload(BaseModel):
    reason: str = Field(..., min_length=1, max_length=500)


class ResolveErrorPayload(BaseModel):
    note: Optional[str] = None


class ErrorUploadItem(BaseModel):
    severity: str = "error"
    error_type: str = "unknown"
    message: str = ""
    stack_trace: Optional[str] = None
    context_json: Optional[str] = None
    environment_json: Optional[str] = None
    occurred_at: Optional[str] = None


class ErrorUploadPayload(BaseModel):
    errors: list[ErrorUploadItem]


class HealthSnapshotPayload(BaseModel):
    battery_level: Optional[int] = None
    battery_charging: Optional[bool] = None
    storage_used_mb: Optional[float] = None
    storage_total_mb: Optional[float] = None
    app_version: Optional[str] = None
    os_version: Optional[str] = None
    pending_sync_count: int = 0
    pending_media_count: int = 0
    last_sync_at: Optional[str] = None
    memory_used_mb: Optional[float] = None


class BtEncounterPayload(BaseModel):
    local_device_id: str
    remote_device_id: str
    encounter_start: str
    encounter_end: Optional[str] = None
    changes_sent: int = 0
    changes_received: int = 0
    media_bytes_sent: int = 0
    media_bytes_received: int = 0
    signal_strength: Optional[int] = None
    status: str = "completed"
    failure_reason: Optional[str] = None


class MediaRegisterPayload(BaseModel):
    media_path: str
    media_hash: str
    origin_device_id: str
    media_size_bytes: int = 0


class MediaConfirmPayload(BaseModel):
    media_hashes: list[str]


class ClusterNodePayload(BaseModel):
    node_id: Optional[str] = None
    hostname: Optional[str] = None
    local_ip: Optional[str] = None
    port: int = 8000
    app_version: Optional[str] = None
    db_version: Optional[int] = None


class RetentionUpdatePayload(BaseModel):
    device_retention_days: int = Field(..., ge=1, le=3650)
    shop_retention_days: int = Field(..., ge=1, le=3650)


class OverrideCheckPayload(BaseModel):
    device_id: str


# ── Helpers ──────────────────────────────────────────────────────────

def _svc(db: aiosqlite.Connection) -> DeviceManagementService:
    return DeviceManagementService(db)


# ── Device List & Detail ─────────────────────────────────────────────

@router.get("")
async def list_devices(
    include_disabled: bool = True,
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_permission("manage_devices")),
):
    """List all registered devices with health summaries."""
    svc = _svc(db)
    return await svc.list_devices(include_disabled=include_disabled)


@router.get("/{device_id}")
async def get_device(
    device_id: str,
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_permission("manage_devices")),
):
    """Get full detail for a single device."""
    svc = _svc(db)
    device = await svc.get_device(device_id)
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")
    return device


@router.put("/{device_id}/rename")
async def rename_device(
    device_id: str,
    payload: RenamePayload,
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_permission("manage_devices")),
):
    """Rename a device."""
    svc = _svc(db)
    ok = await svc.rename_device(device_id, payload.name)
    if not ok:
        raise HTTPException(status_code=404, detail="Device not found")
    return {"ok": True}


# ── Primary User ─────────────────────────────────────────────────────

@router.put("/{device_id}/primary-user")
async def set_primary_user(
    device_id: str,
    payload: PrimaryUserPayload,
    db: aiosqlite.Connection = Depends(get_db),
    user=Depends(require_permission("manage_devices")),
):
    """Reassign the primary user of a device."""
    svc = _svc(db)
    await svc.set_primary_user(device_id, payload.user_id, actor_id=user["id"])
    return {"ok": True}


# ── Override Actions ─────────────────────────────────────────────────

@router.post("/{device_id}/override")
async def set_override(
    device_id: str,
    payload: OverridePayload,
    db: aiosqlite.Connection = Depends(get_db),
    user=Depends(require_permission("manage_devices")),
):
    """Set an override flag on a device (force_logout, force_wipe, force_sync)."""
    svc = _svc(db)
    await svc.set_override(device_id, payload.action, actor_id=user["id"],
                           reason=payload.reason)
    return {"ok": True}


@router.delete("/{device_id}/override")
async def clear_override(
    device_id: str,
    db: aiosqlite.Connection = Depends(get_db),
    user=Depends(require_permission("manage_devices")),
):
    """Clear any pending override on a device."""
    svc = _svc(db)
    await svc.clear_override(device_id, actor_id=user["id"])
    return {"ok": True}


@router.get("/{device_id}/override")
async def check_override(
    device_id: str,
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_user),
):
    """Check if a device has a pending override. Used by device itself on sync."""
    svc = _svc(db)
    override = await svc.check_override(device_id)
    return {"override": override}


@router.post("/{device_id}/override/consume")
async def consume_override(
    device_id: str,
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_user),
):
    """Device consumes (acknowledges) a pending override. Returns the action."""
    svc = _svc(db)
    action = await svc.consume_override(device_id)
    return {"action": action}


@router.post("/{device_id}/disable")
async def disable_device(
    device_id: str,
    payload: DisablePayload,
    db: aiosqlite.Connection = Depends(get_db),
    user=Depends(require_permission("manage_devices")),
):
    """Disable a device (lost/stolen). Blocks sync and forces logout."""
    svc = _svc(db)
    await svc.disable_device(device_id, payload.reason, actor_id=user["id"])
    return {"ok": True}


@router.post("/{device_id}/enable")
async def enable_device(
    device_id: str,
    db: aiosqlite.Connection = Depends(get_db),
    user=Depends(require_permission("manage_devices")),
):
    """Re-enable a previously disabled device."""
    svc = _svc(db)
    await svc.enable_device(device_id, actor_id=user["id"])
    return {"ok": True}


@router.post("/{device_id}/force-wipe")
async def force_wipe(
    device_id: str,
    db: aiosqlite.Connection = Depends(get_db),
    user=Depends(require_permission("manage_devices")),
):
    """Flag a device for a full wipe on next check-in."""
    svc = _svc(db)
    await svc.force_wipe(device_id, actor_id=user["id"])
    return {"ok": True}


@router.post("/{device_id}/force-sync")
async def force_sync(
    device_id: str,
    db: aiosqlite.Connection = Depends(get_db),
    user=Depends(require_permission("manage_devices")),
):
    """Flag a device to sync immediately on next check-in."""
    svc = _svc(db)
    await svc.force_sync(device_id, actor_id=user["id"])
    return {"ok": True}


@router.post("/{device_id}/push-config")
async def push_config(
    device_id: str,
    db: aiosqlite.Connection = Depends(get_db),
    user=Depends(require_permission("manage_devices")),
):
    """Increment config version to force device config refresh."""
    svc = _svc(db)
    await svc.push_config(device_id, actor_id=user["id"])
    return {"ok": True}


# ── Error Logs ───────────────────────────────────────────────────────

@router.get("/errors/all")
async def list_all_errors(
    device_id: Optional[str] = None,
    severity: Optional[str] = None,
    unresolved_only: bool = False,
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_permission("manage_devices")),
):
    """List error logs across all devices with filtering."""
    svc = _svc(db)
    return await svc.list_errors(
        device_id=device_id, severity=severity,
        unresolved_only=unresolved_only, limit=limit, offset=offset,
    )


@router.get("/{device_id}/errors")
async def list_device_errors(
    device_id: str,
    severity: Optional[str] = None,
    unresolved_only: bool = False,
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_permission("manage_devices")),
):
    """List error logs for a specific device."""
    svc = _svc(db)
    return await svc.list_errors(
        device_id=device_id, severity=severity,
        unresolved_only=unresolved_only, limit=limit, offset=offset,
    )


@router.post("/{device_id}/errors")
async def upload_errors(
    device_id: str,
    payload: ErrorUploadPayload,
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_user),
):
    """Device uploads its error logs (auto-upload on sync)."""
    svc = _svc(db)
    count = await svc.upload_errors(device_id, [e.model_dump() for e in payload.errors])
    return {"uploaded": count}


@router.post("/errors/{error_id}/resolve")
async def resolve_error(
    error_id: int,
    payload: ResolveErrorPayload,
    db: aiosqlite.Connection = Depends(get_db),
    user=Depends(require_permission("manage_devices")),
):
    """Resolve a specific error log entry."""
    svc = _svc(db)
    ok = await svc.resolve_error(error_id, actor_id=user["id"], note=payload.note)
    if not ok:
        raise HTTPException(status_code=404, detail="Error not found or already resolved")
    return {"ok": True}


@router.post("/{device_id}/errors/resolve-all")
async def resolve_all_errors(
    device_id: str,
    db: aiosqlite.Connection = Depends(get_db),
    user=Depends(require_permission("manage_devices")),
):
    """Resolve all unresolved errors for a device."""
    svc = _svc(db)
    count = await svc.resolve_all_for_device(device_id, actor_id=user["id"])
    return {"resolved": count}


# ── Health Telemetry ─────────────────────────────────────────────────

@router.post("/{device_id}/health")
async def upload_health(
    device_id: str,
    payload: HealthSnapshotPayload,
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_user),
):
    """Device uploads a health telemetry snapshot."""
    svc = _svc(db)
    snap_id = await svc.upload_health(device_id, payload.model_dump())
    return {"id": snap_id}


@router.get("/{device_id}/health")
async def get_health_history(
    device_id: str,
    hours: int = Query(48, ge=1, le=720),
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_permission("manage_devices")),
):
    """Get health snapshot history for a device."""
    svc = _svc(db)
    return await svc.get_health_history(device_id, hours=hours)


@router.get("/{device_id}/health/latest")
async def get_latest_health(
    device_id: str,
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_permission("manage_devices")),
):
    """Get the most recent health snapshot."""
    svc = _svc(db)
    health = await svc.get_latest_health(device_id)
    if not health:
        raise HTTPException(status_code=404, detail="No health data")
    return health


# ── Storage Info ─────────────────────────────────────────────────────

@router.get("/{device_id}/storage")
async def get_storage(
    device_id: str,
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_permission("manage_devices")),
):
    """Get storage configuration and usage for a device."""
    svc = _svc(db)
    return await svc.get_device_storage(device_id)


# ── BT Encounters ───────────────────────────────────────────────────

@router.get("/bt/encounters")
async def list_bt_encounters(
    device_id: Optional[str] = None,
    limit: int = Query(50, ge=1, le=500),
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_permission("manage_devices")),
):
    """List Bluetooth encounter log."""
    svc = _svc(db)
    return await svc.list_bt_encounters(device_id=device_id, limit=limit)


@router.post("/bt/encounters")
async def log_bt_encounter(
    payload: BtEncounterPayload,
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_user),
):
    """Device logs a BT encounter after sync."""
    svc = _svc(db)
    enc_id = await svc.log_bt_encounter(payload.model_dump())
    return {"id": enc_id}


# ── Media Delivery Tracking ─────────────────────────────────────────

@router.post("/media/register")
async def register_media(
    payload: MediaRegisterPayload,
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_user),
):
    """Register a media file for delivery tracking."""
    svc = _svc(db)
    mid = await svc.register_media(payload.model_dump())
    return {"id": mid}


@router.post("/media/confirm")
async def confirm_media(
    payload: MediaConfirmPayload,
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_permission("manage_devices")),
):
    """Confirm media hashes have arrived at shop."""
    svc = _svc(db)
    count = await svc.confirm_media_delivery(payload.media_hashes)
    return {"confirmed": count}


@router.get("/{device_id}/media/pending")
async def get_pending_media(
    device_id: str,
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_user),
):
    """List pending (undelivered) media for a device."""
    svc = _svc(db)
    return await svc.get_pending_media(device_id)


# ── Shop Cluster ─────────────────────────────────────────────────────

@router.get("/cluster/nodes")
async def list_cluster_nodes(
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_permission("manage_devices")),
):
    """List all shop cluster nodes."""
    svc = _svc(db)
    return await svc.list_cluster_nodes()


@router.post("/cluster/register")
async def register_cluster_node(
    payload: ClusterNodePayload,
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_permission("manage_devices")),
):
    """Register or update a cluster node."""
    svc = _svc(db)
    node_id = await svc.register_cluster_node(payload.model_dump())
    return {"node_id": node_id}


@router.post("/cluster/{node_id}/primary")
async def set_cluster_primary(
    node_id: str,
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_permission("manage_devices")),
):
    """Designate a node as primary shop PC."""
    svc = _svc(db)
    ok = await svc.set_cluster_primary(node_id)
    if not ok:
        raise HTTPException(status_code=404, detail="Node not found")
    return {"ok": True}


@router.post("/cluster/{node_id}/sync")
async def mark_cluster_sync(
    node_id: str,
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_user),
):
    """Record that a cluster node just completed sync."""
    svc = _svc(db)
    await svc.mark_cluster_sync(node_id)
    return {"ok": True}


# ── Log Retention ────────────────────────────────────────────────────

@router.get("/admin/retention")
async def get_retention_config(
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_permission("manage_devices")),
):
    """Get log retention configuration."""
    svc = _svc(db)
    return await svc.get_retention_config()


@router.put("/admin/retention/{log_type}")
async def update_retention(
    log_type: str,
    payload: RetentionUpdatePayload,
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_permission("manage_devices")),
):
    """Update retention policy for a log type."""
    svc = _svc(db)
    ok = await svc.update_retention(log_type, payload.device_retention_days,
                                     payload.shop_retention_days)
    if not ok:
        raise HTTPException(status_code=404, detail="Log type not found")
    return {"ok": True}


@router.post("/admin/retention/run")
async def run_retention_cleanup(
    db: aiosqlite.Connection = Depends(get_db),
    _user=Depends(require_permission("manage_devices")),
):
    """Manually trigger log retention cleanup."""
    svc = _svc(db)
    results = await svc.run_log_retention()
    return {"purged": results}
