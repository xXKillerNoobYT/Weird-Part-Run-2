"""
Trucks routes — vehicles, assignments, inventory, deliveries, maintenance,
mileage, reimbursements, warehouse locations, and fleet dashboard.

~35 endpoints covering the full fleet management lifecycle.

IMPORTANT: Route ordering matters! The /{vehicle_id} catch-all routes
MUST be registered LAST, after all named paths like /maintenance-types,
/warehouse-locations, /reimbursements, and /fleet/*. Otherwise FastAPI
will match those names as vehicle_id and return 422 validation errors.
"""

from __future__ import annotations

import logging
import uuid
from pathlib import Path
from typing import Any

import aiosqlite
from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse, PaginatedData
from app.models.vehicles import (
    DeliveryItemBulkCreate,
    DeliveryItemResponse,
    DeliveryItemUpdate,
    FleetDashboardStats,
    FuelLogCreate,
    FuelLogResponse,
    FuelLogUpdate,
    FuelSummary,
    InspectionRecordCreate,
    InspectionRecordResponse,
    InspectionTemplateCreate,
    InspectionTemplateResponse,
    InspectionTemplateUpdate,
    InspectionItemSubmit,
    JobTrailerCreate,
    JobTrailerResponse,
    JobTrailerUpdate,
    MaintenanceAlert,
    MaintenanceRecordCreate,
    MaintenanceRecordResponse,
    MaintenanceScheduleCreate,
    MaintenanceScheduleResponse,
    MaintenanceTypeCreate,
    MaintenanceTypeResponse,
    MileageEstimate,
    MileageLogCreate,
    MileageLogResponse,
    MileageLogUpdate,
    MileageSummary,
    MyVehicleDashboard,
    ReimbursementApproval,
    ReimbursementCreate,
    ReimbursementResponse,
    TelematicsDeviceCreate,
    TelematicsDeviceResponse,
    TelematicsPositionIngest,
    TelematicsPositionResponse,
    TelematicsEventIngest,
    TelematicsEventResponse,
    TripLegBulkCreate,
    TripLegResponse,
    TrailerLocationEventCreate,
    TrailerLocationEventResponse,
    VehicleAssignmentCreate,
    VehicleAssignmentResponse,
    VehicleCreate,
    VehicleDocumentAlert,
    VehicleListItem,
    VehicleLocationSummary,
    VehicleResponse,
    VehicleTransferCreate,
    VehicleTransferResponse,
    VehicleUpdate,
    VehicleUtilizationReport,
    WarehouseLocationCreate,
    WarehouseLocationResponse,
    WarehouseLocationUpdate,
)
from app.services.delivery_service import DeliveryService
from app.services.fuel_service import FuelService
from app.services.inspection_service import InspectionService
from app.services.maintenance_service import MaintenanceService
from app.services.mileage_service import MileageService
from app.services.telematics_service import TelematicsService
from app.services.vehicle_service import VehicleService

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/trucks", tags=["Trucks"], redirect_slashes=False)

UPLOAD_DIR = Path("uploads/vehicles")


# ═══════════════════════════════════════════════════════════════════════
# VEHICLE CRUD
# ═══════════════════════════════════════════════════════════════════════

