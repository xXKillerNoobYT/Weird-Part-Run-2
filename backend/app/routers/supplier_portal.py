"""
Supplier Portal routes — token management + public supplier-facing endpoints.

Two distinct sections:
  1. Internal management (requires staff auth):
     POST   /api/supplier-portal/tokens         — generate new token
     GET    /api/supplier-portal/tokens          — list active tokens
     DELETE /api/supplier-portal/tokens/{id}     — revoke a token

  2. Public supplier-facing (requires valid portal token via header/query):
     GET    /api/supplier-portal/view            — validate token, get supplier info
     GET    /api/supplier-portal/view/pos        — list POs for this supplier
     GET    /api/supplier-portal/view/pos/{id}   — get PO detail with line items
     POST   /api/supplier-portal/view/pos/{id}/acknowledge — acknowledge a PO
"""

from __future__ import annotations

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException, Header, Query

from app.database import get_db
from app.middleware.auth import require_permission
from app.models.common import ApiResponse
from app.models.orders import (
    SupplierPortalTokenCreate,
    SupplierPortalAcknowledge,
    SupplierPortalNote,
)
from app.services.supplier_portal_service import SupplierPortalService

router = APIRouter(
    prefix="/api/supplier-portal",
    tags=["Supplier Portal"],
    redirect_slashes=False,
)


# ═══════════════════════════════════════════════════════════════
# Helper — extract portal token from request
# ═══════════════════════════════════════════════════════════════

async def _get_portal_token(
    x_portal_token: str | None = Header(None, alias="X-Portal-Token"),
    token: str | None = Query(None),
) -> str:
    """Extract portal token from header or query parameter.

    Supports both:
      - Header: X-Portal-Token: <token>
      - Query:  ?token=<token>

    Query parameter is useful for direct browser access / link sharing.
    """
    t = x_portal_token or token
    if not t:
        raise HTTPException(401, "Portal access token required (X-Portal-Token header or ?token= query)")
    return t


async def _validate_portal_access(
    portal_token: str = Depends(_get_portal_token),
    db: aiosqlite.Connection = Depends(get_db),
) -> dict:
    """Validate portal token and return token record with supplier info.

    Raises 401 if token is invalid, expired, or revoked.
    """
    svc = SupplierPortalService(db)
    record = await svc.validate_token(portal_token)
    if not record:
        raise HTTPException(401, "Invalid or expired portal token")
    return record


# ═══════════════════════════════════════════════════════════════
# Internal Management Endpoints (staff auth required)
# ═══════════════════════════════════════════════════════════════


