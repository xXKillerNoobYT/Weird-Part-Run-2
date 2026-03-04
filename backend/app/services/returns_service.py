"""
Returns service — truck return flow, supplier returns, RMA lifecycle.

Two return types:
  1. job_to_warehouse — field worker returns unused parts via truck
  2. warehouse_to_supplier — RMA/defective/wrong item returns

Truck return flow:
  Job → Truck (job→truck movement, optional notebook entry)
  Truck → Staging (truck→staging movement at warehouse)
  Staging → Shelf (restock) or → Supplier Return (RMA)
"""

from __future__ import annotations

import logging
from typing import Any

import aiosqlite

from app.repositories.orders_repo import (
    OrderStatusHistoryRepo,
    ReturnLineRepo,
    ReturnRepo,
)

logger = logging.getLogger(__name__)


class ReturnsService:
    """Orchestrates return lifecycle operations."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.return_repo = ReturnRepo(db)
        self.return_line_repo = ReturnLineRepo(db)
        self.history_repo = OrderStatusHistoryRepo(db)

    async def create_truck_return(
        self,
        job_id: int,
        initiated_by: int,
        lines: list[dict],
        *,
        reason: str = "unused",
        notes: str | None = None,
        create_notebook_entry: bool = False,
    ) -> dict:
        """Create a job-to-warehouse return (field worker returning parts).

        Creates stock movements: job → truck for each line.
        Optionally creates a notebook entry for the job.
        """
        return_number = await self.return_repo.get_next_return_number()

        return_id = await self.return_repo.insert({
            "return_number": return_number,
            "return_type": "job_to_warehouse",
            "job_id": job_id,
            "status": "draft",
            "reason": reason,
            "notes": notes,
            "initiated_by": initiated_by,
        })

        # Insert line items
        if lines:
            await self.return_line_repo.bulk_insert(return_id, lines)

        # Create stock movements: job → truck
        for line in lines:
            await self._create_return_movement(
                part_id=line["part_id"],
                qty=line["qty"],
                from_type="job",
                from_id=job_id,
                to_type="truck",
                to_id=None,  # truck determined by user context
                user_id=initiated_by,
                return_id=return_id,
                condition=line.get("condition", "new"),
            )

        # Log status
        await self.history_repo.log_change(
            "return", return_id, None, "draft", initiated_by, "Return created"
        )

        # Optional notebook entry
        if create_notebook_entry:
            await self._create_notebook_entry(job_id, return_id, initiated_by, lines)

        await self.db.commit()
        return await self.return_repo.get_with_details(return_id)

    async def create_supplier_return(
        self,
        supplier_id: int,
        initiated_by: int,
        lines: list[dict],
        *,
        po_id: int | None = None,
        reason: str = "defective",
        notes: str | None = None,
    ) -> dict:
        """Create a warehouse-to-supplier return (RMA)."""
        return_number = await self.return_repo.get_next_return_number()

        return_id = await self.return_repo.insert({
            "return_number": return_number,
            "return_type": "warehouse_to_supplier",
            "supplier_id": supplier_id,
            "po_id": po_id,
            "status": "draft",
            "reason": reason,
            "notes": notes,
            "initiated_by": initiated_by,
        })

        if lines:
            await self.return_line_repo.bulk_insert(return_id, lines)

        await self.history_repo.log_change(
            "return", return_id, None, "draft", initiated_by, "Supplier return created"
        )
        await self.db.commit()

        return await self.return_repo.get_with_details(return_id)

    async def submit_return(
        self, return_id: int, user_id: int
    ) -> dict | None:
        """Submit a return for approval (draft → pending_approval)."""
        ret = await self.return_repo.get_by_id(return_id)
        if not ret or ret["status"] != "draft":
            return None

        await self.return_repo.update(return_id, {"status": "pending_approval"})
        await self.history_repo.log_change(
            "return", return_id, "draft", "pending_approval",
            user_id, "Submitted for approval"
        )
        await self.db.commit()

        return await self.return_repo.get_with_details(return_id)

    async def approve_return(
        self, return_id: int, approved_by: int, notes: str | None = None
    ) -> dict | None:
        """Approve a return (pending_approval → approved)."""
        ret = await self.return_repo.get_by_id(return_id)
        if not ret or ret["status"] != "pending_approval":
            return None

        await self.return_repo.update(return_id, {
            "status": "approved",
            "approved_by": approved_by,
        })
        await self.db.execute(
            "UPDATE returns SET approved_at = datetime('now') WHERE id = ?",
            (return_id,),
        )
        await self.history_repo.log_change(
            "return", return_id, "pending_approval", "approved",
            approved_by, notes
        )
        await self.db.commit()

        return await self.return_repo.get_with_details(return_id)

    async def update_return_status(
        self,
        return_id: int,
        new_status: str,
        user_id: int,
        *,
        rma_number: str | None = None,
        tracking_number: str | None = None,
        shipping_carrier: str | None = None,
        credit_amount: float | None = None,
        notes: str | None = None,
    ) -> bool:
        """Update return status and optional fields."""
        ret = await self.return_repo.get_by_id(return_id)
        if not ret:
            return False

        update_data: dict[str, Any] = {"status": new_status}
        if rma_number is not None:
            update_data["rma_number"] = rma_number
        if tracking_number is not None:
            update_data["tracking_number"] = tracking_number
        if shipping_carrier is not None:
            update_data["shipping_carrier"] = shipping_carrier
        if credit_amount is not None:
            update_data["credit_amount"] = credit_amount
        if notes is not None:
            update_data["notes"] = notes

        await self.return_repo.update(return_id, update_data)
        await self.history_repo.log_change(
            "return", return_id, ret["status"], new_status, user_id, notes
        )
        await self.db.commit()
        return True

    async def process_staging_sort(
        self,
        return_id: int,
        dispositions: list[dict],
        user_id: int,
    ) -> dict:
        """Sort return items from staging to final destinations.

        Each disposition: {return_line_id, disposition, dest_type, dest_id}
        disposition: 'restock' → warehouse shelf, 'return_to_supplier' → RMA
        """
        results = {"restocked": [], "supplier_returns": [], "write_offs": []}

        for item in dispositions:
            line = await self.return_line_repo.get_by_id(item["return_line_id"])
            if not line:
                continue

            if item["disposition"] == "restock":
                # Move to warehouse shelf
                await self._create_return_movement(
                    part_id=line["part_id"],
                    qty=line["qty"],
                    from_type=None,
                    from_id=None,
                    to_type="warehouse",
                    to_id=item.get("dest_id"),
                    user_id=user_id,
                    return_id=return_id,
                    condition=line.get("condition", "new"),
                )
                results["restocked"].append(line["part_id"])

            elif item["disposition"] == "return_to_supplier":
                results["supplier_returns"].append(line["part_id"])

            elif item["disposition"] == "write_off":
                results["write_offs"].append(line["part_id"])

        await self.db.commit()
        return results

    async def get_po_match_suggestions(
        self, part_id: int, supplier_id: int | None = None
    ) -> list[dict]:
        """Suggest PO matches for a return item."""
        sql = """
            SELECT pli.id AS po_line_id, po.po_number, po.id AS po_id,
                   s.name AS supplier_name, pli.unit_cost,
                   pli.qty_ordered, pli.qty_received
            FROM po_line_items pli
            JOIN purchase_orders po ON po.id = pli.po_id
            JOIN suppliers s ON s.id = po.supplier_id
            WHERE pli.part_id = ? AND pli.status = 'received'
        """
        params: list[Any] = [part_id]

        if supplier_id:
            sql += " AND po.supplier_id = ?"
            params.append(supplier_id)

        sql += " ORDER BY po.order_date DESC LIMIT 10"

        cursor = await self.db.execute(sql, tuple(params))
        return await cursor.fetchall()

    # ── Internal Helpers ──────────────────────────────────────

    async def _create_return_movement(
        self,
        part_id: int,
        qty: int,
        from_type: str,
        from_id: int | None,
        to_type: str,
        to_id: int | None,
        user_id: int,
        return_id: int,
        condition: str = "new",
    ) -> None:
        """Create a stock_movement for a return flow."""
        await self.db.execute(
            """
            INSERT INTO stock_movements (
                part_id, qty, movement_type,
                from_location_type, from_location_id,
                to_location_type, to_location_id,
                performed_by, notes
            ) VALUES (?, ?, 'return', ?, ?, ?, ?, ?, ?)
            """,
            (
                part_id, qty,
                from_type, from_id,
                to_type, to_id,
                user_id,
                f"Return #{return_id} ({condition})",
            ),
        )

    async def _create_notebook_entry(
        self,
        job_id: int,
        return_id: int,
        user_id: int,
        lines: list[dict],
    ) -> None:
        """Create a notebook entry for a truck return (optional logging)."""
        # Find the job's notebook
        cursor = await self.db.execute(
            "SELECT id FROM notebooks WHERE job_id = ? LIMIT 1",
            (job_id,),
        )
        notebook = await cursor.fetchone()
        if not notebook:
            return

        # Find the first section
        cursor = await self.db.execute(
            "SELECT id FROM notebook_sections WHERE notebook_id = ? ORDER BY sort_order LIMIT 1",
            (notebook["id"],),
        )
        section = await cursor.fetchone()
        if not section:
            return

        # Build note content
        parts_summary = ", ".join(
            f"{l.get('qty', 1)}x Part#{l['part_id']} ({l.get('condition', 'new')})"
            for l in lines
        )
        content = f"Parts returned: {parts_summary}"

        await self.db.execute(
            """
            INSERT INTO notebook_entries (
                section_id, title, content, entry_type,
                created_by, sort_order
            ) VALUES (?, ?, ?, 'note', ?, 999)
            """,
            (section["id"], f"Return #{return_id}", content, user_id),
        )
