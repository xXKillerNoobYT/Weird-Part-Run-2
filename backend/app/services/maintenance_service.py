"""
Maintenance service — log service records, manage per-vehicle schedules,
calculate next-due dates/miles, surface alerts, and summarize costs.

Schedule cascade flow:
  1. Log a service record (oil change, tire rotation, etc.)
  2. Update the per-vehicle schedule: set last_performed_at/miles
  3. Compute next_due_date and next_due_miles from interval config
  4. Overdue/upcoming queries surface alerts to dashboards

Interval sources (priority order):
  - Per-vehicle schedule overrides (vehicle_maintenance_schedules)
  - Default intervals from maintenance_types table
"""

from __future__ import annotations

import logging
from datetime import date, timedelta
from typing import Any

import aiosqlite

from app.repositories.vehicle_repo import (
    MaintenanceRecordRepo,
    MaintenanceScheduleRepo,
    MaintenanceTypeRepo,
    VehicleRepo,
)

logger = logging.getLogger(__name__)


class MaintenanceService:
    """Orchestrates vehicle maintenance scheduling and service history."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.type_repo = MaintenanceTypeRepo(db)
        self.schedule_repo = MaintenanceScheduleRepo(db)
        self.record_repo = MaintenanceRecordRepo(db)
        self.vehicle_repo = VehicleRepo(db)

    # ── Maintenance Types (admin CRUD) ────────────────────────

    async def list_maintenance_types(self, *, active_only: bool = True) -> list[dict]:
        """List all maintenance types."""
        if active_only:
            return await self.type_repo.list_active()
        return await self.type_repo.get_all()

    async def create_maintenance_type(self, data: dict) -> dict:
        """Create a new maintenance type."""
        existing = await self.type_repo.get_by_name(data["name"])
        if existing:
            raise ValueError(f"Maintenance type '{data['name']}' already exists")

        new_id = await self.type_repo.insert(data)
        await self.db.commit()
        return await self.type_repo.get_by_id(new_id)

    async def update_maintenance_type(self, type_id: int, data: dict) -> dict | None:
        """Update a maintenance type's info."""
        existing = await self.type_repo.get_by_id(type_id)
        if not existing:
            return None

        # Check name uniqueness if name is changing
        if "name" in data and data["name"] != existing["name"]:
            conflict = await self.type_repo.get_by_name(data["name"])
            if conflict:
                raise ValueError(f"Maintenance type '{data['name']}' already exists")

        await self.type_repo.update(type_id, data)
        await self.db.commit()
        return await self.type_repo.get_by_id(type_id)

    # ── Per-Vehicle Schedules ─────────────────────────────────

    async def get_vehicle_schedule(self, vehicle_id: int) -> list[dict]:
        """Get the full maintenance schedule for a vehicle.

        Returns all enabled schedule entries with their type info,
        including computed urgency levels.
        """
        schedules = await self.schedule_repo.get_for_vehicle(vehicle_id)
        vehicle = await self.vehicle_repo.get_by_id(vehicle_id)
        if not vehicle:
            return schedules

        # Enrich each schedule with urgency calculation
        today = date.today()
        enriched = []
        for s in schedules:
            s = dict(s)
            s["urgency"] = self._compute_urgency(s, vehicle, today)
            enriched.append(s)

        return enriched

    async def set_schedule(
        self,
        vehicle_id: int,
        maintenance_type_id: int,
        data: dict,
    ) -> dict:
        """Create or update a per-vehicle schedule for a maintenance type.

        Accepts: interval_miles, interval_months, next_due_date,
        next_due_miles, is_enabled, notes
        """
        vehicle = await self.vehicle_repo.get_by_id(vehicle_id)
        if not vehicle:
            raise ValueError(f"Vehicle {vehicle_id} not found")

        mtype = await self.type_repo.get_by_id(maintenance_type_id)
        if not mtype:
            raise ValueError(f"Maintenance type {maintenance_type_id} not found")

        # Get-or-create the schedule entry
        schedule = await self.schedule_repo.get_or_create(
            vehicle_id, maintenance_type_id
        )

        # If no custom intervals provided, copy defaults from the type
        if "interval_miles" not in data and not schedule.get("interval_miles"):
            data.setdefault("interval_miles", mtype.get("default_interval_miles"))
        if "interval_months" not in data and not schedule.get("interval_months"):
            data.setdefault("interval_months", mtype.get("default_interval_months"))

        # Filter out None values to avoid overwriting with NULL
        update_data = {k: v for k, v in data.items() if v is not None}

        if update_data:
            await self.schedule_repo.update(schedule["id"], update_data)

        await self.db.commit()
        return await self.schedule_repo.get_by_id(schedule["id"])

    async def init_schedules_for_vehicle(self, vehicle_id: int) -> int:
        """Initialize maintenance schedules for a vehicle using all active types.

        Called after creating a new vehicle. Creates schedule entries
        using the default intervals from each maintenance_type.
        Returns count of schedules created.
        """
        types = await self.type_repo.list_active()
        count = 0

        for mtype in types:
            # get_or_create avoids duplicates if called twice
            schedule = await self.schedule_repo.get_or_create(
                vehicle_id, mtype["id"]
            )

            # Apply default intervals from the type
            defaults = {}
            if mtype.get("default_interval_miles"):
                defaults["interval_miles"] = mtype["default_interval_miles"]
            if mtype.get("default_interval_months"):
                defaults["interval_months"] = mtype["default_interval_months"]

            if defaults:
                await self.schedule_repo.update(schedule["id"], defaults)
                count += 1

        await self.db.commit()
        return count

    # ── Service Record Logging ────────────────────────────────

    async def log_service(
        self,
        vehicle_id: int,
        data: dict,
        performed_by: int,
    ) -> dict:
        """Log a maintenance service and cascade to schedule.

        Steps:
          1. Validate vehicle + maintenance type exist
          2. Insert the record with vehicle_id and performed_by
          3. Update vehicle's current_odometer if record has a reading
          4. Update the schedule: last_performed, recalculate next_due
        """
        vehicle = await self.vehicle_repo.get_by_id(vehicle_id)
        if not vehicle:
            raise ValueError(f"Vehicle {vehicle_id} not found")

        mtype = await self.type_repo.get_by_id(data["maintenance_type_id"])
        if not mtype:
            raise ValueError(
                f"Maintenance type {data['maintenance_type_id']} not found"
            )

        # Default service_date to today
        if not data.get("service_date"):
            data["service_date"] = date.today().isoformat()

        # 1. Insert the record
        record_data = {
            "vehicle_id": vehicle_id,
            "performed_by": performed_by,
            **data,
        }
        new_id = await self.record_repo.insert(record_data)

        # 2. Update vehicle odometer if provided
        odometer = data.get("odometer_reading")
        if odometer and odometer > (vehicle.get("current_odometer") or 0):
            await self.vehicle_repo.update(vehicle_id, {
                "current_odometer": odometer,
            })

        # 3. Cascade to schedule — update last_performed + compute next_due
        await self._cascade_to_schedule(
            vehicle_id=vehicle_id,
            maintenance_type_id=data["maintenance_type_id"],
            service_date=data["service_date"],
            odometer_reading=odometer,
        )

        await self.db.commit()
        return await self.record_repo.get_by_id(new_id)

    async def _cascade_to_schedule(
        self,
        vehicle_id: int,
        maintenance_type_id: int,
        service_date: str,
        odometer_reading: int | None,
    ) -> None:
        """Update the maintenance schedule after logging a service.

        Recalculates next_due_date and next_due_miles based on intervals.
        """
        schedule = await self.schedule_repo.get_or_create(
            vehicle_id, maintenance_type_id
        )

        update_data: dict[str, Any] = {
            "last_performed_at": service_date,
        }
        if odometer_reading:
            update_data["last_performed_miles"] = odometer_reading

        # Get interval config (per-vehicle override → type default)
        mtype = await self.type_repo.get_by_id(maintenance_type_id)

        interval_miles = (
            schedule.get("interval_miles")
            or (mtype.get("default_interval_miles") if mtype else None)
        )
        interval_months = (
            schedule.get("interval_months")
            or (mtype.get("default_interval_months") if mtype else None)
        )

        # Compute next_due_miles
        if interval_miles and odometer_reading:
            update_data["next_due_miles"] = odometer_reading + interval_miles

        # Compute next_due_date
        if interval_months:
            performed = date.fromisoformat(service_date)
            # Approximate month addition (30 days per month)
            next_date = performed + timedelta(days=interval_months * 30)
            update_data["next_due_date"] = next_date.isoformat()

        await self.schedule_repo.update(schedule["id"], update_data)

    # ── Alerts & Queries ──────────────────────────────────────

    async def get_overdue(
        self, *, vehicle_id: int | None = None
    ) -> list[dict]:
        """Get all overdue maintenance items, enriched with urgency."""
        items = await self.schedule_repo.get_overdue(vehicle_id=vehicle_id)
        return [
            {**dict(item), "is_overdue": True, "urgency": "overdue"}
            for item in items
        ]

    async def get_upcoming(
        self,
        *,
        days_ahead: int = 30,
        vehicle_id: int | None = None,
    ) -> list[dict]:
        """Get maintenance due within the next N days."""
        items = await self.schedule_repo.get_upcoming(
            days_ahead=days_ahead, vehicle_id=vehicle_id
        )
        enriched = []
        for item in items:
            item = dict(item)
            days = item.get("days_until_due")
            if days is not None and days <= 7:
                item["urgency"] = "soon"
            else:
                item["urgency"] = "normal"
            item["is_overdue"] = False
            enriched.append(item)

        return enriched

    async def get_alerts(
        self, *, vehicle_id: int | None = None, days_ahead: int = 30
    ) -> list[dict]:
        """Combined overdue + upcoming alerts, sorted by urgency."""
        overdue = await self.get_overdue(vehicle_id=vehicle_id)
        upcoming = await self.get_upcoming(
            days_ahead=days_ahead, vehicle_id=vehicle_id
        )

        # Combine and sort: overdue first, then by days_until_due
        all_alerts = overdue + upcoming
        all_alerts.sort(key=lambda a: (
            0 if a.get("is_overdue") else 1,
            a.get("days_until_due") or 0,
        ))

        return all_alerts

    # ── Service History ───────────────────────────────────────

    async def get_service_history(
        self,
        vehicle_id: int,
        *,
        maintenance_type_id: int | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """Get service history for a vehicle."""
        return await self.record_repo.get_for_vehicle(
            vehicle_id,
            maintenance_type_id=maintenance_type_id,
            limit=limit,
            offset=offset,
        )

    async def get_cost_summary(
        self,
        vehicle_id: int,
        *,
        period_start: str | None = None,
        period_end: str | None = None,
    ) -> dict:
        """Get maintenance cost summary with per-type breakdown."""
        return await self.record_repo.get_cost_summary(
            vehicle_id,
            period_start=period_start,
            period_end=period_end,
        )

    async def get_fleet_cost_summary(
        self,
        *,
        period_start: str | None = None,
        period_end: str | None = None,
    ) -> dict:
        """Get fleet-wide maintenance cost summary."""
        conditions = []
        params: list[Any] = []

        if period_start:
            conditions.append("mr.service_date >= ?")
            params.append(period_start)
        if period_end:
            conditions.append("mr.service_date <= ?")
            params.append(period_end)

        where_sql = " AND ".join(conditions) if conditions else "1=1"

        cursor = await self.db.execute(
            f"""
            SELECT COALESCE(SUM(mr.cost), 0) AS total_cost,
                   COUNT(*) AS total_records
            FROM vehicle_maintenance_records mr
            WHERE {where_sql}
            """,
            tuple(params),
        )
        row = await cursor.fetchone()
        totals = dict(row) if row else {"total_cost": 0, "total_records": 0}

        # Per-vehicle breakdown
        cursor = await self.db.execute(
            f"""
            SELECT v.vehicle_name, v.vehicle_number,
                   COALESCE(SUM(mr.cost), 0) AS total_cost,
                   COUNT(*) AS record_count
            FROM vehicle_maintenance_records mr
            JOIN vehicles v ON v.id = mr.vehicle_id
            WHERE {where_sql}
            GROUP BY v.id
            ORDER BY total_cost DESC
            """,
            tuple(params),
        )
        totals["per_vehicle"] = [dict(r) for r in await cursor.fetchall()]

        return totals

    # ── Helpers ────────────────────────────────────────────────

    @staticmethod
    def _compute_urgency(
        schedule: dict, vehicle: dict, today: date
    ) -> str:
        """Determine urgency level for a schedule entry.

        Returns: 'overdue', 'soon' (within 7 days or 500 miles), 'normal'
        """
        # Check date-based urgency
        due_date_str = schedule.get("next_due_date")
        if due_date_str:
            try:
                due_date = date.fromisoformat(due_date_str)
                if due_date <= today:
                    return "overdue"
                if (due_date - today).days <= 7:
                    return "soon"
            except ValueError:
                pass

        # Check miles-based urgency
        due_miles = schedule.get("next_due_miles")
        current = vehicle.get("current_odometer") or 0
        if due_miles and current:
            remaining = due_miles - current
            if remaining <= 0:
                return "overdue"
            if remaining <= 500:
                return "soon"

        return "normal"