@router.post("/tokens", response_model=ApiResponse)
async def create_portal_token(
    body: SupplierPortalTokenCreate,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Generate a new portal access token for a supplier.

    The token grants the supplier read-only access to their POs
    and the ability to acknowledge orders.
    """
    svc = SupplierPortalService(db)
    try:
        result = await svc.create_token(
            supplier_id=body.supplier_id,
            user_id=user["id"],
            expires_in_days=body.expires_in_days,
            note=body.note,
        )
    except ValueError as exc:
        raise HTTPException(422, str(exc))

    return ApiResponse(data=result, message="Portal token created.")


@router.get("/tokens", response_model=ApiResponse)
async def list_portal_tokens(
    supplier_id: int | None = None,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List portal tokens, optionally filtered by supplier."""
    svc = SupplierPortalService(db)
    tokens = await svc.list_tokens(supplier_id)
    return ApiResponse(data=[dict(t) for t in tokens])


@router.delete("/tokens/{token_id}", response_model=ApiResponse)
async def revoke_portal_token(
    token_id: int,
    user: dict = Depends(require_permission("manage_orders")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Revoke a portal token — immediately invalidates supplier access."""
    svc = SupplierPortalService(db)
    ok = await svc.revoke_token(token_id)
    if not ok:
        raise HTTPException(404, "Token not found")

    return ApiResponse(data={"revoked": True}, message="Portal token revoked.")


# ═══════════════════════════════════════════════════════════════
# Public Supplier-Facing Endpoints (portal token required)
# ═══════════════════════════════════════════════════════════════


@router.get("/view", response_model=ApiResponse)
async def get_portal_info(
    token_record: dict = Depends(_validate_portal_access),
):
    """Validate token and return supplier info.

    Called when a supplier first opens their portal link.
    Returns supplier name, basic info, and confirms the token is valid.
    """
    return ApiResponse(data={
        "supplier_id": token_record["supplier_id"],
        "supplier_name": token_record["supplier_name"],
        "supplier_email": token_record.get("supplier_email"),
        "supplier_contact": token_record.get("supplier_contact"),
        "token_expires_at": token_record.get("expires_at"),
    })


@router.get("/view/pos", response_model=ApiResponse)
async def list_supplier_pos(
    status: str | None = None,
    limit: int = Query(50, le=200),
    offset: int = 0,
    token_record: dict = Depends(_validate_portal_access),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List POs for this supplier (portal view).

    Only shows non-draft, non-cancelled POs.
    Shows acknowledgment status for each PO.
    """
    svc = SupplierPortalService(db)
    pos = await svc.get_supplier_pos(
        supplier_id=token_record["supplier_id"],
        status=status,
        limit=limit,
        offset=offset,
    )
    return ApiResponse(data=pos)


@router.get("/view/pos/{po_id}", response_model=ApiResponse)
async def get_supplier_po_detail(
    po_id: int,
    token_record: dict = Depends(_validate_portal_access),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get full PO detail with line items (portal view).

    Only returns POs that belong to this supplier.
    """
    svc = SupplierPortalService(db)
    po = await svc.get_po_detail_for_supplier(
        po_id=po_id,
        supplier_id=token_record["supplier_id"],
    )
    if not po:
        raise HTTPException(404, "PO not found")

    return ApiResponse(data=po)


@router.post("/view/pos/{po_id}/acknowledge", response_model=ApiResponse)
async def acknowledge_po(
    po_id: int,
    body: SupplierPortalAcknowledge,
    token_record: dict = Depends(_validate_portal_access),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Supplier acknowledges receipt of a PO.

    Optionally provides an estimated delivery date and notes.
    Automatically updates PO status from 'submitted' to 'acknowledged'.
    """
    svc = SupplierPortalService(db)
    try:
        result = await svc.acknowledge_po(
            po_id=po_id,
            supplier_id=token_record["supplier_id"],
            token_id=token_record["id"],
            estimated_delivery=body.estimated_delivery,
            supplier_notes=body.supplier_notes,
        )
    except ValueError as exc:
        raise HTTPException(422, str(exc))

    # Log as conversation entry — system entry since it's from the portal
    from app.services.po_conversation_service import POConversationService
    conv_svc = POConversationService(db)
    msg = f"Supplier acknowledged via portal"
    if body.estimated_delivery:
        msg += f" — ETA: {body.estimated_delivery}"
    if body.supplier_notes:
        msg += f" — Note: {body.supplier_notes}"
    await conv_svc.add_system_entry(po_id, msg)

    return ApiResponse(data=result, message="PO acknowledged.")


@router.post("/view/pos/{po_id}/note", response_model=ApiResponse)
async def add_supplier_note(
    po_id: int,
    body: SupplierPortalNote,
    token_record: dict = Depends(_validate_portal_access),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Supplier adds a follow-up note to a PO.

    Available after acknowledgment — lets suppliers communicate about
    delays, partial availability, questions, etc.  The note is stored
    as a po_conversations entry with entry_type='supplier_note' so office
    staff can see it alongside their own conversation thread.

    Phase 17 Gap 2: Supplier Portal Ongoing Notes.
    """
    svc = SupplierPortalService(db)

    # Verify PO belongs to this supplier
    po = await svc.get_po_detail_for_supplier(po_id, token_record["supplier_id"])
    if not po:
        raise HTTPException(404, "PO not found")

    # Create a conversation entry with special entry_type
    from app.services.po_conversation_service import POConversationService
    conv_svc = POConversationService(db)

    # Resolve supplier_id from the PO
    cursor = await db.execute(
        "SELECT supplier_id FROM purchase_orders WHERE id = ?",
        (po_id,),
    )
    po_row = await cursor.fetchone()
    supplier_id = po_row["supplier_id"] if po_row else None

    entry_id = await conv_svc.conv_repo.insert({
        "po_id": po_id,
        "supplier_id": supplier_id,
        "entry_type": "supplier_note",
        "message": body.message,
        "follow_up_needed": 1,  # Flag for office review
        "created_by": None,     # No internal user — from supplier portal
    })
    await db.commit()

    return ApiResponse(
        data={"id": entry_id, "po_id": po_id},
        message="Note added successfully.",
    )
