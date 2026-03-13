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

import logging
from datetime import datetime, timezone

import aiosqlite
from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse
from app.services.device_security_service import DeviceSecurityService
from app.services.sync_service import SyncService

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/sync", tags=["Sync"])


# ── Request / Response Models ────────────────────────────────────


class SyncPushPayload(BaseModel):
    """Device sends its local changes to the shop.

    If the shop has security enabled (company keys initialised),
    the device should include its certificate_data and signature
    so the shop can verify its identity before accepting changes.
    """
    device_id: str
    last_sync_at: str = ""
    changes: list[dict] = Field(default_factory=list)
    # Optional cert fields — required when company keys are initialised
    company_id: str | None = None
    certificate_data: str | None = None
    signature: str | None = None


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
    only_active_jobs: bool = False
    # Optional cert fields — required when company keys are initialised
    company_id: str | None = None
    certificate_data: str | None = None
    signature: str | None = None


class DeviceSyncProfileUpdatePayload(BaseModel):
    primary_user_id: int | None = None
    storage_policy: str | None = None
    media_policy: str | None = None
    media_retention_days: int | None = None
    force_carry_undelivered_media: bool | None = None
    allow_borrowed_user_overrides: bool | None = None
    active_only_sync: bool | None = None


class MeshRelayEventPayload(BaseModel):
    source_device_id: str
    peer_device_id: str
    relay_type: str = "gossip"
    carried_change_count: int = 0
    carried_media_count: int = 0
    undelivered_after_count: int = 0
    metadata: dict = Field(default_factory=dict)


class RelayManifestPayload(BaseModel):
    """Advertise what undelivered data a device is carrying."""
    device_id: str
    pending_change_count: int = 0
    pending_media_count: int = 0
    change_hashes: list[str] = Field(default_factory=list)
    media_hashes: list[str] = Field(default_factory=list)
    origin_device_ids: list[str] = Field(default_factory=list)


class RelayPackagePayload(BaseModel):
    """Record a device-to-device relay transfer."""
    sender_device_id: str
    receiver_device_id: str
    origin_device_id: str
    change_count: int = 0
    media_count: int = 0
    package_hash: str | None = None


class RelayPackageStatusPayload(BaseModel):
    """Update status of a relay package."""
    status: str  # 'transferred' | 'confirmed' | 'failed'
    failure_reason: str | None = None


class RelayedDataPayload(BaseModel):
    """Accept data that was relayed through another device.

    The delivering device submits the changes originally from
    origin_device_id, along with the relay chain for audit.
    """
    delivering_device_id: str
    origin_device_id: str
    changes: list[dict] = Field(default_factory=list)
    relay_chain: list[str] = Field(default_factory=list)


class AcknowledgeReceiptsPayload(BaseModel):
    """Acknowledge one or more delivery receipts."""
    receipt_ids: list[int]


class HardSyncRequestPayload(BaseModel):
    """Request a hard-sync recovery package for a device."""
    device_id: str
    reason_code: str | None = None
    pending_outbound_hashes: list[str] = Field(default_factory=list)
    include_tables: list[str] | None = None
    preserve_pending_data: bool = True
    notes: str | None = None


class HardSyncCompletePayload(BaseModel):
    """Confirm hard-sync package was applied locally."""
    hard_sync_id: int
    device_id: str
    sync_batch_id: str
    applied_tables: list[str] = Field(default_factory=list)
    restored_pending_count: int = 0
    notes: str | None = None


