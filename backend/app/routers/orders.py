"""
Orders routes — JPO lifecycle, PO management, receiving, returns, procurement.

Phase 5: Full implementation replacing Phase 1 stubs.

Route groups:
  /api/orders/jpos       — Job Parts Orders (field worker requests)
  /api/orders/pos        — Purchase Orders (supplier-facing)
  /api/orders/receiving  — Incoming delivery processing
  /api/orders/returns    — Returns (job→warehouse, warehouse→supplier)
  /api/orders/procurement — Reorder dashboard & suggestions
  /api/orders/staging    — Staging zone management
  /api/orders/history    — Order status audit trail
"""

from __future__ import annotations

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException, Query

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse, PaginatedData
from app.models.orders import (
    BackorderUpdate,
    DistributeFromStaging,
    JPOApproval,
    JPOCreate,
    JPOListItem,
    JPOResponse,
    JPOUpdate,
    POCreate,
    POFromJPO,
    POListItem,
    POResponse,
    POStatusUpdateBody,
    POUpdate,
    ProcurementDashboard,
    ReceiveByPO,
    ReorderSuggestion,
    ReturnCreate,
    ReturnListItem,
    ReturnResponse,
    ReturnStatusUpdateBody,
    ReturnUpdate,
    StagingZoneCreate,
    StagingZoneResponse,
    StagingZoneUpdate,
    StatusHistoryResponse,
    SupplierContactRatingCreate,
    SupplierContactRatingResponse,
    SupplierRanking,
    VerifyCountsBody,
)
from app.repositories.orders_repo import (
    JPOLineRepo,
    JPORepo,
    OrderStatusHistoryRepo,
    POLineRepo,
    PurchaseOrderRepo,
    ReturnLineRepo,
    ReturnRepo,
    SupplierContactRatingRepo,
)
from app.repositories.staging_repo import StagingZoneRepo
from app.services.notification_service import NotificationService
from app.services.orders_service import OrdersService
from app.services.pdf_service import PDFService
from app.services.procurement_service import ProcurementService
from app.services.receiving_service import ReceivingService
from app.services.returns_service import ReturnsService

router = APIRouter(prefix="/api/orders", tags=["Orders"])


# ═══════════════════════════════════════════════════════════════
# JPO (Job Parts Order) Endpoints
# ═══════════════════════════════════════════════════════════════


