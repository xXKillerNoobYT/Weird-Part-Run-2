"""
Scheduling service — orchestrates default schedules, time off, dispatch,
subcontractor scheduling, and calendar assembly.

This is the business-logic layer between the router and the scheduling
repositories.  Handles conflict detection orchestration, bulk dispatch,
and calendar data merging from multiple sources.
"""

from __future__ import annotations

from datetime import date as dt_date, timedelta
from typing import Any

import aiosqlite

from app.models.scheduling import (
    BulkDispatchCreate,
    DefaultScheduleCreate,
    DispatchCreate,
    DispatchTemplateApply,
    DispatchTemplateCreate,
    DispatchTemplateUpdate,
    DispatchUpdate,
    ScheduleExceptionCreate,
    ScheduleExceptionUpdate,
    ShiftPatternCreate,
    ShiftPatternUpdate,
    SubScheduleCreate,
    SubScheduleUpdate,
    TeamDispatchCreate,
)
from app.repositories.scheduling_repo import (
    DefaultScheduleRepo,
    JobDispatchRepo,
    ScheduleExceptionRepo,
    SubcontractorScheduleRepo,
)
from app.repositories.team_repo import EmployeeTeamMemberRepo


class SchedulingService:
    """Stateless service — instantiate with a DB connection per request."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.default_repo = DefaultScheduleRepo(db)
        self.exception_repo = ScheduleExceptionRepo(db)
        self.dispatch_repo = JobDispatchRepo(db)
        self.sub_repo = SubcontractorScheduleRepo(db)

    # ── Default Schedules ───────────────────────────────────────────

    async def get_default_schedule(self, user_id: int) -> list[dict]:
        """Get the 7-day default schedule for an employee."""
        return await self.default_repo.get_for_user(user_id)

    async def set_default_schedule(
        self, user_id: int, data: DefaultScheduleCreate,
    ) -> None:
        """Replace the full 7-day default schedule for an employee."""
        days = [d.model_dump() for d in data.days]
        await self.default_repo.bulk_upsert(user_id, days)

    async def init_default_schedule(self, user_id: int) -> None:
        """Initialize a Mon–Fri 07:00–15:30 schedule for a new user."""
        await self.default_repo.init_defaults(user_id)

    # ── Schedule Exceptions (Time Off) ──────────────────────────────

    async def get_pending_exceptions(self, limit: int = 100) -> list[dict]:
        """Get all unapproved time-off requests, newest first."""
        return await self.exception_repo.get_pending(limit=limit)

    async def get_user_exceptions(
        self,
        user_id: int,
        date_from: str | None = None,
        date_to: str | None = None,
    ) -> list[dict]:
        """Get exceptions for a user, optionally within a date range."""
        return await self.exception_repo.get_for_user(
            user_id, date_from=date_from, date_to=date_to,
        )

    async def request_exception(
        self,
        user_id: int,
        data: ScheduleExceptionCreate,
    ) -> int:
        """Submit a schedule exception (time-off request). Returns new ID."""
        return await self.exception_repo.insert({
            "user_id": user_id,
            "exception_date": data.exception_date,
            "exception_type": data.exception_type,
            "start_time": data.start_time,
            "end_time": data.end_time,
            "reason": data.reason,
            "notes": data.notes,
            "is_approved": 0,
        })

    async def update_exception(
        self, exception_id: int, data: ScheduleExceptionUpdate,
    ) -> bool:
        """Partial update for a schedule exception."""
        update_dict = {
            k: v
            for k, v in data.model_dump(exclude_unset=True).items()
            if v is not None
        }
        if not update_dict:
            return False
        return await self.exception_repo.update(exception_id, update_dict)

    async def approve_exception(
        self, exception_id: int, approved_by: int,
    ) -> bool:
        """Approve a time-off request."""
        return await self.exception_repo.approve(exception_id, approved_by)

    async def deny_exception(self, exception_id: int) -> bool:
        """Deny (delete) a time-off request."""
        return await self.exception_repo.deny(exception_id)

    async def delete_exception(self, exception_id: int) -> bool:
        """Delete a schedule exception entirely."""
        return await self.exception_repo.delete(exception_id)

    # ── Dispatch ────────────────────────────────────────────────────

    async def get_daily_view(self, date: str) -> dict[str, Any]:
        """Assemble the daily dispatch view for a given date.

        Returns dispatches and available (unblocked) employees.
        """
        dispatches = await self.dispatch_repo.get_for_date(date)
        available = await self.dispatch_repo.get_available_employees(date)
        return {
            "date": date,
            "dispatches": dispatches,
            "available_employees": available,
        }

    async def dispatch_employee(
        self,
        data: DispatchCreate,
        *,
        dispatched_by: int | None = None,
    ) -> dict[str, Any]:
        """Dispatch a single employee to a job.

        Returns { id, conflicts } — conflicts is a list (may be empty).
        The dispatch is created even if there are soft conflicts; the caller
        can warn the user but doesn't block.
        """
        conflicts = await self.dispatch_repo.check_conflicts(
            data.user_id, data.dispatch_date,
        )

        dispatch_id = await self.dispatch_repo.insert({
            "job_id": data.job_id,
            "user_id": data.user_id,
            "dispatch_date": data.dispatch_date,
            "shift_start": data.shift_start,
            "shift_end": data.shift_end,
            "lunch_start": data.lunch_start,
            "lunch_end": data.lunch_end,
            "role_on_job": data.role_on_job,
            "status": "scheduled",
            "dispatched_by": dispatched_by,
            "notes": data.notes,
        })

        return {"id": dispatch_id, "conflicts": conflicts}

    async def bulk_dispatch(
        self,
        data: BulkDispatchCreate,
        *,
        dispatched_by: int | None = None,
    ) -> dict[str, Any]:
        """Dispatch multiple employees to the same job/date.

        Returns { created: [{id, user_id, conflicts}, ...], failed: [...] }
        """
        created: list[dict] = []
        failed: list[dict] = []

        for user_id in data.user_ids:
            try:
                conflicts = await self.dispatch_repo.check_conflicts(
                    user_id, data.dispatch_date,
                )
                dispatch_id = await self.dispatch_repo.insert({
                    "job_id": data.job_id,
                    "user_id": user_id,
                    "dispatch_date": data.dispatch_date,
                    "shift_start": data.shift_start,
                    "shift_end": data.shift_end,
                    "lunch_start": data.lunch_start,
                    "lunch_end": data.lunch_end,
                    "role_on_job": data.role_on_job,
                    "status": "scheduled",
                    "dispatched_by": dispatched_by,
                    "notes": data.notes,
                })
                created.append({
                    "id": dispatch_id,
                    "user_id": user_id,
                    "conflicts": conflicts,
                })
            except Exception as exc:
                failed.append({
                    "user_id": user_id,
                    "error": str(exc),
                })

        return {"created": created, "failed": failed}

    async def team_dispatch(
        self,
        data: TeamDispatchCreate,
        *,
        dispatched_by: int | None = None,
    ) -> dict[str, Any]:
        """Dispatch all members of an employee team to a job for a date.

        Fetches team membership, then delegates to bulk_dispatch.
        Returns { team_id, team_size, created: [...], failed: [...] }
        """
        member_repo = EmployeeTeamMemberRepo(self.db)
        members = await member_repo.get_for_team(data.team_id)
        if not members:
            return {
                "team_id": data.team_id,
                "team_size": 0,
                "created": [],
                "failed": [],
            }

        user_ids = [m["user_id"] for m in members]
        bulk = BulkDispatchCreate(
            job_id=data.job_id,
            dispatch_date=data.dispatch_date,
            user_ids=user_ids,
            shift_start=data.shift_start,
            shift_end=data.shift_end,
            lunch_start=data.lunch_start,
            lunch_end=data.lunch_end,
            role_on_job=data.role_on_job,
            notes=data.notes,
        )
        result = await self.bulk_dispatch(bulk, dispatched_by=dispatched_by)
        return {
            "team_id": data.team_id,
            "team_size": len(user_ids),
            **result,
        }

    async def update_dispatch(
        self, dispatch_id: int, data: DispatchUpdate,
    ) -> bool:
        """Partial update for a dispatch assignment."""
        update_dict = {
            k: v
            for k, v in data.model_dump(exclude_unset=True).items()
            if v is not None
        }
        if not update_dict:
            return False
        return await self.dispatch_repo.update(dispatch_id, update_dict)

    # Valid dispatch status transitions (state machine)
    DISPATCH_TRANSITIONS: dict[str, set[str]] = {
        "scheduled":  {"confirmed", "cancelled"},
        "confirmed":  {"on_site", "no_show", "cancelled"},
        "on_site":    {"completed", "no_show"},
        "completed":  set(),  # terminal
        "no_show":    {"scheduled"},  # can reschedule
        "cancelled":  {"scheduled"},  # can reschedule
    }

    async def update_dispatch_status(
        self, dispatch_id: int, status: str,
    ) -> bool:
        """Update dispatch status with state machine enforcement.

        Valid transitions:
          scheduled → confirmed | cancelled
          confirmed → on_site | no_show | cancelled
          on_site   → completed | no_show
          no_show   → scheduled (reschedule)
          cancelled → scheduled (reschedule)
          completed → (terminal)
        """
        current = await self.dispatch_repo.get_by_id(dispatch_id)
        if not current:
            return False
        current_status = current["status"]
        allowed = self.DISPATCH_TRANSITIONS.get(current_status, set())
        if status not in allowed:
            raise ValueError(
                f"Cannot transition dispatch from '{current_status}' to '{status}'. "
                f"Allowed: {', '.join(sorted(allowed)) or 'none (terminal state)'}"
            )
        return await self.dispatch_repo.update(dispatch_id, {"status": status})

    async def cancel_dispatch(self, dispatch_id: int) -> bool:
        """Cancel a dispatch by setting status to 'cancelled'."""
        return await self.dispatch_repo.update(
            dispatch_id, {"status": "cancelled"},
        )

    async def check_conflicts(self, user_id: int, date: str) -> list[dict]:
        """Check for scheduling conflicts (existing dispatch, time off,
        non-working day) without creating anything."""
        return await self.dispatch_repo.check_conflicts(user_id, date)

    async def get_user_dispatches(
        self, user_id: int, date_from: str, date_to: str,
    ) -> list[dict]:
        """Get dispatches for a user within a date range."""
        return await self.dispatch_repo.get_for_user(user_id, date_from, date_to)

    async def get_job_dispatches(
        self,
        job_id: int,
        date_from: str | None = None,
        date_to: str | None = None,
    ) -> list[dict]:
        """Get dispatches for a job, optionally within a date range."""
        return await self.dispatch_repo.get_for_job(
            job_id, date_from=date_from, date_to=date_to,
        )

    # ── Subcontractor Scheduling ────────────────────────────────────

    async def get_job_sub_schedules(
        self,
        job_id: int,
        date_from: str | None = None,
        date_to: str | None = None,
    ) -> list[dict]:
        """Get subcontractor schedules for a job."""
        return await self.sub_repo.get_for_job(
            job_id, date_from=date_from, date_to=date_to,
        )

    async def schedule_subcontractor(self, data: SubScheduleCreate) -> int:
        """Schedule a subcontractor visit. Returns the new row ID."""
        return await self.sub_repo.insert({
            "job_id": data.job_id,
            "gc_id": data.gc_id,
            "scheduled_date": data.scheduled_date,
            "arrival_time": data.arrival_time,
            "departure_time": data.departure_time,
            "work_description": data.work_description,
            "status": "scheduled",
            "notes": data.notes,
        })

    async def update_sub_schedule(
        self, schedule_id: int, data: SubScheduleUpdate,
    ) -> bool:
        """Partial update for a subcontractor schedule entry."""
        update_dict = {
            k: v
            for k, v in data.model_dump(exclude_unset=True).items()
            if v is not None
        }
        if not update_dict:
            return False
        return await self.sub_repo.update(schedule_id, update_dict)

    async def cancel_sub_schedule(self, schedule_id: int) -> bool:
        """Cancel a subcontractor schedule entry."""
        return await self.sub_repo.update(
            schedule_id, {"status": "cancelled"},
        )

    # ── Calendar Assembly ───────────────────────────────────────────

    async def get_calendar_data(
        self, date_from: str, date_to: str,
    ) -> dict[str, Any]:
        """Assemble calendar data for a date range.

        Merges three sources into a unified list of calendar entries:
        - Employee dispatches (type='dispatch')
        - Schedule exceptions / time off (type='time_off')
        - Subcontractor schedules (type='sub_schedule')
        """
        dispatches = await self.dispatch_repo.get_for_date_range(date_from, date_to)
        exceptions = await self.exception_repo.get_for_date_range(date_from, date_to)
        sub_schedules = await self.sub_repo.get_for_date_range(date_from, date_to)

        entries: list[dict] = []

        # Dispatches → calendar entries
        for d in dispatches:
            role = d.get("role_on_job", "worker")
            entries.append({
                "date": d["dispatch_date"],
                "entry_type": "dispatch",
                "user_id": d["user_id"],
                "user_name": d.get("user_name"),
                "job_id": d["job_id"],
                "job_name": d.get("job_name"),
                "gc_id": None,
                "gc_name": None,
                "status": d.get("status", "scheduled"),
                "role_on_job": role,
                "label": f"{d.get('user_name', '?')} → {d.get('job_name', '?')}",
            })

        # Time off → calendar entries
        for e in exceptions:
            etype = e.get("exception_type", "time_off")
            entries.append({
                "date": e["exception_date"],
                "entry_type": "time_off",
                "user_id": e["user_id"],
                "user_name": e.get("user_name"),
                "job_id": None,
                "job_name": None,
                "gc_id": None,
                "gc_name": None,
                "status": "approved" if e.get("is_approved") else "pending",
                "label": f"{e.get('user_name', '?')} — {etype.replace('_', ' ').title()}",
            })

        # Sub schedules → calendar entries
        for s in sub_schedules:
            entries.append({
                "date": s["scheduled_date"],
                "entry_type": "sub_schedule",
                "user_id": None,
                "user_name": None,
                "job_id": s["job_id"],
                "job_name": s.get("job_name"),
                "gc_id": s["gc_id"],
                "gc_name": s.get("gc_name"),
                "status": s.get("status", "scheduled"),
                "label": f"{s.get('gc_name', '?')} @ {s.get('job_name', '?')}",
            })

        # Sort all entries by date, then by label
        entries.sort(key=lambda x: (x["date"], x.get("label", "")))

        return {
            "date_from": date_from,
            "date_to": date_to,
            "entries": entries,
        }

    # ── Dispatch Templates ─────────────────────────────────────────

    DAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    @staticmethod
    def _bitmask_to_labels(bitmask: int) -> list[str]:
        """Convert a day bitmask to a list of day labels."""
        return [
            SchedulingService.DAY_LABELS[i]
            for i in range(7)
            if bitmask & (1 << i)
        ]

    @staticmethod
    def _bitmask_to_weekdays(bitmask: int) -> list[int]:
        """Convert a bitmask to list of Python weekday ints (0=Mon..6=Sun)."""
        # DB bitmask: bit0=Sun(python 6), bit1=Mon(0), ..., bit6=Sat(5)
        db_to_python = {0: 6, 1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 6: 5}
        return [db_to_python[i] for i in range(7) if bitmask & (1 << i)]

    async def list_dispatch_templates(self, active_only: bool = True) -> list[dict]:
        """List all dispatch templates with members and job names."""
        where = "WHERE dt.is_active = 1" if active_only else ""
        cursor = await self.db.execute(
            f"""SELECT dt.*, j.job_name AS job_name
                FROM dispatch_templates dt
                LEFT JOIN jobs j ON j.id = dt.job_id
                {where}
                ORDER BY dt.name""",
        )
        templates = [dict(r) for r in await cursor.fetchall()]

        for t in templates:
            # Fetch members
            mc = await self.db.execute(
                """SELECT dtm.user_id, dtm.role_on_job, u.display_name AS user_name
                   FROM dispatch_template_members dtm
                   LEFT JOIN users u ON u.id = dtm.user_id
                   WHERE dtm.template_id = ?""",
                (t["id"],),
            )
            t["members"] = [dict(m) for m in await mc.fetchall()]
            t["days_labels"] = self._bitmask_to_labels(t.get("days_of_week", 62))

        return templates

    async def get_dispatch_template(self, template_id: int) -> dict | None:
        """Get a single dispatch template with members."""
        cursor = await self.db.execute(
            """SELECT dt.*, j.job_name AS job_name
               FROM dispatch_templates dt
               LEFT JOIN jobs j ON j.id = dt.job_id
               WHERE dt.id = ?""",
            (template_id,),
        )
        row = await cursor.fetchone()
        if not row:
            return None
        t = dict(row)
        mc = await self.db.execute(
            """SELECT dtm.user_id, dtm.role_on_job, u.display_name AS user_name
               FROM dispatch_template_members dtm
               LEFT JOIN users u ON u.id = dtm.user_id
               WHERE dtm.template_id = ?""",
            (template_id,),
        )
        t["members"] = [dict(m) for m in await mc.fetchall()]
        t["days_labels"] = self._bitmask_to_labels(t.get("days_of_week", 62))
        return t

    async def create_dispatch_template(
        self, data: DispatchTemplateCreate, *, created_by: int | None = None,
    ) -> int:
        """Create a dispatch template with members. Returns new ID."""
        cursor = await self.db.execute(
            """INSERT INTO dispatch_templates
               (name, job_id, shift_start, shift_end, lunch_start, lunch_end,
                role_on_job, days_of_week, notes, created_by)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (data.name, data.job_id, data.shift_start, data.shift_end,
             data.lunch_start, data.lunch_end,
             data.role_on_job, data.days_of_week, data.notes, created_by),
        )
        template_id = cursor.lastrowid
        for m in data.members:
            await self.db.execute(
                """INSERT INTO dispatch_template_members
                   (template_id, user_id, role_on_job)
                   VALUES (?, ?, ?)""",
                (template_id, m.user_id, m.role_on_job),
            )
        await self.db.commit()
        return template_id  # type: ignore[return-value]

    async def update_dispatch_template(
        self, template_id: int, data: DispatchTemplateUpdate,
    ) -> bool:
        """Update a dispatch template (and optionally replace members)."""
        fields: list[str] = []
        values: list[Any] = []
        for field in ("name", "job_id", "shift_start", "shift_end",
                      "lunch_start", "lunch_end",
                      "role_on_job", "days_of_week", "notes"):
            val = getattr(data, field, None)
            if val is not None:
                fields.append(f"{field} = ?")
                values.append(val)
        if fields:
            fields.append("updated_at = CURRENT_TIMESTAMP")
            values.append(template_id)
            await self.db.execute(
                f"UPDATE dispatch_templates SET {', '.join(fields)} WHERE id = ?",
                values,
            )
        # Replace members if provided
        if data.members is not None:
            await self.db.execute(
                "DELETE FROM dispatch_template_members WHERE template_id = ?",
                (template_id,),
            )
            for m in data.members:
                await self.db.execute(
                    """INSERT INTO dispatch_template_members
                       (template_id, user_id, role_on_job) VALUES (?, ?, ?)""",
                    (template_id, m.user_id, m.role_on_job),
                )
        await self.db.commit()
        return True

    async def delete_dispatch_template(self, template_id: int) -> bool:
        """Soft-delete a dispatch template."""
        cursor = await self.db.execute(
            "UPDATE dispatch_templates SET is_active = 0 WHERE id = ? AND is_active = 1",
            (template_id,),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def apply_dispatch_template(
        self,
        template_id: int,
        data: DispatchTemplateApply,
        *,
        dispatched_by: int | None = None,
    ) -> dict[str, Any]:
        """Apply a template to generate dispatch records for a date range.

        Returns { created: int, skipped: int, conflicts: [...] }
        """
        template = await self.get_dispatch_template(template_id)
        if not template:
            raise ValueError("Template not found")

        weekdays = self._bitmask_to_weekdays(template["days_of_week"])
        members = template.get("members", [])
        if not members:
            raise ValueError("Template has no members")

        start = dt_date.fromisoformat(data.date_from)
        end = dt_date.fromisoformat(data.date_to)

        created = 0
        skipped = 0
        all_conflicts: list[dict] = []

        current = start
        while current <= end:
            if current.weekday() not in weekdays:
                current += timedelta(days=1)
                continue

            date_str = current.isoformat()
            for member in members:
                user_id = member["user_id"]
                role = member.get("role_on_job", template.get("role_on_job", "worker"))

                conflicts = await self.dispatch_repo.check_conflicts(user_id, date_str)
                if conflicts and data.skip_conflicts:
                    skipped += 1
                    all_conflicts.extend(conflicts)
                    continue

                await self.dispatch_repo.insert({
                    "job_id": template["job_id"],
                    "user_id": user_id,
                    "dispatch_date": date_str,
                    "shift_start": template.get("shift_start"),
                    "shift_end": template.get("shift_end"),
                    "lunch_start": template.get("lunch_start"),
                    "lunch_end": template.get("lunch_end"),
                    "role_on_job": role,
                    "status": "scheduled",
                    "dispatched_by": dispatched_by,
                    "notes": f"From template: {template['name']}",
                })
                created += 1
                if conflicts:
                    all_conflicts.extend(conflicts)

            current += timedelta(days=1)

        await self.db.commit()
        return {"created": created, "skipped": skipped, "conflicts": all_conflicts}

    # ── Shift Patterns ─────────────────────────────────────────────

    async def list_shift_patterns(self, active_only: bool = True) -> list[dict]:
        """List all shift patterns with their day definitions."""
        where = "WHERE is_active = 1" if active_only else ""
        cursor = await self.db.execute(
            f"SELECT * FROM shift_patterns {where} ORDER BY name",
        )
        patterns = [dict(r) for r in await cursor.fetchall()]
        for p in patterns:
            dc = await self.db.execute(
                """SELECT * FROM shift_pattern_days
                   WHERE pattern_id = ? ORDER BY day_of_week""",
                (p["id"],),
            )
            p["days"] = [dict(d) for d in await dc.fetchall()]
        return patterns

    async def get_shift_pattern(self, pattern_id: int) -> dict | None:
        """Get a single shift pattern with days."""
        cursor = await self.db.execute(
            "SELECT * FROM shift_patterns WHERE id = ?", (pattern_id,),
        )
        row = await cursor.fetchone()
        if not row:
            return None
        p = dict(row)
        dc = await self.db.execute(
            """SELECT * FROM shift_pattern_days
               WHERE pattern_id = ? ORDER BY day_of_week""",
            (p["id"],),
        )
        p["days"] = [dict(d) for d in await dc.fetchall()]
        return p

    async def create_shift_pattern(self, data: ShiftPatternCreate) -> int:
        """Create a named shift pattern with 7-day definition."""
        cursor = await self.db.execute(
            "INSERT INTO shift_patterns (name, description) VALUES (?, ?)",
            (data.name, data.description),
        )
        pattern_id = cursor.lastrowid
        for day in data.days:
            await self.db.execute(
                """INSERT INTO shift_pattern_days
                   (pattern_id, day_of_week, start_time, end_time,
                    lunch_start, lunch_end, is_working_day)
                   VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (pattern_id, day.day_of_week, day.start_time, day.end_time,
                 day.lunch_start, day.lunch_end,
                 1 if day.is_working_day else 0),
            )
        await self.db.commit()
        return pattern_id  # type: ignore[return-value]

    async def update_shift_pattern(
        self, pattern_id: int, data: ShiftPatternUpdate,
    ) -> bool:
        """Update a shift pattern (and optionally replace days)."""
        if data.name is not None or data.description is not None:
            fields: list[str] = []
            values: list[Any] = []
            if data.name is not None:
                fields.append("name = ?")
                values.append(data.name)
            if data.description is not None:
                fields.append("description = ?")
                values.append(data.description)
            values.append(pattern_id)
            await self.db.execute(
                f"UPDATE shift_patterns SET {', '.join(fields)} WHERE id = ?",
                values,
            )
        if data.days is not None:
            await self.db.execute(
                "DELETE FROM shift_pattern_days WHERE pattern_id = ?",
                (pattern_id,),
            )
            for day in data.days:
                await self.db.execute(
                    """INSERT INTO shift_pattern_days
                       (pattern_id, day_of_week, start_time, end_time,
                        lunch_start, lunch_end, is_working_day)
                       VALUES (?, ?, ?, ?, ?, ?, ?)""",
                    (pattern_id, day.day_of_week, day.start_time, day.end_time,
                     day.lunch_start, day.lunch_end,
                     1 if day.is_working_day else 0),
                )
        await self.db.commit()
        return True

    async def delete_shift_pattern(self, pattern_id: int) -> bool:
        """Soft-delete a shift pattern."""
        cursor = await self.db.execute(
            "UPDATE shift_patterns SET is_active = 0 WHERE id = ? AND is_active = 1",
            (pattern_id,),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def apply_shift_pattern_to_user(
        self, user_id: int, pattern_id: int,
    ) -> None:
        """Apply a shift pattern's days as the user's default schedule."""
        pattern = await self.get_shift_pattern(pattern_id)
        if not pattern:
            raise ValueError("Shift pattern not found")
        days = [
            {
                "day_of_week": d["day_of_week"],
                "start_time": d["start_time"],
                "end_time": d["end_time"],
                "lunch_start": d.get("lunch_start"),
                "lunch_end": d.get("lunch_end"),
                "is_working_day": bool(d["is_working_day"]),
            }
            for d in pattern["days"]
        ]
        await self.default_repo.bulk_upsert(user_id, days)

    # ── Weekly Availability ────────────────────────────────────────

    async def get_weekly_availability(
        self, date_from: str, date_to: str,
    ) -> list[dict]:
        """Get employee availability for a week.

        Returns a list of employees with their dispatch counts and
        time-off status for each day in the range.
        """
        # Get all active employees
        cursor = await self.db.execute(
            """SELECT id, display_name FROM users
               WHERE is_active = 1 ORDER BY display_name""",
        )
        employees = [dict(r) for r in await cursor.fetchall()]

        # Get dispatches in range
        dispatches = await self.dispatch_repo.get_for_date_range(date_from, date_to)
        # Get time-off in range
        exceptions = await self.exception_repo.get_for_date_range(date_from, date_to)

        # Build a map: user_id -> date -> {dispatched, time_off}
        avail_map: dict[int, dict[str, dict]] = {}
        for emp in employees:
            avail_map[emp["id"]] = {}

        for d in dispatches:
            uid = d["user_id"]
            ddate = d["dispatch_date"]
            if uid not in avail_map:
                continue
            entry = avail_map[uid].setdefault(ddate, {"dispatches": 0, "time_off": False})
            entry["dispatches"] += 1

        for e in exceptions:
            uid = e["user_id"]
            edate = e["exception_date"]
            if uid not in avail_map:
                continue
            entry = avail_map[uid].setdefault(edate, {"dispatches": 0, "time_off": False})
            if e.get("is_approved"):
                entry["time_off"] = True

        # Build result
        start = dt_date.fromisoformat(date_from)
        end = dt_date.fromisoformat(date_to)
        dates = []
        current = start
        while current <= end:
            dates.append(current.isoformat())
            current += timedelta(days=1)

        result = []
        for emp in employees:
            days_avail = []
            for d in dates:
                info = avail_map[emp["id"]].get(d, {"dispatches": 0, "time_off": False})
                days_avail.append({
                    "date": d,
                    "dispatches": info["dispatches"],
                    "time_off": info["time_off"],
                    "available": info["dispatches"] == 0 and not info["time_off"],
                })
            result.append({
                "user_id": emp["id"],
                "user_name": emp["display_name"],
                "days": days_avail,
            })

        return result
