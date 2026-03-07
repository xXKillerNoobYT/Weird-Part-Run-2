"""
Spending service — dashboard analytics, job cost rollups, price variance, budget alerts.

Aggregates data from purchase_orders, po_line_items, job_parts, and cost_layers
to provide spending breakdowns, trend analysis, and budget monitoring.

Queries use the PO submission date as the spend date, since that's when the
company commits to the expenditure.
"""

from __future__ import annotations

import logging
from typing import Any

import aiosqlite

logger = logging.getLogger(__name__)


class SpendingService:
    """Analytics: spending dashboard, job costs, variance, budget alerts."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    # ═══════════════════════════════════════════════════════════════
    # Spending Dashboard
    # ═══════════════════════════════════════════════════════════════

    async def get_spending_summary(
        self, date_from: str, date_to: str
    ) -> dict:
        """Top-level spending KPIs for a date range."""
        cursor = await self.db.execute(
            """
            SELECT COALESCE(SUM(po.total_cost), 0) AS total_spend,
                   COUNT(DISTINCT po.id) AS order_count,
                   COUNT(DISTINCT po.supplier_id) AS active_suppliers
            FROM purchase_orders po
            WHERE po.status NOT IN ('draft', 'cancelled')
              AND po.created_at >= ? AND po.created_at < ?
            """,
            (date_from, date_to),
        )
        row = await cursor.fetchone()

        total_spend = row["total_spend"] or 0
        order_count = row["order_count"] or 0
        avg_order = round(total_spend / order_count, 2) if order_count > 0 else 0

        return {
            "total_spend": round(total_spend, 2),
            "order_count": order_count,
            "avg_order_size": avg_order,
            "active_suppliers": row["active_suppliers"] or 0,
        }

    async def get_spending_by_supplier(
        self, date_from: str, date_to: str
    ) -> list[dict]:
        """Spending per supplier, sorted by total spend descending."""
        cursor = await self.db.execute(
            """
            SELECT s.id AS supplier_id,
                   s.name AS supplier_name,
                   COALESCE(SUM(po.total_cost), 0) AS total_spend,
                   COUNT(DISTINCT po.id) AS order_count
            FROM purchase_orders po
            JOIN suppliers s ON s.id = po.supplier_id
            WHERE po.status NOT IN ('draft', 'cancelled')
              AND po.created_at >= ? AND po.created_at < ?
            GROUP BY s.id, s.name
            ORDER BY total_spend DESC
            """,
            (date_from, date_to),
        )
        rows = [dict(r) for r in await cursor.fetchall()]

        # Calculate percentage of total
        grand_total = sum(r["total_spend"] for r in rows) or 1
        for r in rows:
            r["pct_of_total"] = round(r["total_spend"] / grand_total * 100, 1)

        return rows

    async def get_spending_by_category(
        self, date_from: str, date_to: str
    ) -> list[dict]:
        """Spending per part category, sorted by total spend descending."""
        cursor = await self.db.execute(
            """
            SELECT COALESCE(cat.id, 0) AS category_id,
                   COALESCE(cat.name, 'Uncategorized') AS category_name,
                   COALESCE(SUM(pli.unit_cost * pli.qty_ordered), 0) AS total_spend,
                   COUNT(DISTINCT pli.part_id) AS item_count
            FROM po_line_items pli
            JOIN purchase_orders po ON po.id = pli.po_id
            JOIN parts p ON p.id = pli.part_id
            LEFT JOIN part_categories cat ON cat.id = p.category_id
            WHERE po.status NOT IN ('draft', 'cancelled')
              AND po.created_at >= ? AND po.created_at < ?
            GROUP BY cat.id, cat.name
            ORDER BY total_spend DESC
            """,
            (date_from, date_to),
        )
        return [dict(r) for r in await cursor.fetchall()]

    async def get_spending_by_job(
        self, date_from: str, date_to: str
    ) -> list[dict]:
        """Spending per job (via JPO → PO linkage)."""
        cursor = await self.db.execute(
            """
            SELECT j.id AS job_id,
                   j.job_name,
                   COALESCE(SUM(pli.unit_cost * pli.qty_ordered), 0) AS total_spend,
                   j.budget_limit
            FROM po_line_items pli
            JOIN jpo_line_items jli ON jli.id = pli.jpo_line_id
            JOIN job_parts_orders jpo ON jpo.id = jli.jpo_id
            JOIN jobs j ON j.id = jpo.job_id
            JOIN purchase_orders po ON po.id = pli.po_id
            WHERE po.status NOT IN ('draft', 'cancelled')
              AND po.created_at >= ? AND po.created_at < ?
              AND jpo.job_id IS NOT NULL
            GROUP BY j.id, j.job_name
            ORDER BY total_spend DESC
            """,
            (date_from, date_to),
        )
        rows = [dict(r) for r in await cursor.fetchall()]

        for r in rows:
            if r["budget_limit"] and r["budget_limit"] > 0:
                r["budget_pct"] = round(r["total_spend"] / r["budget_limit"] * 100, 1)
            else:
                r["budget_pct"] = None

        return rows

    async def get_spending_trend(
        self, date_from: str, date_to: str, group_by: str = "month"
    ) -> list[dict]:
        """Spending trend over time, grouped by month or week."""
        if group_by == "week":
            date_fmt = "strftime('%Y-W%W', po.created_at)"
        else:
            date_fmt = "strftime('%Y-%m', po.created_at)"

        cursor = await self.db.execute(
            f"""
            SELECT {date_fmt} AS period_label,
                   COALESCE(SUM(po.total_cost), 0) AS total_spend,
                   COUNT(DISTINCT po.id) AS order_count
            FROM purchase_orders po
            WHERE po.status NOT IN ('draft', 'cancelled')
              AND po.created_at >= ? AND po.created_at < ?
            GROUP BY period_label
            ORDER BY period_label ASC
            """,
            (date_from, date_to),
        )
        return [dict(r) for r in await cursor.fetchall()]

    # ═══════════════════════════════════════════════════════════════
    # Job Cost Rollup
    # ═══════════════════════════════════════════════════════════════

    async def get_job_cost_rollup(self, job_id: int) -> dict:
        """Full cost rollup for a job: parts cost + labor cost + budget status."""
        # Parts cost: from PO line items linked via JPOs
        cursor = await self.db.execute(
            """
            SELECT COALESCE(SUM(pli.unit_cost * pli.qty_ordered), 0) AS parts_from_pos
            FROM po_line_items pli
            JOIN jpo_line_items jli ON jli.id = pli.jpo_line_id
            JOIN job_parts_orders jpo ON jpo.id = jli.jpo_id
            WHERE jpo.job_id = ?
            """,
            (job_id,),
        )
        row = await cursor.fetchone()
        parts_cost = round(row["parts_from_pos"], 2) if row else 0

        # Also include direct job_parts consumption (consumed parts snapshotted cost)
        cursor = await self.db.execute(
            """
            SELECT COALESCE(SUM(jp.qty_consumed * COALESCE(jp.unit_cost_at_consume, 0)), 0) AS consumed_cost
            FROM job_parts jp
            WHERE jp.job_id = ?
            """,
            (job_id,),
        )
        row = await cursor.fetchone()
        consumed_cost = round(row["consumed_cost"], 2) if row else 0

        # Use the larger of PO-based cost and consumed cost as the parts total
        # (PO cost is committed spend, consumed cost is actual usage)
        total_parts = max(parts_cost, consumed_cost)

        # Labor cost estimate: total hours × billing rate
        cursor = await self.db.execute(
            """
            SELECT j.job_name, j.billing_rate, j.budget_limit, j.budget_alert_percent,
                   COALESCE(SUM(
                       (julianday(COALESCE(le.clock_out, datetime('now'))) -
                        julianday(le.clock_in)) * 24
                   ), 0) AS total_hours
            FROM jobs j
            LEFT JOIN labor_entries le ON le.job_id = j.id
            WHERE j.id = ?
            GROUP BY j.id
            """,
            (job_id,),
        )
        job_row = await cursor.fetchone()
        if not job_row:
            raise ValueError(f"Job {job_id} not found")

        total_hours = round(job_row["total_hours"] or 0, 2)
        billing_rate = job_row["billing_rate"] or 0
        total_labor = round(total_hours * billing_rate, 2)
        combined = round(total_parts + total_labor, 2)

        budget_limit = job_row["budget_limit"]
        budget_remaining = None
        budget_pct = None
        if budget_limit and budget_limit > 0:
            budget_remaining = round(budget_limit - combined, 2)
            budget_pct = round(combined / budget_limit * 100, 1)

        return {
            "job_id": job_id,
            "job_name": job_row["job_name"],
            "total_parts_cost": total_parts,
            "total_labor_cost": total_labor,
            "total_labor_hours": total_hours,
            "billing_rate": billing_rate,
            "combined_total": combined,
            "budget_limit": budget_limit,
            "budget_remaining": budget_remaining,
            "budget_pct": budget_pct,
            "budget_alert_percent": job_row["budget_alert_percent"] or 80,
        }

    async def get_job_budget_status(self, job_id: int) -> dict:
        """Quick budget status check for a job (lighter than full rollup)."""
        rollup = await self.get_job_cost_rollup(job_id)
        alert_level = None
        if rollup["budget_pct"] is not None:
            if rollup["budget_pct"] >= 95:
                alert_level = "danger"
            elif rollup["budget_pct"] >= rollup["budget_alert_percent"]:
                alert_level = "warning"

        return {
            "job_id": job_id,
            "budget_limit": rollup["budget_limit"],
            "current_spend": rollup["combined_total"],
            "budget_pct": rollup["budget_pct"],
            "alert_level": alert_level,
        }

    async def check_budget_alerts(self) -> list[dict]:
        """Check all jobs with budgets for overspend alerts.

        Returns a list of jobs that are at or above their alert threshold.
        """
        # Get all jobs with budget limits set
        cursor = await self.db.execute(
            """
            SELECT id, job_name, budget_limit, budget_alert_percent
            FROM jobs
            WHERE budget_limit IS NOT NULL AND budget_limit > 0
              AND status IN ('active', 'in_progress')
            """
        )
        jobs = await cursor.fetchall()

        alerts = []
        for job in jobs:
            try:
                status = await self.get_job_budget_status(job["id"])
                if status["alert_level"]:
                    alerts.append({
                        "job_id": job["id"],
                        "job_name": job["job_name"],
                        "budget_limit": job["budget_limit"],
                        "current_spend": status["current_spend"],
                        "pct_used": status["budget_pct"],
                        "alert_level": status["alert_level"],
                    })
            except Exception as exc:
                logger.warning("Budget alert check failed for job %d: %s", job["id"], exc)

        return alerts

    # ═══════════════════════════════════════════════════════════════
    # Price Variance Report
    # ═══════════════════════════════════════════════════════════════

    async def get_price_variance_report(
        self, date_from: str, date_to: str
    ) -> list[dict]:
        """Find PO lines where received price differs from quoted price.

        Only includes lines that have been received with an actual cost
        that differs from the original unit cost.
        """
        cursor = await self.db.execute(
            """
            SELECT pli.part_id,
                   p.description AS part_name,
                   s.name AS supplier_name,
                   po.po_number,
                   pli.unit_cost AS quoted_price,
                   pli.received_unit_cost AS actual_price
            FROM po_line_items pli
            JOIN purchase_orders po ON po.id = pli.po_id
            JOIN suppliers s ON s.id = po.supplier_id
            JOIN parts p ON p.id = pli.part_id
            WHERE pli.received_unit_cost IS NOT NULL
              AND pli.unit_cost IS NOT NULL
              AND ABS(pli.received_unit_cost - pli.unit_cost) > 0.01
              AND po.created_at >= ? AND po.created_at < ?
            ORDER BY ABS(pli.received_unit_cost - pli.unit_cost) DESC
            """,
            (date_from, date_to),
        )
        rows = await cursor.fetchall()

        results = []
        for r in rows:
            quoted = r["quoted_price"] or 0
            actual = r["actual_price"] or 0
            variance_amt = round(actual - quoted, 2)
            variance_pct = round(abs(variance_amt) / quoted * 100, 1) if quoted > 0 else 0

            if variance_pct >= 15:
                level = "danger"
            elif variance_pct >= 5:
                level = "warning"
            else:
                level = "ok"

            results.append({
                "part_id": r["part_id"],
                "part_name": r["part_name"],
                "supplier_name": r["supplier_name"],
                "po_number": r["po_number"],
                "quoted_price": quoted,
                "actual_price": actual,
                "variance_amount": variance_amt,
                "variance_pct": variance_pct,
                "variance_level": level,
            })

        return results

    # ═══════════════════════════════════════════════════════════════
    # Daily Report (Live Data)
    # ═══════════════════════════════════════════════════════════════

    async def get_daily_report(self) -> dict:
        """Aggregate live data for the daily report tab.

        This is NOT the locked daily snapshot from report_service —
        it's real-time data for the dashboard.
        """
        # Pending actions
        jpos_pending = await self._count(
            "SELECT COUNT(*) FROM job_parts_orders WHERE status = 'pending_approval'"
        )
        pos_draft = await self._count(
            "SELECT COUNT(*) FROM purchase_orders WHERE status = 'draft'"
        )
        returns_pending = await self._count(
            "SELECT COUNT(*) FROM returns WHERE status = 'approved'"
        )
        overdue = await self._count(
            """
            SELECT COUNT(*) FROM purchase_orders
            WHERE status IN ('submitted', 'acknowledged', 'partially_received')
              AND expected_delivery IS NOT NULL
              AND expected_delivery < date('now')
            """
        )

        # Expected deliveries this week
        cursor = await self.db.execute(
            """
            SELECT po.id AS po_id, po.po_number,
                   s.name AS supplier_name,
                   po.expected_delivery,
                   COUNT(pli.id) AS line_count,
                   CASE WHEN po.expected_delivery < date('now') THEN 1 ELSE 0 END AS is_overdue
            FROM purchase_orders po
            JOIN suppliers s ON s.id = po.supplier_id
            LEFT JOIN po_line_items pli ON pli.po_id = po.id
            WHERE po.status IN ('submitted', 'acknowledged', 'partially_received')
              AND po.expected_delivery IS NOT NULL
              AND po.expected_delivery BETWEEN date('now', '-1 day') AND date('now', '+7 days')
            GROUP BY po.id
            ORDER BY po.expected_delivery ASC
            """
        )
        deliveries_raw = [dict(r) for r in await cursor.fetchall()]

        expected = [d for d in deliveries_raw if not d["is_overdue"]]
        overdue_list = [d for d in deliveries_raw if d["is_overdue"]]

        # Also get overdue items not in this week's window
        cursor = await self.db.execute(
            """
            SELECT po.id AS po_id, po.po_number,
                   s.name AS supplier_name,
                   po.expected_delivery,
                   COUNT(pli.id) AS line_count,
                   1 AS is_overdue
            FROM purchase_orders po
            JOIN suppliers s ON s.id = po.supplier_id
            LEFT JOIN po_line_items pli ON pli.po_id = po.id
            WHERE po.status IN ('submitted', 'acknowledged', 'partially_received')
              AND po.expected_delivery IS NOT NULL
              AND po.expected_delivery < date('now', '-1 day')
            GROUP BY po.id
            ORDER BY po.expected_delivery ASC
            """
        )
        older_overdue = [dict(r) for r in await cursor.fetchall()]
        overdue_list.extend(older_overdue)

        # Today's activity
        orders_today = await self._count(
            "SELECT COUNT(*) FROM job_parts_orders WHERE date(created_at) = date('now')"
        )
        received_today = await self._count(
            """
            SELECT COALESCE(SUM(rsi.received_qty), 0) FROM receiving_session_items rsi
            JOIN receiving_sessions rs ON rs.id = rsi.session_id
            WHERE rs.status = 'completed' AND date(rs.completed_at) = date('now')
            """
        )
        returns_today = await self._count(
            "SELECT COUNT(*) FROM returns WHERE date(created_at) = date('now')"
        )

        # Budget alerts
        alerts = await self._safe_budget_alerts()

        return {
            "pending_actions": {
                "jpos_awaiting_approval": jpos_pending,
                "pos_to_submit": pos_draft,
                "returns_to_sort": returns_pending,
                "overdue_deliveries": overdue,
            },
            "expected_deliveries": expected,
            "overdue_items": overdue_list,
            "todays_activity": {
                "orders_created": orders_today,
                "items_received": received_today,
                "returns_processed": returns_today,
            },
            "budget_alerts": alerts,
        }

    async def _count(self, sql: str) -> int:
        """Run a scalar count/sum query with error handling."""
        try:
            cursor = await self.db.execute(sql)
            row = await cursor.fetchone()
            return row[0] if row else 0
        except Exception as exc:
            logger.debug("Spending count query failed: %s — %s", sql[:80], exc)
            return 0

    async def _safe_budget_alerts(self) -> list[dict]:
        """Budget alerts with graceful error handling."""
        try:
            return await self.check_budget_alerts()
        except Exception as exc:
            logger.warning("Budget alerts failed: %s", exc)
            return []
