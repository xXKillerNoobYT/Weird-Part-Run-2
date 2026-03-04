"""
Receiving service — PO receiving, staging zone assignment, price changes.

Three entry points:
  1. By PO# — see expected items, check off
  2. By Supplier — all open lines, bulk check
  3. By Item scan — search part, pick PO match

Each receive creates stock_movements to staging, updates PO line quantities,
cascades to JPO lines, handles price changes, and assigns staging zones.
"""

from __future__ import annotations

import logging
from typing import Any

import aiosqlite

from app.repositories.orders_repo import (
    OrderStatusHistoryRepo,
    POLineRepo,
    JPOLineRepo,
    PriceHistoryRepo,
    PurchaseOrderRepo,
)
from app.repositories.staging_repo import StagingAssignmentRepo, StagingZoneRepo

logger = logging.getLogger(__name__)


class ReceivingService:
    """Handles all PO receiving workflows."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.po_repo = PurchaseOrderRepo(db)
        self.po_line_repo = POLineRepo(db)
        self.jpo_line_repo = JPOLineRepo(db)
        self.history_repo = OrderStatusHistoryRepo(db)
        self.price_repo = PriceHistoryRepo(db)
        self.zone_repo = StagingZoneRepo(db)
        self.assignment_repo = StagingAssignmentRepo(db)

    async def receive_po_items(
        self,
        po_id: int,
        items: list[dict],
        received_by: int,
    ) -> dict:
        """Receive items for a specific PO.

        Each item: {po_line_id, qty_received, actual_cost?, staging_zone_id?}

        Returns summary of what was received and any actions needed.
        """
        po = await self.po_repo.get_by_id(po_id)
        if not po:
            raise ValueError(f"PO {po_id} not found")

        results = {
            "po_id": po_id,
            "items_received": [],
            "price_changes": [],
            "staging_assignments": [],
        }

        for item in items:
            line_id = item["po_line_id"]
            qty = item["qty_received"]
            actual_cost = item.get("actual_cost")
            zone_id = item.get("staging_zone_id")

            # Get current line state
            line = await self.po_line_repo.get_by_id(line_id)
            if not line:
                continue

            # Update PO line received qty
            await self.po_line_repo.update_received(line_id, qty, actual_cost)

            # Update line status
            new_received = line["qty_received"] + qty
            if new_received >= line["qty_ordered"]:
                line_status = "received"
            else:
                line_status = "partial"

            await self.po_line_repo.update(line_id, {
                "status": line_status,
                "received_by": received_by,
            })

            # Handle price change
            if actual_cost is not None and actual_cost != line.get("unit_cost"):
                await self._handle_price_change(
                    line["part_id"], po["supplier_id"],
                    actual_cost, po_id, line_id
                )
                results["price_changes"].append({
                    "part_id": line["part_id"],
                    "old_price": line.get("unit_cost"),
                    "new_price": actual_cost,
                })

            # Cascade to JPO line (if linked)
            if line.get("jpo_line_id"):
                await self.jpo_line_repo.update_received_qty(
                    line["jpo_line_id"], qty
                )

            # Create stock movement to staging
            zone_id = zone_id or await self._assign_staging_zone(
                line["part_id"], po
            )

            await self._create_receive_movement(
                part_id=line["part_id"],
                qty=qty,
                supplier_id=po["supplier_id"],
                staging_zone_id=zone_id,
                user_id=received_by,
                po_id=po_id,
            )

            results["items_received"].append({
                "po_line_id": line_id,
                "part_id": line["part_id"],
                "qty": qty,
                "status": line_status,
                "staging_zone_id": zone_id,
            })

        # Check if PO is fully received
        all_received = await self.po_line_repo.check_po_complete(po_id)
        if all_received:
            results["po_complete"] = True
            # Suggest status change (don't auto-transition)
            results["suggest_status"] = "received"

        # Update PO status based on receiving progress
        receivable_statuses = ("submitted", "acknowledged", "partially_received")
        if po["status"] in receivable_statuses:
            new_status = "received" if all_received else "partially_received"
            old_status = po["status"]
            if new_status != old_status:
                await self.po_repo.update(po_id, {"status": new_status})
                await self.history_repo.log_change(
                    "po", po_id, old_status, new_status, received_by,
                    f"Received {len(items)} items"
                )

        # Recalculate totals (actual costs may differ)
        await self.po_repo.recalculate_totals(po_id)

        # Update supplier reliability metrics
        await self._update_supplier_metrics(po["supplier_id"], po)

        await self.db.commit()
        return results

    async def get_open_lines_by_supplier(self, supplier_id: int) -> list[dict]:
        """Get all open PO lines for a supplier (for bulk receive)."""
        return await self.po_line_repo.get_open_lines_for_supplier(supplier_id)

    async def get_open_lines_by_part(self, part_id: int) -> list[dict]:
        """Get all open PO lines for a specific part (item scan)."""
        return await self.po_line_repo.get_open_lines_for_part(part_id)

    async def mark_backorder(
        self,
        po_line_id: int,
        expected_date: str | None,
        user_id: int,
        notes: str | None = None,
    ) -> None:
        """Mark remaining quantity on a PO line as backordered."""
        await self.po_line_repo.update(po_line_id, {
            "status": "backordered",
            "backorder_expected_date": expected_date,
            "notes": notes,
        })
        await self.db.commit()

    # ── Staging Zone Assignment ───────────────────────────────

    async def _assign_staging_zone(self, part_id: int, po: dict) -> int | None:
        """Auto-assign a staging zone based on PO context.

        Logic:
          - If PO has JPO lines → find job → assign job zone
          - If restock PO → assign general zone
          - If no zone available → create overflow
        """
        # Check if any PO line is linked to a JPO (→ job context)
        cursor = await self.db.execute(
            """
            SELECT DISTINCT jpo.job_id
            FROM po_line_items pli
            JOIN jpo_line_items jli ON jli.id = pli.jpo_line_id
            JOIN job_parts_orders jpo ON jpo.id = jli.jpo_id
            WHERE pli.po_id = ? AND pli.jpo_line_id IS NOT NULL
            LIMIT 1
            """,
            (po["id"],),
        )
        job_row = await cursor.fetchone()

        if job_row:
            job_id = job_row["job_id"]
            # Find existing zone for this job
            zones = await self.zone_repo.get_zones_for_job(job_id)
            if zones:
                return zones[0]["id"]

            # Assign new zone for this job
            available = await self.zone_repo.get_available_zone("general")
            if available:
                await self.zone_repo.assign_to_job(available["id"], job_id)
                await self.assignment_repo.create_assignment(available["id"], job_id)
                return available["id"]

        # Fallback: use any general zone
        general = await self.zone_repo.get_available_zone("general")
        return general["id"] if general else None

    # ── Price Change Handling ─────────────────────────────────

    async def _handle_price_change(
        self,
        part_id: int,
        supplier_id: int,
        new_price: float,
        po_id: int,
        line_id: int,
    ) -> None:
        """Record a price change from receiving and update supplier links."""
        # Record in price history
        await self.price_repo.record_price(
            part_id, supplier_id, new_price,
            source="po_receive",
            reference_id=po_id,
            notes=f"Updated during receive (PO line #{line_id})"
        )

        # Update part_supplier_links with new price
        await self.db.execute(
            """
            UPDATE part_supplier_links
            SET supplier_cost_price = ?
            WHERE part_id = ? AND supplier_id = ?
            """,
            (new_price, part_id, supplier_id),
        )

    # ── Stock Movement Creation ───────────────────────────────

    async def _create_receive_movement(
        self,
        part_id: int,
        qty: int,
        supplier_id: int,
        staging_zone_id: int | None,
        user_id: int,
        po_id: int,
    ) -> None:
        """Create a stock_movement for receiving into warehouse.

        from_location_type is NULL (new stock from external supplier).
        to_location_type is 'warehouse' (stock enters warehouse inventory).
        """
        await self.db.execute(
            """
            INSERT INTO stock_movements (
                part_id, qty, movement_type,
                from_location_type, from_location_id,
                to_location_type, to_location_id,
                supplier_id, performed_by, notes
            ) VALUES (?, ?, 'receive', NULL, NULL, 'warehouse', ?, ?, ?, ?)
            """,
            (
                part_id, qty,
                staging_zone_id,  # to_location_id (warehouse zone)
                supplier_id,
                user_id,
                f"Received from PO #{po_id}",
            ),
        )

    # ── Supplier Metrics ──────────────────────────────────────

    async def _update_supplier_metrics(
        self, supplier_id: int, po: dict
    ) -> None:
        """Update supplier reliability metrics after receiving."""
        # Check if delivery was on time
        if po.get("expected_delivery") and po.get("actual_delivery"):
            # Simple on-time check — could be more sophisticated
            pass

        # Update avg_lead_days based on order_date → now
        if po.get("order_date"):
            await self.db.execute(
                """
                UPDATE suppliers
                SET avg_lead_days = (
                    SELECT AVG(julianday(COALESCE(actual_delivery, date('now'))) - julianday(order_date))
                    FROM purchase_orders
                    WHERE supplier_id = ? AND status IN ('received', 'partially_received')
                      AND order_date IS NOT NULL
                )
                WHERE id = ?
                """,
                (supplier_id, supplier_id),
            )
