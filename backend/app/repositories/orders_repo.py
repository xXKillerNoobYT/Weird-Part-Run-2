"""
Repositories for the Orders & Procurement system.

Covers JPOs, POs, PO line items, returns, price history,
supplier contact ratings, and order status history.
Each repo extends BaseRepo for standard CRUD; domain-specific
queries live here.
"""

from __future__ import annotations

from typing import Any

import aiosqlite

from app.repositories.base import BaseRepo


# ═══════════════════════════════════════════════════════════════
# JPO Repository
# ═══════════════════════════════════════════════════════════════

class JPORepo(BaseRepo):
    TABLE = "job_parts_orders"
    HAS_UPDATED_AT = True

    async def get_next_order_number(self, job_id: int | None = None) -> str:
        """Generate the next JPO order number.

        Job orders:       '{JOB_NAME}-JPO-001' (scoped to the job)
        Warehouse restocks: 'WH-JPO-001' (global sequence)
        """
        if job_id:
            cursor = await self.db.execute(
                "SELECT job_name FROM jobs WHERE id = ?", (job_id,)
            )
            job = await cursor.fetchone()
            prefix = (job["job_name"] if job else "JOB").upper().replace(" ", "-")[:20]

            cursor = await self.db.execute(
                "SELECT COUNT(*) as cnt FROM job_parts_orders WHERE job_id = ?",
                (job_id,),
            )
            row = await cursor.fetchone()
            seq = (row["cnt"] if row else 0) + 1
            return f"{prefix}-JPO-{seq:03d}"
        else:
            # Warehouse restock — global sequence
            cursor = await self.db.execute(
                "SELECT COUNT(*) as cnt FROM job_parts_orders WHERE job_id IS NULL"
            )
            row = await cursor.fetchone()
            seq = (row["cnt"] if row else 0) + 1
            return f"WH-JPO-{seq:03d}"

    async def list_with_details(
        self,
        *,
        status: str | None = None,
        job_id: int | None = None,
        requested_by: int | None = None,
        order_type: str | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """List JPOs with joined job and user info.

        Uses LEFT JOIN on jobs so warehouse restocks (job_id IS NULL)
        are still included in results.
        """
        sql = """
            SELECT jpo.*,
                   j.job_name, j.job_number,
                   u.display_name AS requester_name,
                   (SELECT COUNT(*) FROM jpo_line_items WHERE jpo_id = jpo.id) AS line_count
            FROM job_parts_orders jpo
            LEFT JOIN jobs j ON j.id = jpo.job_id
            JOIN users u ON u.id = jpo.requested_by
        """
        conditions: list[str] = []
        params: list[Any] = []

        if status:
            conditions.append("jpo.status = ?")
            params.append(status)
        if job_id:
            conditions.append("jpo.job_id = ?")
            params.append(job_id)
        if requested_by:
            conditions.append("jpo.requested_by = ?")
            params.append(requested_by)
        if order_type:
            conditions.append("jpo.order_type = ?")
            params.append(order_type)

        if conditions:
            sql += " WHERE " + " AND ".join(conditions)

        sql += " ORDER BY jpo.updated_at DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])

        cursor = await self.db.execute(sql, tuple(params))
        return await cursor.fetchall()

    async def count_filtered(
        self,
        *,
        status: str | None = None,
        job_id: int | None = None,
        requested_by: int | None = None,
        order_type: str | None = None,
    ) -> int:
        """Count JPOs matching filters."""
        sql = "SELECT COUNT(*) as cnt FROM job_parts_orders"
        conditions: list[str] = []
        params: list[Any] = []

        if status:
            conditions.append("status = ?")
            params.append(status)
        if job_id:
            conditions.append("job_id = ?")
            params.append(job_id)
        if requested_by:
            conditions.append("requested_by = ?")
            params.append(requested_by)
        if order_type:
            conditions.append("order_type = ?")
            params.append(order_type)

        if conditions:
            sql += " WHERE " + " AND ".join(conditions)

        cursor = await self.db.execute(sql, tuple(params))
        row = await cursor.fetchone()
        return row["cnt"] if row else 0

    async def get_with_details(self, jpo_id: int) -> dict | None:
        """Get a single JPO with all joined info.

        Uses LEFT JOIN on jobs so warehouse restocks (job_id IS NULL)
        are still returned correctly.
        """
        cursor = await self.db.execute(
            """
            SELECT jpo.*,
                   j.job_name, j.job_number,
                   u.display_name AS requester_name,
                   a.display_name AS approver_name,
                   (SELECT COUNT(*) FROM jpo_line_items WHERE jpo_id = jpo.id) AS line_count,
                   (SELECT COUNT(*) FROM special_items WHERE jpo_id = jpo.id) AS special_item_count
            FROM job_parts_orders jpo
            LEFT JOIN jobs j ON j.id = jpo.job_id
            JOIN users u ON u.id = jpo.requested_by
            LEFT JOIN users a ON a.id = jpo.approved_by
            WHERE jpo.id = ?
            """,
            (jpo_id,),
        )
        return await cursor.fetchone()


# ═══════════════════════════════════════════════════════════════
# JPO Line Items Repository
# ═══════════════════════════════════════════════════════════════

class JPOLineRepo(BaseRepo):
    TABLE = "jpo_line_items"

    async def get_lines_for_jpo(self, jpo_id: int) -> list[dict]:
        """Get all line items for a JPO with part and supplier info."""
        cursor = await self.db.execute(
            """
            SELECT li.*,
                   p.code AS part_number, p.description AS part_description,
                   s.name AS supplier_name
            FROM jpo_line_items li
            JOIN parts p ON p.id = li.part_id
            LEFT JOIN suppliers s ON s.id = li.suggested_supplier_id
            WHERE li.jpo_id = ?
            ORDER BY li.id
            """,
            (jpo_id,),
        )
        return await cursor.fetchall()

    async def get_unordered_lines(self, jpo_id: int) -> list[dict]:
        """Get JPO lines that haven't been fully ordered yet."""
        cursor = await self.db.execute(
            """
            SELECT li.*,
                   p.code AS part_number, p.description AS part_description,
                   s.name AS supplier_name
            FROM jpo_line_items li
            JOIN parts p ON p.id = li.part_id
            LEFT JOIN suppliers s ON s.id = li.suggested_supplier_id
            WHERE li.jpo_id = ? AND li.qty_ordered < li.qty_requested
            ORDER BY li.id
            """,
            (jpo_id,),
        )
        return await cursor.fetchall()

    async def bulk_insert(self, jpo_id: int, lines: list[dict]) -> list[int]:
        """Insert multiple line items at once. Returns list of new IDs."""
        ids = []
        for line in lines:
            line["jpo_id"] = jpo_id
            new_id = await self.insert(line)
            ids.append(new_id)
        return ids

    async def update_ordered_qty(self, line_id: int, additional_qty: int) -> None:
        """Increment qty_ordered for a JPO line."""
        await self.db.execute(
            "UPDATE jpo_line_items SET qty_ordered = qty_ordered + ? WHERE id = ?",
            (additional_qty, line_id),
        )

    async def update_received_qty(self, line_id: int, additional_qty: int) -> None:
        """Increment qty_received for a JPO line."""
        await self.db.execute(
            "UPDATE jpo_line_items SET qty_received = qty_received + ? WHERE id = ?",
            (additional_qty, line_id),
        )


# ═══════════════════════════════════════════════════════════════
# PO Repository
# ═══════════════════════════════════════════════════════════════

class PurchaseOrderRepo(BaseRepo):
    TABLE = "purchase_orders"
    HAS_UPDATED_AT = True

    async def get_next_po_number(self, supplier_id: int | None = None) -> str:
        """Generate the next PO number: 'PO-001' sequential."""
        cursor = await self.db.execute(
            "SELECT COUNT(*) as cnt FROM purchase_orders"
        )
        row = await cursor.fetchone()
        seq = (row["cnt"] if row else 0) + 1
        return f"PO-{seq:04d}"

    async def list_with_details(
        self,
        *,
        status: str | None = None,
        statuses: list[str] | None = None,
        supplier_id: int | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """List POs with joined supplier info."""
        sql = """
            SELECT po.*,
                   s.name AS supplier_name,
                   u.display_name AS submitter_name,
                   (SELECT COUNT(*) FROM po_line_items WHERE po_id = po.id) AS line_count
            FROM purchase_orders po
            JOIN suppliers s ON s.id = po.supplier_id
            LEFT JOIN users u ON u.id = po.submitted_by
        """
        conditions: list[str] = []
        params: list[Any] = []

        if status:
            conditions.append("po.status = ?")
            params.append(status)
        elif statuses:
            placeholders = ", ".join("?" for _ in statuses)
            conditions.append(f"po.status IN ({placeholders})")
            params.extend(statuses)
        if supplier_id:
            conditions.append("po.supplier_id = ?")
            params.append(supplier_id)

        if conditions:
            sql += " WHERE " + " AND ".join(conditions)

        sql += " ORDER BY po.updated_at DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])

        cursor = await self.db.execute(sql, tuple(params))
        return await cursor.fetchall()

    async def count_filtered(
        self,
        *,
        status: str | None = None,
        statuses: list[str] | None = None,
        supplier_id: int | None = None,
    ) -> int:
        """Count POs matching filters."""
        sql = "SELECT COUNT(*) as cnt FROM purchase_orders"
        conditions: list[str] = []
        params: list[Any] = []

        if status:
            conditions.append("status = ?")
            params.append(status)
        elif statuses:
            placeholders = ", ".join("?" for _ in statuses)
            conditions.append(f"status IN ({placeholders})")
            params.extend(statuses)
        if supplier_id:
            conditions.append("supplier_id = ?")
            params.append(supplier_id)

        if conditions:
            sql += " WHERE " + " AND ".join(conditions)

        cursor = await self.db.execute(sql, tuple(params))
        row = await cursor.fetchone()
        return row["cnt"] if row else 0

    async def get_with_details(self, po_id: int) -> dict | None:
        """Get a single PO with all joined info."""
        cursor = await self.db.execute(
            """
            SELECT po.*,
                   s.name AS supplier_name,
                   u.display_name AS submitter_name,
                   (SELECT COUNT(*) FROM po_line_items WHERE po_id = po.id) AS line_count
            FROM purchase_orders po
            JOIN suppliers s ON s.id = po.supplier_id
            LEFT JOIN users u ON u.id = po.submitted_by
            WHERE po.id = ?
            """,
            (po_id,),
        )
        return await cursor.fetchone()

    async def recalculate_totals(self, po_id: int) -> None:
        """Recalculate subtotal and total_cost from line items."""
        cursor = await self.db.execute(
            """
            SELECT COALESCE(SUM(qty_ordered * COALESCE(unit_cost, 0)), 0) as subtotal
            FROM po_line_items WHERE po_id = ?
            """,
            (po_id,),
        )
        row = await cursor.fetchone()
        subtotal = row["subtotal"] if row else 0

        # Get current tax + shipping
        cursor = await self.db.execute(
            "SELECT tax_amount, shipping_cost FROM purchase_orders WHERE id = ?",
            (po_id,),
        )
        po = await cursor.fetchone()
        tax = po["tax_amount"] if po else 0
        shipping = po["shipping_cost"] if po else 0
        total = subtotal + (tax or 0) + (shipping or 0)

        await self.db.execute(
            "UPDATE purchase_orders SET subtotal = ?, total_cost = ? WHERE id = ?",
            (subtotal, total, po_id),
        )

    async def get_open_for_supplier(self, supplier_id: int) -> list[dict]:
        """Get all open POs for a supplier (for receiving flow)."""
        cursor = await self.db.execute(
            """
            SELECT po.*, s.name AS supplier_name
            FROM purchase_orders po
            JOIN suppliers s ON s.id = po.supplier_id
            WHERE po.supplier_id = ? AND po.status IN ('submitted', 'acknowledged', 'partially_received')
            ORDER BY po.order_date
            """,
            (supplier_id,),
        )
        return await cursor.fetchall()


# ═══════════════════════════════════════════════════════════════
# PO Line Items Repository
# ═══════════════════════════════════════════════════════════════

class POLineRepo(BaseRepo):
    TABLE = "po_line_items"

    async def get_lines_for_po(self, po_id: int) -> list[dict]:
        """Get all line items for a PO with part info."""
        cursor = await self.db.execute(
            """
            SELECT li.*,
                   p.code AS part_number, p.description AS part_description,
                   (li.qty_ordered * COALESCE(li.unit_cost, 0)) AS line_total
            FROM po_line_items li
            JOIN parts p ON p.id = li.part_id
            WHERE li.po_id = ?
            ORDER BY li.id
            """,
            (po_id,),
        )
        return await cursor.fetchall()

    async def get_open_lines_for_supplier(self, supplier_id: int) -> list[dict]:
        """Get all open (unreceived) PO lines for a supplier across all POs."""
        cursor = await self.db.execute(
            """
            SELECT li.*, po.po_number, po.id AS po_id,
                   p.code AS part_number, p.description AS part_description
            FROM po_line_items li
            JOIN purchase_orders po ON po.id = li.po_id
            JOIN parts p ON p.id = li.part_id
            WHERE po.supplier_id = ?
              AND li.status IN ('pending', 'partial', 'backordered')
              AND po.status IN ('submitted', 'acknowledged', 'partially_received')
            ORDER BY po.po_number, li.id
            """,
            (supplier_id,),
        )
        return await cursor.fetchall()

    async def get_open_lines_for_part(self, part_id: int) -> list[dict]:
        """Get all open PO lines for a specific part (item scan receiving)."""
        cursor = await self.db.execute(
            """
            SELECT li.*, po.po_number, po.supplier_id,
                   s.name AS supplier_name
            FROM po_line_items li
            JOIN purchase_orders po ON po.id = li.po_id
            JOIN suppliers s ON s.id = po.supplier_id
            WHERE li.part_id = ?
              AND li.status IN ('pending', 'partial', 'backordered')
              AND po.status IN ('submitted', 'acknowledged', 'partially_received')
            ORDER BY po.order_date
            """,
            (part_id,),
        )
        return await cursor.fetchall()

    async def bulk_insert(self, po_id: int, lines: list[dict]) -> list[int]:
        """Insert multiple PO line items. Returns list of new IDs."""
        ids = []
        for line in lines:
            line["po_id"] = po_id
            new_id = await self.insert(line)
            ids.append(new_id)
        return ids

    async def update_received(
        self, line_id: int, qty: int, actual_cost: float | None = None
    ) -> None:
        """Update received quantity and optionally actual cost."""
        sql = "UPDATE po_line_items SET qty_received = qty_received + ?"
        params: list[Any] = [qty]

        if actual_cost is not None:
            sql += ", received_unit_cost = ?"
            params.append(actual_cost)

        sql += ", received_at = datetime('now') WHERE id = ?"
        params.append(line_id)

        await self.db.execute(sql, tuple(params))

    async def check_po_complete(self, po_id: int) -> bool:
        """Check if all lines in a PO are fully received."""
        cursor = await self.db.execute(
            """
            SELECT COUNT(*) as remaining
            FROM po_line_items
            WHERE po_id = ? AND status NOT IN ('received', 'cancelled')
            """,
            (po_id,),
        )
        row = await cursor.fetchone()
        return row["remaining"] == 0 if row else False


# ═══════════════════════════════════════════════════════════════
# Return Repository
# ═══════════════════════════════════════════════════════════════

class ReturnRepo(BaseRepo):
    TABLE = "returns"
    HAS_UPDATED_AT = True

    async def get_next_return_number(self) -> str:
        """Generate the next return number: 'RET-001'."""
        cursor = await self.db.execute(
            "SELECT COUNT(*) as cnt FROM returns"
        )
        row = await cursor.fetchone()
        seq = (row["cnt"] if row else 0) + 1
        return f"RET-{seq:04d}"

    async def list_with_details(
        self,
        *,
        return_type: str | None = None,
        status: str | None = None,
        supplier_id: int | None = None,
        job_id: int | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """List returns with joined info."""
        sql = """
            SELECT r.*,
                   s.name AS supplier_name,
                   j.job_name,
                   u.display_name AS initiator_name,
                   (SELECT COUNT(*) FROM return_line_items WHERE return_id = r.id) AS line_count
            FROM returns r
            LEFT JOIN suppliers s ON s.id = r.supplier_id
            LEFT JOIN jobs j ON j.id = r.job_id
            JOIN users u ON u.id = r.initiated_by
        """
        conditions: list[str] = []
        params: list[Any] = []

        if return_type:
            conditions.append("r.return_type = ?")
            params.append(return_type)
        if status:
            conditions.append("r.status = ?")
            params.append(status)
        if supplier_id:
            conditions.append("r.supplier_id = ?")
            params.append(supplier_id)
        if job_id:
            conditions.append("r.job_id = ?")
            params.append(job_id)

        if conditions:
            sql += " WHERE " + " AND ".join(conditions)

        sql += " ORDER BY r.updated_at DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])

        cursor = await self.db.execute(sql, tuple(params))
        return await cursor.fetchall()

    async def get_with_details(self, return_id: int) -> dict | None:
        """Get a single return with all joined info."""
        cursor = await self.db.execute(
            """
            SELECT r.*,
                   s.name AS supplier_name,
                   j.job_name,
                   u.display_name AS initiator_name,
                   (SELECT COUNT(*) FROM return_line_items WHERE return_id = r.id) AS line_count
            FROM returns r
            LEFT JOIN suppliers s ON s.id = r.supplier_id
            LEFT JOIN jobs j ON j.id = r.job_id
            JOIN users u ON u.id = r.initiated_by
            WHERE r.id = ?
            """,
            (return_id,),
        )
        return await cursor.fetchone()


class ReturnLineRepo(BaseRepo):
    TABLE = "return_line_items"

    async def get_lines_for_return(self, return_id: int) -> list[dict]:
        """Get all line items for a return with part info."""
        cursor = await self.db.execute(
            """
            SELECT rli.*,
                   p.code AS part_number, p.description AS part_description
            FROM return_line_items rli
            JOIN parts p ON p.id = rli.part_id
            WHERE rli.return_id = ?
            ORDER BY rli.id
            """,
            (return_id,),
        )
        return await cursor.fetchall()

    async def bulk_insert(self, return_id: int, lines: list[dict]) -> list[int]:
        """Insert multiple return line items."""
        ids = []
        for line in lines:
            line["return_id"] = return_id
            new_id = await self.insert(line)
            ids.append(new_id)
        return ids


# ═══════════════════════════════════════════════════════════════
# Order Status History Repository
# ═══════════════════════════════════════════════════════════════

class OrderStatusHistoryRepo(BaseRepo):
    TABLE = "order_status_history"

    async def get_timeline(self, entity_type: str, entity_id: int) -> list[dict]:
        """Get the full status change timeline for an entity."""
        cursor = await self.db.execute(
            """
            SELECT h.*, u.display_name AS changer_name
            FROM order_status_history h
            JOIN users u ON u.id = h.changed_by
            WHERE h.entity_type = ? AND h.entity_id = ?
            ORDER BY h.created_at ASC
            """,
            (entity_type, entity_id),
        )
        return await cursor.fetchall()

    async def log_change(
        self,
        entity_type: str,
        entity_id: int,
        old_status: str | None,
        new_status: str,
        changed_by: int,
        notes: str | None = None,
    ) -> int:
        """Log a status change. Returns the new history entry ID."""
        return await self.insert({
            "entity_type": entity_type,
            "entity_id": entity_id,
            "old_status": old_status,
            "new_status": new_status,
            "changed_by": changed_by,
            "notes": notes,
        })


# ═══════════════════════════════════════════════════════════════
# Price History Repository
# ═══════════════════════════════════════════════════════════════

class PriceHistoryRepo(BaseRepo):
    TABLE = "price_history"

    async def get_for_part_supplier(
        self, part_id: int, supplier_id: int, limit: int = 20
    ) -> list[dict]:
        """Get price history for a specific part-supplier combo."""
        cursor = await self.db.execute(
            """
            SELECT ph.*, s.name AS supplier_name, p.code AS part_number
            FROM price_history ph
            JOIN suppliers s ON s.id = ph.supplier_id
            JOIN parts p ON p.id = ph.part_id
            WHERE ph.part_id = ? AND ph.supplier_id = ?
            ORDER BY ph.effective_date DESC
            LIMIT ?
            """,
            (part_id, supplier_id, limit),
        )
        return await cursor.fetchall()

    async def get_latest_price(self, part_id: int, supplier_id: int) -> float | None:
        """Get the most recent price for a part from a supplier."""
        cursor = await self.db.execute(
            """
            SELECT price FROM price_history
            WHERE part_id = ? AND supplier_id = ?
            ORDER BY effective_date DESC LIMIT 1
            """,
            (part_id, supplier_id),
        )
        row = await cursor.fetchone()
        return row["price"] if row else None

    async def record_price(
        self,
        part_id: int,
        supplier_id: int,
        price: float,
        source: str = "manual",
        reference_id: int | None = None,
        notes: str | None = None,
    ) -> int:
        """Record a new price entry."""
        return await self.insert({
            "part_id": part_id,
            "supplier_id": supplier_id,
            "price": price,
            "source": source,
            "reference_id": reference_id,
            "notes": notes,
        })


# ═══════════════════════════════════════════════════════════════
# Supplier Contact Ratings Repository
# ═══════════════════════════════════════════════════════════════

class SupplierContactRatingRepo(BaseRepo):
    TABLE = "supplier_contact_ratings"

    async def get_for_supplier(
        self, supplier_id: int, limit: int = 50
    ) -> list[dict]:
        """Get all ratings for a supplier."""
        cursor = await self.db.execute(
            """
            SELECT r.*, u.display_name AS rater_name
            FROM supplier_contact_ratings r
            JOIN users u ON u.id = r.rated_by
            WHERE r.supplier_id = ?
            ORDER BY r.interaction_date DESC
            LIMIT ?
            """,
            (supplier_id, limit),
        )
        return await cursor.fetchall()

    async def get_avg_score(self, supplier_id: int) -> float:
        """Calculate rolling average communication score for a supplier."""
        cursor = await self.db.execute(
            """
            SELECT AVG(score) as avg_score
            FROM supplier_contact_ratings
            WHERE supplier_id = ?
              AND interaction_date >= date('now', '-180 days')
            """,
            (supplier_id,),
        )
        row = await cursor.fetchone()
        # Normalize 1-5 scale to 0.0-1.0
        raw = row["avg_score"] if row and row["avg_score"] else 4.25
        return (raw - 1) / 4  # 1→0.0, 5→1.0

    async def update_supplier_communication_score(self, supplier_id: int) -> None:
        """Recalculate and update the supplier's communication_score."""
        score = await self.get_avg_score(supplier_id)
        await self.db.execute(
            "UPDATE suppliers SET communication_score = ? WHERE id = ?",
            (score, supplier_id),
        )
        await self.db.commit()
