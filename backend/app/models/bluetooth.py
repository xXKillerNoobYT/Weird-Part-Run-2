"""
Pydantic models for Bluetooth pairing and sync.

Defines request/response shapes for the /api/bluetooth/* endpoints.
"""

from __future__ import annotations

from pydantic import BaseModel, Field


# ── Bluetooth Availability ────────────────────────────────────────

class BtAvailability(BaseModel):
    """Bluetooth hardware availability status."""
    available: bool = False
    platform_ok: bool = False
    adapter_found: bool = False
    error: str | None = None


# ── Discovered Devices ────────────────────────────────────────────

class BtDiscoveredDevice(BaseModel):
    """A Bluetooth device found during scanning."""
    address: str               # "AA:BB:CC:DD:EE:FF"
    name: str                  # Human-readable name
    device_class: int = 0      # Bluetooth COD
    is_paired: bool = False    # Already paired with OS
    is_connected: bool = False # Currently connected


class BtScanResponse(BaseModel):
    """Response from a Bluetooth scan operation."""
    devices: list[BtDiscoveredDevice] = Field(default_factory=list)
    scan_duration_seconds: float = 0.0


# ── Paired Devices ────────────────────────────────────────────────

class BtPairRequest(BaseModel):
    """Request to pair with a discovered Bluetooth device."""
    bt_address: str            # "AA:BB:CC:DD:EE:FF"
    display_name: str = "Unknown Device"
    role: str = "secondary"    # "primary" or "secondary"


class BtPairedDevice(BaseModel):
    """A paired Bluetooth device from the database."""
    id: int
    device_id: str | None = None
    bt_address: str
    display_name: str
    role: str                  # "primary" or "secondary"
    pairing_code: str | None = None
    is_active: bool = True
    last_connected_at: str | None = None
    last_sync_at: str | None = None
    paired_at: str | None = None
    # Live status (populated at query time, not stored)
    is_currently_connected: bool = False


class BtPairedDeviceResponse(BaseModel):
    """Response containing a list of paired devices."""
    devices: list[BtPairedDevice] = Field(default_factory=list)


# ── Tunnel Status ─────────────────────────────────────────────────

class BtTunnelStatus(BaseModel):
    """Current status of the Bluetooth RFCOMM tunnel."""
    state: str = "stopped"     # stopped, starting, listening, connecting, connected, reconnecting, error
    mode: str = "primary"      # primary or secondary
    remote_address: str = ""
    connected_since: str | None = None
    last_heartbeat_at: str | None = None
    bytes_sent: int = 0
    bytes_received: int = 0
    requests_forwarded: int = 0
    reconnect_count: int = 0
    last_error: str | None = None
    uptime_seconds: float = 0.0


# ── Connection Control ────────────────────────────────────────────

class BtConnectRequest(BaseModel):
    """Request to manually initiate a BT connection."""
    bt_address: str            # Address of paired device to connect to
    role: str = "secondary"    # Role for this connection


class BtDisconnectRequest(BaseModel):
    """Request to disconnect the current BT tunnel."""
    reason: str = "manual"


# ── Connection Log ────────────────────────────────────────────────

class BtConnectionLogEntry(BaseModel):
    """An entry in the Bluetooth connection log."""
    id: int
    local_device_id: str | None = None
    remote_device_id: str | None = None
    remote_bt_address: str
    connected_at: str
    disconnected_at: str | None = None
    duration_seconds: float | None = None
    bytes_sent: int = 0
    bytes_received: int = 0
    requests_forwarded: int = 0
    changes_synced: int = 0
    disconnect_reason: str | None = None
    error_message: str | None = None


# ── BT Sync Configuration ────────────────────────────────────────

class BtSyncConfig(BaseModel):
    """Bluetooth sync configuration (from settings table)."""
    bt_enabled: bool = True
    bt_device_role: str = "auto"       # "primary", "secondary", "auto"
    bt_auto_connect: bool = True
    bt_sync_interval: int = 120        # seconds
    bt_tunnel_port: int = 9000


class BtSyncConfigUpdate(BaseModel):
    """Request to update BT sync configuration."""
    bt_enabled: bool | None = None
    bt_device_role: str | None = None
    bt_auto_connect: bool | None = None
    bt_sync_interval: int | None = None
    bt_tunnel_port: int | None = None
