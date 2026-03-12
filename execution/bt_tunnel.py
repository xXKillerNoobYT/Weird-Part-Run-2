"""
Bluetooth RFCOMM ↔ TCP Bidirectional Tunnel.

Creates a transparent bridge between a local TCP port and a remote
Bluetooth RFCOMM connection. This allows the existing sync engine
(which speaks HTTP) to communicate over Bluetooth without any changes.

Two modes:
  PRIMARY (server):
    1. Starts an RFCOMM listener (Bluetooth)
    2. When a secondary connects, proxies all data to localhost:8000
    3. Any response from FastAPI routes back over BT to the secondary

  SECONDARY (client):
    1. Connects to the primary via RFCOMM (Bluetooth)
    2. Listens on localhost:9000 (TCP)
    3. Local HTTP clients (sync job) → :9000 → BT → primary's :8000

The tunnel uses HTTP/1.1 framing natively — each complete HTTP
request/response is forwarded as-is over the RFCOMM stream with
length-prefixed framing.

Usage:
    # On primary PC (shop role):
    tunnel = BtTunnel(mode="primary", local_api_port=8000)
    await tunnel.start()

    # On secondary PC (field role):
    tunnel = BtTunnel(mode="secondary", remote_bt_addr="AA:BB:CC:DD:EE:FF",
                       tunnel_port=9000, remote_api_port=8000)
    await tunnel.start()
"""

from __future__ import annotations

import asyncio
import json
import logging
import socket
import struct
import threading
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Callable

# Import our BT primitives from the same execution/ directory
try:
    from execution.bt_windows import (
        SERVICE_UUID,
        BluetoothDevice,
        close_socket,
        is_bluetooth_available,
        is_heartbeat,
        rfcomm_accept,
        rfcomm_connect,
        rfcomm_listen,
        rfcomm_recv,
        rfcomm_send,
        send_heartbeat,
    )
except ImportError:
    # When run directly or from backend context
    import sys, os
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
    from execution.bt_windows import (
        SERVICE_UUID,
        BluetoothDevice,
        close_socket,
        is_bluetooth_available,
        is_heartbeat,
        rfcomm_accept,
        rfcomm_connect,
        rfcomm_listen,
        rfcomm_recv,
        rfcomm_send,
        send_heartbeat,
    )

logger = logging.getLogger(__name__)


# ── Constants ──────────────────────────────────────────────────────

DEFAULT_TUNNEL_PORT = 9000     # Local TCP port on secondary for sync job
DEFAULT_API_PORT = 8000        # FastAPI port on both machines
HEARTBEAT_INTERVAL = 30        # Seconds between heartbeats
RECONNECT_DELAYS = [5, 10, 30, 60]  # Exponential backoff (caps at 60s)

# Frame types for multiplexing
FRAME_TYPE_HTTP_REQUEST = 0x01
FRAME_TYPE_HTTP_RESPONSE = 0x02
FRAME_TYPE_HEARTBEAT = 0x03
FRAME_TYPE_CONTROL = 0x04


class TunnelMode(str, Enum):
    PRIMARY = "primary"
    SECONDARY = "secondary"


class TunnelState(str, Enum):
    STOPPED = "stopped"
    STARTING = "starting"
    LISTENING = "listening"      # Primary: waiting for secondary
    CONNECTING = "connecting"    # Secondary: connecting to primary
    CONNECTED = "connected"     # Tunnel active, forwarding data
    RECONNECTING = "reconnecting"
    ERROR = "error"


@dataclass
class TunnelStats:
    """Runtime statistics for the tunnel."""
    state: TunnelState = TunnelState.STOPPED
    mode: TunnelMode = TunnelMode.PRIMARY
    remote_address: str = ""
    connected_since: str | None = None
    last_heartbeat_at: str | None = None
    bytes_sent: int = 0
    bytes_received: int = 0
    requests_forwarded: int = 0
    reconnect_count: int = 0
    last_error: str | None = None
    uptime_seconds: float = 0.0


@dataclass
class _PendingRequest:
    """Tracks an in-flight HTTP request through the tunnel."""
    request_id: int
    tcp_writer: asyncio.StreamWriter
    created_at: float = field(default_factory=time.monotonic)


