"""
Contacts routes — customers, general contractors, entity contacts, and directory.

~19 endpoints covering customer/GC CRUD, flexible entity contacts, and a
unified contact directory search.

Permission gates:
- view_customers   → read customer list/detail/contacts
- manage_customers → create/update customers and their contacts
- view_contractors → read GC list/detail/contacts
- manage_contractors → create/update GCs and their contacts
"""

from __future__ import annotations

import csv
import io
from typing import Any

import aiosqlite
from fastapi import APIRouter, Body, Depends, File, HTTPException, Query, UploadFile, status

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse
from app.models.contacts import (
    CustomerCreate,
    CustomerUpdate,
    EntityContactCreate,
    EntityContactUpdate,
    GCCreate,
    GCUpdate,
)
from app.services.contacts_service import ContactsService

router = APIRouter(prefix="/api/contacts", tags=["Contacts"])


# ═════════════════════════════════════════════════════════════════
# CUSTOMERS
# ═════════════════════════════════════════════════════════════════


@router.get("/customers")
async def list_customers(
    search: str | None = Query(None, description="Search by name, company, email, phone"),
    customer_type: str | None = Query(None, description="Filter by customer type"),
    is_active: bool | None = Query(None, description="Filter by active status"),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(50, ge=1, le=200, description="Items per page"),
    user: dict = Depends(require_permission("view_customers")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Paginated customer list with job/contact counts."""
    svc = ContactsService(db)
    result = await svc.list_customers(
        search=search, customer_type=customer_type, is_active=is_active,
        page=page, page_size=page_size,
    )
    return ApiResponse(data=result, message=f"Found {result['total']} customers")


@router.get("/customers/search")
async def search_customers(
    q: str = Query(..., min_length=1, description="Search query"),
    limit: int = Query(20, ge=1, le=100, description="Max results"),
    user: dict = Depends(require_permission("view_customers")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Quick autocomplete search for customers."""
    svc = ContactsService(db)
    results = await svc.search_customers(q, limit=limit)
    return ApiResponse(data=results, message=f"{len(results)} matches")


@router.get("/customers/{customer_id}")
async def get_customer(
    customer_id: int,
    user: dict = Depends(require_permission("view_customers")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Full customer detail with contacts and job count."""
    svc = ContactsService(db)
    detail = await svc.get_customer_detail(customer_id)
    if not detail:
        raise HTTPException(status_code=404, detail="Customer not found")
    return ApiResponse(data=detail, message="Customer detail loaded")


@router.post("/customers", status_code=status.HTTP_201_CREATED)
async def create_customer(
    data: CustomerCreate,
    user: dict = Depends(require_permission("manage_customers")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new customer."""
    svc = ContactsService(db)
    new_id = await svc.create_customer(data)
    detail = await svc.get_customer_detail(new_id)
    return ApiResponse(data=detail, message="Customer created")


@router.put("/customers/{customer_id}")
async def update_customer(
    customer_id: int,
    data: CustomerUpdate,
    user: dict = Depends(require_permission("manage_customers")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a customer's information."""
    svc = ContactsService(db)
    updated = await svc.update_customer(customer_id, data)
    if not updated:
        raise HTTPException(status_code=404, detail="Customer not found or no changes")
    detail = await svc.get_customer_detail(customer_id)
    return ApiResponse(data=detail, message="Customer updated")


@router.patch("/customers/{customer_id}/toggle-active")
async def toggle_customer_active(
    customer_id: int,
    is_active: bool = Query(..., description="New active status"),
    user: dict = Depends(require_permission("manage_customers")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Activate or deactivate a customer."""
    svc = ContactsService(db)
    toggled = await svc.toggle_customer_active(customer_id, is_active)
    if not toggled:
        raise HTTPException(status_code=404, detail="Customer not found")
    action = "activated" if is_active else "deactivated"
    return ApiResponse(
        data={"customer_id": customer_id, "is_active": is_active},
        message=f"Customer {action}",
    )


@router.get("/customers/{customer_id}/contacts")
async def get_customer_contacts(
    customer_id: int,
    include_inactive: bool = Query(False, description="Include inactive contacts"),
    user: dict = Depends(require_permission("view_customers")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all contacts for a customer."""
    svc = ContactsService(db)
    contacts = await svc.get_entity_contacts(
        "customer", customer_id, include_inactive=include_inactive,
    )
    return ApiResponse(data=contacts, message=f"{len(contacts)} contacts")


@router.post("/customers/{customer_id}/contacts", status_code=status.HTTP_201_CREATED)
async def add_customer_contact(
    customer_id: int,
    data: EntityContactCreate,
    user: dict = Depends(require_permission("manage_customers")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Add a contact to a customer."""
    svc = ContactsService(db)
    contact_id = await svc.add_entity_contact("customer", customer_id, data)
    return ApiResponse(data={"id": contact_id}, message="Contact added")


@router.get("/customers/{customer_id}/jobs")
async def get_customer_jobs(
    customer_id: int,
    user: dict = Depends(require_permission("view_customers")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all jobs linked to a customer (reverse of GET /jobs/{id}/customers)."""
    svc = ContactsService(db)
    jobs = await svc.get_customer_jobs(customer_id)
    return ApiResponse(data=jobs, message=f"{len(jobs)} linked jobs")


# ═════════════════════════════════════════════════════════════════
# GENERAL CONTRACTORS
# ═════════════════════════════════════════════════════════════════


@router.get("/general-contractors")
async def list_gcs(
    search: str | None = Query(None, description="Search by name, code, email, phone"),
    trade_type: str | None = Query(None, description="Filter by trade type"),
    is_active: bool | None = Query(None, description="Filter by active status"),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(50, ge=1, le=200, description="Items per page"),
    user: dict = Depends(require_permission("view_contractors")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Paginated GC list with job/contact counts."""
    svc = ContactsService(db)
    result = await svc.list_gcs(
        search=search, trade_type=trade_type, is_active=is_active,
        page=page, page_size=page_size,
    )
    return ApiResponse(data=result, message=f"Found {result['total']} contractors")


@router.get("/general-contractors/search")
async def search_gcs(
    q: str = Query(..., min_length=1, description="Search query"),
    limit: int = Query(20, ge=1, le=100, description="Max results"),
    user: dict = Depends(require_permission("view_contractors")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Quick autocomplete search for GCs."""
    svc = ContactsService(db)
    results = await svc.search_gcs(q, limit=limit)
    return ApiResponse(data=results, message=f"{len(results)} matches")


@router.get("/general-contractors/{gc_id}")
async def get_gc(
    gc_id: int,
    user: dict = Depends(require_permission("view_contractors")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Full GC detail with contacts and job count."""
    svc = ContactsService(db)
    detail = await svc.get_gc_detail(gc_id)
    if not detail:
        raise HTTPException(status_code=404, detail="General contractor not found")
    return ApiResponse(data=detail, message="Contractor detail loaded")


@router.post("/general-contractors", status_code=status.HTTP_201_CREATED)
async def create_gc(
    data: GCCreate,
    user: dict = Depends(require_permission("manage_contractors")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new general contractor."""
    svc = ContactsService(db)
    new_id = await svc.create_gc(data)
    detail = await svc.get_gc_detail(new_id)
    return ApiResponse(data=detail, message="Contractor created")


@router.put("/general-contractors/{gc_id}")
async def update_gc(
    gc_id: int,
    data: GCUpdate,
    user: dict = Depends(require_permission("manage_contractors")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a general contractor's information."""
    svc = ContactsService(db)
    updated = await svc.update_gc(gc_id, data)
    if not updated:
        raise HTTPException(status_code=404, detail="Contractor not found or no changes")
    detail = await svc.get_gc_detail(gc_id)
    return ApiResponse(data=detail, message="Contractor updated")


@router.patch("/general-contractors/{gc_id}/toggle-active")
async def toggle_gc_active(
    gc_id: int,
    is_active: bool = Query(..., description="New active status"),
    user: dict = Depends(require_permission("manage_contractors")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Activate or deactivate a general contractor."""
    svc = ContactsService(db)
    toggled = await svc.toggle_gc_active(gc_id, is_active)
    if not toggled:
        raise HTTPException(status_code=404, detail="Contractor not found")
    action = "activated" if is_active else "deactivated"
    return ApiResponse(
        data={"gc_id": gc_id, "is_active": is_active},
        message=f"Contractor {action}",
    )


@router.get("/general-contractors/{gc_id}/contacts")
async def get_gc_contacts(
    gc_id: int,
    include_inactive: bool = Query(False, description="Include inactive contacts"),
    user: dict = Depends(require_permission("view_contractors")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all contacts for a general contractor."""
    svc = ContactsService(db)
    contacts = await svc.get_entity_contacts(
        "general_contractor", gc_id, include_inactive=include_inactive,
    )
    return ApiResponse(data=contacts, message=f"{len(contacts)} contacts")


@router.post("/general-contractors/{gc_id}/contacts", status_code=status.HTTP_201_CREATED)
async def add_gc_contact(
    gc_id: int,
    data: EntityContactCreate,
    user: dict = Depends(require_permission("manage_contractors")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Add a contact to a general contractor."""
    svc = ContactsService(db)
    contact_id = await svc.add_entity_contact("general_contractor", gc_id, data)
    return ApiResponse(data={"id": contact_id}, message="Contact added")


@router.get("/general-contractors/{gc_id}/jobs")
async def get_gc_jobs(
    gc_id: int,
    user: dict = Depends(require_permission("view_contractors")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all jobs linked to a GC (reverse of GET /jobs/{id}/general-contractors)."""
    svc = ContactsService(db)
    jobs = await svc.get_gc_jobs(gc_id)
    return ApiResponse(data=jobs, message=f"{len(jobs)} linked jobs")


# ═════════════════════════════════════════════════════════════════
# SUPPLIER CONTACTS (entity_contacts for suppliers)
# ═════════════════════════════════════════════════════════════════


@router.get("/suppliers/{supplier_id}/contacts")
async def get_supplier_contacts(
    supplier_id: int,
    include_inactive: bool = Query(False),
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all contacts for a supplier."""
    svc = ContactsService(db)
    contacts = await svc.get_entity_contacts(
        "supplier", supplier_id, include_inactive=include_inactive,
    )
    return ApiResponse(data=contacts, message=f"{len(contacts)} contacts")


@router.post("/suppliers/{supplier_id}/contacts", status_code=status.HTTP_201_CREATED)
async def add_supplier_contact(
    supplier_id: int,
    data: EntityContactCreate,
    user: dict = Depends(require_permission("edit_parts_catalog")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Add a contact to a supplier."""
    svc = ContactsService(db)
    contact_id = await svc.add_entity_contact("supplier", supplier_id, data)
    return ApiResponse(data={"id": contact_id}, message="Contact added")


# ═════════════════════════════════════════════════════════════════
# ENTITY CONTACTS (cross-entity operations)
# ═════════════════════════════════════════════════════════════════


@router.get("/directory")
async def search_directory(
    q: str = Query(..., min_length=1, description="Search query"),
    limit: int = Query(50, ge=1, le=200, description="Max results"),
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Unified contact directory search across all entity types.

    Searches entity_contacts for customers, GCs, and suppliers by
    name, role, phone, or email. Returns results with the parent
    entity name and type badge.
    """
    svc = ContactsService(db)
    results = await svc.search_all_contacts(q, limit=limit)
    return ApiResponse(data=results, message=f"{len(results)} contacts found")


@router.put("/entity-contacts/{contact_id}")
async def update_entity_contact(
    contact_id: int,
    data: EntityContactUpdate,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update an entity contact."""
    # Caller needs manage_customers OR manage_contractors OR edit_parts_catalog (for suppliers).
    perms = user.get("permissions", [])
    has_mgmt = any(p in perms for p in ("manage_customers", "manage_contractors", "edit_parts_catalog"))
    if not has_mgmt:
        raise HTTPException(status_code=403, detail="Management permission required")

    svc = ContactsService(db)
    updated = await svc.update_entity_contact(contact_id, data)
    if not updated:
        raise HTTPException(status_code=404, detail="Contact not found or no changes")
    return ApiResponse(data={"id": contact_id}, message="Contact updated")


@router.delete("/entity-contacts/{contact_id}")
async def delete_entity_contact(
    contact_id: int,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Soft-delete an entity contact (set is_active = 0)."""
    perms = user.get("permissions", [])
    has_mgmt = any(p in perms for p in ("manage_customers", "manage_contractors", "edit_parts_catalog"))
    if not has_mgmt:
        raise HTTPException(status_code=403, detail="Management permission required")

    svc = ContactsService(db)
    deleted = await svc.delete_entity_contact(contact_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Contact not found")
    return ApiResponse(data={"id": contact_id}, message="Contact deactivated")


# ═════════════════════════════════════════════════════════════════
# CSV IMPORT
# ═════════════════════════════════════════════════════════════════


@router.post("/import/customers")
async def import_customers_csv(
    file: UploadFile = File(...),
    user: dict = Depends(require_permission("manage_customers")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Import customers from a CSV file.

    Expected columns: name, code (optional), email, phone, address,
    city, state, zip_code, notes.
    Returns { created, skipped, errors }.
    """
    content = await file.read()
    text = content.decode("utf-8-sig")
    reader = csv.DictReader(io.StringIO(text))

    svc = ContactsService(db)
    created, skipped, errors = 0, 0, []

    for i, row in enumerate(reader, start=2):
        name = (row.get("name") or "").strip()
        if not name:
            errors.append({"row": i, "error": "Missing name"})
            continue

        # Check for duplicate by name
        existing = await db.execute(
            "SELECT id FROM customers WHERE LOWER(name) = LOWER(?) AND is_active = 1",
            (name,),
        )
        if await existing.fetchone():
            skipped += 1
            continue

        try:
            cust_data = CustomerCreate(
                name=name,
                code=row.get("code", "").strip() or None,
                email=row.get("email", "").strip() or None,
                phone=row.get("phone", "").strip() or None,
                address=row.get("address", "").strip() or None,
                city=row.get("city", "").strip() or None,
                state=row.get("state", "").strip() or None,
                zip_code=row.get("zip_code", "").strip() or None,
                notes=row.get("notes", "").strip() or None,
            )
            await svc.create_customer(cust_data)
            created += 1
        except Exception as e:
            errors.append({"row": i, "error": str(e)})

    return ApiResponse(
        data={"created": created, "skipped": skipped, "errors": errors},
        message=f"{created} customers imported, {skipped} skipped",
    )


@router.post("/import/contractors")
async def import_contractors_csv(
    file: UploadFile = File(...),
    user: dict = Depends(require_permission("manage_contractors")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Import general contractors from a CSV file.

    Expected columns: name, code (optional), contact_name, email, phone,
    specialty, license_number, notes.
    """
    content = await file.read()
    text = content.decode("utf-8-sig")
    reader = csv.DictReader(io.StringIO(text))

    svc = ContactsService(db)
    created, skipped, errors = 0, 0, []

    for i, row in enumerate(reader, start=2):
        name = (row.get("name") or "").strip()
        if not name:
            errors.append({"row": i, "error": "Missing name"})
            continue

        existing = await db.execute(
            "SELECT id FROM general_contractors WHERE LOWER(name) = LOWER(?) AND is_active = 1",
            (name,),
        )
        if await existing.fetchone():
            skipped += 1
            continue

        try:
            gc_data = GCCreate(
                name=name,
                code=row.get("code", "").strip() or None,
                contact_name=row.get("contact_name", "").strip() or None,
                email=row.get("email", "").strip() or None,
                phone=row.get("phone", "").strip() or None,
                specialty=row.get("specialty", "").strip() or None,
                license_number=row.get("license_number", "").strip() or None,
                notes=row.get("notes", "").strip() or None,
            )
            await svc.create_gc(gc_data)
            created += 1
        except Exception as e:
            errors.append({"row": i, "error": str(e)})

    return ApiResponse(
        data={"created": created, "skipped": skipped, "errors": errors},
        message=f"{created} contractors imported, {skipped} skipped",
    )


# ═════════════════════════════════════════════════════════════════
# CONTACT DEDUPE / MERGE
# ═════════════════════════════════════════════════════════════════


@router.get("/dedupe/customers")
async def find_duplicate_customers(
    threshold: float = Query(0.8, ge=0.5, le=1.0, description="Similarity threshold"),
    user: dict = Depends(require_permission("manage_customers")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Find potential duplicate customers based on name similarity.

    Returns pairs of customers that may be duplicates.
    """
    cursor = await db.execute(
        "SELECT id, name, email, phone FROM customers WHERE is_active = 1 ORDER BY name",
    )
    customers = [dict(r) for r in await cursor.fetchall()]

    duplicates: list[dict[str, Any]] = []
    for i, a in enumerate(customers):
        for b in customers[i + 1:]:
            # Simple Jaccard similarity on lowercased name words
            words_a = set(a["name"].lower().split())
            words_b = set(b["name"].lower().split())
            if not words_a or not words_b:
                continue
            similarity = len(words_a & words_b) / len(words_a | words_b)
            if similarity >= threshold:
                duplicates.append({
                    "a": a,
                    "b": b,
                    "similarity": round(similarity, 2),
                    "match_type": "name",
                })

            # Exact email match
            if a.get("email") and a["email"] == b.get("email"):
                if not any(d["a"]["id"] == a["id"] and d["b"]["id"] == b["id"] for d in duplicates):
                    duplicates.append({
                        "a": a,
                        "b": b,
                        "similarity": 1.0,
                        "match_type": "email",
                    })

    return ApiResponse(
        data=duplicates,
        message=f"{len(duplicates)} potential duplicates found",
    )


@router.post("/merge/customers")
async def merge_customers(
    keep_id: int = Body(..., embed=True),
    merge_id: int = Body(..., embed=True),
    user: dict = Depends(require_permission("manage_customers")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Merge two customers: keep one, deactivate the other.

    All entity_contacts of the merged customer are re-pointed to the kept one.
    Jobs referencing the merged customer are updated.
    """
    # Verify both exist
    for cid in (keep_id, merge_id):
        cur = await db.execute("SELECT id FROM customers WHERE id = ?", (cid,))
        if not await cur.fetchone():
            raise HTTPException(status_code=404, detail=f"Customer {cid} not found")

    # Re-point entity contacts
    await db.execute(
        """UPDATE entity_contacts SET entity_id = ?
           WHERE entity_type = 'customer' AND entity_id = ?""",
        (keep_id, merge_id),
    )
    # Re-point jobs
    await db.execute(
        "UPDATE jobs SET customer_id = ? WHERE customer_id = ?",
        (keep_id, merge_id),
    )
    # Deactivate the merged customer
    await db.execute(
        "UPDATE customers SET is_active = 0 WHERE id = ?",
        (merge_id,),
    )
    await db.commit()

    return ApiResponse(
        data={"keep_id": keep_id, "merged_id": merge_id},
        message=f"Customer #{merge_id} merged into #{keep_id}",
    )
