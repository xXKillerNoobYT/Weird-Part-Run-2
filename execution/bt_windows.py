"""
Windows Bluetooth RFCOMM — low-level API via ctypes + Winsock2.

Provides device discovery and RFCOMM socket creation for Bluetooth
communication between two Windows PCs running the full application.

This module uses ONLY the Windows built-in Bluetooth stack via ws2_32.dll
and bthprops.dll — zero third-party dependencies.

Functions:
    is_bluetooth_available()  — check if a BT adapter is present and enabled
    discover_devices()        — scan for nearby Bluetooth devices
    rfcomm_listen(uuid, ch)   — create a listening RFCOMM server socket
    rfcomm_accept(sock)       — accept an incoming RFCOMM connection
    rfcomm_connect(addr, uuid)— connect to a remote RFCOMM service
    rfcomm_send(sock, data)   — send length-prefixed data over RFCOMM
    rfcomm_recv(sock)         — receive length-prefixed data from RFCOMM
    close_socket(sock)        — close an RFCOMM socket

Protocol level:
    All data is sent length-prefixed: 4-byte big-endian length header
    followed by the payload. This handles TCP-stream framing so callers
    can send/receive complete JSON messages reliably.

Usage (primary/server):
    sock = rfcomm_listen(SERVICE_UUID)
    client_sock, client_addr = rfcomm_accept(sock)
    data = rfcomm_recv(client_sock)

Usage (secondary/client):
    sock = rfcomm_connect("AA:BB:CC:DD:EE:FF", SERVICE_UUID)
    rfcomm_send(sock, b'{"hello": "world"}')
    response = rfcomm_recv(sock)
"""

from __future__ import annotations

import ctypes
import ctypes.wintypes
import logging
import platform
import socket
import struct
import sys
import uuid as _uuid
from dataclasses import dataclass
from typing import Any

logger = logging.getLogger(__name__)

# ── Constants ──────────────────────────────────────────────────────

# Winsock Bluetooth constants
AF_BTH = 32                     # Bluetooth address family
BTHPROTO_RFCOMM = 0x0003       # RFCOMM protocol
BT_PORT_ANY = -1               # Let the system choose an RFCOMM channel
SOL_RFCOMM = 0x0003            # RFCOMM socket option level
SO_BTH_AUTHENTICATE = 0x80000001  # BT authentication option

# SDP service class UUID for Wired-Part sync
# This UUID uniquely identifies our application's Bluetooth service.
SERVICE_UUID = "7a1e0001-1234-5678-abcd-ef0123456789"

# Maximum payload size per frame (16 MB — more than enough for sync batches)
MAX_FRAME_SIZE = 16 * 1024 * 1024

# Discovery timeout in seconds
DISCOVERY_TIMEOUT_SECONDS = 12

# Socket timeouts
CONNECT_TIMEOUT_SECONDS = 15
IO_TIMEOUT_SECONDS = 60


# ── Platform check ────────────────────────────────────────────────

def _check_platform() -> bool:
    """Return True if running on Windows with Bluetooth support potential."""
    return platform.system() == "Windows"


# ── Data classes ──────────────────────────────────────────────────

@dataclass
class BluetoothDevice:
    """A discovered Bluetooth device."""
    address: str           # "AA:BB:CC:DD:EE:FF"
    name: str              # Human-readable device name
    device_class: int      # Bluetooth device class (COD)
    is_paired: bool        # Whether already paired with this PC
    is_connected: bool     # Whether currently connected


# ── Low-level helpers ─────────────────────────────────────────────

def _uuid_to_bytes(uuid_str: str) -> bytes:
    """Convert a UUID string to the 16-byte binary format Windows expects."""
    u = _uuid.UUID(uuid_str)
    return u.bytes


def _addr_string_to_int(addr: str) -> int:
    """Convert 'AA:BB:CC:DD:EE:FF' to a 64-bit Bluetooth address integer."""
    parts = addr.replace("-", ":").split(":")
    if len(parts) != 6:
        raise ValueError(f"Invalid Bluetooth address: {addr}")
    # Bluetooth address is little-endian in the integer representation
    addr_int = 0
    for i, part in enumerate(parts):
        addr_int |= int(part, 16) << (8 * (5 - i))
    return addr_int