@router.get("", response_model=ApiResponse[PaginatedData[VehicleListItem]])
async def list_vehicles(
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    vehicle_type: str | None = None,
    vehicle_status: str | None = None,
    driver_id: int | None = None,
    search: str | None = None,
    is_active: bool | None = True,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all vehicles with optional filters."""
    svc = VehicleService(db)
    offset = (page - 1) * page_size

    items = await svc.vehicle_repo.list_with_details(
        vehicle_type=vehicle_type,
        status=vehicle_status,
        driver_id=driver_id,
        search=search,
        is_active=is_active,
        limit=page_size,
        offset=offset,
    )
    total = await svc.vehicle_repo.count_filtered(
        vehicle_type=vehicle_type,
        status=vehicle_status,
        driver_id=driver_id,
        search=search,
        is_active=is_active,
    )

    return ApiResponse(data=PaginatedData(
        items=[dict(v) for v in items],
        total=total,
        page=page,
        page_size=page_size,
        total_pages=(total + page_size - 1) // page_size,
    ))


@router.post("", response_model=ApiResponse[VehicleResponse], status_code=201)
async def create_vehicle(
    body: VehicleCreate,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new vehicle."""
    svc = VehicleService(db)
    try:
        vehicle = await svc.create_vehicle(body.model_dump())
        # Auto-initialize maintenance schedules for the new vehicle
        maint_svc = MaintenanceService(db)
        await maint_svc.init_schedules_for_vehicle(vehicle["id"])
        return ApiResponse(data=vehicle, message="Vehicle created")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


# ═══════════════════════════════════════════════════════════════════════
# JOB TRAILERS
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/trailers",
    response_model=ApiResponse[list[JobTrailerResponse]],
)
async def list_trailers(
    search: str | None = None,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List active job trailers."""
    svc = VehicleService(db)
    trailers = await svc.list_trailers(search=search)
    return ApiResponse(data=[dict(t) for t in trailers])


@router.post(
    "/trailers",
    response_model=ApiResponse[JobTrailerResponse],
    status_code=201,
)
async def create_trailer(
    body: JobTrailerCreate,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a job trailer."""
    svc = VehicleService(db)
    try:
        trailer = await svc.create_trailer(body.model_dump(exclude_none=True))
        return ApiResponse(data=trailer, message="Trailer created")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.put(
    "/trailers/{trailer_id}",
    response_model=ApiResponse[JobTrailerResponse],
)
async def update_trailer(
    trailer_id: int,
    body: JobTrailerUpdate,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update trailer metadata."""
    svc = VehicleService(db)
    updated = await svc.update_trailer(trailer_id, body.model_dump(exclude_unset=True))
    if not updated:
        raise HTTPException(status_code=404, detail="Trailer not found")
    return ApiResponse(data=updated, message="Trailer updated")


@router.delete(
    "/trailers/{trailer_id}",
    response_model=ApiResponse[dict],
)
async def deactivate_trailer(
    trailer_id: int,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Soft deactivate a trailer."""
    svc = VehicleService(db)
    ok = await svc.deactivate_trailer(trailer_id)
    if not ok:
        raise HTTPException(status_code=404, detail="Trailer not found")
    return ApiResponse(data={"id": trailer_id}, message="Trailer deactivated")


@router.get(
    "/trailers/{trailer_id}/inventory",
    response_model=ApiResponse[list[dict]],
)
async def get_trailer_inventory(
    trailer_id: int,
    search: str | None = None,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get inventory currently on a trailer."""
    svc = VehicleService(db)
    try:
        items = await svc.get_trailer_inventory(trailer_id, search=search)
        return ApiResponse(data=items)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.post(
    "/trailers/{trailer_id}/inventory/preload",
    response_model=ApiResponse[dict],
)
async def preload_trailer_inventory(
    trailer_id: int,
    part_id: int = Query(...),
    qty: int = Query(..., ge=1),
    from_location_type: str = Query("warehouse"),
    from_location_id: int = Query(1),
    notes: str | None = None,
    user: dict = Depends(require_permission("move_stock_warehouse")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Preload stock onto trailer (transfer only, not job consumption)."""
    svc = VehicleService(db)
    try:
        result = await svc.preload_trailer_inventory(
            trailer_id,
            part_id,
            qty,
            user["id"],
            from_location_type=from_location_type,
            from_location_id=from_location_id,
            notes=notes,
        )
        return ApiResponse(data=result, message="Trailer preloaded")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post(
    "/trailers/{trailer_id}/inventory/consume",
    response_model=ApiResponse[dict],
)
async def consume_trailer_inventory(
    trailer_id: int,
    part_id: int = Query(...),
    qty: int = Query(..., ge=1),
    job_id: int = Query(...),
    notes: str | None = None,
    photo_path: str | None = None,
    scan_confirmed: bool = False,
    user: dict = Depends(require_permission("move_stock_warehouse")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Consume stock from trailer to a job (explicit billing boundary)."""
    svc = VehicleService(db)
    try:
        result = await svc.consume_trailer_inventory_to_job(
            trailer_id,
            part_id,
            qty,
            job_id,
            user["id"],
            notes=notes,
            photo_path=photo_path,
            scan_confirmed=scan_confirmed,
        )
        return ApiResponse(data=result, message="Trailer inventory consumed to job")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post(
    "/trailers/{trailer_id}/inventory/return",
    response_model=ApiResponse[dict],
)
async def return_trailer_inventory(
    trailer_id: int,
    part_id: int = Query(...),
    qty: int = Query(..., ge=1),
    to_location_type: str = Query("warehouse"),
    to_location_id: int = Query(1),
    notes: str | None = None,
    user: dict = Depends(require_permission("move_stock_warehouse")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Return stock from trailer to destination (default warehouse)."""
    svc = VehicleService(db)
    try:
        result = await svc.return_trailer_inventory(
            trailer_id,
            part_id,
            qty,
            user["id"],
            to_location_type=to_location_type,
            to_location_id=to_location_id,
            notes=notes,
        )
        return ApiResponse(data=result, message="Trailer inventory returned")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get(
    "/trailers/{trailer_id}/location",
    response_model=ApiResponse[dict],
)
async def get_trailer_location(
    trailer_id: int,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get latest known trailer location snapshot."""
    svc = VehicleService(db)
    location = await svc.get_trailer_location(trailer_id)
    if not location:
        raise HTTPException(status_code=404, detail="Trailer not found")
    return ApiResponse(data=location)


@router.get(
    "/trailers/{trailer_id}/location-events",
    response_model=ApiResponse[list[TrailerLocationEventResponse]],
)
async def list_trailer_location_events(
    trailer_id: int,
    limit: int = Query(100, ge=1, le=500),
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List trailer location timeline events (newest first)."""
    svc = VehicleService(db)
    try:
        events = await svc.list_trailer_location_events(trailer_id, limit=limit)
        return ApiResponse(data=[dict(e) for e in events])
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.post(
    "/trailers/{trailer_id}/location-events",
    response_model=ApiResponse[TrailerLocationEventResponse],
    status_code=201,
)
async def create_trailer_location_event(
    trailer_id: int,
    body: TrailerLocationEventCreate,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a trailer location event/check-in."""
    svc = VehicleService(db)
    try:
        event = await svc.record_trailer_location_event(
            trailer_id,
            body.model_dump(exclude_none=True),
            recorded_by=user["id"],
        )
        return ApiResponse(data=event, message="Trailer location updated")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


# ═══════════════════════════════════════════════════════════════════════
# TRAILER STOCK TEMPLATES
# ═══════════════════════════════════════════════════════════════════════


@router.get("/trailer-templates", response_model=ApiResponse[list[dict]])
async def list_trailer_templates(
    trailer_id: int | None = Query(None, description="Filter to a specific trailer"),
    include_global: bool = Query(True, description="Include global templates when filtering by trailer"),
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List trailer stock templates (global + trailer-specific)."""
    svc = VehicleService(db)
    templates = await svc.list_trailer_templates(
        trailer_id=trailer_id, include_global=include_global
    )
    return ApiResponse(data=[dict(t) for t in templates])


@router.get("/trailer-templates/{template_id}", response_model=ApiResponse[dict])
async def get_trailer_template(
    template_id: int,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a single template with its lines."""
    svc = VehicleService(db)
    template = await svc.get_trailer_template(template_id)
    if not template:
        raise HTTPException(status_code=404, detail="Template not found")
    return ApiResponse(data=template)


@router.post("/trailer-templates", response_model=ApiResponse[dict], status_code=201)
async def create_trailer_template(
    body: dict,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new trailer stock template.

    Body: { name, trailer_id?, is_default?, notes?, lines: [{part_id, target_qty, min_qty?}] }
    """
    if not body.get("name"):
        raise HTTPException(status_code=422, detail="Template name is required")
    svc = VehicleService(db)
    template = await svc.create_trailer_template(body)
    return ApiResponse(data=template, message="Template created")


@router.put("/trailer-templates/{template_id}", response_model=ApiResponse[dict])
async def update_trailer_template(
    template_id: int,
    body: dict,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a template header and/or replace its lines."""
    svc = VehicleService(db)
    result = await svc.update_trailer_template(template_id, body)
    if not result:
        raise HTTPException(status_code=404, detail="Template not found")
    return ApiResponse(data=result, message="Template updated")


@router.delete("/trailer-templates/{template_id}", response_model=ApiResponse[dict])
async def delete_trailer_template(
    template_id: int,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a template (CASCADE deletes its lines)."""
    svc = VehicleService(db)
    deleted = await svc.delete_trailer_template(template_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Template not found")
    return ApiResponse(data={"deleted": True}, message="Template deleted")


@router.get(
    "/trailers/{trailer_id}/restock-guidance",
    response_model=ApiResponse[dict],
)
async def trailer_restock_guidance(
    trailer_id: int,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Restock guidance: compare trailer stock vs default template targets."""
    svc = VehicleService(db)
    guidance = await svc.get_restock_guidance(trailer_id)
    return ApiResponse(data=guidance)


@router.get("/my-vehicle", response_model=ApiResponse[MyVehicleDashboard])
async def my_vehicle_dashboard(
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Personal vehicle dashboard for the current user."""
    svc = VehicleService(db)
    dashboard = await svc.get_my_vehicle_dashboard(user["id"])
    return ApiResponse(data=dashboard)


# ═══════════════════════════════════════════════════════════════════════
# ASSIGNMENTS
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/{vehicle_id}/assignments",
    response_model=ApiResponse[list[VehicleAssignmentResponse]],
)
async def list_assignments(
    vehicle_id: int,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List active driver assignments for a vehicle."""
    svc = VehicleService(db)
    assignments = await svc.assignment_repo.get_active_for_vehicle(vehicle_id)
    return ApiResponse(data=[dict(a) for a in assignments])


@router.post(
    "/{vehicle_id}/assign",
    response_model=ApiResponse[VehicleAssignmentResponse],
    status_code=201,
)
async def assign_driver(
    vehicle_id: int,
    body: VehicleAssignmentCreate,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Assign a driver to a vehicle."""
    svc = VehicleService(db)
    try:
        assignment = await svc.assign_driver(
            vehicle_id,
            body.model_dump(exclude_none=True),
        )
        return ApiResponse(data=assignment, message="Driver assigned")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.delete(
    "/{vehicle_id}/assign/{target_user_id}",
    response_model=ApiResponse[dict],
)
async def unassign_driver(
    vehicle_id: int,
    target_user_id: int,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Unassign a driver from a vehicle."""
    svc = VehicleService(db)
    await svc.unassign_driver(vehicle_id, target_user_id)
    return ApiResponse(
        data={"vehicle_id": vehicle_id, "user_id": target_user_id},
        message="Driver unassigned",
    )


@router.put(
    "/{vehicle_id}/take-home",
    response_model=ApiResponse[VehicleAssignmentResponse],
)
async def toggle_take_home(
    vehicle_id: int,
    is_take_home: bool = Query(...),
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Toggle take-home status for the current user's assignment."""
    svc = VehicleService(db)
    try:
        assignment = await svc.toggle_take_home(
            vehicle_id, user["id"], is_take_home
        )
        return ApiResponse(data=assignment, message="Take-home updated")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


# ═══════════════════════════════════════════════════════════════════════
# VEHICLE INVENTORY (uses existing stock system)
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/{vehicle_id}/inventory",
    response_model=ApiResponse[list[dict]],
)
async def get_vehicle_inventory(
    vehicle_id: int,
    search: str | None = None,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get parts inventory on a vehicle."""
    svc = VehicleService(db)
    items = await svc.get_vehicle_inventory(vehicle_id, search=search)
    return ApiResponse(data=items)


@router.post(
    "/{vehicle_id}/inventory/add",
    response_model=ApiResponse[dict],
    status_code=201,
)
async def add_to_inventory(
    vehicle_id: int,
    part_id: int = Query(...),
    qty: int = Query(..., ge=1),
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Add parts to a vehicle's inventory (stock movement warehouse→truck)."""
    svc = VehicleService(db)
    try:
        result = await svc.add_to_vehicle_inventory(
            vehicle_id, part_id, qty, user["id"]
        )
        return ApiResponse(data=result, message="Inventory updated")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post(
    "/{vehicle_id}/inventory/remove",
    response_model=ApiResponse[dict],
)
async def remove_from_inventory(
    vehicle_id: int,
    part_id: int = Query(...),
    qty: int = Query(..., ge=1),
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Remove parts from a vehicle's inventory (stock movement truck→warehouse)."""
    svc = VehicleService(db)
    try:
        result = await svc.remove_from_vehicle_inventory(
            vehicle_id, part_id, qty, user["id"]
        )
        return ApiResponse(data=result, message="Inventory updated")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


# ═══════════════════════════════════════════════════════════════════════
# DELIVERY ITEMS
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/{vehicle_id}/deliveries",
    response_model=ApiResponse[list[DeliveryItemResponse]],
)
async def list_deliveries(
    vehicle_id: int,
    delivery_status: str | None = None,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get delivery items on a vehicle."""
    svc = DeliveryService(db)
    items = await svc.get_deliveries_for_vehicle(
        vehicle_id, status=delivery_status
    )
    return ApiResponse(data=[dict(i) for i in items])


@router.post(
    "/{vehicle_id}/deliveries",
    response_model=ApiResponse[list[DeliveryItemResponse]],
    status_code=201,
)
async def assign_delivery_items(
    vehicle_id: int,
    body: DeliveryItemBulkCreate,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Assign parts to a vehicle for delivery to a specific job."""
    svc = DeliveryService(db)
    try:
        items = await svc.assign_delivery_items(
            vehicle_id,
            body.job_id,
            [item.model_dump() for item in body.items],
            user["id"],
        )
        return ApiResponse(data=items, message="Delivery items assigned")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.put(
    "/{vehicle_id}/deliveries/{item_id}/status",
    response_model=ApiResponse[DeliveryItemResponse],
)
async def update_delivery_status(
    vehicle_id: int,
    item_id: int,
    new_status: str = Query(...),
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a delivery item's status (loaded, in_transit, etc.)."""
    svc = DeliveryService(db)
    try:
        result = await svc.update_delivery_status(item_id, new_status, user["id"])
        if not result:
            raise HTTPException(status_code=404, detail="Delivery item not found")
        return ApiResponse(data=dict(result), message=f"Status updated to {new_status}")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.put(
    "/{vehicle_id}/deliveries/{item_id}/deliver",
    response_model=ApiResponse[DeliveryItemResponse],
)
async def mark_delivered(
    vehicle_id: int,
    item_id: int,
    qty_delivered: int | None = None,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Mark a delivery item as delivered (triggers stock movement truck→job)."""
    svc = DeliveryService(db)
    result = await svc.mark_delivered(
        item_id, user["id"], qty_delivered=qty_delivered
    )
    if not result:
        raise HTTPException(status_code=404, detail="Delivery item not found")
    return ApiResponse(data=dict(result), message="Item delivered")


@router.put(
    "/{vehicle_id}/deliveries/{item_id}/return",
    response_model=ApiResponse[DeliveryItemResponse],
)
async def return_undelivered(
    vehicle_id: int,
    item_id: int,
    return_to: str = Query("truck", pattern="^(truck|warehouse)$"),
    notes: str | None = None,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Return an undelivered item (optionally back to warehouse)."""
    svc = DeliveryService(db)
    try:
        result = await svc.return_undelivered(
            item_id, user["id"], return_to=return_to, notes=notes
        )
        if not result:
            raise HTTPException(status_code=404, detail="Delivery item not found")
        return ApiResponse(data=dict(result), message="Item returned")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


# ═══════════════════════════════════════════════════════════════════════
# MAINTENANCE TYPES (admin)
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/maintenance-types",
    response_model=ApiResponse[list[MaintenanceTypeResponse]],
)
async def list_maintenance_types(
    active_only: bool = True,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all maintenance types."""
    svc = MaintenanceService(db)
    types = await svc.list_maintenance_types(active_only=active_only)
    return ApiResponse(data=[dict(t) for t in types])


@router.post(
    "/maintenance-types",
    response_model=ApiResponse[MaintenanceTypeResponse],
    status_code=201,
)
async def create_maintenance_type(
    body: MaintenanceTypeCreate,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new maintenance type."""
    svc = MaintenanceService(db)
    try:
        mtype = await svc.create_maintenance_type(body.model_dump())
        return ApiResponse(data=dict(mtype), message="Maintenance type created")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.put(
    "/maintenance-types/{type_id}",
    response_model=ApiResponse[MaintenanceTypeResponse],
)
async def update_maintenance_type(
    type_id: int,
    body: MaintenanceTypeCreate,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a maintenance type."""
    svc = MaintenanceService(db)
    try:
        updated = await svc.update_maintenance_type(type_id, body.model_dump())
        if not updated:
            raise HTTPException(status_code=404, detail="Maintenance type not found")
        return ApiResponse(data=dict(updated), message="Type updated")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


# ═══════════════════════════════════════════════════════════════════════
# MAINTENANCE SCHEDULES (per-vehicle)
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/{vehicle_id}/maintenance/schedule",
    response_model=ApiResponse[list[MaintenanceScheduleResponse]],
)
async def get_vehicle_schedule(
    vehicle_id: int,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get the full maintenance schedule for a vehicle."""
    svc = MaintenanceService(db)
    schedules = await svc.get_vehicle_schedule(vehicle_id)
    return ApiResponse(data=[dict(s) for s in schedules])


@router.post(
    "/{vehicle_id}/maintenance/schedule",
    response_model=ApiResponse[MaintenanceScheduleResponse],
)
async def set_maintenance_schedule(
    vehicle_id: int,
    body: MaintenanceScheduleCreate,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Set/update a per-vehicle maintenance schedule for a type."""
    svc = MaintenanceService(db)
    try:
        schedule = await svc.set_schedule(
            vehicle_id,
            body.maintenance_type_id,
            body.model_dump(exclude_unset=True, exclude={"maintenance_type_id"}),
        )
        return ApiResponse(data=dict(schedule), message="Schedule updated")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get(
    "/maintenance/upcoming",
    response_model=ApiResponse[list[MaintenanceAlert]],
)
async def upcoming_maintenance(
    days_ahead: int = Query(30, ge=1, le=365),
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Fleet-wide upcoming maintenance items."""
    svc = MaintenanceService(db)
    items = await svc.get_upcoming(days_ahead=days_ahead)
    return ApiResponse(data=items)


@router.get(
    "/maintenance/overdue",
    response_model=ApiResponse[list[MaintenanceAlert]],
)
async def overdue_maintenance(
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Fleet-wide overdue maintenance items."""
    svc = MaintenanceService(db)
    items = await svc.get_overdue()
    return ApiResponse(data=items)


# ═══════════════════════════════════════════════════════════════════════
# MAINTENANCE RECORDS (service history)
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/{vehicle_id}/maintenance/history",
    response_model=ApiResponse[list[MaintenanceRecordResponse]],
)
async def service_history(
    vehicle_id: int,
    maintenance_type_id: int | None = None,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get service history for a vehicle."""
    svc = MaintenanceService(db)
    records = await svc.get_service_history(
        vehicle_id,
        maintenance_type_id=maintenance_type_id,
        limit=limit,
        offset=offset,
    )
    return ApiResponse(data=[dict(r) for r in records])


@router.post(
    "/{vehicle_id}/maintenance/log",
    response_model=ApiResponse[MaintenanceRecordResponse],
    status_code=201,
)
async def log_maintenance(
    vehicle_id: int,
    body: MaintenanceRecordCreate,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Log a maintenance service for a vehicle."""
    svc = MaintenanceService(db)
    try:
        record = await svc.log_service(
            vehicle_id, body.model_dump(), user["id"]
        )
        return ApiResponse(data=dict(record), message="Service logged")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get(
    "/{vehicle_id}/maintenance/costs",
    response_model=ApiResponse[dict],
)
async def maintenance_costs(
    vehicle_id: int,
    period_start: str | None = None,
    period_end: str | None = None,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get maintenance cost summary with per-type breakdown."""
    svc = MaintenanceService(db)
    summary = await svc.get_cost_summary(
        vehicle_id,
        period_start=period_start,
        period_end=period_end,
    )
    return ApiResponse(data=summary)


# ═══════════════════════════════════════════════════════════════════════
# MILEAGE
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/{vehicle_id}/mileage",
    response_model=ApiResponse[list[MileageLogResponse]],
)
async def list_mileage_logs(
    vehicle_id: int,
    limit: int = Query(30, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get mileage logs for a vehicle."""
    svc = MileageService(db)
    logs = await svc.get_mileage_logs(vehicle_id, limit=limit, offset=offset)
    return ApiResponse(data=[dict(l) for l in logs])


@router.post(
    "/{vehicle_id}/mileage",
    response_model=ApiResponse[MileageLogResponse],
    status_code=201,
)
async def log_mileage(
    vehicle_id: int,
    body: MileageLogCreate,
    user: dict = Depends(require_permission("log_mileage")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Log daily mileage for a vehicle."""
    svc = MileageService(db)
    try:
        log = await svc.log_daily_mileage(
            vehicle_id, user["id"], body.model_dump()
        )
        return ApiResponse(data=dict(log), message="Mileage logged")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.put(
    "/{vehicle_id}/mileage/{log_id}",
    response_model=ApiResponse[MileageLogResponse],
)
async def update_mileage_log(
    vehicle_id: int,
    log_id: int,
    body: MileageLogUpdate,
    user: dict = Depends(require_permission("log_mileage")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a mileage log entry."""
    svc = MileageService(db)
    try:
        updated = await svc.update_mileage_log(
            log_id, body.model_dump(exclude_unset=True)
        )
        if not updated:
            raise HTTPException(status_code=404, detail="Mileage log not found")
        return ApiResponse(data=dict(updated), message="Mileage log updated")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get(
    "/{vehicle_id}/mileage/{log_id}/trips",
    response_model=ApiResponse[list[TripLegResponse]],
)
async def get_trip_legs(
    vehicle_id: int,
    log_id: int,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get trip legs for a mileage log entry."""
    svc = MileageService(db)
    legs = await svc.get_trip_legs(log_id)
    return ApiResponse(data=[dict(l) for l in legs])


@router.post(
    "/{vehicle_id}/mileage/{log_id}/trips",
    response_model=ApiResponse[list[int]],
    status_code=201,
)
async def add_trip_legs(
    vehicle_id: int,
    log_id: int,
    body: TripLegBulkCreate,
    user: dict = Depends(require_permission("log_mileage")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Add trip legs to a mileage log."""
    svc = MileageService(db)
    try:
        ids = await svc.add_trip_legs(
            log_id, [leg.model_dump() for leg in body.legs]
        )
        return ApiResponse(data=ids, message=f"{len(ids)} trip legs added")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get(
    "/mileage/estimate",
    response_model=ApiResponse[MileageEstimate],
)
async def estimate_mileage(
    vehicle_id: int | None = None,
    driver_id: int | None = None,
    job_id: int | None = None,
    is_take_home: bool | None = None,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Estimate trip mileage using stored distances."""
    svc = MileageService(db)
    estimate = await svc.estimate_trip(
        vehicle_id=vehicle_id,
        driver_id=driver_id or user["id"],
        job_id=job_id,
        is_take_home=is_take_home,
    )
    return ApiResponse(data=estimate)


@router.get(
    "/mileage/summary",
    response_model=ApiResponse[MileageSummary],
)
async def mileage_summary(
    period_start: str = Query(...),
    period_end: str = Query(...),
    vehicle_id: int | None = None,
    driver_id: int | None = None,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get mileage summary for a period."""
    svc = MileageService(db)
    summary = await svc.get_mileage_summary(
        vehicle_id=vehicle_id,
        driver_id=driver_id,
        period_start=period_start,
        period_end=period_end,
    )
    return ApiResponse(data=summary)


# ═══════════════════════════════════════════════════════════════════════
# REIMBURSEMENT (private vehicles)
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/reimbursements",
    response_model=ApiResponse[list[ReimbursementResponse]],
)
async def list_reimbursements(
    reimbursement_status: str | None = None,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List reimbursements for the current user."""
    svc = MileageService(db)
    items = await svc.get_user_reimbursements(
        user["id"], status=reimbursement_status
    )
    return ApiResponse(data=[dict(r) for r in items])


@router.get(
    "/reimbursements/pending",
    response_model=ApiResponse[list[ReimbursementResponse]],
)
async def pending_reimbursements(
    user: dict = Depends(require_permission("approve_reimbursement")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all pending reimbursements (manager approval queue)."""
    svc = MileageService(db)
    items = await svc.get_pending_reimbursements()
    return ApiResponse(data=[dict(r) for r in items])


@router.post(
    "/reimbursements",
    response_model=ApiResponse[ReimbursementResponse],
    status_code=201,
)
async def create_reimbursement(
    body: ReimbursementCreate,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a mileage reimbursement request."""
    svc = MileageService(db)
    try:
        reimb = await svc.create_reimbursement(user["id"], body.model_dump())
        return ApiResponse(data=dict(reimb), message="Reimbursement submitted")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.put(
    "/reimbursements/{reimbursement_id}/approve",
    response_model=ApiResponse[ReimbursementResponse],
)
async def approve_reimbursement(
    reimbursement_id: int,
    body: ReimbursementApproval,
    user: dict = Depends(require_permission("approve_reimbursement")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Approve or reject a pending reimbursement."""
    svc = MileageService(db)
    try:
        result = await svc.approve_reimbursement(
            reimbursement_id, body.action, user["id"], body.notes
        )
        if not result:
            raise HTTPException(status_code=404, detail="Reimbursement not found")
        return ApiResponse(
            data=dict(result),
            message=f"Reimbursement {body.action}d",
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


# ═══════════════════════════════════════════════════════════════════════
# WAREHOUSE LOCATIONS
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/warehouse-locations",
    response_model=ApiResponse[list[WarehouseLocationResponse]],
)
async def list_warehouse_locations(
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all warehouse/shop locations."""
    svc = VehicleService(db)
    locations = await svc.warehouse_repo.list_active()
    return ApiResponse(data=[dict(l) for l in locations])


@router.post(
    "/warehouse-locations",
    response_model=ApiResponse[WarehouseLocationResponse],
    status_code=201,
)
async def create_warehouse_location(
    body: WarehouseLocationCreate,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a warehouse/shop location."""
    svc = VehicleService(db)
    location = await svc.create_warehouse_location(body.model_dump())
    return ApiResponse(data=location, message="Location created")


@router.put(
    "/warehouse-locations/{location_id}",
    response_model=ApiResponse[WarehouseLocationResponse],
)
async def update_warehouse_location(
    location_id: int,
    body: WarehouseLocationUpdate,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a warehouse/shop location."""
    svc = VehicleService(db)
    updated = await svc.update_warehouse_location(
        location_id, body.model_dump(exclude_unset=True)
    )
    if not updated:
        raise HTTPException(status_code=404, detail="Location not found")
    return ApiResponse(data=updated, message="Location updated")


@router.delete(
    "/warehouse-locations/{location_id}",
    response_model=ApiResponse[dict],
)
async def deactivate_warehouse_location(
    location_id: int,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Deactivate a warehouse/shop location."""
    svc = VehicleService(db)
    result = await svc.deactivate_warehouse_location(location_id)
    if not result:
        raise HTTPException(status_code=404, detail="Location not found")
    return ApiResponse(data={"id": location_id}, message="Location deactivated")


# ═══════════════════════════════════════════════════════════════════════
# FLEET DASHBOARD
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/fleet/dashboard",
    response_model=ApiResponse[FleetDashboardStats],
)
async def fleet_dashboard(
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Fleet management dashboard with summary KPIs."""
    svc = VehicleService(db)
    stats = await svc.get_fleet_dashboard()
    return ApiResponse(data=stats)


# ═══════════════════════════════════════════════════════════════════════
# FUEL TRACKING
# ═══════════════════════════════════════════════════════════════════════

@router.post(
    "/fuel/{vehicle_id}",
    response_model=ApiResponse[FuelLogResponse],
    status_code=status.HTTP_201_CREATED,
)
async def log_fuel(
    vehicle_id: int,
    body: FuelLogCreate,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Log a fuel purchase for a vehicle."""
    svc = FuelService(db)
    try:
        record = await svc.log_fuel(vehicle_id, user["id"], body.model_dump())
        return ApiResponse(data=record, message="Fuel log recorded")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get(
    "/fuel/{vehicle_id}",
    response_model=ApiResponse[list[FuelLogResponse]],
)
async def get_vehicle_fuel_logs(
    vehicle_id: int,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Fuel history for a vehicle."""
    svc = FuelService(db)
    logs = await svc.get_fuel_logs(vehicle_id, limit=limit, offset=offset)
    return ApiResponse(data=logs)


@router.put(
    "/fuel/log/{log_id}",
    response_model=ApiResponse[FuelLogResponse],
)
async def update_fuel_log(
    log_id: int,
    body: FuelLogUpdate,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a fuel log entry."""
    svc = FuelService(db)
    result = await svc.update_fuel_log(log_id, body.model_dump(exclude_unset=True))
    if not result:
        raise HTTPException(status_code=404, detail="Fuel log not found")
    return ApiResponse(data=result, message="Fuel log updated")


@router.get(
    "/fuel-summary/{vehicle_id}",
    response_model=ApiResponse[FuelSummary],
)
async def get_fuel_summary(
    vehicle_id: int,
    period_start: str | None = None,
    period_end: str | None = None,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Fuel cost/consumption summary for a vehicle."""
    svc = FuelService(db)
    summary = await svc.get_fuel_summary(vehicle_id, period_start, period_end)
    return ApiResponse(data=summary)


@router.get(
    "/fleet/fuel-summary",
    response_model=ApiResponse[FuelSummary],
)
async def fleet_fuel_summary(
    period_start: str | None = None,
    period_end: str | None = None,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Fleet-wide fuel cost/consumption summary."""
    svc = FuelService(db)
    summary = await svc.get_fuel_summary(None, period_start, period_end)
    return ApiResponse(data=summary)


# ═══════════════════════════════════════════════════════════════════════
# TELEMATICS — Device Management & Data Ingestion
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/telematics/devices",
    response_model=ApiResponse[list[TelematicsDeviceResponse]],
)
async def list_telematics_devices(
    active_only: bool = True,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all registered telematics devices."""
    svc = TelematicsService(db)
    devices = await svc.list_devices(active_only=active_only)
    return ApiResponse(data=devices)


@router.post(
    "/telematics/devices",
    response_model=ApiResponse[TelematicsDeviceResponse],
    status_code=status.HTTP_201_CREATED,
)
async def register_telematics_device(
    body: TelematicsDeviceCreate,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Register a telematics device on a vehicle."""
    svc = TelematicsService(db)
    try:
        device = await svc.register_device(body.model_dump())
        return ApiResponse(data=device, message="Device registered")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.delete(
    "/telematics/devices/{device_id}",
    response_model=ApiResponse[dict],
)
async def deactivate_telematics_device(
    device_id: int,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Deactivate a telematics device."""
    svc = TelematicsService(db)
    ok = await svc.deactivate_device(device_id)
    if not ok:
        raise HTTPException(status_code=404, detail="Device not found")
    return ApiResponse(data={"id": device_id}, message="Device deactivated")


@router.post(
    "/telematics/ingest/position",
    response_model=ApiResponse[TelematicsPositionResponse],
    status_code=status.HTTP_201_CREATED,
)
async def ingest_position(
    body: TelematicsPositionIngest,
    db: aiosqlite.Connection = Depends(get_db),
):
    """Device pushes a GPS position reading. Auth via device token."""
    svc = TelematicsService(db)
    try:
        pos = await svc.ingest_position(body.auth_token, body.model_dump())
        return ApiResponse(data=pos)
    except ValueError as e:
        raise HTTPException(status_code=401, detail=str(e))


@router.post(
    "/telematics/ingest/event",
    response_model=ApiResponse[TelematicsEventResponse],
    status_code=status.HTTP_201_CREATED,
)
async def ingest_event(
    body: TelematicsEventIngest,
    db: aiosqlite.Connection = Depends(get_db),
):
    """Device pushes a telematics event. Auth via device token."""
    svc = TelematicsService(db)
    try:
        event = await svc.ingest_event(body.auth_token, body.model_dump())
        return ApiResponse(data=event)
    except ValueError as e:
        raise HTTPException(status_code=401, detail=str(e))


@router.get(
    "/telematics/positions/{vehicle_id}",
    response_model=ApiResponse[list[TelematicsPositionResponse]],
)
async def get_vehicle_positions(
    vehicle_id: int,
    since: str | None = None,
    limit: int = Query(200, ge=1, le=1000),
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Recent GPS breadcrumbs for a vehicle."""
    svc = TelematicsService(db)
    positions = await svc.get_vehicle_positions(vehicle_id, since=since, limit=limit)
    return ApiResponse(data=positions)


@router.get(
    "/telematics/events/{vehicle_id}",
    response_model=ApiResponse[list[TelematicsEventResponse]],
)
async def get_vehicle_events(
    vehicle_id: int,
    since: str | None = None,
    event_type: str | None = None,
    limit: int = Query(100, ge=1, le=500),
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Recent telematics events for a vehicle."""
    svc = TelematicsService(db)
    events = await svc.get_vehicle_events(
        vehicle_id, since=since, event_type=event_type, limit=limit
    )
    return ApiResponse(data=events)


@router.get(
    "/fleet/positions",
    response_model=ApiResponse[list[VehicleLocationSummary]],
)
async def fleet_positions(
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Last known location for every vehicle with a telematics device."""
    svc = TelematicsService(db)
    positions = await svc.get_fleet_positions()
    return ApiResponse(data=positions)


# ═══════════════════════════════════════════════════════════════════════
# VEHICLE INSPECTIONS
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/inspections/templates",
    response_model=ApiResponse[list[InspectionTemplateResponse]],
)
async def list_inspection_templates(
    vehicle_type: str | None = None,
    inspection_type: str | None = None,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all inspection templates."""
    svc = InspectionService(db)
    templates = await svc.get_templates(
        vehicle_type=vehicle_type, inspection_type=inspection_type
    )
    return ApiResponse(data=templates)


@router.post(
    "/inspections/templates",
    response_model=ApiResponse[InspectionTemplateResponse],
    status_code=status.HTTP_201_CREATED,
)
async def create_inspection_template(
    body: InspectionTemplateCreate,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create an inspection template with checklist items."""
    svc = InspectionService(db)
    template = await svc.create_template(body.model_dump())
    return ApiResponse(data=template, message="Template created")


@router.get(
    "/inspections/templates/{template_id}",
    response_model=ApiResponse[InspectionTemplateResponse],
)
async def get_inspection_template(
    template_id: int,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get an inspection template with items."""
    svc = InspectionService(db)
    template = await svc.get_template(template_id)
    if not template:
        raise HTTPException(status_code=404, detail="Template not found")
    return ApiResponse(data=template)


@router.put(
    "/inspections/templates/{template_id}",
    response_model=ApiResponse[InspectionTemplateResponse],
)
async def update_inspection_template(
    template_id: int,
    body: InspectionTemplateUpdate,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update an inspection template."""
    svc = InspectionService(db)
    result = await svc.update_template(template_id, body.model_dump(exclude_unset=True))
    if not result:
        raise HTTPException(status_code=404, detail="Template not found")
    return ApiResponse(data=result, message="Template updated")


@router.post(
    "/inspections/{vehicle_id}/start",
    response_model=ApiResponse[InspectionRecordResponse],
    status_code=status.HTTP_201_CREATED,
)
async def start_inspection(
    vehicle_id: int,
    body: InspectionRecordCreate,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Start a new inspection for a vehicle from a template."""
    svc = InspectionService(db)
    try:
        record = await svc.start_inspection(vehicle_id, user["id"], body.model_dump())
        return ApiResponse(data=record, message="Inspection started")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.put(
    "/inspections/records/{record_id}/items/{item_id}",
    response_model=ApiResponse[InspectionRecordResponse],
)
async def submit_inspection_item(
    record_id: int,
    item_id: int,
    body: InspectionItemSubmit,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Submit pass/fail for a single inspection item."""
    svc = InspectionService(db)
    try:
        record = await svc.submit_item(record_id, item_id, body.model_dump())
        return ApiResponse(data=record, message="Item submitted")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post(
    "/inspections/records/{record_id}/complete",
    response_model=ApiResponse[InspectionRecordResponse],
)
async def complete_inspection(
    record_id: int,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Finalize an inspection — calculates overall result."""
    svc = InspectionService(db)
    try:
        record = await svc.complete_inspection(record_id)
        return ApiResponse(data=record, message="Inspection completed")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get(
    "/inspections/{vehicle_id}/history",
    response_model=ApiResponse[list[InspectionRecordResponse]],
)
async def get_vehicle_inspections(
    vehicle_id: int,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Inspection history for a vehicle."""
    svc = InspectionService(db)
    records = await svc.get_vehicle_inspections(vehicle_id, limit=limit, offset=offset)
    return ApiResponse(data=records)


@router.get(
    "/fleet/inspections/pending",
    response_model=ApiResponse[list[InspectionRecordResponse]],
)
async def fleet_pending_inspections(
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Fleet-wide incomplete inspections."""
    svc = InspectionService(db)
    records = await svc.get_pending_inspections()
    return ApiResponse(data=records)


@router.get(
    "/fleet/inspections/failed",
    response_model=ApiResponse[list[InspectionRecordResponse]],
)
async def fleet_failed_inspections(
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Failed / needs-attention inspections for manager review."""
    svc = InspectionService(db)
    records = await svc.get_failed_inspections()
    return ApiResponse(data=records)


# ═══════════════════════════════════════════════════════════════════════
# VEHICLE TRANSFERS
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/fleet/transfers",
    response_model=ApiResponse[list[VehicleTransferResponse]],
)
async def list_transfers(
    transfer_status: str | None = None,
    vehicle_id: int | None = None,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List vehicle transfers."""
    svc = VehicleService(db)
    transfers = await svc.list_transfers(
        status=transfer_status, vehicle_id=vehicle_id, limit=limit, offset=offset
    )
    return ApiResponse(data=transfers)


@router.post(
    "/fleet/transfers",
    response_model=ApiResponse[VehicleTransferResponse],
    status_code=status.HTTP_201_CREATED,
)
async def request_transfer(
    body: VehicleTransferCreate,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Request a vehicle transfer between warehouses."""
    svc = VehicleService(db)
    try:
        transfer = await svc.request_transfer(body.model_dump(), user["id"])
        return ApiResponse(data=transfer, message="Transfer requested")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post(
    "/fleet/transfers/{transfer_id}/approve",
    response_model=ApiResponse[VehicleTransferResponse],
)
async def approve_transfer(
    transfer_id: int,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Approve a transfer request."""
    svc = VehicleService(db)
    try:
        transfer = await svc.approve_transfer(transfer_id, user["id"])
        return ApiResponse(data=transfer, message="Transfer approved")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post(
    "/fleet/transfers/{transfer_id}/transit",
    response_model=ApiResponse[VehicleTransferResponse],
)
async def start_transit(
    transfer_id: int,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Mark a transfer as in-transit."""
    svc = VehicleService(db)
    try:
        transfer = await svc.start_transit(transfer_id)
        return ApiResponse(data=transfer, message="Transfer in transit")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post(
    "/fleet/transfers/{transfer_id}/complete",
    response_model=ApiResponse[VehicleTransferResponse],
)
async def complete_transfer(
    transfer_id: int,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Mark a transfer as completed."""
    svc = VehicleService(db)
    try:
        transfer = await svc.complete_transfer(transfer_id)
        return ApiResponse(data=transfer, message="Transfer completed")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post(
    "/fleet/transfers/{transfer_id}/cancel",
    response_model=ApiResponse[VehicleTransferResponse],
)
async def cancel_transfer(
    transfer_id: int,
    reason: str | None = None,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Cancel a pending/approved transfer."""
    svc = VehicleService(db)
    try:
        transfer = await svc.cancel_transfer(transfer_id, reason)
        return ApiResponse(data=transfer, message="Transfer cancelled")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


# ═══════════════════════════════════════════════════════════════════════
# DOCUMENT ALERTS & UTILIZATION
# ═══════════════════════════════════════════════════════════════════════

@router.get(
    "/fleet/document-alerts",
    response_model=ApiResponse[list[VehicleDocumentAlert]],
)
async def get_document_alerts(
    days_ahead: int = Query(30, ge=1, le=365),
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Vehicles with insurance or registration expiring within N days."""
    svc = VehicleService(db)
    alerts = await svc.get_document_alerts(days_ahead)
    return ApiResponse(data=alerts)


@router.get(
    "/fleet/utilization",
    response_model=ApiResponse[VehicleUtilizationReport],
)
async def get_utilization_report(
    period_start: str = Query(..., description="YYYY-MM-DD"),
    period_end: str = Query(..., description="YYYY-MM-DD"),
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Fleet utilization report: miles, costs, MPG per vehicle."""
    svc = VehicleService(db)
    report = await svc.get_utilization_report(period_start, period_end)
    return ApiResponse(data=report)


# ═══════════════════════════════════════════════════════════════════════
# VEHICLE PHOTO UPLOAD
# ═══════════════════════════════════════════════════════════════════════


@router.post(
    "/photo/{vehicle_id}",
    response_model=ApiResponse[dict],
    summary="Upload vehicle photo",
)
async def upload_vehicle_photo(
    vehicle_id: int,
    file: UploadFile = File(...),
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Upload or replace a vehicle's photo."""
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    ext = Path(file.filename or "photo.jpg").suffix
    stored_name = f"vehicle_{vehicle_id}_{uuid.uuid4().hex}{ext}"
    file_path = UPLOAD_DIR / stored_name

    content = await file.read()
    file_path.write_bytes(content)

    # Update vehicle record with the new photo path
    await db.execute(
        "UPDATE vehicles SET photo_path = ?, updated_at = datetime('now') WHERE id = ?",
        (f"/uploads/vehicles/{stored_name}", vehicle_id),
    )
    await db.commit()

    return ApiResponse(
        data={"photo_path": f"/uploads/vehicles/{stored_name}"},
        message="Vehicle photo uploaded",
    )


@router.delete(
    "/photo/{vehicle_id}",
    response_model=ApiResponse[dict],
    summary="Remove vehicle photo",
)
async def remove_vehicle_photo(
    vehicle_id: int,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Remove a vehicle's photo."""
    await db.execute(
        "UPDATE vehicles SET photo_path = NULL, updated_at = datetime('now') WHERE id = ?",
        (vehicle_id,),
    )
    await db.commit()
    return ApiResponse(data={}, message="Vehicle photo removed")


# ═══════════════════════════════════════════════════════════════════════
# SINGLE-VEHICLE CRUD — /{vehicle_id} catch-all (MUST BE LAST!)
# ═══════════════════════════════════════════════════════════════════════
# IMPORTANT: These /{vehicle_id} routes match ANY single path segment,
# so they MUST be registered after all specific named paths
# (/maintenance-types, /reimbursements, /warehouse-locations, /fleet/*)
# to avoid route collisions (same pattern as app_settings.py /{key}).


@router.get("/{vehicle_id}", response_model=ApiResponse[VehicleResponse])
async def get_vehicle(
    vehicle_id: int,
    user: dict = Depends(require_permission("view_trucks")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get vehicle details."""
    svc = VehicleService(db)
    vehicle = await svc.vehicle_repo.get_with_details(vehicle_id)
    if not vehicle:
        raise HTTPException(status_code=404, detail="Vehicle not found")
    return ApiResponse(data=dict(vehicle))


@router.put("/{vehicle_id}", response_model=ApiResponse[VehicleResponse])
async def update_vehicle(
    vehicle_id: int,
    body: VehicleUpdate,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update vehicle details."""
    svc = VehicleService(db)
    updated = await svc.update_vehicle(vehicle_id, body.model_dump(exclude_unset=True))
    if not updated:
        raise HTTPException(status_code=404, detail="Vehicle not found")
    return ApiResponse(data=updated, message="Vehicle updated")


@router.delete("/{vehicle_id}", response_model=ApiResponse[VehicleResponse])
async def deactivate_vehicle(
    vehicle_id: int,
    user: dict = Depends(require_permission("manage_fleet")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Soft-delete (deactivate) a vehicle."""
    svc = VehicleService(db)
    result = await svc.deactivate_vehicle(vehicle_id)
    if not result:
        raise HTTPException(status_code=404, detail="Vehicle not found")
    return ApiResponse(data=result, message="Vehicle deactivated")
