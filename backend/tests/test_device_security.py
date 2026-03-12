"""Tests for Device Security — Ed25519 company keys, certificates, BT handshake, audit."""

from __future__ import annotations

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_company_init_and_cert_lifecycle(auth_client: AsyncClient):
    """Full flow: init company → issue cert → verify → revoke → verify fails.

    Now uses Ed25519 (crypto_version=2) for all signatures.
    """

    # ── 1. Initialise company ────────────────────────────────────
    resp = await auth_client.post(
        "/api/security/company/init",
        json={"company_id": "test-co-001", "company_name": "Test Corp"},
    )
    assert resp.status_code == 200, resp.text
    company = resp.json()["data"]
    assert company["company_id"] == "test-co-001"
    assert company["key_version"] == 1
    assert company["root_key_public"]  # non-empty

    # Idempotent — calling again returns same record
    resp2 = await auth_client.post(
        "/api/security/company/init",
        json={"company_id": "test-co-001", "company_name": "Test Corp"},
    )
    assert resp2.json()["data"]["key_version"] == 1

    # ── 2. Register a device first (so FK constraint is met) ─────
    await auth_client.post(
        "/api/sync/register",
        json={"device_id": "sec-device-001", "device_name": "Tablet A", "platform": "ios"},
    )

    # ── 3. Issue certificate ─────────────────────────────────────
    resp = await auth_client.post(
        "/api/security/certs/issue",
        json={
            "device_id": "sec-device-001",
            "company_id": "test-co-001",
            "device_public_key": "dGVzdC1wdWJsaWMta2V5",
            "validity_days": 30,
        },
    )
    assert resp.status_code == 200, resp.text
    cert = resp.json()["data"]
    assert cert["device_id"] == "sec-device-001"
    assert cert["signature"]

    # ── 4. Verify certificate ────────────────────────────────────
    resp = await auth_client.post(
        "/api/security/certs/verify",
        json={
            "device_id": "sec-device-001",
            "company_id": "test-co-001",
            "certificate_data": cert["certificate_data"],
            "signature": cert["signature"],
        },
    )
    assert resp.status_code == 200, resp.text
    result = resp.json()["data"]
    assert result["valid"] is True

    # ── 5. Revoke certificate ────────────────────────────────────
    resp = await auth_client.post(
        "/api/security/certs/revoke",
        json={
            "device_id": "sec-device-001",
            "company_id": "test-co-001",
            "reason": "test_revocation",
        },
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["data"]["revoked"] is True

    # ── 6. Verify after revocation fails ─────────────────────────
    resp = await auth_client.post(
        "/api/security/certs/verify",
        json={
            "device_id": "sec-device-001",
            "company_id": "test-co-001",
            "certificate_data": cert["certificate_data"],
            "signature": cert["signature"],
        },
    )
    result = resp.json()["data"]
    assert result["valid"] is False
    assert result["reason"] == "cert_revoked_or_missing"


@pytest.mark.asyncio
async def test_ed25519_crypto_version(auth_client: AsyncClient):
    """Verify that new companies are created with crypto_version=2 (Ed25519)."""
    resp = await auth_client.post(
        "/api/security/company/init",
        json={"company_id": "ed25519-co", "company_name": "Ed25519 Corp"},
    )
    assert resp.status_code == 200, resp.text
    company = resp.json()["data"]
    # New companies should use crypto_version 2 (Ed25519)
    assert company.get("crypto_version", 1) == 2


@pytest.mark.asyncio
async def test_key_rotation_revokes_all_certs(auth_client: AsyncClient):
    """Key rotation should revoke all existing certs for the company."""

    # Init company + register device + issue cert
    await auth_client.post(
        "/api/security/company/init",
        json={"company_id": "rotate-co", "company_name": "Rotate Corp"},
    )
    await auth_client.post(
        "/api/sync/register",
        json={"device_id": "rot-device-001", "device_name": "Field Phone", "platform": "android"},
    )
    await auth_client.post(
        "/api/security/certs/issue",
        json={
            "device_id": "rot-device-001",
            "company_id": "rotate-co",
            "device_public_key": "cm90LXRlc3Q=",
        },
    )

    # Rotate keys
    resp = await auth_client.post(
        "/api/security/company/rotate",
        json={"company_id": "rotate-co"},
    )
    assert resp.status_code == 200, resp.text
    rotated = resp.json()["data"]
    assert rotated["key_version"] == 2

    # Old cert should be gone
    resp = await auth_client.get(
        "/api/security/certs/rot-device-001",
        params={"company_id": "rotate-co"},
    )
    assert resp.json()["data"] is None  # no active cert


@pytest.mark.asyncio
async def test_security_audit_log(auth_client: AsyncClient):
    """Audit log should capture security events."""

    await auth_client.post(
        "/api/security/company/init",
        json={"company_id": "audit-co", "company_name": "Audit Corp"},
    )

    resp = await auth_client.get(
        "/api/security/audit",
        params={"company_id": "audit-co", "limit": 10},
    )
    assert resp.status_code == 200, resp.text
    events = resp.json()["data"]
    assert len(events) >= 1
    assert any(e["event_type"] == "company_initialised" for e in events)


@pytest.mark.asyncio
async def test_shared_channel_creation(auth_client: AsyncClient):
    """Create a shared channel and list it."""

    await auth_client.post(
        "/api/security/company/init",
        json={"company_id": "owner-co", "company_name": "Owner Inc"},
    )
    await auth_client.post(
        "/api/security/company/init",
        json={"company_id": "partner-co", "company_name": "Partner LLC"},
    )

    resp = await auth_client.post(
        "/api/security/channels",
        json={
            "channel_name": "Job 42 Shared Data",
            "owner_company_id": "owner-co",
            "partner_company_ids": ["partner-co"],
            "scope": {"job_ids": [42]},
            "permissions": {"read": True, "write": False},
        },
    )
    assert resp.status_code == 200, resp.text
    ch = resp.json()["data"]
    assert ch["channel_name"] == "Job 42 Shared Data"
    assert len(ch["members"]) == 2

    # List channels
    resp = await auth_client.get(
        "/api/security/channels",
        params={"company_id": "owner-co"},
    )
    assert resp.status_code == 200
    channels = resp.json()["data"]
    assert len(channels) >= 1


@pytest.mark.asyncio
async def test_shared_channel_deactivate(auth_client: AsyncClient):
    """Deactivate a shared channel and verify it's no longer listed."""

    await auth_client.post(
        "/api/security/company/init",
        json={"company_id": "deact-owner-co", "company_name": "Deact Owner"},
    )
    resp = await auth_client.post(
        "/api/security/channels",
        json={
            "channel_name": "Temp Channel",
            "owner_company_id": "deact-owner-co",
        },
    )
    ch_id = resp.json()["data"]["id"]

    # Deactivate
    resp = await auth_client.post(f"/api/security/channels/{ch_id}/deactivate")
    assert resp.status_code == 200, resp.text
    assert resp.json()["data"]["deactivated"] is True

    # Should no longer appear in active list
    resp = await auth_client.get(
        "/api/security/channels",
        params={"company_id": "deact-owner-co"},
    )
    active_ids = [c["id"] for c in resp.json()["data"]]
    assert ch_id not in active_ids


@pytest.mark.asyncio
async def test_bt_handshake_full_flow(auth_client: AsyncClient):
    """Full Bluetooth handshake: hello → verify hello → verify ack."""

    # Setup: init company + register 2 devices + issue certs
    await auth_client.post(
        "/api/security/company/init",
        json={"company_id": "bt-co", "company_name": "BT Corp"},
    )
    for dev_id, dev_name in [("bt-dev-001", "Phone A"), ("bt-dev-002", "Phone B")]:
        await auth_client.post(
            "/api/sync/register",
            json={"device_id": dev_id, "device_name": dev_name, "platform": "ios"},
        )
        await auth_client.post(
            "/api/security/certs/issue",
            json={
                "device_id": dev_id,
                "company_id": "bt-co",
                "device_public_key": "YnQtdGVzdC1rZXk=",
            },
        )

    # Step 1: Initiator (bt-dev-001) creates BT_HELLO
    resp = await auth_client.post(
        "/api/security/bt/hello",
        json={"device_id": "bt-dev-001", "company_id": "bt-co"},
    )
    assert resp.status_code == 200, resp.text
    hello = resp.json()["data"]
    assert hello["type"] == "BT_HELLO"
    assert hello["nonce"]

    # Step 2: Responder (bt-dev-002) verifies hello → gets ACK
    resp = await auth_client.post(
        "/api/security/bt/verify-hello",
        json={
            "hello": hello,
            "responder_device_id": "bt-dev-002",
            "responder_company_id": "bt-co",
        },
    )
    assert resp.status_code == 200, resp.text
    ack = resp.json()["data"]
    assert ack["type"] == "BT_HELLO_ACK"
    assert ack["nonce_response"] == hello["nonce"]

    # Step 3: Initiator verifies ACK → mutual trust
    resp = await auth_client.post(
        "/api/security/bt/verify-ack",
        json={
            "ack": ack,
            "initiator_device_id": "bt-dev-001",
            "initiator_company_id": "bt-co",
            "original_nonce": hello["nonce"],
        },
    )
    assert resp.status_code == 200, resp.text
    result = resp.json()["data"]
    assert result["valid"] is True
    assert result["peer_device_id"] == "bt-dev-002"


@pytest.mark.asyncio
async def test_bt_handshake_cross_company_rejected(auth_client: AsyncClient):
    """BT handshake should reject devices from different companies."""

    # Setup two companies
    await auth_client.post(
        "/api/security/company/init",
        json={"company_id": "bt-co-a", "company_name": "Company A"},
    )
    await auth_client.post(
        "/api/security/company/init",
        json={"company_id": "bt-co-b", "company_name": "Company B"},
    )

    # Register + cert for device in company A
    await auth_client.post(
        "/api/sync/register",
        json={"device_id": "bt-cross-001", "device_name": "Phone A", "platform": "ios"},
    )
    await auth_client.post(
        "/api/security/certs/issue",
        json={
            "device_id": "bt-cross-001",
            "company_id": "bt-co-a",
            "device_public_key": "Y3Jvc3MtdGVzdA==",
        },
    )

    # Create hello from company A device
    resp = await auth_client.post(
        "/api/security/bt/hello",
        json={"device_id": "bt-cross-001", "company_id": "bt-co-a"},
    )
    hello = resp.json()["data"]

    # Try to verify as company B responder → should fail
    await auth_client.post(
        "/api/sync/register",
        json={"device_id": "bt-cross-002", "device_name": "Phone B", "platform": "android"},
    )
    resp = await auth_client.post(
        "/api/security/bt/verify-hello",
        json={
            "hello": hello,
            "responder_device_id": "bt-cross-002",
            "responder_company_id": "bt-co-b",
        },
    )
    assert resp.status_code == 200
    result = resp.json()["data"]
    assert result.get("valid") is False or "company_mismatch" in resp.json().get("message", "")
