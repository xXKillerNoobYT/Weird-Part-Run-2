"""
Scheduling routes — default schedules, time off, dispatch, subcontractor
scheduling, and calendar assembly.

~21 endpoints covering the full employee scheduling and dispatch lifecycle.

Permission gates:
- view_schedule      → read schedules, calendar, and dispatch data
- manage_schedule    → modify default schedules
- request_time_off   → submit time-off requests
- approve_time_off   → approve/deny time-off requests
- dispatch_employees → create/update/cancel dispatch assignments
"""

from __future__ import annotations

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse
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
from app.services.scheduling_service import SchedulingService

router = APIRouter(prefix="/api/scheduling", tags=["Scheduling"])


# ═════════════════════════════════════════════════════════════════
# DEFAULT SCHEDULES
# ═════════════════════════════════════════════════════════════════


@router.get("/schedules/{user_id}/default")
async def get_default_schedule(
    user_id: int,
    user: dict = Depends(require_permission("view_schedule")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get the 7-day default schedule for an employee."""
    svc = SchedulingService(db)
    schedule = await svc.get_default_schedule(user_id)
    return ApiResponse(data=schedule, message=f"{len(schedule)} schedule entries")


@router.put("/schedules/{user_id}/default")
async def set_default_schedule(
    user_id: int,
    data: DefaultScheduleCreate,
    user: dict = Depends(require_permission("manage_schedule")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Replace the full 7-day default schedule for an employee."""
    svc = SchedulingService(db)
    await svc.set_default_schedule(user_id, data)
    schedule = await svc.get_default_schedule(user_id)
    return ApiResponse(data=schedule, message="Default schedule updated")


@router.post("/schedules/{user_id}/default/init")
async def init_default_schedule(
    user_id: int,
    user: dict = Depends(require_permission("manage_schedule")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Initialize a standard Mon–Fri 07:00–15:30 schedule for an employee."""
    svc = SchedulingService(db)
    await svc.init_default_schedule(user_id)
    schedule = await svc.get_default_schedule(user_id)
    return ApiResponse(data=schedule, message="Default schedule initialized")


# ═════════════════════════════════════════════════════════════════
# TIME OFF (SCHEDULE EXCEPTIONS)
# ═════════════════════════════════════════════════════════════════


@router.get("/time-off/pending")
async def get_pending_time_off(
    limit: int = Query(100, ge=1, le=500, description="Max results"),
    user: dict = Depends(require_permission("approve_time_off")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all pending (unapproved) time-off requests."""
    svc = SchedulingService(db)
    requests = await svc.get_pending_exceptions(limit=limit)
    return ApiResponse(data=requests, message=f"{len(requests)} pending requests")


@router.get("/time-off/user/{user_id}")
async def get_user_time_off(
    user_id: int,
    date_from: str | None = Query(None, description="Start date (YYYY-MM-DD)"),
    date_to: str | None = Query(None, description="End date (YYYY-MM-DD)"),
    user: dict = Depends(require_permission("view_schedule")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get time-off requests for a specific user."""
    svc = SchedulingService(db)
    exceptions = await svc.get_user_exceptions(
        user_id, date_from=date_from, date_to=date_to,
    )
    return ApiResponse(data=exceptions, message=f"{len(exceptions)} time-off entries")


@router.post("/time-off", status_code=status.HTTP_201_CREATED)
async def request_time_off(
    data: ScheduleExceptionCreate,
    user: dict = Depends(require_permission("request_time_off")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Submit a time-off request for the current user."""
    svc = SchedulingService(db)
    exception_id = await svc.request_exception(user["id"], data)
    return ApiResponse(
        data={"id": exception_id},
        message="Time-off request submitted",
    )


@router.post("/time-off/{user_id}", status_code=status.HTTP_201_CREATED)
async def request_time_off_for_user(
    user_id: int,
    data: ScheduleExceptionCreate,
    user: dict = Depends(require_permission("manage_schedule")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Submit a time-off request on behalf of another user (manager only)."""
    svc = SchedulingService(db)
    exception_id = await svc.request_exception(user_id, data)
    return ApiResponse(
        data={"id": exception_id},
        message="Time-off request submitted",
    )


@router.put("/time-off/{exception_id}")
async def update_time_off(
    exception_id: int,
    data: ScheduleExceptionUpdate,
    user: dict = Depends(require_permission("manage_schedule")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a time-off request."""
    svc = SchedulingService(db)
    updated = await svc.update_exception(exception_id, data)
    if not updated:
        raise HTTPException(status_code=404, detail="Time-off request not found or no changes")
    return ApiResponse(data={"id": exception_id}, message="Time-off request updated")


@router.patch("/time-off/{exception_id}/approve")
async def approve_time_off(
    exception_id: int,
    user: dict = Depends(require_permission("approve_time_off")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Approve a time-off request."""
    svc = SchedulingService(db)
    approved = await svc.approve_exception(exception_id, approved_by=user["id"])
    if not approved:
        raise HTTPException(status_code=404, detail="Time-off request not found")
    return ApiResponse(data={"id": exception_id}, message="Time-off approved")


@router.patch("/time-off/{exception_id}/deny")
async def deny_time_off(
    exception_id: int,
    user: dict = Depends(require_permission("approve_time_off")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Deny (delete) a time-off request."""
    svc = SchedulingService(db)
    denied = await svc.deny_exception(exception_id)
    if not denied:
        raise HTTPException(status_code=404, detail="Time-off request not found")
    return ApiResponse(data={"id": exception_id}, message="Time-off denied")


@router.delete("/time-off/{exception_id}")
async def delete_time_off(
    exception_id: int,
    user: dict = Depends(require_permission("manage_schedule")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a time-off request entirely."""
    svc = SchedulingService(db)
    deleted = await svc.delete_exception(exception_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Time-off request not found")
    return ApiResponse(data={"id": exception_id}, message="Time-off deleted")


# ═════════════════════════════════════════════════════════════════
# DISPATCH
# ═════════════════════════════════════════════════════════════════


@router.get("/dispatch/daily")
async def get_daily_dispatch(
    date: str = Query(..., description="Date (YYYY-MM-DD)"),
    user: dict = Depends(require_permission("view_schedule")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get daily dispatch view — dispatches and available employees for a date."""
    svc = SchedulingService(db)
    result = await svc.get_daily_view(date)
    return ApiResponse(
        data=result,
        message=f"{len(result['dispatches'])} dispatches, "
                f"{len(result['available_employees'])} available",
    )


@router.get("/dispatch/conflicts")
async def check_dispatch_conflicts(
    user_id: int = Query(..., description="Employee user ID"),
    date: str = Query(..., description="Date (YYYY-MM-DD)"),
    user: dict = Depends(require_permission("dispatch_employees")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Check for scheduling conflicts without creating a dispatch."""
    svc = SchedulingService(db)
    conflicts = await svc.check_conflicts(user_id, date)
    return ApiResponse(
        data=conflicts,
        message=f"{len(conflicts)} conflicts found" if conflicts else "No conflicts",
    )


@router.get("/dispatch/user/{user_id}")
async def get_user_dispatches(
    user_id: int,
    date_from: str = Query(..., description="Start date (YYYY-MM-DD)"),
    date_to: str = Query(..., description="End date (YYYY-MM-DD)"),
    user: dict = Depends(require_permission("view_schedule")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get dispatches for a user within a date range."""
    svc = SchedulingService(db)
    dispatches = await svc.get_user_dispatches(user_id, date_from, date_to)
    return ApiResponse(data=dispatches, message=f"{len(dispatches)} dispatches")


@router.get("/dispatch/job/{job_id}")
async def get_job_dispatches(
    job_id: int,
    date_from: str | None = Query(None, description="Start date (YYYY-MM-DD)"),
    date_to: str | None = Query(None, description="End date (YYYY-MM-DD)"),
    user: dict = Depends(require_permission("view_schedule")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get dispatches for a job, optionally within a date range."""
    svc = SchedulingService(db)
    dispatches = await svc.get_job_dispatches(
        job_id, date_from=date_from, date_to=date_to,
    )
    return ApiResponse(data=dispatches, message=f"{len(dispatches)} dispatches")


@router.post("/dispatch", status_code=status.HTTP_201_CREATED)
async def dispatch_employee(
    data: DispatchCreate,
    user: dict = Depends(require_permission("dispatch_employees")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Dispatch a single employee to a job.

    Returns the new dispatch ID and any scheduling conflicts (soft warnings).
    The dispatch is created even with conflicts — the frontend warns but doesn't block.
    """
    svc = SchedulingService(db)
    result = await svc.dispatch_employee(data, dispatched_by=user.get("id"))
    return ApiResponse(data=result, message="Employee dispatched")


@router.post("/dispatch/bulk", status_code=status.HTTP_201_CREATED)
async def bulk_dispatch(
    data: BulkDispatchCreate,
    user: dict = Depends(require_permission("dispatch_employees")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Dispatch multiple employees to the same job/date.

    Returns { created: [...], failed: [...] } — individual failures
    don't prevent other dispatches from succeeding.
    """
    svc = SchedulingService(db)
    result = await svc.bulk_dispatch(data, dispatched_by=user.get("id"))
    return ApiResponse(
        data=result,
        message=f"{len(result['created'])} dispatched, {len(result['failed'])} failed",
    )


@router.put("/dispatch/{dispatch_id}")
async def update_dispatch(
    dispatch_id: int,
    data: DispatchUpdate,
    user: dict = Depends(require_permission("dispatch_employees")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Partial update for a dispatch assignment."""
    svc = SchedulingService(db)
    updated = await svc.update_dispatch(dispatch_id, data)
    if not updated:
        raise HTTPException(status_code=404, detail="Dispatch not found or no changes")
    return ApiResponse(data={"id": dispatch_id}, message="Dispatch updated")


@router.patch("/dispatch/{dispatch_id}/status")
async def update_dispatch_status(
    dispatch_id: int,
    status_val: str = Query(..., alias="status", description="New status"),
    user: dict = Depends(require_permission("dispatch_employees")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Quick status update (e.g. confirmed, on_site, completed)."""
    svc = SchedulingService(db)
    updated = await svc.update_dispatch_status(dispatch_id, status_val)
    if not updated:
        raise HTTPException(status_code=404, detail="Dispatch not found")
    return ApiResponse(
        data={"id": dispatch_id, "status": status_val},
        message=f"Dispatch status → {status_val}",
    )


@router.patch("/dispatch/{dispatch_id}/cancel")
async def cancel_dispatch(
    dispatch_id: int,
    user: dict = Depends(require_permission("dispatch_employees")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Cancel a dispatch assignment."""
    svc = SchedulingService(db)
    cancelled = await svc.cancel_dispatch(dispatch_id)
    if not cancelled:
        raise HTTPException(status_code=404, detail="Dispatch not found")
    return ApiResponse(data={"id": dispatch_id}, message="Dispatch cancelled")


# ═════════════════════════════════════════════════════════════════
# SUBCONTRACTOR SCHEDULING
# ═════════════════════════════════════════════════════════════════


@router.get("/subcontractors/job/{job_id}")
async def get_job_sub_schedules(
    job_id: int,
    date_from: str | None = Query(None, description="Start date (YYYY-MM-DD)"),
    date_to: str | None = Query(None, description="End date (YYYY-MM-DD)"),
    user: dict = Depends(require_permission("view_schedule")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get subcontractor schedules for a job."""
    svc = SchedulingService(db)
    schedules = await svc.get_job_sub_schedules(
        job_id, date_from=date_from, date_to=date_to,
    )
    return ApiResponse(data=schedules, message=f"{len(schedules)} sub schedules")


@router.post("/subcontractors", status_code=status.HTTP_201_CREATED)
async def schedule_subcontractor(
    data: SubScheduleCreate,
    user: dict = Depends(require_permission("dispatch_employees")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Schedule a subcontractor visit on a job."""
    svc = SchedulingService(db)
    schedule_id = await svc.schedule_subcontractor(data)
    return ApiResponse(data={"id": schedule_id}, message="Subcontractor scheduled")


@router.put("/subcontractors/{schedule_id}")
async def update_sub_schedule(
    schedule_id: int,
    data: SubScheduleUpdate,
    user: dict = Depends(require_permission("dispatch_employees")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a subcontractor schedule entry."""
    svc = SchedulingService(db)
    updated = await svc.update_sub_schedule(schedule_id, data)
    if not updated:
        raise HTTPException(status_code=404, detail="Sub schedule not found or no changes")
    return ApiResponse(data={"id": schedule_id}, message="Sub schedule updated")


@router.patch("/subcontractors/{schedule_id}/cancel")
async def cancel_sub_schedule(
    schedule_id: int,
    user: dict = Depends(require_permission("dispatch_employees")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Cancel a subcontractor schedule entry."""
    svc = SchedulingService(db)
    cancelled = await svc.cancel_sub_schedule(schedule_id)
    if not cancelled:
        raise HTTPException(status_code=404, detail="Sub schedule not found")
    return ApiResponse(data={"id": schedule_id}, message="Sub schedule cancelled")


# ═════════════════════════════════════════════════════════════════
# CALENDAR (UNIFIED VIEW)
# ═════════════════════════════════════════════════════════════════


@router.get("/calendar")
async def get_calendar(
    date_from: str = Query(..., description="Start date (YYYY-MM-DD)"),
    date_to: str = Query(..., description="End date (YYYY-MM-DD)"),
    user: dict = Depends(require_permission("view_schedule")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Assemble unified calendar data for a date range.

    Merges three sources into a single sorted entry list:
    - Employee dispatches (type='dispatch')
    - Time off / schedule exceptions (type='time_off')
    - Subcontractor schedules (type='sub_schedule')
    """
    svc = SchedulingService(db)
    result = await svc.get_calendar_data(date_from, date_to)
    return ApiResponse(
        data=result,
        message=f"{len(result['entries'])} calendar entries",
    )
