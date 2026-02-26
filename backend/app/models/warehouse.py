"""
Warehouse Pydantic models — requests and responses for Phase 3.

Covers:
- Movement wizard (validate, preview, execute)
- Dashboard KPIs and activity
- Inventory grid
- Staging area
- Audit sessions and items
- Supplier preferences
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field


# =================================================================
# MOVEMENT WIZARD
# =================================================================

class MovementLineItem(BaseModel):
    """A single part+qty line within a movement request."""
    part_id: int
    qty: int = Field(ge=1)
    supplier_id: int | None = None  # resolved automatically if not provided


class MovementRequest(BaseModel):
    """Request to validate, preview, or execute a stock movement."""
    from_location_type: str
    from_location_id: int = 1
    to_location_type: str
    to_location_id: int = 1
    items: list[MovementLineItem] = Field(min_length=1, max_length=20)
    # Optional metadata
    reason: str | None = None
    reason_detail: str | None = None
    notes: str | None = None
    reference_number: str | None = None
    job_id: int | None = None
    photo_path: str | None = None
    scan_confirmed: bool = False
    gps_lat: float | None = None
    gps_lng: float | None = None
    # Staging destination hint (only for moves TO pulled)
    destination_type: str | None = None  # 'truck' or 'job'
    destination_id: int | None = None
    destination_label: str | None = None


class ValidationError(BaseModel):
    """A single validation error from pre-flight check."""
    field: str | None = None
    message: str
    part_id: int | None = None


class ValidationResult(BaseModel):
    """Result of movement validation."""
    valid: bool
    errors: list[ValidationError] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


class MovementPreviewLine(BaseModel):
    """Preview of a single line item's before/after state."""
    part_id: int
    part_name: str
    part_code: str | None = None
    qty: int
    supplier_id: int | None = None
    supplier_name: str | None = None
    supplier_source: str | None = None  # 'preferred' or 'fifo'
    source_before: int
    source_after: int
    dest_before: int
    dest_after: int
    unit_cost: float | None = None
    line_value: float | None = None


class MovementPreview(BaseModel):
    """Full preview of a movement batch before execution."""
    lines: list[MovementPreviewLine]
    total_qty: int = 0
    total_value: float | None = None
    movement_type: str  # transfer, consume, return
    photo_required: bool = False
    warnings: list[str] = Field(default_factory=list)


class MovementResult(BaseModel):
    """Result of a single executed movement line."""
    movement_id: int
    part_id: int
    part_name: str
    qty: int
    movement_type: str
    from_location_type: str | None = None
    to_location_type: str | None = None


class MovementExecuteResponse(BaseModel):
    """Response from executing a batch movement."""
    success: bool = True
    movements: list[MovementResult] = Field(default_factory=list)
    total_items: int = 0
    total_qty: int = 0


# =================================================================
# MOVEMENT RULES
# =================================================================

MOVEMENT_RULES: dict[tuple[str, str], dict[str, Any]] = {
    ("warehouse", "pulled"):   {"type": "transfer", "photo_required": False},
    ("pulled", "truck"):       {"type": "transfer", "photo_required": False},
    ("warehouse", "truck"):    {"type": "transfer", "photo_required": False},
    ("truck", "job"):          {"type": "consume",  "photo_required": True},
    ("job", "truck"):          {"type": "return",   "photo_required": True},
    ("truck", "warehouse"):    {"type": "return",   "photo_required": False},
    ("pulled", "warehouse"):   {"type": "return",   "photo_required": False},
}

VALID_LOCATION_TYPES = {"warehouse", "pulled", "truck", "job"}

# Reason categories and sub-reasons for the wizard
REASON_CATEGORIES: dict[str, list[str]] = {
    "Job Stock": ["New Install", "Repair/Replace", "Service Call", "Warranty Work"],
    "Truck Restock": ["Daily Restock", "Special Order", "Emergency Load"],
    "Return": ["Unused/Leftover", "Wrong Part", "Job Cancelled", "Overstock"],
    "Damage/Loss": ["Damaged Transit", "Damaged on Job", "Lost/Missing", "Defective"],
    "Audit Adjustment": ["Count Correction", "Found Extra", "Write-off"],
    "Other": [],
}


