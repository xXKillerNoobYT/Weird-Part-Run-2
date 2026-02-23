"""
Authentication and user-related Pydantic models.

Covers device login, PIN login, user profiles, hats, and permissions.
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


# ── Request Models ──────────────────────────────────────────────────

class DeviceLoginRequest(BaseModel):
    """Sent when a device first connects to the app.

    The frontend generates a unique fingerprint (browser ID / device UUID)
    and sends it here. If the device is assigned to a user and NOT public,
    we auto-login and return a JWT.
    """
    device_fingerprint: str = Field(..., min_length=8, max_length=255)
    device_name: str = Field(default="Unknown Device", max_length=100)


class PinLoginRequest(BaseModel):
    """PIN-based login for public devices or first-time setup.

    The user selects their name from a list, then enters their 4-6 digit PIN.
    """
    user_id: int
    pin: str = Field(..., min_length=4, max_length=6, pattern=r"^\d{4,6}$")
    device_fingerprint: str = Field(..., min_length=8, max_length=255)
    device_name: str = Field(default="Unknown Device", max_length=100)


class VerifyPinRequest(BaseModel):
    """PIN verification for sensitive actions (e.g., editing pricing, manager override).

    Returns a short-lived PIN token (5 min) that authorizes the specific action.
    """
    pin: str = Field(..., min_length=4, max_length=6, pattern=r"^\d{4,6}$")


# ── Response Models ─────────────────────────────────────────────────

class TokenResponse(BaseModel):
    """JWT token response after successful authentication."""
    access_token: str
    token_type: str = "bearer"
    expires_in: int  # seconds until expiration


class PinTokenResponse(BaseModel):
    """Short-lived PIN verification token for sensitive actions."""
    pin_token: str
    token_type: str = "pin_verify"
    expires_in: int  # seconds (typically 300 = 5 min)


class DeviceLoginResponse(BaseModel):
    """Response from device login attempt.

    If auto_login is True, token is included.
    If False, the frontend should show the user picker / PIN form.
    """
    auto_login: bool
    token: TokenResponse | None = None
    requires_user_selection: bool = False
    is_public_device: bool = False
    device_id: int | None = None


class HatSummary(BaseModel):
    """Minimal hat (role) info returned in user profiles."""
    id: int
    name: str
    level: int


class UserProfile(BaseModel):
    """Full user profile returned by /auth/me."""
    id: int
    display_name: str
    email: str | None = None
    phone: str | None = None
    avatar_url: str | None = None
    certification: str | None = None
    hire_date: str | None = None
    is_active: bool = True
    hats: list[HatSummary] = Field(default_factory=list)
    permissions: list[str] = Field(default_factory=list)
    created_at: datetime | None = None


class UserPickerItem(BaseModel):
    """Minimal user info for the user selection screen on public devices."""
    id: int
    display_name: str
    avatar_url: str | None = None
    hats: list[str] = Field(default_factory=list)
