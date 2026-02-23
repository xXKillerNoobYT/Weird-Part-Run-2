"""
Orders routes — PO lifecycle, procurement planner, returns.

Phase 1: Returns stub responses. Full implementation in Phase 5.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse, StatusMessage

router = APIRouter(prefix="/api/orders", tags=["Orders"])


@router.get("/drafts", response_model=ApiResponse[StatusMessage])
async def draft_orders(user: dict = Depends(require_permission("view_orders"))):
    """Draft purchase orders awaiting submission."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="orders/drafts"),
        message="Draft POs — coming in Phase 5.",
    )


@router.get("/pending", response_model=ApiResponse[StatusMessage])
async def pending_orders(user: dict = Depends(require_permission("view_orders"))):
    """Submitted POs awaiting delivery."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="orders/pending"),
        message="Pending Orders — coming in Phase 5.",
    )


@router.get("/incoming", response_model=ApiResponse[StatusMessage])
async def incoming_orders(user: dict = Depends(require_permission("view_orders"))):
    """Received/partial POs → Guided Receive flow."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="orders/incoming"),
        message="Incoming Orders — coming in Phase 5.",
    )


@router.get("/returns", response_model=ApiResponse[StatusMessage])
async def returns(user: dict = Depends(require_permission("approve_returns"))):
    """Return requests and RMA tracking. Permission-gated."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="orders/returns"),
        message="Returns — coming in Phase 5.",
    )


@router.get("/procurement", response_model=ApiResponse[StatusMessage])
async def procurement_planner(user: dict = Depends(require_permission("manage_orders"))):
    """Procurement optimization dashboard with suggestions."""
    return ApiResponse(
        data=StatusMessage(status="stub", module="orders/procurement"),
        message="Procurement Planner — coming in Phase 5.",
    )
