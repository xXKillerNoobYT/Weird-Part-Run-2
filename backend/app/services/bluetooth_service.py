"""
Bluetooth service — Orchestrates BT scanning, pairing, tunnel, and sync.

This is the main coordination layer between:
  - execution/bt_windows.py   (low-level BT RFCOMM via ctypes)
  - execution/bt_tunnel.py    (TCP ↔ RFCOMM tunnel)
  - repositories/bluetooth_repo.py (DB persistence)

The service manages the full lifecycle: scan → pair → connect → tunnel → sync.
"""

from __future__ import annotations

import asyncio
import logging
import platform
import secrets
import sys
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import aiosqlite

from app.repositories.bluetooth_repo import BluetoothRepo

logger = logging.getLogger(__name__)

# ── Lazy imports for execution scripts ────────────────────────────
# These only work on Windows with a BT adapter.  On other platforms
# they gracefully degrade (scan returns empty, tunnel won't start).

_bt_windows = None
_bt_tunnel_mod = None
_import_attempted = False


def _ensure_imports() -> None:
    """Lazy-import the execution modules once."""
    global _bt_windows, _bt_tunnel_mod, _import_attempted
    if _import_attempted:
        return
    _import_attempted = True

    # Add project root to path so execution/ is importable
    project_root = Path(__file__).resolve().parent.parent.parent.parent
    exec_dir = project_root / "execution"
    if str(exec_dir) not in sys.path:
        sys.path.insert(0, str(exec_dir))

    try:
        import bt_windows  # type: ignore[import-untyped]
        _bt_windows = bt_windows
        logger.info("bt_windows loaded successfully")
    except Exception as e:
        logger.warning("bt_windows not available: %s", e)

    try:
        import bt_tunnel  # type: ignore[import-untyped]
        _bt_tunnel_mod = bt_tunnel
        logger.info("bt_tunnel loaded successfully")
    except Exception as e:
        logger.warning("bt_tunnel not available: %s", e)


# ── Singleton tunnel instance ─────────────────────────────────────
# Only one tunnel can be active at a time.  Access via get_tunnel().

_active_tunnel: Any = None
_active_log_id: int | None = None
_tunnel_lock = threading.Lock()


def get_tunnel() -> Any:
    """Return the active BtTunnel instance (or None)."""
    return _active_tunnel