class BtTunnel:
    """Bidirectional TCP ↔ Bluetooth RFCOMM tunnel.

    Manages the full lifecycle: discovery, connection,
    data forwarding, heartbeat, and reconnection.
    """

    def __init__(
        self,
        mode: str = "primary",
        remote_bt_addr: str = "",
        tunnel_port: int = DEFAULT_TUNNEL_PORT,
        local_api_port: int = DEFAULT_API_PORT,
        service_uuid: str = SERVICE_UUID,
        on_state_change: Callable[[TunnelState], None] | None = None,
    ):
        self.mode = TunnelMode(mode)
        self.remote_bt_addr = remote_bt_addr
        self.tunnel_port = tunnel_port
        self.local_api_port = local_api_port
        self.service_uuid = service_uuid
        self._on_state_change = on_state_change

        # Runtime state
        self._state = TunnelState.STOPPED
        self._bt_sock: socket.socket | None = None
        self._listen_sock: socket.socket | None = None
        self._tcp_server: asyncio.Server | None = None
        self._running = False
        self._bt_thread: threading.Thread | None = None
        self._heartbeat_task: asyncio.Task[Any] | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._lock = threading.Lock()

        # Statistics
        self._stats = TunnelStats(mode=self.mode)
        self._connected_at: float = 0.0
        self._request_counter = 0
        self._pending_requests: dict[int, _PendingRequest] = {}

    # ── Public API ──────────────────────────────────────────────

    @property
    def state(self) -> TunnelState:
        return self._state

    @property
    def is_connected(self) -> bool:
        return self._state == TunnelState.CONNECTED

    def get_stats(self) -> TunnelStats:
        """Get current tunnel statistics."""
        stats = TunnelStats(
            state=self._state,
            mode=self.mode,
            remote_address=self.remote_bt_addr,
            connected_since=self._stats.connected_since,
            last_heartbeat_at=self._stats.last_heartbeat_at,
            bytes_sent=self._stats.bytes_sent,
            bytes_received=self._stats.bytes_received,
            requests_forwarded=self._stats.requests_forwarded,
            reconnect_count=self._stats.reconnect_count,
            last_error=self._stats.last_error,
        )
        if self._connected_at > 0:
            stats.uptime_seconds = time.monotonic() - self._connected_at
        return stats

    async def start(self) -> None:
        """Start the tunnel in the appropriate mode.

        For PRIMARY: starts BT listener in a background thread,
        then waits for a secondary to connect.

        For SECONDARY: connects to the primary via BT, then starts
        a local TCP server on tunnel_port for the sync job to hit.
        """
        if self._running:
            logger.warning("Tunnel already running")
            return

        self._running = True
        self._set_state(TunnelState.STARTING)

        # Run the blocking BT operations in a background thread
        self._bt_thread = threading.Thread(
            target=self._run_tunnel_thread,
            daemon=True,
            name=f"bt-tunnel-{self.mode.value}",
        )
        self._bt_thread.start()

    async def stop(self) -> None:
        """Gracefully stop the tunnel."""
        logger.info("Stopping BT tunnel (%s mode)", self.mode.value)
        self._running = False

        # Close the TCP server
        if self._tcp_server:
            self._tcp_server.close()
            self._tcp_server = None

        # Cancel heartbeat
        if self._heartbeat_task and not self._heartbeat_task.done():
            self._heartbeat_task.cancel()

        # Close BT sockets
        close_socket(self._bt_sock)
        self._bt_sock = None
        close_socket(self._listen_sock)
        self._listen_sock = None

        self._set_state(TunnelState.STOPPED)

    # ── Background Thread (blocking BT I/O) ─────────────────────

    def _run_tunnel_thread(self) -> None:
        """Main tunnel loop running in a background thread.

        Handles connection establishment and reconnection.
        BT socket operations are blocking, which is fine in a thread.
        """
        reconnect_idx = 0

        while self._running:
            try:
                if self.mode == TunnelMode.PRIMARY:
                    self._run_primary()
                else:
                    self._run_secondary()
            except Exception as e:
                self._stats.last_error = str(e)
                logger.exception("BT tunnel error (%s): %s", self.mode.value, e)

            if not self._running:
                break

            # Reconnection backoff
            self._set_state(TunnelState.RECONNECTING)
            delay = RECONNECT_DELAYS[min(reconnect_idx, len(RECONNECT_DELAYS) - 1)]
            self._stats.reconnect_count += 1
            reconnect_idx += 1
            logger.info("Reconnecting in %ds (attempt %d)", delay, self._stats.reconnect_count)
            time.sleep(delay)

        self._set_state(TunnelState.STOPPED)

    def _run_primary(self) -> None:
        """Primary mode: listen for secondary, then forward data."""
        self._set_state(TunnelState.LISTENING)
        logger.info("Primary: starting RFCOMM listener (UUID: %s)", self.service_uuid)

        self._listen_sock = rfcomm_listen(self.service_uuid)
        try:
            # Accept one connection (blocking)
            self._bt_sock, remote_addr = rfcomm_accept(self._listen_sock, timeout=None)
            self.remote_bt_addr = remote_addr
            self._on_connected()

            # Forward loop: read from BT, forward to local API
            self._primary_forward_loop()

        finally:
            close_socket(self._bt_sock)
            self._bt_sock = None
            close_socket(self._listen_sock)
            self._listen_sock = None

    def _run_secondary(self) -> None:
        """Secondary mode: connect to primary, start local TCP forwarder."""
        if not self.remote_bt_addr:
            logger.error("Secondary: no remote_bt_addr configured")
            time.sleep(5)
            return

        self._set_state(TunnelState.CONNECTING)
        logger.info("Secondary: connecting to %s", self.remote_bt_addr)

        self._bt_sock = rfcomm_connect(self.remote_bt_addr, self.service_uuid)
        self._on_connected()

        try:
            # Start TCP listener in an async event loop for the sync job
            loop = asyncio.new_event_loop()
            self._loop = loop
            loop.run_until_complete(self._secondary_serve(loop))
        finally:
            close_socket(self._bt_sock)
            self._bt_sock = None
            if self._loop:
                self._loop.close()
                self._loop = None

    # ── Primary: BT → TCP forwarding ─────────────────────────────

    def _primary_forward_loop(self) -> None:
        """Read HTTP requests from BT, forward to local FastAPI, return responses."""
        while self._running and self._bt_sock:
            try:
                # Read a framed message from the secondary
                data = rfcomm_recv(self._bt_sock)
                self._stats.bytes_received += len(data)

                if is_heartbeat(data):
                    self._stats.last_heartbeat_at = datetime.now(timezone.utc).isoformat()
                    # Reply with heartbeat
                    send_heartbeat(self._bt_sock)
                    self._stats.bytes_sent += 8
                    continue

                # Parse the tunneled HTTP request
                request = json.loads(data.decode("utf-8"))
                request_id = request.get("_request_id", 0)

                # Forward to local API
                response_data = self._forward_to_local_api(request)
                response_data["_request_id"] = request_id

                # Send response back over BT
                resp_bytes = json.dumps(response_data).encode("utf-8")
                rfcomm_send(self._bt_sock, resp_bytes)
                self._stats.bytes_sent += len(resp_bytes)
                self._stats.requests_forwarded += 1

            except (ConnectionError, OSError) as e:
                logger.warning("Primary: BT connection lost: %s", e)
                break
            except Exception as e:
                logger.exception("Primary: error in forward loop: %s", e)
                # Try to send error response
                try:
                    if self._bt_sock:
                        err = json.dumps({"error": str(e), "status_code": 500}).encode()
                        rfcomm_send(self._bt_sock, err)
                except Exception:
                    break

    def _forward_to_local_api(self, request: dict[str, Any]) -> dict[str, Any]:
        """Forward an HTTP-like request to the local FastAPI server.

        Request format:
            {"method": "POST", "path": "/api/sync/push", "body": {...}, "headers": {...}}

        Returns:
            {"status_code": 200, "body": {...}}
        """
        import http.client

        method = request.get("method", "GET")
        path = request.get("path", "/")
        body = request.get("body")
        headers = request.get("headers", {})

        # Add standard headers
        if "Content-Type" not in headers:
            headers["Content-Type"] = "application/json"
        if "Host" not in headers:
            headers["Host"] = f"localhost:{self.local_api_port}"

        conn = http.client.HTTPConnection("127.0.0.1", self.local_api_port, timeout=30)
        try:
            body_str = json.dumps(body) if body is not None else None
            conn.request(method, path, body=body_str, headers=headers)
            response = conn.getresponse()

            resp_body_raw = response.read().decode("utf-8")
            try:
                resp_body = json.loads(resp_body_raw)
            except (json.JSONDecodeError, ValueError):
                resp_body = resp_body_raw

            return {
                "status_code": response.status,
                "headers": dict(response.getheaders()),
                "body": resp_body,
            }
        except Exception as e:
            logger.error("Failed to forward to local API: %s", e)
            return {"status_code": 502, "body": {"error": f"Local API unreachable: {e}"}}
        finally:
            conn.close()

    # ── Secondary: TCP → BT forwarding ───────────────────────────

    async def _secondary_serve(self, loop: asyncio.AbstractEventLoop) -> None:
        """Start a local TCP server that forwards requests through BT tunnel."""

        async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
            """Handle a connection from the local sync job."""
            try:
                # Read the full HTTP request
                request_data = await self._read_http_request(reader)
                if not request_data:
                    writer.close()
                    return

                # Assign a request ID for matching responses
                self._request_counter += 1
                request_data["_request_id"] = self._request_counter

                # Send through BT tunnel (blocking call in executor)
                response = await loop.run_in_executor(
                    None, self._send_via_bt, request_data
                )

                # Write HTTP response back to the TCP client
                await self._write_http_response(writer, response)

            except Exception as e:
                logger.error("Secondary: client handler error: %s", e)
                try:
                    error_body = json.dumps({"error": str(e)}).encode()
                    response_line = b"HTTP/1.1 502 Bad Gateway\r\n"
                    headers = f"Content-Type: application/json\r\nContent-Length: {len(error_body)}\r\n\r\n"
                    writer.write(response_line + headers.encode() + error_body)
                    await writer.drain()
                except Exception:
                    pass
            finally:
                try:
                    writer.close()
                    await writer.wait_closed()
                except Exception:
                    pass

        server = await asyncio.start_server(
            handle_client, "127.0.0.1", self.tunnel_port
        )
        self._tcp_server = server
        logger.info("Secondary: TCP tunnel listening on 127.0.0.1:%d", self.tunnel_port)

        # Also start heartbeat
        self._heartbeat_task = loop.create_task(self._heartbeat_loop())

        # Also start a BT reader for unsolicited messages (heartbeat responses)
        bt_reader_task = loop.create_task(self._secondary_bt_reader(loop))

        try:
            async with server:
                await server.serve_forever()
        except asyncio.CancelledError:
            pass
        finally:
            bt_reader_task.cancel()

    async def _read_http_request(self, reader: asyncio.StreamReader) -> dict[str, Any] | None:
        """Read a raw HTTP request from a TCP stream and parse into a dict."""
        try:
            # Read the request line and headers
            request_line = await asyncio.wait_for(reader.readline(), timeout=30)
            if not request_line:
                return None

            request_str = request_line.decode("utf-8").strip()
            parts = request_str.split(" ", 2)
            if len(parts) < 2:
                return None

            method = parts[0]
            path = parts[1]

            # Read headers
            headers: dict[str, str] = {}
            while True:
                line = await asyncio.wait_for(reader.readline(), timeout=10)
                line_str = line.decode("utf-8").strip()
                if not line_str:
                    break
                if ":" in line_str:
                    key, value = line_str.split(":", 1)
                    headers[key.strip()] = value.strip()

            # Read body if present
            body = None
            content_length = int(headers.get("Content-Length", "0"))
            if content_length > 0:
                body_bytes = await asyncio.wait_for(
                    reader.readexactly(content_length), timeout=30
                )
                try:
                    body = json.loads(body_bytes.decode("utf-8"))
                except (json.JSONDecodeError, ValueError):
                    body = body_bytes.decode("utf-8")

            return {
                "method": method,
                "path": path,
                "headers": headers,
                "body": body,
            }

        except (asyncio.TimeoutError, asyncio.IncompleteReadError):
            return None

    async def _write_http_response(
        self, writer: asyncio.StreamWriter, response: dict[str, Any]
    ) -> None:
        """Write a tunneled response as a raw HTTP response to the TCP client."""
        status_code = response.get("status_code", 200)
        body = response.get("body", "")

        if isinstance(body, (dict, list)):
            body_bytes = json.dumps(body).encode("utf-8")
            content_type = "application/json"
        else:
            body_bytes = str(body).encode("utf-8")
            content_type = "text/plain"

        # Build HTTP response
        status_text = {200: "OK", 201: "Created", 204: "No Content",
                       400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
                       404: "Not Found", 500: "Internal Server Error",
                       502: "Bad Gateway"}.get(status_code, "OK")

        response_line = f"HTTP/1.1 {status_code} {status_text}\r\n"
        resp_headers = (
            f"Content-Type: {content_type}\r\n"
            f"Content-Length: {len(body_bytes)}\r\n"
            f"Connection: close\r\n"
            f"\r\n"
        )

        writer.write(response_line.encode() + resp_headers.encode() + body_bytes)
        await writer.drain()

    def _send_via_bt(self, request: dict[str, Any]) -> dict[str, Any]:
        """Send an HTTP request through the BT tunnel (blocking, runs in executor)."""
        if not self._bt_sock:
            return {"status_code": 503, "body": {"error": "BT tunnel not connected"}}

        try:
            req_bytes = json.dumps(request).encode("utf-8")
            with self._lock:
                rfcomm_send(self._bt_sock, req_bytes)
                self._stats.bytes_sent += len(req_bytes)

                # Wait for response
                resp_bytes = rfcomm_recv(self._bt_sock)
                self._stats.bytes_received += len(resp_bytes)

            # Skip heartbeats
            if is_heartbeat(resp_bytes):
                self._stats.last_heartbeat_at = datetime.now(timezone.utc).isoformat()
                # Re-read for actual response
                with self._lock:
                    resp_bytes = rfcomm_recv(self._bt_sock)
                    self._stats.bytes_received += len(resp_bytes)

            self._stats.requests_forwarded += 1
            return json.loads(resp_bytes.decode("utf-8"))

        except Exception as e:
            logger.error("BT send/recv failed: %s", e)
            return {"status_code": 503, "body": {"error": f"BT tunnel error: {e}"}}

    async def _heartbeat_loop(self) -> None:
        """Send periodic heartbeats to detect connection health."""
        while self._running and self._bt_sock:
            try:
                await asyncio.sleep(HEARTBEAT_INTERVAL)
                if self._bt_sock and self._running:
                    loop = asyncio.get_event_loop()
                    await loop.run_in_executor(None, self._send_heartbeat_sync)
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.warning("Heartbeat failed: %s", e)
                break

    def _send_heartbeat_sync(self) -> None:
        """Send heartbeat (blocking, for executor)."""
        if self._bt_sock:
            with self._lock:
                send_heartbeat(self._bt_sock)
                self._stats.bytes_sent += 8
            self._stats.last_heartbeat_at = datetime.now(timezone.utc).isoformat()

    async def _secondary_bt_reader(self, loop: asyncio.AbstractEventLoop) -> None:
        """Background task to handle unsolicited BT messages (heartbeats)."""
        # This is needed if the primary sends heartbeats or push notifications
        # For now, heartbeats are request/response, so this is mostly a sentinel
        while self._running:
            await asyncio.sleep(1)

    # ── Helpers ───────────────────────────────────────────────────

    def _on_connected(self) -> None:
        """Called when BT connection is established."""
        self._connected_at = time.monotonic()
        self._stats.connected_since = datetime.now(timezone.utc).isoformat()
        self._set_state(TunnelState.CONNECTED)
        logger.info("BT tunnel connected (%s → %s)", self.mode.value, self.remote_bt_addr)

    def _set_state(self, new_state: TunnelState) -> None:
        """Update tunnel state and notify listener."""
        old = self._state
        self._state = new_state
        self._stats.state = new_state
        if old != new_state:
            logger.debug("Tunnel state: %s → %s", old.value, new_state.value)
            if self._on_state_change:
                try:
                    self._on_state_change(new_state)
                except Exception:
                    pass