# =================================================================
# DASHBOARD
# =================================================================

class DashboardKPIs(BaseModel):
    """Warehouse dashboard headline numbers."""
    stock_health_pct: float = 0.0       # % of parts within min/max range
    total_units: int = 0                 # total qty across warehouse
    warehouse_value: float | None = None  # $ value (permission-gated)
    shortfall_count: int = 0             # parts below min (excl. winding down)
    pending_task_count: int = 0          # staged items + audits + spot-checks


class ActivitySummary(BaseModel):
    """One-line summary of a recent movement for the activity feed."""
    id: int
    summary: str           # e.g. "Mike pulled 12× GFI White to Staging"
    movement_type: str
    performer_name: str | None = None
    created_at: datetime | None = None


class PendingTask(BaseModel):
    """A pending action item for the warehouse dashboard."""
    task_type: str         # 'staged_item', 'audit', 'spot_check'
    title: str             # "Staged: 5 items for Truck #2"
    subtitle: str | None = None  # "2 hours ago"
    severity: str = "normal"  # 'normal', 'warning', 'critical'
    # Contextual IDs for navigation
    audit_id: int | None = None
    part_id: int | None = None
    stock_id: int | None = None
    destination_type: str | None = None
    destination_id: int | None = None


class DashboardData(BaseModel):
    """Combined dashboard payload (single request)."""
    kpis: DashboardKPIs
    recent_activity: list[ActivitySummary] = Field(default_factory=list)
    pending_tasks: list[PendingTask] = Field(default_factory=list)


# =================================================================
# INVENTORY GRID
# =================================================================

class WarehouseInventoryItem(BaseModel):
    """A single row in the warehouse inventory grid."""
    part_id: int
    part_code: str | None = None
    part_name: str
    category_id: int | None = None
    category_name: str | None = None
    brand_id: int | None = None
    brand_name: str | None = None
    unit_of_measure: str = "each"
    shelf_location: str | None = None
    bin_location: str | None = None
    # Stock levels
    warehouse_qty: int = 0
    pulled_qty: int = 0
    truck_qty: int = 0
    total_qty: int = 0
    # Targets
    min_stock_level: int = 0
    target_stock_level: int = 0
    max_stock_level: int = 0
    # Health
    stock_status: str = "in_range"  # low_stock, overstock, in_range, winding_down, zero
    health_pct: float = 0.0        # 0-100 for progress bar
    # Pricing (permission-gated)
    unit_cost: float | None = None
    total_value: float | None = None
    # Forecast
    forecast_days_until_low: int | None = None
    # Supplier info
    primary_supplier_name: str | None = None
    # QR tagging
    is_qr_tagged: bool = False


# =================================================================
# STAGING
# =================================================================

class StagingItem(BaseModel):
    """A single pulled/staged stock entry with destination tag."""
    stock_id: int
    part_id: int
    part_name: str
    part_code: str | None = None
    qty: int
    supplier_name: str | None = None
    # Destination tag
    destination_type: str | None = None  # 'truck' or 'job'
    destination_id: int | None = None
    destination_label: str | None = None
    # Who pulled and when
    tagged_by_name: str | None = None
    staged_at: datetime | None = None
    # Aging
    hours_staged: float = 0.0
    aging_status: str = "normal"  # 'normal', 'warning' (24h), 'critical' (48h)


class StagingGroup(BaseModel):
    """Staged items grouped by destination."""
    destination_type: str | None = None
    destination_id: int | None = None
    destination_label: str
    items: list[StagingItem] = Field(default_factory=list)
    total_qty: int = 0
    oldest_hours: float = 0.0
    aging_status: str = "normal"


# =================================================================
# AUDIT
# =================================================================

