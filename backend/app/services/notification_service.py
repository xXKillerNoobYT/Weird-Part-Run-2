"""
Notification service — create, read, dismiss, and manage preferences.

Architecture:
  - Persisted in DB, auto-purge after 30 days (via scheduler)
  - Bell icon in app header with unread count badge
  - Tied to hat/role system — defaults OFF, user opts in
  - Services call notify() to create notifications for relevant users
"""

from __future__ import annotations

import logging
from typing import Any

import aiosqlite

from app.repositories.notification_repo import NotificationPrefRepo, NotificationRepo

logger = logging.getLogger(__name__)

# All supported notification types
NOTIFICATION_TYPES = [
    "jpo_approval",
    "jpo_approved",
    "jpo_rejected",
    "po_submitted",
    "po_received",
    "delivery_expected",
    "partial_receive",
    "backorder_created",
    "low_stock",
    "audit_needed",
    "task_assigned",
    "return_approval",
    "distribution_waiting",
    "job_status_changed",
    "dispatch_created",
    "dispatch_cancelled",
    "time_off_approved",
    "time_off_denied",
    "sub_schedule_created",
    "sub_schedule_cancelled",
    "shift_pattern_assigned",
    "pto_accrual_posted",
    "vehicle_expiry",
    # Phase 9: Chat & Q&A
    "chat_message",
    "chat_mention",
    "qa_assigned",
    "qa_answered",
    "qa_escalated",
]


class NotificationService:
    """Manages notification creation, delivery, and preferences."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.notif_repo = NotificationRepo(db)
        self.pref_repo = NotificationPrefRepo(db)

    async def notify(
        self,
        notification_type: str,
        title: str,
        *,
        message: str | None = None,
        link: str | None = None,
        entity_type: str | None = None,
        entity_id: int | None = None,
        target_user_ids: list[int] | None = None,
    ) -> list[int]:
        """Create a notification for users who have this type enabled.

        If target_user_ids is provided, only notifies those users (if enabled).
        Otherwise, notifies ALL users who have opted in to this type.
        """
        if target_user_ids:
            # Filter to only users who have this type enabled
            enabled_users = []
            for uid in target_user_ids:
                if await self.pref_repo.is_enabled(uid, notification_type):
                    enabled_users.append(uid)
        else:
            enabled_users = await self.pref_repo.get_users_with_enabled(
                notification_type
            )

        if not enabled_users:
            return []

        return await self.notif_repo.create_for_users(
            enabled_users,
            type=notification_type,
            title=title,
            message=message,
            link=link,
            entity_type=entity_type,
            entity_id=entity_id,
        )

    async def get_notifications(
        self,
        user_id: int,
        *,
        unread_only: bool = False,
        limit: int = 50,
        offset: int = 0,
    ) -> dict:
        """Get notifications for a user with unread count."""
        items = await self.notif_repo.get_for_user(
            user_id, unread_only=unread_only, limit=limit, offset=offset
        )
        unread_count = await self.notif_repo.count_unread(user_id)

        return {
            "items": items,
            "total": len(items),
            "unread_count": unread_count,
        }

    async def get_badge_count(self, user_id: int) -> dict:
        """Get unread count for the bell icon badge."""
        count = await self.notif_repo.count_unread(user_id)
        return {"unread_count": count, "has_urgent": count > 10}

    async def mark_read(
        self,
        user_id: int,
        notification_ids: list[int] | None = None,
        mark_all: bool = False,
    ) -> int:
        """Mark notifications as read."""
        if mark_all:
            return await self.notif_repo.mark_all_read(user_id)
        elif notification_ids:
            return await self.notif_repo.mark_read(notification_ids, user_id)
        return 0

    async def get_preferences(self, user_id: int) -> list[dict]:
        """Get all notification preferences for a user.

        Returns all known types with their enabled/disabled status.
        """
        existing = await self.pref_repo.get_for_user(user_id)
        existing_map = {p["notification_type"]: bool(p["is_enabled"]) for p in existing}

        return [
            {
                "notification_type": nt,
                "is_enabled": existing_map.get(nt, False),
            }
            for nt in NOTIFICATION_TYPES
        ]

    async def update_preferences(
        self, user_id: int, preferences: list[dict]
    ) -> None:
        """Batch update notification preferences."""
        await self.pref_repo.bulk_set(user_id, preferences)

    async def cleanup_old_notifications(self, days: int = 30) -> int:
        """Delete notifications older than N days. Called by scheduler."""
        count = await self.notif_repo.cleanup_old(days)
        if count > 0:
            logger.info("Cleaned up %d old notifications (>%d days)", count, days)
        return count

    # ── Sound Settings (Phase 7E) ───────────────────────────────

    async def get_sound_settings(self, user_id: int) -> list[dict]:
        """Get per-type sound settings for a user.

        Returns all known types with sound_enabled / sound_file.
        Missing entries default to sound off.
        """
        rows = await self.db.execute_fetchall(
            "SELECT notification_type, sound_enabled, sound_file "
            "FROM notification_sounds WHERE user_id = ?",
            (user_id,),
        )
        existing_map = {
            r["notification_type"]: {
                "sound_enabled": bool(r["sound_enabled"]),
                "sound_file": r["sound_file"],
            }
            for r in rows
        }

        return [
            {
                "notification_type": nt,
                "sound_enabled": existing_map.get(nt, {}).get("sound_enabled", False),
                "sound_file": existing_map.get(nt, {}).get("sound_file", "chime.mp3"),
            }
            for nt in NOTIFICATION_TYPES
        ]

    async def update_sound_settings(
        self, user_id: int, settings: list[dict]
    ) -> int:
        """Batch upsert sound settings for a user."""
        for s in settings:
            await self.db.execute(
                """INSERT INTO notification_sounds
                        (user_id, notification_type, sound_enabled, sound_file)
                   VALUES (?, ?, ?, ?)
                   ON CONFLICT(user_id, notification_type)
                   DO UPDATE SET sound_enabled = excluded.sound_enabled,
                                 sound_file   = excluded.sound_file""",
                (user_id, s["notification_type"], int(s.get("sound_enabled", False)),
                 s.get("sound_file", "chime.mp3")),
            )
        await self.db.commit()
        return len(settings)
