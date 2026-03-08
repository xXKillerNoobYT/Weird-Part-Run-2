"""
Pydantic models for the Orders & Procurement system.

Covers:
  - Job Parts Orders (JPO) — field-worker requests (job + warehouse restock)
  - Purchase Orders (PO) — supplier-facing orders
  - PO Line Items — individual items on a PO
  - Returns — job-to-warehouse and warehouse-to-supplier
  - Staging Zones — physical QR-coded staging areas
  - Order Status History — audit trail
  - Price History — supplier pricing over time
  - Supplier Contact Ratings — communication scoring
  - Job Preferences — smart suggestion memory per job (Phase 7A)
  - Special Items — non-catalog items on an order (Phase 7A)
  - PO Conversations — CRM-style conversation threads per PO (Phase 7B)
  - PO Groups — bundle multiple POs for combined sending (Phase 7B)
  - Approval Queue — unified pending approvals for office (Phase 7B)
  - Confirmation Checklist — per-line confirmation tracking (Phase 7B)
  - Receiving Sessions — session-based receiving workflow (Phase 7C)
  - Return Sorting — eligibility checking and sorting guidance (Phase 7C)
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


class SpecialItemCreate(BaseModel):
    """A non-catalog item to include in an order."""
    description: str = Field(..., min_length=1)
    part_number: str | None = None  # optional manufacturer part number
    quantity: int = Field(1, ge=1)
    unit: str = "each"
    estimated_cost: float | None = None
    notes: str | None = None


class JPOCreate(BaseModel):
    """Create a new Job Parts Order (job order or warehouse restock).

    For job orders:  job_id is required, order_type defaults to 'job'.
    For restocks:    job_id is None, order_type must be 'warehouse'.
    """
    job_id: int | None = None  # NULL for warehouse restocks
    order_type: str = "job"  # 'job' | 'warehouse'
    priority: str = "normal"  # normal | urgent
    smart_suggestions_enabled: bool = True
    notes: str | None = None
    lines: list[JPOLineCreate] = Field(default_factory=list)
    special_items: list[SpecialItemCreate] = Field(default_factory=list)


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
    # Hierarchy fields
    part_name: str | None = None
    category_name: str | None = None
    type_name: str | None = None
    color_name: str | None = None
    color_hex: str | None = None
    brand_name: str | None = None


class JPOResponse(BaseModel):
    """JPO in API responses."""
    id: int
    job_id: int | None = None  # NULL for warehouse restocks
    order_number: str
    status: str
    priority: str = "normal"
    order_type: str = "job"
    has_special_items: bool = False
    smart_suggestions_enabled: bool = True
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
    special_items: list[Any] | None = None  # populated on detail view


class JPOListItem(BaseModel):
    """Compact JPO for list views."""
    id: int
    job_id: int | None = None
    order_number: str
    status: str
    priority: str = "normal"
    order_type: str = "job"
    has_special_items: bool = False
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
    # Hierarchy fields
    part_name: str | None = None
    category_name: str | None = None
    type_name: str | None = None
    color_name: str | None = None
    color_hex: str | None = None
    brand_name: str | None = None


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
    # Hierarchy fields
    part_name: str | None = None
    category_name: str | None = None
    type_name: str | None = None
    color_name: str | None = None
    color_hex: str | None = None
    brand_name: str | None = None


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
    # Hierarchy fields
    part_name: str | None = None
    category_name: str | None = None
    type_name: str | None = None
    color_name: str | None = None
    color_hex: str | None = None
    brand_name: str | None = None


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


# ═══════════════════════════════════════════════════════════════
# Job Preferences Models (Phase 7A)
# ═══════════════════════════════════════════════════════════════

class JobPreferenceResponse(BaseModel):
    """A single learned preference for a job."""
    id: int
    job_id: int
    preference_type: str  # brand | color | supplier | part
    entity_id: int | None = None
    text_value: str | None = None
    category: str | None = None
    is_active: bool = True
    auto_learned: bool = True
    confidence_score: float = 0.5
    last_used_at: str | None = None
    created_at: datetime | None = None
    # Joined fields
    entity_name: str | None = None
    hex_code: str | None = None  # for color preferences
    category_name: str | None = None


class JobPreferenceToggle(BaseModel):
    """Toggle a preference on or off."""
    is_active: bool


class JobPreferencesSummary(BaseModel):
    """Grouped preferences for the unified order form filter chips."""
    brands: list[dict] = Field(default_factory=list)
    colors: list[dict] = Field(default_factory=list)
    suppliers: list[dict] = Field(default_factory=list)
    parts: list[dict] = Field(default_factory=list)


# ═══════════════════════════════════════════════════════════════
# Special Item Models (Phase 7A)
# ═══════════════════════════════════════════════════════════════

class SpecialItemResponse(BaseModel):
    """A non-catalog special item on an order."""
    id: int
    jpo_id: int
    description: str
    part_number: str | None = None
    quantity: int = 1
    unit: str = "each"
    estimated_cost: float | None = None
    notes: str | None = None
    is_flagged: bool = True
    flag_resolved_by: int | None = None
    flag_resolved_at: datetime | None = None
    linked_part_id: int | None = None
    created_at: datetime | None = None
    # Joined fields
    resolver_name: str | None = None
    linked_part_description: str | None = None


class SpecialItemResolve(BaseModel):
    """Office resolves a flagged special item."""
    linked_part_id: int | None = None  # optional match to catalog part


class SpecialItemPlaceInCatalog(BaseModel):
    """Place a special item into the parts catalog hierarchy.

    Creates a new part at the specified position in the hierarchy
    (type + brand + color), then resolves the special item linked
    to the newly created part.
    """
    type_id: int
    brand_id: int | None = None       # None = General (unbranded)
    color_id: int
    manufacturer_part_number: str | None = None  # pre-filled from special item


# ═══════════════════════════════════════════════════════════════
# PO Conversation Models (Phase 7B)
# ═══════════════════════════════════════════════════════════════

class POConversationCreate(BaseModel):
    """Add a manual entry to a PO's conversation thread.

    entry_type controls the visual treatment in the UI:
      - 'note':          general notes (blue)
      - 'call':          phone call log (green)
      - 'email_summary': email summary (purple)
      - 'action':        action item (amber)
    System entries are auto-generated and use a separate code path.
    """
    entry_type: str = Field(
        ...,
        pattern="^(note|call|email_summary|action)$",
    )
    message: str = Field(..., min_length=1)
    follow_up_needed: bool = False


class POConversationResponse(BaseModel):
    """A single conversation entry in API responses."""
    id: int
    po_id: int | None = None
    supplier_id: int | None = None
    entry_type: str
    message: str
    follow_up_needed: bool = False
    follow_up_resolved_at: datetime | None = None
    created_by: int | None = None
    created_at: datetime | None = None
    # Joined fields
    creator_name: str | None = None
    po_number: str | None = None  # included when viewing supplier-level thread


class POConversationFollowUp(BaseModel):
    """Toggle the follow-up status on a conversation entry."""
    resolved: bool


# ═══════════════════════════════════════════════════════════════
# PO Group Models (Phase 7B)
# ═══════════════════════════════════════════════════════════════

class POGroupCreate(BaseModel):
    """Create a PO group for bundled sending to a supplier.

    Groups allow generating a single combined PDF (or individual PDFs
    packaged together) for multiple POs going to the same supplier.
    """
    group_name: str | None = None  # auto-generated if not provided
    supplier_id: int
    po_ids: list[int] = Field(..., min_length=1)


class POGroupMemberResponse(BaseModel):
    """A PO that is part of a group — includes compact PO info."""
    id: int  # po_group_members.id
    group_id: int
    po_id: int
    po_number: str | None = None
    status: str | None = None
    total_cost: float = 0
    line_count: int = 0


class POGroupResponse(BaseModel):
    """PO group in API responses."""
    id: int
    group_name: str | None = None
    supplier_id: int
    supplier_name: str | None = None
    pdf_path: str | None = None
    individual_pdfs: list[str] | None = None  # deserialized from JSON
    created_by: int | None = None
    creator_name: str | None = None
    created_at: datetime | None = None
    members: list[POGroupMemberResponse] = Field(default_factory=list)
    total_value: float = 0  # sum of all member POs


class POGroupListItem(BaseModel):
    """Compact PO group for list views."""
    id: int
    group_name: str | None = None
    supplier_id: int
    supplier_name: str | None = None
    po_count: int = 0
    total_value: float = 0
    has_pdf: bool = False
    created_at: datetime | None = None


# ═══════════════════════════════════════════════════════════════
# Approval Queue Models (Phase 7B)
# ═══════════════════════════════════════════════════════════════

class PendingApprovalItem(BaseModel):
    """A unified approval queue item — covers both JPOs and Returns.

    This is a view model: it doesn't map to a single table but merges
    data from job_parts_orders and returns for the Office approvals tab.
    The `entity_type` field tells the frontend which detail page to link to.
    """
    entity_type: str  # 'jpo' | 'return'
    entity_id: int
    reference_number: str  # JPO order_number or Return return_number
    status: str  # pending_approval (always, by definition)
    priority: str = "normal"
    order_type: str | None = None  # 'job' | 'warehouse' (JPO only)
    return_type: str | None = None  # 'job_to_warehouse' | 'warehouse_to_supplier' (Return only)
    reason: str | None = None  # Return reason
    has_special_items: bool = False  # JPO only
    requester_id: int
    requester_name: str | None = None
    job_id: int | None = None
    job_name: str | None = None
    supplier_name: str | None = None  # Return only
    line_count: int = 0
    created_at: datetime | None = None


class BulkApprovalTarget(BaseModel):
    """A single target in a bulk approval action."""
    entity_type: str = Field(..., pattern="^(jpo|return)$")
    entity_id: int


class BulkApprovalAction(BaseModel):
    """Approve or reject multiple items at once from the Office approvals tab.

    Each item is identified by (entity_type, entity_id) so that the
    backend can route to the correct service (JPO or Returns).
    """
    items: list[BulkApprovalTarget] = Field(..., min_length=1)
    action: str = Field(..., pattern="^(approve|reject)$")
    notes: str | None = None


# ═══════════════════════════════════════════════════════════════
# Bulk PO Actions (Phase 7E)
# ═══════════════════════════════════════════════════════════════

class BulkPOSubmit(BaseModel):
    """Submit multiple draft POs to suppliers at once."""
    po_ids: list[int] = Field(..., min_length=1)
    notes: str | None = None


class BulkPOStatusUpdate(BaseModel):
    """Update status on multiple POs at once."""
    po_ids: list[int] = Field(..., min_length=1)
    status: str = Field(..., pattern="^(submitted|confirmed|shipped|delivered|cancelled)$")
    notes: str | None = None


class BulkReturnApprove(BaseModel):
    """Approve multiple pending returns at once."""
    return_ids: list[int] = Field(..., min_length=1)
    notes: str | None = None


# ═══════════════════════════════════════════════════════════════
# Confirmation Checklist Models (Phase 7B)
# ═══════════════════════════════════════════════════════════════

class ConfirmationChecklistItem(BaseModel):
    """A single line in the PO confirmation checklist.

    Office staff check off each line item as they confirm it has been
    ordered correctly with the supplier. Stored as JSON array in the
    purchase_orders.confirmation_checklist column.
    """
    po_line_id: int
    part_id: int
    confirmed: bool = False
    confirmed_by: int | None = None
    confirmed_at: str | None = None  # ISO datetime string
    # Joined (only populated in response, not stored in JSON)
    part_description: str | None = None
    confirmer_name: str | None = None
    # Hierarchy fields
    part_number: str | None = None
    part_name: str | None = None
    category_name: str | None = None
    type_name: str | None = None
    color_name: str | None = None
    color_hex: str | None = None
    brand_name: str | None = None


class ConfirmationChecklistUpdate(BaseModel):
    """Update the confirmation checklist for a PO.

    Accepts a full checklist (all items, including unchanged ones).
    The service layer diffs against existing state to find changes.
    """
    checklist: list[ConfirmationChecklistItem] = Field(..., min_length=1)


# ═══════════════════════════════════════════════════════════════
# Receiving Session Models (Phase 7C)
# ═══════════════════════════════════════════════════════════════

class ReceivingSessionCreate(BaseModel):
    """Start a new receiving session for a PO.

    Mode determines the UI experience:
      - 'packing_slip': show all expected lines, user enters qty per line
      - 'scan':         QR scanner active, user scans parts and enters qty
    """
    po_id: int
    mode: str = Field("packing_slip", pattern="^(packing_slip|scan)$")
    notes: str | None = None


class ReceivingSessionItemUpdate(BaseModel):
    """Update a single line in a receiving session.

    The frontend sends incremental updates as the user fills in quantities.
    `received_qty` is the TOTAL quantity for this line (not a delta).
    """
    po_line_id: int
    received_qty: int = Field(0, ge=0)
    actual_cost: float | None = None  # if different from PO price
    staging_zone_id: int | None = None
    notes: str | None = None


class ReceivingSessionCommit(BaseModel):
    """Commit a receiving session — applies all received quantities to the PO.

    The `items` array should contain only lines with received_qty > 0.
    On commit the service:
      1. Updates PO line received quantities
      2. Creates stock movements
      3. Updates PO status (partially_received / received)
      4. Marks session as completed
    """
    items: list[ReceivingSessionItemUpdate] = Field(default_factory=list)
    notes: str | None = None


class ReceivingSessionItemResponse(BaseModel):
    """A single line in a receiving session (API response)."""
    id: int
    session_id: int
    po_line_id: int
    expected_qty: int = 0
    received_qty: int = 0
    actual_cost: float | None = None
    staging_zone_id: int | None = None
    scanned_at: datetime | None = None
    notes: str | None = None
    created_at: datetime | None = None
    # Joined fields
    part_id: int | None = None
    part_number: str | None = None
    part_description: str | None = None
    unit_cost: float | None = None  # from PO line
    zone_label: str | None = None
    # Hierarchy fields
    part_name: str | None = None
    category_name: str | None = None
    type_name: str | None = None
    color_name: str | None = None
    color_hex: str | None = None
    brand_name: str | None = None


class ReceivingSessionResponse(BaseModel):
    """Receiving session in API responses."""
    id: int
    po_id: int
    po_number: str | None = None
    supplier_name: str | None = None
    started_by: int
    starter_name: str | None = None
    mode: str = "packing_slip"
    status: str = "in_progress"
    completed_at: datetime | None = None
    notes: str | None = None
    created_at: datetime | None = None
    items: list[ReceivingSessionItemResponse] = Field(default_factory=list)
    # Progress summary
    total_expected: int = 0
    total_received: int = 0
    line_count: int = 0


class ReceivingSessionListItem(BaseModel):
    """Compact session for list views."""
    id: int
    po_id: int
    po_number: str | None = None
    supplier_name: str | None = None
    mode: str = "packing_slip"
    status: str = "in_progress"
    total_expected: int = 0
    total_received: int = 0
    started_by: int
    starter_name: str | None = None
    created_at: datetime | None = None
    completed_at: datetime | None = None


# ═══════════════════════════════════════════════════════════════
# Return Sorting Models (Phase 7C)
# ═══════════════════════════════════════════════════════════════

class ReturnSortingGuidance(BaseModel):
    """Sorting guidance for a single return line item.

    The service analyzes each line's condition, supplier return eligibility,
    and current stock levels to produce a recommendation:
      - 'return_to_supplier':  good condition, within return window
      - 'restock':             usable but not returnable (or below target)
      - 'write_off':           damaged/defective beyond use
    """
    return_line_id: int
    part_id: int
    part_number: str | None = None
    part_description: str | None = None
    qty: int = 1
    condition: str = "new"
    current_stock: int = 0
    target_qty: int = 0
    below_target: bool = False
    returnable_to_supplier: bool = True
    non_return_reason: str | None = None
    recommended_disposition: str  # return_to_supplier | restock | write_off
    recommendation_reason: str  # human-readable explanation


class ReturnSortingDisposition(BaseModel):
    """Apply a sorting disposition to a return line item.

    The warehouse worker confirms or overrides the recommendation.
    """
    return_line_id: int
    disposition: str = Field(..., pattern="^(return_to_supplier|restock|write_off)$")
    dest_type: str | None = None  # warehouse | truck (for restock)
    dest_id: int | None = None    # staging_zone_id or location_id
    notes: str | None = None


class ReturnSortingRequest(BaseModel):
    """Process sorting dispositions for all lines in a return."""
    dispositions: list[ReturnSortingDisposition] = Field(..., min_length=1)


class ReturnEligibilityCheck(BaseModel):
    """Response for checking a part's return eligibility to supplier."""
    part_id: int
    returnable: bool = True
    reasons: list[str] = Field(default_factory=list)  # why not returnable
    supplier_return_window_days: int | None = None  # if known
    days_since_receipt: int | None = None
