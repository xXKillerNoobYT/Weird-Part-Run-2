"""Tests for Device Security — company keys, certificates, audit."""

from __future__ import annotations

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_company_init_and_cert_lifecycle(auth_client: AsyncClient):
    """Full flow: init company → issue cert → verify → revoke → verify fails."""

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
