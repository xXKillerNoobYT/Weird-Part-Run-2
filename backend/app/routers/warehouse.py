"""
Warehouse routes — dashboard, inventory, staging, audit, movement log.

Phase 1: Returns stub responses. Full implementation in Phase 3.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse, StatusMessage

router = APIRouter(prefix="/api/warehouse", tags=["Warehouse"])


@router.get("/dashboard", response_model=ApiResponse[StatusMessage])
async def warehouse_dashboard(user: dict = Depends(require_permission("view_warehouse"))):
    """Warehouse dashboard — KPIs, stock health, action queue."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="warehouse/dashboard"),
        message="Warehouse Dashboard — coming in Phase 3.",
    )


@router.get("/inventory", response_model=ApiResponse[StatusMessage])
async def warehouse_inventory(user: dict = Depends(require_permission("view_warehouse"))):
    """Full warehouse inventory grid with filters."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="warehouse/inventory"),
        message="Warehouse Inventory — coming in Phase 3.",
    )


@router.get("/staging", response_model=ApiResponse[StatusMessage])
async def staging_area(user: dict = Depends(require_permission("view_warehouse"))):
    """Pulled/staging area — items prepped for jobs or trucks."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="warehouse/staging"),
        message="Staging Area — coming in Phase 3.",
    )


@router.get("/audit", response_model=ApiResponse[StatusMessage])
async def audit(user: dict = Depends(require_permission("perform_audit"))):
    """Card-swipe audit flow. Permission-gated."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="warehouse/audit"),
        message="Audit — coming in Phase 3.",
    )


@router.get("/movements", response_model=ApiResponse[StatusMessage])
async def movements_log(user: dict = Depends(require_permission("view_warehouse"))):
    """Movement history log with user, photos, timestamps."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="warehouse/movements"),
        message="Movements Log — coming in Phase 3.",
    )