class BluetoothService:
    """Coordinates Bluetooth operations: scan, pair, tunnel, status."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.repo = BluetoothRepo(db)
        _ensure_imports()

    # ── Availability ──────────────────────────────────────────────

    async def check_availability(self) -> dict[str, Any]:
        """Check if Windows Bluetooth hardware is available."""
        result = {
            "available": False,
            "platform_ok": platform.system() == "Windows",
            "adapter_found": False,
            "error": None,
        }

        if not result["platform_ok"]:
            result["error"] = f"Bluetooth RFCOMM requires Windows (got {platform.system()})"
            return result

        if _bt_windows is None:
            result["error"] = "Bluetooth module not loaded"
            return result

        try:
            # Run blocking check in executor
            loop = asyncio.get_running_loop()
            available = await loop.run_in_executor(
                None, _bt_windows.is_bluetooth_available
            )
            result["adapter_found"] = available
            result["available"] = available
            if not available:
                result["error"] = "No Bluetooth adapter found or adapter is off"
        except Exception as e:
            result["error"] = str(e)

        return result

    # ── Scanning ──────────────────────────────────────────────────

    async def scan_devices(self, duration: int = 10) -> dict[str, Any]:
        """Scan for nearby Bluetooth devices.

        Returns discovered devices with their addresses and names.
        Duration is capped at 60 seconds.
        """
        if _bt_windows is None:
            return {"devices": [], "scan_duration_seconds": 0.0, "error": "BT not available"}

        duration = min(max(duration, 5), 60)

        try:
            loop = asyncio.get_running_loop()
            discovered = await loop.run_in_executor(
                None, _bt_windows.discover_devices
            )

            # Check which are already paired in our DB
            paired = await self.repo.list_paired_devices(active_only=True)
            paired_addrs = {d["bt_address"] for d in paired}

            devices = []
            for dev in discovered:
                devices.append({
                    "address": dev.address,
                    "name": dev.name,
                    "device_class": dev.device_class,
                    "is_paired": dev.address in paired_addrs,
                    "is_connected": False,
                })

            return {
                "devices": devices,
                "scan_duration_seconds": float(duration),
            }
        except Exception as e:
            logger.exception("BT scan failed")
            return {"devices": [], "scan_duration_seconds": 0.0, "error": str(e)}

    # ── Pairing ───────────────────────────────────────────────────

    async def pair_device(
        self,
        bt_address: str,
        display_name: str = "Unknown Device",
        role: str = "secondary",
    ) -> dict[str, Any]:
        """Create a pairing record for a Bluetooth device.

        Generates a 6-digit pairing code that should be confirmed
        on the other device for verification.
        """
        # Generate a 6-digit pairing code
        pairing_code = f"{secrets.randbelow(1000000):06d}"

        paired = await self.repo.create_paired_device(
            bt_address=bt_address,
            display_name=display_name,
            role=role,
            pairing_code=pairing_code,
        )

        logger.info("Paired with %s (%s) as %s", display_name, bt_address, role)
        return paired

    async def unpair_device(self, device_id: int) -> bool:
        """Deactivate a paired device. Stops tunnel if connected to it."""
        global _active_tunnel

        device = await self.repo.get_paired_device(device_id)
        if not device:
            return False

        # If tunnel is active to this device, stop it first
        if _active_tunnel and hasattr(_active_tunnel, "remote_addr"):
            if _active_tunnel.remote_addr == device.get("bt_address"):
                await self.disconnect()

        result = await self.repo.deactivate_paired_device(device_id)
        if result:
            logger.info("Unpaired device %d (%s)", device_id, device.get("bt_address"))
        return result

    async def get_paired_devices(self) -> list[dict[str, Any]]:
        """List all active paired devices with live connection status."""
        devices = await self.repo.list_paired_devices(active_only=True)

        # Annotate with live connection status
        for dev in devices:
            dev["is_currently_connected"] = (
                _active_tunnel is not None
                and hasattr(_active_tunnel, "remote_addr")
                and _active_tunnel.remote_addr == dev.get("bt_address")
                and hasattr(_active_tunnel, "state")
                and str(_active_tunnel.state.value) == "connected"
            )

        return devices

    # ── Tunnel Control ────────────────────────────────────────────

    async def connect(
        self,
        bt_address: str,
        role: str = "secondary",
    ) -> dict[str, Any]:
        """Start the BT RFCOMM tunnel to a paired device.

        For PRIMARY role: listens for incoming RFCOMM connections and
            forwards requests to the local FastAPI server (port 8000).
        For SECONDARY role: connects to the primary and starts a local
            TCP server (port 9000) that tunnels to the primary.
        """
        global _active_tunnel, _active_log_id

        if _bt_tunnel_mod is None:
            return {"success": False, "error": "BT tunnel module not loaded"}

        if _active_tunnel is not None:
            return {"success": False, "error": "Tunnel already active. Disconnect first."}

        # Read tunnel port from settings
        settings = await self.repo.get_bt_settings()
        tunnel_port = int(settings.get("bt_tunnel_port", "9000"))

        try:
            with _tunnel_lock:
                if role == "primary":
                    mode = _bt_tunnel_mod.TunnelMode.PRIMARY
                else:
                    mode = _bt_tunnel_mod.TunnelMode.SECONDARY

                tunnel = _bt_tunnel_mod.create_tunnel(
                    mode=mode,
                    remote_bt_addr=bt_address,
                    tunnel_port=tunnel_port,
                    local_api_port=8000,
                )

                # Start tunnel in background thread
                tunnel.start()
                _active_tunnel = tunnel

            # Log connection start
            _active_log_id = await self.repo.log_connection_start(
                remote_bt_address=bt_address,
            )

            # Update paired device timestamps
            paired = await self.repo.get_paired_device_by_address(bt_address)
            if paired:
                await self.repo.touch_connected(paired["id"])

            logger.info("BT tunnel started: %s mode to %s", role, bt_address)
            return {"success": True, "mode": role, "address": bt_address}

        except Exception as e:
            logger.exception("Failed to start BT tunnel")
            _active_tunnel = None
            return {"success": False, "error": str(e)}

    async def disconnect(
        self,
        reason: str = "manual",
    ) -> dict[str, Any]:
        """Stop the active BT RFCOMM tunnel."""
        global _active_tunnel, _active_log_id

        if _active_tunnel is None:
            return {"success": True, "message": "No active tunnel"}

        try:
            stats = None
            if hasattr(_active_tunnel, "get_stats"):
                stats = _active_tunnel.get_stats()

            with _tunnel_lock:
                _active_tunnel.stop()
                _active_tunnel = None

            # Finalize connection log
            if _active_log_id:
                await self.repo.log_connection_end(
                    _active_log_id,
                    bytes_sent=stats.bytes_sent if stats else 0,
                    bytes_received=stats.bytes_received if stats else 0,
                    requests_forwarded=stats.requests_forwarded if stats else 0,
                    disconnect_reason=reason,
                )
                _active_log_id = None

            logger.info("BT tunnel stopped (reason: %s)", reason)
            return {"success": True, "reason": reason}

        except Exception as e:
            logger.exception("Error stopping BT tunnel")
            _active_tunnel = None
            _active_log_id = None
            return {"success": False, "error": str(e)}

    async def get_tunnel_status(self) -> dict[str, Any]:
        """Get current tunnel state and stats."""
        if _active_tunnel is None:
            return {
                "state": "stopped",
                "mode": "none",
                "remote_address": "",
                "connected_since": None,
                "last_heartbeat_at": None,
                "bytes_sent": 0,
                "bytes_received": 0,
                "requests_forwarded": 0,
                "reconnect_count": 0,
                "last_error": None,
                "uptime_seconds": 0.0,
            }

        try:
            stats = (
                _active_tunnel.get_stats()
                if hasattr(_active_tunnel, "get_stats")
                else None
            )
            state_name = (
                str(_active_tunnel.state.value)
                if hasattr(_active_tunnel, "state")
                else "unknown"
            )
            mode_name = (
                str(_active_tunnel.mode.value)
                if hasattr(_active_tunnel, "mode")
                else "unknown"
            )

            return {
                "state": state_name,
                "mode": mode_name,
                "remote_address": getattr(_active_tunnel, "remote_addr", ""),
                "connected_since": (
                    stats.connected_since.isoformat() if stats and stats.connected_since else None
                ),
                "last_heartbeat_at": (
                    stats.last_heartbeat.isoformat() if stats and stats.last_heartbeat else None
                ),
                "bytes_sent": stats.bytes_sent if stats else 0,
                "bytes_received": stats.bytes_received if stats else 0,
                "requests_forwarded": stats.requests_forwarded if stats else 0,
                "reconnect_count": stats.reconnect_count if stats else 0,
                "last_error": getattr(_active_tunnel, "last_error", None),
                "uptime_seconds": stats.uptime_seconds if stats else 0.0,
            }
        except Exception as e:
            logger.exception("Error reading tunnel status")
            return {"state": "error", "last_error": str(e)}

    # ── Settings ──────────────────────────────────────────────────

    async def get_config(self) -> dict[str, Any]:
        """Read Bluetooth sync configuration."""
        raw = await self.repo.get_bt_settings()
        return {
            "bt_enabled": raw.get("bt_enabled", "true") == "true",
            "bt_device_role": raw.get("bt_device_role", "auto"),
            "bt_auto_connect": raw.get("bt_auto_connect", "true") == "true",
            "bt_sync_interval": int(raw.get("bt_sync_interval", "120")),
            "bt_tunnel_port": int(raw.get("bt_tunnel_port", "9000")),
        }

    async def update_config(self, updates: dict[str, Any]) -> dict[str, Any]:
        """Update Bluetooth sync configuration.

        Accepts typed values and converts to strings for settings table.
        """
        settings_updates: dict[str, str] = {}

        for key, value in updates.items():
            if key in ("bt_enabled", "bt_auto_connect"):
                settings_updates[key] = "true" if value else "false"
            elif key in ("bt_device_role",):
                if value in ("primary", "secondary", "auto"):
                    settings_updates[key] = value
            elif key in ("bt_sync_interval", "bt_tunnel_port"):
                settings_updates[key] = str(int(value))

        if settings_updates:
            await self.repo.update_bt_settings(settings_updates)

        return await self.get_config()

    # ── Connection Log ────────────────────────────────────────────

    async def get_connection_log(
        self,
        *,
        limit: int = 50,
        offset: int = 0,
        bt_address: str | None = None,
    ) -> dict[str, Any]:
        """Return paginated connection log."""
        entries = await self.repo.get_connection_log(
            limit=limit, offset=offset, bt_address=bt_address
        )
        total = await self.repo.get_connection_log_count(bt_address=bt_address)
        return {"entries": entries, "total": total}
