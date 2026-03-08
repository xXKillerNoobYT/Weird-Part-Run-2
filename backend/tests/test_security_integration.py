"""
Tests for Device Security Integration — bootstrap cert auto-issue
and sync push certificate verification gate.
"""

from __future__ import annotations

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_bootstrap_handshake_auto_issues_cert(auth_client: AsyncClient):
    """Bootstrap handshake with a public_key should auto-issue a device cert.

    Flow:
    1. Admin creates pairing code
    2. Device performs handshake WITH a public_key
    3. Response includes a signed certificate
    """
    # Create pairing code
    resp = await auth_client.post(
        "/api/bootstrap/pairing-codes",
        json={"ttl_minutes": 15},
    )
    assert resp.status_code == 200, resp.text
    code = resp.json()["data"]["code"]

    # Perform bootstrap handshake with a public key
    resp = await auth_client.post(
        "/api/bootstrap/handshake",
        json={
            "pairing_code": code,
            "device_id": "bootstrap-cert-test-001",
            "device_name": "Test Tablet",
            "platform": "ios",
            "bootstrap_version": "1.0.0",
            "public_key": "dGVzdC1wdWJsaWMta2V5LWJhc2U2NA==",
        },
    )
    assert resp.status_code == 200, resp.text
    result = resp.json()["data"]

    # Certificate should be in response
    assert result["certificate"] is not None, "Expected auto-issued certificate"
    cert = result["certificate"]
    assert cert["device_id"] == "bootstrap-cert-test-001"
    assert cert["company_id"] == "default"
    assert cert["signature"]
    assert cert["certificate_data"]

    # Verify the cert is valid
    resp = await auth_client.post(
        "/api/security/certs/verify",
        json={
            "device_id": "bootstrap-cert-test-001",
            "company_id": "default",
            "certificate_data": cert["certificate_data"],
            "signature": cert["signature"],
        },
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["data"]["valid"] is True


@pytest.mark.asyncio
async def test_bootstrap_handshake_no_public_key_no_cert(auth_client: AsyncClient):
    """Bootstrap handshake without a public_key should NOT issue a cert."""
    # Create pairing code
    resp = await auth_client.post(
        "/api/bootstrap/pairing-codes",
        json={"ttl_minutes": 15},
    )
    code = resp.json()["data"]["code"]

    # Perform bootstrap handshake WITHOUT a public key
    resp = await auth_client.post(
        "/api/bootstrap/handshake",
        json={
            "pairing_code": code,
            "device_id": "bootstrap-no-cert-002",
            "device_name": "Legacy Device",
            "platform": "android",
            "bootstrap_version": "0.5.0",
        },
    )
    assert resp.status_code == 200, resp.text
    result = resp.json()["data"]

    # No certificate should be issued
    assert result["certificate"] is None


@pytest.mark.asyncio
async def test_sync_push_requires_cert_when_security_enabled(auth_client: AsyncClient):
    """When company keys exist, sync push should require a valid certificate.

    Flow:
    1. Initialise company (enables security)
    2. Register device + issue cert
    3. Sync push WITHOUT cert → rejected
    4. Sync push WITH valid cert → accepted
    """
    # ── 1. Init company ──────────────────────────────────────────
    await auth_client.post(
        "/api/security/company/init",
        json={"company_id": "sync-co", "company_name": "Sync Corp"},
    )

    # ── 2. Register device + issue cert ──────────────────────────
    await auth_client.post(
        "/api/sync/register",
        json={"device_id": "sync-device-001", "device_name": "Field Phone", "platform": "ios"},
    )

    resp = await auth_client.post(
        "/api/security/certs/issue",
        json={
            "device_id": "sync-device-001",
            "company_id": "sync-co",
            "device_public_key": "c3luYy10ZXN0LWtleQ==",
        },
    )
    cert = resp.json()["data"]

    # ── 3. Push WITHOUT cert → rejected ──────────────────────────
    resp = await auth_client.post(
        "/api/sync/push",
        json={
            "device_id": "sync-device-001",
            "last_sync_at": "",
            "changes": [],
        },
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["data"] is None, "Expected rejection when cert missing"
    assert "Security enabled" in body.get("message", "")

    # ── 4. Push WITH valid cert → accepted ───────────────────────
    resp = await auth_client.post(
        "/api/sync/push",
        json={
            "device_id": "sync-device-001",
            "last_sync_at": "",
            "changes": [],
            "company_id": "sync-co",
            "certificate_data": cert["certificate_data"],
            "signature": cert["signature"],
        },
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["data"] is not None, "Expected sync push to succeed with valid cert"
    assert "sync_batch_id" in body["data"]


@pytest.mark.asyncio
async def test_sync_push_rejects_revoked_cert(auth_client: AsyncClient):
    """Sync push with a revoked certificate should be rejected."""
    # Init company + register device + issue cert
    await auth_client.post(
        "/api/security/company/init",
        json={"company_id": "revoke-co", "company_name": "Revoke Corp"},
    )
    await auth_client.post(
        "/api/sync/register",
        json={"device_id": "revoke-device-001", "device_name": "Phone X", "platform": "android"},
    )
    resp = await auth_client.post(
        "/api/security/certs/issue",
        json={
            "device_id": "revoke-device-001",
            "company_id": "revoke-co",
            "device_public_key": "cmV2b2tlLXRlc3Q=",
        },
    )
    cert = resp.json()["data"]

    # Revoke the cert
    await auth_client.post(
        "/api/security/certs/revoke",
        json={
            "device_id": "revoke-device-001",
            "company_id": "revoke-co",
            "reason": "test_revoke",
        },
    )

    # Push with revoked cert → rejected
    resp = await auth_client.post(
        "/api/sync/push",
        json={
            "device_id": "revoke-device-001",
            "last_sync_at": "",
            "changes": [],
            "company_id": "revoke-co",
            "certificate_data": cert["certificate_data"],
            "signature": cert["signature"],
        },
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["data"]["cert_valid"] is False
    assert "cert_revoked" in body["data"].get("reason", "")


@pytest.mark.asyncio
async def test_sync_push_works_without_security(auth_client: AsyncClient):
    """If no company is initialised, sync push should work without any cert."""
    # Register a device (but don't init any company)
    await auth_client.post(
        "/api/sync/register",
        json={"device_id": "no-sec-device-001", "device_name": "Plain Device", "platform": "windows"},
    )

    # Push without cert when no companies exist → should succeed
    resp = await auth_client.post(
        "/api/sync/push",
        json={
            "device_id": "no-sec-device-001",
            "last_sync_at": "",
            "changes": [],
        },
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["data"] is not None
    assert "sync_batch_id" in body["data"]


@pytest.mark.asyncio
async def test_sync_pull_requires_cert_when_security_enabled(auth_client: AsyncClient):
    """When security is enabled, sync pull should also require a valid certificate."""
    await auth_client.post(
        "/api/security/company/init",
        json={"company_id": "pull-co", "company_name": "Pull Corp"},
    )
    await auth_client.post(
        "/api/sync/register",
        json={"device_id": "pull-device-001", "device_name": "Pull Phone", "platform": "ios"},
    )
    resp = await auth_client.post(
        "/api/security/certs/issue",
        json={
            "device_id": "pull-device-001",
            "company_id": "pull-co",
            "device_public_key": "cHVsbC10ZXN0LWtleQ==",
        },
    )
    cert = resp.json()["data"]

    # Missing cert fields => rejected
    resp = await auth_client.get(
        "/api/sync/pull",
        params={"device_id": "pull-device-001", "since": "1970-01-01"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["data"] is None
    assert "Security enabled" in body.get("message", "")

    # With cert => accepted
    resp = await auth_client.get(
        "/api/sync/pull",
        params={
            "device_id": "pull-device-001",
            "since": "1970-01-01",
            "company_id": "pull-co",
            "certificate_data": cert["certificate_data"],
            "signature": cert["signature"],
        },
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["data"] is not None
    assert "changes" in resp.json()["data"]


@pytest.mark.asyncio
async def test_initial_sync_requires_cert_when_security_enabled(auth_client: AsyncClient):
    """When security is enabled, initial sync should require a valid certificate."""
    await auth_client.post(
        "/api/security/company/init",
        json={"company_id": "init-co", "company_name": "Init Corp"},
    )
    await auth_client.post(
        "/api/sync/register",
        json={"device_id": "init-device-001", "device_name": "Init Tablet", "platform": "android"},
    )
    resp = await auth_client.post(
        "/api/security/certs/issue",
        json={
            "device_id": "init-device-001",
            "company_id": "init-co",
            "device_public_key": "aW5pdC10ZXN0LWtleQ==",
        },
    )
    cert = resp.json()["data"]

    # Missing cert fields => rejected
    resp = await auth_client.post(
        "/api/sync/initial",
        json={"device_id": "init-device-001", "tables": ["parts"]},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["data"] is None
    assert "Security enabled" in body.get("message", "")

    # With cert => accepted
    resp = await auth_client.post(
        "/api/sync/initial",
        json={
            "device_id": "init-device-001",
            "tables": ["parts"],
            "company_id": "init-co",
            "certificate_data": cert["certificate_data"],
            "signature": cert["signature"],
        },
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()["data"]
    assert data is not None
    assert "tables" in data