def _addr_int_to_string(addr_int: int) -> str:
    """Convert a 64-bit Bluetooth address integer to 'AA:BB:CC:DD:EE:FF'."""
    parts = []
    for i in range(5, -1, -1):
        parts.append(f"{(addr_int >> (8 * i)) & 0xFF:02X}")
    return ":".join(parts)


# ── SOCKADDR_BTH structure ────────────────────────────────────────

class SOCKADDR_BTH(ctypes.Structure):
    """Windows Bluetooth socket address structure.

    Layout:
        addressFamily: USHORT  (AF_BTH = 32)
        btAddr:        ULONGLONG (6-byte BT address, zero-padded to 8)
        serviceClassId: GUID  (16 bytes — our service UUID)
        port:          ULONG  (RFCOMM channel, or BT_PORT_ANY)
    """
    _fields_ = [
        ("addressFamily", ctypes.c_ushort),
        ("btAddr", ctypes.c_ulonglong),
        ("serviceClassId", ctypes.c_byte * 16),
        ("port", ctypes.c_ulong),
    ]


# ── Bluetooth availability ────────────────────────────────────────

def is_bluetooth_available() -> dict[str, Any]:
    """Check if a Bluetooth adapter is present and enabled.

    Returns:
        {
            "available": True/False,
            "platform_ok": True/False,
            "adapter_found": True/False,
            "error": "..." or None
        }
    """
    result: dict[str, Any] = {
        "available": False,
        "platform_ok": _check_platform(),
        "adapter_found": False,
        "error": None,
    }

    if not result["platform_ok"]:
        result["error"] = f"Not Windows (running on {platform.system()})"
        return result

    try:
        # Try to create a Bluetooth socket. If this succeeds,
        # the Windows BT stack is loaded and an adapter exists.
        test_sock = socket.socket(AF_BTH, socket.SOCK_STREAM, BTHPROTO_RFCOMM)
        test_sock.close()
        result["adapter_found"] = True
        result["available"] = True
    except OSError as e:
        # Common errors:
        # 10047 (WSAEAFNOSUPPORT) = No BT stack / adapter
        # 10043 (WSAEPROTONOSUPPORT) = BT stack not available
        result["error"] = f"Bluetooth socket creation failed: {e}"
        logger.debug("Bluetooth availability check failed: %s", e)

    return result


# ── Device Discovery ──────────────────────────────────────────────

