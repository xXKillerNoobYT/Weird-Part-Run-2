"""
Warehouse Service — dashboard KPIs, activity feed, pending tasks, inventory grid.

Aggregates data from stock, movements, audits, and staging for the
warehouse dashboard and inventory views.
"""

from __future__ import annotations

import logging
from typing import Any

import aiosqlite

from app.models.warehouse import (
    ActivitySummary,
    DashboardData,
    DashboardKPIs,
    PendingTask,
    StagingGroup,
    StagingItem,
    WarehouseInventoryItem,
)

logger = logging.getLogger(__name__)


class WarehouseService:
    """High-level warehouse queries for dashboard and inventory pages."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    # ── Dashboard ─────────────────────────────────────────────────

    async def get_dashboard(self, show_dollars: bool = False) -> DashboardData:
        """Combined dashboard payload in a single call."""
        kpis = await self.get_kpis(show_dollars=show_dollars)
        activity = await self.get_recent_activity(limit=10)
        tasks = await self.get_pending_tasks()
        return DashboardData(kpis=kpis, recent_activity=activity, pending_tasks=tasks)

    async def get_kpis(self, show_dollars: bool = False) -> DashboardKPIs:
        """Calculate dashboard KPI numbers."""
        # Stock health %: parts that have warehouse qty within min-max range
        cursor = await self.db.execute(
            """SELECT
                   COUNT(DISTINCT p.id) AS total_parts,
                   COUNT(DISTINCT CASE
                       WHEN COALESCE(s.wh_qty, 0) >= p.min_stock_level
                        AND (p.max_stock_level = 0 OR COALESCE(s.wh_qty, 0) <= p.max_stock_level)
                       THEN p.id
                   END) AS healthy_parts
               FROM parts p
               LEFT JOIN (
                   SELECT part_id, SUM(qty) AS wh_qty
                   FROM stock WHERE location_type = 'warehouse'
                   GROUP BY part_id
               ) s ON s.part_id = p.id
               WHERE p.is_deprecated = 0
                 AND p.target_stock_level > 0"""
        )
        row = await cursor.fetchone()
        total_parts = row["total_parts"] or 0
        healthy_parts = row["healthy_parts"] or 0
        health_pct = round((healthy_parts / total_parts * 100) if total_parts > 0 else 100, 1)

        # Total units in warehouse
        cursor = await self.db.execute(
            "SELECT COALESCE(SUM(qty), 0) AS total FROM stock WHERE location_type = 'warehouse'"
        )
        row = await cursor.fetchone()
        total_units = row["total"] if row else 0

        # Warehouse value (only if allowed)
        warehouse_value = None
        if show_dollars:
            cursor = await self.db.execute(
                """SELECT COALESCE(SUM(s.qty * p.company_cost_price), 0) AS val
                   FROM stock s JOIN parts p ON p.id = s.part_id
                   WHERE s.location_type = 'warehouse'"""
            )
            row = await cursor.fetchone()
            warehouse_value = round(row["val"], 2) if row else 0.0

        # Shortfall count (parts below min, excluding winding-down)
        cursor = await self.db.execute(
            """SELECT COUNT(DISTINCT p.id) AS cnt
               FROM parts p
               LEFT JOIN (
                   SELECT part_id, SUM(qty) AS wh_qty
                   FROM stock WHERE location_type = 'warehouse'
                   GROUP BY part_id
               ) s ON s.part_id = p.id
               WHERE p.is_deprecated = 0
                 AND p.target_stock_level > 0
                 AND p.min_stock_level > 0
                 AND COALESCE(s.wh_qty, 0) < p.min_stock_level"""
        )
        row = await cursor.fetchone()
        shortfall = row["cnt"] if row else 0

        # Pending tasks count
        tasks = await self.get_pending_tasks()

        return DashboardKPIs(
            stock_health_pct=health_pct,
            total_units=total_units,
            warehouse_value=warehouse_value,
            shortfall_count=shortfall,
            pending_task_count=len(tasks),
        )

    async def get_recent_activity(self, limit: int = 10) -> list[ActivitySummary]:
        """Get recent movements as one-line summaries."""
        cursor = await self.db.execute(
            """SELECT m.id, m.movement_type, m.qty,
                      m.from_location_type, m.to_location_type,
                      m.created_at,
                      p.name AS part_name,
                      u.display_name AS performer_name
               FROM stock_movements m
               JOIN parts p ON p.id = m.part_id
               LEFT JOIN users u ON u.id = m.performed_by
               ORDER BY m.created_at DESC
               LIMIT ?""",
            (limit,),
        )
        rows = await cursor.fetchall()

        results = []
        for row in rows:
            # Build one-line summary
            action = _movement_verb(row["movement_type"])
            user = row["performer_name"] or "Someone"
            summary = f"{user} {action} {row['qty']}× {row['part_name']}"

            if row["from_location_type"] and row["to_location_type"]:
                summary += f" ({row['from_location_type']} → {row['to_location_type']})"

            results.append(ActivitySummary(
                id=row["id"],
                summary=summary,
                movement_type=row["movement_type"],
                performer_name=row["performer_name"],
                created_at=row["created_at"],
            ))

        return results

    async def get_pending_tasks(self) -> list[PendingTask]:
        """Get all pending warehouse tasks."""
        tasks: list[PendingTask] = []

        # 1. Staged items awaiting pickup (grouped by destination)
        cursor = await self.db.execute(
            """SELECT st.destination_type, st.destination_id, st.destination_label,
                      COUNT(*) AS item_count,
                      SUM(s.qty) AS total_qty,
                      MIN(st.created_at) AS oldest,
                      ROUND((julianday('now') - julianday(MIN(st.created_at))) * 24, 1) AS hours_old
               FROM staging_tags st
               JOIN stock s ON s.id = st.stock_id AND s.qty > 0
               GROUP BY st.destination_type, st.destination_id"""
        )
        for row in await cursor.fetchall():
            hours = row["hours_old"] or 0
            severity = "critical" if hours > 48 else "warning" if hours > 24 else "normal"
            label = row["destination_label"] or f"{row['destination_type']} #{row['destination_id']}"

            tasks.append(PendingTask(
                task_type="staged_item",
                title=f"Staged: {row['total_qty']} units for {label}",
                subtitle=f"{row['item_count']} items, {_format_hours(hours)}",
                severity=severity,
                destination_type=row["destination_type"],
                destination_id=row["destination_id"],
            ))

        # 2. Active/paused audits
        cursor = await self.db.execute(
            """SELECT a.id, a.audit_type, a.status,
                      a.total_items, a.matched_items, a.discrepancy_count,
                      pc.name AS category_name
               FROM audits a
               LEFT JOIN part_categories pc ON pc.id = a.category_id
               WHERE a.status IN ('in_progress', 'paused')
               ORDER BY a.created_at DESC"""
        )
        for row in await cursor.fetchall():
            counted = (row["matched_items"] or 0) + (row["discrepancy_count"] or 0)
            total = row["total_items"] or 0
            pct = round(counted / total * 100) if total > 0 else 0

            type_label = row["audit_type"].replace("_", " ").title()
            if row["category_name"]:
                type_label += f": {row['category_name']}"

            tasks.append(PendingTask(
                task_type="audit",
                title=f"{type_label} — {pct}%",
                subtitle=f"{counted}/{total} items counted" if total > 0 else "Starting...",
                severity="normal",
                audit_id=row["id"],
            ))

        # 3. Spot-check requests (pending low-stock verification)
        cursor = await self.db.execute(
            """SELECT a.id AS audit_id, ai.part_id, p.name AS part_name,
                      ai.expected_qty
               FROM audits a
               JOIN audit_items ai ON ai.audit_id = a.id
               JOIN parts p ON p.id = ai.part_id
               WHERE a.audit_type = 'spot_check'
                 AND a.status = 'in_progress'
                 AND ai.result = 'pending'
               ORDER BY a.created_at DESC"""
        )
        for row in await cursor.fetchall():
            tasks.append(PendingTask(
                task_type="spot_check",
                title=f"Verify Count: {row['part_name']}",
                subtitle=f"System shows {row['expected_qty']} units",
                severity="warning",
                audit_id=row["audit_id"],
                part_id=row["part_id"],
            ))

        return tasks

    # ── Inventory Grid ────────────────────────────────────────────

    async def get_warehouse_inventory(
        self,
        *,
        search: str | None = None,
        category_id: int | None = None,
        brand_id: int | None = None,
        part_id: int | None = None,
        stock_status: str | None = None,
        sort_by: str = "name",
        sort_dir: str = "asc",
        page: int = 1,
        page_size: int = 50,
        show_dollars: bool = False,
    ) -> tuple[list[WarehouseInventoryItem], int]:
        """Paginated warehouse inventory with health calculations.

        Only shows "warehouse-relevant" parts: those with actual stock
        or a non-zero target level. Parts with 0 stock AND 0 target
        (wound-out / never stocked) are excluded.
        """
        where_clauses = [
            "p.is_deprecated = 0",
            # Only warehouse-relevant: has stock or has a target
            "(COALESCE(wh.qty, 0) > 0 OR p.target_stock_level > 0)",
        ]
        params: list[Any] = []

        if part_id:
            where_clauses.append("p.id = ?")
            params.append(part_id)
        if search:
            where_clauses.append(
                "(p.name LIKE ? OR p.code LIKE ? OR p.shelf_location LIKE ? OR p.bin_location LIKE ?)"
            )
            params.extend([f"%{search}%"] * 4)
        if category_id:
            where_clauses.append("p.category_id = ?")
            params.append(category_id)
        if brand_id:
            where_clauses.append("p.brand_id = ?")
            params.append(brand_id)

        # Stock status filter — use WHERE on the subquery expression
        # (HAVING requires GROUP BY; these are non-aggregate filters on a computed column)
        if stock_status == "low_stock":
            where_clauses.append("COALESCE(wh.qty, 0) < p.min_stock_level AND p.target_stock_level > 0")
        elif stock_status == "overstock":
            where_clauses.append("p.max_stock_level > 0 AND COALESCE(wh.qty, 0) > p.max_stock_level")
        elif stock_status == "winding_down":
            # Has stock we don't want: target is 0 but warehouse qty > 0
            where_clauses.append("p.target_stock_level = 0 AND COALESCE(wh.qty, 0) > 0")
        elif stock_status == "zero":
            where_clauses.append("COALESCE(wh.qty, 0) = 0 AND p.target_stock_level > 0")
        elif stock_status == "in_range":
            where_clauses.append(
                "COALESCE(wh.qty, 0) >= p.min_stock_level "
                "AND (p.max_stock_level = 0 OR COALESCE(wh.qty, 0) <= p.max_stock_level) "
                "AND p.target_stock_level > 0"
            )

        where_sql = " AND ".join(where_clauses)

        # Sort mapping
        sort_map = {
            "name": "p.name",
            "code": "p.code",
            "category": "pc.name",
            "brand": "b.name",
            "qty": "wh_qty",
            "shelf": "p.shelf_location",
        }
        order_col = sort_map.get(sort_by, "p.name")
        order_dir = "DESC" if sort_dir.lower() == "desc" else "ASC"

        # Count query
        count_sql = f"""
            SELECT COUNT(*) AS cnt
            FROM parts p
            LEFT JOIN (
                SELECT part_id, SUM(qty) AS qty
                FROM stock WHERE location_type = 'warehouse'
                GROUP BY part_id
            ) wh ON wh.part_id = p.id
            WHERE {where_sql}
        """
        cursor = await self.db.execute(count_sql, params)
        row = await cursor.fetchone()
        total = row["cnt"] if row else 0

        # Data query
        offset = (page - 1) * page_size
        data_sql = f"""
            SELECT
                p.id AS part_id,
                p.code AS part_code,
                p.name AS part_name,
                p.category_id,
                pc.name AS category_name,
                p.brand_id,
                b.name AS brand_name,
                p.unit_of_measure,
                p.shelf_location,
                p.bin_location,
                COALESCE(wh.qty, 0) AS warehouse_qty,
                COALESCE(pulled.qty, 0) AS pulled_qty,
                COALESCE(truck.qty, 0) AS truck_qty,
                COALESCE(wh.qty, 0) + COALESCE(pulled.qty, 0) + COALESCE(truck.qty, 0) AS total_qty,
                p.min_stock_level,
                p.target_stock_level,
                p.max_stock_level,
                p.company_cost_price,
                p.forecast_days_until_low,
                p.is_qr_tagged,
                COALESCE(wh.qty, 0) AS wh_qty
            FROM parts p
            LEFT JOIN part_categories pc ON pc.id = p.category_id
            LEFT JOIN brands b ON b.id = p.brand_id
            LEFT JOIN (
                SELECT part_id, SUM(qty) AS qty FROM stock
                WHERE location_type = 'warehouse' GROUP BY part_id
            ) wh ON wh.part_id = p.id
            LEFT JOIN (
                SELECT part_id, SUM(qty) AS qty FROM stock
                WHERE location_type = 'pulled' GROUP BY part_id
            ) pulled ON pulled.part_id = p.id
            LEFT JOIN (
                SELECT part_id, SUM(qty) AS qty FROM stock
                WHERE location_type = 'truck' GROUP BY part_id
            ) truck ON truck.part_id = p.id
            WHERE {where_sql}
            ORDER BY {order_col} {order_dir}
            LIMIT ? OFFSET ?
        """
        cursor = await self.db.execute(data_sql, (*params, page_size, offset))
        rows = await cursor.fetchall()

        items = []
        for row in rows:
            wh = row["warehouse_qty"]
            min_s = row["min_stock_level"] or 0
            max_s = row["max_stock_level"] or 0
            target = row["target_stock_level"] or 0

            # Determine stock status
            if target == 0:
                status = "winding_down"
            elif wh == 0:
                status = "zero"
            elif min_s > 0 and wh < min_s:
                status = "low_stock"
            elif max_s > 0 and wh > max_s:
                status = "overstock"
            else:
                status = "in_range"

            # Health percentage (for progress bar)
            if max_s > 0:
                health_pct = min(100, round(wh / max_s * 100, 1))
            elif target > 0:
                health_pct = min(100, round(wh / target * 100, 1))
            else:
                health_pct = 100.0

            items.append(WarehouseInventoryItem(
                part_id=row["part_id"],
                part_code=row["part_code"],
                part_name=row["part_name"],
                category_id=row["category_id"],
                category_name=row["category_name"],
                brand_id=row["brand_id"],
                brand_name=row["brand_name"],
                unit_of_measure=row["unit_of_measure"],
                shelf_location=row["shelf_location"],
                bin_location=row["bin_location"],
                warehouse_qty=wh,
                pulled_qty=row["pulled_qty"],
                truck_qty=row["truck_qty"],
                total_qty=row["total_qty"],
                min_stock_level=min_s,
                target_stock_level=target,
                max_stock_level=max_s,
                stock_status=status,
                health_pct=health_pct,
                unit_cost=row["company_cost_price"] if show_dollars else None,
                total_value=round(wh * (row["company_cost_price"] or 0), 2) if show_dollars else None,
                forecast_days_until_low=row["forecast_days_until_low"],
                is_qr_tagged=bool(row["is_qr_tagged"]),
            ))

        return items, total

    # ── Staging ───────────────────────────────────────────────────

    async def get_staging_groups(self) -> list[StagingGroup]:
        """Get all pulled/staged items grouped by destination."""
        cursor = await self.db.execute(
            """SELECT s.id AS stock_id, s.part_id, s.qty,
                      p.name AS part_name, p.code AS part_code,
                      sup.name AS supplier_name,
                      st.destination_type, st.destination_id, st.destination_label,
                      st.created_at AS staged_at,
                      u.display_name AS tagged_by_name,
                      ROUND((julianday('now') - julianday(st.created_at)) * 24, 1) AS hours_staged
               FROM stock s
               JOIN parts p ON p.id = s.part_id
               LEFT JOIN suppliers sup ON sup.id = s.supplier_id
               LEFT JOIN staging_tags st ON st.stock_id = s.id
               LEFT JOIN users u ON u.id = st.tagged_by
               WHERE s.location_type = 'pulled' AND s.qty > 0
               ORDER BY st.destination_type, st.destination_id, p.name"""
        )
        rows = await cursor.fetchall()

        # Group by destination
        groups: dict[str, StagingGroup] = {}
        for row in rows:
            dest_type = row["destination_type"]
            dest_id = row["destination_id"]

            if dest_type and dest_id:
                key = f"{dest_type}:{dest_id}"
                label = row["destination_label"] or f"{dest_type.title()} #{dest_id}"
            else:
                key = "untagged"
                label = "Untagged"

            if key not in groups:
                groups[key] = StagingGroup(
                    destination_type=dest_type,
                    destination_id=dest_id,
                    destination_label=label,
                )

            hours = row["hours_staged"] or 0
            aging = "critical" if hours > 48 else "warning" if hours > 24 else "normal"

            groups[key].items.append(StagingItem(
                stock_id=row["stock_id"],
                part_id=row["part_id"],
                part_name=row["part_name"],
                part_code=row["part_code"],
                qty=row["qty"],
                supplier_name=row["supplier_name"],
                destination_type=dest_type,
                destination_id=dest_id,
                destination_label=row["destination_label"],
                tagged_by_name=row["tagged_by_name"],
                staged_at=row["staged_at"],
                hours_staged=hours,
                aging_status=aging,
            ))
            groups[key].total_qty += row["qty"]
            if hours > groups[key].oldest_hours:
                groups[key].oldest_hours = hours
                groups[key].aging_status = aging

        return list(groups.values())

    # ── Parts Search (Context-Aware) ──────────────────────────────

    async def search_parts_for_wizard(
        self,
        query: str,
        location_type: str | None = None,
        location_id: int | None = None,
        limit: int = 20,
    ) -> list[dict]:
        """Search parts for the wizard, optionally scoped to a location.

        If location_type/id given, only returns parts WITH stock there.
        Otherwise returns all catalog parts.
        """
        if location_type and location_id is not None:
            # Context-aware: only parts with stock at source
            cursor = await self.db.execute(
                """SELECT p.id, p.code, p.name, p.image_url,
                          p.unit_of_measure, p.company_cost_price,
                          COALESCE(SUM(s.qty), 0) AS available_qty,
                          GROUP_CONCAT(DISTINCT sup.name) AS supplier_names
                   FROM parts p
                   JOIN stock s ON s.part_id = p.id
                       AND s.location_type = ? AND s.location_id = ? AND s.qty > 0
                   LEFT JOIN suppliers sup ON sup.id = s.supplier_id
                   WHERE (p.name LIKE ? OR p.code LIKE ?)
                     AND p.is_deprecated = 0
                   GROUP BY p.id
                   ORDER BY p.name
                   LIMIT ?""",
                (location_type, location_id, f"%{query}%", f"%{query}%", limit),
            )
        else:
            # All catalog parts
            cursor = await self.db.execute(
                """SELECT p.id, p.code, p.name, p.image_url,
                          p.unit_of_measure, p.company_cost_price,
                          COALESCE(wh.qty, 0) AS available_qty,
                          NULL AS supplier_names
                   FROM parts p
                   LEFT JOIN (
                       SELECT part_id, SUM(qty) AS qty FROM stock
                       WHERE location_type = 'warehouse' GROUP BY part_id
                   ) wh ON wh.part_id = p.id
                   WHERE (p.name LIKE ? OR p.code LIKE ?)
                     AND p.is_deprecated = 0
                   ORDER BY p.name
                   LIMIT ?""",
                (f"%{query}%", f"%{query}%", limit),
            )

        return await cursor.fetchall()


# ── Helpers ───────────────────────────────────────────────────────

def _movement_verb(movement_type: str) -> str:
    """Convert movement type to past-tense verb for activity feed."""
    return {
        "transfer": "moved",
        "consume": "consumed",
        "return": "returned",
        "receive": "received",
        "adjust": "adjusted",
        "write_off": "wrote off",
    }.get(movement_type, "moved")


def _format_hours(hours: float) -> str:
    """Format hours as a human-readable time string."""
    if hours < 1:
        return "just now"
    elif hours < 24:
        return f"{int(hours)}h ago"
    else:
        days = int(hours / 24)
        return f"{days}d ago"
