"""
People-specific repositories — certifications, wage history, notes, skills.

Each repo class handles data access for one of the Phase 8 companion tables.
All inherit from BaseRepo for standard CRUD, then add domain-specific queries.
"""

from __future__ import annotations

from app.repositories.base import BaseRepo


class CertificationRepo(BaseRepo):
    """Repository for employee certifications."""

    TABLE = "certifications"
    HAS_UPDATED_AT = True

    async def get_for_user(self, user_id: int, *, active_only: bool = False) -> list[dict]:
        """Get all certifications for an employee, newest first."""
        where = "user_id = ?"
        params: list = [user_id]
        if active_only:
            where += " AND is_active = 1"

        return await self.get_all(
            where=where,
            params=tuple(params),
            order_by="expiry_date ASC",  # soonest-expiring first
            limit=100,
        )

    async def get_expiring_soon(self, days: int = 30) -> list[dict]:
        """Get certifications expiring within N days (for alerts).

        Returns certs across ALL employees, joined with user display_name.
        """
        cursor = await self.db.execute(
            """
            SELECT c.*, u.display_name AS user_name
            FROM certifications c
            JOIN users u ON u.id = c.user_id
            WHERE c.is_active = 1
              AND c.expiry_date IS NOT NULL
              AND c.expiry_date <= date('now', '+' || ? || ' days')
              AND c.expiry_date >= date('now')
            ORDER BY c.expiry_date ASC
            """,
            (days,),
        )
        return await cursor.fetchall()

    async def count_active_for_user(self, user_id: int) -> int:
        """Count active certifications for a user."""
        return await self.count(
            where="user_id = ? AND is_active = 1",
            params=(user_id,),
        )


class WageHistoryRepo(BaseRepo):
    """Repository for pay rate history (immutable audit trail)."""

    TABLE = "wage_history"
    HAS_UPDATED_AT = False  # wage history is immutable — no updates

    async def get_for_user(self, user_id: int) -> list[dict]:
        """Get full wage history for an employee, newest first.

        Joins changed_by to get the changer's display_name.
        """
        cursor = await self.db.execute(
            """
            SELECT wh.*,
                   u.display_name AS changed_by_name
            FROM wage_history wh
            LEFT JOIN users u ON u.id = wh.changed_by
            WHERE wh.user_id = ?
            ORDER BY wh.effective_date DESC, wh.id DESC
            """,
            (user_id,),
        )
        return await cursor.fetchall()

    async def get_latest(self, user_id: int) -> dict | None:
        """Get the most recent wage entry for a user."""
        cursor = await self.db.execute(
            """
            SELECT * FROM wage_history
            WHERE user_id = ?
            ORDER BY effective_date DESC, id DESC
            LIMIT 1
            """,
            (user_id,),
        )
        return await cursor.fetchone()


class EmployeeNoteRepo(BaseRepo):
    """Repository for HR-style employee notes."""

    TABLE = "employee_notes"
    HAS_UPDATED_AT = True

    async def get_for_user(
        self,
        user_id: int,
        *,
        include_private: bool = False,
        note_type: str | None = None,
    ) -> list[dict]:
        """Get notes for an employee, newest first.

        Joins created_by for author name. Private notes are hidden
        unless include_private=True (requires manage_people).
        """
        conditions = ["en.user_id = ?"]
        params: list = [user_id]

        if not include_private:
            conditions.append("en.is_private = 0")

        if note_type:
            conditions.append("en.note_type = ?")
            params.append(note_type)

        where = " AND ".join(conditions)

        cursor = await self.db.execute(
            f"""
            SELECT en.*,
                   u.display_name AS created_by_name
            FROM employee_notes en
            LEFT JOIN users u ON u.id = en.created_by
            WHERE {where}
            ORDER BY en.created_at DESC
            """,
            tuple(params),
        )
        return await cursor.fetchall()

    async def count_for_user(self, user_id: int, *, include_private: bool = False) -> int:
        """Count notes for an employee."""
        if include_private:
            return await self.count(where="user_id = ?", params=(user_id,))
        return await self.count(
            where="user_id = ? AND is_private = 0",
            params=(user_id,),
        )


class UserSkillRepo(BaseRepo):
    """Repository for user skills and proficiency tracking."""

    TABLE = "user_skills"
    HAS_UPDATED_AT = False  # no updated_at column

    async def get_for_user(self, user_id: int) -> list[dict]:
        """Get all skills for an employee, with verifier name.

        Sorted by proficiency level (expert first) then alphabetically.
        """
        cursor = await self.db.execute(
            """
            SELECT us.*,
                   u.display_name AS verified_by_name
            FROM user_skills us
            LEFT JOIN users u ON u.id = us.verified_by
            WHERE us.user_id = ?
            ORDER BY
                CASE us.proficiency
                    WHEN 'expert' THEN 1
                    WHEN 'advanced' THEN 2
                    WHEN 'intermediate' THEN 3
                    WHEN 'beginner' THEN 4
                END,
                us.skill_name ASC
            """,
            (user_id,),
        )
        return await cursor.fetchall()

    async def get_by_skill_name(self, skill_name: str) -> list[dict]:
        """Find all employees with a specific skill (for team assembly)."""
        cursor = await self.db.execute(
            """
            SELECT us.*, u.display_name AS user_name
            FROM user_skills us
            JOIN users u ON u.id = us.user_id
            WHERE us.skill_name = ?
            ORDER BY
                CASE us.proficiency
                    WHEN 'expert' THEN 1
                    WHEN 'advanced' THEN 2
                    WHEN 'intermediate' THEN 3
                    WHEN 'beginner' THEN 4
                END
            """,
            (skill_name,),
        )
        return await cursor.fetchall()
