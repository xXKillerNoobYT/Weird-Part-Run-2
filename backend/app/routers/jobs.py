"""
Jobs routes — active jobs, job detail, notebook, labor, templates.

Phase 1: Returns stub responses. Full implementation in Phase 4.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse, StatusMessage

router = APIRouter(prefix="/api/jobs", tags=["Jobs"])


@router.get("/active", response_model=ApiResponse[StatusMessage])
async def active_jobs(user: dict = Depends(require_permission("view_jobs"))):
    """List active jobs with status, type, and priority filters."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="jobs/active"),
        message="Active Jobs — coming in Phase 4.",
    )


@router.get("/{job_id}", response_model=ApiResponse[StatusMessage])
async def job_detail(job_id: int, user: dict = Depends(require_permission("view_jobs"))):
    """Get full job detail (notebook, parts, labor, billing)."""
    return ApiResponse(
        data=StatusMessage(status="stub", module=f"jobs/{job_id}"),
        message=f"Job #{job_id} Detail — coming in Phase 4.",
    )


@router.get("/{job_id}/notebook", response_model=ApiResponse[StatusMessage])
async def job_notebook(job_id: int, user: dict = Depends(require_permission("view_jobs"))):
    """Job notebook — sections, pages, attachments."""
    return ApiResponse(
        data=StatusMessage(status="stub", module=f"jobs/{job_id}/notebook"),
        message=f"Job #{job_id} Notebook — coming in Phase 4.",
    )


@router.get("/{job_id}/parts", response_model=ApiResponse[StatusMessage])
async def job_parts(job_id: int, user: dict = Depends(require_permission("view_jobs"))):
    """Parts consumed on this job."""
    return ApiResponse(
        data=StatusMessage(status="stub", module=f"jobs/{job_id}/parts"),
        message=f"Job #{job_id} Parts — coming in Phase 4.",
    )


@router.get("/{job_id}/labor", response_model=ApiResponse[StatusMessage])
async def job_labor(job_id: int, user: dict = Depends(require_permission("view_jobs"))):
    """Labor entries and clock in/out for this job."""
    return ApiResponse(
        data=StatusMessage(status="stub", module=f"jobs/{job_id}/labor"),
        message=f"Job #{job_id} Labor — coming in Phase 4.",
    )


@router.get("/templates", response_model=ApiResponse[StatusMessage])
async def notebook_templates(
    user: dict = Depends(require_permission("manage_templates")),
):
    """Notebook template management. Permission-gated."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="jobs/templates"),
        message="Notebook Templates — coming in Phase 4.",
    )
