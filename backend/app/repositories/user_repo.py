"""
User repository — data access for users, hats, and permissions.

Handles user CRUD, hat assignment, and permission resolution.
The permission model is additive: a user's effective permissions are
the UNION of all permissions from all their assigned hats, plus any
job-level elevations.
"""

from __future__ import annotations

from typing import Any

import aiosqlite

from app.repositories.base import BaseRepo


class UserRepo(BaseRepo):
    TABLE = "users"

    async def get_by_id_with_hats(self, user_id: int) -> dict | None:
        """Fetch a user with their assigned hats and aggregated permissions.

        Returns:
            dict with keys: id, display_name, ..., hats: [{id, name, level}],
            permissions: ["view_parts_catalog", "edit_pricing", ...]
        """
        # Get the user
        user = await self.get_by_id(user_id)
        if not user:
            return None

        # Get their hats
        cursor = await self.db.execute(
            """
            SELECT h.id, h.name, h.level
            FROM hats h
            JOIN user_hats uh ON uh.hat_id = h.id
            WHERE uh.user_id = ?
            ORDER BY h.level ASC
            """,
            (user_id,),
        )
        hats = await cursor.fetchall()

        # Get the UNION of all permissions from all hats
        cursor = await self.db.execute(
            """
            SELECT DISTINCT hp.permission_key
            FROM hat_permissions hp
            JOIN user_hats uh ON uh.hat_id = hp.hat_id
            WHERE uh.user_id = ?
            ORDER BY hp.permission_key
            """,
            (user_id,),
        )
        permissions = [row["permission_key"] for row in await cursor.fetchall()]

        user["hats"] = hats
        user["permissions"] = permissions
        return user

    async def get_active_users(self) -> list[dict]:
        """Get all active users with their hat names (for user picker)."""
        cursor = await self.db.execute(
            """
            SELECT u.id, u.display_name, u.avatar_url,
                   GROUP_CONCAT(h.name) as hat_names
            FROM users u
            LEFT JOIN user_hats uh ON uh.user_id = u.id
            LEFT JOIN hats h ON h.id = uh.hat_id
            WHERE u.is_active = 1
            GROUP BY u.id
            ORDER BY u.display_name
            """
        )
        rows = await cursor.fetchall()

        # Split hat_names CSV into a list
        for row in rows:
            hat_str = row.get("hat_names") or ""
            row["hats"] = [h.strip() for h in hat_str.split(",") if h.strip()]

        return rows

    async def get_by_email(self, email: str) -> dict | None:
        """Find a user by email address."""
        cursor = await self.db.execute(
            "SELECT * FROM users WHERE email = ? LIMIT 1",
            (email,),
        )
        return await cursor.fetchone()

    async def create_user(
        self,
        display_name: str,
        pin_hash: str,
        *,
        email: str | None = None,
        phone: str | None = None,
        hat_ids: list[int] | None = None,
        **extra_fields: Any,
    ) -> int:
        """Create a new user and optionally assign hats.

        Returns the new user's ID.
        """
        data = {
            "display_name": display_name,
            "pin_hash": pin_hash,
        }
        if email:
            data["email"] = email
        if phone:
            data["phone"] = phone
        data.update(extra_fields)

        user_id = await self.insert(data)

        # Assign hats if provided
        if hat_ids:
            for hat_id in hat_ids:
                await self.db.execute(
                    "INSERT OR IGNORE INTO user_hats (user_id, hat_id) VALUES (?, ?)",
                    (user_id, hat_id),
                )
            await self.db.commit()

        return user_id

    async def update_pin_hash(self, user_id: int, pin_hash: str) -> bool:
        """Update a user's PIN hash."""
        return await self.update(user_id, {"pin_hash": pin_hash})

    async def get_pin_hash(self, user_id: int) -> str | None:
        """Get just the PIN hash for a user (for verification)."""
        cursor = await self.db.execute(
            "SELECT pin_hash FROM users WHERE id = ? AND is_active = 1",
            (user_id,),
        )
        row = await cursor.fetchone()
        return row["pin_hash"] if row else None

    async def assign_hat(self, user_id: int, hat_id: int) -> None:
        """Assign a hat to a user (idempotent via INSERT OR IGNORE)."""
        await self.db.execute(
            "INSERT OR IGNORE INTO user_hats (user_id, hat_id) VALUES (?, ?)",
            (user_id, hat_id),
        )
        await self.db.commit()

    async def remove_hat(self, user_id: int, hat_id: int) -> None:
        """Remove a hat from a user."""
        await self.db.execute(
            "DELETE FROM user_hats WHERE user_id = ? AND hat_id = ?",
            (user_id, hat_id),
        )
        await self.db.commit()

    async def get_user_permissions(
        self,
        user_id: int,
        *,
        job_id: int | None = None,
    ) -> set[str]:
        """Get the full set of permission keys for a user.

        Includes:
        1. All permissions from all assigned hats (permanent)
        2. Any job-level elevations for the specified job (temporary)

        This is THE permission resolution function used by the auth middleware.
        """
        # Hat-based permissions
        cursor = await self.db.execute(
            """
            SELECT DISTINCT hp.permission_key
            FROM hat_permissions hp
            JOIN user_hats uh ON uh.hat_id = hp.hat_id
            WHERE uh.user_id = ?
            """,
            (user_id,),
        )
        permissions = {row["permission_key"] for row in await cursor.fetchall()}

        # Job-level elevations (if a job context is provided)
        if job_id is not None:
            cursor = await self.db.execute(
                """
                SELECT permission_key
                FROM job_lead_elevations
                WHERE user_id = ? AND job_id = ?
                  AND (expires_at IS NULL OR expires_at > datetime('now'))
                """,
                (user_id, job_id),
            )
            for row in await cursor.fetchall():
                permissions.add(row["permission_key"])

        return permissions


class HatRepo(BaseRepo):
    """Repository for hat (role) management."""

    TABLE = "hats"

    async def get_all_with_permissions(self) -> list[dict]:
        """Get all hats with their permission keys."""
        cursor = await self.db.execute(
            "SELECT * FROM hats ORDER BY level ASC"
        )
        hats = await cursor.fetchall()

        for hat in hats:
            perm_cursor = await self.db.execute(
                "SELECT permission_key FROM hat_permissions WHERE hat_id = ? ORDER BY permission_key",
                (hat["id"],),
            )
            hat["permissions"] = [
                row["permission_key"] for row in await perm_cursor.fetchall()
            ]

        return hats

    async def get_by_name(self, name: str) -> dict | None:
        """Find a hat by name."""
        cursor = await self.db.execute(
            "SELECT * FROM hats WHERE name = ? LIMIT 1",
            (name,),
        )
        return await cursor.fetchone()
