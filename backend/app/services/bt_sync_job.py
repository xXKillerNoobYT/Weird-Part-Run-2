"""
Bluetooth sync job — Scheduled task that syncs data through the BT tunnel.

When a BT tunnel is active, this job performs the same push/pull sync
that a mobile device does over HTTP — except the traffic goes through
the RFCOMM tunnel to the primary's FastAPI server.

Architecture:
  Secondary PC:  bt_sync_job → HTTP to localhost:9000 (tunnel port)
                 → BT RFCOMM → Primary's localhost:8000 (FastAPI)

This job:
1. Checks if a BT tunnel is connected
2. Reads local changes from _shop_change_log
3. POSTs them to the primary's /api/sync/push (via tunnel)
4. Applies returned shop changes locally
5. ACKs the sync batch

The secondary registers itself as a "device" in the primary's device
registry, using a stable device ID derived from the machine.
"""

from __future__ import annotations

import json
import logging
import platform
import socket
import uuid
from datetime import datetime, timezone
from typing import Any

import aiosqlite

logger = logging.getLogger(__name__)


def _get_device_id() -> str:
    """Generate a stable device ID for this machine.

    Uses hostname + MAC address hash to produce a repeatable ID.
    """
    hostname = socket.gethostname()
    mac = uuid.getnode()
    return f"bt-{hostname}-{mac:012x}"


def _get_device_name() -> str:
    """Human-readable device name."""
    return f"{socket.gethostname()} ({platform.system()})"


async def bt_sync_job() -> None:
    """Scheduled job: sync data over the BT tunnel.

    Runs every N seconds (configurable via bt_sync_interval setting).
    Only does work if a BT tunnel is active and connected.
    """
    # Lazy imports to avoid circular dependencies
    from app.database import get_connection
    from app.services.bluetooth_service import get_tunnel

    tunnel = get_tunnel()
    if tunnel is None:
        return  # No active tunnel, nothing to do

    # Check tunnel state
    if not hasattr(tunnel, "state") or str(tunnel.state.value) != "connected":
        return  # Tunnel not connected

    # Only secondary syncs TO primary
    if hasattr(tunnel, "mode") and str(tunnel.mode.value) != "secondary":
        return  # Primary doesn't initiate sync — it receives

    db = await get_connection()
    try:
        await _run_sync_cycle(db, tunnel)
    except Exception:
        logger.exception("BT sync job failed")
    finally:
        await db.close()


async def _run_sync_cycle(
    db: aiosqlite.Connection,
    tunnel: Any,
) -> None:
    """Execute one push/pull sync cycle through the BT tunnel.

    Uses httpx-style calls to the tunnel's local proxy port.
    The tunnel forwards these to the primary's FastAPI server.
    """
    import http.client

    # Get tunnel port (secondary's local TCP → BT bridge)
    tunnel_port = getattr(tunnel, "tunnel_port", 9000)
    device_id = _get_device_id()
    device_name = _get_device_name()

    logger.info(
        "BT sync starting (device=%s, tunnel_port=%d)",
        device_id, tunnel_port,
    )

    # ── Step 1: Register device (idempotent) ──────────────────
    try:
        _api_post(tunnel_port, "/api/sync/register", {
            "device_id": device_id,
            "device_name": device_name,
            "platform": "windows",
        })
    except Exception as e:
        logger.warning("Device registration failed (may already exist): %s", e)

    # ── Step 2: Gather local changes ──────────────────────────
    last_sync_at = await _get_last_sync_timestamp(db)
    changes = await _get_local_changes(db, since=last_sync_at)

    logger.info(
        "Pushing %d local changes (since %s)",
        len(changes), last_sync_at or "never",
    )

    # ── Step 3: Push changes to primary ───────────────────────
    push_payload = {
        "device_id": device_id,
        "device_name": device_name,
        "platform": "windows",
        "last_sync_at": last_sync_at,
        "changes": changes,
    }

    try:
        push_response = _api_post(tunnel_port, "/api/sync/push", push_payload)
    except Exception as e:
        logger.error("BT sync push failed: %s", e)
        return

    applied = push_response.get("applied", 0)
    conflicts = push_response.get("conflicts", [])
    shop_changes = push_response.get("shop_changes", [])
    batch_id = push_response.get("sync_batch_id", "")

    logger.info(
        "Push complete: applied=%d, conflicts=%d, shop_changes=%d, batch=%s",
        applied, len(conflicts), len(shop_changes), batch_id,
    )

    # ── Step 4: Apply shop changes locally ────────────────────
    applied_count = 0
    for change in shop_changes:
        try:
            await _apply_shop_change(db, change)
            applied_count += 1
        except Exception:
            logger.exception(
                "Failed to apply shop change: %s.%s",
                change.get("table_name"), change.get("record_id"),
            )

    if applied_count > 0:
        logger.info("Applied %d shop changes locally", applied_count)

    # ── Step 5: Acknowledge sync batch ────────────────────────
    if batch_id:
        try:
            _api_post(tunnel_port, "/api/sync/ack", {
                "device_id": device_id,
                "sync_batch_id": batch_id,
            })
        except Exception as e:
            logger.warning("Sync ACK failed: %s", e)

    # ── Step 6: Update sync timestamps ────────────────────────
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    await db.execute(
        "INSERT OR REPLACE INTO _bt_sync_state (key, value) VALUES ('last_sync_at', ?)",
        (now,),
    )
    await db.commit()

    # Update paired device's last_sync_at
    try:
        from app.repositories.bluetooth_repo import BluetoothRepo
        repo = BluetoothRepo(db)
        remote_addr = getattr(tunnel, "remote_addr", "")
        if remote_addr:
            paired = await repo.get_paired_device_by_address(remote_addr)
            if paired:
                await repo.touch_synced(paired["id"])
    except Exception:
        pass  # Non-critical

    total_changes = len(changes) + applied_count
    logger.info("BT sync complete: %d total changes exchanged", total_changes)


