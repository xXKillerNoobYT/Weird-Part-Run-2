"""
Contacts repositories — customers, general contractors, entity contacts,
and job-linking junction tables.

Each repo extends BaseRepo for standard CRUD and adds domain-specific
queries (JOINs for counts, unified search, etc.).
"""

from __future__ import annotations

from typing import Any

import aiosqlite

from .base import BaseRepo


# ── CustomerRepo ──────────────────────────────────────────────────

class CustomerRepo(BaseRepo):
    """CRUD + list-with-counts for the customers table."""

    TABLE = "customers"
    HAS_UPDATED_AT = True

    async def list_with_counts(
        self,
        *,
        search: str | None = None,
        customer_type: str | None = None,
        is_active: bool | None = None,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict]:
        """List customers with aggregated job_count and contact_count."""
        conditions: list[str] = []
        params: list[Any] = []

        if search:
            conditions.append(
                "(c.first_name LIKE ? OR c.last_name LIKE ? "
                "OR c.company_name LIKE ? OR c.email LIKE ? OR c.phone LIKE ?)"
            )
            q = f"%{search}%"
            params.extend([q, q, q, q, q])

        if customer_type:
            conditions.append("c.customer_type = ?")
            params.append(customer_type)

        if is_active is not None:
            conditions.append("c.is_active = ?")
            params.append(1 if is_active else 0)

        where = " AND ".join(conditions) if conditions else "1=1"

        sql = f"""
            SELECT c.*,
                   COUNT(DISTINCT jc.id) AS job_count,
                   COUNT(DISTINCT ec.id) AS contact_count
            FROM customers c
            LEFT JOIN job_customers jc ON jc.customer_id = c.id
            LEFT JOIN entity_contacts ec ON ec.entity_type = 'customer'
                                         AND ec.entity_id = c.id
                                         AND ec.is_active = 1
            WHERE {where}
            GROUP BY c.id
            ORDER BY c.last_name ASC, c.first_name ASC
            LIMIT ? OFFSET ?
        """
        params.extend([limit, offset])
        cursor = await self.db.execute(sql, params)
        return await cursor.fetchall()

    async def count_filtered(
        self,
        *,
        search: str | None = None,
        customer_type: str | None = None,
        is_active: bool | None = None,
    ) -> int:
        """Count customers matching filters."""
        conditions: list[str] = []
        params: list[Any] = []

        if search:
            conditions.append(
                "(first_name LIKE ? OR last_name LIKE ? "
                "OR company_name LIKE ? OR email LIKE ? OR phone LIKE ?)"
            )
            q = f"%{search}%"
            params.extend([q, q, q, q, q])

        if customer_type:
            conditions.append("customer_type = ?")
            params.append(customer_type)

        if is_active is not None:
            conditions.append("is_active = ?")
            params.append(1 if is_active else 0)

        where = " AND ".join(conditions) if conditions else "1=1"
        cursor = await self.db.execute(
            f"SELECT COUNT(*) AS cnt FROM customers WHERE {where}", params
        )
        row = await cursor.fetchone()
        return row["cnt"] if row else 0

    async def search(self, query: str, limit: int = 20) -> list[dict]:
        """Quick search for autocomplete — name/company match."""
        q = f"%{query}%"
        cursor = await self.db.execute(
            """SELECT id, company_name, first_name, last_name, display_name,
                      phone, email, customer_type, is_active
               FROM customers
               WHERE is_active = 1
                 AND (first_name LIKE ? OR last_name LIKE ?
                      OR company_name LIKE ? OR display_name LIKE ?)
               ORDER BY display_name ASC
               LIMIT ?""",
            (q, q, q, q, limit),
        )
        return await cursor.fetchall()


# ── GeneralContractorRepo ─────────────────────────────────────────

