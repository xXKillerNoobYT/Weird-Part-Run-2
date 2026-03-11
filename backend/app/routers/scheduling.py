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
    DispatchTemplateApply,
    DispatchTemplateCreate,
    DispatchTemplateUpdate,
    DispatchUpdate,
    PtoBalanceResponse,
    PtoPolicyCreate,
    PtoPolicyResponse,
    PtoPolicyUpdate,
    PtoTransactionCreate,
    PtoTransactionResponse,
    ScheduleExceptionCreate,
    ScheduleExceptionUpdate,
    ShiftPatternCreate,
    ShiftPatternUpdate,
    SubScheduleCreate,
    SubScheduleUpdate,
    TeamDispatchCreate,
)
from app.services.notification_service import NotificationService
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

    # Look up who requested time off before approving (for notification)
    exception = await svc.exception_repo.get_by_id(exception_id)
    approved = await svc.approve_exception(exception_id, approved_by=user["id"])
    if not approved:
        raise HTTPException(status_code=404, detail="Time-off request not found")

    # Notify the requesting employee
    if exception:
        notif = NotificationService(db)
        await notif.notify(
            "time_off_approved",
            "Your time-off request was approved",
            message=f"Time off on {exception.get('exception_date', 'N/A')} has been approved.",
            link="/scheduling/time-off",
            entity_type="schedule_exception",
            entity_id=exception_id,
            target_user_ids=[exception["user_id"]],
        )

    return ApiResponse(data={"id": exception_id}, message="Time-off approved")