# ── Convenience Factory ───────────────────────────────────────────

def create_tunnel(
    mode: str,
    remote_bt_addr: str = "",
    tunnel_port: int = DEFAULT_TUNNEL_PORT,
    local_api_port: int = DEFAULT_API_PORT,
    on_state_change: Callable[[TunnelState], None] | None = None,
) -> BtTunnel:
    """Create a BT tunnel instance.

    Args:
        mode: "primary" or "secondary"
        remote_bt_addr: BT address to connect to (secondary only)
        tunnel_port: Local TCP port for the tunnel (secondary only, default 9000)
        local_api_port: Local FastAPI port (default 8000)
        on_state_change: Optional callback for state changes

    Returns:
        Configured BtTunnel instance (call .start() to begin)
    """
    return BtTunnel(
        mode=mode,
        remote_bt_addr=remote_bt_addr,
        tunnel_port=tunnel_port,
        local_api_port=local_api_port,
        on_state_change=on_state_change,
    )


# ── Standalone test ───────────────────────────────────────────────

if __name__ == "__main__":
    import sys

    logging.basicConfig(level=logging.DEBUG, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

    if len(sys.argv) < 2:
        print("Usage:")
        print("  Primary:   python bt_tunnel.py primary")
        print("  Secondary: python bt_tunnel.py secondary AA:BB:CC:DD:EE:FF")
        sys.exit(1)

    mode = sys.argv[1]
    addr = sys.argv[2] if len(sys.argv) > 2 else ""

    tunnel = create_tunnel(mode=mode, remote_bt_addr=addr)

    async def main():
        await tunnel.start()
        try:
            while True:
                await asyncio.sleep(5)
                stats = tunnel.get_stats()
                print(f"  State: {stats.state.value} | "
                      f"Sent: {stats.bytes_sent}B | Recv: {stats.bytes_received}B | "
                      f"Requests: {stats.requests_forwarded}")
        except KeyboardInterrupt:
            await tunnel.stop()

    asyncio.run(main())
