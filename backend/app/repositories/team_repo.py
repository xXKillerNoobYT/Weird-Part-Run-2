"""
Employee-team repositories — teams and team membership.

Handles data access for the global employee-teams feature (Phase 16 P6).
Uses BaseRepo for standard CRUD, plus domain-specific queries for
membership management and team listings with member counts.
"""

from __future__ import annotations

from app.repositories.base import BaseRepo


class EmployeeTeamRepo(BaseRepo):
    """Repository for the employee_teams table."""

    TABLE = "employee_teams"
    HAS_UPDATED_AT = True
    TRACK_CHANGES = True

    async def get_all_with_counts(
        self,
        *,
        active_only: bool = True,
    ) -> list[dict]:
        """List all teams with member counts and lead info."""
        where = "WHERE t.is_active = 1" if active_only else ""
        sql = f"""
            SELECT
                t.*,
                u.display_name AS lead_name,
                COUNT(m.id) AS member_count
            FROM employee_teams t
            LEFT JOIN users u ON u.id = t.lead_user_id
            LEFT JOIN employee_team_members m ON m.team_id = t.id
            {where}
            GROUP BY t.id
            ORDER BY t.name ASC
        """
        cursor = await self.db.execute(sql)
        rows = await cursor.fetchall()
        return [dict(r) for r in rows]

    async def get_by_name(self, name: str) -> dict | None:
        """Find a team by name (case-insensitive)."""
        cursor = await self.db.execute(
            "SELECT * FROM employee_teams WHERE LOWER(name) = LOWER(?)",
            (name,),
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

    async def get_with_members(self, team_id: int) -> dict | None:
        """Get a single team with its full member list."""
        team = await self.get_by_id(team_id)
        if not team:
            return None

        cursor = await self.db.execute(
            """
            SELECT
                m.id,
                m.team_id,
                m.user_id,
                m.role,
                m.joined_at,
                u.display_name,
                u.avatar_url,
                u.is_active AS user_is_active
            FROM employee_team_members m
            JOIN users u ON u.id = m.user_id
            WHERE m.team_id = ?
            ORDER BY
                CASE m.role WHEN 'lead' THEN 0 ELSE 1 END,
                u.display_name ASC
            """,
            (team_id,),
        )
        rows = await cursor.fetchall()
        members = [dict(r) for r in rows]

        # Also grab lead name
        if team.get("lead_user_id"):
            lead_cursor = await self.db.execute(
                "SELECT display_name FROM users WHERE id = ?",
                (team["lead_user_id"],),
            )
            lead_row = await lead_cursor.fetchone()
            team["lead_name"] = lead_row["display_name"] if lead_row else None
        else:
            team["lead_name"] = None

        team["members"] = members
        team["member_count"] = len(members)
        return team


class EmployeeTeamMemberRepo(BaseRepo):
    """Repository for the employee_team_members table."""

    TABLE = "employee_team_members"
    HAS_UPDATED_AT = False
    TRACK_CHANGES = True

    async def get_for_team(self, team_id: int) -> list[dict]:
        """Get all members of a team with user info."""
        cursor = await self.db.execute(
            """
            SELECT
                m.id,
                m.team_id,
                m.user_id,
                m.role,
                m.joined_at,
                u.display_name,
                u.avatar_url,
                u.is_active AS user_is_active
            FROM employee_team_members m
            JOIN users u ON u.id = m.user_id
            WHERE m.team_id = ?
            ORDER BY
                CASE m.role WHEN 'lead' THEN 0 ELSE 1 END,
                u.display_name ASC
            """,
            (team_id,),
        )
        rows = await cursor.fetchall()
        return [dict(r) for r in rows]

    async def find_membership(self, team_id: int, user_id: int) -> dict | None:
        """Check if a user is already in a team."""
        cursor = await self.db.execute(
            "SELECT * FROM employee_team_members WHERE team_id = ? AND user_id = ?",
            (team_id, user_id),
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

    async def get_teams_for_user(self, user_id: int) -> list[dict]:
        """Get all teams a user belongs to."""
        cursor = await self.db.execute(
            """
            SELECT
                t.id, t.name, t.description, t.is_active,
                m.role, m.joined_at
            FROM employee_team_members m
            JOIN employee_teams t ON t.id = m.team_id
            WHERE m.user_id = ?
            ORDER BY t.name ASC
            """,
            (user_id,),
        )
        rows = await cursor.fetchall()
        return [dict(r) for r in rows]

    async def remove_member(self, team_id: int, user_id: int) -> bool:
        """Remove a member from a team. Returns True if removed."""
        cursor = await self.db.execute(
            "DELETE FROM employee_team_members WHERE team_id = ? AND user_id = ?",
            (team_id, user_id),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def update_role(self, team_id: int, user_id: int, role: str) -> bool:
        """Update a member's role within a team."""
        cursor = await self.db.execute(
            "UPDATE employee_team_members SET role = ? WHERE team_id = ? AND user_id = ?",
            (role, team_id, user_id),
        )
        await self.db.commit()
        return cursor.rowcount > 0
