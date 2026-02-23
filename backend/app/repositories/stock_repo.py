"""
Stock repository — data access for stock levels and movement history.

Separated from parts_repo because stock operations are the critical path
for the Guided Movement Wizard (Phase 3) and need their own atomic
transaction patterns.
"""

from __future__ import annotations

from typing import Any

import aiosqlite

from app.repositories.base import BaseRepo


class StockRepo(BaseRepo):
    """Data access for stock levels across all locations."""

    TABLE = "stock"

    async def get_stock_for_part(self, part_id: int) -> list[dict]:
        """Get all stock entries for a part across every location.

        Includes supplier name for chain tracking visibility.
        """
        sql = """
            SELECT s.*, sup.name AS supplier_name
            FROM stock s
            LEFT JOIN suppliers sup ON sup.id = s.supplier_id
            WHERE s.part_id = ?
            ORDER BY s.location_type, s.location_id
        """
        cursor = await self.db.execute(sql, (part_id,))
        return await cursor.fetchall()

    async def get_stock_summary(self, part_id: int) -> dict:
        """Get aggregated stock totals for a part by location type."""
        sql = """
            SELECT
                COALESCE(SUM(qty), 0) AS total,
                COALESCE(SUM(CASE WHEN location_type = 'warehouse' THEN qty ELSE 0 END), 0) AS warehouse,
                COALESCE(SUM(CASE WHEN location_type = 'pulled' THEN qty ELSE 0 END), 0) AS pulled,
                COALESCE(SUM(CASE WHEN location_type = 'truck' THEN qty ELSE 0 END), 0) AS truck,
                COALESCE(SUM(CASE WHEN location_type = 'job' THEN qty ELSE 0 END), 0) AS job
            FROM stock
            WHERE part_id = ?
        """
        cursor = await self.db.execute(sql, (part_id,))
        row = await cursor.fetchone()
        return dict(row) if row else {"total": 0, "warehouse": 0, "pulled": 0, "truck": 0, "job": 0}

    async def get_stock_at_location(
        self,
        location_type: str,
        location_id: int,
        *,
        search: str | None = None,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict]:
        """Get all stock at a specific location (e.g., warehouse 1, truck 5).

        Joins part info for display.
        """
        where_clauses = [
            "s.location_type = ?",
            "s.location_id = ?",
            "s.qty > 0",
        ]
        params: list[Any] = [location_type, location_id]

        if search:
            where_clauses.append("(p.code LIKE ? OR p.name LIKE ?)")
            params.extend([f"%{search}%"] * 2)

        where_sql = " AND ".join(where_clauses)

        sql = f"""
            SELECT s.*,
                   p.code AS part_code,
                   p.name AS part_name,
                   p.unit_of_measure,
                   p.company_cost_price,
                   p.company_sell_price,
                   sup.name AS supplier_name
            FROM stock s
            JOIN parts p ON p.id = s.part_id
            LEFT JOIN suppliers sup ON sup.id = s.supplier_id
            WHERE {where_sql}
            ORDER BY p.name ASC
            LIMIT ? OFFSET ?
        """
        params.extend([limit, offset])

        cursor = await self.db.execute(sql, params)
        return await cursor.fetchall()

    async def add_stock(
        self,
        part_id: int,
        location_type: str,
        location_id: int,
        qty: int,
        supplier_id: int | None = None,
    ) -> int:
        """Add stock to a location. Uses UPSERT to increment existing rows.

        This is a simple add — for atomic moves between locations,
        use the movement_service instead.
        """
        # Try to update existing row first
        cursor = await self.db.execute(
            """UPDATE stock
               SET qty = qty + ?, updated_at = datetime('now')
               WHERE part_id = ? AND location_type = ? AND location_id = ?
                 AND (supplier_id = ? OR (supplier_id IS NULL AND ? IS NULL))""",
            (qty, part_id, location_type, location_id, supplier_id, supplier_id),
        )

        if cursor.rowcount > 0:
            await self.db.commit()
            # Return the existing row's ID
            id_cursor = await self.db.execute(
                """SELECT id FROM stock
                   WHERE part_id = ? AND location_type = ? AND location_id = ?
                     AND (supplier_id = ? OR (supplier_id IS NULL AND ? IS NULL))""",
                (part_id, location_type, location_id, supplier_id, supplier_id),
            )
            row = await id_cursor.fetchone()
            return row["id"] if row else 0

        # Insert new row
        cursor = await self.db.execute(
            """INSERT INTO stock (part_id, location_type, location_id, qty, supplier_id, updated_at)
               VALUES (?, ?, ?, ?, ?, datetime('now'))""",
            (part_id, location_type, location_id, qty, supplier_id),
        )
        await self.db.commit()
        return cursor.lastrowid  # type: ignore[return-value]