@router.patch("/time-off/{exception_id}/deny")
async def deny_time_off(
    exception_id: int,
    user: dict = Depends(require_permission("approve_time_off")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Deny (delete) a time-off request."""
    svc = SchedulingService(db)

    # Look up who requested it before denying (for notification)
    exception = await svc.exception_repo.get_by_id(exception_id)
    denied = await svc.deny_exception(exception_id)
    if not denied:
        raise HTTPException(status_code=404, detail="Time-off request not found")

    # Notify the requesting employee
    if exception:
        notif = NotificationService(db)
        await notif.notify(
            "time_off_denied",
            "Your time-off request was denied",
            message=f"Time off on {exception.get('exception_date', 'N/A')} was not approved.",
            link="/scheduling/time-off",
            entity_type="schedule_exception",
            entity_id=exception_id,
            target_user_ids=[exception["user_id"]],
        )

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

    # Notify the dispatched employee
    notif = NotificationService(db)
    await notif.notify(
        "dispatch_created",
        f"You've been dispatched for {data.dispatch_date}",
        message=f"Job assignment on {data.dispatch_date}. Check your schedule for details.",
        link="/scheduling/dispatch",
        entity_type="dispatch",
        entity_id=result["id"],
        target_user_ids=[data.user_id],
    )

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


@router.post("/dispatch/team", status_code=status.HTTP_201_CREATED)
async def team_dispatch(
    data: TeamDispatchCreate,
    user: dict = Depends(require_permission("dispatch_employees")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Dispatch all members of an employee team to a job for a date.

    Fetches team membership and creates individual dispatches for each member.
    Returns { team_id, team_size, created: [...], failed: [...] }
    """
    svc = SchedulingService(db)
    result = await svc.team_dispatch(data, dispatched_by=user.get("id"))
    return ApiResponse(
        data=result,
        message=f"Team dispatched: {len(result['created'])} created, {len(result['failed'])} failed",
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
    """Update dispatch status with state machine enforcement."""
    svc = SchedulingService(db)
    try:
        updated = await svc.update_dispatch_status(dispatch_id, status_val)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
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

    # Look up who is dispatched before cancelling (for notification)
    dispatch = await svc.dispatch_repo.get_by_id(dispatch_id)
    cancelled = await svc.cancel_dispatch(dispatch_id)
    if not cancelled:
        raise HTTPException(status_code=404, detail="Dispatch not found")

    # Notify the affected employee
    if dispatch:
        notif = NotificationService(db)
        await notif.notify(
            "dispatch_cancelled",
            f"Your dispatch for {dispatch.get('dispatch_date', 'N/A')} was cancelled",
            link="/scheduling/dispatch",
            entity_type="dispatch",
            entity_id=dispatch_id,
            target_user_ids=[dispatch["user_id"]],
        )

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

    # Notify about the new subcontractor schedule
    notif = NotificationService(db)
    await notif.notify(
        "sub_schedule_created",
        f"Subcontractor scheduled for {data.scheduled_date}",
        message=f"GC #{data.gc_id} scheduled on job #{data.job_id} for {data.scheduled_date}.",
        link="/scheduling/calendar",
        entity_type="sub_schedule",
        entity_id=schedule_id,
    )

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

    # Fetch schedule before cancelling for notification context
    existing = await db.execute_fetchone(
        "SELECT gc_id, scheduled_date, job_id FROM sub_schedules WHERE id = ?",
        (schedule_id,),
    )

    cancelled = await svc.cancel_sub_schedule(schedule_id)
    if not cancelled:
        raise HTTPException(status_code=404, detail="Sub schedule not found")

    # Notify about the cancellation
    if existing:
        notif = NotificationService(db)
        await notif.notify(
            "sub_schedule_cancelled",
            f"Subcontractor schedule cancelled for {existing['scheduled_date']}",
            message=f"GC #{existing['gc_id']} removed from job #{existing['job_id']} on {existing['scheduled_date']}.",
            link="/scheduling/calendar",
            entity_type="sub_schedule",
            entity_id=schedule_id,
        )

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


# ═════════════════════════════════════════════════════════════════
# DISPATCH TEMPLATES
# ═════════════════════════════════════════════════════════════════


@router.get("/templates")
async def list_dispatch_templates(
    active_only: bool = Query(True),
    user: dict = Depends(require_permission("dispatch_employees")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all dispatch templates."""
    svc = SchedulingService(db)
    templates = await svc.list_dispatch_templates(active_only=active_only)
    return ApiResponse(data=templates, message=f"{len(templates)} templates")


@router.get("/templates/{template_id}")
async def get_dispatch_template(
    template_id: int,
    user: dict = Depends(require_permission("dispatch_employees")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a single dispatch template with members."""
    svc = SchedulingService(db)
    template = await svc.get_dispatch_template(template_id)
    if not template:
        raise HTTPException(status_code=404, detail="Template not found")
    return ApiResponse(data=template, message="Template found")


@router.post("/templates", status_code=status.HTTP_201_CREATED)
async def create_dispatch_template(
    data: DispatchTemplateCreate,
    user: dict = Depends(require_permission("dispatch_employees")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a recurring dispatch template."""
    svc = SchedulingService(db)
    template_id = await svc.create_dispatch_template(
        data, created_by=user.get("id"),
    )
    return ApiResponse(data={"id": template_id}, message="Template created")


@router.put("/templates/{template_id}")
async def update_dispatch_template(
    template_id: int,
    data: DispatchTemplateUpdate,
    user: dict = Depends(require_permission("dispatch_employees")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a dispatch template."""
    svc = SchedulingService(db)
    await svc.update_dispatch_template(template_id, data)
    return ApiResponse(data={"id": template_id}, message="Template updated")


@router.delete("/templates/{template_id}")
async def delete_dispatch_template(
    template_id: int,
    user: dict = Depends(require_permission("dispatch_employees")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Soft-delete a dispatch template."""
    svc = SchedulingService(db)
    deleted = await svc.delete_dispatch_template(template_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Template not found")
    return ApiResponse(data={"id": template_id}, message="Template deleted")


@router.post("/templates/{template_id}/apply")
async def apply_dispatch_template(
    template_id: int,
    data: DispatchTemplateApply,
    user: dict = Depends(require_permission("dispatch_employees")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Apply a template to generate dispatches for a date range."""
    svc = SchedulingService(db)
    try:
        result = await svc.apply_dispatch_template(
            template_id, data, dispatched_by=user.get("id"),
        )
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    return ApiResponse(
        data=result,
        message=f"{result['created']} dispatches created, {result['skipped']} skipped",
    )


# ═════════════════════════════════════════════════════════════════
# SHIFT PATTERNS
# ═════════════════════════════════════════════════════════════════


@router.get("/shift-patterns")
async def list_shift_patterns(
    active_only: bool = Query(True),
    user: dict = Depends(require_permission("view_schedule")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all named shift patterns."""
    svc = SchedulingService(db)
    patterns = await svc.list_shift_patterns(active_only=active_only)
    return ApiResponse(data=patterns, message=f"{len(patterns)} patterns")


@router.get("/shift-patterns/{pattern_id}")
async def get_shift_pattern(
    pattern_id: int,
    user: dict = Depends(require_permission("view_schedule")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a single shift pattern with day definitions."""
    svc = SchedulingService(db)
    pattern = await svc.get_shift_pattern(pattern_id)
    if not pattern:
        raise HTTPException(status_code=404, detail="Pattern not found")
    return ApiResponse(data=pattern, message="Pattern found")


@router.post("/shift-patterns", status_code=status.HTTP_201_CREATED)
async def create_shift_pattern(
    data: ShiftPatternCreate,
    user: dict = Depends(require_permission("manage_schedule")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a named shift pattern."""
    svc = SchedulingService(db)
    pattern_id = await svc.create_shift_pattern(data)
    return ApiResponse(data={"id": pattern_id}, message="Shift pattern created")


@router.put("/shift-patterns/{pattern_id}")
async def update_shift_pattern(
    pattern_id: int,
    data: ShiftPatternUpdate,
    user: dict = Depends(require_permission("manage_schedule")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a shift pattern."""
    svc = SchedulingService(db)
    await svc.update_shift_pattern(pattern_id, data)
    return ApiResponse(data={"id": pattern_id}, message="Shift pattern updated")


@router.delete("/shift-patterns/{pattern_id}")
async def delete_shift_pattern(
    pattern_id: int,
    user: dict = Depends(require_permission("manage_schedule")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Soft-delete a shift pattern."""
    svc = SchedulingService(db)
    deleted = await svc.delete_shift_pattern(pattern_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Pattern not found")
    return ApiResponse(data={"id": pattern_id}, message="Shift pattern deleted")


@router.post("/shift-patterns/{pattern_id}/apply/{user_id}")
async def apply_shift_pattern_to_user(
    pattern_id: int,
    user_id: int,
    user: dict = Depends(require_permission("manage_schedule")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Apply a shift pattern to a user's default schedule."""
    svc = SchedulingService(db)
    try:
        await svc.apply_shift_pattern_to_user(user_id, pattern_id)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))

    # Notify the employee about their new shift pattern
    pattern = await db.execute_fetchone(
        "SELECT name FROM shift_patterns WHERE id = ?", (pattern_id,),
    )
    pattern_name = pattern["name"] if pattern else f"Pattern #{pattern_id}"
    notif = NotificationService(db)
    await notif.notify(
        "shift_pattern_assigned",
        f"Shift pattern '{pattern_name}' assigned to you",
        message=f"Your default schedule has been updated to the '{pattern_name}' shift pattern.",
        link="/scheduling/calendar",
        entity_type="shift_pattern",
        entity_id=pattern_id,
        target_user_ids=[user_id],
    )

    return ApiResponse(
        data={"user_id": user_id, "pattern_id": pattern_id},
        message="Shift pattern applied to user's default schedule",
    )


# ═════════════════════════════════════════════════════════════════
# WEEKLY AVAILABILITY
# ═════════════════════════════════════════════════════════════════


@router.get("/availability/weekly")
async def get_weekly_availability(
    date_from: str = Query(..., description="Start date (YYYY-MM-DD)"),
    date_to: str = Query(..., description="End date (YYYY-MM-DD)"),
    user: dict = Depends(require_permission("view_schedule")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get weekly employee availability — dispatch counts + time-off status per day."""
    svc = SchedulingService(db)
    result = await svc.get_weekly_availability(date_from, date_to)
    return ApiResponse(
        data=result,
        message=f"{len(result)} employees",
    )


# ═════════════════════════════════════════════════════════════════
# PTO POLICIES & BALANCES
# ═════════════════════════════════════════════════════════════════


@router.get("/pto/balance/{user_id}")
async def get_pto_balance(
    user_id: int,
    user: dict = Depends(require_permission("view_schedule")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get PTO balance for a specific user."""
    import json
    from datetime import datetime

    # Get active policy
    policy_row = await db.execute_fetchone(
        "SELECT * FROM pto_policies WHERE user_id = ? AND is_active = 1",
        (user_id,),
    )

    # Get user name
    user_row = await db.execute_fetchone(
        "SELECT display_name FROM users WHERE id = ?", (user_id,)
    )
    user_name = user_row["display_name"] if user_row else "Unknown"

    # Current balance = last transaction's balance_after, or 0
    bal_row = await db.execute_fetchone(
        """
        SELECT balance_after FROM pto_transactions
        WHERE user_id = ? ORDER BY effective_date DESC, id DESC LIMIT 1
        """,
        (user_id,),
    )
    current_balance = float(bal_row["balance_after"]) if bal_row else 0.0

    # YTD stats
    year_start = f"{datetime.utcnow().year}-01-01"
    ytd_rows = await db.execute_fetchall(
        """
        SELECT transaction_type, SUM(hours) AS total
        FROM pto_transactions
        WHERE user_id = ? AND effective_date >= ?
        GROUP BY transaction_type
        """,
        (user_id, year_start),
    )
    accrued_ytd = 0.0
    used_ytd = 0.0
    for r in ytd_rows:
        if r["transaction_type"] == "accrual":
            accrued_ytd = float(r["total"] or 0)
        elif r["transaction_type"] == "usage":
            used_ytd = abs(float(r["total"] or 0))

    # Recent transactions (last 20)
    tx_rows = await db.execute_fetchall(
        """
        SELECT * FROM pto_transactions
        WHERE user_id = ? ORDER BY effective_date DESC, id DESC LIMIT 20
        """,
        (user_id,),
    )
    transactions = [
        PtoTransactionResponse(
            id=t["id"],
            user_id=t["user_id"],
            transaction_type=t["transaction_type"],
            hours=float(t["hours"]),
            balance_after=float(t["balance_after"]),
            reference_id=t["reference_id"],
            reference_type=t["reference_type"],
            note=t["note"],
            effective_date=t["effective_date"],
            created_by=t["created_by"],
            created_at=t["created_at"],
        )
        for t in tx_rows
    ]

    policy = None
    if policy_row:
        policy = PtoPolicyResponse(
            id=policy_row["id"],
            user_id=policy_row["user_id"],
            policy_name=policy_row["policy_name"],
            accrual_rate=float(policy_row["accrual_rate"]),
            accrual_period=policy_row["accrual_period"],
            max_balance=float(policy_row["max_balance"]) if policy_row["max_balance"] is not None else None,
            carryover_limit=float(policy_row["carryover_limit"]) if policy_row["carryover_limit"] is not None else None,
            start_date=policy_row["start_date"],
            is_active=bool(policy_row["is_active"]),
        )

    return ApiResponse(
        data=PtoBalanceResponse(
            user_id=user_id,
            user_name=user_name,
            current_balance=current_balance,
            accrued_ytd=accrued_ytd,
            used_ytd=used_ytd,
            policy=policy,
            recent_transactions=transactions,
        )
    )


@router.get("/pto/balances")
async def get_all_pto_balances(
    user: dict = Depends(require_permission("approve_time_off")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get PTO balances for all users with active policies."""
    from datetime import datetime

    rows = await db.execute_fetchall(
        """
        SELECT p.*, u.display_name AS user_name,
               (SELECT balance_after FROM pto_transactions
                WHERE user_id = p.user_id ORDER BY effective_date DESC, id DESC LIMIT 1) AS current_balance
        FROM pto_policies p
        JOIN users u ON u.id = p.user_id
        WHERE p.is_active = 1
        ORDER BY u.display_name
        """
    )
    balances = []
    for r in rows:
        balances.append({
            "user_id": r["user_id"],
            "user_name": r["user_name"],
            "current_balance": float(r["current_balance"]) if r["current_balance"] is not None else 0.0,
            "policy_name": r["policy_name"],
            "accrual_rate": float(r["accrual_rate"]),
            "accrual_period": r["accrual_period"],
            "max_balance": float(r["max_balance"]) if r["max_balance"] is not None else None,
        })
    return ApiResponse(data=balances, message=f"{len(balances)} users with PTO policies")


@router.post("/pto/policies", status_code=201)
async def create_pto_policy(
    body: PtoPolicyCreate,
    user: dict = Depends(require_permission("approve_time_off")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a PTO accrual policy for a user."""
    from datetime import datetime

    # Deactivate existing policy
    await db.execute(
        "UPDATE pto_policies SET is_active = 0 WHERE user_id = ? AND is_active = 1",
        (body.user_id,),
    )
    now = datetime.utcnow().isoformat()
    cursor = await db.execute(
        """
        INSERT INTO pto_policies (user_id, policy_name, accrual_rate, accrual_period,
                                  max_balance, carryover_limit, start_date, is_active)
        VALUES (?, ?, ?, ?, ?, ?, ?, 1)
        """,
        (body.user_id, body.policy_name, body.accrual_rate, body.accrual_period,
         body.max_balance, body.carryover_limit, body.start_date),
    )
    await db.commit()
    return ApiResponse(
        data=PtoPolicyResponse(
            id=cursor.lastrowid,
            user_id=body.user_id,
            policy_name=body.policy_name,
            accrual_rate=body.accrual_rate,
            accrual_period=body.accrual_period,
            max_balance=body.max_balance,
            carryover_limit=body.carryover_limit,
            start_date=body.start_date,
            is_active=True,
        ),
        message="PTO policy created",
    )


@router.put("/pto/policies/{policy_id}")
async def update_pto_policy(
    policy_id: int,
    body: PtoPolicyUpdate,
    user: dict = Depends(require_permission("approve_time_off")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a PTO policy."""
    row = await db.execute_fetchone("SELECT * FROM pto_policies WHERE id = ?", (policy_id,))
    if not row:
        raise HTTPException(404, "PTO policy not found")

    updates = {}
    if body.policy_name is not None:
        updates["policy_name"] = body.policy_name
    if body.accrual_rate is not None:
        updates["accrual_rate"] = body.accrual_rate
    if body.accrual_period is not None:
        updates["accrual_period"] = body.accrual_period
    if body.max_balance is not None:
        updates["max_balance"] = body.max_balance
    if body.carryover_limit is not None:
        updates["carryover_limit"] = body.carryover_limit
    if body.is_active is not None:
        updates["is_active"] = int(body.is_active)

    if updates:
        set_clause = ", ".join(f"{k} = ?" for k in updates)
        await db.execute(
            f"UPDATE pto_policies SET {set_clause} WHERE id = ?",
            (*updates.values(), policy_id),
        )
        await db.commit()

    updated = await db.execute_fetchone("SELECT * FROM pto_policies WHERE id = ?", (policy_id,))
    return ApiResponse(
        data=PtoPolicyResponse(
            id=updated["id"],
            user_id=updated["user_id"],
            policy_name=updated["policy_name"],
            accrual_rate=float(updated["accrual_rate"]),
            accrual_period=updated["accrual_period"],
            max_balance=float(updated["max_balance"]) if updated["max_balance"] is not None else None,
            carryover_limit=float(updated["carryover_limit"]) if updated["carryover_limit"] is not None else None,
            start_date=updated["start_date"],
            is_active=bool(updated["is_active"]),
        )
    )


@router.post("/pto/transactions", status_code=201)
async def create_pto_transaction(
    body: PtoTransactionCreate,
    user: dict = Depends(require_permission("approve_time_off")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Record a PTO transaction (accrual, usage, adjustment, etc.)."""
    from datetime import datetime

    # Get current balance
    bal_row = await db.execute_fetchone(
        """
        SELECT balance_after FROM pto_transactions
        WHERE user_id = ? ORDER BY effective_date DESC, id DESC LIMIT 1
        """,
        (body.user_id,),
    )
    current = float(bal_row["balance_after"]) if bal_row else 0.0

    # Check max balance for accruals
    if body.transaction_type == "accrual":
        policy = await db.execute_fetchone(
            "SELECT max_balance FROM pto_policies WHERE user_id = ? AND is_active = 1",
            (body.user_id,),
        )
        if policy and policy["max_balance"] is not None:
            max_bal = float(policy["max_balance"])
            if current + body.hours > max_bal:
                body.hours = max(0, max_bal - current)

    new_balance = current + body.hours
    # Don't go negative for usage
    if body.transaction_type == "usage" and new_balance < 0:
        raise HTTPException(422, f"Insufficient PTO balance. Current: {current}h, Requested: {abs(body.hours)}h")

    now = datetime.utcnow().isoformat()
    cursor = await db.execute(
        """
        INSERT INTO pto_transactions
            (user_id, transaction_type, hours, balance_after, reference_id, reference_type,
             note, effective_date, created_by, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (body.user_id, body.transaction_type, body.hours, new_balance,
         body.reference_id, body.reference_type, body.note, body.effective_date,
         user["user_id"], now),
    )
    await db.commit()
    return ApiResponse(
        data=PtoTransactionResponse(
            id=cursor.lastrowid,
            user_id=body.user_id,
            transaction_type=body.transaction_type,
            hours=body.hours,
            balance_after=new_balance,
            reference_id=body.reference_id,
            reference_type=body.reference_type,
            note=body.note,
            effective_date=body.effective_date,
            created_by=user["user_id"],
            created_at=now,
        ),
        message=f"PTO transaction recorded. New balance: {new_balance}h",
    )


@router.post("/pto/run-accruals")
async def run_pto_accruals(
    user: dict = Depends(require_permission("approve_time_off")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """
    Run PTO accruals for all active policies.
    Call this on a schedule (weekly/monthly) or manually.
    """
    from datetime import datetime

    today = datetime.utcnow().date().isoformat()
    policies = await db.execute_fetchall(
        "SELECT * FROM pto_policies WHERE is_active = 1"
    )

    processed = 0
    skipped = 0
    for p in policies:
        # Check if already accrued today
        existing = await db.execute_fetchone(
            """
            SELECT id FROM pto_transactions
            WHERE user_id = ? AND transaction_type = 'accrual' AND effective_date = ?
            """,
            (p["user_id"], today),
        )
        if existing:
            skipped += 1
            continue

        # Calculate accrual
        hours = float(p["accrual_rate"])
        bal_row = await db.execute_fetchone(
            """
            SELECT balance_after FROM pto_transactions
            WHERE user_id = ? ORDER BY effective_date DESC, id DESC LIMIT 1
            """,
            (p["user_id"],),
        )
        current = float(bal_row["balance_after"]) if bal_row else 0.0

        # Cap at max balance
        if p["max_balance"] is not None:
            max_bal = float(p["max_balance"])
            if current + hours > max_bal:
                hours = max(0, max_bal - current)

        if hours <= 0:
            skipped += 1
            continue

        new_balance = current + hours
        now = datetime.utcnow().isoformat()
        await db.execute(
            """
            INSERT INTO pto_transactions
                (user_id, transaction_type, hours, balance_after, note, effective_date, created_by, created_at)
            VALUES (?, 'accrual', ?, ?, 'Auto-accrual', ?, ?, ?)
            """,
            (p["user_id"], hours, new_balance, today, user["user_id"], now),
        )
        processed += 1

        # Notify the employee about their accrual
        notif = NotificationService(db)
        await notif.notify(
            "pto_accrual_posted",
            f"PTO accrual: +{hours:.1f} hrs (balance: {new_balance:.1f} hrs)",
            message=f"Automatic PTO accrual of {hours:.1f} hours posted for {today}. New balance: {new_balance:.1f} hours.",
            link="/scheduling/time-off",
            entity_type="pto_transaction",
            target_user_ids=[p["user_id"]],
        )

    await db.commit()
    return ApiResponse(
        data={"processed": processed, "skipped": skipped, "total_policies": len(policies)},
        message=f"Accrual run complete — {processed} processed, {skipped} skipped",
    )
