"""
Audit repository — data access for audit sessions and items.

Handles CRUD for audits and audit_items tables, with specialized
queries for the card-swipe UI ordering and progress tracking.
"""

from __future__ import annotations

from typing import Any

import aiosqlite

from app.repositories.base import BaseRepo


class AuditRepo(BaseRepo):
    """Data access for audit sessions."""

    TABLE = "audits"

    async def get_audits(
        self,
        *,
        status: str | None = None,
        audit_type: str | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """List audits with optional filters, joined with user and category names."""
        where_clauses: list[str] = []
        params: list[Any] = []

        if status:
            where_clauses.append("a.status = ?")
            params.append(status)
        if audit_type:
            where_clauses.append("a.audit_type = ?")
            params.append(audit_type)

        where_sql = f"WHERE {' AND '.join(where_clauses)}" if where_clauses else ""

        cursor = await self.db.execute(
            f"""SELECT a.*,
                       u.display_name AS started_by_name,
                       pc.name AS category_name
                FROM audits a
                LEFT JOIN users u ON u.id = a.started_by
                LEFT JOIN part_categories pc ON pc.id = a.category_id
                {where_sql}
                ORDER BY a.created_at DESC
                LIMIT ? OFFSET ?""",
            (*params, limit, offset),
        )
        return await cursor.fetchall()

    async def get_audit_with_details(self, audit_id: int) -> dict | None:
        """Get a single audit with user/category names and progress stats."""
        cursor = await self.db.execute(
            """SELECT a.*,
                      u.display_name AS started_by_name,
                      pc.name AS category_name
               FROM audits a
               LEFT JOIN users u ON u.id = a.started_by
               LEFT JOIN part_categories pc ON pc.id = a.category_id
               WHERE a.id = ?""",
            (audit_id,),
        )
        audit = await cursor.fetchone()
        if not audit:
            return None

        # Get progress counts
        progress = await self.count_by_result(audit_id)
        return {**dict(audit), "progress": progress}

    async def count_by_result(self, audit_id: int) -> dict:
        """Count audit items grouped by result status."""
        cursor = await self.db.execute(
            """SELECT
                   COUNT(*) AS total_items,
                   SUM(CASE WHEN result != 'pending' THEN 1 ELSE 0 END) AS counted,
                   SUM(CASE WHEN result = 'match' THEN 1 ELSE 0 END) AS matched,
                   SUM(CASE WHEN result = 'discrepancy' THEN 1 ELSE 0 END) AS discrepancies,
                   SUM(CASE WHEN result = 'skipped' THEN 1 ELSE 0 END) AS skipped,
                   SUM(CASE WHEN result = 'pending' THEN 1 ELSE 0 END) AS pending
               FROM audit_items
               WHERE audit_id = ?""",
            (audit_id,),
        )
        row = await cursor.fetchone()
        if not row:
            return {"total_items": 0, "counted": 0, "matched": 0,
                    "discrepancies": 0, "skipped": 0, "pending": 0, "pct_complete": 0.0}

        total = row["total_items"] or 0
        counted = row["counted"] or 0
        return {
            **dict(row),
            "pct_complete": round((counted / total * 100) if total > 0 else 0, 1),
        }

    async def update_summary_counts(self, audit_id: int) -> None:
        """Refresh the cached summary counts on the audit row."""
        progress = await self.count_by_result(audit_id)
        await self.db.execute(
            """UPDATE audits SET
                   total_items = ?,
                   matched_items = ?,
                   discrepancy_count = ?,
                   skipped_count = ?
               WHERE id = ?""",
            (
                progress["total_items"],
                progress["matched"],
                progress["discrepancies"],
                progress["skipped"],
                audit_id,
            ),
        )


class AuditItemRepo(BaseRepo):
    """Data access for individual audit count items."""

    TABLE = "audit_items"

    async def get_next_pending_item(self, audit_id: int) -> dict | None:
        """Get the next un-counted item, ordered by shelf location then name."""
        cursor = await self.db.execute(
            """SELECT ai.*,
                      p.name AS part_name,
                      p.code AS part_code,
                      p.shelf_location,
                      p.image_url
               FROM audit_items ai
               JOIN parts p ON p.id = ai.part_id
               WHERE ai.audit_id = ? AND ai.result = 'pending'
               ORDER BY
                   CASE WHEN p.shelf_location IS NOT NULL THEN 0 ELSE 1 END,
                   p.shelf_location ASC,
                   p.name ASC
               LIMIT 1""",
            (audit_id,),
        )
        return await cursor.fetchone()

    async def get_items_for_audit(
        self, audit_id: int, *, result_filter: str | None = None
    ) -> list[dict]:
        """Get all items for an audit, with part details."""
        where = "ai.audit_id = ?"
        params: list[Any] = [audit_id]

        if result_filter:
            where += " AND ai.result = ?"
            params.append(result_filter)

        cursor = await self.db.execute(
            f"""SELECT ai.*,
                       p.name AS part_name,
                       p.code AS part_code,
                       p.shelf_location,
                       p.image_url
                FROM audit_items ai
                JOIN parts p ON p.id = ai.part_id
                WHERE {where}
                ORDER BY
                    CASE WHEN p.shelf_location IS NOT NULL THEN 0 ELSE 1 END,
                    p.shelf_location ASC,
                    p.name ASC""",
            params,
        )
        return await cursor.fetchall()

    async def record_count(
        self,
        item_id: int,
        actual_qty: int,
        result: str,
        discrepancy_note: str | None = None,
        photo_path: str | None = None,
    ) -> bool:
        """Record a count for an audit item."""
        cursor = await self.db.execute(
            """UPDATE audit_items SET
                   actual_qty = ?,
                   result = ?,
                   discrepancy_note = ?,
                   photo_path = ?,
                   counted_at = datetime('now')
               WHERE id = ?""",
            (actual_qty, result, discrepancy_note, photo_path, item_id),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def bulk_insert(self, audit_id: int, items: list[dict]) -> int:
        """Insert multiple audit items for a new audit session."""
        count = 0
        for item in items:
            await self.db.execute(
                """INSERT OR IGNORE INTO audit_items (audit_id, part_id, expected_qty)
                   VALUES (?, ?, ?)""",
                (audit_id, item["part_id"], item["expected_qty"]),
            )
            count += 1
        await self.db.commit()
        return count
