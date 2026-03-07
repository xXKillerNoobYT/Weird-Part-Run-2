"""
Scheduling repositories — default schedules, exceptions (time off),
job dispatch, and subcontractor schedules.

Each repo extends BaseRepo for standard CRUD and adds domain-specific
queries (date-range filtering, conflict detection, calendar assembly).
"""

from __future__ import annotations

from typing import Any

import aiosqlite

from .base import BaseRepo


# ── DefaultScheduleRepo ───────────────────────────────────────────

class DefaultScheduleRepo(BaseRepo):
    """Employee weekly schedule patterns (7 rows per employee)."""

    TABLE = "employee_default_schedules"

    async def get_for_user(self, user_id: int) -> list[dict]:
        """Get all 7 day-of-week entries for an employee, ordered Sun→Sat."""
        cursor = await self.db.execute(
            """SELECT * FROM employee_default_schedules
               WHERE user_id = ?
               ORDER BY day_of_week ASC""",
            (user_id,),
        )
        return await cursor.fetchall()

    async def bulk_upsert(self, user_id: int, days: list[dict]) -> None:
        """Replace the full 7-day schedule for an employee.

        Uses INSERT OR REPLACE on the UNIQUE(user_id, day_of_week) constraint.
        """
        for day in days:
            await self.db.execute(
                """INSERT OR REPLACE INTO employee_default_schedules
                   (user_id, day_of_week, start_time, end_time,
                    lunch_start, lunch_end, is_working_day, notes)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    user_id,
                    day["day_of_week"],
                    day.get("start_time", "07:00"),
                    day.get("end_time", "15:30"),
                    day.get("lunch_start"),
                    day.get("lunch_end"),
                    1 if day.get("is_working_day", True) else 0,
                    day.get("notes"),
                ),
            )
        await self.db.commit()

    async def init_defaults(self, user_id: int) -> None:
        """Create standard Mon-Fri 07:00-15:30 schedule for a new user."""
        for dow in range(7):
            is_working = 1 if 1 <= dow <= 5 else 0  # Mon-Fri
            await self.db.execute(
                """INSERT OR IGNORE INTO employee_default_schedules
                   (user_id, day_of_week, start_time, end_time, is_working_day)
                   VALUES (?, ?, '07:00', '15:30', ?)""",
                (user_id, dow, is_working),
            )
        await self.db.commit()

    async def get_for_user_day(self, user_id: int, day_of_week: int) -> dict | None:
        """Get the schedule for a specific day."""
        cursor = await self.db.execute(
            """SELECT * FROM employee_default_schedules
               WHERE user_id = ? AND day_of_week = ?""",
            (user_id, day_of_week),
        )
        return await cursor.fetchone()


# ── ScheduleExceptionRepo ─────────────────────────────────────────

class ScheduleExceptionRepo(BaseRepo):
    """Time off requests and other schedule overrides."""

    TABLE = "schedule_exceptions"

    async def get_pending(self, limit: int = 100) -> list[dict]:
        """Get all unapproved exceptions, newest first, with user name."""
        cursor = await self.db.execute(
            """SELECT se.*, u.display_name AS user_name
               FROM schedule_exceptions se
               JOIN users u ON u.id = se.user_id
               WHERE se.is_approved = 0
               ORDER BY se.exception_date ASC
               LIMIT ?""",
            (limit,),
        )
        return await cursor.fetchall()

    async def get_for_user(
        self,
        user_id: int,
        date_from: str | None = None,
        date_to: str | None = None,
    ) -> list[dict]:
        """Get exceptions for a user, optionally within a date range."""
        conditions = ["se.user_id = ?"]
        params: list[Any] = [user_id]

        if date_from:
            conditions.append("se.exception_date >= ?")
            params.append(date_from)
        if date_to:
            conditions.append("se.exception_date <= ?")
            params.append(date_to)

        where = " AND ".join(conditions)
        cursor = await self.db.execute(
            f"""SELECT se.*,
                       u.display_name AS user_name,
                       a.display_name AS approved_by_name
                FROM schedule_exceptions se
                JOIN users u ON u.id = se.user_id
                LEFT JOIN users a ON a.id = se.approved_by
                WHERE {where}
                ORDER BY se.exception_date ASC""",
            params,
        )
        return await cursor.fetchall()

    async def get_for_date(self, user_id: int, date: str) -> dict | None:
        """Check if a user has an exception on a specific date."""
        cursor = await self.db.execute(
            """SELECT * FROM schedule_exceptions
               WHERE user_id = ? AND exception_date = ?""",
            (user_id, date),
        )
        return await cursor.fetchone()

    async def get_for_date_range(
        self, date_from: str, date_to: str
    ) -> list[dict]:
        """Get all exceptions in a date range (all users), for calendar view."""
        cursor = await self.db.execute(
            """SELECT se.*, u.display_name AS user_name
               FROM schedule_exceptions se
               JOIN users u ON u.id = se.user_id
               WHERE se.exception_date >= ? AND se.exception_date <= ?
               ORDER BY se.exception_date ASC, u.display_name ASC""",
            (date_from, date_to),
        )
        return await cursor.fetchall()

    async def approve(self, exception_id: int, approved_by: int) -> bool:
        """Approve a time-off request."""
        cursor = await self.db.execute(
            """UPDATE schedule_exceptions
               SET is_approved = 1, approved_by = ?, approved_at = datetime('now')
               WHERE id = ?""",
            (approved_by, exception_id),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def deny(self, exception_id: int) -> bool:
        """Deny (delete) a time-off request."""
        return await self.delete(exception_id)


# ── JobDispatchRepo ───────────────────────────────────────────────

class JobDispatchRepo(BaseRepo):
    """Daily employee-to-job dispatch assignments."""

    TABLE = "job_dispatch"
    HAS_UPDATED_AT = True

    async def get_for_date(self, date: str) -> list[dict]:
        """Get all dispatches for a date, with user and job names."""
        cursor = await self.db.execute(
            """SELECT d.*, u.display_name AS user_name,
                      j.job_name AS job_name,
                      disp.display_name AS dispatched_by_name
               FROM job_dispatch d
               JOIN users u ON u.id = d.user_id
               JOIN jobs j ON j.id = d.job_id
               LEFT JOIN users disp ON disp.id = d.dispatched_by
               WHERE d.dispatch_date = ?
               ORDER BY j.job_name ASC, u.display_name ASC""",
            (date,),
        )
        return await cursor.fetchall()

    async def get_for_user(
        self, user_id: int, date_from: str, date_to: str
    ) -> list[dict]:
        """Get dispatches for a user within a date range."""
        cursor = await self.db.execute(
            """SELECT d.*, j.job_name AS job_name
               FROM job_dispatch d
               JOIN jobs j ON j.id = d.job_id
               WHERE d.user_id = ?
                 AND d.dispatch_date >= ? AND d.dispatch_date <= ?
               ORDER BY d.dispatch_date ASC""",
            (user_id, date_from, date_to),
        )
        return await cursor.fetchall()

    async def get_for_job(
        self, job_id: int, date_from: str | None = None, date_to: str | None = None
    ) -> list[dict]:
        """Get dispatches for a job, optionally within a date range."""
        conditions = ["d.job_id = ?"]
        params: list[Any] = [job_id]

        if date_from:
            conditions.append("d.dispatch_date >= ?")
            params.append(date_from)
        if date_to:
            conditions.append("d.dispatch_date <= ?")
            params.append(date_to)

        where = " AND ".join(conditions)
        cursor = await self.db.execute(
            f"""SELECT d.*, u.display_name AS user_name
                FROM job_dispatch d
                JOIN users u ON u.id = d.user_id
                WHERE {where}
                ORDER BY d.dispatch_date ASC, u.display_name ASC""",
            params,
        )
        return await cursor.fetchall()

    async def check_conflicts(self, user_id: int, date: str) -> list[dict]:
        """Check for scheduling conflicts on a given date.

        Returns a list of conflict dicts with type and description.
        Checks:
        1. Already dispatched to another job
        2. Has approved time off
        3. Not a working day per default schedule
        """
        conflicts: list[dict] = []

        # 1. Existing dispatches (not cancelled)
        cursor = await self.db.execute(
            """SELECT d.id, d.job_id, j.job_name AS job_name,
                      d.shift_start, d.shift_end, d.role_on_job
               FROM job_dispatch d
               JOIN jobs j ON j.id = d.job_id
               WHERE d.user_id = ? AND d.dispatch_date = ?
                 AND d.status NOT IN ('cancelled')""",
            (user_id, date),
        )
        for row in await cursor.fetchall():
            conflicts.append({
                "conflict_type": "already_dispatched",
                "description": f"Already dispatched to {row['job_name']}",
                "related_job_id": row["job_id"],
                "related_job_name": row["job_name"],
                "shift_start": row["shift_start"],
                "shift_end": row["shift_end"],
                "role_on_job": row["role_on_job"],
            })

        # 2. Approved time off
        cursor = await self.db.execute(
            """SELECT exception_type, reason
               FROM schedule_exceptions
               WHERE user_id = ? AND exception_date = ? AND is_approved = 1""",
            (user_id, date),
        )
        exc = await cursor.fetchone()
        if exc:
            conflicts.append({
                "conflict_type": "time_off",
                "description": f"Has approved {exc['exception_type']}"
                               + (f": {exc['reason']}" if exc["reason"] else ""),
                "related_job_id": None,
                "related_job_name": None,
            })

        # 3. Not a working day
        # Convert ISO date to day_of_week (0=Mon in Python, but we store 0=Sun)
        from datetime import date as dt_date
        d = dt_date.fromisoformat(date)
        # Python: Monday=0, Sunday=6  →  Our schema: Sunday=0, Monday=1, ...
        dow = (d.weekday() + 1) % 7

        cursor = await self.db.execute(
            """SELECT is_working_day
               FROM employee_default_schedules
               WHERE user_id = ? AND day_of_week = ?""",
            (user_id, dow),
        )
        sched = await cursor.fetchone()
        if sched and not sched["is_working_day"]:
            day_names = ["Sunday", "Monday", "Tuesday", "Wednesday",
                         "Thursday", "Friday", "Saturday"]
            conflicts.append({
                "conflict_type": "not_working_day",
                "description": f"{day_names[dow]} is not a working day",
                "related_job_id": None,
                "related_job_name": None,
            })

        return conflicts

    async def get_available_employees(self, date: str) -> list[dict]:
        """Get employees who are working that day and not on time off.

        Returns user info + count of existing dispatches for the date.
        """
        from datetime import date as dt_date
        d = dt_date.fromisoformat(date)
        dow = (d.weekday() + 1) % 7

        cursor = await self.db.execute(
            """SELECT u.id, u.display_name,
                      ds.start_time AS default_start,
                      ds.end_time AS default_end,
                      (SELECT COUNT(*) FROM job_dispatch jd
                       WHERE jd.user_id = u.id AND jd.dispatch_date = ?
                         AND jd.status NOT IN ('cancelled')) AS current_dispatches
               FROM users u
               JOIN employee_default_schedules ds ON ds.user_id = u.id
                                                  AND ds.day_of_week = ?
               WHERE u.is_active = 1
                 AND ds.is_working_day = 1
                 AND u.id NOT IN (
                     SELECT user_id FROM schedule_exceptions
                     WHERE exception_date = ? AND is_approved = 1
                       AND start_time IS NULL  -- full day off only
                 )
               ORDER BY u.display_name ASC""",
            (date, dow, date),
        )
        return await cursor.fetchall()

    async def get_for_date_range(
        self, date_from: str, date_to: str
    ) -> list[dict]:
        """Get all dispatches in a date range (all users), for calendar view."""
        cursor = await self.db.execute(
            """SELECT d.*, u.display_name AS user_name, j.job_name AS job_name
               FROM job_dispatch d
               JOIN users u ON u.id = d.user_id
               JOIN jobs j ON j.id = d.job_id
               WHERE d.dispatch_date >= ? AND d.dispatch_date <= ?
               ORDER BY d.dispatch_date ASC, u.display_name ASC""",
            (date_from, date_to),
        )
        return await cursor.fetchall()


# ── SubcontractorScheduleRepo ─────────────────────────────────────

class SubcontractorScheduleRepo(BaseRepo):
    """Subcontractor (GC) visit schedules at our job sites."""

    TABLE = "subcontractor_schedules"
    HAS_UPDATED_AT = True

    async def get_for_job(
        self,
        job_id: int,
        date_from: str | None = None,
        date_to: str | None = None,
    ) -> list[dict]:
        """Get sub schedules for a job, optionally within a date range."""
        conditions = ["ss.job_id = ?"]
        params: list[Any] = [job_id]

        if date_from:
            conditions.append("ss.scheduled_date >= ?")
            params.append(date_from)
        if date_to:
            conditions.append("ss.scheduled_date <= ?")
            params.append(date_to)

        where = " AND ".join(conditions)
        cursor = await self.db.execute(
            f"""SELECT ss.*, g.company_name AS gc_name, g.gc_code,
                       j.job_name AS job_name
                FROM subcontractor_schedules ss
                JOIN general_contractors g ON g.id = ss.gc_id
                JOIN jobs j ON j.id = ss.job_id
                WHERE {where}
                ORDER BY ss.scheduled_date ASC""",
            params,
        )
        return await cursor.fetchall()

    async def get_for_date(self, date: str) -> list[dict]:
        """Get all sub schedules for a date across all jobs."""
        cursor = await self.db.execute(
            """SELECT ss.*, g.company_name AS gc_name, g.gc_code,
                      j.job_name AS job_name
               FROM subcontractor_schedules ss
               JOIN general_contractors g ON g.id = ss.gc_id
               JOIN jobs j ON j.id = ss.job_id
               WHERE ss.scheduled_date = ?
               ORDER BY j.job_name ASC, g.company_name ASC""",
            (date,),
        )
        return await cursor.fetchall()

    async def get_for_date_range(
        self, date_from: str, date_to: str
    ) -> list[dict]:
        """Get all sub schedules in a date range, for calendar view."""
        cursor = await self.db.execute(
            """SELECT ss.*, g.company_name AS gc_name, g.gc_code,
                      j.job_name AS job_name
               FROM subcontractor_schedules ss
               JOIN general_contractors g ON g.id = ss.gc_id
               JOIN jobs j ON j.id = ss.job_id
               WHERE ss.scheduled_date >= ? AND ss.scheduled_date <= ?
               ORDER BY ss.scheduled_date ASC, j.job_name ASC""",
            (date_from, date_to),
        )
        return await cursor.fetchall()
