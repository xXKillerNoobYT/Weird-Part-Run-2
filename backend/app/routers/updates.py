"""
Update Protocol routes — shop-centric update pipeline management.

Endpoints:
  POST /api/updates/versions             → Register a new update version
  GET  /api/updates/versions             → List all versions
  GET  /api/updates/versions/{version}   → Get version details
  POST /api/updates/versions/{version}/publish → Publish version to fleet

  POST /api/updates/validations          → Create/reset a validation
  PUT  /api/updates/validations          → Update validation results
  GET  /api/updates/validations          → List validations

  GET  /api/updates/fleet                → List fleet targets (all platforms)
  GET  /api/updates/fleet/{platform}     → Get fleet target for platform
  PUT  /api/updates/fleet/{platform}     → Update fleet target
  POST /api/updates/fleet/{platform}/refresh → Refresh fleet device counts

  POST /api/updates/devices/report       → Device reports its installed version
  GET  /api/updates/devices              → List device update statuses
  GET  /api/updates/devices/{device_id}  → Get device update status
  GET  /api/updates/devices/{device_id}/pending → Get ordered pending updates

  POST /api/updates/backups              → Create a backup snapshot
  GET  /api/updates/backups              → List backup snapshots
  POST /api/updates/backups/{id}/restore → Mark backup as restored
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

import aiosqlite

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse
from app.services.update_protocol_service import UpdateProtocolService

router = APIRouter(prefix="/api/updates", tags=["Updates"])


# ── Request Models ───────────────────────────────────────────────


class RegisterVersionPayload(BaseModel):
    version: str
    previous_version: str | None = None
    release_notes: str | None = None
    checksum_sha256: str | None = None
    signature: str | None = None
    package_url: str | None = None
    package_size_bytes: int | None = None
    migration_scripts: list[str] = Field(default_factory=list)
    rollback_scripts: list[str] = Field(default_factory=list)
    min_compatible_version: str | None = None
    max_compatible_version: str | None = None
    criticality: str = "normal"
    source: str = "github"


class CreateValidationPayload(BaseModel):
    version: str
    platform: str


class UpdateValidationPayload(BaseModel):
    version: str
    platform: str
    status: str
    schema_diff_ok: bool | None = None
    migration_test_ok: bool | None = None
    rollback_test_ok: bool | None = None
    backward_compat_ok: bool | None = None
    error_log: str | None = None


class FleetTargetPayload(BaseModel):
    current_target: str | None = None
    latest_validated: str | None = None
    auto_advance: bool | None = None


class DeviceVersionReportPayload(BaseModel):
    device_id: str
    platform: str
    current_version: str
    install_status: str = "success"
    install_error: str | None = None


class BackupSnapshotPayload(BaseModel):
    version_before: str
    version_target: str
    backup_path: str
    backup_size_bytes: int | None = None
    checksum_sha256: str | None = None
    includes_db: bool = True
    includes_config: bool = True
    includes_binary: bool = True


# ── Version Registry ─────────────────────────────────────────────


@router.post("/versions")
async def register_version(
    payload: RegisterVersionPayload,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Register a new update version from GitHub or manual upload."""
    svc = UpdateProtocolService(db)
    ver = await svc.register_version(
        version=payload.version,
        previous_version=payload.previous_version,
        release_notes=payload.release_notes,
        checksum_sha256=payload.checksum_sha256,
        signature=payload.signature,
        package_url=payload.package_url,
        package_size_bytes=payload.package_size_bytes,
        migration_scripts=payload.migration_scripts,
        rollback_scripts=payload.rollback_scripts,
        min_compatible_version=payload.min_compatible_version,
        max_compatible_version=payload.max_compatible_version,
        criticality=payload.criticality,
        source=payload.source,
    )
    return ApiResponse(data=ver, message=f"Version {payload.version} registered")