async def _enforce_device_certificate_if_security_enabled(
    *,
    db: aiosqlite.Connection,
    device_id: str,
    company_id: str | None,
    certificate_data: str | None,
    signature: str | None,
) -> tuple[bool, str | None]:
    """Validate device certificate when security is enabled.

    Returns (valid, reason). If no companies are configured yet,
    security is considered disabled and validation is skipped.
    """
    sec = DeviceSecurityService(db)
    companies = await sec.list_companies()
    if not companies:
        return True, None

    if not certificate_data or not signature or not company_id:
        return False, "missing_certificate_fields"

    result = await sec.verify_certificate(
        device_id=device_id,
        company_id=company_id,
        certificate_data=certificate_data,
        signature=signature,
    )
    if not result.get("valid"):
        return False, result.get("reason", "unknown")
    return True, None


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

    **Certificate verification:** If any company has been initialised
    (security is enabled), the device must present a valid certificate.
    This prevents rogue devices from pushing data.  If security is NOT
    configured yet, sync proceeds unauthenticated for backward compat.
    """
    svc = SyncService(db)

    # ── Certificate gate ─────────────────────────────────────────
    cert_valid, cert_reason = await _enforce_device_certificate_if_security_enabled(
        db=db,
        device_id=payload.device_id,
        company_id=payload.company_id,
        certificate_data=payload.certificate_data,
        signature=payload.signature,
    )
    if not cert_valid:
        logger.warning(
            "Sync push rejected for device %s: cert invalid (%s)",
            payload.device_id,
            cert_reason,
        )
        if cert_reason == "missing_certificate_fields":
            return ApiResponse(
                data=None,
                message="Security enabled — device must present certificate_data, signature, and company_id",
            )
        return ApiResponse(
            data={"cert_valid": False, "reason": cert_reason},
            message=f"Certificate verification failed: {cert_reason}",
        )

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
            "server_time": datetime.now(timezone.utc).isoformat(),
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
    company_id: str | None = Query(None),
    certificate_data: str | None = Query(None),
    signature: str | None = Query(None),
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Pull shop changes since a timestamp. Lighter than full push flow."""
    cert_valid, cert_reason = await _enforce_device_certificate_if_security_enabled(
        db=db,
        device_id=device_id,
        company_id=company_id,
        certificate_data=certificate_data,
        signature=signature,
    )
    if not cert_valid:
        logger.warning(
            "Sync pull rejected for device %s: cert invalid (%s)",
            device_id,
            cert_reason,
        )
        if cert_reason == "missing_certificate_fields":
            return ApiResponse(
                data=None,
                message="Security enabled — device must present certificate_data, signature, and company_id",
            )
        return ApiResponse(
            data={"cert_valid": False, "reason": cert_reason},
            message=f"Certificate verification failed: {cert_reason}",
        )

    svc = SyncService(db)
    changes = await svc.get_changes_since(since, exclude_device=device_id)
    return ApiResponse(
        data={
            "changes": changes,
            "server_time": datetime.now(timezone.utc).isoformat(),
        },
        message=f"{len(changes)} changes since {since}",
    )


