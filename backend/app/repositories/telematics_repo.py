"""
Repositories for telematics — devices, positions, and events.

Supports device registration, GPS breadcrumb ingestion,
and event (hard brake, speeding, DTC, etc.) storage.
"""

from __future__ import annotations

from typing import Any

from app.repositories.base import BaseRepo


class TelematicsDeviceRepo(BaseRepo):
    """Registered telematics/GPS devices per vehicle."""

    TABLE = "telematics_devices"
    HAS_UPDATED_AT = True

    async def list_all(self, *, active_only: bool = True) -> list[dict]:
        """List devices with joined vehicle names."""
        active_clause = "AND d.is_active = 1" if active_only else ""
        sql = f"""
            SELECT d.*,
                   v.vehicle_name,
                   v.vehicle_number
            FROM telematics_devices d
            JOIN vehicles v ON v.id = d.vehicle_id
            WHERE 1=1 {active_clause}
            ORDER BY d.created_at DESC
        """
        rows = await self.db.execute(sql)
        return [dict(r) for r in await rows.fetchall()]

    async def get_by_token(self, auth_token: str) -> dict | None:
        """Look up device by auth token (for device-auth ingestion)."""
        row = await self.db.execute(
            "SELECT * FROM telematics_devices WHERE auth_token = ? AND is_active = 1",
            (auth_token,),
        )
        result = await row.fetchone()
        return dict(result) if result else None

    async def get_by_serial(self, serial: str) -> dict | None:
        """Look up device by serial number."""
        row = await self.db.execute(
            "SELECT * FROM telematics_devices WHERE device_serial = ?",
            (serial,),
        )
        result = await row.fetchone()
        return dict(result) if result else None


class TelematicsPositionRepo(BaseRepo):
    """GPS breadcrumb positions from telematics devices."""

    TABLE = "telematics_positions"
    HAS_UPDATED_AT = False
    TRACK_CHANGES = False  # High-volume data, don't sync every breadcrumb

    async def list_for_vehicle(
        self,
        vehicle_id: int,
        *,
        since: str | None = None,
        limit: int = 200,
    ) -> list[dict]:
        """Recent positions for a vehicle, newest first."""
        conditions = ["vehicle_id = ?"]
        params: list[Any] = [vehicle_id]

        if since:
            conditions.append("recorded_at >= ?")
            params.append(since)

        where = " AND ".join(conditions)
        sql = f"""
            SELECT * FROM telematics_positions
            WHERE {where}
            ORDER BY recorded_at DESC
            LIMIT ?
        """
        params.append(limit)
        rows = await self.db.execute(sql, params)
        return [dict(r) for r in await rows.fetchall()]

    async def get_last_known_all(self) -> list[dict]:
        """Last known position for every vehicle with a device."""
        sql = """
            SELECT tp.*,
                   v.vehicle_name,
                   v.vehicle_number,
                   d.device_type
            FROM telematics_positions tp
            INNER JOIN (
                SELECT vehicle_id, MAX(recorded_at) AS max_recorded
                FROM telematics_positions
                GROUP BY vehicle_id
            ) latest ON latest.vehicle_id = tp.vehicle_id
                    AND latest.max_recorded = tp.recorded_at
            JOIN vehicles v ON v.id = tp.vehicle_id
            JOIN telematics_devices d ON d.id = tp.device_id
            ORDER BY v.vehicle_number
        """
        rows = await self.db.execute(sql)
        return [dict(r) for r in await rows.fetchall()]


class TelematicsEventRepo(BaseRepo):
    """Events from telematics devices (hard brake, speeding, DTC, etc.)."""

    TABLE = "telematics_events"
    HAS_UPDATED_AT = False
    TRACK_CHANGES = False  # High-volume data

    async def list_for_vehicle(
        self,
        vehicle_id: int,
        *,
        since: str | None = None,
        event_type: str | None = None,
        limit: int = 100,
    ) -> list[dict]:
        """Recent events for a vehicle, newest first."""
        conditions = ["vehicle_id = ?"]
        params: list[Any] = [vehicle_id]

        if since:
            conditions.append("recorded_at >= ?")
            params.append(since)
        if event_type:
            conditions.append("event_type = ?")
            params.append(event_type)

        where = " AND ".join(conditions)
        sql = f"""
            SELECT * FROM telematics_events
            WHERE {where}
            ORDER BY recorded_at DESC
            LIMIT ?
        """
        params.append(limit)
        rows = await self.db.execute(sql, params)
        return [dict(r) for r in await rows.fetchall()]
