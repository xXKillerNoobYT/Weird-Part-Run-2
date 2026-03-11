"""Tests for P2P relay transport: manifests, packages, delivery receipts, and relay stats."""

from __future__ import annotations

import pytest
from httpx import AsyncClient


# ── Helpers ──────────────────────────────────────────────────────

async def _register_device(client: AsyncClient, device_id: str, name: str, platform: str = "android"):
    resp = await client.post(
        "/api/sync/register",
        json={"device_id": device_id, "device_name": name, "platform": platform},
    )
    assert resp.status_code == 200, resp.text


# ── Relay Manifests ──────────────────────────────────────────────

@pytest.mark.asyncio
async def test_relay_manifest_upsert_and_read(auth_client: AsyncClient):
    """Upsert a relay manifest, then read it back."""
    await _register_device(auth_client, "relay-dev-A", "Device A")

    # Upsert manifest
    resp = await auth_client.post(
        "/api/sync/relay/manifests",
        json={
            "device_id": "relay-dev-A",
            "pending_change_count": 15,
            "pending_media_count": 3,
            "change_hashes": ["abc123", "def456"],
            "media_hashes": ["img001"],
            "origin_device_ids": ["relay-dev-B"],
        },
    )
    assert resp.status_code == 200, resp.text
    m = resp.json()["data"]
    assert m["device_id"] == "relay-dev-A"
    assert m["pending_change_count"] == 15
    assert "abc123" in m["change_hashes"]

    # Read back
    resp = await auth_client.get("/api/sync/relay/manifests/relay-dev-A")
    assert resp.status_code == 200, resp.text
    m = resp.json()["data"]
    assert m["pending_media_count"] == 3
    assert m["origin_device_ids"] == ["relay-dev-B"]


@pytest.mark.asyncio
async def test_relay_manifest_upsert_updates_existing(auth_client: AsyncClient):
    """Upserting a manifest for the same device updates it instead of duplicating."""
    await _register_device(auth_client, "relay-dev-C", "Device C")

    # First upsert
    await auth_client.post(
        "/api/sync/relay/manifests",
        json={"device_id": "relay-dev-C", "pending_change_count": 5, "pending_media_count": 0,
              "change_hashes": ["h1"], "media_hashes": [], "origin_device_ids": []},
    )

    # Second upsert (updated counts)
    resp = await auth_client.post(
        "/api/sync/relay/manifests",
        json={"device_id": "relay-dev-C", "pending_change_count": 12, "pending_media_count": 2,
              "change_hashes": ["h1", "h2", "h3"], "media_hashes": ["m1"], "origin_device_ids": ["remote-1"]},
    )
    assert resp.status_code == 200, resp.text
    m = resp.json()["data"]
    assert m["pending_change_count"] == 12
    assert len(m["change_hashes"]) == 3


@pytest.mark.asyncio
async def test_relay_manifest_list(auth_client: AsyncClient):
    """List all relay manifests (admin endpoint)."""
    await _register_device(auth_client, "relay-dev-D", "Device D")

    await auth_client.post(
        "/api/sync/relay/manifests",
        json={"device_id": "relay-dev-D", "pending_change_count": 7, "pending_media_count": 1,
              "change_hashes": ["x1"], "media_hashes": [], "origin_device_ids": []},
    )

    resp = await auth_client.get("/api/sync/relay/manifests")
    assert resp.status_code == 200, resp.text
    manifests = resp.json()["data"]
    assert isinstance(manifests, list)
    assert any(m["device_id"] == "relay-dev-D" for m in manifests)


# ── Relay Packages ───────────────────────────────────────────────