class MovementRepo(BaseRepo):
    """Data access for stock movement history."""

    TABLE = "stock_movements"

    async def get_movements(
        self,
        *,
        part_id: int | None = None,
        movement_type: str | None = None,
        location_type: str | None = None,
        location_id: int | None = None,
        job_id: int | None = None,
        performed_by: int | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """Query movement history with optional filters.

        Joins part, supplier, and user names for display.
        """
        where_clauses: list[str] = []
        params: list[Any] = []

        if part_id is not None:
            where_clauses.append("m.part_id = ?")
            params.append(part_id)

        if movement_type:
            where_clauses.append("m.movement_type = ?")
            params.append(movement_type)

        if location_type and location_id is not None:
            where_clauses.append(
                "((m.from_location_type = ? AND m.from_location_id = ?) "
                "OR (m.to_location_type = ? AND m.to_location_id = ?))"
            )
            params.extend([location_type, location_id, location_type, location_id])

        if job_id is not None:
            where_clauses.append("m.job_id = ?")
            params.append(job_id)

        if performed_by is not None:
            where_clauses.append("m.performed_by = ?")
            params.append(performed_by)

        where_sql = f"WHERE {' AND '.join(where_clauses)}" if where_clauses else ""

        sql = f"""
            SELECT m.*,
                   p.code AS part_code,
                   p.name AS part_name,
                   sup.name AS supplier_name,
                   u.display_name AS performer_name
            FROM stock_movements m
            JOIN parts p ON p.id = m.part_id
            LEFT JOIN suppliers sup ON sup.id = m.supplier_id
            LEFT JOIN users u ON u.id = m.performed_by
            {where_sql}
            ORDER BY m.created_at DESC
            LIMIT ? OFFSET ?
        """
        params.extend([limit, offset])

        cursor = await self.db.execute(sql, params)
        return await cursor.fetchall()

    async def count_movements(
        self,
        *,
        part_id: int | None = None,
        movement_type: str | None = None,
    ) -> int:
        """Count movements matching filters."""
        where_clauses: list[str] = []
        params: list[Any] = []

        if part_id is not None:
            where_clauses.append("part_id = ?")
            params.append(part_id)

        if movement_type:
            where_clauses.append("movement_type = ?")
            params.append(movement_type)

        where_sql = f"WHERE {' AND '.join(where_clauses)}" if where_clauses else ""
        cursor = await self.db.execute(
            f"SELECT COUNT(*) AS cnt FROM stock_movements {where_sql}", params
        )
        row = await cursor.fetchone()
        return row["cnt"] if row else 0

    async def log_movement(self, data: dict) -> int:
        """Insert a movement log entry."""
        columns = ", ".join(data.keys())
        placeholders = ", ".join(["?"] * len(data))
        cursor = await self.db.execute(
            f"INSERT INTO stock_movements ({columns}) VALUES ({placeholders})",
            tuple(data.values()),
        )
        await self.db.commit()
        return cursor.lastrowid  # type: ignore[return-value]