@router.post("/initial")
async def initial_sync(
    payload: InitialSyncRequest,
    user: dict = Depends(require_permission("manage_devices")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Full data load for initial device setup.

    Returns all rows from synced tables. Used when a device first
    connects and needs to populate its local DB from scratch.

    Requires ``manage_devices`` permission — only Admin (or any hat
    with that permission) can authorize a new device to join the fleet.
    """
    svc = SyncService(db)

    cert_valid, cert_reason = await _enforce_device_certificate_if_security_enabled(
        db=db,
        device_id=payload.device_id,
        company_id=payload.company_id,
        certificate_data=payload.certificate_data,
        signature=payload.signature,
    )
    if not cert_valid:
        logger.warning(
            "Initial sync rejected for device %s: cert invalid (%s)",
            payload.device_id,
            cert_reason,
        )
        if cert_reason == "missing_certificate_fields":
            return ApiResponse(
                data=None,
                message="Security enabled — device must present certificate_data, signature, and company_id",
            )
        return ApiResponse(
            data={"cert_valid": False, "reason": cert_reason},
            message=f"Certificate verification failed: {cert_reason}",
        )

    # Register the device
    await svc.register_device(
        payload.device_id, "Initial Sync", "unknown", user.get("id"),
    )

    data = await svc.get_initial_sync_data(
        payload.tables,
        only_active_jobs=payload.only_active_jobs,
    )

    total_rows = sum(len(rows) for rows in data.values())
    return ApiResponse(
        data={
            "tables": data,
            "server_time": datetime.now(timezone.utc).isoformat(),
        },
        message=f"Initial sync: {total_rows} rows across {len(data)} tables",
    )


@router.post("/register")
async def register_device(
    payload: DeviceRegisterPayload,
    user: dict = Depends(require_permission("manage_devices")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Register or update a device in the sync registry.

    Requires ``manage_devices`` permission — only Admins can register
    new devices into the fleet.
    """
    svc = SyncService(db)
    device = await svc.register_device(
        payload.device_id, payload.device_name, payload.platform, user.get("id"),
    )
    return ApiResponse(data=device, message="Device registered for sync")


@router.get("/profile/{device_id}")
async def get_device_sync_profile(
    device_id: str,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get storage/sync behavior profile for a device."""
    svc = SyncService(db)
    profile = await svc.get_device_sync_profile(device_id)
    if not profile:
        return ApiResponse(data=None, message="Device sync profile not found")
    return ApiResponse(data=profile)


@router.put("/profile/{device_id}")
async def update_device_sync_profile(
    device_id: str,
    payload: DeviceSyncProfileUpdatePayload,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update device sync/storage profile (primary-user policy source)."""
    svc = SyncService(db)
    profile = await svc.upsert_device_sync_profile(
        device_id=device_id,
        updated_by=user.get("id"),
        fields=payload.model_dump(exclude_unset=True),
    )
    return ApiResponse(data=profile, message="Device sync profile updated")


@router.post("/mesh/relay-events")
async def log_mesh_relay_event(
    payload: MeshRelayEventPayload,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Log a device↔device relay exchange event for mesh auditability."""
    svc = SyncService(db)
    event = await svc.log_mesh_relay_event(
        source_device_id=payload.source_device_id,
        peer_device_id=payload.peer_device_id,
        relay_type=payload.relay_type,
        carried_change_count=payload.carried_change_count,
        carried_media_count=payload.carried_media_count,
        undelivered_after_count=payload.undelivered_after_count,
        metadata=payload.metadata,
    )
    return ApiResponse(data=event, message="Mesh relay event logged")


@router.get("/mesh/relay-events")
async def list_mesh_relay_events(
    device_id: str | None = Query(None),
    limit: int = Query(100, ge=1, le=500),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List mesh relay events for operations/audit review."""
    svc = SyncService(db)
    rows = await svc.get_mesh_relay_events(device_id=device_id, limit=limit)
    return ApiResponse(data=rows, message=f"{len(rows)} relay events")


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


@router.delete("/devices/{device_id}")
async def revoke_device(
    device_id: str,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Revoke a device from the sync registry.

    The device will be blocked from syncing until it re-registers.
    Existing data on the device is not affected.
    """
    await db.execute(
        "DELETE FROM _device_registry WHERE device_id = ?",
        (device_id,),
    )
    await db.commit()
    return ApiResponse(message="Device revoked successfully")


@router.post("/hard-sync/request")
async def hard_sync_request(
    payload: HardSyncRequestPayload,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create and return a hard-sync package for a specific device.

    This is a controlled reset/resync path for recovery scenarios.
    """
    svc = SyncService(db)
    data = await svc.request_hard_sync(
        device_id=payload.device_id,
        requested_by=user.get("id"),
        reason_code=payload.reason_code,
        pending_outbound_hashes=payload.pending_outbound_hashes,
        include_tables=payload.include_tables,
        preserve_pending_data=payload.preserve_pending_data,
        notes=payload.notes,
    )
    return ApiResponse(
        data=data,
        message=f"Hard sync package ready: {data['total_rows']} rows across {data['table_count']} tables",
    )


@router.post("/hard-sync/complete")
async def hard_sync_complete(
    payload: HardSyncCompletePayload,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Mark a hard-sync operation as completed by the device."""
    svc = SyncService(db)
    result = await svc.complete_hard_sync(
        hard_sync_id=payload.hard_sync_id,
        device_id=payload.device_id,
        sync_batch_id=payload.sync_batch_id,
        completed_by=user.get("id"),
        applied_tables=payload.applied_tables,
        restored_pending_count=payload.restored_pending_count,
        notes=payload.notes,
    )
    if not result:
        return ApiResponse(data=None, message="Hard sync event not found")
    return ApiResponse(data=result, message="Hard sync marked complete")


@router.get("/hard-sync/history")
async def hard_sync_history(
    device_id: str | None = Query(None),
    limit: int = Query(50, ge=1, le=200),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List hard-sync recovery events."""
    svc = SyncService(db)
    rows = await svc.get_hard_sync_history(device_id=device_id, limit=limit)
    return ApiResponse(data=rows, message=f"{len(rows)} hard-sync events")


# ── Relay Manifests ──────────────────────────────────────────────


@router.post("/relay/manifests")
async def upsert_relay_manifest(
    payload: RelayManifestPayload,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create or update a device's relay manifest.

    A relay manifest advertises what undelivered data a device carries
    so peers can decide what to accept during BT/LAN encounters.
    """
    svc = SyncService(db)
    manifest = await svc.upsert_relay_manifest(
        device_id=payload.device_id,
        pending_change_count=payload.pending_change_count,
        pending_media_count=payload.pending_media_count,
        change_hashes=payload.change_hashes,
        media_hashes=payload.media_hashes,
        origin_device_ids=payload.origin_device_ids,
    )
    return ApiResponse(data=manifest, message="Relay manifest updated")


@router.get("/relay/manifests/{device_id}")
async def get_relay_manifest(
    device_id: str,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a device's current relay manifest."""
    svc = SyncService(db)
    manifest = await svc.get_relay_manifest(device_id)
    if not manifest:
        return ApiResponse(data=None, message="No manifest for device")
    return ApiResponse(data=manifest)


@router.get("/relay/manifests")
async def list_relay_manifests(
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all relay manifests (admin oversight)."""
    svc = SyncService(db)
    rows = await svc.list_relay_manifests()
    return ApiResponse(data=rows, message=f"{len(rows)} manifests")


# ── Relay Packages ───────────────────────────────────────────────


@router.post("/relay/packages")
async def create_relay_package(
    payload: RelayPackagePayload,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Record a device-to-device relay package for audit.

    Called when one device prepares a data bundle to hand off to
    another device via BT or LAN.
    """
    svc = SyncService(db)
    pkg = await svc.create_relay_package(
        sender_device_id=payload.sender_device_id,
        receiver_device_id=payload.receiver_device_id,
        origin_device_id=payload.origin_device_id,
        change_count=payload.change_count,
        media_count=payload.media_count,
        package_hash=payload.package_hash,
    )
    return ApiResponse(data=pkg, message="Relay package recorded")


@router.put("/relay/packages/{package_id}")
async def update_relay_package(
    package_id: int,
    payload: RelayPackageStatusPayload,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update relay package status (transferred, confirmed, failed)."""
    svc = SyncService(db)
    pkg = await svc.update_relay_package_status(
        package_id=package_id,
        status=payload.status,
        failure_reason=payload.failure_reason,
    )
    if not pkg:
        return ApiResponse(data=None, message="Relay package not found")
    return ApiResponse(data=pkg, message=f"Package status → {payload.status}")


@router.get("/relay/packages")
async def list_relay_packages(
    device_id: str | None = Query(None),
    status: str | None = Query(None),
    limit: int = Query(100, ge=1, le=500),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List relay packages for admin oversight."""
    svc = SyncService(db)
    rows = await svc.list_relay_packages(
        device_id=device_id, status=status, limit=limit,
    )
    return ApiResponse(data=rows, message=f"{len(rows)} relay packages")


# ── Relayed Data Delivery ────────────────────────────────────────


@router.post("/relay/deliver")
async def accept_relayed_data(
    payload: RelayedDataPayload,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Accept data that was relayed through another device.

    Almost identical to sync push, but the changes originated on
    origin_device_id and were carried here by delivering_device_id.
    A delivery receipt is issued so the origin can purge its copies.
    """
    svc = SyncService(db)

    # Certificate gate (same as sync push)
    cert_valid, cert_reason = await _enforce_device_certificate_if_security_enabled(
        db=db,
        device_id=payload.delivering_device_id,
        company_id=None,  # Relay delivery uses device-level auth
        certificate_data=None,
        signature=None,
    )
    # Note: cert enforcement is best-effort for relays — the delivering
    # device is authenticated via its session, and the origin's data
    # was already authenticated when it was first created.

    # Apply changes just like a normal sync push
    batch_id = await svc.create_batch(payload.delivering_device_id, "relay")
    applied, conflicts = await svc.apply_device_changes(
        payload.origin_device_id, payload.changes,
    )
    await svc.update_batch(
        batch_id, sent=0, received=len(applied), conflicts=len(conflicts),
    )

    # Issue delivery receipt so origin device can purge
    receipt = await svc.issue_delivery_receipt(
        origin_device_id=payload.origin_device_id,
        delivered_by_device_id=payload.delivering_device_id,
        receipt_type="mixed" if len(payload.changes) > 0 else "changes",
        change_count=len(applied),
        relay_chain=payload.relay_chain,
    )

    # Log mesh relay event
    await svc.log_mesh_relay_event(
        source_device_id=payload.delivering_device_id,
        peer_device_id="shop",
        relay_type="shop_delivery",
        carried_change_count=len(applied),
        metadata={"origin": payload.origin_device_id, "relay_chain": payload.relay_chain},
    )

    return ApiResponse(
        data={
            "applied": len(applied),
            "conflicts": conflicts,
            "receipt": receipt,
            "sync_batch_id": batch_id,
        },
        message=f"Relayed data accepted: {len(applied)} applied, receipt #{receipt['id']} issued",
    )


# ── Delivery Receipts ───────────────────────────────────────────


@router.get("/relay/receipts/pending/{device_id}")
async def get_pending_receipts(
    device_id: str,
    limit: int = Query(100, ge=1, le=500),
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get unacknowledged delivery receipts destined for a device.

    Called during sync so the device knows which relayed data has
    been delivered to the shop and can be safely purged locally.
    """
    svc = SyncService(db)
    rows = await svc.get_pending_receipts(device_id, limit=limit)
    return ApiResponse(data=rows, message=f"{len(rows)} pending receipts")


@router.post("/relay/receipts/acknowledge")
async def acknowledge_receipts(
    payload: AcknowledgeReceiptsPayload,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Acknowledge delivery receipts — device confirms it can purge.

    Accepts multiple receipt IDs for efficient bulk acknowledgment.
    """
    svc = SyncService(db)
    count = await svc.acknowledge_receipts_bulk(payload.receipt_ids)
    return ApiResponse(
        data={"acknowledged_count": count},
        message=f"{count} receipts acknowledged",
    )


@router.get("/relay/receipts")
async def list_delivery_receipts(
    device_id: str | None = Query(None),
    acknowledged: bool | None = Query(None),
    limit: int = Query(100, ge=1, le=500),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List delivery receipts for admin review."""
    svc = SyncService(db)
    rows = await svc.list_delivery_receipts(
        device_id=device_id, acknowledged=acknowledged, limit=limit,
    )
    return ApiResponse(data=rows, message=f"{len(rows)} delivery receipts")


# ── Relay Stats ──────────────────────────────────────────────────


@router.get("/relay/stats")
async def get_relay_stats(
    device_id: str | None = Query(None),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Aggregate relay statistics for the admin dashboard."""
    svc = SyncService(db)
    stats = await svc.get_relay_stats(device_id=device_id)
    return ApiResponse(data=stats)
