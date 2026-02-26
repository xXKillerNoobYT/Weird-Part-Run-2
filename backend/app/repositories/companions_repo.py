"""
Companion Rules, Suggestions, and Co-Occurrence repositories.

Three repos in one file — they share the same domain (companion system):
- CompanionRuleRepo     — CRUD for rules with sources/targets
- CompanionSuggestionRepo — pending/history/decide/stats
- CoOccurrenceRepo      — refresh from movements, query pairs
"""

from __future__ import annotations

from typing import Any

import aiosqlite

from app.repositories.base import BaseRepo


class CompanionRuleRepo(BaseRepo):
    """Data access for companion rules + their sources/targets.

    Rules have child tables (companion_rule_sources, companion_rule_targets)
    that get fully replaced on update — no partial patching of children.
    """

    TABLE = "companion_rules"

    async def get_rule_with_children(self, rule_id: int) -> dict | None:
        """Fetch a rule with its resolved sources and targets."""
        rule = await self.get_by_id(rule_id)
        if not rule:
            return None

        rule = dict(rule)
        rule["sources"] = await self._get_sources(rule_id)
        rule["targets"] = await self._get_targets(rule_id)
        return rule

    async def get_all_rules_with_children(
        self,
        *,
        active_only: bool = False,
    ) -> list[dict]:
        """List all rules with their resolved sources and targets."""
        where = "is_active = 1" if active_only else None
        rules = await self.get_all(where=where, order_by="name ASC", limit=500)

        result = []
        for rule in rules:
            r = dict(rule)
            r["sources"] = await self._get_sources(r["id"])
            r["targets"] = await self._get_targets(r["id"])
            result.append(r)
        return result

    async def create_rule(
        self,
        data: dict[str, Any],
        sources: list[dict],
        targets: list[dict],
    ) -> int:
        """Create a rule with its sources and targets atomically."""
        rule_id = await self.insert(data)
        await self._replace_sources(rule_id, sources)
        await self._replace_targets(rule_id, targets)
        return rule_id

    async def update_rule(
        self,
        rule_id: int,
        data: dict[str, Any],
        sources: list[dict] | None = None,
        targets: list[dict] | None = None,
    ) -> bool:
        """Update a rule and optionally replace its sources/targets."""
        if data:
            await self.update(rule_id, data)
        if sources is not None:
            await self._replace_sources(rule_id, sources)
        if targets is not None:
            await self._replace_targets(rule_id, targets)
        return True

    async def get_rules_for_categories(
        self, category_ids: list[int]
    ) -> list[dict]:
        """Find all active rules that have ANY of the given categories as sources.

        This is the core lookup for the suggestion engine — given a list of
        category IDs in the user's input, which rules fire?
        """
        if not category_ids:
            return []

        placeholders = ", ".join(["?"] * len(category_ids))
        sql = f"""
            SELECT DISTINCT cr.*
            FROM companion_rules cr
            INNER JOIN companion_rule_sources crs ON crs.rule_id = cr.id
            WHERE cr.is_active = 1
              AND crs.category_id IN ({placeholders})
            ORDER BY cr.name
        """
        cursor = await self.db.execute(sql, tuple(category_ids))
        rules = await cursor.fetchall()

        # Hydrate each rule with its full sources and targets
        result = []
        for rule in rules:
            r = dict(rule)
            r["sources"] = await self._get_sources(r["id"])
            r["targets"] = await self._get_targets(r["id"])
            result.append(r)
        return result

    # ── Private helpers ────────────────────────────────────────────

    async def _get_sources(self, rule_id: int) -> list[dict]:
        """Get resolved sources for a rule (with category/style names)."""
        sql = """
            SELECT crs.id, crs.category_id, pc.name AS category_name,
                   crs.style_id, ps.name AS style_name
            FROM companion_rule_sources crs
            JOIN part_categories pc ON pc.id = crs.category_id
            LEFT JOIN part_styles ps ON ps.id = crs.style_id
            WHERE crs.rule_id = ?
            ORDER BY pc.name
        """
        cursor = await self.db.execute(sql, (rule_id,))
        return [dict(row) for row in await cursor.fetchall()]

    async def _get_targets(self, rule_id: int) -> list[dict]:
        """Get resolved targets for a rule (with category/style names)."""
        sql = """
            SELECT crt.id, crt.category_id, pc.name AS category_name,
                   crt.style_id, ps.name AS style_name
            FROM companion_rule_targets crt
            JOIN part_categories pc ON pc.id = crt.category_id
            LEFT JOIN part_styles ps ON ps.id = crt.style_id
            WHERE crt.rule_id = ?
            ORDER BY pc.name
        """
        cursor = await self.db.execute(sql, (rule_id,))
        return [dict(row) for row in await cursor.fetchall()]

    async def _replace_sources(
        self, rule_id: int, sources: list[dict]
    ) -> None:
        """Delete existing sources and insert new ones."""
        await self.db.execute(
            "DELETE FROM companion_rule_sources WHERE rule_id = ?",
            (rule_id,),
        )
        for src in sources:
            await self.db.execute(
                """INSERT INTO companion_rule_sources
                   (rule_id, category_id, style_id) VALUES (?, ?, ?)""",
                (rule_id, src["category_id"], src.get("style_id")),
            )
        await self.db.commit()

    async def _replace_targets(
        self, rule_id: int, targets: list[dict]
    ) -> None:
        """Delete existing targets and insert new ones."""
        await self.db.execute(
            "DELETE FROM companion_rule_targets WHERE rule_id = ?",
            (rule_id,),
        )
        for tgt in targets:
            await self.db.execute(
                """INSERT INTO companion_rule_targets
                   (rule_id, category_id, style_id) VALUES (?, ?, ?)""",
                (rule_id, tgt["category_id"], tgt.get("style_id")),
            )
        await self.db.commit()