@pytest.mark.asyncio
async def test_relay_package_lifecycle(auth_client: AsyncClient):
    """Create a package, transition through statuses: created → transferred → confirmed."""
    await _register_device(auth_client, "relay-pkg-sender", "Sender")
    await _register_device(auth_client, "relay-pkg-receiver", "Receiver")
    await _register_device(auth_client, "relay-pkg-origin", "Origin")

    # Create package
    resp = await auth_client.post(
        "/api/sync/relay/packages",
        json={
            "sender_device_id": "relay-pkg-sender",
            "receiver_device_id": "relay-pkg-receiver",
            "origin_device_id": "relay-pkg-origin",
            "change_count": 25,
            "media_count": 4,
            "package_hash": "sha256-abc123def456",
        },
    )
    assert resp.status_code == 200, resp.text
    pkg = resp.json()["data"]
    pkg_id = pkg["id"]
    assert pkg["status"] == "created"
    assert pkg["change_count"] == 25

    # Mark transferred
    resp = await auth_client.put(
        f"/api/sync/relay/packages/{pkg_id}",
        json={"status": "transferred"},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["data"]["status"] == "transferred"

    # Mark confirmed
    resp = await auth_client.put(
        f"/api/sync/relay/packages/{pkg_id}",
        json={"status": "confirmed"},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["data"]["status"] == "confirmed"
    assert resp.json()["data"]["confirmed_at"] is not None


@pytest.mark.asyncio
async def test_relay_package_failure(auth_client: AsyncClient):
    """Create a package and mark it as failed with a reason."""
    await _register_device(auth_client, "relay-fail-s", "S")
    await _register_device(auth_client, "relay-fail-r", "R")

    resp = await auth_client.post(
        "/api/sync/relay/packages",
        json={
            "sender_device_id": "relay-fail-s",
            "receiver_device_id": "relay-fail-r",
            "origin_device_id": "relay-fail-s",
            "change_count": 10,
            "media_count": 0,
            "package_hash": "sha256-fail-test",
        },
    )
    pkg_id = resp.json()["data"]["id"]

    # Fail it
    resp = await auth_client.put(
        f"/api/sync/relay/packages/{pkg_id}",
        json={"status": "failed", "failure_reason": "BT connection lost mid-transfer"},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["data"]["status"] == "failed"
    assert resp.json()["data"]["failure_reason"] == "BT connection lost mid-transfer"


@pytest.mark.asyncio
async def test_relay_package_list_filtering(auth_client: AsyncClient):
    """List packages with device and status filters."""
    await _register_device(auth_client, "relay-list-s", "LS")
    await _register_device(auth_client, "relay-list-r", "LR")

    # Create two packages
    for i in range(2):
        await auth_client.post(
            "/api/sync/relay/packages",
            json={
                "sender_device_id": "relay-list-s",
                "receiver_device_id": "relay-list-r",
                "origin_device_id": "relay-list-s",
                "change_count": i + 1,
                "media_count": 0,
                "package_hash": f"hash-list-{i}",
            },
        )

    # List all
    resp = await auth_client.get("/api/sync/relay/packages")
    assert resp.status_code == 200
    all_pkgs = resp.json()["data"]
    assert len(all_pkgs) >= 2

    # Filter by device
    resp = await auth_client.get(
        "/api/sync/relay/packages",
        params={"device_id": "relay-list-s"},
    )
    assert resp.status_code == 200
    filtered = resp.json()["data"]
    assert all(
        p["sender_device_id"] == "relay-list-s" or p["receiver_device_id"] == "relay-list-s"
        for p in filtered
    )


# ── Delivery Receipts ───────────────────────────────────────────

@pytest.mark.asyncio
async def test_delivery_receipt_full_flow(auth_client: AsyncClient):
    """Deliver relayed data → receipt issued → acknowledge receipt."""
    await _register_device(auth_client, "relay-origin", "Origin Device")
    await _register_device(auth_client, "relay-courier", "Courier Device")

    # Log a relay event first (gossip from origin to courier)
    await auth_client.post(
        "/api/sync/mesh/relay-events",
        json={
            "source_device_id": "relay-origin",
            "peer_device_id": "relay-courier",
            "relay_type": "gossip",
            "carried_change_count": 10,
            "carried_media_count": 2,
            "undelivered_after_count": 0,
        },
    )

    # Courier delivers relayed data to shop
    resp = await auth_client.post(
        "/api/sync/relay/deliver",
        json={
            "delivering_device_id": "relay-courier",
            "origin_device_id": "relay-origin",
            "changes": [],  # Empty for simplicity; apply_device_changes handles []
            "relay_chain": ["relay-origin", "relay-courier"],
        },
    )
    assert resp.status_code == 200, resp.text
    result = resp.json()["data"]
    assert "applied" in result
    assert result["receipt"]["origin_device_id"] == "relay-origin"
    assert result["receipt"]["delivered_by_device_id"] == "relay-courier"
    receipt_id = result["receipt"]["id"]

    # Origin device checks pending receipts
    resp = await auth_client.get(
        f"/api/sync/relay/receipts/pending/relay-origin",
    )
    assert resp.status_code == 200, resp.text
    pending = resp.json()["data"]
    assert any(r["id"] == receipt_id for r in pending)

    # Origin acknowledges the receipt
    resp = await auth_client.post(
        "/api/sync/relay/receipts/acknowledge",
        json={"receipt_ids": [receipt_id]},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["data"]["acknowledged_count"] == 1

    # Confirm receipt is no longer pending
    resp = await auth_client.get(
        f"/api/sync/relay/receipts/pending/relay-origin",
    )
    assert resp.status_code == 200
    pending = resp.json()["data"]
    assert not any(r["id"] == receipt_id for r in pending)


@pytest.mark.asyncio
async def test_delivery_receipt_list_admin(auth_client: AsyncClient):
    """Admin can list all delivery receipts with optional filters."""
    resp = await auth_client.get(
        "/api/sync/relay/receipts",
        params={"limit": 50},
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()["data"]
    assert isinstance(data, list)


# ── Relay Stats ──────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_relay_stats_aggregate(auth_client: AsyncClient):
    """Stats endpoint returns aggregate relay metrics."""
    # Ensure there's some data from previous tests
    resp = await auth_client.get("/api/sync/relay/stats")
    assert resp.status_code == 200, resp.text
    stats = resp.json()["data"]
    assert "events_by_type" in stats
    assert "packages_by_status" in stats
    assert "receipts_by_status" in stats
    assert "active_manifests" in stats
    assert isinstance(stats["active_manifests"], int)


@pytest.mark.asyncio
async def test_relay_stats_per_device(auth_client: AsyncClient):
    """Stats endpoint filters by device_id when provided."""
    resp = await auth_client.get(
        "/api/sync/relay/stats",
        params={"device_id": "relay-dev-A"},
    )
    assert resp.status_code == 200, resp.text
    stats = resp.json()["data"]
    assert isinstance(stats["events_by_type"], list)
