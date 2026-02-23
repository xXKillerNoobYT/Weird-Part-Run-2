"""
Reports routes — pre-billing, timesheets, labor overview, exports.

Phase 1: Returns stub responses. Full implementation in Phase 8.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse, StatusMessage

router = APIRouter(prefix="/api/reports", tags=["Reports"])


@router.get("/pre-billing", response_model=ApiResponse[StatusMessage])
async def pre_billing(user: dict = Depends(require_permission("view_reports"))):
    """Pre-billing reports — job cost breakdowns for the bookkeeper."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="reports/pre-billing"),
        message="Pre-Billing Reports — coming in Phase 8.",
    )


@router.get("/timesheets", response_model=ApiResponse[StatusMessage])
async def timesheets(user: dict = Depends(require_permission("view_reports"))):
    """Employee timesheet views."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="reports/timesheets"),
        message="Timesheets — coming in Phase 8.",
    )


@router.get("/labor-overview", response_model=ApiResponse[StatusMessage])
async def labor_overview(user: dict = Depends(require_permission("view_reports"))):
    """Cross-job labor summary."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="reports/labor-overview"),
        message="Labor Overview — coming in Phase 8.",
    )


@router.get("/exports", response_model=ApiResponse[StatusMessage])
async def exports(user: dict = Depends(require_permission("export_reports"))):
    """Export bundles (CSV/PDF). Permission-gated."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="reports/exports"),
        message="Export Bundles — coming in Phase 8.",
    )
