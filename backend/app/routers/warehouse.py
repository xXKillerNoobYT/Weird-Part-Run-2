"""
Warehouse routes — dashboard, inventory, staging, movements, audit, helpers.

Provides ~20 endpoints covering:
- Dashboard KPIs, activity feed, pending tasks
- Inventory grid with filters and pagination
- Staging area (pulled items grouped by destination)
- Movement wizard (validate, preview, execute)
- Audit sessions (spot check, category, rolling)
- Helpers (locations, parts search, photo upload, supplier prefs, reasons)
"""

from __future__ import annotations

import logging
import uuid
from pathlib import Path
from typing import Any

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File, status

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse, PaginatedData
from app.models.warehouse import (
    MOVEMENT_RULES,
    REASON_CATEGORIES,
    VALID_LOCATION_TYPES,
    ActivitySummary,
    AuditCountRequest,
    AuditItemResponse,
    AuditProgress,
    AuditResponse,
    AuditStartRequest,
    AuditSummary,
    DashboardData,
    DashboardKPIs,
    LocationOption,
    MovementExecuteResponse,
    MovementPreview,
    MovementRequest,
    PendingTask,
    ReceiveStockRequest,
    ReceiveStockResult,
    StagingGroup,
    SupplierPreferenceResponse,
    SupplierPreferenceSet,
    ValidationResult,
    WarehouseInventoryItem,
)
from app.repositories.stock_repo import MovementRepo
from app.services.audit_service import AuditService
from app.services.movement_service import MovementService
from app.services.warehouse_service import WarehouseService

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/warehouse", tags=["Warehouse"])

# Upload directory for photos (local filesystem for v1)
UPLOAD_DIR = Path("uploads")


# =================================================================
# DASHBOARD
# =================================================================


