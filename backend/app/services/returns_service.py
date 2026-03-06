"""
Returns service — truck return flow, supplier returns, RMA lifecycle.

Two return types:
  1. job_to_warehouse — field worker returns unused parts via truck
  2. warehouse_to_supplier — RMA/defective/wrong item returns

Truck return flow:
  Job → Truck (job→truck movement, optional notebook entry)
  Truck → Staging (truck→staging movement at warehouse)
  Staging → Shelf (restock) or → Supplier Return (RMA)

Phase 7C additions:
  - get_sorting_guidance(return_id) — per-line recommendations
  - check_return_eligibility(part_id, condition) — supplier return check
  - check_below_target(part_id) — restock target comparison
  - process_sorted_return(return_id, dispositions) — apply sorting decisions
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
from app.services.cost_tracking_service import CostTrackingService

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

    # ═══════════════════════════════════════════════════════════════
    # Return Sorting Guidance (Phase 7C)
    # ═══════════════════════════════════════════════════════════════

    async def get_sorting_guidance(self, return_id: int) -> list[dict]:
        """Generate per-line sorting guidance for a return.

        For each line item, analyzes:
          - Item condition (new, used, damaged, defective)
          - Whether the supplier accepts returns for this condition
          - Current stock vs restock target
          - Time since last receipt (return window)

        Returns a list of guidance objects, one per line.
        """
        # Fetch return lines with part details
        cursor = await self.db.execute(
            """
            SELECT rli.id AS return_line_id,
                   rli.part_id, rli.qty, rli.condition,
                   rli.disposition AS current_disposition,
                   rli.returnable_to_supplier,
                   rli.non_return_reason,
                   rli.below_target_flag,
                   p.part_number, p.description AS part_description,
                   p.reorder_point, p.target_qty
            FROM return_line_items rli
            JOIN parts p ON p.id = rli.part_id
            WHERE rli.return_id = ?
            ORDER BY rli.id
            """,
            (return_id,),
        )
        lines = await cursor.fetchall()

        guidance_list = []
        for line in lines:
            part_id = line["part_id"]

            # Get current warehouse stock
            current_stock = await self._get_current_stock(part_id)

            # Get target qty (defaults)
            target_qty = line["target_qty"] or 0
            reorder_point = line["reorder_point"] or 0
            below_target = current_stock < target_qty

            # Check supplier returnability
            eligibility = await self.check_return_eligibility(
                part_id, line["condition"]
            )

            # Determine recommendation
            recommendation, reason = self._compute_recommendation(
                condition=line["condition"],
                returnable=eligibility["returnable"],
                eligibility_reasons=eligibility["reasons"],
                below_target=below_target,
                current_stock=current_stock,
                target_qty=target_qty,
            )

            # Update the return line item with computed flags
            await self.db.execute(
                """
                UPDATE return_line_items
                SET returnable_to_supplier = ?,
                    below_target_flag = ?,
                    non_return_reason = ?
                WHERE id = ?
                """,
                (
                    1 if eligibility["returnable"] else 0,
                    1 if below_target else 0,
                    eligibility["reasons"][0] if eligibility["reasons"] else None,
                    line["return_line_id"],
                ),
            )

            guidance_list.append({
                "return_line_id": line["return_line_id"],
                "part_id": part_id,
                "part_number": line["part_number"],
                "part_description": line["part_description"],
                "qty": line["qty"],
                "condition": line["condition"],
                "current_stock": current_stock,
                "target_qty": target_qty,
                "below_target": below_target,
                "returnable_to_supplier": eligibility["returnable"],
                "non_return_reason": (
                    eligibility["reasons"][0] if eligibility["reasons"] else None
                ),
                "recommended_disposition": recommendation,
                "recommendation_reason": reason,
            })

        await self.db.commit()
        return guidance_list

    async def check_return_eligibility(
        self, part_id: int, condition: str
    ) -> dict:
        """Determine if a part can be returned to its supplier.

        Factors:
          - Condition: 'new' or 'unused' are returnable; 'used', 'damaged',
            'defective' may not be (depends on supplier policy)
          - Time since receipt: most suppliers have a 30-90 day window
          - Custom modifications: not returnable
        """
        reasons: list[str] = []

        # Condition-based check
        non_returnable_conditions = ("used", "damaged")
        if condition in non_returnable_conditions:
            reasons.append(f"Item is in '{condition}' condition")

        # Check most recent receipt date for this part
        cursor = await self.db.execute(
            """
            SELECT MAX(sm.created_at) AS last_received
            FROM stock_movements sm
            WHERE sm.part_id = ? AND sm.movement_type = 'receive'
            """,
            (part_id,),
        )
        row = await cursor.fetchone()
        last_received = row["last_received"] if row else None

        days_since_receipt = None
        if last_received:
            cursor2 = await self.db.execute(
                "SELECT julianday('now') - julianday(?) AS days",
                (last_received,),
            )
            days_row = await cursor2.fetchone()
            if days_row and days_row["days"] is not None:
                days_since_receipt = int(days_row["days"])

                # Default return window: 90 days
                if days_since_receipt > 90:
                    reasons.append(
                        f"Received {days_since_receipt} days ago (exceeds 90-day return window)"
                    )

        returnable = len(reasons) == 0

        return {
            "part_id": part_id,
            "returnable": returnable,
            "reasons": reasons,
            "supplier_return_window_days": 90,  # configurable in future
            "days_since_receipt": days_since_receipt,
        }

    async def check_below_target(self, part_id: int) -> dict:
        """Check if a part is below its restock target quantity."""
        cursor = await self.db.execute(
            "SELECT target_qty, reorder_point FROM parts WHERE id = ?",
            (part_id,),
        )
        part = await cursor.fetchone()
        if not part:
            return {"part_id": part_id, "below_target": False, "current_stock": 0, "target_qty": 0}

        current_stock = await self._get_current_stock(part_id)
        target = part["target_qty"] or 0

        return {
            "part_id": part_id,
            "below_target": current_stock < target,
            "current_stock": current_stock,
            "target_qty": target,
            "reorder_point": part["reorder_point"] or 0,
            "deficit": max(0, target - current_stock),
        }

    async def process_sorted_return(
        self,
        return_id: int,
        dispositions: list[dict],
        user_id: int,
    ) -> dict:
        """Apply sorting dispositions to all lines in a return.

        Each disposition: {return_line_id, disposition, dest_type?, dest_id?, notes?}

        disposition values:
          - 'restock':              move to warehouse shelf
          - 'return_to_supplier':   queue for supplier RMA
          - 'write_off':            record as loss
        """
        results = {"restocked": [], "supplier_returns": [], "write_offs": []}

        for item in dispositions:
            line = await self.return_line_repo.get_by_id(item["return_line_id"])
            if not line:
                continue

            # Update the line's disposition
            update_data: dict[str, Any] = {
                "disposition": item["disposition"],
            }
            if item.get("notes"):
                update_data["notes"] = item["notes"]

            await self.return_line_repo.update(item["return_line_id"], update_data)

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

                # ── Phase 7D: Restore cost layers via LIFO ──
                try:
                    cost_svc = CostTrackingService(self.db)
                    await cost_svc.return_lifo(line["part_id"], line["qty"])
                except Exception as e:
                    logger.warning(
                        "LIFO return failed for part %d: %s", line["part_id"], e
                    )

                results["restocked"].append({
                    "part_id": line["part_id"],
                    "qty": line["qty"],
                    "return_line_id": item["return_line_id"],
                })

            elif item["disposition"] == "return_to_supplier":
                results["supplier_returns"].append({
                    "part_id": line["part_id"],
                    "qty": line["qty"],
                    "return_line_id": item["return_line_id"],
                })

            elif item["disposition"] == "write_off":
                # Create a write-off movement (from warehouse → void)
                await self._create_return_movement(
                    part_id=line["part_id"],
                    qty=line["qty"],
                    from_type="warehouse",
                    from_id=None,
                    to_type=None,
                    to_id=None,
                    user_id=user_id,
                    return_id=return_id,
                    condition=line.get("condition", "damaged"),
                )
                results["write_offs"].append({
                    "part_id": line["part_id"],
                    "qty": line["qty"],
                    "return_line_id": item["return_line_id"],
                })

        # Update return status to reflect sorting is done
        ret = await self.return_repo.get_by_id(return_id)
        if ret and ret["status"] == "approved":
            has_supplier_returns = len(results["supplier_returns"]) > 0
            new_status = "shipped" if has_supplier_returns else "closed"
            await self.return_repo.update(return_id, {"status": new_status})
            await self.history_repo.log_change(
                "return", return_id, "approved", new_status,
                user_id,
                f"Sorted: {len(results['restocked'])} restocked, "
                f"{len(results['supplier_returns'])} to supplier, "
                f"{len(results['write_offs'])} written off"
            )

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

    # ═══════════════════════════════════════════════════════════════
    # Internal Helpers
    # ═══════════════════════════════════════════════════════════════

    def _compute_recommendation(
        self,
        condition: str,
        returnable: bool,
        eligibility_reasons: list[str],
        below_target: bool,
        current_stock: int,
        target_qty: int,
    ) -> tuple[str, str]:
        """Compute a sorting recommendation for a single return line.

        Returns (disposition, human-readable reason).
        """
        # Write-off damaged/defective items that can't be returned
        if condition in ("damaged", "defective") and not returnable:
            return (
                "write_off",
                f"Item is {condition} and cannot be returned to supplier",
            )

        # Defective items that CAN be returned → return to supplier
        if condition == "defective" and returnable:
            return (
                "return_to_supplier",
                "Defective item — return to supplier for credit/replacement",
            )

        # New/unused items that are returnable → return to supplier
        if condition in ("new",) and returnable and not below_target:
            return (
                "return_to_supplier",
                "Item in new condition, eligible for supplier return",
            )

        # Below target → prefer restocking
        if below_target:
            deficit = target_qty - current_stock
            return (
                "restock",
                f"Below target by {deficit} units (stock: {current_stock}, "
                f"target: {target_qty}) — recommend restocking",
            )

        # Used items → restock (can't return)
        if condition == "used":
            return (
                "restock",
                "Used condition — restock in warehouse (not returnable to supplier)",
            )

        # Default: return to supplier if eligible, otherwise restock
        if returnable:
            return (
                "return_to_supplier",
                "Eligible for supplier return",
            )

        reason_str = "; ".join(eligibility_reasons) if eligibility_reasons else "Not eligible"
        return ("restock", f"Cannot return to supplier: {reason_str}")

    async def _get_current_stock(self, part_id: int) -> int:
        """Get the current warehouse stock for a part."""
        cursor = await self.db.execute(
            """
            SELECT COALESCE(
                (SELECT SUM(CASE
                    WHEN to_location_type = 'warehouse' THEN qty
                    WHEN from_location_type = 'warehouse' THEN -qty
                    ELSE 0
                END)
                FROM stock_movements
                WHERE part_id = ?), 0
            ) AS stock
            """,
            (part_id,),
        )
        row = await cursor.fetchone()
        return max(0, row["stock"]) if row else 0

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