# ── HTTP helpers (via tunnel) ─────────────────────────────────────

def _api_post(port: int, path: str, payload: dict) -> dict:
    """Make an HTTP POST to the primary via the BT tunnel proxy.

    The tunnel listens on localhost:{port} and forwards to the
    primary's localhost:8000 over RFCOMM.
    """
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=30)
    try:
        body = json.dumps(payload).encode()
        conn.request("POST", path, body=body, headers={
            "Content-Type": "application/json",
            "Content-Length": str(len(body)),
        })
        resp = conn.getresponse()
        data = resp.read().decode()
        if resp.status >= 400:
            raise RuntimeError(f"API error {resp.status}: {data[:500]}")
        return json.loads(data) if data else {}
    finally:
        conn.close()


def _api_get(port: int, path: str) -> dict:
    """Make an HTTP GET to the primary via the BT tunnel proxy."""
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=30)
    try:
        conn.request("GET", path)
        resp = conn.getresponse()
        data = resp.read().decode()
        if resp.status >= 400:
            raise RuntimeError(f"API error {resp.status}: {data[:500]}")
        return json.loads(data) if data else {}
    finally:
        conn.close()


# ── Local DB helpers ──────────────────────────────────────────────

async def _get_last_sync_timestamp(db: aiosqlite.Connection) -> str | None:
    """Read the last successful BT sync timestamp from local state."""
    # Try bt-specific state table first
    try:
        async with db.execute(
            "SELECT value FROM _bt_sync_state WHERE key = 'last_sync_at'"
        ) as cur:
            row = await cur.fetchone()
            if row:
                return row[0]
    except Exception:
        pass  # Table might not exist yet

    return None


async def _get_local_changes(
    db: aiosqlite.Connection,
    since: str | None = None,
) -> list[dict]:
    """Read changes from _shop_change_log since the given timestamp.

    These are changes made locally that need to be pushed to the primary.
    """
    from app.services.sync_service import SYNCED_TABLES

    sql = "SELECT * FROM _shop_change_log"
    params: list[Any] = []

    if since:
        sql += " WHERE timestamp > ?"
        params.append(since)

    sql += " ORDER BY timestamp ASC, id ASC LIMIT 1000"

    try:
        async with db.execute(sql, params) as cur:
            rows = await cur.fetchall()
            changes = []
            for row in rows:
                d = dict(row)
                # Only include changes for synced tables
                if d.get("table_name") in SYNCED_TABLES:
                    changes.append({
                        "id": d.get("id"),
                        "table_name": d["table_name"],
                        "record_id": d["record_id"],
                        "operation": d["operation"],
                        "changed_fields": d.get("changed_fields"),
                        "old_values": d.get("old_values"),
                        "timestamp": d.get("timestamp", ""),
                    })
            return changes
    except Exception as e:
        logger.warning("Failed to read change log: %s", e)
        return []


async def _apply_shop_change(
    db: aiosqlite.Connection,
    change: dict,
) -> None:
    """Apply a single shop change to the local database.

    Handles INSERT, UPDATE, and DELETE operations.
    Uses last-writer-wins: shop changes always win on the secondary.
    """
    table_name = change.get("table_name")
    record_id = change.get("record_id")
    operation = change.get("operation", "").upper()
    row_data = change.get("row_data") or {}

    if not table_name or record_id is None:
        return

    if operation == "DELETE":
        await db.execute(
            f"DELETE FROM [{table_name}] WHERE id = ?",
            (record_id,),
        )

    elif operation == "INSERT":
        if row_data:
            cols = list(row_data.keys())
            placeholders = ", ".join(["?"] * len(cols))
            col_names = ", ".join(f"[{c}]" for c in cols)
            values = [row_data[c] for c in cols]
            await db.execute(
                f"INSERT OR REPLACE INTO [{table_name}] ({col_names}) "
                f"VALUES ({placeholders})",
                values,
            )

    elif operation == "UPDATE":
        changed_fields_raw = change.get("changed_fields")
        if changed_fields_raw:
            fields = (
                json.loads(changed_fields_raw)
                if isinstance(changed_fields_raw, str)
                else changed_fields_raw
            )
            if fields:
                set_clause = ", ".join(f"[{k}] = ?" for k in fields)
                values = [*fields.values(), record_id]
                await db.execute(
                    f"UPDATE [{table_name}] SET {set_clause} WHERE id = ?",
                    values,
                )

    await db.commit()
