"""
Companions routes — rule management, suggestion engine, co-occurrence.

Prefix: /api/parts/companions

This router handles all companion-related endpoints:
- Rules CRUD (with sources + targets)
- Manual trigger (generate suggestions from input items)
- Suggestion board (list, decide)
- Co-occurrence pairs (view, refresh)
- Stats (KPI dashboard counts)

Permissions:
  - view_parts_catalog → read access (list rules, suggestions, stats)
  - edit_parts_catalog → write access (create/update/delete rules, decide, refresh)
"""

from __future__ import annotations

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException, Query

from app.database import get_db
from app.middleware.auth import require_permission
from app.models.common import ApiResponse
from app.models.companions import (
    CompanionRuleCreate,
    CompanionRuleUpdate,
    CompanionRuleResponse,
    CompanionRuleSourceResponse,
    CompanionRuleTargetResponse,
    CompanionSuggestionResponse,
    SuggestionSourceResponse,
    SuggestionDecisionRequest,
    ManualTriggerRequest,
    CoOccurrencePairResponse,
    CompanionStats,
)
from app.repositories.companions_repo import (
    CompanionRuleRepo,
    CompanionSuggestionRepo,
    CoOccurrenceRepo,
)
from app.services.companions_service import CompanionsService

router = APIRouter(prefix="/api/parts/companions", tags=["Companions"])


# ═══════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════

def _rule_to_response(rule: dict) -> CompanionRuleResponse:
    """Map a raw rule dict (with children) to the response model."""
    return CompanionRuleResponse(
        id=rule["id"],
        name=rule["name"],
        description=rule.get("description"),
        style_match=rule.get("style_match", "auto"),
        qty_mode=rule.get("qty_mode", "sum"),
        qty_ratio=rule.get("qty_ratio", 1.0),
        is_active=bool(rule.get("is_active", 1)),
        sources=[
            CompanionRuleSourceResponse(
                id=s["id"],
                category_id=s["category_id"],
                category_name=s.get("category_name"),
                style_id=s.get("style_id"),
                style_name=s.get("style_name"),
            )
            for s in rule.get("sources", [])
        ],
        targets=[
            CompanionRuleTargetResponse(
                id=t["id"],
                category_id=t["category_id"],
                category_name=t.get("category_name"),
                style_id=t.get("style_id"),
                style_name=t.get("style_name"),
            )
            for t in rule.get("targets", [])
        ],
        created_by=rule.get("created_by"),
        created_at=rule.get("created_at"),
        updated_at=rule.get("updated_at"),
    )


def _suggestion_to_response(s: dict) -> CompanionSuggestionResponse:
    """Map a raw suggestion dict (with sources) to the response model."""
    return CompanionSuggestionResponse(
        id=s["id"],
        rule_id=s.get("rule_id"),
        target_category_id=s["target_category_id"],
        target_style_id=s.get("target_style_id"),
        target_description=s.get("target_description", ""),
        suggested_qty=s["suggested_qty"],
        approved_qty=s.get("approved_qty"),
        reason_type=s.get("reason_type", "rule"),
        reason_text=s.get("reason_text", ""),
        status=s.get("status", "pending"),
        sources=[
            SuggestionSourceResponse(
                id=src["id"],
                category_id=src["category_id"],
                category_name=src.get("category_name"),
                style_id=src.get("style_id"),
                style_name=src.get("style_name"),
                qty=src["qty"],
            )
            for src in s.get("sources", [])
        ],
        triggered_by=s.get("triggered_by"),
        decided_by=s.get("decided_by"),
        decided_at=s.get("decided_at"),
        order_id=s.get("order_id"),
        notes=s.get("notes"),
        created_at=s.get("created_at"),
    )


# ═══════════════════════════════════════════════════════════════
# RULES CRUD
# ═══════════════════════════════════════════════════════════════

