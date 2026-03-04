"""
Pydantic models for the Orders & Procurement system.

Covers:
  - Job Parts Orders (JPO) — field-worker requests
  - Purchase Orders (PO) — supplier-facing orders
  - PO Line Items — individual items on a PO
  - Returns — job-to-warehouse and warehouse-to-supplier
  - Staging Zones — physical QR-coded staging areas
  - Order Status History — audit trail
  - Price History — supplier pricing over time
  - Supplier Contact Ratings — communication scoring
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field


# ═══════════════════════════════════════════════════════════════
# JPO (Job Parts Order) Models
# ═══════════════════════════════════════════════════════════════

class JPOLineCreate(BaseModel):
    """A single line item when creating a JPO."""
    part_id: int
    qty_requested: int = Field(1, ge=1)
    priority: str = "normal"  # normal | urgent | critical
    entry_id: int | None = None  # optional notebook task link
    suggested_supplier_id: int | None = None
    notes: str | None = None


class JPOCreate(BaseModel):
    """Create a new Job Parts Order."""
    job_id: int
    priority: str = "normal"  # normal | urgent
    notes: str | None = None
    lines: list[JPOLineCreate] = Field(default_factory=list)


class JPOUpdate(BaseModel):
    """Update an existing JPO (only while in draft)."""
    priority: str | None = None
    notes: str | None = None


class JPOLineResponse(BaseModel):
    """A JPO line item in API responses."""
    id: int
    jpo_id: int
    part_id: int
    qty_requested: int
    qty_ordered: int = 0
    qty_received: int = 0
    priority: str = "normal"
    entry_id: int | None = None
    suggested_supplier_id: int | None = None
    notes: str | None = None
    created_at: datetime | None = None
    # Joined fields
    part_number: str | None = None
    part_description: str | None = None
    supplier_name: str | None = None


class JPOResponse(BaseModel):
    """JPO in API responses."""
    id: int
    job_id: int
    order_number: str
    status: str
    priority: str = "normal"
    requested_by: int
    approved_by: int | None = None
    approved_at: datetime | None = None
    notes: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
    # Joined fields
    job_name: str | None = None
    job_number: str | None = None
    requester_name: str | None = None
    approver_name: str | None = None
    line_count: int = 0
    lines: list[JPOLineResponse] | None = None


class JPOListItem(BaseModel):
    """Compact JPO for list views."""
    id: int
    job_id: int
    order_number: str
    status: str
    priority: str = "normal"
    requested_by: int
    requester_name: str | None = None
    job_name: str | None = None
    job_number: str | None = None
    line_count: int = 0
    created_at: datetime | None = None
    updated_at: datetime | None = None


class JPOApproval(BaseModel):
    """Approve or reject a JPO."""
    action: str = Field(..., pattern="^(approve|reject)$")
    notes: str | None = None


# ═══════════════════════════════════════════════════════════════
# PO (Purchase Order) Models
# ═══════════════════════════════════════════════════════════════

class POLineCreate(BaseModel):
    """A single line item when creating a PO."""
    part_id: int
    jpo_line_id: int | None = None  # NULL for standalone POs
    qty_ordered: int = Field(..., ge=1)
    unit_cost: float | None = None
    notes: str | None = None


class POCreate(BaseModel):
    """Create a new Purchase Order."""
    supplier_id: int
    expected_delivery: str | None = None
    shipping_method: str | None = None
    notes: str | None = None
    internal_notes: str | None = None
    lines: list[POLineCreate] = Field(default_factory=list)


class POUpdate(BaseModel):
    """Update an existing PO (only while in draft)."""
    expected_delivery: str | None = None
    shipping_method: str | None = None
    tracking_number: str | None = None
    notes: str | None = None
    internal_notes: str | None = None
    tax_amount: float | None = None
    shipping_cost: float | None = None


class POLineResponse(BaseModel):
    """PO line item in API responses."""
    id: int
    po_id: int
    jpo_line_id: int | None = None
    part_id: int
    qty_ordered: int
    qty_received: int = 0
    unit_cost: float | None = None
    received_unit_cost: float | None = None
    status: str = "pending"
    backorder_expected_date: str | None = None
    received_at: datetime | None = None
    received_by: int | None = None
    notes: str | None = None
    created_at: datetime | None = None
    # Joined fields
    part_number: str | None = None
    part_description: str | None = None
    line_total: float | None = None


class POResponse(BaseModel):
    """PO in API responses."""
    id: int
    po_number: str
    supplier_id: int
    status: str
    order_date: str | None = None
    expected_delivery: str | None = None
    actual_delivery: str | None = None
    shipping_method: str | None = None
    tracking_number: str | None = None
    subtotal: float = 0
    tax_amount: float = 0
    shipping_cost: float = 0
    total_cost: float = 0
    notes: str | None = None
    internal_notes: str | None = None
    pdf_path: str | None = None
    submitted_by: int | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
    # Joined fields
    supplier_name: str | None = None
    submitter_name: str | None = None
    line_count: int = 0
    lines: list[POLineResponse] | None = None


class POListItem(BaseModel):
    """Compact PO for list views."""
    id: int
    po_number: str
    supplier_id: int
    supplier_name: str | None = None
    status: str
    order_date: str | None = None
    expected_delivery: str | None = None
    total_cost: float = 0
    line_count: int = 0
    created_at: datetime | None = None
    updated_at: datetime | None = None


class POFromJPO(BaseModel):
    """Create POs from an approved JPO — groups lines by supplier."""
    jpo_id: int
    supplier_line_groups: list[SupplierLineGroup] | None = None  # None = auto-group


class SupplierLineGroup(BaseModel):
    """A group of JPO lines destined for one supplier."""
    supplier_id: int
    line_ids: list[int]
    expected_delivery: str | None = None
    notes: str | None = None


# ═══════════════════════════════════════════════════════════════
# Receiving Models
# ═══════════════════════════════════════════════════════════════

class ReceiveItem(BaseModel):
    """Receive a single item from a PO delivery."""
    po_line_id: int
    qty_received: int = Field(..., ge=1)
    actual_cost: float | None = None  # if different from ordered price
    staging_zone_id: int | None = None
    notes: str | None = None


class ReceiveByPO(BaseModel):
    """Receive items for a specific PO."""
    po_id: int
    items: list[ReceiveItem]


class ReceiveBySupplier(BaseModel):
    """Bulk receive items from a supplier delivery."""
    supplier_id: int
    items: list[ReceiveItem]


class BackorderUpdate(BaseModel):
    """Mark remaining items as backordered."""
    po_line_id: int
    expected_date: str | None = None
    notes: str | None = None


# ═══════════════════════════════════════════════════════════════
# Return Models
# ═══════════════════════════════════════════════════════════════

class ReturnLineCreate(BaseModel):
    """A single line item on a return."""
    part_id: int
    po_line_id: int | None = None
    qty: int = Field(..., ge=1)
    condition: str = "new"  # new | used | damaged | defective
    disposition: str  # return_to_supplier | restock | write_off
    unit_cost: float | None = None
    notes: str | None = None


class ReturnCreate(BaseModel):
    """Create a new return."""
    return_type: str  # job_to_warehouse | warehouse_to_supplier
    po_id: int | None = None
    supplier_id: int | None = None
    job_id: int | None = None
    reason: str  # defective | wrong_item | surplus | damaged | unused
    notes: str | None = None
    lines: list[ReturnLineCreate] = Field(default_factory=list)


class ReturnUpdate(BaseModel):
    """Update an existing return."""
    rma_number: str | None = None
    shipping_carrier: str | None = None
    tracking_number: str | None = None
    credit_amount: float | None = None
    notes: str | None = None


class ReturnLineResponse(BaseModel):
    """Return line item in API responses."""
    id: int
    return_id: int
    part_id: int
    po_line_id: int | None = None
    qty: int
    condition: str = "new"
    disposition: str
    unit_cost: float | None = None
    notes: str | None = None
    created_at: datetime | None = None
    # Joined fields
    part_number: str | None = None
    part_description: str | None = None


class ReturnResponse(BaseModel):
    """Return in API responses."""
    id: int
    return_number: str
    return_type: str
    po_id: int | None = None
    supplier_id: int | None = None
    job_id: int | None = None
    status: str
    rma_number: str | None = None
    reason: str
    shipping_carrier: str | None = None
    tracking_number: str | None = None
    credit_amount: float = 0
    notes: str | None = None
    initiated_by: int
    approved_by: int | None = None
    approved_at: datetime | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
    # Joined fields
    supplier_name: str | None = None
    job_name: str | None = None
    initiator_name: str | None = None
    line_count: int = 0
    lines: list[ReturnLineResponse] | None = None


class ReturnListItem(BaseModel):
    """Compact return for list views."""
    id: int
    return_number: str
    return_type: str
    status: str
    reason: str
    supplier_name: str | None = None
    job_name: str | None = None
    initiator_name: str | None = None
    line_count: int = 0
    credit_amount: float = 0
    created_at: datetime | None = None


# ═══════════════════════════════════════════════════════════════
# Staging Zone Models
# ═══════════════════════════════════════════════════════════════

class StagingZoneCreate(BaseModel):
    """Create a new staging zone."""
    label: str = Field(..., min_length=1, max_length=100)
    qr_code: str | None = None
    zone_type: str = "general"
    notes: str | None = None


class StagingZoneUpdate(BaseModel):
    """Update a staging zone."""
    label: str | None = Field(None, min_length=1, max_length=100)
    zone_type: str | None = None
    is_active: bool | None = None
    notes: str | None = None


class StagingZoneResponse(BaseModel):
    """Staging zone in API responses."""
    id: int
    label: str
    qr_code: str | None = None
    zone_type: str = "general"
    current_job_id: int | None = None
    is_active: bool = True
    notes: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
    # Joined fields
    job_name: str | None = None
    item_count: int = 0


class DistributionItem(BaseModel):
    """A single item to distribute from staging."""
    part_id: int
    qty: int = Field(..., ge=1)
    dest_type: str  # warehouse | truck | job
    dest_id: int
    notes: str | None = None


class DistributeFromStaging(BaseModel):
    """Distribute items from a staging zone."""
    zone_id: int
    items: list[DistributionItem]


# ═══════════════════════════════════════════════════════════════
# Status History & Price History Models
# ═══════════════════════════════════════════════════════════════

class StatusHistoryResponse(BaseModel):
    """A single status change in the audit trail."""
    id: int
    entity_type: str
    entity_id: int
    old_status: str | None = None
    new_status: str
    changed_by: int
    changer_name: str | None = None
    notes: str | None = None
    created_at: datetime | None = None


class PriceHistoryResponse(BaseModel):
    """A price record for a part from a supplier."""
    id: int
    part_id: int
    supplier_id: int
    price: float
    effective_date: str
    source: str = "manual"
    reference_id: int | None = None
    notes: str | None = None
    created_at: datetime | None = None
    # Joined
    supplier_name: str | None = None
    part_number: str | None = None


class SupplierContactRatingCreate(BaseModel):
    """Rate a supplier contact interaction."""
    supplier_id: int
    contact_type: str  # business | rep | driver
    score: int = Field(..., ge=1, le=5)
    category: str | None = None  # responsiveness | accuracy | helpfulness | professionalism
    notes: str | None = None
    interaction_date: str | None = None  # defaults to today


class SupplierContactRatingResponse(BaseModel):
    """Supplier contact rating in API responses."""
    id: int
    supplier_id: int
    contact_type: str
    rated_by: int
    score: int
    category: str | None = None
    notes: str | None = None
    interaction_date: str
    created_at: datetime | None = None
    rater_name: str | None = None


class SupplierRanking(BaseModel):
    """Composite supplier ranking for procurement decisions."""
    supplier_id: int
    supplier_name: str
    composite_score: float  # 0.0 – 1.0
    price_score: float = 0
    on_time_score: float = 0
    communication_score: float = 0
    quality_score: float = 0
    lead_time_score: float = 0
    avg_unit_cost: float | None = None
    avg_lead_days: int | None = None
    is_preferred: bool = False


# ═══════════════════════════════════════════════════════════════
# Procurement Dashboard Models
# ═══════════════════════════════════════════════════════════════

class ReorderSuggestion(BaseModel):
    """A single reorder suggestion from the procurement engine."""
    part_id: int
    part_number: str | None = None
    part_description: str | None = None
    current_stock: int = 0
    reorder_point: int = 0
    target_qty: int = 0
    pending_po_qty: int = 0
    expected_return_qty: int = 0
    suggested_order_qty: int = 0
    best_supplier_id: int | None = None
    best_supplier_name: str | None = None
    estimated_cost: float | None = None
    days_until_stockout: int | None = None


class ProcurementDashboard(BaseModel):
    """Summary stats for the procurement dashboard."""
    parts_needing_reorder: int = 0
    pending_po_count: int = 0
    pending_po_value: float = 0
    avg_lead_time_days: float = 0
    overdue_deliveries: int = 0
    parts_below_critical: int = 0


# ═══════════════════════════════════════════════════════════════
# Status Update Bodies (for POST endpoints that receive JSON body)
# ═══════════════════════════════════════════════════════════════

class POStatusUpdateBody(BaseModel):
    """Body for POST /pos/{id}/status — update PO status."""
    status: str
    notes: str | None = None


class ReturnStatusUpdateBody(BaseModel):
    """Body for POST /returns/{id}/status — update return status."""
    status: str
    tracking_number: str | None = None
    rma_number: str | None = None
    credit_amount: float | None = None
    notes: str | None = None


class VerifyCountsBody(BaseModel):
    """Body for POST /procurement/verify — request spot-check audits."""
    part_ids: list[int]