class AuditStartRequest(BaseModel):
    """Request to start a new audit session."""
    audit_type: str = Field(pattern="^(spot_check|category|rolling)$")
    location_type: str = "warehouse"
    location_id: int = 1
    category_id: int | None = None  # required for category audits
    part_ids: list[int] | None = None  # for spot checks on specific parts


class AuditCountRequest(BaseModel):
    """Request to record a count for an audit item."""
    actual_qty: int = Field(ge=0)
    result: str = Field(pattern="^(match|discrepancy|skipped)$")
    discrepancy_note: str | None = None
    photo_path: str | None = None


class AuditItemResponse(BaseModel):
    """An individual audit item (for card-swipe UI)."""
    id: int
    audit_id: int
    part_id: int
    part_name: str
    part_code: str | None = None
    shelf_location: str | None = None
    image_url: str | None = None
    expected_qty: int
    actual_qty: int | None = None
    result: str = "pending"
    discrepancy_note: str | None = None
    photo_path: str | None = None
    counted_at: str | None = None


class AuditProgress(BaseModel):
    """Progress stats for an ongoing audit."""
    total_items: int = 0
    counted: int = 0
    matched: int = 0
    discrepancies: int = 0
    skipped: int = 0
    pending: int = 0
    pct_complete: float = 0.0


class AuditResponse(BaseModel):
    """Full audit session response."""
    id: int
    audit_type: str
    location_type: str
    location_id: int
    category_id: int | None = None
    category_name: str | None = None
    status: str
    started_by: int
    started_by_name: str | None = None
    completed_at: str | None = None
    progress: AuditProgress = Field(default_factory=AuditProgress)
    notes: str | None = None
    created_at: datetime | None = None


class AuditSummary(BaseModel):
    """Summary shown after completing an audit."""
    audit_id: int
    audit_type: str
    status: str
    progress: AuditProgress
    adjustments_needed: int = 0  # discrepancies that need stock adjustment
    has_unapplied_adjustments: bool = False


# =================================================================
# SUPPLIER PREFERENCES
# =================================================================

class SupplierPreferenceResponse(BaseModel):
    """Resolved preferred supplier for a scope."""
    scope_type: str | None = None
    scope_id: int | None = None
    supplier_id: int | None = None
    supplier_name: str | None = None
    resolved_from: str | None = None  # which level it was resolved from


class SupplierPreferenceSet(BaseModel):
    """Request to set a preferred supplier for a scope level."""
    scope_type: str = Field(pattern="^(category|style|type|part)$")
    scope_id: int
    supplier_id: int


# =================================================================
# LOCATIONS HELPER
# =================================================================

class LocationOption(BaseModel):
    """An available from/to location for the wizard."""
    location_type: str
    location_id: int
    label: str       # "Warehouse", "Truck #2", "Job #1042"
    sub_label: str | None = None  # "Main", "Mike's Truck"


# =================================================================
# RECEIVE STOCK (add new stock to warehouse)
# =================================================================

class ReceiveStockItem(BaseModel):
    """A single line item when receiving stock into the warehouse."""
    part_id: int
    qty: int = Field(ge=1, description="Quantity to add")
    shelf_location: str | None = None  # General area (Row A, Shelf 3)
    bin_location: str | None = None    # Specific bin (Bin 12) — optional
    supplier_id: int | None = None     # Which supplier provided this stock
    notes: str | None = None           # Optional notes for this line


class ReceiveStockRequest(BaseModel):
    """Request to receive stock into the warehouse.

    This is stock entering the system from outside (delivery, found stock, etc.)
    — not a transfer between locations.
    """
    items: list[ReceiveStockItem] = Field(min_length=1, max_length=50)
    reason: str | None = "Stock Received"  # Overall reason
    notes: str | None = None               # Overall notes
    reference_number: str | None = None    # PO number, delivery ref, etc.


class ReceiveStockResult(BaseModel):
    """Result of receiving stock."""
    success: bool = True
    items_received: int = 0
    total_qty: int = 0
    movement_ids: list[int] = Field(default_factory=list)
