"""
Jobs routes — Job CRUD, labor clock in/out, clock-out questions,
one-time questions, parts consumption, and daily reports.

Phase 4 — Full implementation with ~25 endpoints covering the
complete job lifecycle from creation through daily report generation.
"""

from __future__ import annotations

import logging
from datetime import date

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse, StatusMessage
from app.models.jobs import (
    ActiveClockResponse,
    BillRateTypeCreate,
    BillRateTypeResponse,
    BillRateTypeUpdate,
    ClockInRequest,
    ClockOutBundle,
    ClockOutQuestionCreate,
    ClockOutQuestionResponse,
    ClockOutRequest,
    DailyReportFull,
    DailyReportResponse,
    JobCreate,
    JobListItem,
    JobPartConsumeRequest,
    JobPartResponse,
    JobResponse,
    JobStatusUpdate,
    JobTeamMemberAdd,
    JobTeamMemberResponse,
    JobUpdate,
    LaborEntryResponse,
    OneTimeQuestionCreate,
    OneTimeQuestionResponse,
    QuestionReorderRequest,
)
from app.models.notebooks import EntryResponse, NotebookFull
from app.models.contacts import JobCustomerCreate, JobGCCreate
from app.models.orders import JobPreferenceToggle, JobPreferredSuppliersUpdate
from app.services.contacts_service import ContactsService
from app.services.job_preferences_service import JobPreferencesService
from app.services.job_service import JobService
from app.services.labor_service import LaborService
from app.services.questionnaire_service import QuestionnaireService
from app.services.report_service import ReportService

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/jobs", tags=["Jobs"])


