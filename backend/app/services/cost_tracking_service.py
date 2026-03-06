"""
Cost tracking service — FIFO consumption, LIFO returns, weighted average cost.

Core concepts:
  - **Cost layer**: Each PO receipt creates a layer (part_id, qty, unit_cost).
  - **FIFO consumption**: Oldest layers are consumed first when parts go to a job.
  - **LIFO returns**: Newest layers are restored first when parts come back.
  - **Weighted average**: sum(remaining_qty × unit_cost) / sum(remaining_qty)

Integration points (Phase 7D hooks):
  1. receiving_service.receive_po_items() → add_cost_layer()
  2. job_service.consume_part()           → consume_fifo()
  3. returns_service.process_sorted_return() → return_lifo() for restocks

Margin management:
  - Each part can have a custom_margin_percent override.
  - If NULL, falls back to company_cost_settings['default_margin_percent'].
  - "Enforce default" clears all custom margins.
"""

from __future__ import annotations

import logging
from datetime import date, datetime
from typing import Any

import aiosqlite

logger = logging.getLogger(__name__)


class CostTrackingService:
    """FIFO/LIFO cost layers, weighted average pricing, margin management."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    # ═══════════════════════════════════════════════════════════════
    # Cost Layer Operations
    # ═══════════════════════════════════════════════════════════════

    async def add_cost_layer(
        self,
        part_id: int,
        qty: int,
        unit_cost: float,
        po_line_id: int | None = None,
        purchase_date: str | None = None,
    ) -> dict:
        """Create a new cost layer when receiving items from a PO.

        Called from: receiving_service.receive_po_items()
        After adding, recalculates the weighted average cost for this part.
        """
        if qty <= 0:
            raise ValueError("Quantity must be positive")
        if unit_cost < 0:
            raise ValueError("Unit cost cannot be negative")

        pdate = purchase_date or date.today().isoformat()

        cursor = await self.db.execute(
            """
            INSERT INTO cost_layers
                (part_id, purchase_date, po_line_id, original_qty, remaining_qty, unit_cost)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (part_id, pdate, po_line_id, qty, qty, unit_cost),
        )
        layer_id = cursor.lastrowid

        # Recalculate weighted average
        await self._recalculate_weighted_average(part_id)

        logger.info(
            "Cost layer #%d added: part=%d qty=%d cost=%.2f",
            layer_id, part_id, qty, unit_cost,
        )
        return {"id": layer_id, "part_id": part_id, "qty": qty, "unit_cost": unit_cost}

    async def consume_fifo(self, part_id: int, qty: int) -> float:
        """Consume inventory using FIFO (oldest layers first).

        Called from: job_service.consume_part()
        Returns the total cost consumed (for job cost snapshots).

        If there aren't enough cost layers to cover the full quantity
        (e.g. parts added before Phase 7D), we consume what we can and
        use the weighted average for the remainder.
        """
        if qty <= 0:
            raise ValueError("Quantity must be positive")

        # Get all layers with remaining stock, ordered oldest first (FIFO)
        cursor = await self.db.execute(
            """
            SELECT id, remaining_qty, unit_cost
            FROM cost_layers
            WHERE part_id = ? AND remaining_qty > 0
            ORDER BY purchase_date ASC, id ASC
            """,
            (part_id,),
        )
        layers = await cursor.fetchall()

        remaining_to_consume = qty
        total_cost = 0.0

        for layer in layers:
            if remaining_to_consume <= 0:
                break

            consume_from_layer = min(remaining_to_consume, layer["remaining_qty"])
            new_remaining = layer["remaining_qty"] - consume_from_layer

            await self.db.execute(
                "UPDATE cost_layers SET remaining_qty = ? WHERE id = ?",
                (new_remaining, layer["id"]),
            )

            total_cost += consume_from_layer * layer["unit_cost"]
            remaining_to_consume -= consume_from_layer

        # If we ran out of layers (legacy data), use weighted average for remainder
        if remaining_to_consume > 0:
            avg_cost = await self._get_weighted_average(part_id)
            total_cost += remaining_to_consume * avg_cost
            logger.warning(
                "FIFO underflow: part=%d, %d units without cost layers (used avg=%.2f)",
                part_id, remaining_to_consume, avg_cost,
            )

        # Recalculate weighted average after consumption
        await self._recalculate_weighted_average(part_id)

        logger.info(
            "FIFO consume: part=%d qty=%d total_cost=%.2f",
            part_id, qty, total_cost,
        )
        return total_cost

    async def return_lifo(
        self,
        part_id: int,
        qty: int,
        unit_cost: float | None = None,
    ) -> dict:
        """Return inventory using LIFO (add back to newest layer or create new).

        Called from: returns_service.process_sorted_return() for 'restock' dispositions.

        If unit_cost is provided, creates a new layer at that cost.
        Otherwise, finds the most recent layer and increases its remaining_qty.
        """
        if qty <= 0:
            raise ValueError("Quantity must be positive")

        if unit_cost is not None:
            # Create a fresh layer at the specified cost
            cursor = await self.db.execute(
                """
                INSERT INTO cost_layers
                    (part_id, purchase_date, original_qty, remaining_qty, unit_cost)
                VALUES (?, ?, ?, ?, ?)
                """,
                (part_id, date.today().isoformat(), qty, qty, unit_cost),
            )
            layer_id = cursor.lastrowid
        else:
            # Find newest layer to add back into (LIFO)
            cursor = await self.db.execute(
                """
                SELECT id, remaining_qty, original_qty, unit_cost
                FROM cost_layers
                WHERE part_id = ?
                ORDER BY purchase_date DESC, id DESC
                LIMIT 1
                """,
                (part_id,),
            )
            newest = await cursor.fetchone()

            if newest:
                # Don't exceed original quantity; if we would, create new layer
                new_remaining = newest["remaining_qty"] + qty
                if new_remaining <= newest["original_qty"]:
                    await self.db.execute(
                        "UPDATE cost_layers SET remaining_qty = ? WHERE id = ?",
                        (new_remaining, newest["id"]),
                    )
                    layer_id = newest["id"]
                    unit_cost = newest["unit_cost"]
                else:
                    # Partially fill the existing layer, create new for the rest
                    can_add = newest["original_qty"] - newest["remaining_qty"]
                    if can_add > 0:
                        await self.db.execute(
                            "UPDATE cost_layers SET remaining_qty = original_qty WHERE id = ?",
                            (newest["id"],),
                        )

                    overflow = qty - can_add
                    if overflow > 0:
                        cursor2 = await self.db.execute(
                            """
                            INSERT INTO cost_layers
                                (part_id, purchase_date, original_qty, remaining_qty, unit_cost)
                            VALUES (?, ?, ?, ?, ?)
                            """,
                            (part_id, date.today().isoformat(), overflow, overflow, newest["unit_cost"]),
                        )
                        layer_id = cursor2.lastrowid
                    else:
                        layer_id = newest["id"]
                    unit_cost = newest["unit_cost"]
            else:
                # No layers at all — use existing weighted_avg_cost or company cost
                fallback_cost = await self._get_fallback_cost(part_id)
                cursor2 = await self.db.execute(
                    """
                    INSERT INTO cost_layers
                        (part_id, purchase_date, original_qty, remaining_qty, unit_cost)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (part_id, date.today().isoformat(), qty, qty, fallback_cost),
                )
                layer_id = cursor2.lastrowid
                unit_cost = fallback_cost

        # Recalculate weighted average
        await self._recalculate_weighted_average(part_id)

        logger.info(
            "LIFO return: part=%d qty=%d cost=%.2f layer=%d",
            part_id, qty, unit_cost or 0, layer_id,
        )
        return {"layer_id": layer_id, "part_id": part_id, "qty": qty, "unit_cost": unit_cost}

    # ═══════════════════════════════════════════════════════════════
    # Weighted Average Cost
    # ═══════════════════════════════════════════════════════════════

    async def _recalculate_weighted_average(self, part_id: int) -> float:
        """Recompute weighted average from all active layers and persist.

        Formula: sum(remaining_qty * unit_cost) / sum(remaining_qty)
        If no layers, keeps existing weighted_avg_cost (or 0).
        """
        avg = await self._get_weighted_average(part_id)

        await self.db.execute(
            """
            UPDATE parts
            SET weighted_avg_cost = ?,
                cost_last_updated = datetime('now')
            WHERE id = ?
            """,
            (avg, part_id),
        )
        return avg

    async def _get_weighted_average(self, part_id: int) -> float:
        """Compute weighted average without persisting."""
        cursor = await self.db.execute(
            """
            SELECT SUM(remaining_qty * unit_cost) AS total_value,
                   SUM(remaining_qty) AS total_qty
            FROM cost_layers
            WHERE part_id = ? AND remaining_qty > 0
            """,
            (part_id,),
        )
        row = await cursor.fetchone()
        if row and row["total_qty"] and row["total_qty"] > 0:
            return round(row["total_value"] / row["total_qty"], 4)

        # Fallback: use existing weighted_avg_cost from parts table
        cursor2 = await self.db.execute(
            "SELECT weighted_avg_cost FROM parts WHERE id = ?",
            (part_id,),
        )
        part = await cursor2.fetchone()
        return part["weighted_avg_cost"] if part and part["weighted_avg_cost"] else 0.0

    async def _get_fallback_cost(self, part_id: int) -> float:
        """Get fallback cost for a part when no layers exist.

        Priority: weighted_avg_cost → company_cost_price → 0
        """
        cursor = await self.db.execute(
            "SELECT weighted_avg_cost, company_cost_price FROM parts WHERE id = ?",
            (part_id,),
        )
        row = await cursor.fetchone()
        if not row:
            return 0.0
        if row["weighted_avg_cost"] and row["weighted_avg_cost"] > 0:
            return row["weighted_avg_cost"]
        if row["company_cost_price"] and row["company_cost_price"] > 0:
            return row["company_cost_price"]
        return 0.0

    # ═══════════════════════════════════════════════════════════════
    # Cost Layer Queries
    # ═══════════════════════════════════════════════════════════════

    async def get_cost_layers(self, part_id: int) -> list[dict]:
        """Get all cost layers with remaining qty > 0 for a part (audit view)."""
        cursor = await self.db.execute(
            """
            SELECT cl.*,
                   po.po_number
            FROM cost_layers cl
            LEFT JOIN po_line_items pli ON pli.id = cl.po_line_id
            LEFT JOIN purchase_orders po ON po.id = pli.po_id
            WHERE cl.part_id = ? AND cl.remaining_qty > 0
            ORDER BY cl.purchase_date ASC, cl.id ASC
            """,
            (part_id,),
        )
        return [dict(r) for r in await cursor.fetchall()]

    async def get_cost_history(
        self, part_id: int, days: int = 90
    ) -> list[dict]:
        """Get cost changes over time for sparkline charts.

        Returns one data point per distinct purchase_date within the window.
        Each point shows the weighted average cost and total remaining qty
        as of that date (based on layers created up to that point).
        """
        cursor = await self.db.execute(
            """
            SELECT purchase_date AS date,
                   ROUND(
                       SUM(remaining_qty * unit_cost) * 1.0 /
                       NULLIF(SUM(remaining_qty), 0),
                   2) AS weighted_avg_cost,
                   SUM(remaining_qty) AS total_qty
            FROM cost_layers
            WHERE part_id = ?
              AND purchase_date >= date('now', ? || ' days')
            GROUP BY purchase_date
            ORDER BY purchase_date ASC
            """,
            (part_id, f"-{days}"),
        )
        return [dict(r) for r in await cursor.fetchall()]

    # ═══════════════════════════════════════════════════════════════
    # Margin Management
    # ═══════════════════════════════════════════════════════════════

    async def get_margin(self, part_id: int) -> dict:
        """Get effective margin for a part (custom or company default)."""
        cursor = await self.db.execute(
            "SELECT custom_margin_percent, weighted_avg_cost FROM parts WHERE id = ?",
            (part_id,),
        )
        part = await cursor.fetchone()
        if not part:
            raise ValueError(f"Part {part_id} not found")

        default_margin = await self._get_default_margin()
        custom = part["custom_margin_percent"]
        effective = custom if custom is not None else default_margin
        avg_cost = part["weighted_avg_cost"] or 0

        sell_price = round(avg_cost * (1 + effective / 100), 2) if avg_cost > 0 else 0

        return {
            "part_id": part_id,
            "custom_margin_percent": custom,
            "default_margin_percent": default_margin,
            "effective_margin_percent": effective,
            "weighted_avg_cost": avg_cost,
            "calculated_sell_price": sell_price,
        }

    async def set_custom_margin(self, part_id: int, margin_percent: float) -> None:
        """Set a custom margin override on a part."""
        await self.db.execute(
            "UPDATE parts SET custom_margin_percent = ? WHERE id = ?",
            (margin_percent, part_id),
        )
        await self.db.commit()

    async def clear_custom_margin(self, part_id: int) -> None:
        """Remove custom margin — revert to company default."""
        await self.db.execute(
            "UPDATE parts SET custom_margin_percent = NULL WHERE id = ?",
            (part_id,),
        )
        await self.db.commit()

    async def enforce_default_margin(self) -> int:
        """Reset ALL parts to company default margin.

        Returns the number of parts that had custom margins cleared.
        """
        cursor = await self.db.execute(
            "SELECT COUNT(*) AS cnt FROM parts WHERE custom_margin_percent IS NOT NULL"
        )
        row = await cursor.fetchone()
        count = row["cnt"] if row else 0

        await self.db.execute(
            "UPDATE parts SET custom_margin_percent = NULL WHERE custom_margin_percent IS NOT NULL"
        )
        await self.db.commit()

        logger.info("Enforced default margin: cleared %d custom margins", count)
        return count

    # ═══════════════════════════════════════════════════════════════
    # Company Settings
    # ═══════════════════════════════════════════════════════════════

    async def get_company_settings(self) -> list[dict]:
        """Get all company cost settings."""
        cursor = await self.db.execute(
            """
            SELECT ccs.*, u.display_name AS updated_by_name
            FROM company_cost_settings ccs
            LEFT JOIN users u ON u.id = ccs.updated_by
            ORDER BY ccs.setting_key
            """
        )
        return [dict(r) for r in await cursor.fetchall()]

    async def update_company_setting(
        self, key: str, value: str, user_id: int
    ) -> dict | None:
        """Update a company cost setting."""
        cursor = await self.db.execute(
            """
            UPDATE company_cost_settings
            SET setting_value = ?, updated_by = ?, updated_at = datetime('now')
            WHERE setting_key = ?
            """,
            (value, user_id, key),
        )
        if cursor.rowcount == 0:
            return None

        await self.db.commit()

        cursor2 = await self.db.execute(
            "SELECT * FROM company_cost_settings WHERE setting_key = ?",
            (key,),
        )
        return dict(await cursor2.fetchone())

    async def _get_default_margin(self) -> float:
        """Read the company default margin from settings."""
        cursor = await self.db.execute(
            "SELECT setting_value FROM company_cost_settings WHERE setting_key = 'default_margin_percent'"
        )
        row = await cursor.fetchone()
        try:
            return float(row["setting_value"]) if row else 25.0
        except (ValueError, TypeError):
            return 25.0
