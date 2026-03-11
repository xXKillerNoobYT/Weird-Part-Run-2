"""
Tools routes — tool registry, kit templates, checkout/return,
kit verification, maintenance tracking, dashboard.

~25 endpoints covering the full Tools & Kits module (Phase 9).
Permission gates:
  - view_tools      → read tool registry, locations, maintenance status
  - checkout_tools  → check out/return tools, perform kit verification
  - manage_tools    → register/edit/retire tools, manage kit templates,
                      maintenance types, log maintenance services
"""

from __future__ import annotations

import csv
import io
import uuid
from pathlib import Path

import aiosqlite
from fastapi import APIRouter, Body, Depends, File, HTTPException, Query, UploadFile
from fastapi.responses import StreamingResponse

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse
from app.models.tools import (
    # Tools
    ToolCreate,
    ToolUpdate,
    ToolResponse,
    ToolListItem,
    # Kit Templates
    KitTemplateItemCreate,
    KitTemplateItemUpdate,
    KitTemplateItemResponse,
    # Movements
    ToolCheckout,
    ToolReturn,
    ToolTransfer,
    ToolMovementResponse,
    # Kit Verification
    KitVerificationStart,
    KitVerificationComplete,
    KitVerificationSessionResponse,
    # Maintenance
    ToolMaintenanceTypeCreate,
    ToolMaintenanceTypeUpdate,
    ToolMaintenanceTypeResponse,
    ToolMaintenanceScheduleCreate,
    ToolMaintenanceScheduleResponse,
    ToolMaintenanceRecordCreate,
    ToolMaintenanceRecordResponse,
    # Dashboard
    ToolsDashboardStats,
    ToolMaintenanceAlert,
    # Depreciation
    DepreciationConfig,
    DepreciationEntryResponse,
    DepreciationSummary,
    # Todo-Tool linking
    EntryToolLink,
    EntryToolLinkResponse,
)
from app.services.tools_service import ToolsService

router = APIRouter(prefix="/api/tools", tags=["Tools"])


# ═══════════════════════════════════════════════════════════════
# STATIC ROUTES — Must be defined BEFORE /{tool_id}
# ═══════════════════════════════════════════════════════════════


