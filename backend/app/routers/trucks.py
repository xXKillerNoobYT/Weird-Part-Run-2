"""
Trucks routes — my truck, all trucks, tools, maintenance, mileage.

Phase 1: Returns stub responses. Full implementation in Phase 6.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse, StatusMessage

router = APIRouter(prefix="/api/trucks", tags=["Trucks"])


@router.get("/my-truck", response_model=ApiResponse[StatusMessage])
async def my_truck(user: dict = Depends(require_permission("view_trucks"))):
    """Personal truck dashboard for the current user."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="trucks/my-truck"),
        message="My Truck — coming in Phase 6.",
    )


@router.get("/all", response_model=ApiResponse[StatusMessage])
async def all_trucks(user: dict = Depends(require_permission("view_trucks"))):
    """Fleet overview — all trucks with status."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="trucks/all"),
        message="All Trucks — coming in Phase 6.",
    )


@router.get("/tools", response_model=ApiResponse[StatusMessage])
async def truck_tools(user: dict = Depends(require_permission("view_trucks"))):
    """Tool tracking per truck."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="trucks/tools"),
        message="Truck Tools — coming in Phase 6.",
    )


@router.get("/maintenance", response_model=ApiResponse[StatusMessage])
async def truck_maintenance(user: dict = Depends(require_permission("view_trucks"))):
    """Service schedule, history, and costs."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="trucks/maintenance"),
        message="Truck Maintenance — coming in Phase 6.",
    )


@router.get("/mileage", response_model=ApiResponse[StatusMessage])
async def truck_mileage(user: dict = Depends(require_permission("view_trucks"))):
    """Mileage log for fleet vehicles."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="trucks/mileage"),
        message="Mileage Log — coming in Phase 6.",
    )
