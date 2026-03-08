"""Tests for bootstrap shell pairing and artifact handoff endpoints."""

from __future__ import annotations

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_pairing_code_and_handshake_flow(auth_client: AsyncClient):
    # Admin creates pairing code
    resp = await auth_client.post(
        "/api/bootstrap/pairing-codes",
        json={"ttl_minutes": 30, "notes": "bootstrap test"},
    )
    assert resp.status_code == 200, resp.text
    code = resp.json()["data"]["code"]

    # Register active artifact for platform
    resp = await auth_client.post(
        "/api/bootstrap/artifacts",
        json={
            "platform": "android",
            "version": "1.0.0",
            "manifest": {"bundle": "wiredpart.apk", "size": 12345},
            "download_url": "http://shop.local/downloads/wiredpart-1.0.0.apk",
            "checksum_sha256": "abc123def456",
            "signature": "sig-test",
            "min_bootstrap_version": "0.0.0-bootstrap",
        },
    )
    assert resp.status_code == 200, resp.text

    # Bootstrap app does handshake without auth, using pairing code
    anon = AsyncClient(base_url="http://test", transport=auth_client._transport)
    try:
        resp = await anon.post(
            "/api/bootstrap/handshake",
            json={
                "pairing_code": code,
                "device_id": "bootstrap-device-001",
                "device_name": "Samsung A53",
                "platform": "android",
                "bootstrap_version": "0.0.0-bootstrap",
                "public_key": "pubkey-test",
            },
        )
    finally:
        await anon.aclose()

    assert resp.status_code == 200, resp.text
    data = resp.json()["data"]
    assert data["device_id"] == "bootstrap-device-001"
    assert data["artifact"] is not None
    assert data["artifact"]["platform"] == "android"
    assert data["artifact"]["version"] == "1.0.0"


@pytest.mark.asyncio
async def test_install_event_logging_and_listing(auth_client: AsyncClient):
    # Create pairing code
    resp = await auth_client.post(
        "/api/bootstrap/pairing-codes",
        json={"ttl_minutes": 15},
    )
    assert resp.status_code == 200
    code = resp.json()["data"]["code"]

    # Log install event (no auth endpoint; pairing code gated)
    anon = AsyncClient(base_url="http://test", transport=auth_client._transport)
    try:
        resp = await anon.post(
            "/api/bootstrap/install-events",
            json={
                "pairing_code": code,
                "device_id": "bootstrap-device-002",
                "platform": "ios",
                "artifact_id": None,
                "status": "requested",
                "metadata": {"step": "download-start"},
            },
        )
    finally:
        await anon.aclose()

    assert resp.status_code == 200, resp.text
    event = resp.json()["data"]
    assert event["device_id"] == "bootstrap-device-002"
    assert event["status"] == "requested"

    # Admin can list events
    resp = await auth_client.get("/api/bootstrap/install-events", params={"device_id": "bootstrap-device-002"})
    assert resp.status_code == 200, resp.text
    rows = resp.json()["data"]
    assert len(rows) >= 1


@pytest.mark.asyncio
async def test_pairing_code_listing(auth_client: AsyncClient):
    # Create multiple pairing codes
    for i in range(2):
        resp = await auth_client.post(
            "/api/bootstrap/pairing-codes",
            json={"ttl_minutes": 10 + i, "notes": f"code-{i}"},
        )
        assert resp.status_code == 200, resp.text

    resp = await auth_client.get("/api/bootstrap/pairing-codes", params={"limit": 10})
    assert resp.status_code == 200, resp.text
    rows = resp.json()["data"]
    assert len(rows) >= 2
    assert "code" in rows[0]
    assert "expires_at" in rows[0]
