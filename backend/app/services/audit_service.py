"""
Audit Service — orchestrates audit sessions (spot check, category, rolling).

Handles:
- Starting new audits and populating items from current stock
- Card-swipe item ordering (shelf location → category+alpha fallback)
- Completing audits and generating summaries
- Applying stock adjustments for discrepancies via MovementService
- Rolling audit scheduling (category rotation + staleness priority)
- Spot-check creation triggered by low stock
"""

from __future__ import annotations

import logging
from typing import Any

import aiosqlite

from app.models.warehouse import (
    AuditItemResponse,
    AuditProgress,
    AuditResponse,
    AuditSummary,
)
from app.repositories.audit_repo import AuditItemRepo, AuditRepo

logger = logging.getLogger(__name__)


class AuditService:
    """Orchestrates audit workflows."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.audit_repo = AuditRepo(db)
        self.item_repo = AuditItemRepo(db)

    # ── Start Audit ───────────────────────────────────────────────

    async def start_audit(
        self,
        audit_type: str,
        started_by: int,
        location_type: str = "warehouse",
        location_id: int = 1,
        category_id: int | None = None,
        part_ids: list[int] | None = None,
    ) -> dict:
        """Start a new audit session and populate items from current stock."""
        # Create the audit record
        audit_id = await self.audit_repo.insert({
            "audit_type": audit_type,
            "location_type": location_type,
            "location_id": location_id,
            "category_id": category_id,
            "started_by": started_by,
        })

        # Populate items based on audit type
        if audit_type == "spot_check" and part_ids:
            items = await self._build_items_for_parts(part_ids, location_type, location_id)
        elif audit_type == "category" and category_id:
            items = await self._build_items_for_category(category_id, location_type, location_id)
        elif audit_type == "rolling":
            items = await self._build_items_for_rolling(location_type, location_id)
        else:
            items = []

        if items:
            await self.item_repo.bulk_insert(audit_id, items)

        # Update total count
        await self.db.execute(
            "UPDATE audits SET total_items = ? WHERE id = ?",
            (len(items), audit_id),
        )
        await self.db.commit()

        return await self.audit_repo.get_audit_with_details(audit_id)

    # ── Item Population ───────────────────────────────────────────

    async def _build_items_for_parts(
        self, part_ids: list[int], location_type: str, location_id: int
    ) -> list[dict]:
        """Build audit items for specific parts (spot check)."""
        items = []
        for pid in part_ids:
            cursor = await self.db.execute(
                """SELECT COALESCE(SUM(qty), 0) AS expected
                   FROM stock WHERE part_id = ? AND location_type = ? AND location_id = ?""",
                (pid, location_type, location_id),
            )
            row = await cursor.fetchone()
            items.append({"part_id": pid, "expected_qty": row["expected"] if row else 0})
        return items

    async def _build_items_for_category(
        self, category_id: int, location_type: str, location_id: int
    ) -> list[dict]:
        """Build audit items for all parts in a category."""
        cursor = await self.db.execute(
            """SELECT p.id AS part_id,
                      COALESCE(s.qty, 0) AS expected_qty
               FROM parts p
               LEFT JOIN (
                   SELECT part_id, SUM(qty) AS qty FROM stock
                   WHERE location_type = ? AND location_id = ?
                   GROUP BY part_id
               ) s ON s.part_id = p.id
               WHERE p.category_id = ? AND p.is_deprecated = 0
               ORDER BY p.shelf_location, p.name""",
            (location_type, location_id, category_id),
        )
        return [dict(row) for row in await cursor.fetchall()]

    async def _build_items_for_rolling(
        self, location_type: str, location_id: int, limit: int = 50
    ) -> list[dict]:
        """Build audit items for rolling audit — category rotation + staleness.

        Picks parts from the next category in rotation, prioritizing
        parts that haven't been audited recently.
        """
        # Find the least-recently-audited category with stock
        cursor = await self.db.execute(
            """SELECT p.category_id, pc.name,
                      MAX(COALESCE(ai.counted_at, '2000-01-01')) AS last_audited
               FROM parts p
               JOIN part_categories pc ON pc.id = p.category_id
               LEFT JOIN audit_items ai ON ai.part_id = p.id
               JOIN stock s ON s.part_id = p.id
                   AND s.location_type = ? AND s.location_id = ? AND s.qty > 0
               WHERE p.is_deprecated = 0
               GROUP BY p.category_id
               ORDER BY last_audited ASC
               LIMIT 1""",
            (location_type, location_id),
        )
        row = await cursor.fetchone()
        if not row:
            return []

        category_id = row["category_id"]

        # Get parts in this category, ordered by staleness (least recently counted first)
        cursor = await self.db.execute(
            """SELECT p.id AS part_id,
                      COALESCE(s.qty, 0) AS expected_qty,
                      MAX(COALESCE(ai.counted_at, '2000-01-01')) AS last_counted
               FROM parts p
               LEFT JOIN (
                   SELECT part_id, SUM(qty) AS qty FROM stock
                   WHERE location_type = ? AND location_id = ?
                   GROUP BY part_id
               ) s ON s.part_id = p.id
               LEFT JOIN audit_items ai ON ai.part_id = p.id
               WHERE p.category_id = ? AND p.is_deprecated = 0
               GROUP BY p.id
               ORDER BY last_counted ASC, p.shelf_location, p.name
               LIMIT ?""",
            (location_type, location_id, category_id, limit),
        )
        return [{"part_id": r["part_id"], "expected_qty": r["expected_qty"]}
                for r in await cursor.fetchall()]

    # ── Get Next Item ─────────────────────────────────────────────

    async def get_next_item(self, audit_id: int) -> AuditItemResponse | None:
        """Get the next un-counted item for the card-swipe UI."""
        row = await self.item_repo.get_next_pending_item(audit_id)
        if not row:
            return None

        return AuditItemResponse(
            id=row["id"],
            audit_id=row["audit_id"],
            part_id=row["part_id"],
            part_name=row["part_name"],
            part_code=row.get("part_code"),
            shelf_location=row.get("shelf_location"),
            image_url=row.get("image_url"),
            expected_qty=row["expected_qty"],
            actual_qty=row.get("actual_qty"),
            result=row["result"],
        )

    # ── Record Count ──────────────────────────────────────────────

    async def record_count(
        self,
        audit_id: int,
        item_id: int,
        actual_qty: int,
        result: str,
        discrepancy_note: str | None = None,
        photo_path: str | None = None,
    ) -> bool:
        """Record a count and update audit summary."""
        success = await self.item_repo.record_count(
            item_id, actual_qty, result, discrepancy_note, photo_path
        )
        if success:
            await self.audit_repo.update_summary_counts(audit_id)
            await self.db.commit()
        return success

    # ── Complete Audit ────────────────────────────────────────────

    async def complete_audit(self, audit_id: int) -> AuditSummary:
        """Mark audit as completed and return summary."""
        await self.audit_repo.update_summary_counts(audit_id)
        await self.db.execute(
            """UPDATE audits SET
                   status = 'completed',
                   completed_at = datetime('now')
               WHERE id = ?""",
            (audit_id,),
        )
        await self.db.commit()

        audit = await self.audit_repo.get_audit_with_details(audit_id)
        progress = audit["progress"] if audit else {}

        return AuditSummary(
            audit_id=audit_id,
            audit_type=audit["audit_type"] if audit else "unknown",
            status="completed",
            progress=AuditProgress(**progress),
            adjustments_needed=progress.get("discrepancies", 0),
            has_unapplied_adjustments=progress.get("discrepancies", 0) > 0,
        )

    # ── Apply Adjustments ─────────────────────────────────────────

    async def apply_adjustments(self, audit_id: int, user_id: int) -> int:
        """Create stock adjustment movements for all discrepancies.

        Returns the number of adjustments applied.
        """
        from app.services.movement_service import MovementService

        items = await self.item_repo.get_items_for_audit(audit_id, result_filter="discrepancy")
        if not items:
            return 0

        audit = await self.audit_repo.get_by_id(audit_id)
        if not audit:
            return 0

        movement_svc = MovementService(self.db)
        count = 0

        for item in items:
            expected = item["expected_qty"]
            actual = item["actual_qty"]
            if actual is None:
                continue

            diff = actual - expected
            if diff == 0:
                continue

            # Positive diff = found extra stock, negative = stock missing
            if diff > 0:
                # Add stock (adjustment receive)
                await self.db.execute(
                    """INSERT INTO stock (part_id, location_type, location_id, qty, updated_at)
                       VALUES (?, ?, ?, ?, datetime('now'))
                       ON CONFLICT(part_id, location_type, location_id, supplier_id)
                       DO UPDATE SET qty = qty + ?, updated_at = datetime('now')""",
                    (item["part_id"], audit["location_type"], audit["location_id"],
                     diff, diff),
                )
                movement_type = "adjust"
                reason = f"Audit #{audit_id}: found {diff} extra"
            else:
                # Remove stock (write off missing)
                await self.db.execute(
                    """UPDATE stock SET qty = MAX(0, qty + ?), updated_at = datetime('now')
                       WHERE part_id = ? AND location_type = ? AND location_id = ?""",
                    (diff, item["part_id"], audit["location_type"], audit["location_id"]),
                )
                movement_type = "adjust"
                reason = f"Audit #{audit_id}: missing {abs(diff)}"

            # Log the adjustment movement
            await movement_svc._log_movement(
                part_id=item["part_id"],
                qty=abs(diff),
                from_location_type=audit["location_type"] if diff < 0 else None,
                from_location_id=audit["location_id"] if diff < 0 else None,
                to_location_type=audit["location_type"] if diff > 0 else None,
                to_location_id=audit["location_id"] if diff > 0 else None,
                movement_type=movement_type,
                reason=reason,
                performed_by=user_id,
                notes=item.get("discrepancy_note"),
                unit_cost=None,
                unit_sell=None,
            )
            count += 1

        # Update last_counted on stock rows
        await self.db.execute(
            """UPDATE stock SET last_counted = datetime('now')
               WHERE location_type = ? AND location_id = ?
                 AND part_id IN (SELECT part_id FROM audit_items WHERE audit_id = ?)""",
            (audit["location_type"], audit["location_id"], audit_id),
        )

        await self.db.commit()

        # Update forecast for affected parts
        for item in items:
            await movement_svc._update_forecast(item["part_id"])

        return count

    # ── Suggested Rolling Parts ───────────────────────────────────

    async def get_suggested_rolling_parts(self, limit: int = 20) -> list[dict]:
        """Get parts suggested for the next rolling audit batch."""
        cursor = await self.db.execute(
            """SELECT p.id, p.name, p.code, p.shelf_location,
                      pc.name AS category_name,
                      COALESCE(MAX(ai.counted_at), 'never') AS last_counted_at,
                      COALESCE(s.qty, 0) AS warehouse_qty
               FROM parts p
               JOIN part_categories pc ON pc.id = p.category_id
               LEFT JOIN audit_items ai ON ai.part_id = p.id
               LEFT JOIN (
                   SELECT part_id, SUM(qty) AS qty FROM stock
                   WHERE location_type = 'warehouse' GROUP BY part_id
               ) s ON s.part_id = p.id
               WHERE p.is_deprecated = 0
               GROUP BY p.id
               ORDER BY
                   COALESCE(MAX(ai.counted_at), '2000-01-01') ASC,
                   p.shelf_location, p.name
               LIMIT ?""",
            (limit,),
        )
        return await cursor.fetchall()
