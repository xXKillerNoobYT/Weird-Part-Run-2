"""
Tests for the auth middleware — JWT validation, permission checks, PIN tokens.

Tests the full auth API flow:
- Device login (fingerprint)
- PIN login
- /me endpoint
- User picker (unauthenticated)
- Permission-gated endpoints
- PIN token requirements
"""

from __future__ import annotations

import pytest
import pytest_asyncio

from httpx import AsyncClient

from app.services.auth_service import create_access_token, create_pin_token

from tests.conftest import make_auth_header


# ══════════════════════════════════════════════════════════════════
# Auth Endpoints
# ══════════════════════════════════════════════════════════════════


class TestDeviceLogin:
    """Tests for POST /api/auth/device-login."""

    @pytest.mark.asyncio
    async def test_new_device_registers(self, client: AsyncClient):
        """First login from a new fingerprint should register the device."""
        resp = await client.post("/api/auth/device-login", json={
            "device_fingerprint": "test-device-abc12345",
            "device_name": "Test Browser",
        })
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["data"]["device_id"] is not None
        assert data["data"]["requires_user_selection"] is True

    @pytest.mark.asyncio
    async def test_returning_device_recognized(self, client: AsyncClient):
        """Second login from the same fingerprint should recognize it."""
        fp = "returning-device-xyz-long-enough"

        # First login
        resp1 = await client.post("/api/auth/device-login", json={
            "device_fingerprint": fp,
            "device_name": "First Visit",
        })
        assert resp1.status_code == 200

        # Second login
        resp2 = await client.post("/api/auth/device-login", json={
            "device_fingerprint": fp,
            "device_name": "Second Visit",
        })
        assert resp2.status_code == 200
        data = resp2.json()
        assert data["success"] is True


class TestPinLogin:
    """Tests for POST /api/auth/pin-login."""

    @pytest.mark.asyncio
    async def test_correct_pin(self, client: AsyncClient):
        """Logging in with the correct admin PIN should succeed."""
        resp = await client.post("/api/auth/pin-login", json={
            "user_id": 1,
            "pin": "1234",
            "device_fingerprint": "pin-test-device-1234",
        })
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["data"]["access_token"] is not None
        assert len(data["data"]["access_token"]) > 20

    @pytest.mark.asyncio
    async def test_wrong_pin(self, client: AsyncClient):
        """Logging in with a wrong PIN should return 401."""
        resp = await client.post("/api/auth/pin-login", json={
            "user_id": 1,
            "pin": "0000",
            "device_fingerprint": "pin-test-device-wrong",
        })
        assert resp.status_code == 401

    @pytest.mark.asyncio
    async def test_nonexistent_user(self, client: AsyncClient):
        """Logging in as a non-existent user should return 401."""
        resp = await client.post("/api/auth/pin-login", json={
            "user_id": 9999,
            "pin": "1234",
            "device_fingerprint": "pin-test-device-ghost",
        })
        assert resp.status_code == 401


class TestMeEndpoint:
    """Tests for GET /api/auth/me."""

    @pytest.mark.asyncio
    async def test_authenticated(self, client: AsyncClient):
        """/me should return the current user's info with a valid token."""
        token = create_access_token(1)
        resp = await client.get("/api/auth/me", headers=make_auth_header(token))

        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["data"]["id"] == 1

    @pytest.mark.asyncio
    async def test_no_token(self, client: AsyncClient):
        """/me should return 401 without an Authorization header."""
        resp = await client.get("/api/auth/me")
        assert resp.status_code == 401

    @pytest.mark.asyncio
    async def test_invalid_token(self, client: AsyncClient):
        """/me should return 401 with a garbage token."""
        resp = await client.get(
            "/api/auth/me",
            headers=make_auth_header("garbage.invalid.token"),
        )
        assert resp.status_code == 401

    @pytest.mark.asyncio
    async def test_malformed_header(self, client: AsyncClient):
        """/me should return 401 with a malformed Authorization header."""
        resp = await client.get(
            "/api/auth/me",
            headers={"Authorization": "NotBearer token"},
        )
        assert resp.status_code == 401


class TestUserPicker:
    """Tests for GET /api/auth/users (unauthenticated user picker)."""

    @pytest.mark.asyncio
    async def test_returns_users(self, client: AsyncClient):
        """User picker should return active users without auth."""
        resp = await client.get("/api/auth/users")
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert isinstance(data["data"], list)
        assert len(data["data"]) >= 1  # At least the admin user


# ══════════════════════════════════════════════════════════════════
# Permission Middleware
# ══════════════════════════════════════════════════════════════════


class TestPermissionMiddleware:
    """Tests for require_user and require_permission dependencies.

    These test the middleware indirectly through real endpoints.
    """

    @pytest.mark.asyncio
    async def test_require_user_with_valid_token(self, client: AsyncClient):
        """Any endpoint using require_user should accept a valid token."""
        token = create_access_token(1)
        # /api/auth/me uses require_user
        resp = await client.get("/api/auth/me", headers=make_auth_header(token))
        assert resp.status_code == 200

    @pytest.mark.asyncio
    async def test_require_user_rejects_expired(self, client: AsyncClient):
        """An expired token should be rejected."""
        from jose import jwt as jose_jwt
        from datetime import datetime, timedelta, timezone
        from app.services.auth_service import ALGORITHM
        from app.config import settings

        expired_token = jose_jwt.encode(
            {
                "sub": "1",
                "type": "access",
                "exp": datetime.now(timezone.utc) - timedelta(hours=1),
            },
            settings.SECRET_KEY,
            algorithm=ALGORITHM,
        )
        resp = await client.get(
            "/api/auth/me",
            headers=make_auth_header(expired_token),
        )
        assert resp.status_code == 401


# ══════════════════════════════════════════════════════════════════
# PIN Token Endpoints
# ══════════════════════════════════════════════════════════════════


class TestPinVerification:
    """Tests for POST /api/auth/verify-pin."""

    @pytest.mark.asyncio
    async def test_verify_correct_pin(self, client: AsyncClient):
        """Verifying the correct PIN should return a short-lived PIN token."""
        access_token = create_access_token(1)
        resp = await client.post(
            "/api/auth/verify-pin",
            json={"pin": "1234"},
            headers=make_auth_header(access_token),
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert "pin_token" in data["data"]

    @pytest.mark.asyncio
    async def test_verify_wrong_pin(self, client: AsyncClient):
        """Verifying a wrong PIN should return 401."""
        access_token = create_access_token(1)
        resp = await client.post(
            "/api/auth/verify-pin",
            json={"pin": "9999"},
            headers=make_auth_header(access_token),
        )
        assert resp.status_code == 401


# ══════════════════════════════════════════════════════════════════
# Health Check (smoke test)
# ══════════════════════════════════════════════════════════════════


class TestHealthCheck:
    @pytest.mark.asyncio
    async def test_health(self, client: AsyncClient):
        resp = await client.get("/api/health")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "healthy"

    @pytest.mark.asyncio
    async def test_root(self, client: AsyncClient):
        resp = await client.get("/")
        assert resp.status_code == 200
        assert "docs" in resp.json()
