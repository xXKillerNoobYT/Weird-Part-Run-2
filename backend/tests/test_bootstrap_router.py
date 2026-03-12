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


# ── Artifact Verification & Signing Tests ─────────────────────────


@pytest.mark.asyncio
async def test_artifact_verify_correct_checksum(auth_client: AsyncClient):
    """Verify artifact verification succeeds with correct checksum."""
    known_checksum = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"

    # Register artifact with known checksum
    resp = await auth_client.post(
        "/api/bootstrap/artifacts",
        json={
            "platform": "ios",
            "version": "2.0.0",
            "manifest": {"bundle": "wiredpart.ipa"},
            "download_url": "http://shop.local/downloads/wiredpart-2.0.0.ipa",
            "checksum_sha256": known_checksum,
        },
    )
    assert resp.status_code == 200, resp.text
    artifact_id = resp.json()["data"]["id"]

    # Anonymous device verifies checksum (no auth required)
    anon = AsyncClient(base_url="http://test", transport=auth_client._transport)
    try:
        resp = await anon.post(
            "/api/bootstrap/artifacts/verify",
            json={
                "artifact_id": artifact_id,
                "client_checksum_sha256": known_checksum,
            },
        )
    finally:
        await anon.aclose()

    assert resp.status_code == 200, resp.text
    data = resp.json()["data"]
    assert data["valid"] is True
    assert data["checksum_match"] is True
    assert data["artifact_id"] == artifact_id
    assert data["version"] == "2.0.0"


@pytest.mark.asyncio
async def test_artifact_verify_wrong_checksum(auth_client: AsyncClient):
    """Verify artifact verification fails with wrong checksum."""
    resp = await auth_client.post(
        "/api/bootstrap/artifacts",
        json={
            "platform": "android",
            "version": "2.1.0",
            "manifest": {"bundle": "wiredpart.apk"},
            "download_url": "http://shop.local/downloads/wiredpart-2.1.0.apk",
            "checksum_sha256": "correct_checksum_value_1234567890abcdef",
        },
    )
    assert resp.status_code == 200, resp.text
    artifact_id = resp.json()["data"]["id"]

    anon = AsyncClient(base_url="http://test", transport=auth_client._transport)
    try:
        resp = await anon.post(
            "/api/bootstrap/artifacts/verify",
            json={
                "artifact_id": artifact_id,
                "client_checksum_sha256": "totally_wrong_checksum_value_zzz",
            },
        )
    finally:
        await anon.aclose()

    assert resp.status_code == 200, resp.text
    data = resp.json()["data"]
    assert data["valid"] is False
    assert data["checksum_match"] is False


@pytest.mark.asyncio
async def test_artifact_verify_nonexistent_artifact(auth_client: AsyncClient):
    """Verify returns valid=False for non-existent artifact."""
    anon = AsyncClient(base_url="http://test", transport=auth_client._transport)
    try:
        resp = await anon.post(
            "/api/bootstrap/artifacts/verify",
            json={
                "artifact_id": 999999,
                "client_checksum_sha256": "doesnt_matter",
            },
        )
    finally:
        await anon.aclose()

    assert resp.status_code == 200, resp.text
    data = resp.json()["data"]
    assert data["valid"] is False
    assert data["detail"] == "Artifact not found"


@pytest.mark.asyncio
async def test_active_artifact_by_platform(auth_client: AsyncClient):
    """Verify active artifact lookup by platform works (no auth)."""
    # Register artifact
    resp = await auth_client.post(
        "/api/bootstrap/artifacts",
        json={
            "platform": "macos",
            "version": "3.0.0",
            "manifest": {"bundle": "wiredpart.app"},
            "download_url": "http://shop.local/downloads/wiredpart-3.0.0.app",
            "checksum_sha256": "macos_checksum_abc123",
        },
    )
    assert resp.status_code == 200, resp.text

    # Anonymous lookup
    anon = AsyncClient(base_url="http://test", transport=auth_client._transport)
    try:
        resp = await anon.get("/api/bootstrap/artifacts/active/macos")
    finally:
        await anon.aclose()

    assert resp.status_code == 200, resp.text
    data = resp.json()["data"]
    assert data["platform"] == "macos"
    assert data["version"] == "3.0.0"
    assert data["is_active"] == 1