class GeneralContractorRepo(BaseRepo):
    """CRUD + list-with-counts for the general_contractors table."""

    TABLE = "general_contractors"
    HAS_UPDATED_AT = True

    async def list_with_counts(
        self,
        *,
        search: str | None = None,
        trade_type: str | None = None,
        is_active: bool | None = None,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict]:
        """List GCs with aggregated job_count and contact_count."""
        conditions: list[str] = []
        params: list[Any] = []

        if search:
            conditions.append(
                "(g.company_name LIKE ? OR g.gc_code LIKE ? "
                "OR g.email LIKE ? OR g.phone LIKE ?)"
            )
            q = f"%{search}%"
            params.extend([q, q, q, q])

        if trade_type:
            conditions.append("g.trade_type = ?")
            params.append(trade_type)

        if is_active is not None:
            conditions.append("g.is_active = ?")
            params.append(1 if is_active else 0)

        where = " AND ".join(conditions) if conditions else "1=1"

        sql = f"""
            SELECT g.*,
                   COUNT(DISTINCT jg.id) AS job_count,
                   COUNT(DISTINCT ec.id) AS contact_count
            FROM general_contractors g
            LEFT JOIN job_general_contractors jg ON jg.gc_id = g.id
            LEFT JOIN entity_contacts ec ON ec.entity_type = 'general_contractor'
                                         AND ec.entity_id = g.id
                                         AND ec.is_active = 1
            WHERE {where}
            GROUP BY g.id
            ORDER BY g.company_name ASC
            LIMIT ? OFFSET ?
        """
        params.extend([limit, offset])
        cursor = await self.db.execute(sql, params)
        return await cursor.fetchall()

    async def count_filtered(
        self,
        *,
        search: str | None = None,
        trade_type: str | None = None,
        is_active: bool | None = None,
    ) -> int:
        """Count GCs matching filters."""
        conditions: list[str] = []
        params: list[Any] = []

        if search:
            conditions.append(
                "(company_name LIKE ? OR gc_code LIKE ? "
                "OR email LIKE ? OR phone LIKE ?)"
            )
            q = f"%{search}%"
            params.extend([q, q, q, q])

        if trade_type:
            conditions.append("trade_type = ?")
            params.append(trade_type)

        if is_active is not None:
            conditions.append("is_active = ?")
            params.append(1 if is_active else 0)

        where = " AND ".join(conditions) if conditions else "1=1"
        cursor = await self.db.execute(
            f"SELECT COUNT(*) AS cnt FROM general_contractors WHERE {where}", params
        )
        row = await cursor.fetchone()
        return row["cnt"] if row else 0

    async def get_by_code(self, gc_code: str) -> dict | None:
        """Lookup a GC by its unique gc_code."""
        cursor = await self.db.execute(
            "SELECT * FROM general_contractors WHERE gc_code = ?",
            (gc_code,),
        )
        return await cursor.fetchone()

    async def search(self, query: str, limit: int = 20) -> list[dict]:
        """Quick search for autocomplete — name/code match."""
        q = f"%{query}%"
        cursor = await self.db.execute(
            """SELECT id, company_name, gc_code, trade_type, phone, email, is_active
               FROM general_contractors
               WHERE is_active = 1
                 AND (company_name LIKE ? OR gc_code LIKE ?)
               ORDER BY company_name ASC
               LIMIT ?""",
            (q, q, limit),
        )
        return await cursor.fetchall()


# ── EntityContactRepo ─────────────────────────────────────────────

class EntityContactRepo(BaseRepo):
    """CRUD for the polymorphic entity_contacts table."""

    TABLE = "entity_contacts"
    HAS_UPDATED_AT = True

    async def get_for_entity(
        self,
        entity_type: str,
        entity_id: int,
        *,
        include_inactive: bool = False,
    ) -> list[dict]:
        """Get all contacts for a specific entity."""
        where = "entity_type = ? AND entity_id = ?"
        params: list[Any] = [entity_type, entity_id]

        if not include_inactive:
            where += " AND is_active = 1"

        cursor = await self.db.execute(
            f"""SELECT * FROM entity_contacts
                WHERE {where}
                ORDER BY is_primary DESC, last_name ASC, first_name ASC""",
            params,
        )
        return await cursor.fetchall()

    async def search_all(self, query: str, limit: int = 50) -> list[dict]:
        """Unified directory search across all entity types.

        Joins to parent entities to resolve entity_name for display.
        Returns contacts from customers, GCs, and suppliers.
        """
        q = f"%{query}%"
        sql = """
            SELECT ec.id, ec.first_name, ec.last_name, ec.role,
                   ec.phone, ec.email, ec.entity_type, ec.entity_id,
                   CASE ec.entity_type
                       WHEN 'customer' THEN c.display_name
                       WHEN 'general_contractor' THEN g.company_name
                       WHEN 'supplier' THEN s.name
                       ELSE ''
                   END AS entity_name
            FROM entity_contacts ec
            LEFT JOIN customers c ON ec.entity_type = 'customer'
                                  AND ec.entity_id = c.id
            LEFT JOIN general_contractors g ON ec.entity_type = 'general_contractor'
                                           AND ec.entity_id = g.id
            LEFT JOIN suppliers s ON ec.entity_type = 'supplier'
                                  AND ec.entity_id = s.id
            WHERE ec.is_active = 1
              AND (ec.first_name LIKE ? OR ec.last_name LIKE ?
                   OR ec.role LIKE ? OR ec.phone LIKE ? OR ec.email LIKE ?)
            ORDER BY ec.last_name ASC, ec.first_name ASC
            LIMIT ?
        """
        cursor = await self.db.execute(sql, (q, q, q, q, q, limit))
        return await cursor.fetchall()

    async def add_contact(
        self, entity_type: str, entity_id: int, data: dict
    ) -> int:
        """Insert a contact for a given entity, returning the new id."""
        full_data = {**data, "entity_type": entity_type, "entity_id": entity_id}
        return await self.insert(full_data)


