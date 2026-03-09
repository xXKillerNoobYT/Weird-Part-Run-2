"""
Repository for vehicle fuel logs.

Handles CRUD and summary queries for fuel purchase tracking.
Each fill-up records odometer, gallons, cost, and optionally a receipt photo.
"""

from __future__ import annotations

from typing import Any

from app.repositories.base import BaseRepo


class FuelLogRepo(BaseRepo):
    """Data access for vehicle_fuel_logs table."""

    TABLE = "vehicle_fuel_logs"
    HAS_UPDATED_AT = True

    async def list_for_vehicle(
        self,
        vehicle_id: int,
        *,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """Get fuel logs for a vehicle, newest first, with joined names."""
        sql = """
            SELECT fl.*,
                   u.display_name AS driver_name,
                   v.vehicle_name,
                   v.vehicle_number
            FROM vehicle_fuel_logs fl
            JOIN users u ON u.id = fl.driver_id
            JOIN vehicles v ON v.id = fl.vehicle_id
            WHERE fl.vehicle_id = ?
            ORDER BY fl.fill_date DESC, fl.id DESC
            LIMIT ? OFFSET ?
        """
        rows = await self.db.execute(sql, (vehicle_id, limit, offset))
        return [dict(r) for r in await rows.fetchall()]

    async def list_fleet(
        self,
        *,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict]:
        """Fleet-wide fuel logs, newest first."""
        sql = """
            SELECT fl.*,
                   u.display_name AS driver_name,
                   v.vehicle_name,
                   v.vehicle_number
            FROM vehicle_fuel_logs fl
            JOIN users u ON u.id = fl.driver_id
            JOIN vehicles v ON v.id = fl.vehicle_id
            ORDER BY fl.fill_date DESC, fl.id DESC
            LIMIT ? OFFSET ?
        """
        rows = await self.db.execute(sql, (limit, offset))
        return [dict(r) for r in await rows.fetchall()]

    async def get_previous_fill(
        self,
        vehicle_id: int,
        fill_date: str,
        current_id: int | None = None,
    ) -> dict | None:
        """Get the fill-up immediately before this one (for MPG calc)."""
        sql = """
            SELECT * FROM vehicle_fuel_logs
            WHERE vehicle_id = ?
              AND (fill_date < ? OR (fill_date = ? AND id < COALESCE(?, 999999999)))
            ORDER BY fill_date DESC, id DESC
            LIMIT 1
        """
        row = await self.db.execute(
            sql, (vehicle_id, fill_date, fill_date, current_id)
        )
        result = await row.fetchone()
        return dict(result) if result else None

    async def get_summary(
        self,
        vehicle_id: int | None = None,
        period_start: str | None = None,
        period_end: str | None = None,
    ) -> dict:
        """Aggregate fuel stats (total gallons, cost, avg price, fill count)."""
        conditions: list[str] = []
        params: list[Any] = []

        if vehicle_id:
            conditions.append("fl.vehicle_id = ?")
            params.append(vehicle_id)
        if period_start:
            conditions.append("fl.fill_date >= ?")
            params.append(period_start)
        if period_end:
            conditions.append("fl.fill_date <= ?")
            params.append(period_end)

        where = f"WHERE {' AND '.join(conditions)}" if conditions else ""

        sql = f"""
            SELECT
                COALESCE(SUM(fl.gallons), 0) AS total_gallons,
                COALESCE(SUM(fl.total_cost), 0) AS total_cost,
                COUNT(*) AS fill_count,
                COALESCE(AVG(fl.price_per_gallon), 0) AS avg_price_per_gallon
            FROM vehicle_fuel_logs fl
            {where}
        """
        row = await self.db.execute(sql, params)
        result = await row.fetchone()
        return dict(result) if result else {
            "total_gallons": 0, "total_cost": 0,
            "fill_count": 0, "avg_price_per_gallon": 0,
        }

    async def get_odometer_range(
        self,
        vehicle_id: int,
        period_start: str | None = None,
        period_end: str | None = None,
    ) -> dict:
        """Get min/max odometer readings to compute miles driven."""
        conditions = ["vehicle_id = ?"]
        params: list[Any] = [vehicle_id]

        if period_start:
            conditions.append("fill_date >= ?")
            params.append(period_start)
        if period_end:
            conditions.append("fill_date <= ?")
            params.append(period_end)

        where = " AND ".join(conditions)
        sql = f"""
            SELECT MIN(odometer_reading) AS min_odo,
                   MAX(odometer_reading) AS max_odo
            FROM vehicle_fuel_logs
            WHERE {where}
        """
        row = await self.db.execute(sql, params)
        result = await row.fetchone()
        return dict(result) if result else {"min_odo": None, "max_odo": None}
