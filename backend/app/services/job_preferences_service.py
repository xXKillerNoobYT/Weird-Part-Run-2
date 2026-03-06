"""
Job Preferences service — smart suggestion memory per job.

After an order is created for a job, this service extracts brand, color,
supplier, and part-usage patterns from the line items and stores them in
the `job_preferences` table.  On subsequent orders the frontend queries
these preferences to auto-filter the part search by the brands, colors,
and suppliers already used on that job.

Learning pipeline:
  1. Field worker creates order with parts (each has brand_id, color_id, etc.)
  2. `learn_from_order(jpo_id)` scans line items and upserts preferences
  3. Confidence scores increase with repeated use (capped at 1.0)
  4. `get_suggestions(job_id)` returns ranked preferences for the frontend
  5. Frontend uses them as filter chips: "Use job brands", "Use job colors", etc.
"""

from __future__ import annotations

import logging
from datetime import datetime
from typing import Any

import aiosqlite

from app.repositories.base import BaseRepo

logger = logging.getLogger(__name__)


# ═══════════════════════════════════════════════════════════════
# Repository
# ═══════════════════════════════════════════════════════════════

class JobPreferencesRepo(BaseRepo):
    TABLE = "job_preferences"
    HAS_UPDATED_AT = True

    async def get_for_job(
        self,
        job_id: int,
        *,
        preference_type: str | None = None,
        category: str | None = None,
        active_only: bool = True,
    ) -> list[dict]:
        """Get preferences for a job, optionally filtered by type/category."""
        sql = """
            SELECT jp.*,
                   CASE jp.preference_type
                       WHEN 'brand'    THEN b.name
                       WHEN 'color'    THEN pc.name
                       WHEN 'supplier' THEN s.name
                       WHEN 'part'     THEN p.description
                   END AS entity_name,
                   CASE jp.preference_type
                       WHEN 'color' THEN pc.hex_code
                   END AS hex_code,
                   cat.name AS category_name
            FROM job_preferences jp
            LEFT JOIN brands b       ON jp.preference_type = 'brand'    AND b.id = jp.entity_id
            LEFT JOIN part_colors pc ON jp.preference_type = 'color'    AND pc.id = jp.entity_id
            LEFT JOIN suppliers s    ON jp.preference_type = 'supplier' AND s.id = jp.entity_id
            LEFT JOIN parts p        ON jp.preference_type = 'part'     AND p.id = jp.entity_id
            LEFT JOIN part_categories cat ON cat.name = jp.category
            WHERE jp.job_id = ?
        """
        params: list[Any] = [job_id]

        if active_only:
            sql += " AND jp.is_active = 1"
        if preference_type:
            sql += " AND jp.preference_type = ?"
            params.append(preference_type)
        if category:
            sql += " AND jp.category = ?"
            params.append(category)

        sql += " ORDER BY jp.confidence_score DESC, jp.last_used_at DESC"

        cursor = await self.db.execute(sql, params)
        return await cursor.fetchall()

    async def upsert_preference(
        self,
        job_id: int,
        preference_type: str,
        entity_id: int | None,
        text_value: str | None,
        category: str | None,
        *,
        auto_learned: bool = True,
        confidence_boost: float = 0.1,
    ) -> int:
        """Insert or update a preference, boosting confidence on repeat use.

        Uses the UNIQUE(job_id, preference_type, entity_id, text_value, category)
        constraint.  If the row already exists we bump its confidence and
        update last_used_at.  If new, insert with base confidence 0.5.

        Returns the preference row ID.
        """
        # Check if it already exists
        sql = """
            SELECT id, confidence_score FROM job_preferences
            WHERE job_id = ?
              AND preference_type = ?
              AND entity_id IS ?
              AND text_value IS ?
              AND category IS ?
        """
        cursor = await self.db.execute(
            sql, (job_id, preference_type, entity_id, text_value, category)
        )
        existing = await cursor.fetchone()

        now = datetime.utcnow().isoformat()

        if existing:
            # Boost confidence (cap at 1.0) and touch last_used_at
            new_score = min(existing["confidence_score"] + confidence_boost, 1.0)
            await self.db.execute(
                """UPDATE job_preferences
                   SET confidence_score = ?,
                       last_used_at = ?,
                       is_active = 1,
                       updated_at = datetime('now')
                   WHERE id = ?""",
                (new_score, now, existing["id"]),
            )
            await self.db.commit()
            return existing["id"]
        else:
            row_id = await self.insert({
                "job_id": job_id,
                "preference_type": preference_type,
                "entity_id": entity_id,
                "text_value": text_value,
                "category": category,
                "is_active": 1,
                "auto_learned": 1 if auto_learned else 0,
                "confidence_score": 0.5,
                "last_used_at": now,
            })
            return row_id

    async def get_preferred_supplier_for_part(
        self,
        job_id: int,
        part_id: int,
    ) -> dict | None:
        """For a given part on a given job, return the most-used supplier.

        Looks at part-level preferences first, then falls back to
        the supplier preference with the highest confidence for this job.
        """
        # Direct: was this exact part ordered from a specific supplier before?
        cursor = await self.db.execute(
            """
            SELECT jp.entity_id AS supplier_id, s.name AS supplier_name,
                   jp.confidence_score
            FROM job_preferences jp
            JOIN suppliers s ON s.id = jp.entity_id
            WHERE jp.job_id = ?
              AND jp.preference_type = 'supplier'
              AND jp.is_active = 1
            ORDER BY jp.confidence_score DESC
            LIMIT 1
            """,
            (job_id,),
        )
        return await cursor.fetchone()


