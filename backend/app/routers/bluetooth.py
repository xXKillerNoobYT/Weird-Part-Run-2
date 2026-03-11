"""
Bluetooth routes — Manage BT device scanning, pairing, and sync tunnel.

Endpoints:
  GET   /api/bluetooth/availability   → Check Bluetooth hardware status
  GET   /api/bluetooth/scan           → Scan for nearby BT devices
  GET   /api/bluetooth/paired         → List paired devices
  POST  /api/bluetooth/pair           → Pair with a BT device
  DELETE /api/bluetooth/pair/{id}     → Unpair a device
  POST  /api/bluetooth/connect        → Start BT tunnel
  POST  /api/bluetooth/disconnect     → Stop BT tunnel
  GET   /api/bluetooth/status         → Tunnel connection status
  GET   /api/bluetooth/log            → Connection history
  GET   /api/bluetooth/config         → Get BT sync configuration
  PUT   /api/bluetooth/config         → Update BT sync configuration
"""

from __future__ import annotations

import logging

import aiosqlite
from fastapi import APIRouter, Depends, Query

from app.database import get_db
from app.middleware.auth import require_permission
from app.models.bluetooth import (
    BtAvailability,
    BtConnectRequest,
    BtConnectionLogEntry,
    BtDisconnectRequest,
    BtDiscoveredDevice,
    BtPairedDevice,
    BtPairRequest,
    BtScanResponse,
    BtSyncConfig,
    BtSyncConfigUpdate,
    BtTunnelStatus,
)
from app.models.common import ApiResponse
from app.services.bluetooth_service import BluetoothService

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/bluetooth", tags=["Bluetooth"])


# ── Availability ──────────────────────────────────────────────────

@router.get("/availability", response_model=ApiResponse[BtAvailability])
async def check_availability(
    db: aiosqlite.Connection = Depends(get_db),
    _user: dict = Depends(require_permission("manage_bluetooth")),
):
    """Check whether Bluetooth hardware is available on this machine."""
    svc = BluetoothService(db)
    result = await svc.check_availability()
    return ApiResponse(data=result)


# ── Scanning ──────────────────────────────────────────────────────

@router.get("/scan", response_model=ApiResponse[BtScanResponse])
async def scan_devices(
    duration: int = Query(10, ge=5, le=60, description="Scan duration in seconds"),
    db: aiosqlite.Connection = Depends(get_db),
    _user: dict = Depends(require_permission("manage_bluetooth")),
):
    """Scan for nearby Bluetooth devices.

    This is a blocking operation that runs in a thread executor.
    Duration controls how long the scan waits (5-60 seconds).
    """
    svc = BluetoothService(db)
    result = await svc.scan_devices(duration=duration)
    return ApiResponse(data=result)


# ── Paired Devices ────────────────────────────────────────────────

@router.get("/paired", response_model=ApiResponse[list[BtPairedDevice]])
async def list_paired_devices(
    db: aiosqlite.Connection = Depends(get_db),
    _user: dict = Depends(require_permission("manage_bluetooth")),
):
    """List all actively paired Bluetooth devices."""
    svc = BluetoothService(db)
    devices = await svc.get_paired_devices()
    return ApiResponse(data=devices)


@router.post("/pair", response_model=ApiResponse[BtPairedDevice])
async def pair_device(
    payload: BtPairRequest,
    db: aiosqlite.Connection = Depends(get_db),
    _user: dict = Depends(require_permission("manage_bluetooth")),
):
    """Pair with a discovered Bluetooth device.

    Creates a pairing record with a 6-digit confirmation code.
    Both devices should show matching codes for verification.
    """
    svc = BluetoothService(db)
    result = await svc.pair_device(
        bt_address=payload.bt_address,
        display_name=payload.display_name,
        role=payload.role,
    )
    return ApiResponse(data=result, message=f"Paired with {payload.display_name}")


