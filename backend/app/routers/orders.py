"""
Orders routes — JPO lifecycle, PO management, receiving, returns, procurement.

Phase 5: Full implementation replacing Phase 1 stubs.
Phase 7B: Conversations, PO groups, approvals queue, confirmation checklist.
Phase 7C: Session-based receiving, return sorting guidance.

Route groups:
  /api/orders/jpos             — Job Parts Orders (field worker requests)
  /api/orders/pos              — Purchase Orders (supplier-facing)
  /api/orders/pos/{id}/conv    — PO conversation threads (Phase 7B)
  /api/orders/pos/group        — PO groups for bundled sending (Phase 7B)
  /api/orders/office           — Office approval queue (Phase 7B)
  /api/orders/receiving        — Incoming delivery processing (legacy)
  /api/orders/receiving/sessions — Session-based receiving (Phase 7C)
  /api/orders/returns          — Returns (job→warehouse, warehouse→supplier)
  /api/orders/returns/{id}/sorting — Return sorting guidance (Phase 7C)
  /api/orders/procurement      — Reorder dashboard & suggestions
  /api/orders/staging          — Staging zone management
  /api/orders/history          — Order status audit trail
"""

from __future__ import annotations

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException, Query

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse, PaginatedData
from app.models.orders import (
    BackorderUpdate,
    BulkApprovalAction,
    BulkPOStatusUpdate,
    BulkPOSubmit,
    BulkReturnApprove,
    ConfirmationChecklistUpdate,
    DistributeFromStaging,
    JPOApproval,
    JPOCreate,
    JPOListItem,
    JPOResponse,
    JPOUpdate,
    POConversationCreate,
    POConversationFollowUp,
    POCreate,
    POFromJPO,
    POGroupCreate,
    POListItem,
    POResponse,
    POStatusUpdateBody,
    POUpdate,
    ProcurementDashboard,
    ReceiveByPO,
    # Phase 7C: Session-based receiving models
    ReceivingSessionCommit,
    ReceivingSessionCreate,
    ReceivingSessionItemUpdate,
    ReceivingSessionResponse,
    ReorderSuggestion,
    ReturnCreate,
    ReturnListItem,
    ReturnResponse,
    # Phase 7C: Return sorting models
    ReturnSortingRequest,
    ReturnStatusUpdateBody,
    ReturnUpdate,
    SpecialItemCreate,
    SpecialItemResolve,
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
from app.services.po_conversation_service import POConversationService
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
    order_type: str | None = None,
    requested_by: int | None = None,
    limit: int = Query(50, le=200),
    offset: int = 0,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List Job Parts Orders with optional filters.

    Filters:
      - status:       JPO workflow status
      - job_id:       specific job
      - order_type:   'job' or 'warehouse'
      - requested_by: user ID of the requester (for "My Orders" view)
    """
    repo = JPORepo(db)
    items = await repo.list_with_details(
        status=status, job_id=job_id, order_type=order_type,
        requested_by=requested_by, limit=limit, offset=offset,
    )
    total = await repo.count_filtered(
        status=status, job_id=job_id, order_type=order_type,
        requested_by=requested_by,
    )

    return ApiResponse(data=PaginatedData(items=items, total=total))


@router.get("/jpos/{jpo_id}", response_model=ApiResponse)
async def get_jpo(
    jpo_id: int,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a single JPO with all details, line items, and special items."""
    repo = JPORepo(db)
    jpo = await repo.get_with_details(jpo_id)
    if not jpo:
        raise HTTPException(404, "JPO not found")

    # Attach catalog line items
    line_repo = JPOLineRepo(db)
    jpo["lines"] = await line_repo.get_lines_for_jpo(jpo_id)

    # Attach special (non-catalog) items — Phase 7A
    from app.services.job_preferences_service import JobPreferencesService
    prefs_svc = JobPreferencesService(db)
    jpo["special_items"] = await prefs_svc.get_special_items(jpo_id)

    return ApiResponse(data=jpo)


@router.post("/jpos", response_model=ApiResponse)
async def create_jpo(
    body: JPOCreate,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a unified order — Job Parts Order or Warehouse Restock.

    Any user with view_orders can create job orders.
    Warehouse restocks require the same permission (office staff always have it).

    The order_type field controls the flow:
      - 'job'       → requires job_id, learns preferences after creation
      - 'warehouse'  → job_id must be null, no preference learning
    """
    svc = OrdersService(db)
    lines = [l.model_dump() for l in body.lines]
    special = [s.model_dump() for s in body.special_items] if body.special_items else None

    try:
        jpo = await svc.create_jpo(
            requested_by=user["id"],
            lines=lines,
            job_id=body.job_id,
            order_type=body.order_type,
            priority=body.priority,
            smart_suggestions_enabled=body.smart_suggestions_enabled,
            notes=body.notes,
            special_items=special,
        )
    except ValueError as exc:
        raise HTTPException(422, str(exc))

    label = "Parts request created." if body.order_type == "job" else "Warehouse restock created."
    return ApiResponse(data=jpo, message=label)


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
# Special Items — non-catalog items on orders (Phase 7A)
# ═══════════════════════════════════════════════════════════════


@router.get("/jpos/{jpo_id}/special-items", response_model=ApiResponse)
async def list_special_items(
    jpo_id: int,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List special (non-catalog) items on a JPO.

    Special items are free-text entries that field workers add when a
    needed part isn't in the catalog.  They're auto-flagged for office
    review — office staff can then link them to existing catalog parts
    or order them as-is.
    """
    from app.services.job_preferences_service import JobPreferencesService
    svc = JobPreferencesService(db)
    items = await svc.get_special_items(jpo_id)
    return ApiResponse(data=items)


@router.post("/jpos/{jpo_id}/special-items", response_model=ApiResponse)
async def add_special_item(
    jpo_id: int,
    body: SpecialItemCreate,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Add a special (non-catalog) item to a JPO.

    Auto-flagged for office review.  The JPO's `has_special_items`
    flag is set automatically.
    """
    # Verify JPO exists and is editable
    repo = JPORepo(db)
    jpo = await repo.get_by_id(jpo_id)
    if not jpo:
        raise HTTPException(404, "JPO not found")
    if jpo["status"] not in ("draft", "pending_approval"):
        raise HTTPException(400, "Cannot add items to a JPO in this status")

    from app.services.job_preferences_service import JobPreferencesService
    svc = JobPreferencesService(db)
    item_id = await svc.add_special_item(
        jpo_id,
        description=body.description,
        quantity=body.quantity,
        part_number=body.part_number,
        unit=body.unit,
        estimated_cost=body.estimated_cost,
        notes=body.notes,
    )

    return ApiResponse(
        data={"id": item_id, "jpo_id": jpo_id},
        message="Special item added and flagged for review.",
    )


@router.put("/special-items/{item_id}/resolve", response_model=ApiResponse)
async def resolve_special_item(
    item_id: int,
    body: SpecialItemResolve,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Office resolves a flagged special item.

    Optionally links it to an existing catalog part.  Clears the flag
    and records who resolved it and when.
    """
    from app.services.job_preferences_service import JobPreferencesService
    svc = JobPreferencesService(db)
    success = await svc.resolve_special_item(
        item_id, resolved_by=user["id"], linked_part_id=body.linked_part_id,
    )
    if not success:
        raise HTTPException(404, "Special item not found or already resolved")

    return ApiResponse(
        data={"id": item_id, "resolved": True},
        message="Special item resolved.",
    )


@router.get("/special-items/flagged", response_model=ApiResponse)
async def list_flagged_special_items(
    limit: int = Query(50, le=200),
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all unresolved flagged special items across all JPOs.

    Used by the office Approvals tab to see items needing attention.
    """
    from app.services.job_preferences_service import JobPreferencesService
    svc = JobPreferencesService(db)
    items = await svc.get_flagged_items(limit=limit)
    return ApiResponse(data=items)


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
# PO Conversation Threads (Phase 7B)
# ═══════════════════════════════════════════════════════════════


@router.get("/pos/{po_id}/conversation", response_model=ApiResponse)
async def get_po_conversation(
    po_id: int,
    limit: int = Query(100, le=500),
    offset: int = 0,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get the conversation thread for a PO.

    Returns all entries (notes, calls, emails, system events) in
    reverse chronological order.  Each entry includes the creator's
    display name.
    """
    svc = POConversationService(db)
    entries = await svc.get_thread(po_id, limit=limit, offset=offset)
    return ApiResponse(data=entries)


@router.post("/pos/{po_id}/conversation", response_model=ApiResponse)
async def add_po_conversation_entry(
    po_id: int,
    body: POConversationCreate,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Add a manual conversation entry to a PO.

    Entry types: note, call, email_summary, action.
    System entries are auto-created by the backend — don't use this
    endpoint for those.
    """
    svc = POConversationService(db)
    entry_id = await svc.add_entry(
        po_id=po_id,
        entry_type=body.entry_type,
        message=body.message,
        user_id=user["id"],
        follow_up_needed=body.follow_up_needed,
    )

    return ApiResponse(
        data={"id": entry_id, "po_id": po_id},
        message="Conversation entry added.",
    )


@router.get("/suppliers/{supplier_id}/conversation", response_model=ApiResponse)
async def get_supplier_conversation(
    supplier_id: int,
    limit: int = Query(100, le=500),
    offset: int = 0,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all conversation entries across POs for a supplier.

    Aggregates threads from all POs with this supplier.  Each entry
    includes the PO number for cross-referencing.
    """
    svc = POConversationService(db)
    entries = await svc.get_supplier_thread(
        supplier_id, limit=limit, offset=offset,
    )
    return ApiResponse(data=entries)


@router.put("/conversation/{entry_id}/follow-up", response_model=ApiResponse)
async def toggle_conversation_follow_up(
    entry_id: int,
    body: POConversationFollowUp,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Toggle the follow-up resolved status on a conversation entry.

    Set resolved=true to mark a follow-up as done.  Set resolved=false
    to re-open it.
    """
    svc = POConversationService(db)
    ok = await svc.toggle_follow_up(entry_id, body.resolved)
    if not ok:
        raise HTTPException(404, "Conversation entry not found or has no follow-up flag")

    status = "resolved" if body.resolved else "reopened"
    return ApiResponse(
        data={"entry_id": entry_id, "resolved": body.resolved},
        message=f"Follow-up {status}.",
    )


@router.get("/conversation/follow-ups", response_model=ApiResponse)
async def list_open_follow_ups(
    supplier_id: int | None = None,
    limit: int = Query(50, le=200),
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all open (unresolved) follow-ups across POs.

    Optionally filter by supplier.  Used by the Office dashboard to
    surface pending action items.
    """
    svc = POConversationService(db)
    items = await svc.get_open_follow_ups(supplier_id=supplier_id, limit=limit)

    return ApiResponse(data=items)


# ═══════════════════════════════════════════════════════════════
# PO Groups — bundle POs for combined sending (Phase 7B)
# ═══════════════════════════════════════════════════════════════


@router.post("/pos/group", response_model=ApiResponse)
async def create_po_group(
    body: POGroupCreate,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a PO group for bundled sending to a supplier.

    All POs in the group must belong to the specified supplier.
    If no group_name is provided, one is auto-generated.
    """
    svc = POConversationService(db)
    try:
        group = await svc.create_group(
            supplier_id=body.supplier_id,
            po_ids=body.po_ids,
            user_id=user["id"],
            group_name=body.group_name,
        )
    except ValueError as exc:
        raise HTTPException(422, str(exc))

    return ApiResponse(data=group, message="PO group created.")


@router.get("/pos/group/{group_id}", response_model=ApiResponse)
async def get_po_group(
    group_id: int,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a PO group with all its member POs."""
    svc = POConversationService(db)
    group = await svc.get_group(group_id)
    if not group:
        raise HTTPException(404, "PO group not found")

    return ApiResponse(data=group)


@router.get("/pos/groups/by-supplier/{supplier_id}", response_model=ApiResponse)
async def list_po_groups_for_supplier(
    supplier_id: int,
    limit: int = Query(20, le=100),
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List PO groups for a supplier (compact list format)."""
    svc = POConversationService(db)
    groups = await svc.list_groups_for_supplier(supplier_id, limit=limit)

    return ApiResponse(data=groups)


# ═══════════════════════════════════════════════════════════════
# Office Approvals Queue (Phase 7B)
# ═══════════════════════════════════════════════════════════════


@router.get("/office/pending-approvals", response_model=ApiResponse)
async def get_pending_approvals(
    limit: int = Query(50, le=200),
    offset: int = 0,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all pending JPOs and returns for the office approval queue.

    Returns a unified list sorted by created_at (oldest first — FIFO).
    Each item has `entity_type` ('jpo' or 'return') to identify the type.
    """
    svc = POConversationService(db)
    items = await svc.get_pending_approvals(limit=limit, offset=offset)

    return ApiResponse(data=items)


@router.get("/office/pending-approvals/count", response_model=ApiResponse)
async def count_pending_approvals(
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Count pending items by type for the Approvals tab badge.

    Returns: {jpo_count, return_count, total}
    """
    svc = POConversationService(db)
    counts = await svc.count_pending_approvals()

    return ApiResponse(data=counts)


@router.post("/office/bulk-approve", response_model=ApiResponse)
async def bulk_approve_or_reject(
    body: BulkApprovalAction,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Bulk approve or reject multiple JPOs and/or returns.

    Processes each item independently so partial success is possible.
    Returns per-item results with success/failure status.
    """
    svc = OrdersService(db)
    returns_svc = ReturnsService(db)
    notif_svc = NotificationService(db)

    results = []
    for target in body.items:
        try:
            if target.entity_type == "jpo":
                if body.action == "approve":
                    result = await svc.approve_jpo(target.entity_id, user["id"], body.notes)
                else:
                    result = await svc.reject_jpo(target.entity_id, user["id"], body.notes)

                if result:
                    # Notify the requester
                    action_label = "approved" if body.action == "approve" else "returned for revision"
                    await notif_svc.notify(
                        f"jpo_{body.action}d",
                        f"Your parts request {result.get('order_number', '')} was {action_label}",
                        message=body.notes,
                        link=f"/orders/parts-requests/{target.entity_id}",
                        entity_type="jpo",
                        entity_id=target.entity_id,
                        target_user_ids=[result["requested_by"]],
                    )
                    results.append({
                        "entity_type": "jpo",
                        "entity_id": target.entity_id,
                        "success": True,
                        "action": body.action,
                    })
                else:
                    results.append({
                        "entity_type": "jpo",
                        "entity_id": target.entity_id,
                        "success": False,
                        "error": "Not in pending status",
                    })

            elif target.entity_type == "return":
                if body.action == "approve":
                    result = await returns_svc.approve_return(
                        target.entity_id, user["id"], body.notes,
                    )
                else:
                    # Returns don't have a "reject" flow — we move to rejected status
                    result = await returns_svc.update_return_status(
                        target.entity_id, "rejected", user["id"], notes=body.notes,
                    )

                results.append({
                    "entity_type": "return",
                    "entity_id": target.entity_id,
                    "success": bool(result),
                    "action": body.action,
                    "error": None if result else "Not in pending status",
                })

        except Exception as exc:
            results.append({
                "entity_type": target.entity_type,
                "entity_id": target.entity_id,
                "success": False,
                "error": str(exc),
            })

    succeeded = sum(1 for r in results if r["success"])
    failed = len(results) - succeeded

    msg = f"{succeeded} item(s) {body.action}d"
    if failed:
        msg += f", {failed} failed"

    return ApiResponse(data={"results": results}, message=msg)


# ═══════════════════════════════════════════════════════════════
# Bulk PO Actions (Phase 7E)
# ═══════════════════════════════════════════════════════════════


@router.post("/pos/bulk-submit", response_model=ApiResponse)
async def bulk_submit_pos(
    body: BulkPOSubmit,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Submit multiple draft POs to suppliers at once.

    Each PO is submitted independently — partial success is possible.
    Only POs in 'draft' status will be submitted; others are skipped.
    """
    svc = OrdersService(db)
    notif_svc = NotificationService(db)

    results = []
    for po_id in body.po_ids:
        try:
            result = await svc.submit_po(po_id, user["id"])
            if result:
                # Notify relevant users
                await notif_svc.notify(
                    "po_submitted",
                    f"PO {result.get('po_number', '')} submitted to {result.get('supplier_name', 'supplier')}",
                    message=body.notes,
                    link=f"/orders/purchase-orders/{po_id}",
                    entity_type="po",
                    entity_id=po_id,
                )
                results.append({"po_id": po_id, "success": True})
            else:
                results.append({
                    "po_id": po_id,
                    "success": False,
                    "error": "Not in draft status or not found",
                })
        except Exception as exc:
            results.append({"po_id": po_id, "success": False, "error": str(exc)})

    succeeded = sum(1 for r in results if r["success"])
    failed = len(results) - succeeded

    msg = f"{succeeded} PO(s) submitted"
    if failed:
        msg += f", {failed} failed"

    return ApiResponse(data={"results": results}, message=msg)


@router.post("/pos/bulk-status", response_model=ApiResponse)
async def bulk_update_po_status(
    body: BulkPOStatusUpdate,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update status on multiple POs at once.

    Valid statuses: submitted, confirmed, shipped, delivered, cancelled.
    Each PO is updated independently — partial success is possible.
    """
    svc = OrdersService(db)

    results = []
    for po_id in body.po_ids:
        try:
            ok = await svc.update_po_status(
                po_id, body.status, user["id"], notes=body.notes,
            )
            results.append({
                "po_id": po_id,
                "success": ok,
                "error": None if ok else "PO not found",
            })
        except Exception as exc:
            results.append({"po_id": po_id, "success": False, "error": str(exc)})

    succeeded = sum(1 for r in results if r["success"])
    failed = len(results) - succeeded

    msg = f"{succeeded} PO(s) updated to '{body.status}'"
    if failed:
        msg += f", {failed} failed"

    return ApiResponse(data={"results": results}, message=msg)


@router.post("/returns/bulk-approve", response_model=ApiResponse)
async def bulk_approve_returns(
    body: BulkReturnApprove,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Approve multiple pending returns at once.

    Only returns in 'pending' status will be approved; others are skipped.
    Each return is approved independently — partial success is possible.
    """
    returns_svc = ReturnsService(db)
    notif_svc = NotificationService(db)

    results = []
    for return_id in body.return_ids:
        try:
            result = await returns_svc.approve_return(
                return_id, user["id"], body.notes,
            )
            if result:
                await notif_svc.notify(
                    "return_approval",
                    f"Return #{return_id} has been approved",
                    message=body.notes,
                    link=f"/orders/returns/{return_id}",
                    entity_type="return",
                    entity_id=return_id,
                )
                results.append({"return_id": return_id, "success": True})
            else:
                results.append({
                    "return_id": return_id,
                    "success": False,
                    "error": "Not in pending status or not found",
                })
        except Exception as exc:
            results.append({
                "return_id": return_id,
                "success": False,
                "error": str(exc),
            })

    succeeded = sum(1 for r in results if r["success"])
    failed = len(results) - succeeded

    msg = f"{succeeded} return(s) approved"
    if failed:
        msg += f", {failed} failed"

    return ApiResponse(data={"results": results}, message=msg)


# ═══════════════════════════════════════════════════════════════
# PO Confirmation Checklist (Phase 7B)
# ═══════════════════════════════════════════════════════════════


@router.get("/pos/{po_id}/confirmation-checklist", response_model=ApiResponse)
async def get_confirmation_checklist(
    po_id: int,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get the confirmation checklist for a PO.

    Each line item has a confirmed/unconfirmed status.  The checklist
    is auto-generated from the PO's line items on first access.
    """
    svc = POConversationService(db)
    checklist = await svc.get_confirmation_checklist(po_id)

    return ApiResponse(data=checklist)


@router.post("/pos/{po_id}/confirmation-checklist", response_model=ApiResponse)
async def update_confirmation_checklist(
    po_id: int,
    body: ConfirmationChecklistUpdate,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update the confirmation checklist for a PO.

    Send the full checklist with confirmed flags.  Newly confirmed
    items are stamped with the current user and timestamp.
    """
    svc = POConversationService(db)
    checklist_dicts = [item.model_dump() for item in body.checklist]
    updated = await svc.update_confirmation_checklist(
        po_id, checklist_dicts, user["id"],
    )

    confirmed_count = sum(1 for item in updated if item.get("confirmed"))
    total_count = len(updated)

    return ApiResponse(
        data=updated,
        message=f"Checklist updated ({confirmed_count}/{total_count} confirmed).",
    )


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
# Receiving Sessions (Phase 7C) — session-based packing slip / scan
# ═══════════════════════════════════════════════════════════════


@router.post("/receiving/sessions", response_model=ApiResponse[ReceivingSessionResponse])
async def start_receiving_session(
    body: ReceivingSessionCreate,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Start a new receiving session for a PO.

    Creates the session and pre-populates items from the PO's open lines.
    The session stays in 'in_progress' until committed or cancelled.
    """
    svc = ReceivingService(db)
    try:
        session = await svc.start_session(
            po_id=body.po_id,
            mode=body.mode,
            user_id=user["id"],
            notes=body.notes,
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc))

    return ApiResponse(
        data=ReceivingSessionResponse(**session),
        message=f"Receiving session started in {body.mode} mode.",
    )


@router.get("/receiving/sessions", response_model=ApiResponse[PaginatedData])
async def list_receiving_sessions(
    po_id: int | None = None,
    status: str | None = None,
    limit: int = Query(50, le=200),
    offset: int = 0,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List receiving sessions, optionally filtered by PO or status."""
    svc = ReceivingService(db)
    sessions = await svc.list_sessions(
        po_id=po_id, status=status, limit=limit, offset=offset,
    )

    return ApiResponse(data=PaginatedData(items=sessions, total=len(sessions)))


@router.get("/receiving/sessions/{session_id}", response_model=ApiResponse[ReceivingSessionResponse])
async def get_receiving_session(
    session_id: int,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get full session detail including items, progress totals, and PO info."""
    svc = ReceivingService(db)
    session = await svc.get_session(session_id)
    if not session:
        raise HTTPException(404, "Receiving session not found")

    return ApiResponse(data=ReceivingSessionResponse(**session))


@router.put(
    "/receiving/sessions/{session_id}/items",
    response_model=ApiResponse,
)
async def update_session_item(
    session_id: int,
    body: ReceivingSessionItemUpdate,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a single line item in a receiving session.

    Used by both packing-slip mode (per-line quantity entry) and scan mode
    (after scanning a part, the frontend calls this to update the matched line).
    """
    svc = ReceivingService(db)
    try:
        item = await svc.update_session_item(
            session_id=session_id,
            po_line_id=body.po_line_id,
            received_qty=body.received_qty,
            actual_cost=body.actual_cost,
            staging_zone_id=body.staging_zone_id,
            notes=body.notes,
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc))

    return ApiResponse(data=item, message="Item updated.")


@router.post(
    "/receiving/sessions/{session_id}/commit",
    response_model=ApiResponse,
)
async def commit_receiving_session(
    session_id: int,
    body: ReceivingSessionCommit | None = None,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Commit a receiving session — applies quantities to the PO.

    Optionally accepts a final `items` array to merge before committing.
    On success: stock movements created, PO status updated, session completed.
    """
    svc = ReceivingService(db)
    try:
        result = await svc.commit_session(
            session_id=session_id,
            user_id=user["id"],
            notes=body.notes if body else None,
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc))

    # Notify about delivery
    notif_svc = NotificationService(db)
    po_id = result.get("po_id")
    await notif_svc.notify(
        "po_received",
        f"Delivery received for PO #{po_id} (session #{session_id})",
        link=f"/orders/pos/{po_id}",
        entity_type="po",
        entity_id=po_id,
    )

    return ApiResponse(data=result, message="Session committed — items received.")


@router.post(
    "/receiving/sessions/{session_id}/cancel",
    response_model=ApiResponse,
)
async def cancel_receiving_session(
    session_id: int,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Cancel a receiving session — discards all progress."""
    svc = ReceivingService(db)
    try:
        await svc.cancel_session(session_id, user["id"])
    except ValueError as exc:
        raise HTTPException(400, str(exc))

    return ApiResponse(
        data={"session_id": session_id, "status": "cancelled"},
        message="Session cancelled.",
    )


@router.get(
    "/receiving/sessions/{session_id}/scan/{part_id}",
    response_model=ApiResponse,
)
async def find_po_line_by_scan(
    session_id: int,
    part_id: int,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Scan-mode lookup: find the PO line matching a scanned part within a session.

    Returns the matched PO line item so the frontend can display it for qty entry.
    If no match is found, returns 404.
    """
    svc = ReceivingService(db)
    match = await svc.find_po_line_by_part_scan(session_id, part_id)
    if not match:
        raise HTTPException(404, "No matching PO line found for this part in the current session")

    return ApiResponse(data=match, message="Match found.")


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
# Return Sorting (Phase 7C) — eligibility, guidance, dispositions
# ═══════════════════════════════════════════════════════════════


@router.get("/returns/{return_id}/sorting", response_model=ApiResponse)
async def get_sorting_guidance(
    return_id: int,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get sorting guidance for all lines in a return.

    Analyzes each line's condition, supplier return eligibility, and current
    stock levels to produce a per-line recommendation:
      - return_to_supplier: good condition, within return window
      - restock: usable but below target or not returnable
      - write_off: damaged / defective beyond use
    """
    svc = ReturnsService(db)
    try:
        guidance = await svc.get_sorting_guidance(return_id)
    except ValueError as exc:
        raise HTTPException(400, str(exc))

    return ApiResponse(data=guidance)


@router.post("/returns/{return_id}/sorting", response_model=ApiResponse)
async def process_sorting_dispositions(
    return_id: int,
    body: ReturnSortingRequest,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Apply sorting dispositions to a return's line items.

    The warehouse worker reviews the guidance, confirms or overrides each
    recommendation, then submits all dispositions in one batch.
    Creates stock movements for restock/write-off lines.
    """
    svc = ReturnsService(db)
    dispositions = [d.model_dump() for d in body.dispositions]
    try:
        result = await svc.process_sorted_return(
            return_id, dispositions, user["id"],
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc))

    # Notify about completed sorting
    notif_svc = NotificationService(db)
    await notif_svc.notify(
        "return_sorted",
        f"Return #{return_id} sorting completed",
        link=f"/orders/returns/{return_id}",
        entity_type="return",
        entity_id=return_id,
    )

    return ApiResponse(data=result, message="Sorting dispositions applied.")


@router.get("/returns/eligibility/{part_id}", response_model=ApiResponse)
async def check_return_eligibility(
    part_id: int,
    condition: str = Query("new", pattern="^(new|like_new|used|damaged|defective)$"),
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Check whether a specific part can be returned to the supplier.

    Examines the part's condition, how long ago it was received (90-day window),
    and whether it's been modified or opened.
    """
    svc = ReturnsService(db)
    result = await svc.check_return_eligibility(part_id, condition)

    return ApiResponse(data=result)


@router.get("/returns/below-target/{part_id}", response_model=ApiResponse)
async def check_below_target(
    part_id: int,
    user: dict = Depends(require_permission("view_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Check whether a part is below its restock target quantity.

    Returns the current stock, target quantity, and whether it's below target.
    Used by the ReturnSortingPage to show amber warnings on parts the warehouse
    might want to keep instead of returning.
    """
    svc = ReturnsService(db)
    result = await svc.check_below_target(part_id)

    return ApiResponse(data=result)


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
