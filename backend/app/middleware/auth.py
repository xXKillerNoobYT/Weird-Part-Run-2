"""
Authentication middleware — FastAPI dependencies for JWT and permission checks.

This module provides injectable dependencies that route handlers use to:
1. Get the current authenticated user (require_user)
2. Check if the user has specific permissions (require_permission)
3. Require a PIN token for sensitive actions (require_pin_token)

Usage in routes:
    @router.get("/protected")
    async def protected_route(user = Depends(require_user)):
        return {"user_id": user["id"]}

    @router.put("/pricing")
    async def edit_pricing(
        user = Depends(require_permission("edit_pricing")),
    ):
        ...
"""

from __future__ import annotations

from typing import Callable

import aiosqlite
from fastapi import Depends, HTTPException, Header, status

from app.database import get_db
from app.repositories.user_repo import UserRepo
from app.services.auth_service import decode_token, get_user_id_from_token


async def _extract_token(authorization: str | None = Header(None)) -> str:
    """Extract the Bearer token from the Authorization header.

    Raises 401 if the header is missing or malformed.
    """
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header required",
            headers={"WWW-Authenticate": "Bearer"},
        )

    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authorization header format. Expected: Bearer <token>",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return parts[1]


async def require_user(
    token: str = Depends(_extract_token),
    db: aiosqlite.Connection = Depends(get_db),
) -> dict:
    """FastAPI dependency: require a valid authenticated user.

    Returns the full user dict with hats and permissions.
    Raises 401 if the token is invalid/expired or user not found.
    """
    user_id = get_user_id_from_token(token)
    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    repo = UserRepo(db)
    user = await repo.get_by_id_with_hats(user_id)

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
        )

    if not user.get("is_active", True):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is deactivated",
        )

    return user


def require_permission(*permission_keys: str) -> Callable:
    """Factory that returns a FastAPI dependency requiring specific permissions.

    Usage:
        @router.put("/edit")
        async def edit_thing(user = Depends(require_permission("edit_parts_catalog"))):
            ...

        # Multiple permissions (user must have ALL of them):
        @router.put("/edit-price")
        async def edit_price(
            user = Depends(require_permission("edit_pricing", "show_dollar_values")),
        ):
            ...
    """

    async def _check_permissions(
        user: dict = Depends(require_user),
    ) -> dict:
        user_perms = set(user.get("permissions", []))

        missing = set(permission_keys) - user_perms
        if missing:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Missing required permissions: {', '.join(sorted(missing))}",
            )

        return user

    return _check_permissions


async def require_pin_token(
    token: str = Depends(_extract_token),
    db: aiosqlite.Connection = Depends(get_db),
) -> dict:
    """FastAPI dependency: require a valid PIN verification token.

    Used for sensitive actions that need the user to re-enter their PIN.
    The PIN token is short-lived (5 minutes) and separate from the access token.

    The frontend sends the PIN token as the Authorization header for these
    specific requests (replacing the normal access token temporarily).
    """
    payload = decode_token(token)

    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired PIN token",
        )

    if payload.get("type") != "pin_verify":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="A PIN verification token is required for this action",
        )

    user_id = int(payload["sub"])
    repo = UserRepo(db)
    user = await repo.get_by_id_with_hats(user_id)

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
        )

    return user


async def optional_user(
    authorization: str | None = Header(None),
    db: aiosqlite.Connection = Depends(get_db),
) -> dict | None:
    """FastAPI dependency: optionally authenticate a user.

    Returns the user dict if a valid token is present, None otherwise.
    Does NOT raise on missing/invalid tokens — useful for endpoints that
    behave differently for authenticated vs anonymous users.
    """
    if not authorization:
        return None

    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        return None

    user_id = get_user_id_from_token(parts[1])
    if user_id is None:
        return None

    repo = UserRepo(db)
    return await repo.get_by_id_with_hats(user_id)
