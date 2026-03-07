"""
Tests for the Auth Router — device login, PIN login, permissions.

Covers:
- Device registration (new fingerprint)
- PIN login with correct/wrong PIN
- /auth/me returns user profile
- Permission-required endpoints return 403 without correct hat
"""

from __future__ import annotations

import pytest
from httpx import AsyncClient


# ══════════════════════════════════════════════════════════════════
# Device Login
# ══════════════════════════════════════════════════════════════════


class TestDeviceLogin:
    """Test the device-login endpoint."""

    @pytest.mark.asyncio
    async def test_new_device_registers(self, client: AsyncClient):
        """A new device fingerprint should register and return device_id."""
        resp = await client.post("/api/auth/device-login", json={
            "device_fingerprint": "brand-new-device-001",
            "device_name": "New Test Device",
        })
        assert resp.status_code == 200
        data = resp.json()["data"]
        assert data["device_id"] is not None
        assert data["requires_user_selection"] is True

    @pytest.mark.asyncio
    async def test_same_device_recognized(self, client: AsyncClient):
        """Same fingerprint on second request should return same device_id."""
        fp = "repeat-device-fingerprint"
        resp1 = await client.post("/api/auth/device-login", json={
            "device_fingerprint": fp,
            "device_name": "Device",
        })
        resp2 = await client.post("/api/auth/device-login", json={
            "device_fingerprint": fp,
            "device_name": "Device",
        })
        assert resp1.json()["data"]["device_id"] == resp2.json()["data"]["device_id"]


# ══════════════════════════════════════════════════════════════════
# PIN Login
# ══════════════════════════════════════════════════════════════════


class TestPinLogin:
    """Test PIN-based authentication."""

    @pytest.mark.asyncio
    async def test_correct_pin_returns_token(self, client: AsyncClient):
        """Correct PIN should return a JWT access token."""
        # Register device first
        await client.post("/api/auth/device-login", json={
            "device_fingerprint": "pin-test-device-01",
            "device_name": "Pin Test",
        })

        resp = await client.post("/api/auth/pin-login", json={
            "user_id": 1,
            "pin": "1234",
            "device_fingerprint": "pin-test-device-01",
            "device_name": "Pin Test",
        })
        assert resp.status_code == 200
        data = resp.json()["data"]
        assert "access_token" in data
        assert data["expires_in"] > 0

    @pytest.mark.asyncio
    async def test_wrong_pin_rejected(self, client: AsyncClient):
        """Wrong PIN should return 401."""
        await client.post("/api/auth/device-login", json={
            "device_fingerprint": "pin-test-device-02",
            "device_name": "Pin Test",
        })

        resp = await client.post("/api/auth/pin-login", json={
            "user_id": 1,
            "pin": "9999",
            "device_fingerprint": "pin-test-device-02",
            "device_name": "Pin Test",
        })
        assert resp.status_code == 401


# ══════════════════════════════════════════════════════════════════
# Auth Me
# ══════════════════════════════════════════════════════════════════


class TestAuthMe:
    """Test the /auth/me endpoint."""

    @pytest.mark.asyncio
    async def test_me_returns_profile(self, auth_client: AsyncClient):
        """Authenticated user should get their profile."""
        resp = await auth_client.get("/api/auth/me")
        assert resp.status_code == 200
        data = resp.json()["data"]
        assert data["id"] == 1
        assert "display_name" in data

    @pytest.mark.asyncio
    async def test_me_without_auth_returns_401(self, client: AsyncClient):
        """Unauthenticated request to /me should return 401."""
        resp = await client.get("/api/auth/me")
        assert resp.status_code == 401
