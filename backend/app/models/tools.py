"""
Tools & Kits Pydantic models.

Covers all request/response schemas for Phase 9: Tools & Kits.
Organized into sections: Tools, Kit Templates, Movements,
Kit Verification, Maintenance, and Dashboard stats.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


# =================================================================
# TYPE ALIASES
# =================================================================

ToolCategory = Literal[
    "power_tool", "hand_tool", "meter", "safety",
    "conduit", "cable", "lighting", "general",
]

ToolStatus = Literal[
    "available", "checked_out", "in_maintenance",
    "lost", "retired", "damaged",
]

ToolLocationType = Literal["warehouse", "truck", "job"]

KitComponentType = Literal[
    "charger", "battery", "blade", "bit_set",
    "case", "accessory", "cable", "adapter", "other",
]

ToolMovementType = Literal[
    "register", "checkout", "return", "transfer",
    "maintenance_in", "maintenance_out", "retire", "lost",
]

KitVerificationTrigger = Literal["checkout", "return", "audit", "manual"]


# =================================================================
# TOOLS — Core entity
# =================================================================

class ToolCreate(BaseModel):
    """Request body for registering a new tool."""
    tool_number: str = Field(..., min_length=1, max_length=30)
    name: str = Field(..., min_length=1, max_length=200)
    category: ToolCategory = "general"
    brand: str | None = None
    model_number: str | None = None
    serial_number: str | None = None
    purchase_date: str | None = None
    purchase_cost: float | None = None
    warranty_expiry: str | None = None
    location_type: ToolLocationType = "warehouse"
    location_id: int | None = None
    assigned_to: int | None = None
    condition_rating: int = Field(5, ge=1, le=5)
    notes: str | None = None
    photo_path: str | None = None


class ToolUpdate(BaseModel):
    """Request body for updating a tool. All fields optional."""
    name: str | None = Field(None, min_length=1, max_length=200)
    category: ToolCategory | None = None
    brand: str | None = None
    model_number: str | None = None
    serial_number: str | None = None
    purchase_date: str | None = None
    purchase_cost: float | None = None
    warranty_expiry: str | None = None
    condition_rating: int | None = Field(None, ge=1, le=5)
    notes: str | None = None
    photo_path: str | None = None
    is_active: bool | None = None


class ToolResponse(BaseModel):
    """A tool as returned from the API. Includes joined fields."""
    id: int
    tool_number: str
    name: str
    category: ToolCategory
    brand: str | None = None
    model_number: str | None = None
    serial_number: str | None = None
    purchase_date: str | None = None
    purchase_cost: float | None = None
    warranty_expiry: str | None = None
    location_type: ToolLocationType
    location_id: int | None = None
    assigned_to: int | None = None
    status: ToolStatus
    condition_rating: int = 5
    has_kit: bool = False
    notes: str | None = None
    photo_path: str | None = None
    barcode: str | None = None
    is_active: bool = True
    created_at: datetime | None = None
    updated_at: datetime | None = None

    # Joined / computed fields
    assigned_to_name: str | None = None
    location_name: str | None = None
    kit_component_count: int = 0
    next_maintenance_due: str | None = None
    overdue_maintenance_count: int = 0


class ToolListItem(BaseModel):
    """Compact tool summary for list views."""
    id: int
    tool_number: str
    name: str
    category: ToolCategory
    brand: str | None = None
    status: ToolStatus
    location_type: ToolLocationType
    location_id: int | None = None
    location_name: str | None = None
    assigned_to: int | None = None
    assigned_to_name: str | None = None
    condition_rating: int = 5
    has_kit: bool = False
    kit_component_count: int = 0
    next_maintenance_due: str | None = None
    overdue_maintenance_count: int = 0


# =================================================================
# KIT TEMPLATES — Required components per tool
# =================================================================

class KitTemplateItemCreate(BaseModel):
    """Add a required component to a tool's kit."""
    component_name: str = Field(..., min_length=1, max_length=200)
    component_type: KitComponentType = "accessory"
    qty_required: int = Field(1, ge=1)
    brand: str | None = None
    model_number: str | None = None
    is_critical: bool = False
    sort_order: int = 0
    notes: str | None = None


class KitTemplateItemUpdate(BaseModel):
    """Update a kit template component."""
    component_name: str | None = Field(None, min_length=1, max_length=200)
    component_type: KitComponentType | None = None
    qty_required: int | None = Field(None, ge=1)
    brand: str | None = None
    model_number: str | None = None
    is_critical: bool | None = None
    sort_order: int | None = None
    notes: str | None = None


class KitTemplateItemResponse(BaseModel):
    """A kit template item as returned from the API."""
    id: int
    tool_id: int
    component_name: str
    component_type: KitComponentType
    qty_required: int = 1
    brand: str | None = None
    model_number: str | None = None
    is_critical: bool = False
    sort_order: int = 0
    notes: str | None = None


# =================================================================
# TOOL MOVEMENTS — Checkout / Return / Transfer
# =================================================================

class ToolCheckout(BaseModel):
    """Checkout a tool from warehouse to a truck or job."""
    to_location_type: ToolLocationType
    to_location_id: int
    job_id: int | None = None
    condition_at_move: int | None = Field(None, ge=1, le=5)
    reason: str | None = None


