"""
Authentication service — JWT token management, PIN hashing, and verification.

This service handles the crypto side of auth:
- Hashing PINs with bcrypt
- Creating and verifying JWT access tokens
- Creating short-lived PIN verification tokens for sensitive actions

The auth FLOW is orchestrated by the auth router, which calls this service
and the user/device repositories.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import bcrypt
from jose import JWTError, jwt

from app.config import settings

# ── Password / PIN Hashing ──────────────────────────────────────────
# bcrypt is deliberately slow (configurable rounds) to resist brute force.
# Even a 4-digit PIN is reasonably safe with bcrypt at 12 rounds.
#
# NOTE: We use the bcrypt library directly instead of passlib because
# passlib has compatibility issues with bcrypt>=4.1 on Python 3.14.
# The bcrypt library is the same underlying implementation either way.


def hash_pin(pin: str) -> str:
    """Hash a PIN using bcrypt. Returns the hash string."""
    salt = bcrypt.gensalt(rounds=settings.PIN_HASH_ROUNDS)
    return bcrypt.hashpw(pin.encode("utf-8"), salt).decode("utf-8")


def verify_pin(plain_pin: str, hashed_pin: str) -> bool:
    """Verify a PIN against its bcrypt hash.

    Returns True if the PIN matches, False otherwise.
    Handles the placeholder hash gracefully (always returns False).
    """
    if hashed_pin == "__PLACEHOLDER_HASH__":
        return False
    try:
        return bcrypt.checkpw(
            plain_pin.encode("utf-8"),
            hashed_pin.encode("utf-8"),
        )
    except Exception:
        return False


# ── JWT Token Management ────────────────────────────────────────────
# We use two types of tokens:
# 1. Access token (24h) — for general API access after device/PIN login
# 2. PIN token (5min) — for sensitive actions requiring PIN confirmation

ALGORITHM = "HS256"


def create_access_token(
    user_id: int,
    *,
    device_id: int | None = None,
    extra_claims: dict | None = None,
) -> str:
    """Create a long-lived JWT access token (default 24h).

    Claims:
        sub: user ID (string)
        device_id: the device this token was issued for
        type: "access"
        iat: issued at
        exp: expiration
    """
    now = datetime.now(timezone.utc)
    expire = now + timedelta(seconds=settings.ACCESS_TOKEN_EXPIRE_SECONDS)

    payload = {
        "sub": str(user_id),
        "type": "access",
        "iat": now,
        "exp": expire,
    }

    if device_id is not None:
        payload["device_id"] = device_id

    if extra_claims:
        payload.update(extra_claims)

    return jwt.encode(payload, settings.SECRET_KEY, algorithm=ALGORITHM)


def create_pin_token(user_id: int) -> str:
    """Create a short-lived PIN verification token (default 5min).

    Used when a user confirms their PIN for sensitive actions like
    editing pricing, manager override, or changing permissions.
    """
    now = datetime.now(timezone.utc)
    expire = now + timedelta(seconds=settings.PIN_TOKEN_EXPIRE_SECONDS)

    payload = {
        "sub": str(user_id),
        "type": "pin_verify",
        "iat": now,
        "exp": expire,
    }

    return jwt.encode(payload, settings.SECRET_KEY, algorithm=ALGORITHM)


def decode_token(token: str) -> dict | None:
    """Decode and validate a JWT token.

    Returns the payload dict if valid, None if expired/invalid.
    """
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except JWTError:
        return None


def get_user_id_from_token(token: str) -> int | None:
    """Extract the user_id from a valid access token.

    Returns None if the token is invalid or expired.
    """
    payload = decode_token(token)
    if payload is None:
        return None

    sub = payload.get("sub")
    if sub is None:
        return None

    try:
        return int(sub)
    except (ValueError, TypeError):
        return None


def is_pin_token(token: str) -> bool:
    """Check if a token is a PIN verification token (vs regular access)."""
    payload = decode_token(token)
    return payload is not None and payload.get("type") == "pin_verify"