# ── JobCustomerRepo ───────────────────────────────────────────────

class JobCustomerRepo(BaseRepo):
    """Junction table: jobs ↔ customers."""

    TABLE = "job_customers"

    async def get_for_job(self, job_id: int) -> list[dict]:
        """Get all customer links for a job, with customer details."""
        cursor = await self.db.execute(
            """SELECT jc.*, c.display_name AS customer_name,
                      c.company_name, c.phone, c.email
               FROM job_customers jc
               JOIN customers c ON c.id = jc.customer_id
               WHERE jc.job_id = ?
               ORDER BY jc.is_primary DESC, c.display_name ASC""",
            (job_id,),
        )
        return await cursor.fetchall()

    async def get_for_customer(self, customer_id: int) -> list[dict]:
        """Get all jobs linked to a customer."""
        cursor = await self.db.execute(
            """SELECT jc.*, j.job_name AS job_name, j.status AS job_status
               FROM job_customers jc
               JOIN jobs j ON j.id = jc.job_id
               WHERE jc.customer_id = ?
               ORDER BY j.created_at DESC""",
            (customer_id,),
        )
        return await cursor.fetchall()

    async def link(self, data: dict) -> int:
        """Create a job-customer link."""
        return await self.insert(data)

    async def unlink(self, link_id: int) -> bool:
        """Remove a job-customer link."""
        return await self.delete(link_id)


# ── JobGCRepo ─────────────────────────────────────────────────────

class JobGCRepo(BaseRepo):
    """Junction table: jobs ↔ general contractors."""

    TABLE = "job_general_contractors"

    async def get_for_job(self, job_id: int) -> list[dict]:
        """Get all GC links for a job, with GC details."""
        cursor = await self.db.execute(
            """SELECT jg.*, g.company_name, g.gc_code, g.trade_type,
                      g.phone, g.email
               FROM job_general_contractors jg
               JOIN general_contractors g ON g.id = jg.gc_id
               WHERE jg.job_id = ?
               ORDER BY jg.is_primary DESC, g.company_name ASC""",
            (job_id,),
        )
        return await cursor.fetchall()

    async def get_for_gc(self, gc_id: int) -> list[dict]:
        """Get all jobs linked to a GC."""
        cursor = await self.db.execute(
            """SELECT jg.*, j.job_name AS job_name, j.status AS job_status
               FROM job_general_contractors jg
               JOIN jobs j ON j.id = jg.job_id
               WHERE jg.gc_id = ?
               ORDER BY j.created_at DESC""",
            (gc_id,),
        )
        return await cursor.fetchall()

    async def get_primary_gc_for_job(
        self, job_id: int, relationship: str = "they_are_gc"
    ) -> dict | None:
        """Get the primary GC for a job with a specific relationship.

        Used by PO naming: when relationship='they_are_gc' and is_primary=1,
        the GC's gc_code is used in the PO number format.
        """
        cursor = await self.db.execute(
            """SELECT jg.*, g.company_name, g.gc_code
               FROM job_general_contractors jg
               JOIN general_contractors g ON g.id = jg.gc_id
               WHERE jg.job_id = ? AND jg.relationship = ? AND jg.is_primary = 1
               LIMIT 1""",
            (job_id, relationship),
        )
        return await cursor.fetchone()

    async def link(self, data: dict) -> int:
        """Create a job-GC link."""
        return await self.insert(data)

    async def unlink(self, link_id: int) -> bool:
        """Remove a job-GC link."""
        return await self.delete(link_id)
