"""
Costs routes — cost layers, margin management, spending analytics, budget monitoring.

Phase 7D: Analytics & Visibility.

Route groups:
  /api/costs/settings         — Company-wide cost settings
  /api/costs/part/{id}/…      — Per-part cost layers, history, margins
  /api/costs/enforce-…        — Bulk margin management
  /api/costs/dashboard        — Spending summary KPIs
  /api/costs/spending/…       — Breakdowns by supplier, category, job, trend
  /api/costs/job/{id}/…       — Job cost rollup and budget status
  /api/costs/variance-report  — Price variance analysis
  /api/costs/budget-alerts    — Active budget warnings

Permissions:
  - show_dollar_values  → view cost data, layers, job rollups
  - edit_pricing        → modify margins, enforce defaults, update settings
  - manage_orders       → spending dashboard, variance reports, budget alerts
"""

from __future__ import annotations

from datetime import date, timedelta

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException, Query

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse
from app.models.costs import (
    BudgetAlert,
    CategorySpend,
    CompanySettingResponse,
    CompanySettingUpdate,
    CostHistoryPoint,
    CostLayerResponse,
    DailyReportData,
    JobCostRollup,
    JobSpend,
    MarginUpdate,
    PartCostSummary,
    PriceVarianceItem,
    SpendingSummary,
    SpendingTrendPoint,
    SupplierSpend,
)
from app.services.cost_tracking_service import CostTrackingService
from app.services.spending_service import SpendingService

router = APIRouter(prefix="/api/costs", tags=["Costs"])


# ── Helpers ────────────────────────────────────────────────────────

def _default_date_range(
    date_from: str | None,
    date_to: str | None,
) -> tuple[str, str]:
    """Default to current month if no dates provided."""
    today = date.today()
    if not date_from:
        date_from = today.replace(day=1).isoformat()
    if not date_to:
        # First day of next month
        if today.month == 12:
            date_to = today.replace(year=today.year + 1, month=1, day=1).isoformat()
        else:
            date_to = today.replace(month=today.month + 1, day=1).isoformat()
    return date_from, date_to


# ═══════════════════════════════════════════════════════════════════
# Company Cost Settings
# ═══════════════════════════════════════════════════════════════════