@router.delete("/pair/{device_id}", response_model=ApiResponse)
async def unpair_device(
    device_id: int,
    db: aiosqlite.Connection = Depends(get_db),
    _user: dict = Depends(require_permission("manage_bluetooth")),
):
    """Unpair a Bluetooth device. Stops tunnel if connected."""
    svc = BluetoothService(db)
    success = await svc.unpair_device(device_id)
    if not success:
        return ApiResponse(success=False, error="Device not found or already unpaired")
    return ApiResponse(message="Device unpaired")


# ── Tunnel Control ────────────────────────────────────────────────

@router.post("/connect", response_model=ApiResponse)
async def connect(
    payload: BtConnectRequest,
    db: aiosqlite.Connection = Depends(get_db),
    _user: dict = Depends(require_permission("manage_bluetooth")),
):
    """Start the Bluetooth RFCOMM tunnel to a paired device.

    For PRIMARY role: listens for incoming RFCOMM connections and
    forwards API requests to the local FastAPI server.

    For SECONDARY role: connects to the primary via RFCOMM and opens
    a local TCP port that tunnels traffic to the primary.
    """
    svc = BluetoothService(db)
    result = await svc.connect(
        bt_address=payload.bt_address,
        role=payload.role,
    )
    if result.get("success"):
        return ApiResponse(message=f"Tunnel started ({payload.role} → {payload.bt_address})")
    return ApiResponse(success=False, error=result.get("error", "Connect failed"))


@router.post("/disconnect", response_model=ApiResponse)
async def disconnect(
    payload: BtDisconnectRequest | None = None,
    db: aiosqlite.Connection = Depends(get_db),
    _user: dict = Depends(require_permission("manage_bluetooth")),
):
    """Stop the active Bluetooth RFCOMM tunnel."""
    svc = BluetoothService(db)
    reason = payload.reason if payload else "manual"
    result = await svc.disconnect(reason=reason)
    if result.get("success"):
        return ApiResponse(message="Tunnel disconnected")
    return ApiResponse(success=False, error=result.get("error", "Disconnect failed"))


@router.get("/status", response_model=ApiResponse[BtTunnelStatus])
async def tunnel_status(
    db: aiosqlite.Connection = Depends(get_db),
    _user: dict = Depends(require_permission("manage_bluetooth")),
):
    """Get the current Bluetooth tunnel status and statistics."""
    svc = BluetoothService(db)
    status = await svc.get_tunnel_status()
    return ApiResponse(data=status)


# ── Connection Log ────────────────────────────────────────────────

@router.get("/log", response_model=ApiResponse)
async def connection_log(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    bt_address: str | None = Query(None, description="Filter by remote BT address"),
    db: aiosqlite.Connection = Depends(get_db),
    _user: dict = Depends(require_permission("manage_bluetooth")),
):
    """Get Bluetooth connection history."""
    svc = BluetoothService(db)
    result = await svc.get_connection_log(
        limit=limit, offset=offset, bt_address=bt_address,
    )
    return ApiResponse(data=result)


# ── Configuration ─────────────────────────────────────────────────

@router.get("/config", response_model=ApiResponse[BtSyncConfig])
async def get_config(
    db: aiosqlite.Connection = Depends(get_db),
    _user: dict = Depends(require_permission("manage_bluetooth")),
):
    """Get Bluetooth sync configuration."""
    svc = BluetoothService(db)
    config = await svc.get_config()
    return ApiResponse(data=config)


@router.put("/config", response_model=ApiResponse[BtSyncConfig])
async def update_config(
    payload: BtSyncConfigUpdate,
    db: aiosqlite.Connection = Depends(get_db),
    _user: dict = Depends(require_permission("manage_bluetooth")),
):
    """Update Bluetooth sync configuration.

    Only provided fields are updated; omitted fields keep current values.
    """
    svc = BluetoothService(db)
    updates = payload.model_dump(exclude_none=True)
    config = await svc.update_config(updates)
    return ApiResponse(data=config, message="Bluetooth configuration updated")