@router.get("/dashboard")
async def warehouse_dashboard(
    user: dict = Depends(require_permission("view_warehouse")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Combined dashboard: KPIs + recent activity + pending tasks."""
    show_dollars = "show_dollar_values" in user.get("permissions", [])
    svc = WarehouseService(db)
    data = await svc.get_dashboard(show_dollars=show_dollars)
    return ApiResponse(data=data, message="Dashboard loaded")


@router.get("/dashboard/kpis")
async def dashboard_kpis(
    user: dict = Depends(require_permission("view_warehouse")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Dashboard KPI cards (stock health %, units, value, shortfall, tasks)."""
    show_dollars = "show_dollar_values" in user.get("permissions", [])
    svc = WarehouseService(db)
    kpis = await svc.get_kpis(show_dollars=show_dollars)
    return ApiResponse(data=kpis)


@router.get("/dashboard/activity")
async def dashboard_activity(
    limit: int = Query(10, ge=1, le=50),
    user: dict = Depends(require_permission("view_warehouse")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Recent movement activity feed (one-line summaries)."""
    svc = WarehouseService(db)
    activity = await svc.get_recent_activity(limit=limit)
    return ApiResponse(data=activity)


@router.get("/dashboard/pending-tasks")
async def dashboard_pending_tasks(
    user: dict = Depends(require_permission("view_warehouse")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Pending tasks: staged items, active audits, spot-check requests."""
    svc = WarehouseService(db)
    tasks = await svc.get_pending_tasks()
    return ApiResponse(data=tasks)


# =================================================================
# INVENTORY GRID
# =================================================================


@router.get("/inventory")
async def warehouse_inventory(
    search: str = Query("", description="Part name or code search"),
    category_id: int | None = Query(None),
    brand_id: int | None = Query(None),
    part_id: int | None = Query(None, description="Filter to a single part (for stock-check lookups)"),
    stock_status: str = Query("all", description="low_stock|overstock|in_range|winding_down|zero|all"),
    sort_by: str = Query("name", description="name|code|qty|category|shelf"),
    sort_dir: str = Query("asc", description="asc|desc"),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=10, le=200),
    user: dict = Depends(require_permission("view_warehouse")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Paginated warehouse inventory grid with health bars."""
    show_dollars = "show_dollar_values" in user.get("permissions", [])
    svc = WarehouseService(db)
    items, total = await svc.get_warehouse_inventory(
        search=search,
        category_id=category_id,
        brand_id=brand_id,
        part_id=part_id,
        stock_status=stock_status,
        sort_by=sort_by,
        sort_dir=sort_dir,
        page=page,
        page_size=page_size,
        show_dollars=show_dollars,
    )
    total_pages = (total + page_size - 1) // page_size if total > 0 else 0
    return ApiResponse(data=PaginatedData(
        items=items,
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
    ))


# =================================================================
# RECEIVE STOCK (add new stock to warehouse)
# =================================================================


@router.post("/receive-stock")
async def receive_stock(
    req: ReceiveStockRequest,
    user: dict = Depends(require_permission("move_stock_warehouse")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Receive new stock into the warehouse.

    Used to add parts from the catalog into warehouse inventory,
    e.g., initial count, deliveries, or manual additions.
    Logs 'receive' movements for the audit trail.
    """
    svc = MovementService(db)
    try:
        result = await svc.receive_stock(req, performed_by=user["id"])
        return ApiResponse(data=result, message=f"Received {result.total_qty} units")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.exception("Receive stock failed")
        raise HTTPException(status_code=500, detail="Failed to receive stock")


# =================================================================
# STAGING
# =================================================================


@router.get("/staging")
async def staging_area(
    user: dict = Depends(require_permission("view_warehouse")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Pulled/staging area — items grouped by destination with aging info."""
    svc = WarehouseService(db)
    groups = await svc.get_staging_groups()
    return ApiResponse(data=groups)


# =================================================================
# MOVEMENTS
# =================================================================


@router.get("/movements")
async def movements_log(
    movement_type: str | None = Query(None),
    from_location_type: str | None = Query(None),
    to_location_type: str | None = Query(None),
    performed_by: int | None = Query(None),
    part_id: int | None = Query(None),
    date_from: str | None = Query(None, description="ISO date YYYY-MM-DD"),
    date_to: str | None = Query(None, description="ISO date YYYY-MM-DD"),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=10, le=200),
    user: dict = Depends(require_permission("view_warehouse")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Paginated movement history log with filters."""
    repo = MovementRepo(db)

    # Build filters
    filters: dict[str, Any] = {}
    if movement_type:
        filters["movement_type"] = movement_type
    if from_location_type:
        filters["from_location_type"] = from_location_type
    if to_location_type:
        filters["to_location_type"] = to_location_type
    if performed_by:
        filters["performed_by"] = performed_by
    if part_id:
        filters["part_id"] = part_id
    if date_from:
        filters["date_from"] = date_from
    if date_to:
        filters["date_to"] = date_to

    movements = await repo.get_movements(
        limit=page_size,
        offset=(page - 1) * page_size,
        **filters,
    )
    total = await repo.count_movements(**filters)

    return ApiResponse(
        data=PaginatedData(
            items=movements,
            total=total,
            page=page,
            page_size=page_size,
            total_pages=(total + page_size - 1) // page_size if page_size else 0,
        )
    )


@router.get("/movements/{movement_id}")
async def get_movement(
    movement_id: int,
    user: dict = Depends(require_permission("view_warehouse")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a single movement with full details including photo URL."""
    cursor = await db.execute(
        """SELECT sm.*,
                  p.name AS part_name, p.code AS part_code,
                  u.display_name AS performer_name
           FROM stock_movements sm
           JOIN parts p ON p.id = sm.part_id
           LEFT JOIN users u ON u.id = sm.performed_by
           WHERE sm.id = ?""",
        (movement_id,),
    )
    row = await cursor.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Movement not found")
    return ApiResponse(data=dict(row))


@router.post("/movements/validate")
async def validate_movement(
    req: MovementRequest,
    user: dict = Depends(require_permission("move_stock_warehouse")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Pre-flight validation for a movement — returns errors and warnings."""
    svc = MovementService(db)
    result = await svc.validate_movement(req)
    return ApiResponse(data=result)


@router.post("/movements/preview")
async def preview_movement(
    req: MovementRequest,
    user: dict = Depends(require_permission("move_stock_warehouse")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Preview before/after state of a movement batch before executing."""
    svc = MovementService(db)

    # Validate first
    validation = await svc.validate_movement(req)
    if not validation.valid:
        return ApiResponse(
            success=False,
            data=validation,
            error="Movement validation failed",
        )

    preview = await svc.calculate_preview(req)
    return ApiResponse(data=preview)


@router.post("/movements/execute")
async def execute_movement(
    req: MovementRequest,
    user: dict = Depends(require_permission("move_stock_warehouse")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Execute a stock movement — atomic all-or-nothing."""
    svc = MovementService(db)

    # Validate first
    validation = await svc.validate_movement(req)
    if not validation.valid:
        return ApiResponse(
            success=False,
            data=validation,
            error="Movement validation failed",
        )

    try:
        result = await svc.execute_movement(req, performed_by=user["id"])
        return ApiResponse(data=result, message="Movement executed successfully")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.exception("Movement execution failed")
        raise HTTPException(status_code=500, detail="Movement execution failed")


# =================================================================
# AUDIT
# =================================================================


@router.get("/audit")
async def list_audits(
    audit_status: str | None = Query(None, alias="status"),
    audit_type: str | None = Query(None, alias="type"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user: dict = Depends(require_permission("perform_audit")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List audits with optional status/type filters."""
    from app.repositories.audit_repo import AuditRepo

    repo = AuditRepo(db)
    audits = await repo.get_audits(
        status=audit_status, audit_type=audit_type, limit=limit, offset=offset
    )

    # Hydrate each audit with its progress stats so the frontend
    # gets the nested `progress` object it expects (pct_complete, etc.)
    results = []
    for a in audits:
        row = dict(a)
        progress = await repo.count_by_result(row["id"])
        row["progress"] = progress
        results.append(row)

    return ApiResponse(data=results)


@router.post("/audit")
async def start_audit(
    req: AuditStartRequest,
    user: dict = Depends(require_permission("perform_audit")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Start a new audit session and populate items from current stock."""
    svc = AuditService(db)
    try:
        audit = await svc.start_audit(
            audit_type=req.audit_type,
            started_by=user["id"],
            location_type=req.location_type,
            location_id=req.location_id,
            category_id=req.category_id,
            part_ids=req.part_ids,
        )
        return ApiResponse(data=audit, message=f"{req.audit_type} audit started")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/audit/suggested-rolling")
async def suggested_rolling_parts(
    limit: int = Query(20, ge=1, le=100),
    user: dict = Depends(require_permission("perform_audit")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get parts suggested for the next rolling audit batch."""
    svc = AuditService(db)
    parts = await svc.get_suggested_rolling_parts(limit=limit)
    return ApiResponse(data=[dict(p) for p in parts])


@router.get("/audit/{audit_id}")
async def get_audit(
    audit_id: int,
    user: dict = Depends(require_permission("perform_audit")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get audit detail with progress stats."""
    from app.repositories.audit_repo import AuditRepo

    repo = AuditRepo(db)
    audit = await repo.get_audit_with_details(audit_id)
    if not audit:
        raise HTTPException(status_code=404, detail="Audit not found")
    return ApiResponse(data=audit)


@router.get("/audit/{audit_id}/next")
async def get_next_audit_item(
    audit_id: int,
    user: dict = Depends(require_permission("perform_audit")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get the next un-counted item for the card-swipe UI."""
    svc = AuditService(db)
    item = await svc.get_next_item(audit_id)
    if not item:
        return ApiResponse(data=None, message="All items have been counted")
    return ApiResponse(data=item)


@router.put("/audit/{audit_id}/items/{item_id}")
async def record_audit_count(
    audit_id: int,
    item_id: int,
    req: AuditCountRequest,
    user: dict = Depends(require_permission("perform_audit")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Record a count for an audit item."""
    svc = AuditService(db)
    success = await svc.record_count(
        audit_id=audit_id,
        item_id=item_id,
        actual_qty=req.actual_qty,
        result=req.result,
        discrepancy_note=req.discrepancy_note,
        photo_path=req.photo_path,
    )
    if not success:
        raise HTTPException(status_code=404, detail="Audit item not found")
    return ApiResponse(data={"recorded": True}, message="Count recorded")


@router.post("/audit/{audit_id}/complete")
async def complete_audit(
    audit_id: int,
    user: dict = Depends(require_permission("perform_audit")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Finalize an audit — mark as completed and return summary."""
    svc = AuditService(db)
    summary = await svc.complete_audit(audit_id)
    return ApiResponse(data=summary, message="Audit completed")


@router.post("/audit/{audit_id}/apply-adjustments")
async def apply_audit_adjustments(
    audit_id: int,
    user: dict = Depends(require_permission("perform_audit")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create stock adjustment movements for all discrepancies in an audit."""
    svc = AuditService(db)
    count = await svc.apply_adjustments(audit_id, user_id=user["id"])
    return ApiResponse(
        data={"adjustments_applied": count},
        message=f"Applied {count} stock adjustments",
    )


# =================================================================
# HELPERS
# =================================================================


@router.get("/locations")
async def get_locations(
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all valid from/to locations for the wizard dropdowns."""
    locations: list[dict] = [
        {"location_type": "warehouse", "location_id": 1,
         "label": "Warehouse", "sub_label": "Main"},
        {"location_type": "pulled", "location_id": 1,
         "label": "Staging Area", "sub_label": "Pulled items"},
    ]

    # Add trucks (table may not exist yet — deferred to Phase 4+)
    try:
        cursor = await db.execute(
            "SELECT id, name FROM trucks WHERE is_active = 1 ORDER BY name"
        )
        trucks = await cursor.fetchall()
        for t in trucks:
            locations.append({
                "location_type": "truck",
                "location_id": t["id"],
                "label": f"Truck #{t['id']}",
                "sub_label": t["name"],
            })
    except Exception:
        # trucks table doesn't exist yet — provide a placeholder
        locations.append({
            "location_type": "truck", "location_id": 1,
            "label": "Truck #1", "sub_label": "Default Truck",
        })

    # Add active jobs (table may not exist yet — deferred to Phase 4+)
    try:
        cursor = await db.execute(
            "SELECT id, name FROM jobs WHERE status = 'active' ORDER BY name"
        )
        jobs = await cursor.fetchall()
        for j in jobs:
            locations.append({
                "location_type": "job",
                "location_id": j["id"],
                "label": f"Job #{j['id']}",
                "sub_label": j["name"],
            })
    except Exception:
        # jobs table doesn't exist yet — provide a placeholder
        locations.append({
            "location_type": "job", "location_id": 1,
            "label": "Job #1", "sub_label": "Default Job",
        })

    return ApiResponse(data=locations)


@router.get("/parts-search")
async def parts_search(
    q: str = Query("", min_length=0, description="Search term"),
    location_type: str | None = Query(None, description="Scope to parts with stock here"),
    location_id: int | None = Query(None),
    limit: int = Query(20, ge=1, le=50),
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Part search scoped to a source location (for wizard Step 2)."""
    svc = WarehouseService(db)
    parts = await svc.search_parts_for_wizard(
        query=q,
        location_type=location_type,
        location_id=location_id,
        limit=limit,
    )
    return ApiResponse(data=parts)


@router.post("/upload-photo")
async def upload_photo(
    file: UploadFile = File(...),
    user: dict = Depends(require_permission("move_stock_warehouse")),
):
    """Upload a verification photo. Returns the file path for later reference."""
    # Ensure upload directory exists
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

    # Generate unique filename
    ext = Path(file.filename or "photo.jpg").suffix or ".jpg"
    unique_name = f"{uuid.uuid4().hex}{ext}"
    file_path = UPLOAD_DIR / unique_name

    # Save file
    contents = await file.read()
    file_path.write_bytes(contents)

    return ApiResponse(
        data={"path": str(file_path), "filename": unique_name},
        message="Photo uploaded",
    )


@router.get("/supplier-preference")
async def get_supplier_preference(
    part_id: int = Query(..., description="Part ID to resolve preferred supplier for"),
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Resolve the preferred supplier for a part (cascade lookup)."""
    from app.repositories.supplier_pref_repo import SupplierPrefRepo

    repo = SupplierPrefRepo(db)
    pref = await repo.resolve_for_part(part_id)
    if not pref:
        return ApiResponse(data=SupplierPreferenceResponse())
    return ApiResponse(data=SupplierPreferenceResponse(**pref))


@router.post("/supplier-preference")
async def set_supplier_preference(
    req: SupplierPreferenceSet,
    user: dict = Depends(require_permission("manage_warehouse")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Set or update the preferred supplier for a scope level."""
    from app.repositories.supplier_pref_repo import SupplierPrefRepo

    repo = SupplierPrefRepo(db)
    pref_id = await repo.set_preference(
        scope_type=req.scope_type,
        scope_id=req.scope_id,
        supplier_id=req.supplier_id,
    )
    return ApiResponse(
        data={"id": pref_id},
        message=f"Preferred supplier set for {req.scope_type} #{req.scope_id}",
    )


@router.delete("/supplier-preference")
async def remove_supplier_preference(
    scope_type: str = Query(...),
    scope_id: int = Query(...),
    user: dict = Depends(require_permission("manage_warehouse")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Remove a preferred supplier for a scope level."""
    from app.repositories.supplier_pref_repo import SupplierPrefRepo

    repo = SupplierPrefRepo(db)
    removed = await repo.remove_preference(scope_type, scope_id)
    if not removed:
        raise HTTPException(status_code=404, detail="Preference not found")
    return ApiResponse(data={"removed": True}, message="Preference removed")


@router.get("/movement-reasons")
async def get_movement_reasons(
    user: dict = Depends(require_user),
):
    """Get the categorized reason options for the movement wizard."""
    return ApiResponse(data=REASON_CATEGORIES)


@router.get("/movement-rules")
async def get_movement_rules(
    user: dict = Depends(require_user),
):
    """Get the valid movement paths and their rules (photo requirements, etc)."""
    # Convert tuple keys to string keys for JSON serialization
    rules = {}
    for (from_loc, to_loc), rule in MOVEMENT_RULES.items():
        rules[f"{from_loc}->{to_loc}"] = {
            **rule,
            "from": from_loc,
            "to": to_loc,
        }
    return ApiResponse(data=rules)
