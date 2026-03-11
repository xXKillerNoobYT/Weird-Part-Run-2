"""
Orders service — JPO + PO lifecycle, status transitions, audit trail.

Handles:
  - JPO creation (with auto-numbering), approval/rejection
  - Unified order creation (job orders + warehouse restocks)  ← Phase 7A
  - PO creation from JPOs and standalone
  - Status transitions with full audit trail
  - Supplier suggestion tagging
  - PO total recalculation
  - Special item creation + preference learning after order  ← Phase 7A
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
from app.services.job_preferences_service import JobPreferencesService

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
        self.prefs_service = JobPreferencesService(db)

    # ── JPO Lifecycle ─────────────────────────────────────────

    async def create_jpo(
        self,
        requested_by: int,
        lines: list[dict],
        *,
        job_id: int | None = None,
        order_type: str = "job",
        priority: str = "normal",
        smart_suggestions_enabled: bool = True,
        notes: str | None = None,
        special_items: list[dict] | None = None,
    ) -> dict:
        """Create a unified order — either a Job Order or Warehouse Restock.

        Phase 7A: this is the single entry-point for creating any parts order.

        Job orders (order_type='job'):
          - Require a job_id
          - Auto-number from job name: '{JOB_NAME}-JPO-001'
          - After creation, learn brand/color/supplier preferences for the job

        Warehouse restocks (order_type='warehouse'):
          - job_id is None
          - Auto-number as 'WH-JPO-001'
          - No preference learning (no job context)

        Special items (non-catalog):
          - Passed as a list of dicts with description, quantity, etc.
          - Auto-flagged for office review
          - Sets has_special_items = 1 on the JPO

        Always starts in 'draft' status.
        """
        # ── Validate ──────────────────────────────────────────────
        if order_type == "job" and not job_id:
            raise ValueError("job_id is required for job orders")
        if order_type == "warehouse":
            job_id = None  # Enforce — warehouse restocks never belong to a job

        # ── Generate order number ─────────────────────────────────
        order_number = await self.jpo_repo.get_next_order_number(job_id)

        has_specials = 1 if special_items else 0

        # ── Insert the JPO ────────────────────────────────────────
        jpo_id = await self.jpo_repo.insert({
            "job_id": job_id,
            "order_number": order_number,
            "status": "draft",
            "priority": priority,
            "order_type": order_type,
            "has_special_items": has_specials,
            "smart_suggestions_enabled": 1 if smart_suggestions_enabled else 0,
            "requested_by": requested_by,
            "notes": notes,
        })

        # ── Insert catalog line items ─────────────────────────────
        if lines:
            await self.jpo_line_repo.bulk_insert(jpo_id, lines)

        # ── Auto-populate suggested_supplier_id from job prefs ────
        # For job orders, look up preferred suppliers per-part (using
        # category-specific preferences) and stamp each line.  This
        # feeds the "→ SupplierName (Category)" display on the frontend
        # and enables accurate PO auto-generation later.
        if order_type == "job" and job_id and lines:
            try:
                inserted_lines = await self.jpo_line_repo.get_lines_for_jpo(jpo_id)
                for jpo_line in inserted_lines:
                    # Skip if the frontend already sent a suggestion
                    if jpo_line.get("suggested_supplier_id"):
                        continue
                    pref = await self.prefs_service.get_preferred_supplier(
                        job_id, jpo_line["part_id"]
                    )
                    if pref:
                        await self.db.execute(
                            "UPDATE jpo_line_items SET suggested_supplier_id = ? WHERE id = ?",
                            (pref["supplier_id"], jpo_line["id"]),
                        )
            except Exception:
                # Best-effort — never block order creation
                logger.exception(
                    "Failed to auto-populate suppliers for JPO %d", jpo_id
                )

        # ── Insert special (non-catalog) items ────────────────────
        if special_items:
            for item in special_items:
                await self.prefs_service.add_special_item(
                    jpo_id,
                    description=item["description"],
                    quantity=item.get("quantity", 1),
                    part_number=item.get("part_number"),
                    unit=item.get("unit", "each"),
                    estimated_cost=item.get("estimated_cost"),
                    notes=item.get("notes"),
                )

        # ── Audit trail ───────────────────────────────────────────
        label = "Job order created" if order_type == "job" else "Warehouse restock created"
        await self.history_repo.log_change(
            "jpo", jpo_id, None, "draft", requested_by, label
        )

        await self.db.commit()

        # ── Learn job preferences (async-safe, non-blocking) ─────
        if order_type == "job" and job_id and lines:
            try:
                learned = await self.prefs_service.learn_from_order(jpo_id)
                logger.info(
                    "Learned preferences from JPO %d: %s",
                    jpo_id, learned,
                )
            except Exception:
                # Preference learning is best-effort — never block order creation
                logger.exception("Failed to learn preferences from JPO %d", jpo_id)

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
        # Get job_id from JPO for GC-aware PO naming
        jpo = await self.jpo_repo.get_by_id(jpo_id)
        jpo_job_id = jpo["job_id"] if jpo else None
        po_number = await self.po_repo.get_next_po_number(supplier_id, job_id=jpo_job_id)

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
        """Auto-split approved JPO lines by preferred supplier into draft POs.

        Supplier resolution order per line:
          1. suggested_supplier_id already set on the JPO line
          2. Job's explicit preferred suppliers (primary first, then backups)
          3. Catalog-level preferred supplier from part_supplier_links
          4. Line skipped (no PO created — office handles manually)
        """
        unordered = await self.jpo_line_repo.get_unordered_lines(jpo_id)
        if not unordered:
            return []

        # Get the JPO's job_id for explicit supplier lookup
        jpo = await self.jpo_repo.get_by_id(jpo_id)
        job_id = jpo["job_id"] if jpo else None

        # Pre-fetch explicit preferred suppliers for this job (if it's a job order)
        explicit_suppliers: list[dict] = []
        if job_id:
            try:
                explicit_suppliers = await self.prefs_service.get_explicit_suppliers(
                    job_id
                )
            except Exception:
                logger.exception("Failed to fetch explicit suppliers for job %d", job_id)

        # Primary explicit supplier (highest confidence, first in list)
        primary_explicit_id = (
            explicit_suppliers[0]["supplier_id"] if explicit_suppliers else None
        )

        # Group lines by supplier
        supplier_groups: dict[int, list[dict]] = {}
        for line in unordered:
            supplier_id = line.get("suggested_supplier_id")

            # Fallback 1: Job's explicit preferred suppliers
            if not supplier_id and primary_explicit_id:
                supplier_id = primary_explicit_id

            # Fallback 2: Catalog-level preferred supplier
            if not supplier_id:
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

    # ── Cross-Job Summary ───────────────────────────────────

    async def get_order_summary(self) -> dict:
        """
        Cross-job aggregate summary of all approved JPO lines that still
        need ordering (qty_requested > qty_ordered).

        Returns part-level aggregation: total qty needed, number of distinct
        jobs, job names, and suggested supplier.  Phase 17 Gap 4.
        """
        cursor = await self.db.execute(
            """
            SELECT
                p.id                          AS part_id,
                p.name                        AS part_name,
                pc.name                       AS category_name,
                SUM(li.qty_requested - li.qty_ordered) AS total_qty_needed,
                COUNT(DISTINCT jpo.job_id)    AS job_count,
                GROUP_CONCAT(DISTINCT j.job_name) AS job_names,
                li.suggested_supplier_id,
                s.name                        AS supplier_name
            FROM jpo_line_items li
            JOIN job_parts_orders jpo ON li.jpo_id = jpo.id
            JOIN parts p              ON li.part_id = p.id
            LEFT JOIN part_categories pc ON p.category_id = pc.id
            LEFT JOIN suppliers s     ON li.suggested_supplier_id = s.id
            LEFT JOIN jobs j          ON jpo.job_id = j.id
            WHERE jpo.status = 'approved'
              AND li.qty_requested > li.qty_ordered
            GROUP BY p.id
            ORDER BY total_qty_needed DESC
            """
        )
        rows = await cursor.fetchall()

        lines = []
        supplier_ids: set[int] = set()
        total_qty = 0
        job_ids_all: set[str] = set()

        for r in rows:
            job_name_str = r["job_names"] or ""
            job_list = [n.strip() for n in job_name_str.split(",") if n.strip()]
            job_ids_all.update(job_list)
            total_qty += r["total_qty_needed"]
            if r["suggested_supplier_id"]:
                supplier_ids.add(r["suggested_supplier_id"])

            lines.append({
                "part_id": r["part_id"],
                "part_name": r["part_name"],
                "category_name": r["category_name"],
                "total_qty_needed": r["total_qty_needed"],
                "job_count": r["job_count"],
                "job_names": job_list,
                "suggested_supplier_id": r["suggested_supplier_id"],
                "supplier_name": r["supplier_name"],
            })

        total_parts = len(lines)
        total_jobs = len(job_ids_all)
        total_suppliers = len(supplier_ids)

        # Build human-readable summary text
        parts_word = "part" if total_parts == 1 else "parts"
        jobs_word = "job" if total_jobs == 1 else "jobs"
        suppliers_word = "supplier" if total_suppliers == 1 else "suppliers"
        summary_text = (
            f"{total_qty} units of {total_parts} {parts_word} needed "
            f"across {total_jobs} {jobs_word} from {total_suppliers} {suppliers_word}"
        )

        return {
            "total_parts": total_parts,
            "total_qty": total_qty,
            "total_jobs": total_jobs,
            "total_suppliers": total_suppliers,
            "lines": lines,
            "summary_text": summary_text,
        }

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