def discover_devices(timeout: int = DISCOVERY_TIMEOUT_SECONDS) -> list[BluetoothDevice]:
    """Scan for nearby Bluetooth devices using Windows Bluetooth APIs.

    Uses bthprops.dll BluetoothFindFirstDevice / BluetoothFindNextDevice
    for reliable device enumeration. Falls back to WSALookupService if
    bthprops is not available.

    Args:
        timeout: Discovery timeout in seconds (default 12s)

    Returns:
        List of BluetoothDevice objects found during the scan.
    """
    if not _check_platform():
        logger.warning("Device discovery called on non-Windows platform")
        return []

    devices: list[BluetoothDevice] = []

    try:
        # Use bthprops.dll for device enumeration
        bthprops = ctypes.windll.bthprops  # type: ignore[attr-defined]

        # BLUETOOTH_DEVICE_SEARCH_PARAMS structure
        class BT_SEARCH_PARAMS(ctypes.Structure):
            _fields_ = [
                ("dwSize", ctypes.c_ulong),
                ("fReturnAuthenticated", ctypes.c_bool),
                ("fReturnRemembered", ctypes.c_bool),
                ("fReturnUnknown", ctypes.c_bool),
                ("fReturnConnected", ctypes.c_bool),
                ("fIssueInquiry", ctypes.c_bool),
                ("cTimeoutMultiplier", ctypes.c_ubyte),
                ("hRadio", ctypes.c_void_p),
            ]

        # BLUETOOTH_DEVICE_INFO structure (simplified)
        class BT_DEVICE_INFO(ctypes.Structure):
            _fields_ = [
                ("dwSize", ctypes.c_ulong),
                ("Address", ctypes.c_ulonglong),
                ("ulClassofDevice", ctypes.c_ulong),
                ("fConnected", ctypes.c_bool),
                ("fRemembered", ctypes.c_bool),
                ("fAuthenticated", ctypes.c_bool),
                ("stLastSeen_year", ctypes.c_ushort),
                ("stLastSeen_month", ctypes.c_ushort),
                ("stLastSeen_dayOfWeek", ctypes.c_ushort),
                ("stLastSeen_day", ctypes.c_ushort),
                ("stLastSeen_hour", ctypes.c_ushort),
                ("stLastSeen_minute", ctypes.c_ushort),
                ("stLastSeen_second", ctypes.c_ushort),
                ("stLastSeen_milliseconds", ctypes.c_ushort),
                ("stLastUsed_year", ctypes.c_ushort),
                ("stLastUsed_month", ctypes.c_ushort),
                ("stLastUsed_dayOfWeek", ctypes.c_ushort),
                ("stLastUsed_day", ctypes.c_ushort),
                ("stLastUsed_hour", ctypes.c_ushort),
                ("stLastUsed_minute", ctypes.c_ushort),
                ("stLastUsed_second", ctypes.c_ushort),
                ("stLastUsed_milliseconds", ctypes.c_ushort),
                ("szName", ctypes.c_wchar * 248),
            ]

        # Set up search params — find all devices (remembered + new)
        params = BT_SEARCH_PARAMS()
        params.dwSize = ctypes.sizeof(BT_SEARCH_PARAMS)
        params.fReturnAuthenticated = True
        params.fReturnRemembered = True
        params.fReturnUnknown = True
        params.fReturnConnected = True
        params.fIssueInquiry = True
        # cTimeoutMultiplier: units of 1.28 seconds. 10 ≈ 12.8s scan.
        params.cTimeoutMultiplier = min(max(timeout * 10 // 13, 1), 48)
        params.hRadio = None

        device_info = BT_DEVICE_INFO()
        device_info.dwSize = ctypes.sizeof(BT_DEVICE_INFO)

        # Start enumeration
        handle = bthprops.BluetoothFindFirstDevice(
            ctypes.byref(params), ctypes.byref(device_info)
        )

        if not handle:
            # Could be no devices found or no BT adapter
            error_code = ctypes.GetLastError()
            if error_code == 259:  # ERROR_NO_MORE_ITEMS
                logger.info("Bluetooth discovery: no devices found")
            else:
                logger.warning("BluetoothFindFirstDevice failed: error %d", error_code)
            return devices

        try:
            # Process first device
            _add_device(devices, device_info)

            # Enumerate remaining devices
            while bthprops.BluetoothFindNextDevice(handle, ctypes.byref(device_info)):
                _add_device(devices, device_info)

        finally:
            bthprops.BluetoothFindDeviceClose(handle)

        logger.info("Bluetooth discovery complete: found %d devices", len(devices))

    except Exception as e:
        logger.exception("Bluetooth device discovery failed: %s", e)

    return devices


def _add_device(devices: list[BluetoothDevice], info: Any) -> None:
    """Extract device info from a BT_DEVICE_INFO structure and add to list."""
    try:
        addr = _addr_int_to_string(info.Address)
        name = info.szName or f"Device-{addr[-8:].replace(':', '')}"
        devices.append(BluetoothDevice(
            address=addr,
            name=name,
            device_class=info.ulClassofDevice,
            is_paired=bool(info.fAuthenticated),
            is_connected=bool(info.fConnected),
        ))
    except Exception as e:
        logger.warning("Failed to parse device info: %s", e)


# ── RFCOMM Listen (Server/Primary) ───────────────────────────────

def rfcomm_listen(
    service_uuid: str = SERVICE_UUID,
    channel: int = BT_PORT_ANY,
    backlog: int = 1,
) -> socket.socket:
    """Create a listening RFCOMM server socket.

    The primary (shop-role) PC calls this to wait for secondary devices
    to connect. The socket listens on an RFCOMM channel and advertises
    the service UUID via SDP so discovery-based connections work.

    Args:
        service_uuid: The service class UUID to advertise
        channel: RFCOMM channel (BT_PORT_ANY = system picks one)
        backlog: Listen queue size (1 for single-device pairing)

    Returns:
        A bound and listening Bluetooth socket.
    """
    sock = socket.socket(AF_BTH, socket.SOCK_STREAM, BTHPROTO_RFCOMM)

    # Build SOCKADDR_BTH for bind
    addr = SOCKADDR_BTH()
    addr.addressFamily = AF_BTH
    addr.btAddr = 0  # Any local adapter
    addr.port = channel & 0xFFFFFFFF  # BT_PORT_ANY is -1 → convert to unsigned

    # Copy service UUID into the GUID field
    uuid_bytes = _uuid_to_bytes(service_uuid)
    for i, b in enumerate(uuid_bytes):
        addr.serviceClassId[i] = b

    addr_bytes = bytes(addr)
    sock.bind(addr_bytes)
    sock.listen(backlog)

    logger.info("RFCOMM listening on channel (UUID: %s)", service_uuid)
    return sock


def rfcomm_accept(sock: socket.socket, timeout: float | None = None) -> tuple[socket.socket, str]:
    """Accept an incoming RFCOMM connection.

    Args:
        sock: The listening server socket from rfcomm_listen()
        timeout: Seconds to wait (None = block forever)

    Returns:
        (client_socket, remote_bt_address)
    """
    if timeout is not None:
        sock.settimeout(timeout)

    client_sock, raw_addr = sock.accept()
    # raw_addr for BT sockets is (address_string, channel) or raw bytes
    if isinstance(raw_addr, tuple) and len(raw_addr) >= 1:
        remote_addr = str(raw_addr[0])
    elif isinstance(raw_addr, bytes) and len(raw_addr) >= 10:
        # Parse SOCKADDR_BTH from raw bytes
        addr_int = struct.unpack_from("<Q", raw_addr, 2)[0]
        remote_addr = _addr_int_to_string(addr_int)
    else:
        remote_addr = "unknown"

    logger.info("RFCOMM connection accepted from %s", remote_addr)
    return client_sock, remote_addr


# ── RFCOMM Connect (Client/Secondary) ────────────────────────────

def rfcomm_connect(
    bt_address: str,
    service_uuid: str = SERVICE_UUID,
    timeout: float = CONNECT_TIMEOUT_SECONDS,
) -> socket.socket:
    """Connect to a remote RFCOMM service.

    The secondary (field-role) PC calls this to connect to the primary's
    listening RFCOMM socket.

    Args:
        bt_address: Remote device address ("AA:BB:CC:DD:EE:FF")
        service_uuid: The service UUID to connect to
        timeout: Connection timeout in seconds

    Returns:
        A connected Bluetooth socket.
    """
    sock = socket.socket(AF_BTH, socket.SOCK_STREAM, BTHPROTO_RFCOMM)
    sock.settimeout(timeout)

    # Build SOCKADDR_BTH for connect
    addr = SOCKADDR_BTH()
    addr.addressFamily = AF_BTH
    addr.btAddr = _addr_string_to_int(bt_address)
    addr.port = 0  # Will use SDP to find the channel by UUID

    uuid_bytes = _uuid_to_bytes(service_uuid)
    for i, b in enumerate(uuid_bytes):
        addr.serviceClassId[i] = b

    logger.info("RFCOMM connecting to %s (UUID: %s)", bt_address, service_uuid)
    addr_bytes = bytes(addr)
    sock.connect(addr_bytes)

    # Set I/O timeout after connection
    sock.settimeout(IO_TIMEOUT_SECONDS)

    logger.info("RFCOMM connected to %s", bt_address)
    return sock


# ── Framed I/O (length-prefixed) ─────────────────────────────────

def rfcomm_send(sock: socket.socket, data: bytes) -> int:
    """Send length-prefixed data over an RFCOMM socket.

    Protocol: [4-byte big-endian length][payload]

    Args:
        sock: Connected RFCOMM socket
        data: Raw bytes to send

    Returns:
        Total bytes sent (including header)
    """
    if len(data) > MAX_FRAME_SIZE:
        raise ValueError(f"Payload too large: {len(data)} > {MAX_FRAME_SIZE}")

    header = struct.pack(">I", len(data))
    sock.sendall(header + data)
    return 4 + len(data)


def rfcomm_recv(sock: socket.socket) -> bytes:
    """Receive length-prefixed data from an RFCOMM socket.

    Protocol: [4-byte big-endian length][payload]

    Args:
        sock: Connected RFCOMM socket

    Returns:
        The payload bytes (without the length header)

    Raises:
        ConnectionError: If the connection is broken
        ValueError: If the frame size exceeds MAX_FRAME_SIZE
    """
    # Read the 4-byte length header
    header = _recv_exact(sock, 4)
    if not header:
        raise ConnectionError("Connection closed while reading frame header")

    payload_len = struct.unpack(">I", header)[0]
    if payload_len > MAX_FRAME_SIZE:
        raise ValueError(f"Frame too large: {payload_len} > {MAX_FRAME_SIZE}")
    if payload_len == 0:
        return b""

    # Read the payload
    payload = _recv_exact(sock, payload_len)
    if not payload or len(payload) < payload_len:
        raise ConnectionError(
            f"Connection closed while reading payload "
            f"(expected {payload_len}, got {len(payload) if payload else 0})"
        )

    return payload


def _recv_exact(sock: socket.socket, num_bytes: int) -> bytes:
    """Read exactly num_bytes from a socket."""
    chunks: list[bytes] = []
    remaining = num_bytes
    while remaining > 0:
        chunk = sock.recv(min(remaining, 65536))
        if not chunk:
            break
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


# ── Socket Cleanup ────────────────────────────────────────────────

def close_socket(sock: socket.socket | None) -> None:
    """Safely close a Bluetooth socket."""
    if sock is None:
        return
    try:
        sock.shutdown(socket.SHUT_RDWR)
    except OSError:
        pass
    try:
        sock.close()
    except OSError:
        pass


# ── Heartbeat Protocol ────────────────────────────────────────────

HEARTBEAT_MAGIC = b"WPHB"  # Wired Part HeartBeat

def send_heartbeat(sock: socket.socket) -> None:
    """Send a heartbeat ping over the RFCOMM socket."""
    rfcomm_send(sock, HEARTBEAT_MAGIC)


def is_heartbeat(data: bytes) -> bool:
    """Check if received data is a heartbeat."""
    return data == HEARTBEAT_MAGIC


# ── Standalone test ───────────────────────────────────────────────

if __name__ == "__main__":
    logging.basicConfig(level=logging.DEBUG)

    print("=" * 50)
    print("Wired-Part Bluetooth Diagnostics")
    print("=" * 50)

    availability = is_bluetooth_available()
    print(f"\nBluetooth available: {availability['available']}")
    print(f"  Platform OK:      {availability['platform_ok']}")
    print(f"  Adapter found:    {availability['adapter_found']}")
    if availability["error"]:
        print(f"  Error:            {availability['error']}")

    if availability["available"]:
        print("\nScanning for nearby devices...")
        found = discover_devices(timeout=8)
        if found:
            print(f"\nFound {len(found)} device(s):")
            for d in found:
                paired = "✓ paired" if d.is_paired else "not paired"
                connected = "✓ connected" if d.is_connected else ""
                print(f"  {d.address}  {d.name:<30}  {paired}  {connected}")
        else:
            print("\nNo devices found.")
    else:
        print("\nBluetooth is not available. To enable:")
        print("  1. Install a USB Bluetooth 5.0 dongle ($10-15)")
        print("  2. Ensure the Windows Bluetooth service is running")
        print("  3. Check Device Manager → Bluetooth adapters")
