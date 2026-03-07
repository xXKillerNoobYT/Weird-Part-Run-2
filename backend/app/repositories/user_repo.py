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
    HAS_UPDATED_AT = True

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

    # ── People module helpers (Phase 8) ──────────────────────────

    async def list_employees(
        self,
        *,
        search: str | None = None,
        is_active: bool | None = None,
        hat_id: int | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """Paginated employee list with hat names and active cert count.

        Supports text search (display_name, email, phone) and filtering
        by active status and hat assignment.
        """
        conditions: list[str] = []
        params: list[Any] = []

        if is_active is not None:
            conditions.append("u.is_active = ?")
            params.append(1 if is_active else 0)

        if hat_id is not None:
            conditions.append(
                "u.id IN (SELECT user_id FROM user_hats WHERE hat_id = ?)"
            )
            params.append(hat_id)

        if search:
            conditions.append(
                "(u.display_name LIKE ? OR u.email LIKE ? OR u.phone LIKE ?)"
            )
            term = f"%{search}%"
            params.extend([term, term, term])

        where = " AND ".join(conditions) if conditions else "1=1"

        cursor = await self.db.execute(
            f"""
            SELECT u.id, u.display_name, u.email, u.phone,
                   u.certification, u.hire_date, u.pay_rate,
                   u.is_active, u.avatar_url,
                   GROUP_CONCAT(DISTINCT h.name) AS hat_names,
                   (SELECT COUNT(*) FROM certifications c
                    WHERE c.user_id = u.id AND c.is_active = 1) AS active_cert_count
            FROM users u
            LEFT JOIN user_hats uh ON uh.user_id = u.id
            LEFT JOIN hats h ON h.id = uh.hat_id
            WHERE {where}
            GROUP BY u.id
            ORDER BY u.display_name ASC
            LIMIT ? OFFSET ?
            """,
            (*params, limit, offset),
        )
        rows = await cursor.fetchall()

        # Split hat_names CSV into a list
        for row in rows:
            hat_str = row.get("hat_names") or ""
            row["hat_names"] = [h.strip() for h in hat_str.split(",") if h.strip()]

        return rows

    async def count_employees(
        self,
        *,
        search: str | None = None,
        is_active: bool | None = None,
        hat_id: int | None = None,
    ) -> int:
        """Count employees matching the given filters (for pagination)."""
        conditions: list[str] = []
        params: list[Any] = []

        if is_active is not None:
            conditions.append("u.is_active = ?")
            params.append(1 if is_active else 0)

        if hat_id is not None:
            conditions.append(
                "u.id IN (SELECT user_id FROM user_hats WHERE hat_id = ?)"
            )
            params.append(hat_id)

        if search:
            conditions.append(
                "(u.display_name LIKE ? OR u.email LIKE ? OR u.phone LIKE ?)"
            )
            term = f"%{search}%"
            params.extend([term, term, term])

        where = " AND ".join(conditions) if conditions else "1=1"

        cursor = await self.db.execute(
            f"SELECT COUNT(*) AS cnt FROM users u WHERE {where}",
            tuple(params),
        )
        row = await cursor.fetchone()
        return row["cnt"] if row else 0

    async def toggle_active(self, user_id: int, is_active: bool) -> bool:
        """Activate or deactivate an employee."""
        return await self.update(user_id, {"is_active": 1 if is_active else 0})

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

    # ── Job Lead Elevations (Phase 10) ────────────────────────────

    async def get_job_lead_elevations(self, user_id: int) -> list[dict]:
        """Get all active elevations for a user, with job and granter names."""
        cursor = await self.db.execute(
            """SELECT jle.*, j.job_name AS job_name,
                      u.display_name AS granted_by_name
               FROM job_lead_elevations jle
               JOIN jobs j ON j.id = jle.job_id
               LEFT JOIN users u ON u.id = jle.granted_by
               WHERE jle.user_id = ?
                 AND (jle.expires_at IS NULL OR jle.expires_at > datetime('now'))
               ORDER BY j.job_name ASC""",
            (user_id,),
        )
        return await cursor.fetchall()

    async def get_elevations_for_job(self, job_id: int) -> list[dict]:
        """Get all active elevations for a specific job, with user names."""
        cursor = await self.db.execute(
            """SELECT jle.*, u.display_name AS user_name,
                      g.display_name AS granted_by_name
               FROM job_lead_elevations jle
               JOIN users u ON u.id = jle.user_id
               LEFT JOIN users g ON g.id = jle.granted_by
               WHERE jle.job_id = ?
                 AND (jle.expires_at IS NULL OR jle.expires_at > datetime('now'))
               ORDER BY u.display_name ASC""",
            (job_id,),
        )
        return await cursor.fetchall()

    async def grant_elevation(
        self,
        user_id: int,
        job_id: int,
        permission_key: str,
        granted_by: int,
    ) -> int:
        """Grant a job-level permission elevation. Returns the row ID.

        Uses INSERT OR IGNORE so duplicates are silently skipped.
        If the elevation already exists, returns the existing row ID.
        """
        cursor = await self.db.execute(
            """INSERT OR IGNORE INTO job_lead_elevations
               (user_id, job_id, permission_key, granted_by)
               VALUES (?, ?, ?, ?)""",
            (user_id, job_id, permission_key, granted_by),
        )
        await self.db.commit()

        if cursor.lastrowid:
            return cursor.lastrowid  # type: ignore[return-value]

        # Already existed — fetch the existing row ID
        cursor = await self.db.execute(
            """SELECT id FROM job_lead_elevations
               WHERE user_id = ? AND job_id = ? AND permission_key = ?""",
            (user_id, job_id, permission_key),
        )
        row = await cursor.fetchone()
        return row["id"] if row else 0

    async def revoke_elevation(self, elevation_id: int) -> bool:
        """Revoke a single elevation by ID."""
        cursor = await self.db.execute(
            "DELETE FROM job_lead_elevations WHERE id = ?",
            (elevation_id,),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def revoke_all_for_job(self, user_id: int, job_id: int) -> int:
        """Revoke all elevations for a user on a specific job.

        Returns the number of revoked elevations.
        """
        cursor = await self.db.execute(
            "DELETE FROM job_lead_elevations WHERE user_id = ? AND job_id = ?",
            (user_id, job_id),
        )
        await self.db.commit()
        return cursor.rowcount


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

    async def get_all_with_user_counts(self) -> list[dict]:
        """Get all hats with permission lists AND user counts."""
        cursor = await self.db.execute(
            """
            SELECT h.*,
                   (SELECT COUNT(*) FROM user_hats uh WHERE uh.hat_id = h.id) AS user_count
            FROM hats h
            ORDER BY h.level ASC
            """
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

    async def replace_permissions(self, hat_id: int, permission_keys: list[str]) -> None:
        """Replace ALL permissions for a hat with the given list.

        This is an atomic delete-then-insert operation.
        """
        await self.db.execute(
            "DELETE FROM hat_permissions WHERE hat_id = ?",
            (hat_id,),
        )
        for key in permission_keys:
            await self.db.execute(
                "INSERT INTO hat_permissions (hat_id, permission_key) VALUES (?, ?)",
                (hat_id, key),
            )
        await self.db.commit()

    async def get_all_permission_keys(self) -> list[str]:
        """Get all unique permission keys across all hats, sorted."""
        cursor = await self.db.execute(
            "SELECT DISTINCT permission_key FROM hat_permissions ORDER BY permission_key"
        )
        return [row["permission_key"] for row in await cursor.fetchall()]
