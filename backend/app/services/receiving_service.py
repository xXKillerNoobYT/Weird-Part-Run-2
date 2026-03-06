"""
Receiving service — PO receiving, staging zone assignment, price changes.

Phase 5 (original) entry points:
  1. By PO# — see expected items, check off
  2. By Supplier — all open lines, bulk check
  3. By Item scan — search part, pick PO match

Phase 7C adds session-based receiving:
  - start_session(po_id, mode, user_id) → create session + line items
  - update_session_item(session_id, po_line_id, qty, ...) → save progress
  - commit_session(session_id, user_id) → apply all quantities to PO
  - cancel_session(session_id, user_id) → discard progress

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
from app.services.cost_tracking_service import CostTrackingService

logger = logging.getLogger(__name__)


class ReceivingService:
    """Handles all PO receiving workflows — legacy one-shot and session-based."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.po_repo = PurchaseOrderRepo(db)
        self.po_line_repo = POLineRepo(db)
        self.jpo_line_repo = JPOLineRepo(db)
        self.history_repo = OrderStatusHistoryRepo(db)
        self.price_repo = PriceHistoryRepo(db)
        self.zone_repo = StagingZoneRepo(db)
        self.assignment_repo = StagingAssignmentRepo(db)
        self.cost_tracking = CostTrackingService(db)

    # ═══════════════════════════════════════════════════════════════
    # Session-Based Receiving (Phase 7C)
    # ═══════════════════════════════════════════════════════════════

    async def start_session(
        self, po_id: int, mode: str, user_id: int, notes: str | None = None
    ) -> dict:
        """Start a new receiving session for a PO.

        Creates the session and pre-populates items from PO lines that
        still have outstanding quantities (qty_ordered - qty_received > 0).

        Returns the full session with items.
        """
        po = await self.po_repo.get_by_id(po_id)
        if not po:
            raise ValueError(f"PO {po_id} not found")

        # Check no other in-progress session exists for this PO
        cursor = await self.db.execute(
            "SELECT id FROM receiving_sessions WHERE po_id = ? AND status = 'in_progress'",
            (po_id,),
        )
        existing = await cursor.fetchone()
        if existing:
            raise ValueError(
                f"PO {po_id} already has an active receiving session (#{existing['id']})"
            )

        # Create the session
        cursor = await self.db.execute(
            """
            INSERT INTO receiving_sessions (po_id, started_by, mode, notes)
            VALUES (?, ?, ?, ?)
            """,
            (po_id, user_id, mode, notes),
        )
        session_id = cursor.lastrowid

        # Pre-populate items from PO lines with remaining quantities
        cursor = await self.db.execute(
            """
            SELECT id, part_id, qty_ordered, qty_received
            FROM po_line_items
            WHERE po_id = ? AND status NOT IN ('cancelled')
            ORDER BY id
            """,
            (po_id,),
        )
        po_lines = await cursor.fetchall()

        for line in po_lines:
            remaining = line["qty_ordered"] - line["qty_received"]
            if remaining > 0:
                await self.db.execute(
                    """
                    INSERT INTO receiving_session_items
                        (session_id, po_line_id, expected_qty, received_qty)
                    VALUES (?, ?, ?, 0)
                    """,
                    (session_id, line["id"], remaining),
                )

        await self.db.commit()
        return await self.get_session(session_id)

    async def get_session(self, session_id: int) -> dict | None:
        """Get a receiving session with all items and progress summary."""
        cursor = await self.db.execute(
            """
            SELECT rs.*,
                   po.po_number,
                   s.name AS supplier_name,
                   u.display_name AS starter_name
            FROM receiving_sessions rs
            JOIN purchase_orders po ON po.id = rs.po_id
            JOIN suppliers s ON s.id = po.supplier_id
            LEFT JOIN users u ON u.id = rs.started_by
            WHERE rs.id = ?
            """,
            (session_id,),
        )
        session = await cursor.fetchone()
        if not session:
            return None

        # Get items with part details
        cursor = await self.db.execute(
            """
            SELECT rsi.*,
                   pli.part_id,
                   p.part_number,
                   p.description AS part_description,
                   pli.unit_cost,
                   sz.label AS zone_label
            FROM receiving_session_items rsi
            JOIN po_line_items pli ON pli.id = rsi.po_line_id
            JOIN parts p ON p.id = pli.part_id
            LEFT JOIN staging_zones sz ON sz.id = rsi.staging_zone_id
            WHERE rsi.session_id = ?
            ORDER BY rsi.id
            """,
            (session_id,),
        )
        items = await cursor.fetchall()

        total_expected = sum(i["expected_qty"] for i in items)
        total_received = sum(i["received_qty"] for i in items)

        result = dict(session)
        result["items"] = [dict(i) for i in items]
        result["total_expected"] = total_expected
        result["total_received"] = total_received
        result["line_count"] = len(items)
        return result

    async def list_sessions(
        self,
        po_id: int | None = None,
        status: str | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> dict:
        """List receiving sessions with optional filters."""
        where_clauses = []
        params: list[Any] = []

        if po_id:
            where_clauses.append("rs.po_id = ?")
            params.append(po_id)
        if status:
            where_clauses.append("rs.status = ?")
            params.append(status)

        where_sql = f"WHERE {' AND '.join(where_clauses)}" if where_clauses else ""

        # Count total
        cursor = await self.db.execute(
            f"SELECT COUNT(*) AS cnt FROM receiving_sessions rs {where_sql}",
            tuple(params),
        )
        row = await cursor.fetchone()
        total = row["cnt"] if row else 0

        # Fetch items
        cursor = await self.db.execute(
            f"""
            SELECT rs.*,
                   po.po_number,
                   s.name AS supplier_name,
                   u.display_name AS starter_name,
                   (SELECT SUM(expected_qty) FROM receiving_session_items WHERE session_id = rs.id) AS total_expected,
                   (SELECT SUM(received_qty) FROM receiving_session_items WHERE session_id = rs.id) AS total_received
            FROM receiving_sessions rs
            JOIN purchase_orders po ON po.id = rs.po_id
            JOIN suppliers s ON s.id = po.supplier_id
            LEFT JOIN users u ON u.id = rs.started_by
            {where_sql}
            ORDER BY rs.created_at DESC
            LIMIT ? OFFSET ?
            """,
            tuple(params) + (limit, offset),
        )
        sessions = [dict(r) for r in await cursor.fetchall()]

        return {"items": sessions, "total": total}

    async def update_session_item(
        self,
        session_id: int,
        po_line_id: int,
        received_qty: int,
        actual_cost: float | None = None,
        staging_zone_id: int | None = None,
        notes: str | None = None,
    ) -> dict | None:
        """Update a single item in a receiving session (save progress).

        The received_qty is the TOTAL for this line, not a delta.
        Returns the updated session item.
        """
        # Verify session is in_progress
        cursor = await self.db.execute(
            "SELECT id, status FROM receiving_sessions WHERE id = ?",
            (session_id,),
        )
        session = await cursor.fetchone()
        if not session or session["status"] != "in_progress":
            return None

        # Find or create the session item
        cursor = await self.db.execute(
            "SELECT id FROM receiving_session_items WHERE session_id = ? AND po_line_id = ?",
            (session_id, po_line_id),
        )
        item = await cursor.fetchone()

        if item:
            # Update existing
            update_parts = ["received_qty = ?"]
            update_params: list[Any] = [received_qty]

            if actual_cost is not None:
                update_parts.append("actual_cost = ?")
                update_params.append(actual_cost)
            if staging_zone_id is not None:
                update_parts.append("staging_zone_id = ?")
                update_params.append(staging_zone_id)
            if notes is not None:
                update_parts.append("notes = ?")
                update_params.append(notes)

            update_params.append(item["id"])
            await self.db.execute(
                f"UPDATE receiving_session_items SET {', '.join(update_parts)} WHERE id = ?",
                tuple(update_params),
            )
        else:
            # Create new (for scan mode — items scanned that weren't pre-populated)
            cursor2 = await self.db.execute(
                "SELECT qty_ordered, qty_received FROM po_line_items WHERE id = ?",
                (po_line_id,),
            )
            po_line = await cursor2.fetchone()
            expected = (po_line["qty_ordered"] - po_line["qty_received"]) if po_line else 0

            await self.db.execute(
                """
                INSERT INTO receiving_session_items
                    (session_id, po_line_id, expected_qty, received_qty,
                     actual_cost, staging_zone_id, scanned_at, notes)
                VALUES (?, ?, ?, ?, ?, ?, datetime('now'), ?)
                """,
                (session_id, po_line_id, expected, received_qty,
                 actual_cost, staging_zone_id, notes),
            )

        await self.db.commit()
        return await self.get_session(session_id)

    async def commit_session(
        self, session_id: int, user_id: int, notes: str | None = None
    ) -> dict:
        """Commit a receiving session — apply all received quantities to the PO.

        This is the critical operation: it calls the existing receive_po_items
        logic for each item that has received_qty > 0, then marks the session
        as completed.
        """
        session = await self.get_session(session_id)
        if not session:
            raise ValueError(f"Session {session_id} not found")
        if session["status"] != "in_progress":
            raise ValueError(f"Session {session_id} is {session['status']}, not in_progress")

        # Build items list for the existing receive_po_items method
        items_to_receive = []
        for item in session["items"]:
            if item["received_qty"] > 0:
                items_to_receive.append({
                    "po_line_id": item["po_line_id"],
                    "qty_received": item["received_qty"],
                    "actual_cost": item.get("actual_cost"),
                    "staging_zone_id": item.get("staging_zone_id"),
                })

        if not items_to_receive:
            raise ValueError("No items to receive — all quantities are 0")

        # Use the existing receive_po_items to do the heavy lifting
        # (stock movements, PO status updates, price changes, JPO cascading)
        result = await self.receive_po_items(
            session["po_id"], items_to_receive, user_id
        )

        # Mark session as completed (receive_po_items already committed)
        await self.db.execute(
            """
            UPDATE receiving_sessions
            SET status = 'completed', completed_at = datetime('now'), notes = COALESCE(?, notes)
            WHERE id = ?
            """,
            (notes, session_id),
        )
        await self.db.commit()

        result["session_id"] = session_id
        result["session_status"] = "completed"
        return result

    async def cancel_session(self, session_id: int, user_id: int) -> bool:
        """Cancel a receiving session — discard all progress."""
        cursor = await self.db.execute(
            "SELECT id, status FROM receiving_sessions WHERE id = ?",
            (session_id,),
        )
        session = await cursor.fetchone()
        if not session or session["status"] != "in_progress":
            return False

        await self.db.execute(
            "UPDATE receiving_sessions SET status = 'cancelled' WHERE id = ?",
            (session_id,),
        )
        await self.db.commit()
        return True

    async def find_po_line_by_part_scan(
        self, session_id: int, part_id: int
    ) -> dict | None:
        """Find a PO line matching a scanned part within a session's PO.

        Used in scan mode: user scans a QR code → we look up which PO line
        on this session's PO matches the scanned part.
        """
        cursor = await self.db.execute(
            """
            SELECT pli.id AS po_line_id, pli.part_id,
                   pli.qty_ordered, pli.qty_received,
                   p.part_number, p.description AS part_description,
                   pli.unit_cost,
                   rsi.id AS session_item_id,
                   rsi.expected_qty,
                   rsi.received_qty AS session_received_qty
            FROM receiving_sessions rs
            JOIN po_line_items pli ON pli.po_id = rs.po_id
            JOIN parts p ON p.id = pli.part_id
            LEFT JOIN receiving_session_items rsi
                ON rsi.session_id = rs.id AND rsi.po_line_id = pli.id
            WHERE rs.id = ? AND pli.part_id = ? AND pli.status NOT IN ('cancelled')
            LIMIT 1
            """,
            (session_id, part_id),
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

    # ═══════════════════════════════════════════════════════════════
    # Legacy One-Shot Receiving (Phase 5 — kept for backward compat)
    # ═══════════════════════════════════════════════════════════════

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

            # ── Phase 7D: Create cost layer for FIFO tracking ──
            layer_cost = actual_cost if actual_cost is not None else line.get("unit_cost", 0)
            try:
                await self.cost_tracking.add_cost_layer(
                    part_id=line["part_id"],
                    qty=qty,
                    unit_cost=layer_cost,
                    po_line_id=line_id,
                )
            except Exception as e:
                logger.warning("Cost layer creation failed for part %d: %s", line["part_id"], e)

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
