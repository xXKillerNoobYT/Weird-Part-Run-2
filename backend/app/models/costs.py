"""
Pydantic models for the Cost Tracking & Analytics system (Phase 7D).

Covers:
  - Cost Layers — FIFO/LIFO inventory cost tracking
  - Company Cost Settings — company-wide margin and pricing config
  - Spending Analytics — dashboard charts, supplier/category/job breakdowns
  - Job Cost Rollup — per-job budget tracking and alerts
  - Price Variance — received vs quoted price deviation reports
  - Daily Report — live dashboard aggregation
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


# ═══════════════════════════════════════════════════════════════
# Cost Layer Models
# ═══════════════════════════════════════════════════════════════

class CostLayerResponse(BaseModel):
    """A single inventory cost layer for audit/display."""
    id: int
    part_id: int
    purchase_date: str
    po_line_id: int | None = None
    original_qty: int
    remaining_qty: int
    unit_cost: float
    created_at: datetime | None = None
    # Joined fields
    po_number: str | None = None


class CostHistoryPoint(BaseModel):
    """A single data point for cost sparkline charts."""
    date: str
    weighted_avg_cost: float
    total_qty: int


# ═══════════════════════════════════════════════════════════════
# Company Settings Models
# ═══════════════════════════════════════════════════════════════

class CompanySettingResponse(BaseModel):
    """A company-wide cost setting."""
    setting_key: str
    setting_value: str
    updated_by: int | None = None
    updated_at: datetime | None = None
    # Joined
    updated_by_name: str | None = None


class CompanySettingUpdate(BaseModel):
    """Update a company setting value."""
    setting_value: str = Field(..., min_length=1)


# ═══════════════════════════════════════════════════════════════
# Margin Models
# ═══════════════════════════════════════════════════════════════

class MarginUpdate(BaseModel):
    """Set a custom margin percentage on a part."""
    margin_percent: float = Field(..., ge=0, le=100)


class PartCostSummary(BaseModel):
    """Consolidated cost info for a single part (used in pricing views)."""
    part_id: int
    weighted_avg_cost: float = 0
    custom_margin_percent: float | None = None
    effective_margin_percent: float = 25  # falls back to company default
    calculated_sell_price: float = 0
    cost_last_updated: str | None = None
    active_layers: int = 0  # count of layers with remaining_qty > 0


# ═══════════════════════════════════════════════════════════════
# Spending Dashboard Models
# ═══════════════════════════════════════════════════════════════

class SpendingSummary(BaseModel):
    """Top-level spending KPIs for a date range."""
    total_spend: float = 0
    order_count: int = 0
    avg_order_size: float = 0
    active_suppliers: int = 0
    period_label: str = ""  # e.g. "March 2026"


class SupplierSpend(BaseModel):
    """Spending breakdown for a single supplier."""
    supplier_id: int
    supplier_name: str
    total_spend: float = 0
    order_count: int = 0
    pct_of_total: float = 0


class CategorySpend(BaseModel):
    """Spending breakdown for a part category."""
    category_id: int | None = None
    category_name: str
    total_spend: float = 0
    item_count: int = 0


class JobSpend(BaseModel):
    """Spending breakdown for a single job."""
    job_id: int
    job_name: str
    total_spend: float = 0
    budget_limit: float | None = None
    budget_pct: float | None = None  # spend / budget * 100


class SpendingTrendPoint(BaseModel):
    """A single point on the spending trend line chart."""
    period_label: str  # e.g. "Jan 2026", "Week 9"
    total_spend: float = 0
    order_count: int = 0


# ═══════════════════════════════════════════════════════════════
# Job Cost Rollup Models
# ═══════════════════════════════════════════════════════════════

class JobCostRollup(BaseModel):
    """Full cost rollup for a single job."""
    job_id: int
    job_name: str
    total_parts_cost: float = 0
    total_labor_cost: float = 0
    combined_total: float = 0
    budget_limit: float | None = None
    budget_remaining: float | None = None
    budget_pct: float | None = None  # combined_total / budget * 100
    budget_alert_percent: float = 80


class BudgetAlert(BaseModel):
    """A job approaching or exceeding its budget."""
    job_id: int
    job_name: str
    budget_limit: float
    current_spend: float
    pct_used: float
    alert_level: str  # 'warning' (≥alert_percent) | 'danger' (≥95%)


# ═══════════════════════════════════════════════════════════════
# Price Variance Models
# ═══════════════════════════════════════════════════════════════

class PriceVarianceItem(BaseModel):
    """A part whose received price deviated from the quoted PO price."""
    part_id: int
    part_name: str
    supplier_name: str
    po_number: str
    quoted_price: float
    actual_price: float
    variance_amount: float  # actual - quoted
    variance_pct: float  # abs variance / quoted * 100
    variance_level: str  # 'ok' (<5%) | 'warning' (5-15%) | 'danger' (>15%)


# ═══════════════════════════════════════════════════════════════
# Daily Report Models
# ═══════════════════════════════════════════════════════════════

class DailyReportPendingActions(BaseModel):
    """Counts of items needing attention."""
    jpos_awaiting_approval: int = 0
    pos_to_submit: int = 0
    returns_to_sort: int = 0
    overdue_deliveries: int = 0


class DailyReportDelivery(BaseModel):
    """A PO expected this week."""
    po_id: int
    po_number: str
    supplier_name: str
    expected_delivery: str
    line_count: int = 0
    is_overdue: bool = False


class DailyReportActivity(BaseModel):
    """Today's activity summary."""
    orders_created: int = 0
    items_received: int = 0
    returns_processed: int = 0


class DailyReportData(BaseModel):
    """Full daily report response."""
    pending_actions: DailyReportPendingActions
    expected_deliveries: list[DailyReportDelivery] = Field(default_factory=list)
    overdue_items: list[DailyReportDelivery] = Field(default_factory=list)
    todays_activity: DailyReportActivity
    budget_alerts: list[BudgetAlert] = Field(default_factory=list)
