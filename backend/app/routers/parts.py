"""
Parts routes — catalog CRUD, hierarchy, brands, suppliers, brand-supplier links,
pending part numbers, pricing, stock, import/export.

Phase 2 implementation with hierarchy redesign. Permissions:
  - view_parts_catalog  → read-only access to catalog, brands, stock
  - edit_parts_catalog  → create/update/delete parts, brands, hierarchy items
  - edit_pricing        → modify cost price and markup (PIN-gated in frontend)
  - show_dollar_values  → see pricing columns at all
  - manage_deprecation  → change deprecation status
"""

from __future__ import annotations

import csv
import io
import math
from typing import Any

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from fastapi.responses import StreamingResponse

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse, PaginatedData
from app.models.parts import (
    # Hierarchy
    PartCategoryCreate,
    PartCategoryUpdate,
    PartCategoryResponse,
    PartStyleCreate,
    PartStyleUpdate,
    PartStyleResponse,
    PartTypeCreate,
    PartTypeUpdate,
    PartTypeResponse,
    PartColorCreate,
    PartColorUpdate,
    PartColorResponse,
    HierarchyTree,
    HierarchyCategory,
    HierarchyStyle,
    HierarchyType,
    HierarchyTypeColor,
    HierarchyColor,
    # Type ↔ Color links
    TypeColorLinkCreate,
    TypeColorLinkResponse,
    # Type ↔ Brand links
    TypeBrandLinkCreate,
    TypeBrandLinkResponse,
    QuickCreatePartRequest,
    # Catalog groups
    CatalogGroup,
    CatalogGroupVariant,
    # Brands & Suppliers
    BrandCreate,
    BrandResponse,
    BrandUpdate,
    BrandSupplierLinkCreate,
    BrandSupplierLinkResponse,
    SupplierCreate,
    SupplierResponse,
    SupplierUpdate,
    # Parts
    PartCreate,
    PartListItem,
    PartPricingUpdate,
    PartResponse,
    PartSearchParams,
    PartUpdate,
    PendingPartNumberItem,
    # Part ↔ Supplier
    PartSupplierLinkCreate,
    PartSupplierLinkResponse,
    # Stock
    StockEntry,
    StockSummary,
)
from app.repositories.parts_repo import BrandRepo, PartsRepo, SupplierRepo
from app.repositories.hierarchy_repo import (
    PartCategoryRepo,
    PartStyleRepo,
    PartTypeRepo,
    PartColorRepo,
    BrandSupplierLinkRepo,
    TypeColorLinkRepo,
    TypeBrandLinkRepo,
)
from app.repositories.stock_repo import StockRepo

router = APIRouter(prefix="/api/parts", tags=["Parts"])


# ═══════════════════════════════════════════════════════════════
# HELPER: Strip pricing if user lacks permission
# ═══════════════════════════════════════════════════════════════

def _strip_pricing(data: dict, user: dict) -> dict:
    """Remove dollar-value fields if user doesn't have show_dollar_values permission."""
    perms = set(user.get("permissions", []))
    if "show_dollar_values" not in perms:
        data = {**data}  # Shallow copy to avoid mutating original
        data["company_cost_price"] = None
        data["company_markup_percent"] = None
        data["company_sell_price"] = None
    return data


def _part_to_list_item(row: dict, user: dict) -> dict:
    """Convert a raw DB row to a PartListItem-compatible dict."""
    row = _strip_pricing(row, user)
    return {
        "id": row["id"],
        # Hierarchy names
        "category_name": row.get("category_name"),
        "style_name": row.get("style_name"),
        "type_name": row.get("type_name"),
        "color_name": row.get("color_name"),
        "color_id": row.get("color_id"),
        "color_hex": row.get("hex_code"),
        # Identity
        "part_type": row.get("part_type", "general"),
        "code": row.get("code"),
        "name": row["name"],
        "brand_id": row.get("brand_id"),
        "brand_name": row.get("brand_name"),
        "manufacturer_part_number": row.get("manufacturer_part_number"),
        "has_pending_part_number": bool(row.get("has_pending_part_number", 0)),
        # Physical
        "unit_of_measure": row.get("unit_of_measure", "each"),
        # Pricing
        "company_cost_price": row.get("company_cost_price"),
        "company_markup_percent": row.get("company_markup_percent"),
        "company_sell_price": row.get("company_sell_price"),
        # Stock
        "total_stock": row.get("total_stock", 0),
        # Forecast
        "forecast_adu_30": row.get("forecast_adu_30"),
        "forecast_days_until_low": row.get("forecast_days_until_low"),
        "forecast_suggested_order": row.get("forecast_suggested_order"),
        # Status
        "is_deprecated": bool(row.get("is_deprecated", 0)),
        "is_qr_tagged": bool(row.get("is_qr_tagged", 0)),
    }


def _part_to_response(row: dict, user: dict, suppliers: list[dict] | None = None) -> dict:
    """Convert a raw DB row to a full PartResponse-compatible dict."""
    row = _strip_pricing(row, user)
    return {
        "id": row["id"],
        # Hierarchy
        "category_id": row.get("category_id"),
        "category_name": row.get("category_name"),
        "style_id": row.get("style_id"),
        "style_name": row.get("style_name"),
        "type_id": row.get("type_id"),
        "type_name": row.get("type_name"),
        "color_id": row.get("color_id"),
        "color_name": row.get("color_name"),
        "color_hex": row.get("color_hex") or row.get("hex_code"),
        # Identity
        "part_type": row.get("part_type", "general"),
        "code": row.get("code"),
        "name": row["name"],
        "description": row.get("description"),
        # Brand
        "brand_id": row.get("brand_id"),
        "brand_name": row.get("brand_name"),
        "manufacturer_part_number": row.get("manufacturer_part_number"),
        "has_pending_part_number": bool(row.get("has_pending_part_number", 0)),
        # Physical
        "unit_of_measure": row.get("unit_of_measure", "each"),
        "weight_lbs": row.get("weight_lbs"),
        # Pricing
        "company_cost_price": row.get("company_cost_price"),
        "company_markup_percent": row.get("company_markup_percent"),
        "company_sell_price": row.get("company_sell_price"),
        # Inventory targets
        "min_stock_level": row.get("min_stock_level", 0),
        "max_stock_level": row.get("max_stock_level", 0),
        "target_stock_level": row.get("target_stock_level", 0),
        # Stock
        "total_stock": row.get("total_stock", 0),
        "warehouse_stock": row.get("warehouse_stock", 0),
        "truck_stock": row.get("truck_stock", 0),
        "job_stock": row.get("job_stock", 0),
        "pulled_stock": row.get("pulled_stock", 0),
        # Forecasting
        "forecast_adu_30": row.get("forecast_adu_30"),
        "forecast_days_until_low": row.get("forecast_days_until_low"),
        "forecast_suggested_order": row.get("forecast_suggested_order"),
        "forecast_last_run": row.get("forecast_last_run"),
        # Status
        "is_deprecated": bool(row.get("is_deprecated", 0)),
        "deprecation_reason": row.get("deprecation_reason"),
        "is_qr_tagged": bool(row.get("is_qr_tagged", 0)),
        "notes": row.get("notes"),
        "image_url": row.get("image_url"),
        "pdf_url": row.get("pdf_url"),
        # Suppliers
        "suppliers": suppliers or [],
        # Timestamps
        "created_at": row.get("created_at"),
        "updated_at": row.get("updated_at"),
    }