# ═══════════════════════════════════════════════════════════════════════
# BILL RATE TYPES (boss-customizable lookup)
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/bill-rate-types",
    response_model=ApiResponse[list[BillRateTypeResponse]],
    summary="List bill rate types",
)
async def list_bill_rate_types(
    active_only: bool = Query(True, description="Only show active types"),
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all bill rate types for dropdown population."""
    svc = JobService(db)
    types = await svc.get_bill_rate_types(active_only=active_only)
    return ApiResponse(data=types, message=f"{len(types)} bill rate types")


@router.post(
    "/bill-rate-types",
    response_model=ApiResponse[BillRateTypeResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Create bill rate type",
)
async def create_bill_rate_type(
    data: BillRateTypeCreate,
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new bill rate type (boss only)."""
    svc = JobService(db)
    brt = await svc.create_bill_rate_type(data)
    return ApiResponse(data=brt, message=f"Bill rate type '{data.name}' created")


@router.put(
    "/bill-rate-types/{type_id}",
    response_model=ApiResponse[BillRateTypeResponse],
    summary="Update bill rate type",
)
async def update_bill_rate_type(
    type_id: int,
    data: BillRateTypeUpdate,
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a bill rate type."""
    svc = JobService(db)
    brt = await svc.update_bill_rate_type(type_id, data)
    if not brt:
        raise HTTPException(status_code=404, detail="Bill rate type not found")
    return ApiResponse(data=brt, message="Bill rate type updated")


@router.delete(
    "/bill-rate-types/{type_id}",
    response_model=ApiResponse[StatusMessage],
    summary="Deactivate bill rate type",
)
async def delete_bill_rate_type(
    type_id: int,
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Soft-delete a bill rate type (sets is_active = 0)."""
    svc = JobService(db)
    await svc.delete_bill_rate_type(type_id)
    return ApiResponse(
        data=StatusMessage(status="ok", module="bill_rate_types"),
        message="Bill rate type deactivated",
    )


# ═══════════════════════════════════════════════════════════════════════
# JOB CRUD
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/active",
    response_model=ApiResponse[list[JobListItem]],
    summary="List active jobs",
)
async def active_jobs(
    search: str | None = Query(None, description="Search job name/number/customer"),
    status_filter: str | None = Query(None, alias="status", description="Filter by status"),
    job_type: str | None = Query(None, description="Filter by job type"),
    priority: str | None = Query(None, description="Filter by priority"),
    sort: str = Query("created_at", description="Sort field"),
    order: str = Query("desc", description="Sort order: asc or desc"),
    user: dict = Depends(require_permission("view_jobs")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List active jobs with status, type, priority filters, and search."""
    svc = JobService(db)
    jobs = await svc.get_active_jobs(
        search=search,
        status=status_filter,
        job_type=job_type,
        priority=priority,
        sort_by=sort,
        sort_dir=order,
    )
    return ApiResponse(data=jobs, message=f"{len(jobs)} jobs found")


@router.post(
    "",
    response_model=ApiResponse[JobResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Create a new job",
)
async def create_job(
    data: JobCreate,
    user: dict = Depends(require_permission("manage_jobs")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new job with all details."""
    svc = JobService(db)
    job = await svc.create_job(data, created_by=user["id"])
    return ApiResponse(data=job, message=f"Job '{data.job_name}' created")


@router.get(
    "/{job_id}/notebook",
    response_model=ApiResponse[NotebookFull],
    summary="Get or create job notebook",
)
async def get_job_notebook(
    job_id: int,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get the job's notebook (lazy-creates from template on first access)."""
    from app.services.notebook_service import NotebookService
    svc = NotebookService(db)
    try:
        nb = await svc.get_or_create_job_notebook(job_id, user["id"])
    except Exception:
        logger.exception("Failed to get/create notebook for job %s", job_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Could not load or create notebook for job {job_id}. "
                   "Check that the database migration has been applied.",
        )
    if not nb:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Notebook for job {job_id} could not be found or created.",
        )
    return ApiResponse(data=nb)


@router.get(
    "/{job_id}/tasks",
    response_model=ApiResponse[list[EntryResponse]],
    summary="Job tasks across all sections",
)
async def get_job_tasks(
    job_id: int,
    status: str | None = Query(None, description="Filter by task status"),
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all tasks from the job's notebook, across all sections."""
    from app.services.notebook_service import NotebookService
    svc = NotebookService(db)
    tasks = await svc.get_job_tasks(job_id, status=status)
    return ApiResponse(data=tasks, message=f"{len(tasks)} tasks")


@router.get(
    "/{job_id}",
    response_model=ApiResponse[JobResponse],
    summary="Get job detail",
)
async def job_detail(
    job_id: int,
    user: dict = Depends(require_permission("view_jobs")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get full job detail including labor hours and parts cost aggregation."""
    svc = JobService(db)
    job = await svc.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail=f"Job #{job_id} not found")
    return ApiResponse(data=job)


@router.put(
    "/{job_id}",
    response_model=ApiResponse[JobResponse],
    summary="Update job",
)
async def update_job(
    job_id: int,
    data: JobUpdate,
    user: dict = Depends(require_permission("manage_jobs")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a job's information."""
    svc = JobService(db)
    job = await svc.update_job(job_id, data)
    if not job:
        raise HTTPException(status_code=404, detail=f"Job #{job_id} not found")
    return ApiResponse(data=job, message="Job updated")


@router.patch(
    "/{job_id}/status",
    response_model=ApiResponse[JobResponse],
    summary="Change job status",
)
async def update_job_status(
    job_id: int,
    data: JobStatusUpdate,
    user: dict = Depends(require_permission("manage_jobs")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Change job status (pending, active, on_hold, completed, cancelled, continuous_maintenance, on_call)."""
    svc = JobService(db)
    job = await svc.update_status(job_id, data.status)
    if not job:
        raise HTTPException(status_code=404, detail=f"Job #{job_id} not found")
    return ApiResponse(data=job, message=f"Job status changed to '{data.status}'")


# ═══════════════════════════════════════════════════════════════════════
# LABOR / CLOCK IN-OUT
# ═══════════════════════════════════════════════════════════════════════

@router.post(
    "/{job_id}/clock-in",
    response_model=ApiResponse[LaborEntryResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Clock in to a job",
)
async def clock_in(
    job_id: int,
    data: ClockInRequest,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Clock the current user into a job with GPS location."""
    svc = LaborService(db)
    entry = await svc.clock_in(
        user_id=user["id"],
        job_id=job_id,
        data=data,
    )
    return ApiResponse(data=entry, message="Clocked in")


@router.post(
    "/clock-out",
    response_model=ApiResponse[LaborEntryResponse],
    summary="Clock out from current job",
)
async def clock_out(
    data: ClockOutRequest,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Clock out from the current job with GPS, responses, and optional notes."""
    svc = LaborService(db)
    entry = await svc.clock_out(
        user_id=user["id"],
        data=data,
    )
    return ApiResponse(data=entry, message="Clocked out")


@router.get(
    "/my-clock",
    response_model=ApiResponse[ActiveClockResponse],
    summary="Get current user's active clock",
)
async def my_clock(
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get the current user's active clock-in entry, if any."""
    svc = LaborService(db)
    result = await svc.get_active_clock(user["id"])
    return ApiResponse(data=result)


@router.get(
    "/{job_id}/labor",
    response_model=ApiResponse[list[LaborEntryResponse]],
    summary="Labor entries for a job",
)
async def job_labor(
    job_id: int,
    date_from: str | None = Query(None, description="Start date (YYYY-MM-DD)"),
    date_to: str | None = Query(None, description="End date (YYYY-MM-DD)"),
    user: dict = Depends(require_permission("view_jobs")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all labor entries for a job, optionally filtered by date range."""
    svc = LaborService(db)
    entries = await svc.get_labor_for_job(job_id, date_from=date_from, date_to=date_to)
    return ApiResponse(data=entries, message=f"{len(entries)} labor entries")


@router.get(
    "/my-labor",
    response_model=ApiResponse[list[LaborEntryResponse]],
    summary="Current user's labor history",
)
async def my_labor(
    date_from: str | None = Query(None, description="Start date (YYYY-MM-DD)"),
    date_to: str | None = Query(None, description="End date (YYYY-MM-DD)"),
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get the current user's labor history, optionally filtered by dates."""
    svc = LaborService(db)
    entries = await svc.get_labor_for_user(user["id"], date_from=date_from, date_to=date_to)
    return ApiResponse(data=entries, message=f"{len(entries)} entries")


# ═══════════════════════════════════════════════════════════════════════
# PARTS CONSUMPTION
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/{job_id}/parts",
    response_model=ApiResponse[list[JobPartResponse]],
    summary="Parts consumed on a job",
)
async def job_parts(
    job_id: int,
    user: dict = Depends(require_permission("view_jobs")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all parts consumed on this job."""
    svc = JobService(db)
    parts = await svc.get_job_parts(job_id)
    return ApiResponse(data=parts, message=f"{len(parts)} parts consumed")


@router.post(
    "/{job_id}/parts/consume",
    response_model=ApiResponse[JobPartResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Record part consumption",
)
async def consume_part(
    job_id: int,
    data: JobPartConsumeRequest,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Record parts consumed on a job. Snapshots cost at time of consumption."""
    svc = JobService(db)
    part = await svc.consume_part(job_id, data, user_id=user["id"])
    return ApiResponse(data=part, message="Part consumption recorded")


# ═══════════════════════════════════════════════════════════════════════
# GLOBAL CLOCK-OUT QUESTIONS (boss-managed)
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/questions/global",
    response_model=ApiResponse[list[ClockOutQuestionResponse]],
    summary="List global clock-out questions",
)
async def list_global_questions(
    active_only: bool = Query(True, description="Only show active questions"),
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all global clock-out questions, ordered by sort_order."""
    svc = QuestionnaireService(db)
    questions = await svc.get_global_questions(active_only=active_only)
    return ApiResponse(data=questions, message=f"{len(questions)} questions")


@router.post(
    "/questions/global",
    response_model=ApiResponse[ClockOutQuestionResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Create a global clock-out question",
)
async def create_global_question(
    data: ClockOutQuestionCreate,
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new global clock-out question (boss only)."""
    svc = QuestionnaireService(db)
    question = await svc.create_global_question(data, created_by=user["id"])
    return ApiResponse(data=question, message="Question created")


@router.put(
    "/questions/global/reorder",
    response_model=ApiResponse[StatusMessage],
    summary="Reorder global questions",
)
async def reorder_global_questions(
    data: QuestionReorderRequest,
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Reorder global questions by providing ordered list of IDs."""
    svc = QuestionnaireService(db)
    await svc.reorder_questions(data.ordered_ids)
    return ApiResponse(
        data=StatusMessage(status="ok", module="questions"),
        message="Questions reordered",
    )


@router.put(
    "/questions/global/{question_id}",
    response_model=ApiResponse[ClockOutQuestionResponse],
    summary="Update a global question",
)
async def update_global_question(
    question_id: int,
    data: ClockOutQuestionCreate,
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update an existing global clock-out question."""
    svc = QuestionnaireService(db)
    question = await svc.update_global_question(question_id, data)
    return ApiResponse(data=question, message="Question updated")


@router.delete(
    "/questions/global/{question_id}",
    response_model=ApiResponse[StatusMessage],
    summary="Deactivate a global question",
)
async def deactivate_global_question(
    question_id: int,
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Soft-delete a global clock-out question (sets is_active = 0)."""
    svc = QuestionnaireService(db)
    await svc.deactivate_global_question(question_id)
    return ApiResponse(
        data=StatusMessage(status="ok", module="questions"),
        message="Question deactivated",
    )


# ═══════════════════════════════════════════════════════════════════════
# ONE-TIME PER-JOB QUESTIONS
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/{job_id}/questions/one-time",
    response_model=ApiResponse[list[OneTimeQuestionResponse]],
    summary="One-time questions for a job",
)
async def list_one_time_questions(
    job_id: int,
    pending_only: bool = Query(False, description="Only show pending questions"),
    user: dict = Depends(require_permission("view_jobs")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all one-time questions for a job."""
    svc = QuestionnaireService(db)
    questions = await svc.get_one_time_questions_for_job(job_id, pending_only=pending_only)
    return ApiResponse(data=questions, message=f"{len(questions)} one-time questions")


@router.post(
    "/{job_id}/questions/one-time",
    response_model=ApiResponse[OneTimeQuestionResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Create a one-time question for a job",
)
async def create_one_time_question(
    job_id: int,
    data: OneTimeQuestionCreate,
    user: dict = Depends(require_permission("manage_jobs")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Boss sends a one-time question to a specific worker (or everyone) on a job."""
    svc = QuestionnaireService(db)
    question = await svc.create_one_time_question(job_id, data, created_by=user["id"])
    return ApiResponse(data=question, message="One-time question created")


class OneTimeAnswerBody(BaseModel):
    """Body for answering a one-time question."""
    answer_text: str | None = None


@router.post(
    "/questions/one-time/{question_id}/answer",
    response_model=ApiResponse[OneTimeQuestionResponse],
    summary="Answer a one-time question",
)
async def answer_one_time_question(
    question_id: int,
    data: OneTimeAnswerBody,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Answer a pending one-time question."""
    svc = QuestionnaireService(db)
    question = await svc.answer_one_time_question(
        question_id=question_id,
        answer_text=data.answer_text,
        user_id=user["id"],
    )
    return ApiResponse(data=question, message="Question answered")


# ═══════════════════════════════════════════════════════════════════════
# CLOCK-OUT BUNDLE (assembled payload for the clock-out flow UI)
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/{job_id}/clock-out-bundle",
    response_model=ApiResponse[ClockOutBundle],
    summary="Get all questions for clock-out flow",
)
async def clock_out_bundle(
    job_id: int,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Assemble the clock-out questionnaire bundle.

    Returns all active global questions plus any pending one-time questions
    for this user on this job. The frontend renders these as a single
    multi-step flow during clock-out.
    """
    svc = QuestionnaireService(db)
    bundle = await svc.get_clock_out_bundle(job_id, user["id"])
    return ApiResponse(data=bundle)


# ═══════════════════════════════════════════════════════════════════════
# DAILY REPORTS
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/reports/all",
    response_model=ApiResponse[list[DailyReportResponse]],
    summary="All daily reports across jobs",
)
async def all_reports(
    date_from: str | None = Query(None, description="Start date (YYYY-MM-DD)"),
    date_to: str | None = Query(None, description="End date (YYYY-MM-DD)"),
    user: dict = Depends(require_permission("view_reports")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all daily reports across all jobs, optionally filtered by date range."""
    svc = ReportService(db)
    reports = await svc.get_all_reports(date_from=date_from, date_to=date_to)
    return ApiResponse(data=reports, message=f"{len(reports)} reports")


@router.get(
    "/{job_id}/reports",
    response_model=ApiResponse[list[DailyReportResponse]],
    summary="Daily reports for a job",
)
async def job_reports(
    job_id: int,
    user: dict = Depends(require_permission("view_reports")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all daily reports for a specific job, newest first."""
    svc = ReportService(db)
    reports = await svc.get_reports_for_job(job_id)
    return ApiResponse(data=reports, message=f"{len(reports)} reports for job #{job_id}")


@router.get(
    "/{job_id}/reports/{report_date}",
    response_model=ApiResponse[DailyReportFull],
    summary="Get a specific daily report",
)
async def get_report(
    job_id: int,
    report_date: str,
    user: dict = Depends(require_permission("view_reports")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get the full daily report for a specific job and date.

    Returns the complete JSON data including workers, responses,
    parts consumed, and cost summary.
    """
    svc = ReportService(db)
    report = await svc.get_report_full(job_id, report_date)
    if not report:
        raise HTTPException(
            status_code=404,
            detail=f"No report found for job #{job_id} on {report_date}",
        )
    return ApiResponse(data=report)


@router.post(
    "/reports/generate-now",
    response_model=ApiResponse[list[DailyReportResponse]],
    summary="Manually trigger report generation",
)
async def generate_reports_now(
    target_date: str | None = Query(None, description="Target date (YYYY-MM-DD), defaults to yesterday"),
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Manually trigger daily report generation (admin only).

    Generates reports for all jobs that had labor activity on the
    target date (or yesterday if not specified).
    """
    svc = ReportService(db)
    parsed_date = date.fromisoformat(target_date) if target_date else None
    reports = await svc.generate_all_pending_reports(target_date=parsed_date)
    return ApiResponse(
        data=reports,
        message=f"Generated {len(reports)} reports",
    )


# ═══════════════════════════════════════════════════════════════════════
# JOB PREFERENCES — Smart suggestion memory per job (Phase 7A)
# ═══════════════════════════════════════════════════════════════════════


@router.get("/{job_id}/preferences", response_model=ApiResponse)
async def get_job_preferences(
    job_id: int,
    preference_type: str | None = None,
    category: str | None = None,
    active_only: bool = True,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all learned preferences for a job.

    Returns brand, color, supplier, and part preferences that the system
    has learned from previous orders on this job.  Used by the frontend
    to power "smart suggestion" filter chips.

    Filters:
      - preference_type: 'brand', 'color', 'supplier', or 'part'
      - category:        e.g. 'outlets', 'switches' — limits to that part category
      - active_only:     exclude disabled preferences (default True)
    """
    svc = JobPreferencesService(db)
    prefs = await svc.get_all_for_job(job_id)
    return ApiResponse(data=prefs)


@router.get("/{job_id}/suggestions", response_model=ApiResponse)
async def get_job_suggestions(
    job_id: int,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all smart suggestions for the order form, grouped by type.

    Returns {brands, colors, suppliers, parts} grouped by preference_type,
    each sorted by confidence_score DESC.  The frontend uses brands/colors
    for catalog filter chips and suppliers for per-line suggestion badges.
    """
    svc = JobPreferencesService(db)
    grouped = await svc.get_all_for_job(job_id)
    return ApiResponse(data=grouped)


@router.put("/{job_id}/preferences/{pref_id}", response_model=ApiResponse)
async def toggle_job_preference(
    job_id: int,
    pref_id: int,
    body: JobPreferenceToggle,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Toggle a specific preference on or off.

    Field workers can disable suggestions they don't want
    (e.g. "stop suggesting Leviton for this job").
    """
    svc = JobPreferencesService(db)
    success = await svc.toggle_preference(pref_id, body.is_active)
    if not success:
        raise HTTPException(404, "Preference not found")

    return ApiResponse(data={"id": pref_id, "is_active": body.is_active})


@router.get("/{job_id}/preferred-suppliers", response_model=ApiResponse)
async def get_job_preferred_suppliers(
    job_id: int,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get explicitly set preferred suppliers for a job.

    Returns manually set suppliers ranked by priority (primary first).
    Does NOT include auto-learned supplier preferences — only explicit ones.
    """
    svc = JobPreferencesService(db)
    suppliers = await svc.get_explicit_suppliers(job_id)
    return ApiResponse(data=[dict(s) for s in suppliers])


@router.put("/{job_id}/preferred-suppliers", response_model=ApiResponse)
async def set_job_preferred_suppliers(
    job_id: int,
    body: JobPreferredSuppliersUpdate,
    user: dict = Depends(require_permission("manage_jobs")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Set explicit preferred suppliers for a job.

    The first supplier in the list is the primary, subsequent ones are backups.
    Replaces all existing manual supplier preferences for this job.
    """
    svc = JobPreferencesService(db)
    results = await svc.set_explicit_suppliers(
        job_id,
        [s.model_dump() for s in body.suppliers],
    )
    return ApiResponse(
        data=results,
        message=f"Set {len(results)} preferred supplier(s) for job {job_id}",
    )


# ═══════════════════════════════════════════════════════════════════════
# JOB ↔ CUSTOMER LINKING
# ═══════════════════════════════════════════════════════════════════════


@router.get("/{job_id}/customers")
async def get_job_customers(
    job_id: int,
    user: dict = Depends(require_permission("view_jobs")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all customers linked to a job."""
    svc = ContactsService(db)
    customers = await svc.get_job_customers(job_id)
    return ApiResponse(data=customers, message=f"{len(customers)} customers linked")


@router.post("/{job_id}/customers", status_code=status.HTTP_201_CREATED)
async def link_customer_to_job(
    job_id: int,
    data: JobCustomerCreate,
    user: dict = Depends(require_permission("manage_jobs")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Link a customer to a job with a contact role."""
    svc = ContactsService(db)
    link_id = await svc.link_customer_to_job(job_id, data)
    return ApiResponse(data={"id": link_id}, message="Customer linked to job")


@router.delete("/{job_id}/customers/{link_id}")
async def unlink_customer_from_job(
    job_id: int,
    link_id: int,
    user: dict = Depends(require_permission("manage_jobs")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Remove a customer link from a job."""
    svc = ContactsService(db)
    removed = await svc.unlink_customer_from_job(link_id)
    if not removed:
        raise HTTPException(status_code=404, detail="Customer link not found")
    return ApiResponse(data={"id": link_id}, message="Customer unlinked from job")


# ═══════════════════════════════════════════════════════════════════════
# JOB ↔ GENERAL CONTRACTOR LINKING
# ═══════════════════════════════════════════════════════════════════════


@router.get("/{job_id}/general-contractors")
async def get_job_gcs(
    job_id: int,
    user: dict = Depends(require_permission("view_jobs")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all general contractors linked to a job."""
    svc = ContactsService(db)
    gcs = await svc.get_job_gcs(job_id)
    return ApiResponse(data=gcs, message=f"{len(gcs)} contractors linked")


@router.post("/{job_id}/general-contractors", status_code=status.HTTP_201_CREATED)
async def link_gc_to_job(
    job_id: int,
    data: JobGCCreate,
    user: dict = Depends(require_permission("manage_jobs")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Link a general contractor to a job with a relationship type.

    Relationship types:
    - 'they_are_gc' — they hired us (PO naming convention applies)
    - 'we_hired_them' — we hired them as a sub (scheduling applies)
    """
    svc = ContactsService(db)
    link_id = await svc.link_gc_to_job(job_id, data)
    return ApiResponse(data={"id": link_id}, message="Contractor linked to job")


@router.delete("/{job_id}/general-contractors/{link_id}")
async def unlink_gc_from_job(
    job_id: int,
    link_id: int,
    user: dict = Depends(require_permission("manage_jobs")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Remove a general contractor link from a job."""
    svc = ContactsService(db)
    removed = await svc.unlink_gc_from_job(link_id)
    if not removed:
        raise HTTPException(status_code=404, detail="Contractor link not found")
    return ApiResponse(data={"id": link_id}, message="Contractor unlinked from job")


# ═══════════════════════════════════════════════════════════════════════
# JOB TEAM MEMBERS
# ═══════════════════════════════════════════════════════════════════════


@router.get(
    "/{job_id}/team",
    response_model=ApiResponse[list[JobTeamMemberResponse]],
)
async def get_job_team(
    job_id: int,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all employees assigned to a job's team."""
    cursor = await db.execute(
        """
        SELECT jtm.id, jtm.job_id, jtm.user_id, jtm.role,
               jtm.assigned_at, jtm.notes,
               COALESCE(u.display_name, u.username) AS display_name,
               u.email
        FROM job_team_members jtm
        JOIN users u ON u.id = jtm.user_id
        WHERE jtm.job_id = ?
        ORDER BY
            CASE jtm.role WHEN 'lead' THEN 0 ELSE 1 END,
            u.display_name ASC
        """,
        (job_id,),
    )
    rows = await cursor.fetchall()
    members = [
        JobTeamMemberResponse(
            id=r["id"],
            job_id=r["job_id"],
            user_id=r["user_id"],
            display_name=r["display_name"] or "Unknown",
            email=r["email"],
            role=r["role"],
            assigned_at=r["assigned_at"],
            notes=r["notes"],
        )
        for r in rows
    ]
    return ApiResponse(data=members, message=f"{len(members)} team members")


@router.post(
    "/{job_id}/team",
    response_model=ApiResponse[JobTeamMemberResponse],
    status_code=status.HTTP_201_CREATED,
)
async def add_job_team_member(
    job_id: int,
    payload: JobTeamMemberAdd,
    user: dict = Depends(require_permission("manage_jobs")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Add an employee to a job's team.

    If the employee is already on the team, returns 409.
    Role must be 'lead' or 'member'.
    """
    # Verify the job exists
    job_row = await db.execute("SELECT id FROM jobs WHERE id = ?", (job_id,))
    if not await job_row.fetchone():
        raise HTTPException(status_code=404, detail="Job not found")

    # Verify the user exists
    user_row = await db.execute(
        "SELECT id, COALESCE(display_name, username) AS display_name, email FROM users WHERE id = ?",
        (payload.user_id,),
    )
    usr = await user_row.fetchone()
    if not usr:
        raise HTTPException(status_code=404, detail="User not found")

    try:
        cursor = await db.execute(
            """
            INSERT INTO job_team_members (job_id, user_id, role, assigned_by, notes)
            VALUES (?, ?, ?, ?, ?)
            """,
            (job_id, payload.user_id, payload.role, user.get("id"), payload.notes),
        )
        await db.commit()
        new_id = cursor.lastrowid
    except Exception as exc:
        if "UNIQUE" in str(exc):
            raise HTTPException(status_code=409, detail="Employee is already on this team")
        raise

    # Fetch the assigned_at value
    row = await db.execute(
        "SELECT assigned_at FROM job_team_members WHERE id = ?", (new_id,)
    )
    inserted = await row.fetchone()

    return ApiResponse(
        data=JobTeamMemberResponse(
            id=new_id,
            job_id=job_id,
            user_id=payload.user_id,
            display_name=usr["display_name"] or "Unknown",
            email=usr["email"],
            role=payload.role,
            assigned_at=inserted["assigned_at"] if inserted else "",
            notes=payload.notes,
        ),
        message="Team member added",
    )


@router.delete("/{job_id}/team/{member_id}")
async def remove_job_team_member(
    job_id: int,
    member_id: int,
    user: dict = Depends(require_permission("manage_jobs")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Remove a team member from a job."""
    result = await db.execute(
        "DELETE FROM job_team_members WHERE id = ? AND job_id = ?",
        (member_id, job_id),
    )
    await db.commit()
    if result.rowcount == 0:
        raise HTTPException(status_code=404, detail="Team member not found")
    return ApiResponse(data={"id": member_id}, message="Team member removed")