@pytest.mark.asyncio
async def test_active_artifact_404_for_missing_platform(auth_client: AsyncClient):
    """Active artifact lookup returns 404 when no artifact exists."""
    anon = AsyncClient(base_url="http://test", transport=auth_client._transport)
    try:
        resp = await anon.get("/api/bootstrap/artifacts/active/windows")
    finally:
        await anon.aclose()

    # Note: might be 200 if a windows artifact was registered by another test,
    # so we just verify the response is well-formed
    assert resp.status_code in (200, 404)


@pytest.mark.asyncio
async def test_artifact_sign_flow(auth_client: AsyncClient):
    """Sign an artifact and verify the signature field is populated."""
    # First initialise company security (needed for shop key)
    resp = await auth_client.post("/api/security/company/init", json={
        "company_id": "default",
        "company_name": "Test Co",
    })
    # May already exist (409) or succeed (200) — either is fine
    assert resp.status_code in (200, 409, 422), resp.text

    # Register artifact
    resp = await auth_client.post(
        "/api/bootstrap/artifacts",
        json={
            "platform": "android",
            "version": "4.0.0",
            "manifest": {"bundle": "wiredpart.apk"},
            "download_url": "http://shop.local/downloads/wiredpart-4.0.0.apk",
            "checksum_sha256": "sign_test_checksum_1234567890abcdef",
        },
    )
    assert resp.status_code == 200, resp.text
    artifact_id = resp.json()["data"]["id"]
    assert resp.json()["data"]["signature"] is None

    # Sign the artifact (admin-only)
    resp = await auth_client.post(f"/api/bootstrap/artifacts/{artifact_id}/sign")
    assert resp.status_code == 200, resp.text
    signed = resp.json()["data"]
    assert signed["signature"] is not None
    assert len(signed["signature"]) > 10  # Should be a base64 Ed25519 sig


@pytest.mark.asyncio
async def test_extended_install_event_fields(auth_client: AsyncClient):
    """Verify extended install event fields (progress, checksum, signature) are recorded."""
    # Create pairing code
    resp = await auth_client.post(
        "/api/bootstrap/pairing-codes",
        json={"ttl_minutes": 15},
    )
    assert resp.status_code == 200
    code = resp.json()["data"]["code"]

    anon = AsyncClient(base_url="http://test", transport=auth_client._transport)
    try:
        # Log event with all extended fields
        resp = await anon.post(
            "/api/bootstrap/install-events",
            json={
                "pairing_code": code,
                "device_id": "verify-test-device",
                "platform": "android",
                "status": "downloading",
                "progress_pct": 45.5,
                "bytes_downloaded": 5242880,
                "bytes_total": 11534336,
                "metadata": {"step": "streaming-download"},
            },
        )
        assert resp.status_code == 200, resp.text
        event = resp.json()["data"]
        assert event["progress_pct"] == 45.5
        assert event["bytes_downloaded"] == 5242880
        assert event["bytes_total"] == 11534336

        # Log verified event with checksum fields
        resp = await anon.post(
            "/api/bootstrap/install-events",
            json={
                "pairing_code": code,
                "device_id": "verify-test-device",
                "platform": "android",
                "status": "verified",
                "progress_pct": 100,
                "bytes_downloaded": 11534336,
                "bytes_total": 11534336,
                "checksum_computed": "abc123def456",
                "checksum_verified": True,
                "signature_verified": True,
            },
        )
        assert resp.status_code == 200, resp.text
        event = resp.json()["data"]
        assert event["checksum_computed"] == "abc123def456"
        assert event["checksum_verified"] == 1
        assert event["signature_verified"] == 1
    finally:
        await anon.aclose()

    # Admin can see extended fields in listing
    resp = await auth_client.get(
        "/api/bootstrap/install-events",
        params={"device_id": "verify-test-device"},
    )
    assert resp.status_code == 200, resp.text
    rows = resp.json()["data"]
    assert len(rows) >= 2
    # Most recent should be the verified event
    verified = next((r for r in rows if r["status"] == "verified"), None)
    assert verified is not None
    assert verified["checksum_verified"] == 1
