"""
Authentication routes — device login, PIN login, user profile, PIN verification.

Auth Flow:
1. Frontend generates device fingerprint → POST /api/auth/device-login
2. If device has assigned user AND is not public → auto JWT token
3. If public or unassigned → frontend shows UserPicker → PinLoginForm
4. User selects themselves, enters PIN → POST /api/auth/pin-login → JWT token
5. For sensitive actions → POST /api/auth/verify-pin → short-lived PIN token
"""

from __future__ import annotations

import logging

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException, status

from app.database import get_db
from app.middleware.auth import require_user
from app.models.auth import (
    DeviceLoginRequest,
    DeviceLoginResponse,
    HatSummary,
    PinLoginRequest,
    PinTokenResponse,
    TokenResponse,
    UserPickerItem,
    UserProfile,
    VerifyPinRequest,
)
from app.models.common import ApiResponse
from app.repositories.device_repo import DeviceRepo
from app.repositories.user_repo import UserRepo
from app.services.auth_service import (
    create_access_token,
    create_pin_token,
    hash_pin,
    verify_pin,
)
from app.config import settings

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/auth", tags=["Authentication"])


@router.post("/device-login", response_model=ApiResponse[DeviceLoginResponse])
async def device_login(
    req: DeviceLoginRequest,
    db: aiosqlite.Connection = Depends(get_db),
):
    """Step 1: Device-based login attempt.

    - If device is known + assigned + not public → auto-login with JWT
    - If device is known + public → requires user selection + PIN
    - If device is unknown → register it, then require user selection + PIN
    """
    device_repo = DeviceRepo(db)
    user_repo = UserRepo(db)

    # Look up the device
    device = await device_repo.get_by_fingerprint(req.device_fingerprint)

    if device is None:
        # First time seeing this device — register it
        device_id = await device_repo.register_device(
            fingerprint=req.device_fingerprint,
            device_name=req.device_name,
        )
        logger.info("New device registered: %s (id=%d)", req.device_name, device_id)

        return ApiResponse(
            data=DeviceLoginResponse(
                auto_login=False,
                requires_user_selection=True,
                is_public_device=False,
                device_id=device_id,
            ),
            message="New device registered. Please select a user and enter PIN.",
        )

    # Device exists — update last seen
    await device_repo.touch(device["id"])

    # Public device → always require login
    if device.get("is_public"):
        return ApiResponse(
            data=DeviceLoginResponse(
                auto_login=False,
                requires_user_selection=True,
                is_public_device=True,
                device_id=device["id"],
            ),
            message="Public device. Please select a user and enter PIN.",
        )

    # Device has assigned user → auto-login
    assigned_user_id = device.get("assigned_user_id")
    if assigned_user_id:
        user = await user_repo.get_by_id(assigned_user_id)
        if user and user.get("is_active"):
            token = create_access_token(
                user_id=assigned_user_id,
                device_id=device["id"],
            )
            return ApiResponse(
                data=DeviceLoginResponse(
                    auto_login=True,
                    token=TokenResponse(
                        access_token=token,
                        expires_in=settings.ACCESS_TOKEN_EXPIRE_SECONDS,
                    ),
                    device_id=device["id"],
                ),
                message=f"Auto-login successful for {user['display_name']}.",
            )

    # Device exists but no assigned user
    return ApiResponse(
        data=DeviceLoginResponse(
            auto_login=False,
            requires_user_selection=True,
            is_public_device=False,
            device_id=device["id"],
        ),
        message="Device not assigned. Please select a user and enter PIN.",
    )