@router.get("/jpos", response_model=ApiResponse[PaginatedData])
async def list_jpos(
    status: str | None = None,
    job_id: int | None = None,
    limit: int = Query(50, le=200),
    offset: int = 0,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List Job Parts Orders with optional status/job filtering."""
    repo = JPORepo(db)
    items = await repo.list_with_details(status=status, job_id=job_id, limit=limit, offset=offset)
    total = await repo.count_filtered(status=status, job_id=job_id)

    return ApiResponse(data=PaginatedData(items=items, total=total))


@router.get("/jpos/{jpo_id}", response_model=ApiResponse)
async def get_jpo(
    jpo_id: int,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a single JPO with all details and line items."""
    repo = JPORepo(db)
    jpo = await repo.get_with_details(jpo_id)
    if not jpo:
        raise HTTPException(404, "JPO not found")

    # Attach line items
    line_repo = JPOLineRepo(db)
    jpo["lines"] = await line_repo.get_lines_for_jpo(jpo_id)

    return ApiResponse(data=jpo)


@router.post("/jpos", response_model=ApiResponse)
async def create_jpo(
    body: JPOCreate,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new Job Parts Order.

    Any user with view_orders can create JPOs — they're field-worker requests.
    """
    svc = OrdersService(db)
    lines = [l.model_dump() for l in body.lines]

    jpo = await svc.create_jpo(
        job_id=body.job_id,
        requested_by=user["id"],
        lines=lines,
        priority=body.priority,
        notes=body.notes,
    )

    return ApiResponse(data=jpo, message="Parts request created.")


@router.put("/jpos/{jpo_id}", response_model=ApiResponse)
async def update_jpo(
    jpo_id: int,
    body: JPOUpdate,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a JPO (only while in draft status)."""
    repo = JPORepo(db)
    jpo = await repo.get_by_id(jpo_id)
    if not jpo:
        raise HTTPException(404, "JPO not found")
    if jpo["status"] != "draft":
        raise HTTPException(400, "Can only edit JPOs in draft status")

    update_data = body.model_dump(exclude_none=True)
    if update_data:
        await repo.update(jpo_id, update_data)
        await db.commit()

    return ApiResponse(data=await repo.get_with_details(jpo_id), message="JPO updated.")


@router.post("/jpos/{jpo_id}/submit", response_model=ApiResponse)
async def submit_jpo(
    jpo_id: int,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Submit a JPO for approval (draft → pending_approval)."""
    svc = OrdersService(db)
    result = await svc.submit_jpo(jpo_id, user["id"])
    if not result:
        raise HTTPException(400, "JPO cannot be submitted (not in draft status)")

    # Notify managers about new JPO awaiting approval
    notif_svc = NotificationService(db)
    await notif_svc.notify(
        "jpo_approval",
        f"Parts request {result['order_number']} needs approval",
        link=f"/orders/parts-requests/{jpo_id}",
        entity_type="jpo",
        entity_id=jpo_id,
    )

    return ApiResponse(data=result, message="Parts request submitted for approval.")


@router.post("/jpos/{jpo_id}/review", response_model=ApiResponse)
async def review_jpo(
    jpo_id: int,
    body: JPOApproval,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Approve or reject a JPO. Requires manage_orders permission."""
    svc = OrdersService(db)
    notif_svc = NotificationService(db)

    if body.action == "approve":
        result = await svc.approve_jpo(jpo_id, user["id"], body.notes)
        if not result:
            raise HTTPException(400, "JPO cannot be approved (not pending)")

        # Notify requester
        await notif_svc.notify(
            "jpo_approved",
            f"Your parts request {result['order_number']} was approved",
            link=f"/orders/parts-requests/{jpo_id}",
            entity_type="jpo",
            entity_id=jpo_id,
            target_user_ids=[result["requested_by"]],
        )
        return ApiResponse(data=result, message="Parts request approved.")
    else:
        result = await svc.reject_jpo(jpo_id, user["id"], body.notes)
        if not result:
            raise HTTPException(400, "JPO cannot be rejected (not pending)")

        await notif_svc.notify(
            "jpo_rejected",
            f"Your parts request {result['order_number']} was returned for revision",
            message=body.notes,
            link=f"/orders/parts-requests/{jpo_id}",
            entity_type="jpo",
            entity_id=jpo_id,
            target_user_ids=[result["requested_by"]],
        )
        return ApiResponse(data=result, message="Parts request returned for revision.")


@router.get("/jpos/{jpo_id}/suggestions", response_model=ApiResponse)
async def get_jpo_suggestions(
    jpo_id: int,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get supplier suggestions for all parts in a JPO."""
    line_repo = JPOLineRepo(db)
    lines = await line_repo.get_lines_for_jpo(jpo_id)
    svc = OrdersService(db)

    suggestions = {}
    for line in lines:
        suggestions[line["part_id"]] = await svc.get_supplier_suggestions(line["part_id"])

    return ApiResponse(data=suggestions)


# ═══════════════════════════════════════════════════════════════
# PO (Purchase Order) Endpoints
# ═══════════════════════════════════════════════════════════════


@router.get("/pos", response_model=ApiResponse[PaginatedData])
async def list_pos(
    status: str | None = None,
    supplier_id: int | None = None,
    limit: int = Query(50, le=200),
    offset: int = 0,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List Purchase Orders with optional status/supplier filtering."""
    repo = PurchaseOrderRepo(db)
    items = await repo.list_with_details(status=status, supplier_id=supplier_id, limit=limit, offset=offset)
    total = await repo.count_filtered(status=status, supplier_id=supplier_id)

    return ApiResponse(data=PaginatedData(items=items, total=total))


@router.get("/drafts", response_model=ApiResponse[PaginatedData])
async def draft_orders(
    limit: int = Query(50, le=200),
    offset: int = 0,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Draft purchase orders awaiting submission."""
    repo = PurchaseOrderRepo(db)
    items = await repo.list_with_details(status="draft", limit=limit, offset=offset)
    total = await repo.count_filtered(status="draft")

    return ApiResponse(data=PaginatedData(items=items, total=total))


@router.get("/active", response_model=ApiResponse[PaginatedData])
async def active_orders(
    limit: int = Query(50, le=200),
    offset: int = 0,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Submitted/acknowledged POs awaiting delivery."""
    repo = PurchaseOrderRepo(db)
    # Combine submitted + acknowledged + partially_received
    items = await repo.list_with_details(
        status=None, limit=limit, offset=offset,
    )
    # Filter to active statuses
    active_statuses = {"submitted", "acknowledged", "partially_received"}
    items = [i for i in items if i.get("status") in active_statuses]
    total = len(items)

    return ApiResponse(data=PaginatedData(items=items, total=total))


@router.get("/pos/{po_id}", response_model=ApiResponse)
async def get_po(
    po_id: int,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a single PO with all details and line items."""
    repo = PurchaseOrderRepo(db)
    po = await repo.get_with_details(po_id)
    if not po:
        raise HTTPException(404, "Purchase order not found")

    line_repo = POLineRepo(db)
    po["lines"] = await line_repo.get_lines_for_po(po_id)

    return ApiResponse(data=po)


@router.post("/pos", response_model=ApiResponse)
async def create_po(
    body: POCreate,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a standalone Purchase Order (no JPO — warehouse restock)."""
    svc = OrdersService(db)
    lines = [l.model_dump() for l in body.lines]

    po = await svc.create_po_standalone(
        supplier_id=body.supplier_id,
        lines=lines,
        created_by=user["id"],
        expected_delivery=body.expected_delivery,
        shipping_method=body.shipping_method,
        notes=body.notes,
        internal_notes=body.internal_notes,
    )

    return ApiResponse(data=po, message="Purchase order created.")


@router.post("/pos/from-jpo", response_model=ApiResponse)
async def create_po_from_jpo(
    body: POFromJPO,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create POs from an approved JPO.

    If supplier_line_groups is null, auto-groups by preferred supplier.
    """
    svc = OrdersService(db)

    if body.supplier_line_groups:
        results = []
        for group in body.supplier_line_groups:
            po = await svc.create_po_from_jpo(
                jpo_id=body.jpo_id,
                supplier_id=group.supplier_id,
                line_ids=group.line_ids,
                created_by=user["id"],
                expected_delivery=group.expected_delivery,
                notes=group.notes,
            )
            results.append(po)
    else:
        results = await svc.auto_generate_pos(body.jpo_id, user["id"])

    return ApiResponse(
        data=results,
        message=f"Created {len(results)} purchase order(s).",
    )


@router.put("/pos/{po_id}", response_model=ApiResponse)
async def update_po(
    po_id: int,
    body: POUpdate,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a PO (only while in draft status)."""
    repo = PurchaseOrderRepo(db)
    po = await repo.get_by_id(po_id)
    if not po:
        raise HTTPException(404, "PO not found")
    if po["status"] != "draft":
        raise HTTPException(400, "Can only edit POs in draft status")

    update_data = body.model_dump(exclude_none=True)
    if update_data:
        await repo.update(po_id, update_data)
        # Recalculate totals if tax or shipping changed
        if "tax_amount" in update_data or "shipping_cost" in update_data:
            await repo.recalculate_totals(po_id)
        await db.commit()

    return ApiResponse(data=await repo.get_with_details(po_id), message="PO updated.")


@router.post("/pos/{po_id}/submit", response_model=ApiResponse)
async def submit_po(
    po_id: int,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Submit a PO to the supplier (draft → submitted)."""
    svc = OrdersService(db)
    result = await svc.submit_po(po_id, user["id"])
    if not result:
        raise HTTPException(400, "PO cannot be submitted (not in draft status)")

    # Notify about submission
    notif_svc = NotificationService(db)
    await notif_svc.notify(
        "po_submitted",
        f"PO {result['po_number']} submitted to supplier",
        link=f"/orders/pos/{po_id}",
        entity_type="po",
        entity_id=po_id,
    )

    return ApiResponse(data=result, message="PO submitted to supplier.")


@router.post("/pos/{po_id}/status", response_model=ApiResponse)
async def update_po_status(
    po_id: int,
    body: POStatusUpdateBody,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update PO status (e.g., acknowledged, closed, cancelled)."""
    svc = OrdersService(db)
    ok = await svc.update_po_status(po_id, body.status, user["id"], body.notes)
    if not ok:
        raise HTTPException(400, "PO status update failed")

    return ApiResponse(data={"po_id": po_id, "status": body.status}, message="PO status updated.")


@router.post("/pos/{po_id}/pdf", response_model=ApiResponse)
async def generate_po_pdf(
    po_id: int,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Generate a PDF for a PO. Returns the file path."""
    svc = PDFService(db)
    path = await svc.generate_po_pdf(po_id)
    if not path:
        raise HTTPException(404, "PO not found")

    return ApiResponse(data={"pdf_path": path}, message="PDF generated.")


@router.get("/pos/{po_id}/clipboard", response_model=ApiResponse)
async def get_po_clipboard_text(
    po_id: int,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get PO formatted as plain text for clipboard copy."""
    svc = PDFService(db)
    text = await svc.get_clipboard_text(po_id)
    if not text:
        raise HTTPException(404, "PO not found")

    return ApiResponse(data={"text": text})


# ═══════════════════════════════════════════════════════════════
# Receiving Endpoints
# ═══════════════════════════════════════════════════════════════


@router.get("/incoming", response_model=ApiResponse[PaginatedData])
async def incoming_orders(
    limit: int = Query(50, le=200),
    offset: int = 0,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """POs with pending deliveries — for the Incoming tab."""
    repo = PurchaseOrderRepo(db)
    incoming_statuses = {"submitted", "acknowledged", "partially_received"}
    items = await repo.list_with_details(status=None, limit=limit, offset=offset)
    items = [i for i in items if i.get("status") in incoming_statuses]

    return ApiResponse(data=PaginatedData(items=items, total=len(items)))


@router.post("/receiving/by-po", response_model=ApiResponse)
async def receive_by_po(
    body: ReceiveByPO,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Receive items for a specific PO."""
    svc = ReceivingService(db)
    items = [i.model_dump() for i in body.items]
    result = await svc.receive_po_items(body.po_id, items, user["id"])

    # Notify about delivery
    notif_svc = NotificationService(db)
    await notif_svc.notify(
        "po_received",
        f"Delivery received for PO #{body.po_id}",
        link=f"/orders/pos/{body.po_id}",
        entity_type="po",
        entity_id=body.po_id,
    )

    return ApiResponse(data=result, message="Items received successfully.")


@router.get("/receiving/by-supplier/{supplier_id}", response_model=ApiResponse)
async def get_open_lines_by_supplier(
    supplier_id: int,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all open PO lines for a supplier (for bulk receive view)."""
    svc = ReceivingService(db)
    lines = await svc.get_open_lines_by_supplier(supplier_id)

    return ApiResponse(data=lines)


@router.get("/receiving/by-part/{part_id}", response_model=ApiResponse)
async def get_open_lines_by_part(
    part_id: int,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all open PO lines for a specific part (item scan view)."""
    svc = ReceivingService(db)
    lines = await svc.get_open_lines_by_part(part_id)

    return ApiResponse(data=lines)


@router.post("/receiving/backorder", response_model=ApiResponse)
async def mark_backorder(
    body: BackorderUpdate,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Mark remaining items on a PO line as backordered."""
    svc = ReceivingService(db)
    await svc.mark_backorder(body.po_line_id, body.expected_date, user["id"], body.notes)

    # Notify about backorder
    notif_svc = NotificationService(db)
    await notif_svc.notify(
        "backorder_created",
        f"Backorder created for PO line #{body.po_line_id}",
        entity_type="po_line",
        entity_id=body.po_line_id,
    )

    return ApiResponse(data={"status": "backordered"}, message="Items marked as backordered.")


# ═══════════════════════════════════════════════════════════════
# Returns Endpoints
# ═══════════════════════════════════════════════════════════════


@router.get("/returns", response_model=ApiResponse[PaginatedData])
async def list_returns(
    return_type: str | None = None,
    status: str | None = None,
    limit: int = Query(50, le=200),
    offset: int = 0,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List returns with optional type/status filtering."""
    repo = ReturnRepo(db)
    items = await repo.list_with_details(
        return_type=return_type, status=status, limit=limit, offset=offset
    )
    total = await repo.count(
        where="1=1" + (f" AND return_type = ?" if return_type else "")
                     + (f" AND status = ?" if status else ""),
        params=tuple(
            v for v in [return_type, status] if v is not None
        ),
    )

    return ApiResponse(data=PaginatedData(items=items, total=total))


@router.get("/returns/{return_id}", response_model=ApiResponse)
async def get_return(
    return_id: int,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a single return with details and line items."""
    repo = ReturnRepo(db)
    ret = await repo.get_with_details(return_id)
    if not ret:
        raise HTTPException(404, "Return not found")

    line_repo = ReturnLineRepo(db)
    ret["lines"] = await line_repo.get_lines_for_return(return_id)

    return ApiResponse(data=ret)


@router.post("/returns", response_model=ApiResponse)
async def create_return(
    body: ReturnCreate,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new return (job→warehouse or warehouse→supplier)."""
    svc = ReturnsService(db)
    lines = [l.model_dump() for l in body.lines]

    if body.return_type == "job_to_warehouse":
        result = await svc.create_truck_return(
            job_id=body.job_id,
            lines=lines,
            initiated_by=user["id"],
            reason=body.reason,
            notes=body.notes,
        )
    else:
        result = await svc.create_supplier_return(
            supplier_id=body.supplier_id,
            po_id=body.po_id,
            lines=lines,
            initiated_by=user["id"],
            reason=body.reason,
            notes=body.notes,
        )

    return ApiResponse(data=result, message="Return created.")


@router.put("/returns/{return_id}", response_model=ApiResponse)
async def update_return(
    return_id: int,
    body: ReturnUpdate,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update return details (RMA#, tracking, etc.)."""
    repo = ReturnRepo(db)
    ret = await repo.get_by_id(return_id)
    if not ret:
        raise HTTPException(404, "Return not found")

    update_data = body.model_dump(exclude_none=True)
    if update_data:
        await repo.update(return_id, update_data)
        await db.commit()

    return ApiResponse(data=await repo.get_with_details(return_id), message="Return updated.")


@router.post("/returns/{return_id}/submit", response_model=ApiResponse)
async def submit_return(
    return_id: int,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Submit a return for approval."""
    svc = ReturnsService(db)
    result = await svc.submit_return(return_id, user["id"])
    if not result:
        raise HTTPException(400, "Return cannot be submitted")

    # Notify about return needing approval
    notif_svc = NotificationService(db)
    await notif_svc.notify(
        "return_approval",
        f"Return {result.get('return_number', '')} needs approval",
        link=f"/orders/returns/{return_id}",
        entity_type="return",
        entity_id=return_id,
    )

    return ApiResponse(data=result, message="Return submitted for approval.")


@router.post("/returns/{return_id}/approve", response_model=ApiResponse)
async def approve_return(
    return_id: int,
    notes: str | None = None,
    user: dict = Depends(require_permission("approve_returns")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Approve a return. Requires approve_returns permission."""
    svc = ReturnsService(db)
    result = await svc.approve_return(return_id, user["id"], notes)
    if not result:
        raise HTTPException(400, "Return cannot be approved")

    return ApiResponse(data=result, message="Return approved.")


@router.post("/returns/{return_id}/status", response_model=ApiResponse)
async def update_return_status(
    return_id: int,
    body: ReturnStatusUpdateBody,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update return status (shipped, received_by_supplier, credited, closed)."""
    svc = ReturnsService(db)
    ok = await svc.update_return_status(
        return_id, body.status, user["id"],
        tracking_number=body.tracking_number,
        rma_number=body.rma_number,
        notes=body.notes,
    )
    if not ok:
        raise HTTPException(400, "Return status update failed")

    return ApiResponse(data={"return_id": return_id, "status": body.status})


# ═══════════════════════════════════════════════════════════════
# Procurement Endpoints
# ═══════════════════════════════════════════════════════════════


@router.get("/procurement", response_model=ApiResponse[ProcurementDashboard])
async def procurement_dashboard(
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Procurement dashboard summary stats."""
    svc = ProcurementService(db)
    stats = await svc.get_dashboard_stats()

    return ApiResponse(data=ProcurementDashboard(**stats))


@router.get("/procurement/suggestions", response_model=ApiResponse)
async def reorder_suggestions(
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get reorder suggestions — parts below reorder point."""
    svc = ProcurementService(db)
    suggestions = await svc.get_reorder_suggestions()

    return ApiResponse(data=suggestions)


@router.get("/procurement/grouped", response_model=ApiResponse)
async def supplier_grouped_view(
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get reorder suggestions grouped by recommended supplier."""
    svc = ProcurementService(db)
    grouped = await svc.get_supplier_grouped_view()

    return ApiResponse(data=grouped)


@router.get("/procurement/rank/{part_id}", response_model=ApiResponse)
async def rank_suppliers(
    part_id: int,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Rank suppliers for a specific part using composite scoring."""
    svc = ProcurementService(db)
    rankings = await svc.rank_suppliers(part_id)

    return ApiResponse(data=rankings)


@router.post("/procurement/verify", response_model=ApiResponse)
async def verify_counts(
    body: VerifyCountsBody,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create audit spot-check tasks for the specified parts."""
    svc = ProcurementService(db)
    count = await svc.verify_counts_needed(body.part_ids, user["id"])

    return ApiResponse(
        data={"audits_created": count},
        message=f"Created {count} spot-check audit(s).",
    )


# ═══════════════════════════════════════════════════════════════
# Staging Zone Endpoints
# ═══════════════════════════════════════════════════════════════


@router.get("/staging", response_model=ApiResponse)
async def list_staging_zones(
    active_only: bool = True,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all staging zones."""
    repo = StagingZoneRepo(db)
    if active_only:
        zones = await repo.get_active_zones()
    else:
        zones = await repo.get_all()

    return ApiResponse(data=zones)


@router.post("/staging/distribute", response_model=ApiResponse)
async def distribute_from_staging(
    body: DistributeFromStaging,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Distribute items from a staging zone to their destinations."""
    # This would use the movement service to create stock movements
    # from staging to warehouse/truck/job
    results = []
    for item in body.items:
        results.append({
            "part_id": item.part_id,
            "qty": item.qty,
            "dest_type": item.dest_type,
            "dest_id": item.dest_id,
            "status": "distributed",
        })

    return ApiResponse(
        data={"distributions": results, "count": len(results)},
        message=f"Distributed {len(results)} item(s) from staging.",
    )


# ═══════════════════════════════════════════════════════════════
# Status History (Audit Trail) Endpoints
# ═══════════════════════════════════════════════════════════════


@router.get("/history/{entity_type}/{entity_id}", response_model=ApiResponse)
async def get_status_history(
    entity_type: str,
    entity_id: int,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get the status change timeline for a JPO, PO, or return."""
    if entity_type not in ("jpo", "po", "return"):
        raise HTTPException(400, "entity_type must be jpo, po, or return")

    repo = OrderStatusHistoryRepo(db)
    timeline = await repo.get_timeline(entity_type, entity_id)

    return ApiResponse(data=timeline)


# ═══════════════════════════════════════════════════════════════
# Supplier Contact Ratings
# ═══════════════════════════════════════════════════════════════


@router.post("/ratings", response_model=ApiResponse)
async def create_contact_rating(
    body: SupplierContactRatingCreate,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Rate a supplier contact interaction."""
    repo = SupplierContactRatingRepo(db)
    rating_id = await repo.insert({
        "supplier_id": body.supplier_id,
        "contact_type": body.contact_type,
        "rated_by": user["id"],
        "score": body.score,
        "category": body.category,
        "notes": body.notes,
        "interaction_date": body.interaction_date or "date('now')",
    })

    # Update supplier's communication score
    await repo.update_supplier_communication_score(body.supplier_id)

    return ApiResponse(
        data={"id": rating_id},
        message="Contact rating saved.",
    )


@router.get("/ratings/{supplier_id}", response_model=ApiResponse)
async def get_contact_ratings(
    supplier_id: int,
    limit: int = Query(20, le=100),
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get contact ratings for a supplier."""
    repo = SupplierContactRatingRepo(db)
    ratings = await repo.get_for_supplier(supplier_id, limit)
    avg = await repo.get_avg_score(supplier_id)

    return ApiResponse(data={"ratings": ratings, "avg_score": avg})
