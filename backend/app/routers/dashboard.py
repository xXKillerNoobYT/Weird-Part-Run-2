"""
Dashboard routes — KPI cards, quick actions, and system health.

Phase 1: Returns stub data. Full implementation in Phase 2+.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from app.middleware.auth import require_user
from app.models.common import ApiResponse

router = APIRouter(prefix="/api/dashboard", tags=["Dashboard"])


@router.get("/", response_model=ApiResponse[dict])
async def get_dashboard(user: dict = Depends(require_user)):
    """Get dashboard data — KPI cards and quick actions."""
    return ApiResponse(
        data={
            "status": "stub",
            "module": "dashboard",
            "kpis": {
                "total_parts": 0,
                "active_jobs": 0,
                "pending_orders": 0,
                "low_stock_alerts": 0,
            },
            "quick_actions": [
                {"label": "New Job", "icon": "briefcase", "route": "/jobs/new"},
                {"label": "Move Stock", "icon": "arrow-right-left", "route": "/warehouse/move"},
                {"label": "New Order", "icon": "shopping-cart", "route": "/orders/new"},
            ],
            "user_name": user["display_name"],
        },
        message="Dashboard data (stub — full implementation in Phase 2).",
    )