class ToolReturn(BaseModel):
    """Return a tool to the warehouse."""
    to_location_type: ToolLocationType = "warehouse"
    to_location_id: int | None = None
    condition_at_move: int | None = Field(None, ge=1, le=5)
    reason: str | None = None


class ToolMovementResponse(BaseModel):
    """A tool movement entry from the audit log."""
    id: int
    tool_id: int
    from_location_type: str | None = None
    from_location_id: int | None = None
    to_location_type: str | None = None
    to_location_id: int | None = None
    movement_type: ToolMovementType
    reason: str | None = None
    job_id: int | None = None
    performed_by: int
    verified_by: int | None = None
    condition_at_move: int | None = None
    created_at: datetime | None = None

    # Joined fields
    performed_by_name: str | None = None
    verified_by_name: str | None = None
    from_location_name: str | None = None
    to_location_name: str | None = None
    tool_name: str | None = None
    tool_number: str | None = None


# =================================================================
# KIT VERIFICATION — Checkout/return checklists
# =================================================================

class KitVerificationStart(BaseModel):
    """Start a kit verification session."""
    trigger_type: KitVerificationTrigger


class KitVerificationItemUpdate(BaseModel):
    """Update a single checklist item within a session."""
    item_id: int
    is_present: bool
    condition_rating: int | None = Field(None, ge=1, le=5)
    notes: str | None = None


class KitVerificationComplete(BaseModel):
    """Complete a verification session with all item updates."""
    items: list[KitVerificationItemUpdate]
    notes: str | None = None


class KitVerificationItemResponse(BaseModel):
    """A single verification checklist item."""
    id: int
    session_id: int
    template_item_id: int
    is_present: bool = False
    condition_rating: int | None = None
    notes: str | None = None

    # Joined from kit_templates
    component_name: str | None = None
    component_type: KitComponentType | None = None
    qty_required: int = 1
    is_critical: bool = False


class KitVerificationSessionResponse(BaseModel):
    """A verification session with its items."""
    id: int
    tool_id: int
    movement_id: int | None = None
    verified_by: int
    trigger_type: KitVerificationTrigger
    is_complete: bool = False
    missing_count: int = 0
    notes: str | None = None
    created_at: datetime | None = None

    # Joined
    verified_by_name: str | None = None
    tool_name: str | None = None
    tool_number: str | None = None
    items: list[KitVerificationItemResponse] = []


# =================================================================
# TOOL MAINTENANCE
# =================================================================

class ToolMaintenanceTypeCreate(BaseModel):
    """Create a new tool maintenance type."""
    name: str = Field(..., min_length=1, max_length=100)
    description: str | None = None
    default_interval_days: int | None = None
    sort_order: int = 0


class ToolMaintenanceTypeUpdate(BaseModel):
    """Update a tool maintenance type."""
    name: str | None = Field(None, min_length=1, max_length=100)
    description: str | None = None
    default_interval_days: int | None = None
    sort_order: int | None = None
    is_active: bool | None = None


class ToolMaintenanceTypeResponse(BaseModel):
    """A tool maintenance type."""
    id: int
    name: str
    description: str | None = None
    default_interval_days: int | None = None
    sort_order: int = 0
    is_active: bool = True
    created_at: datetime | None = None


class ToolMaintenanceScheduleCreate(BaseModel):
    """Set a maintenance schedule for a tool."""
    maintenance_type_id: int
    interval_days: int | None = None
    is_enabled: bool = True
    notes: str | None = None


class ToolMaintenanceScheduleResponse(BaseModel):
    """A per-tool maintenance schedule entry."""
    id: int
    tool_id: int
    maintenance_type_id: int
    interval_days: int | None = None
    last_performed_at: str | None = None
    next_due_date: str | None = None
    is_enabled: bool = True
    notes: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None

    # Joined
    maintenance_type_name: str | None = None


class ToolMaintenanceRecordCreate(BaseModel):
    """Log a maintenance service performed on a tool."""
    maintenance_type_id: int
    service_date: str | None = None
    cost: float = 0
    vendor: str | None = None
    description: str | None = None
    notes: str | None = None


class ToolMaintenanceRecordResponse(BaseModel):
    """A service history entry for a tool."""
    id: int
    tool_id: int
    maintenance_type_id: int
    service_date: str
    cost: float = 0
    vendor: str | None = None
    description: str | None = None
    performed_by: int | None = None
    notes: str | None = None
    created_at: datetime | None = None

    # Joined
    maintenance_type_name: str | None = None
    performed_by_name: str | None = None


# =================================================================
# DASHBOARD / ALERTS
# =================================================================

class ToolsDashboardStats(BaseModel):
    """Aggregate stats for the tools dashboard."""
    total_tools: int = 0
    available: int = 0
    checked_out: int = 0
    in_maintenance: int = 0
    lost_or_damaged: int = 0
    at_warehouse: int = 0
    on_trucks: int = 0
    at_jobs: int = 0
    overdue_maintenance: int = 0
    kits_with_missing_items: int = 0


class ToolMaintenanceAlert(BaseModel):
    """A single maintenance alert (overdue or upcoming)."""
    tool_id: int
    tool_number: str
    tool_name: str
    maintenance_type_id: int
    maintenance_type_name: str
    next_due_date: str | None = None
    days_until_due: int | None = None
    is_overdue: bool = False
