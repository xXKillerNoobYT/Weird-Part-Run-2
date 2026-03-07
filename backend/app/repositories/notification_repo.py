"""
Repositories for the cross-module notification system.

Notifications are persisted with 30-day auto-cleanup.
Preferences are per-user, tied to the hat/role system.
"""

from __future__ import annotations

from typing import Any

import aiosqlite

from app.repositories.base import BaseRepo


class NotificationRepo(BaseRepo):
    TABLE = "notifications"

    async def get_for_user(
        self,
        user_id: int,
        *,
        unread_only: bool = False,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """Get notifications for a user, newest first."""
        sql = "SELECT * FROM notifications WHERE user_id = ?"
        params: list[Any] = [user_id]

        if unread_only:
            sql += " AND is_read = 0"

        sql += " ORDER BY created_at DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])

        cursor = await self.db.execute(sql, tuple(params))
        return await cursor.fetchall()

    async def count_unread(self, user_id: int) -> int:
        """Count unread notifications for the bell badge."""
        cursor = await self.db.execute(
            "SELECT COUNT(*) as cnt FROM notifications WHERE user_id = ? AND is_read = 0",
            (user_id,),
        )
        row = await cursor.fetchone()
        return row["cnt"] if row else 0

    async def mark_read(self, notification_ids: list[int], user_id: int) -> int:
        """Mark specific notifications as read. Returns count updated."""
        if not notification_ids:
            return 0
        placeholders = ", ".join("?" for _ in notification_ids)
        cursor = await self.db.execute(
            f"UPDATE notifications SET is_read = 1 WHERE id IN ({placeholders}) AND user_id = ?",  # noqa: S608
            (*notification_ids, user_id),
        )
        await self.db.commit()
        return cursor.rowcount

    async def mark_all_read(self, user_id: int) -> int:
        """Mark all notifications as read for a user."""
        cursor = await self.db.execute(
            "UPDATE notifications SET is_read = 1 WHERE user_id = ? AND is_read = 0",
            (user_id,),
        )
        await self.db.commit()
        return cursor.rowcount

    async def cleanup_old(self, days: int = 30) -> int:
        """Delete notifications older than N days. Returns count deleted."""
        cursor = await self.db.execute(
            "DELETE FROM notifications WHERE created_at < datetime('now', ?)",
            (f"-{days} days",),
        )
        await self.db.commit()
        return cursor.rowcount

    async def create_for_users(
        self,
        user_ids: list[int],
        type: str,
        title: str,
        message: str | None = None,
        link: str | None = None,
        entity_type: str | None = None,
        entity_id: int | None = None,
    ) -> list[int]:
        """Create a notification for multiple users at once."""
        ids = []
        for uid in user_ids:
            new_id = await self.insert({
                "user_id": uid,
                "type": type,
                "title": title,
                "message": message,
                "link": link,
                "entity_type": entity_type,
                "entity_id": entity_id,
            })
            ids.append(new_id)
        return ids


class NotificationPrefRepo(BaseRepo):
    TABLE = "notification_preferences"

    async def get_for_user(self, user_id: int) -> list[dict]:
        """Get all notification preferences for a user."""
        cursor = await self.db.execute(
            "SELECT * FROM notification_preferences WHERE user_id = ? ORDER BY notification_type",
            (user_id,),
        )
        return await cursor.fetchall()

    async def set_preference(
        self, user_id: int, notification_type: str, is_enabled: bool
    ) -> None:
        """Upsert a notification preference."""
        await self.db.execute(
            """
            INSERT INTO notification_preferences (user_id, notification_type, is_enabled)
            VALUES (?, ?, ?)
            ON CONFLICT(user_id, notification_type)
            DO UPDATE SET is_enabled = excluded.is_enabled
            """,
            (user_id, notification_type, int(is_enabled)),
        )
        await self.db.commit()

    async def bulk_set(self, user_id: int, prefs: list[dict]) -> None:
        """Set multiple preferences at once."""
        for pref in prefs:
            await self.set_preference(
                user_id, pref["notification_type"], pref["is_enabled"]
            )

    async def is_enabled(self, user_id: int, notification_type: str) -> bool:
        """Check if a specific notification type is enabled for a user.

        Defaults to True (opt-out system) — notifications are ON unless
        the user explicitly disables them.
        """
        cursor = await self.db.execute(
            "SELECT is_enabled FROM notification_preferences WHERE user_id = ? AND notification_type = ?",
            (user_id, notification_type),
        )
        row = await cursor.fetchone()
        return bool(row["is_enabled"]) if row else True

    async def get_users_with_enabled(self, notification_type: str) -> list[int]:
        """Get all user IDs that have a specific notification type enabled."""
        cursor = await self.db.execute(
            "SELECT user_id FROM notification_preferences WHERE notification_type = ? AND is_enabled = 1",
            (notification_type,),
        )
        rows = await cursor.fetchall()
        return [row["user_id"] for row in rows]
