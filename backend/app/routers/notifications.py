"""
Notification routes — bell icon data, preferences, mark-as-read.

Cross-module notification system:
  - Bell icon badge count (polled by frontend header)
  - Notification list with pagination
  - Mark individual or all as read
  - Per-user notification preferences (tied to hat/role system)
"""

from __future__ import annotations

import aiosqlite
from fastapi import APIRouter, Depends, Query

from app.database import get_db
from app.middleware.auth import require_user
from app.models.common import ApiResponse
from app.models.notifications import (
    NotificationBadge,
    NotificationListResponse,
    NotificationMarkRead,
    NotificationPreferenceResponse,
    NotificationPreferenceUpdate,
    NotificationSoundSetting,
    NotificationSoundSettingsResponse,
    NotificationSoundSettingsUpdate,
)
from app.services.notification_service import NotificationService

router = APIRouter(prefix="/api/notifications", tags=["Notifications"])


@router.get("/badge", response_model=ApiResponse[NotificationBadge])
async def get_badge_count(
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get unread count for the bell icon badge.

    Polled by the frontend header every 30 seconds.
    Lightweight query — just counts unread notifications.
    """
    svc = NotificationService(db)
    badge = await svc.get_badge_count(user["id"])

    return ApiResponse(data=NotificationBadge(**badge))


@router.get("", response_model=ApiResponse[NotificationListResponse])
async def list_notifications(
    unread_only: bool = False,
    limit: int = Query(50, le=200),
    offset: int = 0,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get notifications for the current user.

    Returns notifications with unread count for the dropdown/page.
    """
    svc = NotificationService(db)
    result = await svc.get_notifications(
        user["id"],
        unread_only=unread_only,
        limit=limit,
        offset=offset,
    )

    return ApiResponse(data=NotificationListResponse(**result))


@router.post("/read", response_model=ApiResponse)
async def mark_notifications_read(
    body: NotificationMarkRead,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Mark one or more notifications as read.

    Set mark_all=true to mark all notifications as read,
    or provide specific notification_ids.
    """
    svc = NotificationService(db)
    count = await svc.mark_read(
        user["id"],
        notification_ids=body.notification_ids or None,
        mark_all=body.mark_all,
    )

    return ApiResponse(
        data={"marked_count": count},
        message=f"Marked {count} notification(s) as read.",
    )


# ── Notification Preferences ─────────────────────────────────


@router.get("/preferences", response_model=ApiResponse[NotificationPreferenceResponse])
async def get_notification_preferences(
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get notification preferences for the current user.

    Returns all known notification types with their enabled/disabled status.
    Types default to OFF — users opt in to what they want.
    """
    svc = NotificationService(db)
    prefs = await svc.get_preferences(user["id"])

    return ApiResponse(
        data=NotificationPreferenceResponse(
            user_id=user["id"],
            preferences=prefs,
        ),
    )


@router.put("/preferences", response_model=ApiResponse)
async def update_notification_preferences(
    body: NotificationPreferenceUpdate,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update notification preferences (batch).

    Accepts a list of {notification_type, is_enabled} objects.
    Only the types included in the list are updated.
    """
    svc = NotificationService(db)
    prefs = [p.model_dump() for p in body.preferences]
    await svc.update_preferences(user["id"], prefs)

    return ApiResponse(
        data={"updated_count": len(prefs)},
        message="Notification preferences updated.",
    )


# ── Sound Settings (Phase 7E) ──────────────────────────────────


@router.get("/sound-settings", response_model=ApiResponse[NotificationSoundSettingsResponse])
async def get_sound_settings(
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get per-type sound settings for the current user.

    Returns which notification types trigger an audio alert.
    Missing entries default to sound_enabled=False.
    """
    svc = NotificationService(db)
    settings = await svc.get_sound_settings(user["id"])

    return ApiResponse(
        data=NotificationSoundSettingsResponse(
            user_id=user["id"],
            settings=settings,
        ),
    )


@router.put("/sound-settings", response_model=ApiResponse)
async def update_sound_settings(
    body: NotificationSoundSettingsUpdate,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update per-type sound settings (batch upsert).

    Only the types included in the list are upserted.
    """
    svc = NotificationService(db)
    count = await svc.update_sound_settings(
        user["id"],
        [s.model_dump() for s in body.settings],
    )

    return ApiResponse(
        data={"updated_count": count},
        message="Sound settings updated.",
    )
