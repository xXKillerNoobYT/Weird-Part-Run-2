"""
Labor Service — Clock in/out, hours calculation, GPS capture, labor queries.

Handles the full clock-in/clock-out lifecycle including:
- GPS location capture at both events
- Regular + overtime hours calculation (8-hour threshold)
- Drive time tracking
- Active clock detection (prevent double-clocking)
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta

import aiosqlite

from app.models.jobs import (
    ActiveClockResponse,
    ClockInRequest,
    ClockOutRequest,
    LaborEntryResponse,
)

logger = logging.getLogger(__name__)

# Overtime threshold: hours beyond this count as OT
REGULAR_HOURS_THRESHOLD = 8.0


class LaborService:
    """Clock in/out and labor entry management."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    # ── Clock In ──────────────────────────────────────────────────

    async def clock_in(
        self,
        user_id: int,
        job_id: int,
        data: ClockInRequest,
        photo_path: str | None = None,
    ) -> LaborEntryResponse:
        """Clock a user into a job. Prevents double-clocking."""
        # Check for existing active clock
        existing = await self.get_active_clock(user_id)
        if existing.is_clocked_in:
            raise ValueError(
                f"Already clocked in to job #{existing.entry.job_number}. "
                "Clock out first before clocking into another job."
            )

        now = datetime.utcnow().isoformat()
        cursor = await self.db.execute(
            """INSERT INTO labor_entries (
                user_id, job_id, clock_in,
                clock_in_gps_lat, clock_in_gps_lng,
                clock_in_photo_path, status
            ) VALUES (?, ?, ?, ?, ?, ?, 'clocked_in')""",
            (user_id, job_id, now, data.gps_lat, data.gps_lng, photo_path),
        )
        await self.db.commit()
        entry_id = cursor.lastrowid
        logger.info("User %d clocked in to job %d (entry %d)", user_id, job_id, entry_id)
        return await self.get_labor_entry(entry_id)

    # ── Clock Out ─────────────────────────────────────────────────

    async def clock_out(
        self,
        user_id: int,
        data: ClockOutRequest,
        photo_path: str | None = None,
    ) -> LaborEntryResponse:
        """Clock out of a job. Calculates hours and saves responses."""
        # Verify the labor entry belongs to this user and is active
        cursor = await self.db.execute(
            "SELECT * FROM labor_entries WHERE id = ? AND user_id = ?",
            (data.labor_entry_id, user_id),
        )
        entry = await cursor.fetchone()
        if not entry:
            raise ValueError("Labor entry not found or not yours.")
        if entry["status"] != "clocked_in":
            raise ValueError("This entry is already clocked out.")

        # Calculate hours
        clock_in = datetime.fromisoformat(entry["clock_in"])
        clock_out = datetime.utcnow()
        total_hours = (clock_out - clock_in).total_seconds() / 3600

        # Subtract drive time from work hours
        drive_hours = (data.drive_time_minutes or 0) / 60
        work_hours = max(0, total_hours - drive_hours)

        regular_hours = min(work_hours, REGULAR_HOURS_THRESHOLD)
        overtime_hours = max(0, work_hours - REGULAR_HOURS_THRESHOLD)

        # Update the labor entry
        await self.db.execute(
            """UPDATE labor_entries SET
                clock_out = ?,
                regular_hours = ?,
                overtime_hours = ?,
                drive_time_minutes = ?,
                clock_out_gps_lat = ?,
                clock_out_gps_lng = ?,
                clock_out_photo_path = ?,
                status = 'clocked_out',
                notes = ?
            WHERE id = ?""",
            (
                clock_out.isoformat(),
                round(regular_hours, 2),
                round(overtime_hours, 2),
                data.drive_time_minutes,
                data.gps_lat,
                data.gps_lng,
                photo_path,
                data.notes,
                data.labor_entry_id,
            ),
        )

        # Save clock-out question responses
        for resp in data.responses:
            await self.db.execute(
                """INSERT INTO clock_out_responses (
                    labor_entry_id, question_id, answer_text, answer_bool
                ) VALUES (?, ?, ?, ?)""",
                (
                    data.labor_entry_id,
                    resp.question_id,
                    resp.answer_text,
                    1 if resp.answer_bool else 0 if resp.answer_bool is not None else None,
                ),
            )

        # Save one-time question answers
        for otq in data.one_time_answers:
            await self.db.execute(
                """UPDATE one_time_questions SET
                    status = 'answered',
                    answered_by = ?,
                    answer_text = ?,
                    answered_at = datetime('now')
                WHERE id = ? AND status = 'pending'""",
                (user_id, otq.answer_text, otq.question_id),
            )

        await self.db.commit()
        logger.info(
            "User %d clocked out (entry %d): %.1fh regular + %.1fh OT",
            user_id, data.labor_entry_id, regular_hours, overtime_hours,
        )
        return await self.get_labor_entry(data.labor_entry_id)

    # ── Active Clock ──────────────────────────────────────────────

    async def get_active_clock(self, user_id: int) -> ActiveClockResponse:
        """Check if a user is currently clocked in."""
        cursor = await self.db.execute(
            """SELECT le.*,
                      u.display_name AS user_name,
                      j.job_name, j.job_number
               FROM labor_entries le
               LEFT JOIN users u ON u.id = le.user_id
               LEFT JOIN jobs j ON j.id = le.job_id
               WHERE le.user_id = ? AND le.status = 'clocked_in'
               ORDER BY le.clock_in DESC LIMIT 1""",
            (user_id,),
        )
        row = await cursor.fetchone()
        if not row:
            return ActiveClockResponse(is_clocked_in=False)

        return ActiveClockResponse(
            is_clocked_in=True,
            entry=self._row_to_response(row),
        )

    # ── Query ─────────────────────────────────────────────────────

    async def get_labor_entry(self, entry_id: int) -> LaborEntryResponse | None:
        """Get a single labor entry with user/job names."""
        cursor = await self.db.execute(
            """SELECT le.*,
                      u.display_name AS user_name,
                      j.job_name, j.job_number
               FROM labor_entries le
               LEFT JOIN users u ON u.id = le.user_id
               LEFT JOIN jobs j ON j.id = le.job_id
               WHERE le.id = ?""",
            (entry_id,),
        )
        row = await cursor.fetchone()
        if not row:
            return None
        return self._row_to_response(row)

    async def get_labor_for_job(
        self,
        job_id: int,
        date_from: str | None = None,
        date_to: str | None = None,
    ) -> list[LaborEntryResponse]:
        """Get all labor entries for a job, optionally filtered by date range."""
        conditions = ["le.job_id = ?"]
        params: list = [job_id]

        if date_from:
            conditions.append("le.clock_in >= ?")
            params.append(date_from)
        if date_to:
            conditions.append("le.clock_in <= ?")
            params.append(date_to)

        where = " AND ".join(conditions)
        cursor = await self.db.execute(
            f"""SELECT le.*,
                       u.display_name AS user_name,
                       j.job_name, j.job_number
                FROM labor_entries le
                LEFT JOIN users u ON u.id = le.user_id
                LEFT JOIN jobs j ON j.id = le.job_id
                WHERE {where}
                ORDER BY le.clock_in DESC""",
            params,
        )
        rows = await cursor.fetchall()
        return [self._row_to_response(r) for r in rows]

    async def get_labor_for_user(
        self,
        user_id: int,
        date_from: str | None = None,
        date_to: str | None = None,
    ) -> list[LaborEntryResponse]:
        """Get all labor entries for a user, optionally filtered by date range."""
        conditions = ["le.user_id = ?"]
        params: list = [user_id]

        if date_from:
            conditions.append("le.clock_in >= ?")
            params.append(date_from)
        if date_to:
            conditions.append("le.clock_in <= ?")
            params.append(date_to)

        where = " AND ".join(conditions)
        cursor = await self.db.execute(
            f"""SELECT le.*,
                       u.display_name AS user_name,
                       j.job_name, j.job_number
                FROM labor_entries le
                LEFT JOIN users u ON u.id = le.user_id
                LEFT JOIN jobs j ON j.id = le.job_id
                WHERE {where}
                ORDER BY le.clock_in DESC""",
            params,
        )
        rows = await cursor.fetchall()
        return [self._row_to_response(r) for r in rows]

    # ── Helpers ───────────────────────────────────────────────────

    def _row_to_response(self, row: aiosqlite.Row) -> LaborEntryResponse:
        return LaborEntryResponse(
            id=row["id"],
            user_id=row["user_id"],
            user_name=row["user_name"],
            job_id=row["job_id"],
            job_name=row["job_name"],
            job_number=row["job_number"],
            clock_in=row["clock_in"],
            clock_out=row["clock_out"],
            regular_hours=row["regular_hours"],
            overtime_hours=row["overtime_hours"],
            drive_time_minutes=row["drive_time_minutes"] or 0,
            clock_in_gps_lat=row["clock_in_gps_lat"],
            clock_in_gps_lng=row["clock_in_gps_lng"],
            clock_out_gps_lat=row["clock_out_gps_lat"],
            clock_out_gps_lng=row["clock_out_gps_lng"],
            clock_in_photo_path=row["clock_in_photo_path"],
            clock_out_photo_path=row["clock_out_photo_path"],
            status=row["status"],
            notes=row["notes"],
            created_at=row["created_at"],
        )