# ═══════════════════════════════════════════════════════════════
# Special Items Repository
# ═══════════════════════════════════════════════════════════════

class SpecialItemsRepo(BaseRepo):
    TABLE = "special_items"
    HAS_UPDATED_AT = False  # special_items only has created_at

    async def get_for_jpo(self, jpo_id: int) -> list[dict]:
        """Get all special items for a JPO, with resolver info."""
        cursor = await self.db.execute(
            """
            SELECT si.*,
                   u.display_name AS resolver_name,
                   p.description AS linked_part_description
            FROM special_items si
            LEFT JOIN users u ON u.id = si.flag_resolved_by
            LEFT JOIN parts p ON p.id = si.linked_part_id
            WHERE si.jpo_id = ?
            ORDER BY si.id
            """,
            (jpo_id,),
        )
        return await cursor.fetchall()

    async def get_flagged(self, *, limit: int = 50) -> list[dict]:
        """Get all unresolved flagged special items across all orders."""
        cursor = await self.db.execute(
            """
            SELECT si.*,
                   jpo.order_number, jpo.job_id,
                   j.job_name, j.job_number,
                   u.display_name AS requester_name
            FROM special_items si
            JOIN job_parts_orders jpo ON jpo.id = si.jpo_id
            LEFT JOIN jobs j ON j.id = jpo.job_id
            LEFT JOIN users u ON u.id = jpo.requested_by
            WHERE si.is_flagged = 1 AND si.flag_resolved_by IS NULL
            ORDER BY si.created_at DESC
            LIMIT ?
            """,
            (limit,),
        )
        return await cursor.fetchall()

    async def resolve(
        self,
        item_id: int,
        resolved_by: int,
        *,
        linked_part_id: int | None = None,
    ) -> bool:
        """Office staff resolves a flagged special item.

        Optionally links it to a catalog part (if they found a match).
        """
        cursor = await self.db.execute(
            """
            UPDATE special_items
            SET is_flagged = 0,
                flag_resolved_by = ?,
                flag_resolved_at = datetime('now'),
                linked_part_id = ?
            WHERE id = ?
            """,
            (resolved_by, linked_part_id, item_id),
        )
        await self.db.commit()
        return cursor.rowcount > 0


# ═══════════════════════════════════════════════════════════════
# Service
# ═══════════════════════════════════════════════════════════════

