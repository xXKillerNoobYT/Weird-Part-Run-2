"""
Orders service — JPO + PO lifecycle, status transitions, audit trail.

Handles:
  - JPO creation (with auto-numbering), approval/rejection
  - PO creation from JPOs and standalone
  - Status transitions with full audit trail
  - Supplier suggestion tagging
  - PO total recalculation
"""

from __future__ import annotations

import logging
from typing import Any

import aiosqlite

from app.repositories.orders_repo import (
    JPOLineRepo,
    JPORepo,
    OrderStatusHistoryRepo,
    POLineRepo,
    PurchaseOrderRepo,
)

logger = logging.getLogger(__name__)


class OrdersService:
    """Orchestrates JPO and PO lifecycle operations."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.jpo_repo = JPORepo(db)
        self.jpo_line_repo = JPOLineRepo(db)
        self.po_repo = PurchaseOrderRepo(db)
        self.po_line_repo = POLineRepo(db)
        self.history_repo = OrderStatusHistoryRepo(db)

    # ── JPO Lifecycle ─────────────────────────────────────────

    async def create_jpo(
        self,
        job_id: int,
        requested_by: int,
        lines: list[dict],
        *,
        priority: str = "normal",
        notes: str | None = None,
    ) -> dict:
        """Create a new Job Parts Order with line items.

        Auto-generates order_number from job name.
        Starts in 'draft' status.
        """
        order_number = await self.jpo_repo.get_next_order_number(job_id)

        jpo_id = await self.jpo_repo.insert({
            "job_id": job_id,
            "order_number": order_number,
            "status": "draft",
            "priority": priority,
            "requested_by": requested_by,
            "notes": notes,
        })

        # Insert line items
        if lines:
            await self.jpo_line_repo.bulk_insert(jpo_id, lines)

        # Log initial status
        await self.history_repo.log_change(
            "jpo", jpo_id, None, "draft", requested_by, "JPO created"
        )

        await self.db.commit()
        return await self.jpo_repo.get_with_details(jpo_id)

    async def submit_jpo(self, jpo_id: int, user_id: int) -> dict | None:
        """Submit a JPO for approval (draft → pending_approval)."""
        jpo = await self.jpo_repo.get_by_id(jpo_id)
        if not jpo or jpo["status"] != "draft":
            return None

        await self.jpo_repo.update(jpo_id, {"status": "pending_approval"})
        await self.history_repo.log_change(
            "jpo", jpo_id, "draft", "pending_approval", user_id, "Submitted for approval"
        )
        await self.db.commit()

        return await self.jpo_repo.get_with_details(jpo_id)

    async def approve_jpo(
        self, jpo_id: int, approved_by: int, notes: str | None = None
    ) -> dict | None:
        """Approve a JPO (pending_approval → approved)."""
        jpo = await self.jpo_repo.get_by_id(jpo_id)
        if not jpo or jpo["status"] != "pending_approval":
            return None

        await self.jpo_repo.update(jpo_id, {
            "status": "approved",
            "approved_by": approved_by,
            "approved_at": "datetime('now')",
        })
        # Fix: approved_at needs SQL expression
        await self.db.execute(
            "UPDATE job_parts_orders SET approved_at = datetime('now') WHERE id = ?",
            (jpo_id,),
        )
        await self.history_repo.log_change(
            "jpo", jpo_id, "pending_approval", "approved", approved_by, notes
        )
        await self.db.commit()

        return await self.jpo_repo.get_with_details(jpo_id)

    async def reject_jpo(
        self, jpo_id: int, rejected_by: int, notes: str | None = None
    ) -> dict | None:
        """Reject a JPO — sends back to draft with feedback."""
        jpo = await self.jpo_repo.get_by_id(jpo_id)
        if not jpo or jpo["status"] != "pending_approval":
            return None

        await self.jpo_repo.update(jpo_id, {"status": "draft"})
        await self.history_repo.log_change(
            "jpo", jpo_id, "pending_approval", "draft", rejected_by,
            f"Rejected: {notes}" if notes else "Rejected"
        )
        await self.db.commit()

        return await self.jpo_repo.get_with_details(jpo_id)

    async def update_jpo_status(
        self, jpo_id: int, new_status: str, user_id: int, notes: str | None = None
    ) -> bool:
        """Generic status update with audit trail."""
        jpo = await self.jpo_repo.get_by_id(jpo_id)
        if not jpo:
            return False

        old_status = jpo["status"]
        await self.jpo_repo.update(jpo_id, {"status": new_status})
        await self.history_repo.log_change(
            "jpo", jpo_id, old_status, new_status, user_id, notes
        )
        await self.db.commit()
        return True

    # ── PO Lifecycle ──────────────────────────────────────────

    async def create_po_standalone(
        self,
        supplier_id: int,
        lines: list[dict],
        *,
        created_by: int,
        expected_delivery: str | None = None,
        shipping_method: str | None = None,
        notes: str | None = None,
        internal_notes: str | None = None,
    ) -> dict:
        """Create a standalone PO (no JPO — warehouse restock, etc.)."""
        po_number = await self.po_repo.get_next_po_number(supplier_id)

        po_id = await self.po_repo.insert({
            "po_number": po_number,
            "supplier_id": supplier_id,
            "status": "draft",
            "expected_delivery": expected_delivery,
            "shipping_method": shipping_method,
            "notes": notes,
            "internal_notes": internal_notes,
        })

        if lines:
            await self.po_line_repo.bulk_insert(po_id, lines)

        await self.po_repo.recalculate_totals(po_id)

        await self.history_repo.log_change(
            "po", po_id, None, "draft", created_by, "PO created (standalone)"
        )
        await self.db.commit()

        return await self.po_repo.get_with_details(po_id)

    async def create_po_from_jpo(
        self,
        jpo_id: int,
        supplier_id: int,
        line_ids: list[int],
        *,
        created_by: int,
        expected_delivery: str | None = None,
        notes: str | None = None,
    ) -> dict:
        """Create a PO from selected JPO lines for a specific supplier."""
        po_number = await self.po_repo.get_next_po_number(supplier_id)

        po_id = await self.po_repo.insert({
            "po_number": po_number,
            "supplier_id": supplier_id,
            "status": "draft",
            "expected_delivery": expected_delivery,
            "notes": notes,
        })

        # Copy JPO lines to PO lines
        for jpo_line_id in line_ids:
            cursor = await self.db.execute(
                "SELECT * FROM jpo_line_items WHERE id = ?", (jpo_line_id,)
            )
            jpo_line = await cursor.fetchone()
            if not jpo_line:
                continue

            # Try to get supplier price
            cursor = await self.db.execute(
                """
                SELECT supplier_cost_price FROM part_supplier_links
                WHERE part_id = ? AND supplier_id = ?
                """,
                (jpo_line["part_id"], supplier_id),
            )
            price_row = await cursor.fetchone()
            unit_cost = price_row["supplier_cost_price"] if price_row else None

            qty = jpo_line["qty_requested"] - jpo_line["qty_ordered"]
            if qty <= 0:
                continue

            await self.po_line_repo.insert({
                "po_id": po_id,
                "jpo_line_id": jpo_line_id,
                "part_id": jpo_line["part_id"],
                "qty_ordered": qty,
                "unit_cost": unit_cost,
            })

            # Update JPO line ordered qty
            await self.jpo_line_repo.update_ordered_qty(jpo_line_id, qty)

        await self.po_repo.recalculate_totals(po_id)

        # Update JPO status if all lines are now ordered
        await self._check_jpo_ordering_status(jpo_id, created_by)

        await self.history_repo.log_change(
            "po", po_id, None, "draft", created_by,
            f"Created from JPO #{jpo_id}"
        )
        await self.db.commit()

        return await self.po_repo.get_with_details(po_id)

    async def auto_generate_pos(self, jpo_id: int, created_by: int) -> list[dict]:
        """Auto-split approved JPO lines by preferred supplier into draft POs."""
        unordered = await self.jpo_line_repo.get_unordered_lines(jpo_id)
        if not unordered:
            return []

        # Group lines by suggested/preferred supplier
        supplier_groups: dict[int, list[dict]] = {}
        for line in unordered:
            supplier_id = line.get("suggested_supplier_id")
            if not supplier_id:
                # Try to find preferred supplier from part_supplier_links
                cursor = await self.db.execute(
                    """
                    SELECT supplier_id FROM part_supplier_links
                    WHERE part_id = ? AND is_preferred = 1
                    LIMIT 1
                    """,
                    (line["part_id"],),
                )
                pref = await cursor.fetchone()
                supplier_id = pref["supplier_id"] if pref else None

            if supplier_id:
                supplier_groups.setdefault(supplier_id, []).append(line)

        # Create a PO for each supplier group
        created_pos = []
        for sid, group_lines in supplier_groups.items():
            line_ids = [l["id"] for l in group_lines]
            po = await self.create_po_from_jpo(
                jpo_id, sid, line_ids, created_by=created_by
            )
            created_pos.append(po)

        return created_pos

    async def submit_po(self, po_id: int, submitted_by: int) -> dict | None:
        """Submit a PO (draft → submitted)."""
        po = await self.po_repo.get_by_id(po_id)
        if not po or po["status"] != "draft":
            return None

        await self.po_repo.update(po_id, {
            "status": "submitted",
            "submitted_by": submitted_by,
        })
        # Set order_date via SQL expression
        await self.db.execute(
            "UPDATE purchase_orders SET order_date = date('now') WHERE id = ?",
            (po_id,),
        )
        await self.history_repo.log_change(
            "po", po_id, "draft", "submitted", submitted_by, "PO submitted to supplier"
        )
        await self.db.commit()

        return await self.po_repo.get_with_details(po_id)

    async def update_po_status(
        self, po_id: int, new_status: str, user_id: int, notes: str | None = None
    ) -> bool:
        """Generic PO status update with audit trail."""
        po = await self.po_repo.get_by_id(po_id)
        if not po:
            return False

        old_status = po["status"]
        await self.po_repo.update(po_id, {"status": new_status})
        await self.history_repo.log_change(
            "po", po_id, old_status, new_status, user_id, notes
        )
        await self.db.commit()
        return True

    # ── Supplier Suggestions ──────────────────────────────────

    async def get_supplier_suggestions(self, part_id: int) -> list[dict]:
        """Get supplier suggestions for a part with preference indicators."""
        cursor = await self.db.execute(
            """
            SELECT psl.supplier_id, s.name AS supplier_name,
                   psl.is_preferred, psl.supplier_cost_price,
                   psl.supplier_sku, s.reliability_score,
                   s.communication_score, s.avg_lead_days
            FROM part_supplier_links psl
            JOIN suppliers s ON s.id = psl.supplier_id
            WHERE psl.part_id = ? AND s.is_active = 1
            ORDER BY psl.is_preferred DESC, s.reliability_score DESC
            """,
            (part_id,),
        )
        return await cursor.fetchall()

    # ── Internal Helpers ──────────────────────────────────────

    async def _check_jpo_ordering_status(self, jpo_id: int, user_id: int) -> None:
        """Check if JPO lines are fully/partially ordered and update status."""
        cursor = await self.db.execute(
            """
            SELECT
                COUNT(*) as total,
                SUM(CASE WHEN qty_ordered >= qty_requested THEN 1 ELSE 0 END) as fully_ordered,
                SUM(CASE WHEN qty_ordered > 0 THEN 1 ELSE 0 END) as any_ordered
            FROM jpo_line_items WHERE jpo_id = ?
            """,
            (jpo_id,),
        )
        row = await cursor.fetchone()
        if not row or row["total"] == 0:
            return

        jpo = await self.jpo_repo.get_by_id(jpo_id)
        if not jpo or jpo["status"] not in ("approved", "ordering", "partially_ordered"):
            return

        if row["fully_ordered"] == row["total"]:
            new_status = "ordered"
        elif row["any_ordered"] > 0:
            new_status = "partially_ordered"
        else:
            new_status = "ordering" if jpo["status"] == "approved" else jpo["status"]

        if new_status != jpo["status"]:
            await self.jpo_repo.update(jpo_id, {"status": new_status})
            await self.history_repo.log_change(
                "jpo", jpo_id, jpo["status"], new_status, user_id,
                "Auto-updated based on PO creation"
            )
