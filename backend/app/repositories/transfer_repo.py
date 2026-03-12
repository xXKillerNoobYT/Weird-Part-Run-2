"""
Repository for vehicle transfers between warehouse locations.
"""

from __future__ import annotations

from typing import Any

from app.repositories.base import BaseRepo


class VehicleTransferRepo(BaseRepo):
    """Data access for the vehicle_transfers table."""

    TABLE = "vehicle_transfers"
    HAS_UPDATED_AT = True

    async def list_transfers(
        self,
        *,
        status: str | None = None,
        vehicle_id: int | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """List transfers with joined names, newest first."""
        conditions: list[str] = []
        params: list[Any] = []

        if status:
            conditions.append("vt.status = ?")
            params.append(status)
        if vehicle_id:
            conditions.append("vt.vehicle_id = ?")
            params.append(vehicle_id)

        where = f"WHERE {' AND '.join(conditions)}" if conditions else ""

        sql = f"""
            SELECT vt.*,
                   v.vehicle_name,
                   v.vehicle_number,
                   wf.name AS from_location_name,
                   wt.name AS to_location_name,
                   ur.display_name AS requested_by_name,
                   ua.display_name AS approved_by_name
            FROM vehicle_transfers vt
            JOIN vehicles v ON v.id = vt.vehicle_id
            JOIN warehouse_locations wf ON wf.id = vt.from_location_id
            JOIN warehouse_locations wt ON wt.id = vt.to_location_id
            JOIN users ur ON ur.id = vt.requested_by
            LEFT JOIN users ua ON ua.id = vt.approved_by
            {where}
            ORDER BY vt.created_at DESC
            LIMIT ? OFFSET ?
        """
        params.extend([limit, offset])
        rows = await self.db.execute(sql, params)
        return [dict(r) for r in await rows.fetchall()]

    async def get_with_details(self, transfer_id: int) -> dict | None:
        """Get a single transfer with joined names."""
        sql = """
            SELECT vt.*,
                   v.vehicle_name,
                   v.vehicle_number,
                   wf.name AS from_location_name,
                   wt.name AS to_location_name,
                   ur.display_name AS requested_by_name,
                   ua.display_name AS approved_by_name
            FROM vehicle_transfers vt
            JOIN vehicles v ON v.id = vt.vehicle_id
            JOIN warehouse_locations wf ON wf.id = vt.from_location_id
            JOIN warehouse_locations wt ON wt.id = vt.to_location_id
            JOIN users ur ON ur.id = vt.requested_by
            LEFT JOIN users ua ON ua.id = vt.approved_by
            WHERE vt.id = ?
        """
        row = await self.db.execute(sql, (transfer_id,))
        result = await row.fetchone()
        return dict(result) if result else None