# ═══════════════════════════════════════════════════════════════
# HIERARCHY — Categories, Styles, Types, Colors
# ═══════════════════════════════════════════════════════════════

# ── Hierarchy Tree (single endpoint for UI cascading dropdowns) ──

@router.get("/hierarchy", response_model=ApiResponse[HierarchyTree])
async def get_hierarchy_tree(
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get the full hierarchy tree for powering cascading dropdowns.

    Returns all active categories → styles → types → linked colors, plus
    the global master color list. Includes image_url at every level for
    the image cascade pattern.

    Single API call replaces N+1 dropdown population queries.
    """
    # Fetch all active hierarchy items (4 quick queries + 1 for type-color links)
    cat_cursor = await db.execute(
        "SELECT id, name, image_url, sort_order FROM part_categories "
        "WHERE is_active = 1 ORDER BY sort_order, name"
    )
    categories_raw = await cat_cursor.fetchall()

    style_cursor = await db.execute(
        "SELECT id, category_id, name, image_url, sort_order FROM part_styles "
        "WHERE is_active = 1 ORDER BY sort_order, name"
    )
    styles_raw = await style_cursor.fetchall()

    type_cursor = await db.execute(
        "SELECT id, style_id, name, image_url, sort_order FROM part_types "
        "WHERE is_active = 1 ORDER BY sort_order, name"
    )
    types_raw = await type_cursor.fetchall()

    color_cursor = await db.execute(
        "SELECT id, name, hex_code, image_url, sort_order FROM part_colors "
        "WHERE is_active = 1 ORDER BY sort_order, name"
    )
    colors_raw = await color_cursor.fetchall()

    # Fetch all type-color links with color details
    tcl_cursor = await db.execute(
        "SELECT tcl.id, tcl.type_id, tcl.color_id, tcl.image_url, tcl.sort_order, "
        "       pc.name AS color_name, pc.hex_code "
        "FROM type_color_links tcl "
        "JOIN part_colors pc ON pc.id = tcl.color_id "
        "WHERE pc.is_active = 1 "
        "ORDER BY tcl.sort_order, pc.name"
    )
    tcl_raw = await tcl_cursor.fetchall()

    # Group type-color links by type_id
    colors_by_type: dict[int, list[HierarchyTypeColor]] = {}
    for tcl in tcl_raw:
        tid = tcl["type_id"]
        colors_by_type.setdefault(tid, []).append(
            HierarchyTypeColor(
                id=tcl["id"],
                color_id=tcl["color_id"],
                name=tcl["color_name"],
                hex_code=tcl["hex_code"],
                image_url=tcl["image_url"],
                sort_order=tcl["sort_order"] or 0,
            )
        )

    # Group types by style_id, attach their valid colors
    types_by_style: dict[int, list[HierarchyType]] = {}
    for t in types_raw:
        sid = t["style_id"]
        types_by_style.setdefault(sid, []).append(
            HierarchyType(
                id=t["id"],
                name=t["name"],
                image_url=t["image_url"],
                sort_order=t["sort_order"],
                colors=colors_by_type.get(t["id"], []),
            )
        )

    # Group styles by category_id, attach types
    styles_by_category: dict[int, list[HierarchyStyle]] = {}
    for s in styles_raw:
        cid = s["category_id"]
        styles_by_category.setdefault(cid, []).append(
            HierarchyStyle(
                id=s["id"],
                name=s["name"],
                image_url=s["image_url"],
                sort_order=s["sort_order"],
                types=types_by_style.get(s["id"], []),
            )
        )

    # Build category list with styles
    tree_categories = [
        HierarchyCategory(
            id=c["id"],
            name=c["name"],
            image_url=c["image_url"],
            sort_order=c["sort_order"],
            styles=styles_by_category.get(c["id"], []),
        )
        for c in categories_raw
    ]

    tree_colors = [
        HierarchyColor(
            id=c["id"], name=c["name"],
            hex_code=c["hex_code"], image_url=c["image_url"],
            sort_order=c["sort_order"],
        )
        for c in colors_raw
    ]

    return ApiResponse(
        data=HierarchyTree(categories=tree_categories, colors=tree_colors)
    )


# ── Categories ───────────────────────────────────────────────────

@router.get("/categories", response_model=ApiResponse[list[PartCategoryResponse]])
async def list_categories(
    search: str | None = None,
    is_active: bool | None = None,
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all part categories with child counts."""
    repo = PartCategoryRepo(db)
    rows = await repo.get_all_with_counts(search=search, is_active=is_active)
    return ApiResponse(data=[
        {
            **dict(row),
            "is_active": bool(row.get("is_active", 1)),
        }
        for row in rows
    ])


@router.post("/categories", response_model=ApiResponse[PartCategoryResponse])
async def create_category(
    body: PartCategoryCreate,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new part category."""
    repo = PartCategoryRepo(db)

    existing = await repo.get_by_name(body.name)
    if existing:
        raise HTTPException(
            status_code=409, detail=f"Category '{body.name}' already exists"
        )

    cat_id = await repo.insert(body.model_dump())
    cat = await repo.get_by_id(cat_id)
    return ApiResponse(data=cat, message=f"Category '{body.name}' created.")


@router.put("/categories/{category_id}", response_model=ApiResponse[PartCategoryResponse])
async def update_category(
    category_id: int,
    body: PartCategoryUpdate,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a part category."""
    repo = PartCategoryRepo(db)

    existing = await repo.get_by_id(category_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Category not found")

    data = body.model_dump(exclude_none=True)
    if not data:
        raise HTTPException(status_code=400, detail="No fields to update")

    await repo.update(category_id, data)
    cat = await repo.get_by_id(category_id)
    return ApiResponse(data=cat)


@router.delete("/categories/{category_id}")
async def delete_category(
    category_id: int,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a part category (only if no parts or styles use it)."""
    repo = PartCategoryRepo(db)

    existing = await repo.get_by_id(category_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Category not found")

    # Check for child styles
    style_repo = PartStyleRepo(db)
    styles = await style_repo.get_by_category(category_id)
    if styles:
        raise HTTPException(
            status_code=409,
            detail=f"Cannot delete category with {len(styles)} styles. Remove them first.",
        )

    # Check for parts in this category
    parts_repo = PartsRepo(db)
    count = await parts_repo.count(where="category_id = ?", params=(category_id,))
    if count > 0:
        raise HTTPException(
            status_code=409,
            detail=f"Cannot delete category with {count} parts.",
        )

    await repo.delete(category_id)
    return ApiResponse(message=f"Category '{existing['name']}' deleted.")


# ── Styles ───────────────────────────────────────────────────────

@router.get("/categories/{category_id}/styles", response_model=ApiResponse[list[PartStyleResponse]])
async def list_styles_by_category(
    category_id: int,
    is_active: bool | None = None,
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all styles for a specific category."""
    # Verify category exists
    cat_repo = PartCategoryRepo(db)
    if not await cat_repo.exists(category_id):
        raise HTTPException(status_code=404, detail="Category not found")

    style_repo = PartStyleRepo(db)
    rows = await style_repo.get_by_category(category_id, is_active=is_active)
    return ApiResponse(data=[
        {
            **dict(row),
            "is_active": bool(row.get("is_active", 1)),
        }
        for row in rows
    ])


@router.post("/styles", response_model=ApiResponse[PartStyleResponse])
async def create_style(
    body: PartStyleCreate,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new style under a category."""
    # Verify parent category
    cat_repo = PartCategoryRepo(db)
    if not await cat_repo.exists(body.category_id):
        raise HTTPException(status_code=404, detail="Category not found")

    style_repo = PartStyleRepo(db)
    existing = await style_repo.get_by_name_in_category(body.category_id, body.name)
    if existing:
        raise HTTPException(
            status_code=409,
            detail=f"Style '{body.name}' already exists in this category",
        )

    style_id = await style_repo.insert(body.model_dump())
    style = await style_repo.get_by_id(style_id)
    return ApiResponse(data=style, message=f"Style '{body.name}' created.")


@router.put("/styles/{style_id}", response_model=ApiResponse[PartStyleResponse])
async def update_style(
    style_id: int,
    body: PartStyleUpdate,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a part style."""
    repo = PartStyleRepo(db)

    existing = await repo.get_by_id(style_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Style not found")

    data = body.model_dump(exclude_none=True)
    if not data:
        raise HTTPException(status_code=400, detail="No fields to update")

    await repo.update(style_id, data)
    style = await repo.get_by_id(style_id)
    return ApiResponse(data=style)


@router.delete("/styles/{style_id}")
async def delete_style(
    style_id: int,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a part style (only if no parts or types use it)."""
    repo = PartStyleRepo(db)

    existing = await repo.get_by_id(style_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Style not found")

    # Check for child types
    type_repo = PartTypeRepo(db)
    types = await type_repo.get_by_style(style_id)
    if types:
        raise HTTPException(
            status_code=409,
            detail=f"Cannot delete style with {len(types)} types. Remove them first.",
        )

    # Check for parts using this style
    parts_repo = PartsRepo(db)
    count = await parts_repo.count(where="style_id = ?", params=(style_id,))
    if count > 0:
        raise HTTPException(
            status_code=409,
            detail=f"Cannot delete style with {count} parts.",
        )

    await repo.delete(style_id)
    return ApiResponse(message=f"Style '{existing['name']}' deleted.")


# ── Types ────────────────────────────────────────────────────────

@router.get("/styles/{style_id}/types", response_model=ApiResponse[list[PartTypeResponse]])
async def list_types_by_style(
    style_id: int,
    is_active: bool | None = None,
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all types for a specific style."""
    style_repo = PartStyleRepo(db)
    if not await style_repo.exists(style_id):
        raise HTTPException(status_code=404, detail="Style not found")

    type_repo = PartTypeRepo(db)
    rows = await type_repo.get_by_style(style_id, is_active=is_active)
    return ApiResponse(data=[
        {
            **dict(row),
            "is_active": bool(row.get("is_active", 1)),
        }
        for row in rows
    ])


@router.post("/types", response_model=ApiResponse[PartTypeResponse])
async def create_type(
    body: PartTypeCreate,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new type under a style."""
    style_repo = PartStyleRepo(db)
    if not await style_repo.exists(body.style_id):
        raise HTTPException(status_code=404, detail="Style not found")

    type_repo = PartTypeRepo(db)
    existing = await type_repo.get_by_name_in_style(body.style_id, body.name)
    if existing:
        raise HTTPException(
            status_code=409,
            detail=f"Type '{body.name}' already exists in this style",
        )

    type_id = await type_repo.insert(body.model_dump())
    ptype = await type_repo.get_by_id(type_id)
    return ApiResponse(data=ptype, message=f"Type '{body.name}' created.")


@router.put("/types/{type_id}", response_model=ApiResponse[PartTypeResponse])
async def update_type(
    type_id: int,
    body: PartTypeUpdate,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a part type."""
    repo = PartTypeRepo(db)

    existing = await repo.get_by_id(type_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Type not found")

    data = body.model_dump(exclude_none=True)
    if not data:
        raise HTTPException(status_code=400, detail="No fields to update")

    await repo.update(type_id, data)
    ptype = await repo.get_by_id(type_id)
    return ApiResponse(data=ptype)


@router.delete("/types/{type_id}")
async def delete_type(
    type_id: int,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a part type (only if no parts use it)."""
    repo = PartTypeRepo(db)

    existing = await repo.get_by_id(type_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Type not found")

    parts_repo = PartsRepo(db)
    count = await parts_repo.count(where="type_id = ?", params=(type_id,))
    if count > 0:
        raise HTTPException(
            status_code=409,
            detail=f"Cannot delete type with {count} parts.",
        )

    await repo.delete(type_id)
    return ApiResponse(message=f"Type '{existing['name']}' deleted.")


# ── Type ↔ Color Links ─────────────────────────────────────────────

@router.get(
    "/types/{type_id}/colors",
    response_model=ApiResponse[list[TypeColorLinkResponse]],
)
async def list_type_colors(
    type_id: int,
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all colors linked to a specific type (valid combos)."""
    type_repo = PartTypeRepo(db)
    if not await type_repo.exists(type_id):
        raise HTTPException(status_code=404, detail="Type not found")

    tcl_repo = TypeColorLinkRepo(db)
    links = await tcl_repo.get_by_type(type_id)
    return ApiResponse(data=[dict(link) for link in links])


@router.post(
    "/types/{type_id}/colors",
    response_model=ApiResponse[list[TypeColorLinkResponse]],
)
async def link_colors_to_type(
    type_id: int,
    color_ids: list[int],
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Link one or more colors to a type (bulk create).

    Accepts a JSON array of color_id values.  Existing links are skipped
    (INSERT OR IGNORE) so the operation is idempotent.
    """
    type_repo = PartTypeRepo(db)
    if not await type_repo.exists(type_id):
        raise HTTPException(status_code=404, detail="Type not found")

    # Validate all color IDs exist
    color_repo = PartColorRepo(db)
    for cid in color_ids:
        if not await color_repo.exists(cid):
            raise HTTPException(
                status_code=404, detail=f"Color ID {cid} not found"
            )

    tcl_repo = TypeColorLinkRepo(db)
    await tcl_repo.bulk_link(type_id, color_ids)

    # Return updated list
    links = await tcl_repo.get_by_type(type_id)
    return ApiResponse(
        data=[dict(link) for link in links],
        message=f"Linked {len(color_ids)} color(s) to type.",
    )


@router.delete("/types/{type_id}/colors/{color_id}")
async def unlink_color_from_type(
    type_id: int,
    color_id: int,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Remove a specific color from a type's valid color list."""
    tcl_repo = TypeColorLinkRepo(db)
    removed = await tcl_repo.unlink(type_id, color_id)
    if not removed:
        raise HTTPException(
            status_code=404, detail="Type-color link not found"
        )
    return ApiResponse(message="Color unlinked from type.")


# ── Type ↔ Brand Links ───────────────────────────────────────────────

@router.get(
    "/types/{type_id}/brands",
    response_model=ApiResponse[list[TypeBrandLinkResponse]],
)
async def list_type_brands(
    type_id: int,
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all brands (and General) enabled for a specific type."""
    type_repo = PartTypeRepo(db)
    if not await type_repo.exists(type_id):
        raise HTTPException(status_code=404, detail="Type not found")

    tbl_repo = TypeBrandLinkRepo(db)
    links = await tbl_repo.get_by_type(type_id)
    return ApiResponse(data=[dict(link) for link in links])


@router.post(
    "/types/{type_id}/brands",
    response_model=ApiResponse[TypeBrandLinkResponse],
)
async def link_brand_to_type(
    type_id: int,
    body: TypeBrandLinkCreate,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Enable a brand (or General) for a type.

    Send brand_id=null (or omit it) for General (unbranded).
    """
    type_repo = PartTypeRepo(db)
    if not await type_repo.exists(type_id):
        raise HTTPException(status_code=404, detail="Type not found")

    if body.brand_id is not None:
        brand_repo = BrandRepo(db)
        if not await brand_repo.exists(body.brand_id):
            raise HTTPException(status_code=404, detail="Brand not found")

    tbl_repo = TypeBrandLinkRepo(db)
    link = await tbl_repo.link_brand(type_id, body.brand_id)
    result = dict(link)
    # Add brand_name for response
    if body.brand_id is None:
        result["brand_name"] = "General"
    elif "brand_name" not in result or result["brand_name"] is None:
        brand_repo = BrandRepo(db)
        brand = await brand_repo.get_by_id(body.brand_id)
        result["brand_name"] = brand["name"] if brand else None
    result["part_count"] = 0  # New link has no parts yet
    return ApiResponse(data=result, message="Brand linked to type.")


@router.delete("/types/{type_id}/brands/{brand_id_or_zero}")
async def unlink_brand_from_type(
    type_id: int,
    brand_id_or_zero: int,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Remove a brand (or General) from a type.

    Use brand_id_or_zero=0 for General (unbranded).
    """
    brand_id = None if brand_id_or_zero == 0 else brand_id_or_zero

    # Check for existing parts under this combo — prevent unlinking if parts exist
    tbl_repo = TypeBrandLinkRepo(db)
    parts = await tbl_repo.get_parts_for_type_brand(type_id, brand_id)
    if parts:
        label = "General" if brand_id is None else f"brand #{brand_id}"
        raise HTTPException(
            status_code=409,
            detail=f"Cannot unlink {label} from type — {len(parts)} parts exist. "
                   "Delete those parts first.",
        )

    removed = await tbl_repo.unlink_brand(type_id, brand_id)
    if not removed:
        raise HTTPException(status_code=404, detail="Type-brand link not found")
    return ApiResponse(message="Brand unlinked from type.")


@router.get(
    "/types/{type_id}/brands/{brand_id_or_zero}/parts",
    response_model=ApiResponse[list[PartListItem]],
)
async def list_parts_for_type_brand(
    type_id: int,
    brand_id_or_zero: int,
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all parts under a type+brand (or type+General) combo.

    Use brand_id_or_zero=0 for General parts.
    """
    brand_id = None if brand_id_or_zero == 0 else brand_id_or_zero

    tbl_repo = TypeBrandLinkRepo(db)
    parts = await tbl_repo.get_parts_for_type_brand(type_id, brand_id)
    return ApiResponse(data=[_part_to_list_item(dict(p), user) for p in parts])


@router.post(
    "/types/{type_id}/brands/{brand_id_or_zero}/parts",
    response_model=ApiResponse[PartResponse],
)
async def quick_create_part(
    type_id: int,
    brand_id_or_zero: int,
    body: QuickCreatePartRequest,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Quick-create a part from the Categories tree.

    Hierarchy context is derived from the type_id path. The user only needs
    to specify the color_id. Part name is auto-generated from hierarchy names.
    Part type is inferred: General if brand_id_or_zero=0, Specific otherwise.
    """
    brand_id = None if brand_id_or_zero == 0 else brand_id_or_zero

    # Validate type exists and get its hierarchy context
    type_repo = PartTypeRepo(db)
    ptype = await type_repo.get_by_id(type_id)
    if not ptype:
        raise HTTPException(status_code=404, detail="Type not found")

    style_repo = PartStyleRepo(db)
    style = await style_repo.get_by_id(ptype["style_id"])
    if not style:
        raise HTTPException(status_code=500, detail="Style not found for type")

    cat_repo = PartCategoryRepo(db)
    category = await cat_repo.get_by_id(style["category_id"])
    if not category:
        raise HTTPException(status_code=500, detail="Category not found for style")

    # Validate color
    color_repo = PartColorRepo(db)
    color = await color_repo.get_by_id(body.color_id)
    if not color:
        raise HTTPException(status_code=404, detail="Color not found")

    # Validate brand if specific
    brand_name = None
    if brand_id is not None:
        brand_repo = BrandRepo(db)
        brand = await brand_repo.get_by_id(brand_id)
        if not brand:
            raise HTTPException(status_code=404, detail="Brand not found")
        brand_name = brand["name"]

    # Validate type-brand link exists
    tbl_repo = TypeBrandLinkRepo(db)
    if not await tbl_repo.link_exists(type_id, brand_id):
        raise HTTPException(
            status_code=400,
            detail="Brand is not enabled for this type. Link it first.",
        )

    # Auto-generate name from hierarchy
    parts = [category["name"], style["name"], ptype["name"]]
    if brand_name:
        parts.append(brand_name)
    parts.append(color["name"])
    name = " ".join(parts)

    # Determine part_type
    part_type = "general" if brand_id is None else "specific"

    # Create the part
    data = {
        "category_id": category["id"],
        "style_id": style["id"],
        "type_id": type_id,
        "color_id": body.color_id,
        "brand_id": brand_id,
        "part_type": part_type,
        "name": name,
    }

    repo = PartsRepo(db)
    try:
        part_id = await repo.insert(data)
    except Exception as e:
        if "UNIQUE constraint" in str(e):
            raise HTTPException(
                status_code=409,
                detail="A part with this exact hierarchy+brand+color already exists.",
            )
        raise

    row = await repo.get_by_id_full(part_id)
    return ApiResponse(
        data=_part_to_response(row, user),  # type: ignore[arg-type]
        message=f"Part '{name}' created.",
    )


# ── Colors ───────────────────────────────────────────────────────

@router.get("/colors", response_model=ApiResponse[list[PartColorResponse]])
async def list_colors(
    search: str | None = None,
    is_active: bool | None = None,
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all part colors with usage counts."""
    repo = PartColorRepo(db)
    rows = await repo.get_all_with_counts(search=search, is_active=is_active)
    return ApiResponse(data=[
        {
            **dict(row),
            "is_active": bool(row.get("is_active", 1)),
        }
        for row in rows
    ])


@router.post("/colors", response_model=ApiResponse[PartColorResponse])
async def create_color(
    body: PartColorCreate,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new part color."""
    repo = PartColorRepo(db)

    existing = await repo.get_by_name(body.name)
    if existing:
        raise HTTPException(
            status_code=409, detail=f"Color '{body.name}' already exists"
        )

    color_id = await repo.insert(body.model_dump())
    color = await repo.get_by_id(color_id)
    return ApiResponse(data=color, message=f"Color '{body.name}' created.")


@router.put("/colors/{color_id}", response_model=ApiResponse[PartColorResponse])
async def update_color(
    color_id: int,
    body: PartColorUpdate,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a part color."""
    repo = PartColorRepo(db)

    existing = await repo.get_by_id(color_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Color not found")

    data = body.model_dump(exclude_none=True)
    if not data:
        raise HTTPException(status_code=400, detail="No fields to update")

    await repo.update(color_id, data)
    color = await repo.get_by_id(color_id)
    return ApiResponse(data=color)


@router.delete("/colors/{color_id}")
async def delete_color(
    color_id: int,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a part color (only if no parts use it)."""
    repo = PartColorRepo(db)

    existing = await repo.get_by_id(color_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Color not found")

    parts_repo = PartsRepo(db)
    count = await parts_repo.count(where="color_id = ?", params=(color_id,))
    if count > 0:
        raise HTTPException(
            status_code=409,
            detail=f"Cannot delete color with {count} parts.",
        )

    await repo.delete(color_id)
    return ApiResponse(message=f"Color '{existing['name']}' deleted.")


# ═══════════════════════════════════════════════════════════════
# CATALOG CRUD
# ═══════════════════════════════════════════════════════════════

@router.get("/catalog", response_model=ApiResponse[PaginatedData[PartListItem]])
async def list_parts(
    search: str | None = None,
    category_id: int | None = None,
    style_id: int | None = None,
    type_id: int | None = None,
    color_id: int | None = None,
    part_type: str | None = None,
    brand_id: int | None = None,
    has_pending_pn: bool | None = None,
    is_deprecated: bool | None = None,
    is_qr_tagged: bool | None = None,
    low_stock: bool | None = None,
    sort_by: str = "name",
    sort_dir: str = "asc",
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=50, ge=1, le=200),
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List parts in the catalog with search, hierarchy filters, sort, and pagination."""
    repo = PartsRepo(db)
    items, total = await repo.search(
        search=search,
        category_id=category_id,
        style_id=style_id,
        type_id=type_id,
        color_id=color_id,
        part_type=part_type,
        brand_id=brand_id,
        has_pending_pn=has_pending_pn,
        is_deprecated=is_deprecated,
        is_qr_tagged=is_qr_tagged,
        low_stock=low_stock,
        sort_by=sort_by,
        sort_dir=sort_dir,
        page=page,
        page_size=page_size,
    )

    return ApiResponse(
        data=PaginatedData(
            items=[_part_to_list_item(row, user) for row in items],
            total=total,
            page=page,
            page_size=page_size,
            total_pages=math.ceil(total / page_size) if total > 0 else 0,
        ),
    )


@router.get("/catalog/stats")
async def catalog_stats(
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get summary statistics for the parts catalog."""
    repo = PartsRepo(db)
    stats = await repo.get_catalog_stats()
    return ApiResponse(data=stats)


@router.get("/catalog/groups", response_model=ApiResponse[list[CatalogGroup]])
async def get_catalog_groups(
    search: str | None = None,
    category_id: int | None = None,
    is_deprecated: bool | None = None,
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get the catalog as grouped product cards.

    Each group = one card in the UI, keyed by (category_id, brand_id).
    General parts (no brand) appear as their own card per category.
    Branded parts create separate cards per (category, brand).

    Example: "Outlet" with General + Leviton + Square D = 3 cards.
    Each card includes its variants and aggregate stats.
    """
    repo = PartsRepo(db)
    groups = await repo.get_catalog_groups(
        search=search,
        category_id=category_id,
        is_deprecated=is_deprecated,
    )

    perms = set(user.get("permissions", []))
    show_pricing = "show_dollar_values" in perms

    # Strip pricing from variants if user lacks permission
    for group in groups:
        if not show_pricing:
            group["price_range_low"] = None
            group["price_range_high"] = None
            for i, variant in enumerate(group.get("variants", [])):
                v = dict(variant) if not isinstance(variant, dict) else {**variant}
                v["company_cost_price"] = None
                v["company_sell_price"] = None
                group["variants"][i] = v

    return ApiResponse(data=groups)


@router.get("/catalog/{part_id}", response_model=ApiResponse[PartResponse])
async def get_part(
    part_id: int,
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get full detail for a single part including hierarchy, suppliers, and stock."""
    repo = PartsRepo(db)
    row = await repo.get_by_id_full(part_id)
    if not row:
        raise HTTPException(status_code=404, detail="Part not found")

    # Get supplier links for detail view
    supplier_links = await repo.get_supplier_links(part_id)
    suppliers = [
        {
            "id": sl["id"],
            "supplier_id": sl["supplier_id"],
            "supplier_name": sl.get("supplier_name"),
            "supplier_part_number": sl.get("supplier_part_number"),
            "supplier_cost_price": sl.get("supplier_cost_price"),
            "moq": sl.get("moq", 1),
            "discount_brackets": sl.get("discount_brackets"),
            "is_preferred": bool(sl.get("is_preferred", 0)),
            "last_price_date": sl.get("last_price_date"),
        }
        for sl in supplier_links
    ]

    return ApiResponse(data=_part_to_response(row, user, suppliers))


@router.post("/catalog", response_model=ApiResponse[PartResponse])
async def create_part(
    body: PartCreate,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new part in the catalog.

    For general parts, code and brand are optional.
    For specific (branded) parts, brand_id is expected.
    Manufacturer part number can be left NULL (appears in pending queue).
    """
    repo = PartsRepo(db)

    # Validate hierarchy references
    cat_repo = PartCategoryRepo(db)
    if not await cat_repo.exists(body.category_id):
        raise HTTPException(status_code=404, detail="Category not found")

    if body.style_id:
        style_repo = PartStyleRepo(db)
        if not await style_repo.exists(body.style_id):
            raise HTTPException(status_code=404, detail="Style not found")

    if body.type_id:
        type_repo = PartTypeRepo(db)
        if not await type_repo.exists(body.type_id):
            raise HTTPException(status_code=404, detail="Type not found")

    if body.color_id:
        color_repo = PartColorRepo(db)
        if not await color_repo.exists(body.color_id):
            raise HTTPException(status_code=404, detail="Color not found")

    if body.brand_id:
        brand_repo = BrandRepo(db)
        if not await brand_repo.exists(body.brand_id):
            raise HTTPException(status_code=404, detail="Brand not found")

    # Check for duplicate code (only if code is provided)
    if body.code:
        existing = await repo.get_by_code(body.code)
        if existing:
            raise HTTPException(
                status_code=409, detail=f"A part with code '{body.code}' already exists"
            )

    # Build insert data
    data = body.model_dump(exclude_none=True)
    # Remove generated column (SQLite computes it)
    data.pop("company_sell_price", None)

    try:
        part_id = await repo.insert(data)
    except Exception as e:
        if "UNIQUE constraint" in str(e):
            raise HTTPException(
                status_code=409,
                detail="A part with this exact hierarchy+brand combination already exists",
            )
        raise

    # Fetch the complete part back
    row = await repo.get_by_id_full(part_id)
    return ApiResponse(
        data=_part_to_response(row, user),  # type: ignore[arg-type]
        message=f"Part '{body.name}' created successfully.",
    )


@router.put("/catalog/{part_id}", response_model=ApiResponse[PartResponse])
async def update_part(
    part_id: int,
    body: PartUpdate,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update an existing part."""
    repo = PartsRepo(db)

    existing = await repo.get_by_id(part_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Part not found")

    data = body.model_dump(exclude_none=True)
    if not data:
        raise HTTPException(status_code=400, detail="No fields to update")

    # Remove generated column
    data.pop("company_sell_price", None)

    # If code is being changed, check for duplicates
    if "code" in data and data["code"] != existing["code"]:
        dupe = await repo.get_by_code(data["code"])
        if dupe:
            raise HTTPException(
                status_code=409,
                detail=f"A part with code '{data['code']}' already exists",
            )

    try:
        await repo.update(part_id, data)
    except Exception as e:
        if "UNIQUE constraint" in str(e):
            raise HTTPException(
                status_code=409,
                detail="A part with this exact hierarchy+brand combination already exists",
            )
        raise

    row = await repo.get_by_id_full(part_id)
    supplier_links = await repo.get_supplier_links(part_id)
    suppliers = [
        {
            "id": sl["id"],
            "supplier_id": sl["supplier_id"],
            "supplier_name": sl.get("supplier_name"),
            "supplier_part_number": sl.get("supplier_part_number"),
            "supplier_cost_price": sl.get("supplier_cost_price"),
            "moq": sl.get("moq", 1),
            "discount_brackets": sl.get("discount_brackets"),
            "is_preferred": bool(sl.get("is_preferred", 0)),
            "last_price_date": sl.get("last_price_date"),
        }
        for sl in supplier_links
    ]
    return ApiResponse(data=_part_to_response(row, user, suppliers))  # type: ignore[arg-type]


@router.delete("/catalog/{part_id}")
async def delete_part(
    part_id: int,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a part from the catalog.

    Soft-delete recommended — prefer deprecation. Hard delete only if no stock exists.
    """
    repo = PartsRepo(db)

    existing = await repo.get_by_id(part_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Part not found")

    # Check if stock exists (prevent deleting parts with inventory)
    stock_repo = StockRepo(db)
    summary = await stock_repo.get_stock_summary(part_id)
    if summary["total"] > 0:
        raise HTTPException(
            status_code=409,
            detail=f"Cannot delete part with {summary['total']} units in stock. "
                   "Deprecate the part instead.",
        )

    await repo.delete(part_id)
    return ApiResponse(message=f"Part '{existing['name']}' deleted.")


# ═══════════════════════════════════════════════════════════════
# PENDING PART NUMBERS
# ═══════════════════════════════════════════════════════════════

@router.get(
    "/pending-part-numbers",
    response_model=ApiResponse[PaginatedData[PendingPartNumberItem]],
)
async def list_pending_part_numbers(
    brand_id: int | None = None,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=50, ge=1, le=200),
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get branded parts that are still missing a manufacturer part number.

    This powers the "Pending Part Numbers" queue — branded items where the
    MPN was not known at creation time and needs to be filled in later.
    """
    repo = PartsRepo(db)
    items, total = await repo.get_pending_part_numbers(
        brand_id=brand_id, page=page, page_size=page_size,
    )

    return ApiResponse(
        data=PaginatedData(
            items=[dict(row) for row in items],
            total=total,
            page=page,
            page_size=page_size,
            total_pages=math.ceil(total / page_size) if total > 0 else 0,
        ),
    )


@router.get("/pending-part-numbers/count")
async def count_pending_part_numbers(
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get the count of branded parts missing manufacturer part numbers.

    Returns a simple count for powering a badge/notification indicator.
    """
    repo = PartsRepo(db)
    count = await repo.count_pending_part_numbers()
    return ApiResponse(data={"count": count})


# ═══════════════════════════════════════════════════════════════
# PRICING (permission-gated)
# ═══════════════════════════════════════════════════════════════

@router.get("/catalog/{part_id}/pricing")
async def get_part_pricing(
    part_id: int,
    user: dict = Depends(require_permission("show_dollar_values")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get pricing details for a part (requires show_dollar_values)."""
    repo = PartsRepo(db)
    row = await repo.get_by_id(part_id)
    if not row:
        raise HTTPException(status_code=404, detail="Part not found")

    return ApiResponse(data={
        "id": row["id"],
        "code": row.get("code"),
        "name": row["name"],
        "company_cost_price": row["company_cost_price"],
        "company_markup_percent": row["company_markup_percent"],
        "company_sell_price": row["company_sell_price"],
    })


@router.put("/catalog/{part_id}/pricing")
async def update_part_pricing(
    part_id: int,
    body: PartPricingUpdate,
    user: dict = Depends(require_permission("edit_pricing")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update pricing for a part (requires edit_pricing permission)."""
    repo = PartsRepo(db)

    existing = await repo.get_by_id(part_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Part not found")

    await repo.update_pricing(part_id, body.company_cost_price, body.company_markup_percent)

    # Return updated pricing
    updated = await repo.get_by_id(part_id)
    return ApiResponse(
        data={
            "id": updated["id"],  # type: ignore[index]
            "company_cost_price": updated["company_cost_price"],  # type: ignore[index]
            "company_markup_percent": updated["company_markup_percent"],  # type: ignore[index]
            "company_sell_price": updated["company_sell_price"],  # type: ignore[index]
        },
        message="Pricing updated.",
    )


# ═══════════════════════════════════════════════════════════════
# STOCK (per-part)
# ═══════════════════════════════════════════════════════════════

@router.get("/catalog/{part_id}/stock")
async def get_part_stock(
    part_id: int,
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get stock levels for a part across all locations."""
    parts_repo = PartsRepo(db)
    existing = await parts_repo.get_by_id(part_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Part not found")

    stock_repo = StockRepo(db)
    entries = await stock_repo.get_stock_for_part(part_id)

    return ApiResponse(data=[
        {
            "id": e["id"],
            "part_id": e["part_id"],
            "location_type": e["location_type"],
            "location_id": e["location_id"],
            "qty": e["qty"],
            "supplier_id": e.get("supplier_id"),
            "supplier_name": e.get("supplier_name"),
            "last_counted": e.get("last_counted"),
            "updated_at": e.get("updated_at"),
        }
        for e in entries
    ])


@router.get("/catalog/{part_id}/stock/summary")
async def get_part_stock_summary(
    part_id: int,
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get aggregated stock summary for a part."""
    stock_repo = StockRepo(db)
    summary = await stock_repo.get_stock_summary(part_id)
    return ApiResponse(data={"part_id": part_id, **summary})


# ═══════════════════════════════════════════════════════════════
# PART ↔ SUPPLIER LINKS
# ═══════════════════════════════════════════════════════════════

@router.post("/catalog/{part_id}/suppliers")
async def add_supplier_link(
    part_id: int,
    body: PartSupplierLinkCreate,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Link a supplier to a part."""
    parts_repo = PartsRepo(db)
    if not await parts_repo.exists(part_id):
        raise HTTPException(status_code=404, detail="Part not found")

    supplier_repo = SupplierRepo(db)
    if not await supplier_repo.exists(body.supplier_id):
        raise HTTPException(status_code=404, detail="Supplier not found")

    data = body.model_dump()
    try:
        link_id = await parts_repo.add_supplier_link(part_id, data)
    except Exception as e:
        if "UNIQUE constraint" in str(e):
            raise HTTPException(
                status_code=409, detail="This supplier is already linked to this part"
            )
        raise

    return ApiResponse(
        data={"id": link_id, "part_id": part_id, **data},
        message="Supplier linked.",
    )


@router.delete("/catalog/{part_id}/suppliers/{link_id}")
async def remove_supplier_link(
    part_id: int,
    link_id: int,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Remove a supplier link from a part."""
    repo = PartsRepo(db)
    removed = await repo.remove_supplier_link(link_id)
    if not removed:
        raise HTTPException(status_code=404, detail="Supplier link not found")
    return ApiResponse(message="Supplier link removed.")


# ═══════════════════════════════════════════════════════════════
# BRANDS CRUD
# ═══════════════════════════════════════════════════════════════

@router.get("/brands", response_model=ApiResponse[list[BrandResponse]])
async def list_brands(
    search: str | None = None,
    is_active: bool | None = None,
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all brands with part counts and supplier counts."""
    repo = BrandRepo(db)
    brands = await repo.get_all_with_counts(
        is_active=is_active, search=search
    )
    return ApiResponse(data=[
        {
            "id": b["id"],
            "name": b["name"],
            "website": b.get("website"),
            "notes": b.get("notes"),
            "is_active": bool(b.get("is_active", 1)),
            "part_count": b.get("part_count", 0),
            "supplier_count": b.get("supplier_count", 0),
            "created_at": b.get("created_at"),
            "updated_at": b.get("updated_at"),
        }
        for b in brands
    ])


@router.get("/brands/{brand_id}", response_model=ApiResponse[BrandResponse])
async def get_brand(
    brand_id: int,
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a single brand by ID."""
    repo = BrandRepo(db)
    brand = await repo.get_by_id(brand_id)
    if not brand:
        raise HTTPException(status_code=404, detail="Brand not found")
    return ApiResponse(data=brand)


@router.post("/brands", response_model=ApiResponse[BrandResponse])
async def create_brand(
    body: BrandCreate,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new brand."""
    repo = BrandRepo(db)

    existing = await repo.get_by_name(body.name)
    if existing:
        raise HTTPException(
            status_code=409, detail=f"Brand '{body.name}' already exists"
        )

    brand_id = await repo.insert(body.model_dump())
    brand = await repo.get_by_id(brand_id)
    return ApiResponse(data=brand, message=f"Brand '{body.name}' created.")


@router.put("/brands/{brand_id}", response_model=ApiResponse[BrandResponse])
async def update_brand(
    brand_id: int,
    body: BrandUpdate,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a brand."""
    repo = BrandRepo(db)

    existing = await repo.get_by_id(brand_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Brand not found")

    data = body.model_dump(exclude_none=True)
    if not data:
        raise HTTPException(status_code=400, detail="No fields to update")

    await repo.update(brand_id, data)

    brand = await repo.get_by_id(brand_id)
    return ApiResponse(data=brand)


@router.delete("/brands/{brand_id}")
async def delete_brand(
    brand_id: int,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a brand (only if no parts are using it)."""
    repo = BrandRepo(db)

    existing = await repo.get_by_id(brand_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Brand not found")

    # Check for parts using this brand
    parts_repo = PartsRepo(db)
    count = await parts_repo.count(where="brand_id = ?", params=(brand_id,))
    if count > 0:
        raise HTTPException(
            status_code=409,
            detail=f"Cannot delete brand with {count} parts. "
                   "Reassign or delete those parts first.",
        )

    await repo.delete(brand_id)
    return ApiResponse(message=f"Brand '{existing['name']}' deleted.")


# ═══════════════════════════════════════════════════════════════
# BRAND ↔ SUPPLIER LINKS
# ═══════════════════════════════════════════════════════════════

@router.get("/brands/{brand_id}/suppliers", response_model=ApiResponse[list[BrandSupplierLinkResponse]])
async def get_brand_suppliers(
    brand_id: int,
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all suppliers that carry a specific brand."""
    brand_repo = BrandRepo(db)
    if not await brand_repo.exists(brand_id):
        raise HTTPException(status_code=404, detail="Brand not found")

    link_repo = BrandSupplierLinkRepo(db)
    links = await link_repo.get_by_brand(brand_id)
    return ApiResponse(data=[
        {
            **dict(link),
            "is_active": bool(link.get("is_active", 1)),
        }
        for link in links
    ])


@router.get("/suppliers/{supplier_id}/brands", response_model=ApiResponse[list[BrandSupplierLinkResponse]])
async def get_supplier_brands(
    supplier_id: int,
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all brands carried by a specific supplier."""
    supplier_repo = SupplierRepo(db)
    if not await supplier_repo.exists(supplier_id):
        raise HTTPException(status_code=404, detail="Supplier not found")

    link_repo = BrandSupplierLinkRepo(db)
    links = await link_repo.get_by_supplier(supplier_id)
    return ApiResponse(data=[
        {
            **dict(link),
            "is_active": bool(link.get("is_active", 1)),
        }
        for link in links
    ])


@router.post("/brand-supplier-links", response_model=ApiResponse[BrandSupplierLinkResponse])
async def create_brand_supplier_link(
    body: BrandSupplierLinkCreate,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Link a brand to a supplier (many-to-many)."""
    brand_repo = BrandRepo(db)
    if not await brand_repo.exists(body.brand_id):
        raise HTTPException(status_code=404, detail="Brand not found")

    supplier_repo = SupplierRepo(db)
    if not await supplier_repo.exists(body.supplier_id):
        raise HTTPException(status_code=404, detail="Supplier not found")

    link_repo = BrandSupplierLinkRepo(db)
    if await link_repo.link_exists(body.brand_id, body.supplier_id):
        raise HTTPException(
            status_code=409,
            detail="This brand-supplier link already exists",
        )

    link_id = await link_repo.insert(body.model_dump())
    link = await link_repo.get_by_id(link_id)
    return ApiResponse(data=link, message="Brand-supplier link created.")


@router.delete("/brand-supplier-links/{link_id}")
async def delete_brand_supplier_link(
    link_id: int,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Remove a brand-supplier link."""
    link_repo = BrandSupplierLinkRepo(db)

    existing = await link_repo.get_by_id(link_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Brand-supplier link not found")

    await link_repo.delete(link_id)
    return ApiResponse(message="Brand-supplier link removed.")


# ═══════════════════════════════════════════════════════════════
# SUPPLIERS CRUD
# ═══════════════════════════════════════════════════════════════

@router.get("/suppliers", response_model=ApiResponse[list[SupplierResponse]])
async def list_suppliers(
    search: str | None = None,
    is_active: bool | None = None,
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all suppliers with brand counts."""
    repo = SupplierRepo(db)
    suppliers = await repo.get_all_filtered(
        is_active=is_active, search=search
    )
    return ApiResponse(data=suppliers)


@router.get("/suppliers/{supplier_id}", response_model=ApiResponse[SupplierResponse])
async def get_supplier(
    supplier_id: int,
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a single supplier by ID."""
    repo = SupplierRepo(db)
    supplier = await repo.get_by_id(supplier_id)
    if not supplier:
        raise HTTPException(status_code=404, detail="Supplier not found")
    return ApiResponse(data=supplier)


@router.post("/suppliers", response_model=ApiResponse[SupplierResponse])
async def create_supplier(
    body: SupplierCreate,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new supplier."""
    repo = SupplierRepo(db)
    supplier_id = await repo.insert(body.model_dump())
    supplier = await repo.get_by_id(supplier_id)
    return ApiResponse(data=supplier, message=f"Supplier '{body.name}' created.")


@router.put("/suppliers/{supplier_id}", response_model=ApiResponse[SupplierResponse])
async def update_supplier(
    supplier_id: int,
    body: SupplierUpdate,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a supplier."""
    repo = SupplierRepo(db)

    existing = await repo.get_by_id(supplier_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Supplier not found")

    data = body.model_dump(exclude_none=True)
    if not data:
        raise HTTPException(status_code=400, detail="No fields to update")

    await repo.update(supplier_id, data)

    supplier = await repo.get_by_id(supplier_id)
    return ApiResponse(data=supplier)


@router.delete("/suppliers/{supplier_id}")
async def delete_supplier(
    supplier_id: int,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a supplier."""
    repo = SupplierRepo(db)

    existing = await repo.get_by_id(supplier_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Supplier not found")

    await repo.delete(supplier_id)
    return ApiResponse(message=f"Supplier '{existing['name']}' deleted.")


# ═══════════════════════════════════════════════════════════════
# FORECASTING (read-only for now — full algorithms in Phase 3+)
# ═══════════════════════════════════════════════════════════════

@router.get("/forecasting")
async def get_forecasting(
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=50, ge=1, le=200),
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get forecasting data for all parts that have forecast data."""
    repo = PartsRepo(db)
    items, total = await repo.search(
        sort_by="forecast_days_until_low",
        sort_dir="asc",
        page=page,
        page_size=page_size,
    )

    forecasts = [
        {
            "id": row["id"],
            "code": row.get("code"),
            "name": row["name"],
            "category_name": row.get("category_name"),
            "brand_name": row.get("brand_name"),
            "total_stock": row.get("total_stock", 0),
            "min_stock_level": row.get("min_stock_level", 0),
            "forecast_adu_30": row.get("forecast_adu_30", 0),
            "forecast_adu_90": row.get("forecast_adu_90", 0),
            "forecast_reorder_point": row.get("forecast_reorder_point", 0),
            "forecast_target_qty": row.get("forecast_target_qty", 0),
            "forecast_suggested_order": row.get("forecast_suggested_order", 0),
            "forecast_days_until_low": row.get("forecast_days_until_low", 999),
            "forecast_last_run": row.get("forecast_last_run"),
        }
        for row in items
    ]

    return ApiResponse(
        data=PaginatedData(
            items=forecasts,
            total=total,
            page=page,
            page_size=page_size,
            total_pages=math.ceil(total / page_size) if total > 0 else 0,
        ),
    )


# ═══════════════════════════════════════════════════════════════
# IMPORT / EXPORT (CSV)
# ═══════════════════════════════════════════════════════════════

@router.get("/export")
async def export_parts_csv(
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Export all parts as CSV. Pricing included only with permission."""
    repo = PartsRepo(db)
    items, _ = await repo.search(page_size=10000)  # Get all parts

    show_pricing = "show_dollar_values" in set(user.get("permissions", []))

    # Build CSV in memory
    output = io.StringIO()
    fieldnames = [
        "category_name", "style_name", "type_name", "color_name",
        "code", "name", "description", "part_type", "brand_name",
        "manufacturer_part_number", "unit_of_measure",
    ]
    if show_pricing:
        fieldnames.extend(["company_cost_price", "company_markup_percent", "company_sell_price"])
    fieldnames.extend([
        "min_stock_level", "max_stock_level", "target_stock_level",
        "total_stock", "is_deprecated", "notes",
    ])

    writer = csv.DictWriter(output, fieldnames=fieldnames)
    writer.writeheader()

    for row in items:
        csv_row: dict[str, Any] = {
            "category_name": row.get("category_name", ""),
            "style_name": row.get("style_name", ""),
            "type_name": row.get("type_name", ""),
            "color_name": row.get("color_name", ""),
            "code": row.get("code", ""),
            "name": row["name"],
            "description": row.get("description", ""),
            "part_type": row.get("part_type", "general"),
            "brand_name": row.get("brand_name", ""),
            "manufacturer_part_number": row.get("manufacturer_part_number", ""),
            "unit_of_measure": row.get("unit_of_measure", "each"),
        }
        if show_pricing:
            csv_row["company_cost_price"] = row.get("company_cost_price", 0)
            csv_row["company_markup_percent"] = row.get("company_markup_percent", 0)
            csv_row["company_sell_price"] = row.get("company_sell_price", 0)
        csv_row.update({
            "min_stock_level": row.get("min_stock_level", 0),
            "max_stock_level": row.get("max_stock_level", 0),
            "target_stock_level": row.get("target_stock_level", 0),
            "total_stock": row.get("total_stock", 0),
            "is_deprecated": "Yes" if row.get("is_deprecated") else "No",
            "notes": row.get("notes", ""),
        })
        writer.writerow(csv_row)

    output.seek(0)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=parts_catalog.csv"},
    )


@router.post("/import")
async def import_parts_csv(
    file: UploadFile = File(...),
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Import parts from a CSV file.

    CSV must have at minimum: name, category_id (or category_name for lookup)
    Optional columns: code, description, part_type, unit_of_measure,
                      company_cost_price, company_markup_percent,
                      min_stock_level, max_stock_level, target_stock_level, notes
    """
    if not file.filename or not file.filename.endswith(".csv"):
        raise HTTPException(status_code=400, detail="File must be a .csv")

    content = await file.read()
    text = content.decode("utf-8-sig")  # Handle BOM
    reader = csv.DictReader(io.StringIO(text))

    repo = PartsRepo(db)
    created = 0
    updated = 0
    errors: list[str] = []

    for i, row in enumerate(reader, start=2):  # Row 2 (after header)
        name = (row.get("name") or "").strip()
        code = (row.get("code") or "").strip() or None

        if not name:
            errors.append(f"Row {i}: missing required 'name'")
            continue

        # Category is required — try by ID first, then by name lookup
        category_id_str = (row.get("category_id") or "").strip()
        if not category_id_str:
            errors.append(f"Row {i}: missing required 'category_id'")
            continue

        try:
            category_id = int(category_id_str)
        except ValueError:
            errors.append(f"Row {i}: invalid category_id '{category_id_str}'")
            continue

        # Build part data from CSV columns
        data: dict[str, Any] = {
            "category_id": category_id,
            "name": name,
            "code": code,
            "description": row.get("description", "").strip() or None,
            "part_type": row.get("part_type", "general").strip(),
            "unit_of_measure": row.get("unit_of_measure", "each").strip(),
            "notes": row.get("notes", "").strip() or None,
        }

        # Optional hierarchy IDs
        for fk_field in ["style_id", "type_id", "color_id", "brand_id"]:
            val = (row.get(fk_field) or "").strip()
            if val:
                try:
                    data[fk_field] = int(val)
                except ValueError:
                    errors.append(f"Row {i}: invalid {fk_field} '{val}'")

        # Numeric fields (with safe parsing)
        for field in ["company_cost_price", "company_markup_percent",
                       "min_stock_level", "max_stock_level", "target_stock_level"]:
            val = row.get(field, "").strip()
            if val:
                try:
                    data[field] = float(val) if "." in val or "price" in field or "percent" in field else int(val)
                except ValueError:
                    errors.append(f"Row {i}: invalid number in '{field}': {val}")

        try:
            # If code is provided, try update by code
            if code:
                existing = await repo.get_by_code(code)
                if existing:
                    await repo.update(existing["id"], data)
                    updated += 1
                    continue

            # Create new part
            await repo.insert(data)
            created += 1
        except Exception as e:
            errors.append(f"Row {i}: {str(e)}")

    return ApiResponse(
        data={
            "created": created,
            "updated": updated,
            "errors": errors[:20],  # Limit error list
            "total_errors": len(errors),
        },
        message=f"Import complete: {created} created, {updated} updated, {len(errors)} errors.",
    )
