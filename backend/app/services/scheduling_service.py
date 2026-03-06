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
    DispatchUpdate,
    ScheduleExceptionCreate,
    ScheduleExceptionUpdate,
    SubScheduleCreate,
    SubScheduleUpdate,
)
from app.repositories.scheduling_repo import (
    DefaultScheduleRepo,
    JobDispatchRepo,
    ScheduleExceptionRepo,
    SubcontractorScheduleRepo,
)


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

    async def update_dispatch_status(
        self, dispatch_id: int, status: str,
    ) -> bool:
        """Quick status update (e.g. confirmed, on_site, completed)."""
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