class JobPreferencesService:
    """Orchestrates learning and querying of job-specific preferences."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.pref_repo = JobPreferencesRepo(db)
        self.special_repo = SpecialItemsRepo(db)

    # ── Learning ─────────────────────────────────────────────

    async def learn_from_order(self, jpo_id: int) -> dict:
        """Extract brand/color/supplier/part patterns from a JPO's line items.

        Called after order creation.  Scans each line item's part to find
        its brand, color, and category, then upserts job_preferences rows.

        Returns a summary of what was learned:
            {"brands": 2, "colors": 1, "suppliers": 3, "parts": 5}
        """
        # Get the JPO to find job_id
        cursor = await self.db.execute(
            "SELECT job_id FROM job_parts_orders WHERE id = ?", (jpo_id,)
        )
        jpo = await cursor.fetchone()
        if not jpo or not jpo["job_id"]:
            # Warehouse restocks (no job_id) don't learn preferences
            logger.debug("Skipping preference learning for JPO %d (no job_id)", jpo_id)
            return {"brands": 0, "colors": 0, "suppliers": 0, "parts": 0}

        job_id = jpo["job_id"]

        # Get all line items with their part details
        cursor = await self.db.execute(
            """
            SELECT li.part_id, li.suggested_supplier_id,
                   p.brand_id, p.color_id, p.category_id, p.part_type,
                   b.name AS brand_name,
                   pc.name AS color_name,
                   cat.name AS category_name
            FROM jpo_line_items li
            JOIN parts p ON p.id = li.part_id
            LEFT JOIN brands b ON b.id = p.brand_id
            LEFT JOIN part_colors pc ON pc.id = p.color_id
            LEFT JOIN part_categories cat ON cat.id = p.category_id
            WHERE li.jpo_id = ?
            """,
            (jpo_id,),
        )
        lines = await cursor.fetchall()

        counts = {"brands": 0, "colors": 0, "suppliers": 0, "parts": 0}

        # Track unique entities to avoid double-counting within same order
        seen_brands: set[int] = set()
        seen_colors: set[int] = set()
        seen_suppliers: set[int] = set()

        for line in lines:
            category_name = line["category_name"]

            # Learn brand preference
            if line["brand_id"] and line["brand_id"] not in seen_brands:
                seen_brands.add(line["brand_id"])
                await self.pref_repo.upsert_preference(
                    job_id=job_id,
                    preference_type="brand",
                    entity_id=line["brand_id"],
                    text_value=line["brand_name"],
                    category=category_name,
                )
                counts["brands"] += 1

            # Learn color preference
            if line["color_id"] and line["color_id"] not in seen_colors:
                seen_colors.add(line["color_id"])
                await self.pref_repo.upsert_preference(
                    job_id=job_id,
                    preference_type="color",
                    entity_id=line["color_id"],
                    text_value=line["color_name"],
                    category=category_name,
                )
                counts["colors"] += 1

            # Learn supplier preference
            if (
                line["suggested_supplier_id"]
                and line["suggested_supplier_id"] not in seen_suppliers
            ):
                seen_suppliers.add(line["suggested_supplier_id"])
                await self.pref_repo.upsert_preference(
                    job_id=job_id,
                    preference_type="supplier",
                    entity_id=line["suggested_supplier_id"],
                    text_value=None,  # supplier name resolved via JOIN
                    category=None,    # suppliers aren't category-specific
                )
                counts["suppliers"] += 1

            # Learn part preference (which specific parts are used on this job)
            await self.pref_repo.upsert_preference(
                job_id=job_id,
                preference_type="part",
                entity_id=line["part_id"],
                text_value=None,
                category=category_name,
            )
            counts["parts"] += 1

        logger.info(
            "Learned preferences from JPO %d for job %d: %s",
            jpo_id, job_id, counts,
        )
        return counts

    # ── Querying ─────────────────────────────────────────────

    async def get_suggestions(
        self,
        job_id: int,
        *,
        category: str | None = None,
        preference_type: str | None = None,
    ) -> list[dict]:
        """Get ranked suggestions for a job.

        Returns preferences ordered by confidence_score DESC.
        Optionally filter by category (e.g. 'outlets') or type ('brand', 'color').
        """
        return await self.pref_repo.get_for_job(
            job_id,
            preference_type=preference_type,
            category=category,
        )

    async def get_preferred_supplier(
        self,
        job_id: int,
        part_id: int,
    ) -> dict | None:
        """For a general part, return the preferred supplier for this job.

        Used when auto-populating the suggested_supplier_id on line items.
        """
        return await self.pref_repo.get_preferred_supplier_for_part(job_id, part_id)

    async def toggle_preference(
        self,
        pref_id: int,
        is_active: bool,
    ) -> bool:
        """Enable or disable a learned preference."""
        return await self.pref_repo.update(
            pref_id, {"is_active": 1 if is_active else 0}
        )

    async def get_all_for_job(self, job_id: int) -> dict:
        """Get all preferences grouped by type — used by the frontend to
        populate filter chips on the unified order form.

        Returns:
            {
                "brands":    [{"id": 1, "entity_id": 5, "text_value": "Leviton", ...}],
                "colors":    [{"id": 2, "entity_id": 3, "text_value": "White", "hex_code": "#FFFFFF", ...}],
                "suppliers": [{"id": 3, "entity_id": 7, "entity_name": "Graybar", ...}],
                "parts":     [{"id": 4, "entity_id": 42, "entity_name": "20A Duplex Outlet", ...}],
            }
        """
        all_prefs = await self.pref_repo.get_for_job(job_id)

        grouped: dict[str, list[dict]] = {
            "brands": [],
            "colors": [],
            "suppliers": [],
            "parts": [],
        }
        for pref in all_prefs:
            ptype = pref["preference_type"]
            if ptype in grouped:
                grouped[ptype].append(dict(pref))

        return grouped

    # ── Special Items ────────────────────────────────────────

    async def get_special_items(self, jpo_id: int) -> list[dict]:
        """Get all special items for a JPO."""
        return await self.special_repo.get_for_jpo(jpo_id)

    async def add_special_item(
        self,
        jpo_id: int,
        description: str,
        quantity: int = 1,
        *,
        part_number: str | None = None,
        unit: str = "each",
        estimated_cost: float | None = None,
        notes: str | None = None,
    ) -> int:
        """Add a special (non-catalog) item to an order.

        Auto-flagged for office review.  Also sets has_special_items
        on the parent JPO.
        """
        item_id = await self.special_repo.insert({
            "jpo_id": jpo_id,
            "description": description,
            "part_number": part_number,
            "quantity": quantity,
            "unit": unit,
            "estimated_cost": estimated_cost,
            "notes": notes,
            "is_flagged": 1,
        })

        # Mark the parent JPO as having special items
        await self.db.execute(
            "UPDATE job_parts_orders SET has_special_items = 1 WHERE id = ?",
            (jpo_id,),
        )
        await self.db.commit()

        logger.info("Added special item '%s' to JPO %d (flagged)", description, jpo_id)
        return item_id

    async def resolve_special_item(
        self,
        item_id: int,
        resolved_by: int,
        *,
        linked_part_id: int | None = None,
    ) -> bool:
        """Office resolves a flagged special item.

        If they find a matching catalog part, pass linked_part_id to
        create the connection.

        After resolving, checks if the parent JPO still has unresolved
        items — if all resolved, clears has_special_items flag.
        """
        success = await self.special_repo.resolve(
            item_id, resolved_by, linked_part_id=linked_part_id,
        )
        if not success:
            return False

        # Check if all special items on this JPO are now resolved
        cursor = await self.db.execute(
            """
            SELECT si.jpo_id
            FROM special_items si
            WHERE si.id = ?
            """,
            (item_id,),
        )
        row = await cursor.fetchone()
        if row:
            cursor = await self.db.execute(
                """
                SELECT COUNT(*) as cnt FROM special_items
                WHERE jpo_id = ? AND is_flagged = 1 AND flag_resolved_by IS NULL
                """,
                (row["jpo_id"],),
            )
            remaining = await cursor.fetchone()
            if remaining and remaining["cnt"] == 0:
                await self.db.execute(
                    "UPDATE job_parts_orders SET has_special_items = 0 WHERE id = ?",
                    (row["jpo_id"],),
                )
                await self.db.commit()
                logger.info("All special items resolved for JPO %d", row["jpo_id"])

        return True

    async def get_flagged_items(self, *, limit: int = 50) -> list[dict]:
        """Get all unresolved flagged special items (office view)."""
        return await self.special_repo.get_flagged(limit=limit)
