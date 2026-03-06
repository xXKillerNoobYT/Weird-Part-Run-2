"""
Contacts service — orchestrates customer, GC, entity contact, and job-linking operations.

Thin business-logic layer between routers and repositories.  Handles
pagination math, cross-repo assembly (e.g. hydrating detail views with
contacts + job links), and the GC PO-prefix lookup used by the orders module.
"""

from __future__ import annotations

import math
from typing import Any

import aiosqlite

from app.models.contacts import (
    CustomerCreate,
    CustomerUpdate,
    EntityContactCreate,
    EntityContactUpdate,
    GCCreate,
    GCUpdate,
    JobCustomerCreate,
    JobGCCreate,
)
from app.repositories.contacts_repo import (
    CustomerRepo,
    EntityContactRepo,
    GeneralContractorRepo,
    JobCustomerRepo,
    JobGCRepo,
)


class ContactsService:
    """Stateless service — instantiate with a DB connection per request."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.customer_repo = CustomerRepo(db)
        self.gc_repo = GeneralContractorRepo(db)
        self.contact_repo = EntityContactRepo(db)
        self.job_customer_repo = JobCustomerRepo(db)
        self.job_gc_repo = JobGCRepo(db)

    # ── Customers ───────────────────────────────────────────────────

    async def list_customers(
        self,
        *,
        search: str | None = None,
        customer_type: str | None = None,
        is_active: bool | None = None,
        page: int = 1,
        page_size: int = 50,
    ) -> dict[str, Any]:
        """Paginated customer list with job/contact counts.

        Returns: { items, total, page, page_size, total_pages }
        """
        offset = (page - 1) * page_size
        items = await self.customer_repo.list_with_counts(
            search=search,
            customer_type=customer_type,
            is_active=is_active,
            limit=page_size,
            offset=offset,
        )
        total = await self.customer_repo.count_filtered(
            search=search,
            customer_type=customer_type,
            is_active=is_active,
        )
        return {
            "items": items,
            "total": total,
            "page": page,
            "page_size": page_size,
            "total_pages": max(1, math.ceil(total / page_size)),
        }

    async def get_customer_detail(self, customer_id: int) -> dict | None:
        """Assemble full customer detail with contacts and job count."""
        customer = await self.customer_repo.get_by_id(customer_id)
        if not customer:
            return None

        contacts = await self.contact_repo.get_for_entity("customer", customer_id)
        jobs = await self.job_customer_repo.get_for_customer(customer_id)

        customer["contacts"] = contacts
        customer["job_count"] = len(jobs)
        return customer

    async def create_customer(self, data: CustomerCreate) -> int:
        """Create a new customer. Returns the new customer ID."""
        return await self.customer_repo.insert(data.model_dump())

    async def update_customer(self, customer_id: int, data: CustomerUpdate) -> bool:
        """Partial update for a customer."""
        update_dict = {
            k: v
            for k, v in data.model_dump(exclude_unset=True).items()
            if v is not None
        }
        if not update_dict:
            return False
        return await self.customer_repo.update(customer_id, update_dict)

    async def toggle_customer_active(self, customer_id: int, is_active: bool) -> bool:
        """Activate or deactivate a customer."""
        return await self.customer_repo.update(
            customer_id, {"is_active": 1 if is_active else 0}
        )

    async def search_customers(self, query: str, limit: int = 20) -> list[dict]:
        """Quick autocomplete search for customers."""
        return await self.customer_repo.search(query, limit=limit)

    # ── General Contractors ─────────────────────────────────────────

    async def list_gcs(
        self,
        *,
        search: str | None = None,
        trade_type: str | None = None,
        is_active: bool | None = None,
        page: int = 1,
        page_size: int = 50,
    ) -> dict[str, Any]:
        """Paginated GC list with job/contact counts.

        Returns: { items, total, page, page_size, total_pages }
        """
        offset = (page - 1) * page_size
        items = await self.gc_repo.list_with_counts(
            search=search,
            trade_type=trade_type,
            is_active=is_active,
            limit=page_size,
            offset=offset,
        )
        total = await self.gc_repo.count_filtered(
            search=search,
            trade_type=trade_type,
            is_active=is_active,
        )
        return {
            "items": items,
            "total": total,
            "page": page,
            "page_size": page_size,
            "total_pages": max(1, math.ceil(total / page_size)),
        }

    async def get_gc_detail(self, gc_id: int) -> dict | None:
        """Assemble full GC detail with contacts and job count."""
        gc = await self.gc_repo.get_by_id(gc_id)
        if not gc:
            return None

        contacts = await self.contact_repo.get_for_entity("general_contractor", gc_id)
        jobs = await self.job_gc_repo.get_for_gc(gc_id)

        gc["contacts"] = contacts
        gc["job_count"] = len(jobs)
        return gc

    async def create_gc(self, data: GCCreate) -> int:
        """Create a new general contractor. Returns the new GC ID."""
        return await self.gc_repo.insert(data.model_dump())

    async def update_gc(self, gc_id: int, data: GCUpdate) -> bool:
        """Partial update for a general contractor."""
        update_dict = {
            k: v
            for k, v in data.model_dump(exclude_unset=True).items()
            if v is not None
        }
        if not update_dict:
            return False
        return await self.gc_repo.update(gc_id, update_dict)

    async def toggle_gc_active(self, gc_id: int, is_active: bool) -> bool:
        """Activate or deactivate a GC."""
        return await self.gc_repo.update(
            gc_id, {"is_active": 1 if is_active else 0}
        )

    async def search_gcs(self, query: str, limit: int = 20) -> list[dict]:
        """Quick autocomplete search for GCs."""
        return await self.gc_repo.search(query, limit=limit)

    async def get_gc_by_code(self, gc_code: str) -> dict | None:
        """Lookup a GC by its unique code (for PO naming)."""
        return await self.gc_repo.get_by_code(gc_code)

    # ── Entity Contacts ─────────────────────────────────────────────

    async def get_entity_contacts(
        self,
        entity_type: str,
        entity_id: int,
        *,
        include_inactive: bool = False,
    ) -> list[dict]:
        """Get all contacts for a customer, GC, or supplier."""
        return await self.contact_repo.get_for_entity(
            entity_type, entity_id, include_inactive=include_inactive,
        )

    async def add_entity_contact(
        self,
        entity_type: str,
        entity_id: int,
        data: EntityContactCreate,
    ) -> int:
        """Add a contact to an entity. Returns the new contact ID."""
        return await self.contact_repo.add_contact(
            entity_type, entity_id, data.model_dump(),
        )

    async def update_entity_contact(
        self, contact_id: int, data: EntityContactUpdate,
    ) -> bool:
        """Partial update for an entity contact."""
        update_dict = {
            k: v
            for k, v in data.model_dump(exclude_unset=True).items()
            if v is not None
        }
        if not update_dict:
            return False
        return await self.contact_repo.update(contact_id, update_dict)

    async def delete_entity_contact(self, contact_id: int) -> bool:
        """Soft-delete an entity contact (set is_active = 0)."""
        return await self.contact_repo.update(contact_id, {"is_active": 0})

    async def search_all_contacts(self, query: str, limit: int = 50) -> list[dict]:
        """Unified directory search across all entity types."""
        return await self.contact_repo.search_all(query, limit=limit)

    # ── Job ↔ Customer Linking ──────────────────────────────────────

    async def get_job_customers(self, job_id: int) -> list[dict]:
        """Get all customers linked to a job."""
        return await self.job_customer_repo.get_for_job(job_id)

    async def get_customer_jobs(self, customer_id: int) -> list[dict]:
        """Get all jobs linked to a customer."""
        return await self.job_customer_repo.get_for_customer(customer_id)

    async def link_customer_to_job(self, job_id: int, data: JobCustomerCreate) -> int:
        """Link a customer to a job. Returns the link row ID."""
        return await self.job_customer_repo.link({
            "job_id": job_id,
            "customer_id": data.customer_id,
            "contact_role": data.contact_role,
            "is_primary": 1 if data.is_primary else 0,
            "notes": data.notes,
        })

    async def unlink_customer_from_job(self, link_id: int) -> bool:
        """Remove a customer link from a job."""
        return await self.job_customer_repo.unlink(link_id)

    # ── Job ↔ GC Linking ────────────────────────────────────────────

    async def get_job_gcs(self, job_id: int) -> list[dict]:
        """Get all GCs linked to a job."""
        return await self.job_gc_repo.get_for_job(job_id)

    async def get_gc_jobs(self, gc_id: int) -> list[dict]:
        """Get all jobs linked to a GC."""
        return await self.job_gc_repo.get_for_gc(gc_id)

    async def link_gc_to_job(self, job_id: int, data: JobGCCreate) -> int:
        """Link a GC to a job. Returns the link row ID."""
        return await self.job_gc_repo.link({
            "job_id": job_id,
            "gc_id": data.gc_id,
            "relationship": data.relationship,
            "contract_amount": data.contract_amount,
            "contract_number": data.contract_number,
            "is_primary": 1 if data.is_primary else 0,
            "notes": data.notes,
        })

    async def unlink_gc_from_job(self, link_id: int) -> bool:
        """Remove a GC link from a job."""
        return await self.job_gc_repo.unlink(link_id)

    # ── GC PO Prefix ────────────────────────────────────────────────

    async def get_gc_po_prefix(self, job_id: int) -> str | None:
        """Get the GC code to use as PO prefix for a job.

        Returns the gc_code of the primary GC with relationship='they_are_gc',
        or None if no such GC exists.  Used by orders_service when generating
        PO numbers — format becomes PO={gc_code}+{job_id}+{seq}.
        """
        primary_gc = await self.job_gc_repo.get_primary_gc_for_job(
            job_id, relationship="they_are_gc",
        )
        if primary_gc:
            return primary_gc.get("gc_code")
        return None