@router.get("/dashboard")
async def dashboard_stats(
    user: dict = Depends(require_permission("view_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Aggregate dashboard stats for all active tools."""
    svc = ToolsService(db)
    stats = await svc.get_dashboard_stats()
    return ApiResponse(data=stats, message="Dashboard stats loaded")


@router.get("/by-location")
async def tools_at_location(
    location_type: str = Query(..., description="warehouse, truck, or job"),
    location_id: int = Query(..., description="ID of the location"),
    user: dict = Depends(require_permission("view_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all active tools at a specific location."""
    svc = ToolsService(db)
    tools = await svc.get_tools_at_location(location_type, location_id)
    return ApiResponse(
        data=tools,
        message=f"Found {len(tools)} tools at {location_type} #{location_id}",
    )


@router.get("/recent-movements")
async def recent_movements(
    limit: int = Query(20, ge=1, le=100),
    user: dict = Depends(require_permission("view_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get most recent tool movements across all tools."""
    svc = ToolsService(db)
    movements = await svc.get_recent_movements(limit=limit)
    return ApiResponse(data=movements, message=f"Loaded {len(movements)} movements")


@router.get("/maintenance-alerts")
async def maintenance_alerts(
    days_ahead: int = Query(14, ge=1, le=90),
    user: dict = Depends(require_permission("view_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get overdue and upcoming maintenance alerts."""
    svc = ToolsService(db)
    alerts = await svc.get_maintenance_alerts(days_ahead=days_ahead)
    return ApiResponse(data=alerts, message="Maintenance alerts loaded")


@router.get("/pending-verifications")
async def pending_verifications(
    user: dict = Depends(require_permission("view_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all incomplete kit verification sessions (auto-triggered but not yet completed)."""
    svc = ToolsService(db)
    pending = await svc.get_pending_verifications()
    return ApiResponse(
        data=pending,
        message=f"{len(pending)} pending verification(s)",
    )


@router.get("/maintenance-types")
async def list_maintenance_types(
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all active tool maintenance types."""
    svc = ToolsService(db)
    types = await svc.list_maintenance_types()
    return ApiResponse(data=types, message=f"Loaded {len(types)} maintenance types")


@router.post("/maintenance-types")
async def create_maintenance_type(
    body: ToolMaintenanceTypeCreate,
    user: dict = Depends(require_permission("manage_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new tool maintenance type."""
    svc = ToolsService(db)
    try:
        result = await svc.create_maintenance_type(body.model_dump())
        return ApiResponse(data=result, message="Maintenance type created")
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))


@router.put("/maintenance-types/{type_id}")
async def update_maintenance_type(
    type_id: int,
    body: ToolMaintenanceTypeUpdate,
    user: dict = Depends(require_permission("manage_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a tool maintenance type."""
    svc = ToolsService(db)
    result = await svc.update_maintenance_type(
        type_id, body.model_dump(exclude_unset=True)
    )
    if not result:
        raise HTTPException(status_code=404, detail="Maintenance type not found")
    return ApiResponse(data=result, message="Maintenance type updated")


@router.delete("/maintenance-types/{type_id}")
async def delete_maintenance_type(
    type_id: int,
    user: dict = Depends(require_permission("manage_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Soft-delete a tool maintenance type (deactivate)."""
    svc = ToolsService(db)
    deleted = await svc.delete_maintenance_type(type_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Maintenance type not found")
    return ApiResponse(data=None, message="Maintenance type deactivated")


@router.get("/scan/{tool_number}")
async def scan_tool(
    tool_number: str,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Look up a tool by its tool_number (QR scan endpoint)."""
    svc = ToolsService(db)
    tool = await svc.get_tool_by_number(tool_number)
    if not tool:
        raise HTTPException(status_code=404, detail=f"Tool '{tool_number}' not found")
    return ApiResponse(data=tool, message=f"Tool {tool_number} found")


# ═══════════════════════════════════════════════════════════════
# DEPRECIATION REPORT (static path — before /{tool_id})
# ═══════════════════════════════════════════════════════════════


@router.get("/depreciation/report")
async def depreciation_report(
    user: dict = Depends(require_permission("manage_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get depreciation summary across all configured tools."""
    svc = ToolsService(db)
    report = await svc.get_depreciation_report()
    return ApiResponse(data=report)


# ═══════════════════════════════════════════════════════════════
# TODO—TOOL LINKING (static paths — before /{tool_id})
# ═══════════════════════════════════════════════════════════════


@router.get("/entry-tools/{entry_id}")
async def get_entry_tools(
    entry_id: int,
    user: dict = Depends(require_permission("view_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all tools linked to a notebook entry."""
    svc = ToolsService(db)
    links = await svc.get_entry_tools(entry_id)
    return ApiResponse(data=links)


@router.post("/entry-tools/{entry_id}")
async def link_tool_to_entry(
    entry_id: int,
    body: EntryToolLink,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Link a tool to a notebook task entry."""
    svc = ToolsService(db)
    try:
        link = await svc.link_tool_to_entry(
            entry_id=entry_id,
            tool_id=body.tool_id,
            notes=body.notes,
            user_id=user["id"],
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        if "UNIQUE constraint" in str(exc):
            raise HTTPException(status_code=409, detail="Tool already linked to this entry")
        raise
    return ApiResponse(data=link, message="Tool linked")


@router.delete("/entry-tools/{entry_id}/{tool_id}")
async def unlink_tool_from_entry(
    entry_id: int,
    tool_id: int,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Remove a tool link from a notebook entry."""
    svc = ToolsService(db)
    removed = await svc.unlink_tool_from_entry(entry_id, tool_id)
    if not removed:
        raise HTTPException(status_code=404, detail="Link not found")
    return ApiResponse(data=None, message="Tool unlinked")


# ═══════════════════════════════════════════════════════════════
# EXPORT CSV (static path — before /{tool_id})
# ═══════════════════════════════════════════════════════════════


@router.get("/export/csv")
async def export_tools_csv(
    category: str | None = Query(None),
    status: str | None = Query(None),
    location_type: str | None = Query(None),
    include_retired: bool = Query(False),
    user: dict = Depends(require_permission("manage_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Export tools as CSV file download."""
    svc = ToolsService(db)
    rows = await svc.export_tools(
        category=category,
        status=status,
        location_type=location_type,
        include_retired=include_retired,
    )

    if not rows:
        raise HTTPException(status_code=404, detail="No tools match the filters")

    # Build CSV in memory
    output = io.StringIO()
    fieldnames = [
        "tool_number", "name", "category", "brand", "model_number",
        "serial_number", "status", "condition_rating", "location_type",
        "location_name", "assigned_to_name", "purchase_date", "purchase_cost",
        "warranty_expiry", "current_book_value", "depreciation_method",
        "calibration_due_date", "notes",
    ]
    writer = csv.DictWriter(output, fieldnames=fieldnames)
    writer.writeheader()
    for row in rows:
        writer.writerow(row)

    output.seek(0)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=tools_export.csv"},
    )


# ═══════════════════════════════════════════════════════════════
# TOOL LIST + CREATE
# ═══════════════════════════════════════════════════════════════


@router.get("/")
async def list_tools(
    category: str | None = Query(None, description="Filter by category"),
    status: str | None = Query(None, description="Filter by status"),
    location_type: str | None = Query(None, description="Filter by location type"),
    search: str | None = Query(None, description="Search name, number, or brand"),
    is_active: bool = Query(True, description="Filter by active status"),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    user: dict = Depends(require_permission("view_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Paginated tool list with filters and joined details."""
    svc = ToolsService(db)
    offset = (page - 1) * page_size
    result = await svc.list_tools(
        category=category,
        status=status,
        location_type=location_type,
        search=search,
        is_active=is_active,
        limit=page_size,
        offset=offset,
    )
    return ApiResponse(
        data=result,
        message=f"Found {result['total']} tools",
    )


@router.post("/")
async def create_tool(
    body: ToolCreate,
    user: dict = Depends(require_permission("manage_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Register a new tool with automatic movement logging."""
    svc = ToolsService(db)
    try:
        tool = await svc.create_tool(body.model_dump(), user["id"])
        return ApiResponse(data=tool, message=f"Tool {body.tool_number} registered")
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))


# ═══════════════════════════════════════════════════════════════
# SINGLE TOOL — GET / UPDATE / DELETE
# ═══════════════════════════════════════════════════════════════


@router.get("/{tool_id}")
async def get_tool(
    tool_id: int,
    user: dict = Depends(require_permission("view_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a single tool with full details."""
    svc = ToolsService(db)
    tool = await svc.get_tool(tool_id)
    if not tool:
        raise HTTPException(status_code=404, detail="Tool not found")
    return ApiResponse(data=tool, message="Tool loaded")


@router.put("/{tool_id}")
async def update_tool(
    tool_id: int,
    body: ToolUpdate,
    user: dict = Depends(require_permission("manage_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update tool fields."""
    svc = ToolsService(db)
    tool = await svc.update_tool(
        tool_id, body.model_dump(exclude_unset=True)
    )
    if not tool:
        raise HTTPException(status_code=404, detail="Tool not found")
    return ApiResponse(data=tool, message="Tool updated")


@router.delete("/{tool_id}")
async def retire_tool(
    tool_id: int,
    user: dict = Depends(require_permission("manage_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Retire (soft-delete) a tool."""
    svc = ToolsService(db)
    tool = await svc.retire_tool(tool_id, user["id"])
    if not tool:
        raise HTTPException(status_code=404, detail="Tool not found")
    return ApiResponse(data=tool, message="Tool retired")


# ═══════════════════════════════════════════════════════════════
# CHECKOUT / RETURN
# ═══════════════════════════════════════════════════════════════


@router.post("/{tool_id}/checkout")
async def checkout_tool(
    tool_id: int,
    body: ToolCheckout,
    user: dict = Depends(require_permission("checkout_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Check out a tool to a truck or job."""
    svc = ToolsService(db)
    try:
        tool = await svc.checkout_tool(tool_id, body.model_dump(), user["id"])
        return ApiResponse(data=tool, message="Tool checked out")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{tool_id}/return")
async def return_tool(
    tool_id: int,
    body: ToolReturn,
    user: dict = Depends(require_permission("checkout_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Return a tool (typically to warehouse)."""
    svc = ToolsService(db)
    try:
        tool = await svc.return_tool(tool_id, body.model_dump(), user["id"])
        return ApiResponse(data=tool, message="Tool returned")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


# ═══════════════════════════════════════════════════════════════
# MOVEMENTS
# ═══════════════════════════════════════════════════════════════


@router.get("/{tool_id}/movements")
async def movement_history(
    tool_id: int,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user: dict = Depends(require_permission("view_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get movement history for a tool."""
    svc = ToolsService(db)
    movements = await svc.get_movement_history(
        tool_id, limit=limit, offset=offset
    )
    return ApiResponse(
        data=movements,
        message=f"Loaded {len(movements)} movements",
    )


# ═══════════════════════════════════════════════════════════════
# KIT TEMPLATES
# ═══════════════════════════════════════════════════════════════


@router.get("/{tool_id}/kit")
async def get_kit(
    tool_id: int,
    user: dict = Depends(require_permission("view_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get kit template (required components) for a tool."""
    svc = ToolsService(db)
    items = await svc.get_kit_template(tool_id)
    return ApiResponse(data=items, message=f"Kit has {len(items)} components")


@router.post("/{tool_id}/kit")
async def add_kit_component(
    tool_id: int,
    body: KitTemplateItemCreate,
    user: dict = Depends(require_permission("manage_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Add a required component to a tool's kit template."""
    svc = ToolsService(db)
    try:
        item = await svc.add_kit_component(tool_id, body.model_dump())
        return ApiResponse(data=item, message="Component added to kit")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.put("/{tool_id}/kit/{item_id}")
async def update_kit_component(
    tool_id: int,
    item_id: int,
    body: KitTemplateItemUpdate,
    user: dict = Depends(require_permission("manage_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a kit template component."""
    svc = ToolsService(db)
    item = await svc.update_kit_component(
        tool_id, item_id, body.model_dump(exclude_unset=True)
    )
    if not item:
        raise HTTPException(status_code=404, detail="Kit component not found")
    return ApiResponse(data=item, message="Component updated")


@router.delete("/{tool_id}/kit/{item_id}")
async def remove_kit_component(
    tool_id: int,
    item_id: int,
    user: dict = Depends(require_permission("manage_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Remove a component from a tool's kit template."""
    svc = ToolsService(db)
    removed = await svc.remove_kit_component(tool_id, item_id)
    if not removed:
        raise HTTPException(status_code=404, detail="Kit component not found")
    return ApiResponse(data=None, message="Component removed from kit")


# ═══════════════════════════════════════════════════════════════
# KIT VERIFICATION
# ═══════════════════════════════════════════════════════════════


@router.post("/{tool_id}/verify")
async def start_verification(
    tool_id: int,
    body: KitVerificationStart,
    user: dict = Depends(require_permission("checkout_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Start a kit verification session (generates checklist from template)."""
    svc = ToolsService(db)
    try:
        session = await svc.start_verification(
            tool_id, body.trigger_type, user["id"]
        )
        return ApiResponse(data=session, message="Verification session started")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.put("/{tool_id}/verify/{session_id}")
async def complete_verification(
    tool_id: int,
    session_id: int,
    body: KitVerificationComplete,
    user: dict = Depends(require_permission("checkout_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Complete a verification session with all item updates."""
    svc = ToolsService(db)
    try:
        session = await svc.complete_verification(
            tool_id,
            session_id,
            [item.model_dump() for item in body.items],
            body.notes,
        )
        return ApiResponse(data=session, message="Verification complete")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/{tool_id}/verify/history")
async def verification_history(
    tool_id: int,
    limit: int = Query(20, ge=1, le=100),
    user: dict = Depends(require_permission("view_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get kit verification history for a tool."""
    svc = ToolsService(db)
    sessions = await svc.get_verification_history(tool_id, limit=limit)
    return ApiResponse(
        data=sessions,
        message=f"Loaded {len(sessions)} verification sessions",
    )


# ═══════════════════════════════════════════════════════════════
# PER-TOOL MAINTENANCE
# ═══════════════════════════════════════════════════════════════


@router.get("/{tool_id}/maintenance/schedule")
async def get_tool_schedule(
    tool_id: int,
    user: dict = Depends(require_permission("view_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get maintenance schedules for a specific tool."""
    svc = ToolsService(db)
    schedules = await svc.get_tool_schedule(tool_id)
    return ApiResponse(
        data=schedules,
        message=f"Loaded {len(schedules)} maintenance schedules",
    )


@router.post("/{tool_id}/maintenance/schedule")
async def set_tool_schedule(
    tool_id: int,
    body: ToolMaintenanceScheduleCreate,
    user: dict = Depends(require_permission("manage_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create or update a maintenance schedule for a tool."""
    svc = ToolsService(db)
    try:
        schedule = await svc.set_tool_schedule(tool_id, body.model_dump())
        return ApiResponse(data=schedule, message="Schedule saved")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{tool_id}/maintenance/log")
async def log_service(
    tool_id: int,
    body: ToolMaintenanceRecordCreate,
    user: dict = Depends(require_permission("manage_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Log a maintenance service. Cascades to update schedule."""
    svc = ToolsService(db)
    try:
        record = await svc.log_service(tool_id, body.model_dump(), user["id"])
        return ApiResponse(data=record, message="Service logged")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/{tool_id}/maintenance/history")
async def service_history(
    tool_id: int,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user: dict = Depends(require_permission("view_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get maintenance service history for a tool."""
    svc = ToolsService(db)
    records = await svc.get_service_history(
        tool_id, limit=limit, offset=offset
    )
    return ApiResponse(
        data=records,
        message=f"Loaded {len(records)} service records",
    )


# ═════════════════════════════════════════════════════════════════
# TOOL PHOTOS
# ═════════════════════════════════════════════════════════════════

UPLOAD_DIR = Path("uploads")


@router.post("/{tool_id}/photo")
async def upload_tool_photo(
    tool_id: int,
    file: UploadFile = File(...),
    user: dict = Depends(require_permission("manage_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Upload or replace a tool's photo."""
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    ext = Path(file.filename or "tool.jpg").suffix or ".jpg"
    unique_name = f"tool_{tool_id}_{uuid.uuid4().hex[:8]}{ext}"
    file_path = UPLOAD_DIR / unique_name

    contents = await file.read()
    file_path.write_bytes(contents)

    await db.execute(
        "UPDATE tools SET photo_path = ? WHERE id = ?",
        (str(file_path), tool_id),
    )
    await db.commit()

    return ApiResponse(
        data={"photo_path": str(file_path)},
        message="Tool photo uploaded",
    )


# ═════════════════════════════════════════════════════════════════
# BULK TOOL OPERATIONS
# ═════════════════════════════════════════════════════════════════


@router.post("/bulk/checkout")
async def bulk_checkout_tools(
    tool_ids: list[int] = Body(..., embed=True),
    location_type: str = Body(..., embed=True),
    location_id: int = Body(..., embed=True),
    notes: str | None = Body(None, embed=True),
    user: dict = Depends(require_permission("checkout_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Check out multiple tools at once to the same location."""
    svc = ToolsService(db)
    results: list[dict] = []
    errors: list[dict] = []

    for tid in tool_ids:
        try:
            movement_id = await svc.checkout_tool(
                tool_id=tid,
                to_location_type=location_type,
                to_location_id=location_id,
                moved_by=user["id"],
                notes=notes,
            )
            results.append({"tool_id": tid, "movement_id": movement_id})
        except Exception as e:
            errors.append({"tool_id": tid, "error": str(e)})

    return ApiResponse(
        data={"checked_out": results, "errors": errors},
        message=f"{len(results)} checked out, {len(errors)} errors",
    )


@router.post("/bulk/return")
async def bulk_return_tools(
    tool_ids: list[int] = Body(..., embed=True),
    notes: str | None = Body(None, embed=True),
    user: dict = Depends(require_permission("checkout_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Return multiple tools at once to the warehouse."""
    svc = ToolsService(db)
    results: list[dict] = []
    errors: list[dict] = []

    for tid in tool_ids:
        try:
            movement_id = await svc.return_tool(
                tool_id=tid,
                moved_by=user["id"],
                notes=notes,
            )
            results.append({"tool_id": tid, "movement_id": movement_id})
        except Exception as e:
            errors.append({"tool_id": tid, "error": str(e)})

    return ApiResponse(
        data={"returned": results, "errors": errors},
        message=f"{len(results)} returned, {len(errors)} errors",
    )


@router.post("/bulk/maintenance")
async def bulk_log_maintenance(
    tool_ids: list[int] = Body(..., embed=True),
    maintenance_type_id: int = Body(..., embed=True),
    notes: str | None = Body(None, embed=True),
    user: dict = Depends(require_permission("manage_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Log a maintenance service for multiple tools at once."""
    svc = ToolsService(db)
    results: list[dict] = []
    errors: list[dict] = []

    for tid in tool_ids:
        try:
            record_id = await svc.log_maintenance(
                tool_id=tid,
                maintenance_type_id=maintenance_type_id,
                performed_by=user["id"],
                notes=notes,
            )
            results.append({"tool_id": tid, "record_id": record_id})
        except Exception as e:
            errors.append({"tool_id": tid, "error": str(e)})

    return ApiResponse(
        data={"serviced": results, "errors": errors},
        message=f"{len(results)} serviced, {len(errors)} errors",
    )


# ═════════════════════════════════════════════════════════════════
# TOOL TRANSFER — Atomic location-to-location
# ═════════════════════════════════════════════════════════════════


@router.post("/{tool_id}/transfer")
async def transfer_tool(
    tool_id: int,
    body: ToolTransfer,
    user: dict = Depends(require_permission("checkout_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Transfer a tool directly between locations (atomic)."""
    svc = ToolsService(db)
    try:
        movement_id = await svc.transfer_tool(
            tool_id=tool_id,
            to_location_type=body.to_location_type,
            to_location_id=body.to_location_id,
            moved_by=user["id"],
            job_id=body.job_id,
            condition_at_move=body.condition_at_move,
            reason=body.reason,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    tool = await svc.get_tool(tool_id)
    return ApiResponse(
        data={**tool, "movement_id": movement_id},
        message="Tool transferred",
    )


@router.get("/{tool_id}/depreciation")
async def get_depreciation(
    tool_id: int,
    user: dict = Depends(require_permission("view_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get full depreciation summary for a tool."""
    svc = ToolsService(db)
    try:
        summary = await svc.get_depreciation_summary(tool_id)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    return ApiResponse(data=summary)


@router.post("/{tool_id}/depreciation")
async def configure_depreciation(
    tool_id: int,
    body: DepreciationConfig,
    user: dict = Depends(require_permission("manage_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Configure depreciation for a tool and generate schedule."""
    svc = ToolsService(db)
    try:
        result = await svc.configure_depreciation(
            tool_id=tool_id,
            method=body.depreciation_method,
            salvage_value=body.salvage_value,
            useful_life_years=body.useful_life_years,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return ApiResponse(data=result, message="Depreciation configured")


# ═════════════════════════════════════════════════════════════════
# CALIBRATION (enhanced maintenance logging)
# ═════════════════════════════════════════════════════════════════


@router.post("/{tool_id}/calibration")
async def log_calibration(
    tool_id: int,
    service_date: str | None = Body(None, embed=True),
    cost: float = Body(0, embed=True),
    vendor: str | None = Body(None, embed=True),
    description: str | None = Body(None, embed=True),
    notes: str | None = Body(None, embed=True),
    calibration_certificate: str | None = Body(None, embed=True),
    calibration_provider: str | None = Body(None, embed=True),
    calibration_standard: str | None = Body(None, embed=True),
    calibration_result: str | None = Body(None, embed=True),
    user: dict = Depends(require_permission("manage_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Log a calibration with certificate details."""
    svc = ToolsService(db)
    try:
        record_id = await svc.log_calibration(
            tool_id=tool_id,
            performed_by=user["id"],
            service_date=service_date,
            cost=cost,
            vendor=vendor,
            description=description,
            notes=notes,
            calibration_certificate=calibration_certificate,
            calibration_provider=calibration_provider,
            calibration_standard=calibration_standard,
            calibration_result=calibration_result,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return ApiResponse(
        data={"record_id": record_id},
        message="Calibration logged",
    )


@router.get("/{tool_id}/references")
async def get_tool_references(
    tool_id: int,
    user: dict = Depends(require_permission("view_tools")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all notebook entries that reference a specific tool."""
    svc = ToolsService(db)
    refs = await svc.get_tools_referencing(tool_id)
    return ApiResponse(data=refs)