@router.get("/versions")
async def list_versions(
    published_only: bool = Query(False),
    limit: int = Query(50, ge=1, le=200),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all known versions."""
    svc = UpdateProtocolService(db)
    versions = await svc.list_versions(published_only=published_only, limit=limit)
    return ApiResponse(data=versions, message=f"{len(versions)} versions")


@router.get("/versions/{version}")
async def get_version(
    version: str,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get details for a specific version."""
    svc = UpdateProtocolService(db)
    ver = await svc.get_version(version)
    if not ver:
        return ApiResponse(data=None, message="Version not found")
    return ApiResponse(data=ver)


@router.post("/versions/{version}/publish")
async def publish_version(
    version: str,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Mark a version as published to the fleet."""
    svc = UpdateProtocolService(db)
    ver = await svc.publish_version(version)
    if not ver:
        return ApiResponse(data=None, message="Version not found")
    return ApiResponse(data=ver, message=f"Version {version} published")


# ── Validations ──────────────────────────────────────────────────


@router.post("/validations")
async def create_validation(
    payload: CreateValidationPayload,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create or reset a validation for a version+platform."""
    svc = UpdateProtocolService(db)
    val = await svc.create_validation(
        version=payload.version,
        platform=payload.platform,
        validated_by=user.get("id"),
    )
    return ApiResponse(data=val, message="Validation created")


@router.put("/validations")
async def update_validation(
    payload: UpdateValidationPayload,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a validation record with sandbox test results."""
    svc = UpdateProtocolService(db)
    val = await svc.update_validation(
        version=payload.version,
        platform=payload.platform,
        status=payload.status,
        schema_diff_ok=payload.schema_diff_ok,
        migration_test_ok=payload.migration_test_ok,
        rollback_test_ok=payload.rollback_test_ok,
        backward_compat_ok=payload.backward_compat_ok,
        error_log=payload.error_log,
    )
    if not val:
        return ApiResponse(data=None, message="Validation not found")
    return ApiResponse(data=val, message=f"Validation updated: {payload.status}")


@router.get("/validations")
async def list_validations(
    version: str | None = Query(None),
    platform: str | None = Query(None),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List validation records."""
    svc = UpdateProtocolService(db)
    vals = await svc.list_validations(version=version, platform=platform)
    return ApiResponse(data=vals, message=f"{len(vals)} validations")


# ── Fleet Targets ────────────────────────────────────────────────


@router.get("/fleet")
async def list_fleet_targets(
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List fleet targets for all platforms."""
    svc = UpdateProtocolService(db)
    targets = await svc.list_fleet_targets()
    return ApiResponse(data=targets, message=f"{len(targets)} fleet targets")


@router.get("/fleet/{platform}")
async def get_fleet_target(
    platform: str,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get fleet target for a specific platform."""
    svc = UpdateProtocolService(db)
    target = await svc.get_fleet_target(platform)
    if not target:
        return ApiResponse(data=None, message="No fleet target for this platform")
    return ApiResponse(data=target)


@router.put("/fleet/{platform}")
async def update_fleet_target(
    platform: str,
    payload: FleetTargetPayload,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update fleet target for a platform."""
    svc = UpdateProtocolService(db)
    target = await svc.upsert_fleet_target(
        platform=platform,
        current_target=payload.current_target,
        latest_validated=payload.latest_validated,
        auto_advance=payload.auto_advance,
        updated_by=user.get("id"),
    )
    return ApiResponse(data=target, message=f"Fleet target for {platform} updated")


@router.post("/fleet/{platform}/refresh")
async def refresh_fleet_counts(
    platform: str,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Recalculate device counts and trigger auto-advance if ready."""
    svc = UpdateProtocolService(db)
    target = await svc.refresh_fleet_counts(platform)
    if not target:
        return ApiResponse(data=None, message="No fleet target for this platform")
    return ApiResponse(data=target, message="Fleet counts refreshed")


# ── Device Update Status ─────────────────────────────────────────


@router.post("/devices/report")
async def device_version_report(
    payload: DeviceVersionReportPayload,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Device reports its currently installed version."""
    svc = UpdateProtocolService(db)
    status = await svc.report_device_version(
        device_id=payload.device_id,
        platform=payload.platform,
        current_version=payload.current_version,
        install_status=payload.install_status,
        install_error=payload.install_error,
    )
    return ApiResponse(data=status, message="Version reported")


@router.get("/devices")
async def list_device_update_statuses(
    platform: str | None = Query(None),
    behind_only: bool = Query(False),
    limit: int = Query(100, ge=1, le=500),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List device update statuses (admin)."""
    svc = UpdateProtocolService(db)
    devices = await svc.list_device_update_statuses(
        platform=platform, behind_only=behind_only, limit=limit,
    )
    return ApiResponse(data=devices, message=f"{len(devices)} device statuses")


@router.get("/devices/{device_id}")
async def get_device_update_status(
    device_id: str,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get update status for a specific device."""
    svc = UpdateProtocolService(db)
    status = await svc.get_device_update_status(device_id)
    if not status:
        return ApiResponse(data=None, message="Device not found")
    return ApiResponse(data=status)


@router.get("/devices/{device_id}/pending")
async def get_pending_updates(
    device_id: str,
    platform: str = Query(...),
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get the ordered list of updates a device should install next.

    Follows the strict version chain from current → fleet target.
    """
    svc = UpdateProtocolService(db)
    updates = await svc.get_pending_updates(device_id, platform)
    return ApiResponse(data=updates, message=f"{len(updates)} pending updates")


# ── Backup Snapshots ─────────────────────────────────────────────


@router.post("/backups")
async def create_backup(
    payload: BackupSnapshotPayload,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Record a pre-update backup snapshot."""
    svc = UpdateProtocolService(db)
    snap = await svc.create_backup_snapshot(
        version_before=payload.version_before,
        version_target=payload.version_target,
        backup_path=payload.backup_path,
        backup_size_bytes=payload.backup_size_bytes,
        checksum_sha256=payload.checksum_sha256,
        includes_db=payload.includes_db,
        includes_config=payload.includes_config,
        includes_binary=payload.includes_binary,
        created_by=user.get("id"),
    )
    return ApiResponse(data=snap, message="Backup snapshot created")


@router.get("/backups")
async def list_backups(
    version_before: str | None = Query(None),
    limit: int = Query(50, ge=1, le=200),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List backup snapshots."""
    svc = UpdateProtocolService(db)
    snaps = await svc.list_backup_snapshots(
        version_before=version_before, limit=limit,
    )
    return ApiResponse(data=snaps, message=f"{len(snaps)} backup snapshots")


@router.post("/backups/{snapshot_id}/restore")
async def mark_backup_restored(
    snapshot_id: int,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Mark a backup as restored (used during rollback)."""
    svc = UpdateProtocolService(db)
    snap = await svc.mark_backup_restored(snapshot_id)
    if not snap:
        return ApiResponse(data=None, message="Backup not found")
    return ApiResponse(data=snap, message="Backup marked as restored")