class CompanionSuggestionRepo(BaseRepo):
    """Data access for companion suggestions (pending/approved/discarded).

    Suggestions are created by the service layer's engine, then users
    approve or discard them from the suggestion board.
    """

    TABLE = "companion_suggestions"

    async def create_suggestion(
        self,
        data: dict[str, Any],
        sources: list[dict],
    ) -> int:
        """Create a suggestion with its source context."""
        suggestion_id = await self.insert(data)
        for src in sources:
            await self.db.execute(
                """INSERT INTO companion_suggestion_sources
                   (suggestion_id, category_id, category_name,
                    style_id, style_name, qty)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (
                    suggestion_id,
                    src["category_id"],
                    src.get("category_name"),
                    src.get("style_id"),
                    src.get("style_name"),
                    src["qty"],
                ),
            )
        await self.db.commit()
        return suggestion_id

    async def get_suggestion_with_sources(
        self, suggestion_id: int
    ) -> dict | None:
        """Fetch a suggestion with its trigger sources."""
        suggestion = await self.get_by_id(suggestion_id)
        if not suggestion:
            return None

        result = dict(suggestion)
        cursor = await self.db.execute(
            """SELECT * FROM companion_suggestion_sources
               WHERE suggestion_id = ? ORDER BY id""",
            (suggestion_id,),
        )
        result["sources"] = [dict(row) for row in await cursor.fetchall()]
        return result

    async def list_suggestions(
        self,
        *,
        status: str | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """List suggestions filtered by status, newest first."""
        where_clauses: list[str] = []
        params: list[Any] = []

        if status:
            where_clauses.append("cs.status = ?")
            params.append(status)

        where_sql = " AND ".join(where_clauses) if where_clauses else "1=1"

        sql = f"""
            SELECT cs.*
            FROM companion_suggestions cs
            WHERE {where_sql}
            ORDER BY cs.created_at DESC
            LIMIT ? OFFSET ?
        """
        params.extend([limit, offset])
        cursor = await self.db.execute(sql, tuple(params))
        suggestions = await cursor.fetchall()

        # Hydrate each with its sources
        result = []
        for s in suggestions:
            r = dict(s)
            src_cursor = await self.db.execute(
                """SELECT * FROM companion_suggestion_sources
                   WHERE suggestion_id = ? ORDER BY id""",
                (r["id"],),
            )
            r["sources"] = [dict(row) for row in await src_cursor.fetchall()]
            result.append(r)
        return result

    async def count_by_status(self, status: str) -> int:
        """Count suggestions with a given status."""
        return await self.count(where="status = ?", params=(status,))

    async def decide(
        self,
        suggestion_id: int,
        action: str,
        decided_by: int,
        approved_qty: int | None = None,
        notes: str | None = None,
    ) -> bool:
        """Mark a suggestion as approved or discarded."""
        data: dict[str, Any] = {
            "status": action,
            "decided_by": decided_by,
            "decided_at": "datetime('now')",
            "notes": notes,
        }
        if approved_qty is not None:
            data["approved_qty"] = approved_qty

        # Use raw SQL for the datetime('now') function
        set_parts = []
        values: list[Any] = []
        for k, v in data.items():
            if v == "datetime('now')":
                set_parts.append(f"{k} = datetime('now')")
            else:
                set_parts.append(f"{k} = ?")
                values.append(v)

        set_clause = ", ".join(set_parts)
        values.append(suggestion_id)

        cursor = await self.db.execute(
            f"UPDATE companion_suggestions SET {set_clause} WHERE id = ?",
            tuple(values),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def record_feedback(self, data: dict[str, Any]) -> int:
        """Write a feedback record for the learning loop."""
        cols = ", ".join(data.keys())
        placeholders = ", ".join(["?"] * len(data))
        cursor = await self.db.execute(
            f"INSERT INTO companion_feedback ({cols}) VALUES ({placeholders})",
            tuple(data.values()),
        )
        await self.db.commit()
        return cursor.lastrowid  # type: ignore[return-value]

    async def get_stats(self) -> dict:
        """Aggregate counts for KPI cards."""
        sql = """
            SELECT
                COALESCE(SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END), 0)
                    AS pending_suggestions,
                COALESCE(SUM(CASE WHEN status = 'approved' THEN 1 ELSE 0 END), 0)
                    AS approved_count,
                COALESCE(SUM(CASE WHEN status = 'discarded' THEN 1 ELSE 0 END), 0)
                    AS discarded_count
            FROM companion_suggestions
        """
        cursor = await self.db.execute(sql)
        row = await cursor.fetchone()
        return dict(row) if row else {
            "pending_suggestions": 0,
            "approved_count": 0,
            "discarded_count": 0,
        }


class CoOccurrenceRepo(BaseRepo):
    """Data access for learned co-occurrence pairs.

    Pairs are computed by analyzing stock_movements where
    movement_type='consume' and job_id IS NOT NULL — i.e., which categories
    appear together on the same jobs.
    """

    TABLE = "co_occurrence_pairs"

    async def get_top_pairs(self, limit: int = 50) -> list[dict]:
        """Get highest-confidence co-occurrence pairs with category names."""
        sql = """
            SELECT cop.*,
                   ca.name AS category_a_name,
                   cb.name AS category_b_name
            FROM co_occurrence_pairs cop
            JOIN part_categories ca ON ca.id = cop.category_a_id
            JOIN part_categories cb ON cb.id = cop.category_b_id
            WHERE cop.confidence > 0
            ORDER BY cop.confidence DESC
            LIMIT ?
        """
        cursor = await self.db.execute(sql, (limit,))
        return [dict(row) for row in await cursor.fetchall()]

    async def get_pairs_for_category(
        self, category_id: int, min_confidence: float = 0.1
    ) -> list[dict]:
        """Get co-occurrence pairs involving a specific category."""
        sql = """
            SELECT cop.*,
                   ca.name AS category_a_name,
                   cb.name AS category_b_name
            FROM co_occurrence_pairs cop
            JOIN part_categories ca ON ca.id = cop.category_a_id
            JOIN part_categories cb ON cb.id = cop.category_b_id
            WHERE (cop.category_a_id = ? OR cop.category_b_id = ?)
              AND cop.confidence >= ?
            ORDER BY cop.confidence DESC
        """
        cursor = await self.db.execute(
            sql, (category_id, category_id, min_confidence)
        )
        return [dict(row) for row in await cursor.fetchall()]

    async def refresh_from_movements(self) -> int:
        """Recompute all co-occurrence pairs from stock_movements.

        Algorithm:
        1. Find all (part_id, job_id) pairs from consume movements
        2. Map parts → categories
        3. For each job, find all category pairs that co-occur
        4. Aggregate counts, compute confidence

        Returns the number of pairs upserted.
        """
        # Step 1: Get category pairs that co-occur on the same job
        sql = """
            WITH job_categories AS (
                -- For each job, get the distinct categories consumed
                SELECT DISTINCT sm.job_id, p.category_id
                FROM stock_movements sm
                JOIN parts p ON p.id = sm.part_id
                WHERE sm.movement_type = 'consume'
                  AND sm.job_id IS NOT NULL
                  AND p.category_id IS NOT NULL
            ),
            category_pairs AS (
                -- Cross-join within each job to get all category pairs
                SELECT
                    CASE WHEN a.category_id < b.category_id
                         THEN a.category_id ELSE b.category_id END AS cat_a,
                    CASE WHEN a.category_id < b.category_id
                         THEN b.category_id ELSE a.category_id END AS cat_b,
                    a.job_id
                FROM job_categories a
                JOIN job_categories b
                  ON a.job_id = b.job_id AND a.category_id < b.category_id
            ),
            pair_stats AS (
                SELECT
                    cat_a,
                    cat_b,
                    COUNT(DISTINCT job_id) AS co_count
                FROM category_pairs
                GROUP BY cat_a, cat_b
            ),
            category_totals AS (
                SELECT category_id, COUNT(DISTINCT job_id) AS total_jobs
                FROM job_categories
                GROUP BY category_id
            )
            SELECT
                ps.cat_a,
                ps.cat_b,
                ps.co_count,
                COALESCE(ta.total_jobs, 0) AS total_a,
                COALESCE(tb.total_jobs, 0) AS total_b
            FROM pair_stats ps
            LEFT JOIN category_totals ta ON ta.category_id = ps.cat_a
            LEFT JOIN category_totals tb ON tb.category_id = ps.cat_b
        """
        cursor = await self.db.execute(sql)
        pairs = await cursor.fetchall()

        # Step 2: Clear and repopulate
        await self.db.execute("DELETE FROM co_occurrence_pairs")

        count = 0
        for pair in pairs:
            p = dict(pair)
            # Confidence = co-occurrence / min(total_a, total_b)
            min_total = min(p["total_a"], p["total_b"]) or 1
            confidence = p["co_count"] / min_total
            avg_ratio = p["total_a"] / (p["total_b"] or 1)

            await self.db.execute(
                """INSERT INTO co_occurrence_pairs
                   (category_a_id, category_b_id, co_occurrence_count,
                    total_jobs_a, total_jobs_b, avg_ratio_a_to_b,
                    confidence, last_computed)
                   VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))""",
                (
                    p["cat_a"], p["cat_b"], p["co_count"],
                    p["total_a"], p["total_b"], avg_ratio, confidence,
                ),
            )
            count += 1

        await self.db.commit()
        return count

    async def count_pairs(self) -> int:
        """Count total co-occurrence pairs."""
        return await self.count()
