"""
Parts routes — catalog CRUD, brands, suppliers, pricing, stock, import/export.

Phase 2 full implementation. Permissions:
  - view_parts_catalog  → read-only access to catalog, brands, stock
  - edit_parts_catalog  → create/update/delete parts and brands
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
    BrandCreate,
    BrandResponse,
    BrandUpdate,
    PartCreate,
    PartListItem,
    PartPricingUpdate,
    PartResponse,
    PartSearchParams,
    PartSupplierLinkCreate,
    PartSupplierLinkResponse,
    PartUpdate,
    StockEntry,
    StockSummary,
    SupplierCreate,
    SupplierResponse,
    SupplierUpdate,
)
from app.repositories.parts_repo import BrandRepo, PartsRepo, SupplierRepo
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
        "code": row["code"],
        "name": row["name"],
        "part_type": row.get("part_type", "general"),
        "brand_name": row.get("brand_name"),
        "unit_of_measure": row.get("unit_of_measure", "each"),
        "company_cost_price": row.get("company_cost_price"),
        "company_markup_percent": row.get("company_markup_percent"),
        "company_sell_price": row.get("company_sell_price"),
        "total_stock": row.get("total_stock", 0),
        "forecast_adu_30": row.get("forecast_adu_30"),
        "forecast_days_until_low": row.get("forecast_days_until_low"),
        "forecast_suggested_order": row.get("forecast_suggested_order"),
        "is_deprecated": bool(row.get("is_deprecated", 0)),
        "is_qr_tagged": bool(row.get("is_qr_tagged", 0)),
    }


def _part_to_response(row: dict, user: dict, suppliers: list[dict] | None = None) -> dict:
    """Convert a raw DB row to a full PartResponse-compatible dict."""
    row = _strip_pricing(row, user)
    return {
        "id": row["id"],
        "code": row["code"],
        "name": row["name"],
        "description": row.get("description"),
        "part_type": row.get("part_type", "general"),
        "brand_id": row.get("brand_id"),
        "brand_name": row.get("brand_name"),
        "manufacturer_part_number": row.get("manufacturer_part_number"),
        "unit_of_measure": row.get("unit_of_measure", "each"),
        "weight_lbs": row.get("weight_lbs"),
        "color": row.get("color"),
        "variant": row.get("variant"),
        "company_cost_price": row.get("company_cost_price"),
        "company_markup_percent": row.get("company_markup_percent"),
        "company_sell_price": row.get("company_sell_price"),
        "min_stock_level": row.get("min_stock_level", 0),
        "max_stock_level": row.get("max_stock_level", 0),
        "target_stock_level": row.get("target_stock_level", 0),
        "total_stock": row.get("total_stock", 0),
        "warehouse_stock": row.get("warehouse_stock", 0),
        "truck_stock": row.get("truck_stock", 0),
        "job_stock": row.get("job_stock", 0),
        "pulled_stock": row.get("pulled_stock", 0),
        "forecast_adu_30": row.get("forecast_adu_30"),
        "forecast_days_until_low": row.get("forecast_days_until_low"),
        "forecast_suggested_order": row.get("forecast_suggested_order"),
        "forecast_last_run": row.get("forecast_last_run"),
        "is_deprecated": bool(row.get("is_deprecated", 0)),
        "deprecation_reason": row.get("deprecation_reason"),
        "is_qr_tagged": bool(row.get("is_qr_tagged", 0)),
        "notes": row.get("notes"),
        "image_url": row.get("image_url"),
        "pdf_url": row.get("pdf_url"),
        "suppliers": suppliers or [],
        "created_at": row.get("created_at"),
        "updated_at": row.get("updated_at"),
    }


# ═══════════════════════════════════════════════════════════════
# CATALOG CRUD
# ═══════════════════════════════════════════════════════════════

@router.get("/catalog", response_model=ApiResponse[PaginatedData[PartListItem]])
async def list_parts(
    search: str | None = None,
    part_type: str | None = None,
    brand_id: int | None = None,
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
    """List parts in the catalog with search, filter, sort, and pagination."""
    repo = PartsRepo(db)
    items, total = await repo.search(
        search=search,
        part_type=part_type,
        brand_id=brand_id,
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


@router.get("/catalog/{part_id}", response_model=ApiResponse[PartResponse])
async def get_part(
    part_id: int,
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get full detail for a single part including suppliers and stock."""
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
    """Create a new part in the catalog."""
    repo = PartsRepo(db)

    # Check for duplicate code
    existing = await repo.get_by_code(body.code)
    if existing:
        raise HTTPException(
            status_code=409, detail=f"A part with code '{body.code}' already exists"
        )

    # Build insert data
    data = body.model_dump(exclude_none=True)
    # Remove generated column (SQLite computes it)
    data.pop("company_sell_price", None)

    part_id = await repo.insert(data)

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

    await repo.update(part_id, data)

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
        "code": row["code"],
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
# SUPPLIER LINKS (per-part)
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
    """List all brands with part counts."""
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
# SUPPLIERS CRUD
# ═══════════════════════════════════════════════════════════════

@router.get("/suppliers", response_model=ApiResponse[list[SupplierResponse]])
async def list_suppliers(
    search: str | None = None,
    is_active: bool | None = None,
    user: dict = Depends(require_permission("view_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all suppliers."""
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
            "code": row["code"],
            "name": row["name"],
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
        "code", "name", "description", "part_type", "brand_name",
        "unit_of_measure", "manufacturer_part_number",
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
            "code": row["code"],
            "name": row["name"],
            "description": row.get("description", ""),
            "part_type": row.get("part_type", "general"),
            "brand_name": row.get("brand_name", ""),
            "unit_of_measure": row.get("unit_of_measure", "each"),
            "manufacturer_part_number": row.get("manufacturer_part_number", ""),
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

    CSV must have at minimum: code, name
    Optional columns: description, part_type, unit_of_measure,
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
        code = (row.get("code") or "").strip()
        name = (row.get("name") or "").strip()

        if not code or not name:
            errors.append(f"Row {i}: missing required 'code' or 'name'")
            continue

        # Build part data from CSV columns
        data: dict[str, Any] = {
            "code": code,
            "name": name,
            "description": row.get("description", "").strip() or None,
            "part_type": row.get("part_type", "general").strip(),
            "unit_of_measure": row.get("unit_of_measure", "each").strip(),
            "notes": row.get("notes", "").strip() or None,
        }

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
            existing = await repo.get_by_code(code)
            if existing:
                # Update existing part
                await repo.update(existing["id"], data)
                updated += 1
            else:
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
