"""
Procurement service — reorder suggestions, supplier ranking, audit verification.

Provides:
  - Smart reorder point analysis (current stock - pending POs - expected returns)
  - Multi-factor supplier ranking (price, on-time, communication, quality, lead time)
  - Supplier-grouped views for efficient PO creation
  - Audit spot-check integration before ordering
  - Procurement dashboard statistics
"""

from __future__ import annotations

import logging
from typing import Any

import aiosqlite

from app.repositories.orders_repo import PriceHistoryRepo, SupplierContactRatingRepo

logger = logging.getLogger(__name__)

# Supplier ranking weights (must sum to 1.0)
WEIGHT_PRICE = 0.35
WEIGHT_ON_TIME = 0.20
WEIGHT_COMMUNICATION = 0.20
WEIGHT_QUALITY = 0.15
WEIGHT_LEAD_TIME = 0.10


class ProcurementService:
    """Procurement analysis and recommendation engine."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.price_repo = PriceHistoryRepo(db)
        self.rating_repo = SupplierContactRatingRepo(db)

    async def get_reorder_suggestions(self) -> list[dict]:
        """Get parts below reorder point, minus pending POs and expected returns.

        Returns a priority-sorted list with suggested order quantities.
        """
        cursor = await self.db.execute(
            """
            SELECT p.id AS part_id, p.code AS part_number, p.description AS part_description,
                   p.forecast_reorder_point AS reorder_point,
                   p.forecast_target_qty AS target_qty,
                   p.forecast_days_until_low AS days_until_stockout,

                   -- Current total stock across all locations
                   COALESCE((
                       SELECT SUM(sm.qty)
                       FROM stock_movements sm
                       WHERE sm.part_id = p.id
                   ), 0) AS current_stock,

                   -- Pending PO quantities (not yet received)
                   COALESCE((
                       SELECT SUM(pli.qty_ordered - pli.qty_received)
                       FROM po_line_items pli
                       JOIN purchase_orders po ON po.id = pli.po_id
                       WHERE pli.part_id = p.id
                         AND pli.status IN ('pending', 'partial', 'backordered')
                         AND po.status NOT IN ('cancelled', 'closed')
                   ), 0) AS pending_po_qty,

                   -- Expected return quantities
                   COALESCE((
                       SELECT SUM(rli.qty)
                       FROM return_line_items rli
                       JOIN returns r ON r.id = rli.return_id
                       WHERE rli.part_id = p.id
                         AND rli.disposition = 'restock'
                         AND r.status IN ('approved', 'shipped')
                   ), 0) AS expected_return_qty,

                   -- Best supplier
                   (SELECT psl.supplier_id FROM part_supplier_links psl
                    WHERE psl.part_id = p.id AND psl.is_preferred = 1
                    LIMIT 1) AS best_supplier_id,
                   (SELECT s.name FROM part_supplier_links psl
                    JOIN suppliers s ON s.id = psl.supplier_id
                    WHERE psl.part_id = p.id AND psl.is_preferred = 1
                    LIMIT 1) AS best_supplier_name,
                   (SELECT psl.supplier_cost_price FROM part_supplier_links psl
                    WHERE psl.part_id = p.id AND psl.is_preferred = 1
                    LIMIT 1) AS estimated_unit_cost

            FROM parts p
            WHERE p.is_deprecated = 0
              AND p.forecast_reorder_point > 0
            ORDER BY p.forecast_days_until_low ASC, p.forecast_reorder_point DESC
            """
        )
        rows = await cursor.fetchall()

        suggestions = []
        for row in rows:
            effective_stock = (
                row["current_stock"]
                + row["pending_po_qty"]
                + row["expected_return_qty"]
            )

            if effective_stock < row["reorder_point"]:
                suggested_qty = max(
                    row["target_qty"] - effective_stock, 1
                )
                estimated_cost = (
                    suggested_qty * row["estimated_unit_cost"]
                    if row["estimated_unit_cost"]
                    else None
                )

                suggestions.append({
                    **dict(row),
                    "suggested_order_qty": suggested_qty,
                    "estimated_cost": estimated_cost,
                })

        return suggestions

    async def get_supplier_grouped_view(self) -> list[dict]:
        """Group reorder suggestions by recommended supplier.

        Returns a list of supplier groups, each with parts to order.
        """
        suggestions = await self.get_reorder_suggestions()

        groups: dict[int, dict] = {}
        ungrouped = []

        for s in suggestions:
            sid = s.get("best_supplier_id")
            if sid:
                if sid not in groups:
                    groups[sid] = {
                        "supplier_id": sid,
                        "supplier_name": s.get("best_supplier_name", "Unknown"),
                        "parts": [],
                        "total_estimated_cost": 0,
                        "part_count": 0,
                    }
                groups[sid]["parts"].append(s)
                groups[sid]["part_count"] += 1
                if s.get("estimated_cost"):
                    groups[sid]["total_estimated_cost"] += s["estimated_cost"]
            else:
                ungrouped.append(s)

        result = sorted(
            groups.values(),
            key=lambda g: g["total_estimated_cost"],
            reverse=True,
        )

        if ungrouped:
            result.append({
                "supplier_id": None,
                "supplier_name": "No Preferred Supplier",
                "parts": ungrouped,
                "total_estimated_cost": sum(
                    u.get("estimated_cost", 0) or 0 for u in ungrouped
                ),
                "part_count": len(ungrouped),
            })

        return result

    async def rank_suppliers(self, part_id: int) -> list[dict]:
        """Rank suppliers for a specific part using composite scoring.

        Weights: Price 35%, On-time 20%, Communication 20%, Quality 15%, Lead time 10%
        """
        cursor = await self.db.execute(
            """
            SELECT psl.supplier_id, s.name AS supplier_name,
                   psl.is_preferred, psl.supplier_cost_price,
                   s.on_time_rate, s.quality_score, s.avg_lead_days,
                   s.communication_score, s.reliability_score
            FROM part_supplier_links psl
            JOIN suppliers s ON s.id = psl.supplier_id
            WHERE psl.part_id = ? AND s.is_active = 1
            """,
            (part_id,),
        )
        suppliers = await cursor.fetchall()

        if not suppliers:
            return []

        # Normalize prices: lowest price gets 1.0, highest gets 0.0
        prices = [s["supplier_cost_price"] or 999999 for s in suppliers]
        min_price = min(prices) if prices else 1
        max_price = max(prices) if prices else 1
        price_range = max_price - min_price if max_price != min_price else 1

        # Normalize lead times: shortest gets 1.0
        leads = [s["avg_lead_days"] or 30 for s in suppliers]
        min_lead = min(leads) if leads else 1
        max_lead = max(leads) if leads else 1
        lead_range = max_lead - min_lead if max_lead != min_lead else 1

        rankings = []
        for s in suppliers:
            price = s["supplier_cost_price"] or 999999
            price_score = 1.0 - ((price - min_price) / price_range) if price_range else 1.0

            lead = s["avg_lead_days"] or 30
            lead_score = 1.0 - ((lead - min_lead) / lead_range) if lead_range else 1.0

            on_time_score = s["on_time_rate"] or 0.5
            quality_score = s["quality_score"] or 0.5
            comm_score = s["communication_score"] or 0.5

            composite = (
                WEIGHT_PRICE * price_score
                + WEIGHT_ON_TIME * on_time_score
                + WEIGHT_COMMUNICATION * comm_score
                + WEIGHT_QUALITY * quality_score
                + WEIGHT_LEAD_TIME * lead_score
            )

            rankings.append({
                "supplier_id": s["supplier_id"],
                "supplier_name": s["supplier_name"],
                "composite_score": round(composite, 3),
                "price_score": round(price_score, 3),
                "on_time_score": round(on_time_score, 3),
                "communication_score": round(comm_score, 3),
                "quality_score": round(quality_score, 3),
                "lead_time_score": round(lead_score, 3),
                "avg_unit_cost": s["supplier_cost_price"],
                "avg_lead_days": s["avg_lead_days"],
                "is_preferred": bool(s["is_preferred"]),
            })

        return sorted(rankings, key=lambda r: r["composite_score"], reverse=True)

    async def verify_counts_needed(self, part_ids: list[int]) -> list[int]:
        """Create audit spot-check tasks for parts before ordering.

        Returns list of task IDs created in the warehouse queue.
        """
        # Integration with audit_service — create spot check entries
        created = []
        for part_id in part_ids:
            cursor = await self.db.execute(
                """
                INSERT INTO audit_spot_checks (
                    part_id, check_type, status, created_at
                ) VALUES (?, 'procurement_verify', 'pending', datetime('now'))
                """,
                (part_id,),
            )
            created.append(cursor.lastrowid)

        await self.db.commit()
        return created

    async def get_dashboard_stats(self) -> dict:
        """Get summary statistics for the procurement dashboard."""
        stats = {}

        # Parts needing reorder
        suggestions = await self.get_reorder_suggestions()
        stats["parts_needing_reorder"] = len(suggestions)
        stats["parts_below_critical"] = sum(
            1 for s in suggestions if (s.get("days_until_stockout") or 999) <= 3
        )

        # Pending PO stats
        cursor = await self.db.execute(
            """
            SELECT COUNT(*) as cnt, COALESCE(SUM(total_cost), 0) as total_value
            FROM purchase_orders
            WHERE status IN ('submitted', 'acknowledged', 'partially_received')
            """
        )
        row = await cursor.fetchone()
        stats["pending_po_count"] = row["cnt"] if row else 0
        stats["pending_po_value"] = row["total_value"] if row else 0

        # Average lead time
        cursor = await self.db.execute(
            """
            SELECT AVG(avg_lead_days) as avg_lead
            FROM suppliers WHERE is_active = 1 AND avg_lead_days > 0
            """
        )
        row = await cursor.fetchone()
        stats["avg_lead_time_days"] = round(row["avg_lead"] or 0, 1) if row else 0

        # Overdue deliveries
        cursor = await self.db.execute(
            """
            SELECT COUNT(*) as cnt FROM purchase_orders
            WHERE status IN ('submitted', 'acknowledged')
              AND expected_delivery < date('now')
            """
        )
        row = await cursor.fetchone()
        stats["overdue_deliveries"] = row["cnt"] if row else 0

        return stats
