"""
People routes — employee list, hat management, permission matrix.

Phase 1: Returns stub responses. Full implementation in Phase 7.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse, StatusMessage

router = APIRouter(prefix="/api/people", tags=["People"])


@router.get("/employees", response_model=ApiResponse[StatusMessage])
async def employee_list(user: dict = Depends(require_permission("view_people"))):
    """Employee list with search and filters."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="people/employees"),
        message="Employee List — coming in Phase 7.",
    )


@router.get("/hats", response_model=ApiResponse[StatusMessage])
async def hat_management(user: dict = Depends(require_permission("manage_people"))):
    """Hat (role) management — view, create, edit hats."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="people/hats"),
        message="Hat Management — coming in Phase 7.",
    )


@router.get("/permissions", response_model=ApiResponse[StatusMessage])
async def permission_matrix(user: dict = Depends(require_permission("manage_people"))):
    """Permission matrix — see who can do what. Permission-gated."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="people/permissions"),
        message="Permission Matrix — coming in Phase 7.",
    )
