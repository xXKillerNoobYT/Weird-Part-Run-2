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
from typing import Any

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse, PaginatedData
from app.models.vehicles import (
    DeliveryItemBulkCreate,
    DeliveryItemResponse,
    DeliveryItemUpdate,
    FleetDashboardStats,
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
    TripLegBulkCreate,
    TripLegResponse,
    VehicleAssignmentCreate,
    VehicleAssignmentResponse,
    VehicleCreate,
    VehicleListItem,
    VehicleResponse,
    VehicleUpdate,
    WarehouseLocationCreate,
    WarehouseLocationResponse,
    WarehouseLocationUpdate,
)
from app.services.delivery_service import DeliveryService
from app.services.maintenance_service import MaintenanceService
from app.services.mileage_service import MileageService
from app.services.vehicle_service import VehicleService

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/trucks", tags=["Trucks"], redirect_slashes=False)


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