@router.get("/settings", response_model=ApiResponse[list[CompanySettingResponse]])
async def get_company_settings(
    user: dict = Depends(require_permission("show_dollar_values")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all company cost settings (margin defaults, cost method, etc.)."""
    svc = CostTrackingService(db)
    settings = await svc.get_company_settings()
    return ApiResponse(data=settings)


@router.put("/settings/{key}", response_model=ApiResponse[CompanySettingResponse])
async def update_company_setting(
    key: str,
    body: CompanySettingUpdate,
    user: dict = Depends(require_permission("edit_pricing")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a company cost setting value."""
    svc = CostTrackingService(db)
    result = await svc.update_company_setting(key, body.setting_value, user["id"])
    if not result:
        raise HTTPException(status_code=404, detail=f"Setting '{key}' not found")
    return ApiResponse(data=result)


# ═══════════════════════════════════════════════════════════════════
# Per-Part Cost Layers & History
# ═══════════════════════════════════════════════════════════════════

@router.get(
    "/part/{part_id}/layers",
    response_model=ApiResponse[list[CostLayerResponse]],
)
async def get_cost_layers(
    part_id: int,
    user: dict = Depends(require_permission("show_dollar_values")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get active cost layers for a part (FIFO audit view)."""
    svc = CostTrackingService(db)
    layers = await svc.get_cost_layers(part_id)
    return ApiResponse(data=layers)


@router.get(
    "/part/{part_id}/history",
    response_model=ApiResponse[list[CostHistoryPoint]],
)
async def get_cost_history(
    part_id: int,
    days: int = Query(90, ge=7, le=365, description="Number of days to look back"),
    user: dict = Depends(require_permission("show_dollar_values")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get cost change history for sparkline charts."""
    svc = CostTrackingService(db)
    history = await svc.get_cost_history(part_id, days)
    return ApiResponse(data=history)


@router.get(
    "/part/{part_id}/summary",
    response_model=ApiResponse[PartCostSummary],
)
async def get_part_cost_summary(
    part_id: int,
    user: dict = Depends(require_permission("show_dollar_values")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get consolidated cost info for a part: avg cost, margin, sell price, layer count."""
    svc = CostTrackingService(db)
    try:
        margin_info = await svc.get_margin(part_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Part not found")

    layers = await svc.get_cost_layers(part_id)

    # Build cost_last_updated from parts table
    cursor = await db.execute(
        "SELECT cost_last_updated FROM parts WHERE id = ?", (part_id,)
    )
    row = await cursor.fetchone()

    return ApiResponse(data={
        "part_id": part_id,
        "weighted_avg_cost": margin_info["weighted_avg_cost"],
        "custom_margin_percent": margin_info["custom_margin_percent"],
        "effective_margin_percent": margin_info["effective_margin_percent"],
        "calculated_sell_price": margin_info["calculated_sell_price"],
        "cost_last_updated": row["cost_last_updated"] if row else None,
        "active_layers": len(layers),
    })


# ═══════════════════════════════════════════════════════════════════
# Margin Management
# ═══════════════════════════════════════════════════════════════════

@router.put("/part/{part_id}/margin", response_model=ApiResponse[dict])
async def set_custom_margin(
    part_id: int,
    body: MarginUpdate,
    user: dict = Depends(require_permission("edit_pricing")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Set a custom margin override on a part."""
    svc = CostTrackingService(db)
    await svc.set_custom_margin(part_id, body.margin_percent)
    margin_info = await svc.get_margin(part_id)
    return ApiResponse(data=margin_info)


@router.delete("/part/{part_id}/margin", response_model=ApiResponse[dict])
async def clear_custom_margin(
    part_id: int,
    user: dict = Depends(require_permission("edit_pricing")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Remove custom margin — revert to company default."""
    svc = CostTrackingService(db)
    await svc.clear_custom_margin(part_id)
    margin_info = await svc.get_margin(part_id)
    return ApiResponse(data=margin_info)


@router.post("/enforce-default-margin", response_model=ApiResponse[dict])
async def enforce_default_margin(
    user: dict = Depends(require_permission("edit_pricing")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Reset ALL parts to company default margin. Returns count of parts cleared."""
    svc = CostTrackingService(db)
    count = await svc.enforce_default_margin()
    return ApiResponse(data={"cleared_count": count, "message": f"Cleared {count} custom margins"})


# ═══════════════════════════════════════════════════════════════════
# Spending Dashboard
# ═══════════════════════════════════════════════════════════════════

@router.get("/dashboard", response_model=ApiResponse[SpendingSummary])
async def get_spending_dashboard(
    date_from: str | None = Query(None, description="Start date (YYYY-MM-DD), defaults to 1st of current month"),
    date_to: str | None = Query(None, description="End date (YYYY-MM-DD), defaults to 1st of next month"),
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Top-level spending KPIs for a date range."""
    df, dt = _default_date_range(date_from, date_to)
    svc = SpendingService(db)
    summary = await svc.get_spending_summary(df, dt)
    return ApiResponse(data=summary)


@router.get(
    "/spending/by-supplier",
    response_model=ApiResponse[list[SupplierSpend]],
)
async def get_spending_by_supplier(
    date_from: str | None = Query(None),
    date_to: str | None = Query(None),
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Spending breakdown by supplier."""
    df, dt = _default_date_range(date_from, date_to)
    svc = SpendingService(db)
    data = await svc.get_spending_by_supplier(df, dt)
    return ApiResponse(data=data)


@router.get(
    "/spending/by-category",
    response_model=ApiResponse[list[CategorySpend]],
)
async def get_spending_by_category(
    date_from: str | None = Query(None),
    date_to: str | None = Query(None),
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Spending breakdown by part category."""
    df, dt = _default_date_range(date_from, date_to)
    svc = SpendingService(db)
    data = await svc.get_spending_by_category(df, dt)
    return ApiResponse(data=data)


@router.get(
    "/spending/by-job",
    response_model=ApiResponse[list[JobSpend]],
)
async def get_spending_by_job(
    date_from: str | None = Query(None),
    date_to: str | None = Query(None),
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Spending breakdown by job (via JPO → PO linkage)."""
    df, dt = _default_date_range(date_from, date_to)
    svc = SpendingService(db)
    data = await svc.get_spending_by_job(df, dt)
    return ApiResponse(data=data)


@router.get(
    "/spending/trend",
    response_model=ApiResponse[list[SpendingTrendPoint]],
)
async def get_spending_trend(
    date_from: str | None = Query(None),
    date_to: str | None = Query(None),
    group_by: str = Query("month", pattern="^(month|week)$"),
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Spending trend over time, grouped by month or week."""
    df, dt = _default_date_range(date_from, date_to)
    svc = SpendingService(db)
    data = await svc.get_spending_trend(df, dt, group_by)
    return ApiResponse(data=data)


# ═══════════════════════════════════════════════════════════════════
# Job Cost Rollup & Budget
# ═══════════════════════════════════════════════════════════════════

@router.get("/job/{job_id}/rollup", response_model=ApiResponse[JobCostRollup])
async def get_job_cost_rollup(
    job_id: int,
    user: dict = Depends(require_permission("show_dollar_values")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Full cost rollup for a job: parts + labor + budget status."""
    svc = SpendingService(db)
    try:
        rollup = await svc.get_job_cost_rollup(job_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Job not found")
    return ApiResponse(data=rollup)


@router.get("/job/{job_id}/budget-status", response_model=ApiResponse[dict])
async def get_job_budget_status(
    job_id: int,
    user: dict = Depends(require_permission("show_dollar_values")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Quick budget status check for a job."""
    svc = SpendingService(db)
    try:
        status = await svc.get_job_budget_status(job_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Job not found")
    return ApiResponse(data=status)


# ═══════════════════════════════════════════════════════════════════
# Price Variance & Budget Alerts
# ═══════════════════════════════════════════════════════════════════

@router.get(
    "/variance-report",
    response_model=ApiResponse[list[PriceVarianceItem]],
)
async def get_price_variance_report(
    date_from: str | None = Query(None),
    date_to: str | None = Query(None),
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Price variance report: received vs quoted prices."""
    df, dt = _default_date_range(date_from, date_to)
    svc = SpendingService(db)
    data = await svc.get_price_variance_report(df, dt)
    return ApiResponse(data=data)


@router.get(
    "/budget-alerts",
    response_model=ApiResponse[list[BudgetAlert]],
)
async def get_budget_alerts(
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all active job budget alerts (jobs approaching or exceeding budget)."""
    svc = SpendingService(db)
    alerts = await svc.check_budget_alerts()
    return ApiResponse(data=alerts)


# ═══════════════════════════════════════════════════════════════════
# Daily Report (Live Dashboard)
# ═══════════════════════════════════════════════════════════════════

@router.get("/daily-report", response_model=ApiResponse[DailyReportData])
async def get_daily_report(
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Live daily report: pending actions, expected deliveries, today's activity.

    Available to all authenticated users — field workers see the same live
    dashboard as office staff (role-specific filtering is done on the frontend).
    """
    svc = SpendingService(db)
    report = await svc.get_daily_report()
    return ApiResponse(data=report)