@router.post("/pin-login", response_model=ApiResponse[TokenResponse])
async def pin_login(
    req: PinLoginRequest,
    db: aiosqlite.Connection = Depends(get_db),
):
    """Step 2: PIN-based login.

    User has selected their name and entered their PIN.
    Verify the PIN and issue a JWT if correct.
    Also assigns the user to the device (unless it's public).
    """
    user_repo = UserRepo(db)
    device_repo = DeviceRepo(db)

    # Verify the user exists and is active
    user = await user_repo.get_by_id(req.user_id)
    if not user or not user.get("is_active"):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid user or account deactivated",
        )

    # Verify PIN
    pin_hash = user["pin_hash"]

    # Handle first-login: if the hash is a placeholder, hash the default PIN
    # and compare. This is the seed admin user (PIN: 1234).
    if pin_hash == "__PLACEHOLDER_HASH__":
        # First run — set the real hash
        new_hash = hash_pin(settings.DEFAULT_ADMIN_PIN)
        await user_repo.update_pin_hash(req.user_id, new_hash)
        pin_hash = new_hash

    if not verify_pin(req.pin, pin_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid PIN",
        )

    # Get or register the device
    device = await device_repo.get_by_fingerprint(req.device_fingerprint)
    device_id = None

    if device is None:
        device_id = await device_repo.register_device(
            fingerprint=req.device_fingerprint,
            device_name=req.device_name,
            assigned_user_id=req.user_id,
        )
    else:
        device_id = device["id"]
        await device_repo.touch(device_id)
        # Assign user to non-public devices
        if not device.get("is_public"):
            await device_repo.assign_user(device_id, req.user_id)

    # Issue JWT
    token = create_access_token(
        user_id=req.user_id,
        device_id=device_id,
    )

    logger.info("PIN login successful: user=%s (id=%d)", user["display_name"], req.user_id)

    return ApiResponse(
        data=TokenResponse(
            access_token=token,
            expires_in=settings.ACCESS_TOKEN_EXPIRE_SECONDS,
        ),
        message=f"Welcome, {user['display_name']}!",
    )


@router.get("/me", response_model=ApiResponse[UserProfile])
async def get_current_user(user: dict = Depends(require_user)):
    """Get the current authenticated user's profile with hats and permissions."""
    return ApiResponse(
        data=UserProfile(
            id=user["id"],
            display_name=user["display_name"],
            email=user.get("email"),
            phone=user.get("phone"),
            avatar_url=user.get("avatar_url"),
            certification=user.get("certification"),
            hire_date=user.get("hire_date"),
            is_active=bool(user.get("is_active", True)),
            hats=[
                HatSummary(id=h["id"], name=h["name"], level=h["level"])
                for h in user.get("hats", [])
            ],
            permissions=user.get("permissions", []),
            created_at=user.get("created_at"),
        ),
    )


@router.get("/users", response_model=ApiResponse[list[UserPickerItem]])
async def list_users_for_picker(
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get the list of active users for the user picker screen.

    This endpoint is intentionally unauthenticated — it's needed
    BEFORE the user logs in (on public devices or first-time setup).
    Only returns minimal info: name, avatar, hat names.
    """
    repo = UserRepo(db)
    users = await repo.get_active_users()

    return ApiResponse(
        data=[
            UserPickerItem(
                id=u["id"],
                display_name=u["display_name"],
                avatar_url=u.get("avatar_url"),
                hats=u.get("hats", []),
            )
            for u in users
        ],
    )


@router.post("/verify-pin", response_model=ApiResponse[PinTokenResponse])
async def verify_pin_for_action(
    req: VerifyPinRequest,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Verify PIN for sensitive actions.

    The user must already be authenticated (have a valid access token).
    This issues a short-lived PIN token for the sensitive action.
    """
    user_repo = UserRepo(db)
    pin_hash = await user_repo.get_pin_hash(user["id"])

    if not pin_hash or not verify_pin(req.pin, pin_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid PIN",
        )

    pin_token = create_pin_token(user["id"])

    return ApiResponse(
        data=PinTokenResponse(
            pin_token=pin_token,
            expires_in=settings.PIN_TOKEN_EXPIRE_SECONDS,
        ),
        message="PIN verified. Token valid for sensitive actions.",
    )