@router.get("/rules", response_model=ApiResponse[list[CompanionRuleResponse]])
async def list_rules(
    user=Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all companion rules with their sources and targets."""
    repo = CompanionRuleRepo(db)
    rules = await repo.get_all_rules_with_children()
    return ApiResponse(
        data=[_rule_to_response(r) for r in rules],
    )


@router.post("/rules", response_model=ApiResponse[CompanionRuleResponse])
async def create_rule(
    body: CompanionRuleCreate,
    user=Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new companion rule with sources and targets."""
    repo = CompanionRuleRepo(db)

    rule_data = {
        "name": body.name,
        "description": body.description,
        "style_match": body.style_match,
        "qty_mode": body.qty_mode,
        "qty_ratio": body.qty_ratio,
        "is_active": 1 if body.is_active else 0,
        "created_by": user["id"],
    }
    sources = [s.model_dump() for s in body.sources]
    targets = [t.model_dump() for t in body.targets]

    rule_id = await repo.create_rule(rule_data, sources, targets)
    rule = await repo.get_rule_with_children(rule_id)
    if not rule:
        raise HTTPException(status_code=500, detail="Failed to create rule")

    return ApiResponse(
        data=_rule_to_response(rule),
        message=f"Companion rule '{body.name}' created",
    )


@router.put("/rules/{rule_id}", response_model=ApiResponse[CompanionRuleResponse])
async def update_rule(
    rule_id: int,
    body: CompanionRuleUpdate,
    user=Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a companion rule. Sources/targets are fully replaced if provided."""
    repo = CompanionRuleRepo(db)

    existing = await repo.get_by_id(rule_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Rule not found")

    # Build update dict (only non-None fields)
    update_data = {}
    if body.name is not None:
        update_data["name"] = body.name
    if body.description is not None:
        update_data["description"] = body.description
    if body.style_match is not None:
        update_data["style_match"] = body.style_match
    if body.qty_mode is not None:
        update_data["qty_mode"] = body.qty_mode
    if body.qty_ratio is not None:
        update_data["qty_ratio"] = body.qty_ratio
    if body.is_active is not None:
        update_data["is_active"] = 1 if body.is_active else 0

    sources = [s.model_dump() for s in body.sources] if body.sources is not None else None
    targets = [t.model_dump() for t in body.targets] if body.targets is not None else None

    await repo.update_rule(rule_id, update_data, sources, targets)

    rule = await repo.get_rule_with_children(rule_id)
    return ApiResponse(
        data=_rule_to_response(rule),  # type: ignore[arg-type]
        message="Rule updated",
    )


@router.delete("/rules/{rule_id}", response_model=ApiResponse)
async def delete_rule(
    rule_id: int,
    user=Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a companion rule (cascades sources and targets)."""
    repo = CompanionRuleRepo(db)

    if not await repo.exists(rule_id):
        raise HTTPException(status_code=404, detail="Rule not found")

    await repo.delete(rule_id)
    return ApiResponse(message="Rule deleted")


# ═══════════════════════════════════════════════════════════════
# MANUAL TRIGGER — "What should I also order?"
# ═══════════════════════════════════════════════════════════════

@router.post(
    "/generate",
    response_model=ApiResponse[list[CompanionSuggestionResponse]],
)
async def generate_suggestions(
    body: ManualTriggerRequest,
    user=Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Generate companion suggestions from a list of input items.

    This is the manual trigger — the same engine will later be called
    automatically when a purchase order is created.
    """
    service = CompanionsService(db)

    # Resolve category/style names for each input item so the engine
    # can build useful reason text
    enriched_items = []
    for item in body.items:
        row = {"category_id": item.category_id, "qty": item.qty}

        # Look up category name
        cursor = await db.execute(
            "SELECT name FROM part_categories WHERE id = ?",
            (item.category_id,),
        )
        cat = await cursor.fetchone()
        row["category_name"] = cat["name"] if cat else "Unknown"

        # Look up style name (if provided)
        if item.style_id:
            row["style_id"] = item.style_id
            cursor = await db.execute(
                "SELECT name FROM part_styles WHERE id = ?",
                (item.style_id,),
            )
            style = await cursor.fetchone()
            row["style_name"] = style["name"] if style else None

        enriched_items.append(row)

    suggestions = await service.generate_suggestions(
        enriched_items, user_id=user["id"]
    )

    return ApiResponse(
        data=[_suggestion_to_response(s) for s in suggestions],
        message=f"{len(suggestions)} suggestion(s) generated",
    )


# ═══════════════════════════════════════════════════════════════
# SUGGESTION BOARD
# ═══════════════════════════════════════════════════════════════

@router.get(
    "/suggestions",
    response_model=ApiResponse[list[CompanionSuggestionResponse]],
)
async def list_suggestions(
    status: str | None = Query(None, description="Filter: pending|approved|discarded"),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    user=Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List companion suggestions, optionally filtered by status."""
    repo = CompanionSuggestionRepo(db)
    offset = (page - 1) * page_size

    suggestions = await repo.list_suggestions(
        status=status,
        limit=page_size,
        offset=offset,
    )

    return ApiResponse(
        data=[_suggestion_to_response(s) for s in suggestions],
    )


@router.post(
    "/suggestions/{suggestion_id}/decide",
    response_model=ApiResponse[CompanionSuggestionResponse],
)
async def decide_suggestion(
    suggestion_id: int,
    body: SuggestionDecisionRequest,
    user=Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Approve or discard a pending suggestion."""
    service = CompanionsService(db)

    result = await service.decide_suggestion(
        suggestion_id=suggestion_id,
        action=body.action,
        user_id=user["id"],
        approved_qty=body.approved_qty,
        notes=body.notes,
    )

    if not result:
        raise HTTPException(
            status_code=404,
            detail="Suggestion not found or already decided",
        )

    return ApiResponse(
        data=_suggestion_to_response(result),
        message=f"Suggestion {body.action}",
    )


# ═══════════════════════════════════════════════════════════════
# STATS — KPI dashboard
# ═══════════════════════════════════════════════════════════════

@router.get("/stats", response_model=ApiResponse[CompanionStats])
async def get_stats(
    user=Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get summary counts for the companion dashboard KPI cards."""
    service = CompanionsService(db)
    stats = await service.get_stats()
    return ApiResponse(data=CompanionStats(**stats))


# ═══════════════════════════════════════════════════════════════
# CO-OCCURRENCE
# ═══════════════════════════════════════════════════════════════

@router.get(
    "/co-occurrence",
    response_model=ApiResponse[list[CoOccurrencePairResponse]],
)
async def get_cooccurrence(
    limit: int = Query(50, ge=1, le=200),
    user=Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get top co-occurrence pairs sorted by confidence."""
    repo = CoOccurrenceRepo(db)
    pairs = await repo.get_top_pairs(limit=limit)
    return ApiResponse(
        data=[CoOccurrencePairResponse(**p) for p in pairs],
    )


@router.post("/co-occurrence/refresh", response_model=ApiResponse)
async def refresh_cooccurrence(
    user=Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Recompute co-occurrence pairs from stock movement history."""
    service = CompanionsService(db)
    count = await service.refresh_cooccurrence()
    return ApiResponse(
        message=f"Refreshed: {count} co-occurrence pairs computed",
    )
