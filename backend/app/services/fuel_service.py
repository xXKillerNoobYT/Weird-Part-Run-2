"""
Fuel tracking service — log fuel purchases, calculate MPG, summaries.

Business rules:
  - Odometer must be >= vehicle's current_odometer
  - MPG is calculated from the previous fill-up on the same vehicle
  - Receipt photo is optional but encouraged
  - Fuel summary aggregates cost, gallons, and avg MPG per vehicle/fleet
"""

from __future__ import annotations

import logging
from datetime import date as _date
from typing import Any

import aiosqlite

from app.repositories.fuel_repo import FuelLogRepo
from app.repositories.vehicle_repo import VehicleRepo

logger = logging.getLogger(__name__)


class FuelService:
    """Orchestrates fuel log operations."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.fuel_repo = FuelLogRepo(db)
        self.vehicle_repo = VehicleRepo(db)

    async def log_fuel(
        self,
        vehicle_id: int,
        driver_id: int,
        data: dict,
    ) -> dict:
        """Log a fuel purchase.

        Validates odometer >= current. Calculates MPG from previous fill.
        Updates vehicle's current_odometer if higher.
        """
        vehicle = await self.vehicle_repo.get_by_id(vehicle_id)
        if not vehicle:
            raise ValueError(f"Vehicle {vehicle_id} not found")

        odo = data["odometer_reading"]
        current_odo = vehicle.get("current_odometer", 0) or 0

        if odo < current_odo:
            raise ValueError(
                f"Odometer {odo} is less than vehicle's current odometer {current_odo}"
            )

        fill_date = data.get("fill_date") or _date.today().isoformat()

        insert_data = {
            "vehicle_id": vehicle_id,
            "driver_id": driver_id,
            "fill_date": fill_date,
            "odometer_reading": odo,
            "gallons": data["gallons"],
            "price_per_gallon": data["price_per_gallon"],
            "fuel_type": data.get("fuel_type", "regular"),
            "station_name": data.get("station_name"),
            "receipt_photo": data.get("receipt_photo"),
            "notes": data.get("notes"),
        }

        new_id = await self.fuel_repo.insert(insert_data)

        # Update vehicle odometer if this reading is newer
        if odo > current_odo:
            await self.vehicle_repo.update(vehicle_id, {"current_odometer": odo})

        await self.db.commit()

        # Fetch the record and calculate MPG
        record = await self.fuel_repo.get_by_id(new_id)
        return await self._enrich_with_mpg(record)

    async def update_fuel_log(
        self,
        log_id: int,
        data: dict,
    ) -> dict | None:
        """Update an existing fuel log entry."""
        existing = await self.fuel_repo.get_by_id(log_id)
        if not existing:
            return None

        patch = {k: v for k, v in data.items() if v is not None}
        if patch:
            await self.fuel_repo.update(log_id, patch)
            await self.db.commit()

        record = await self.fuel_repo.get_by_id(log_id)
        return await self._enrich_with_mpg(record)

    async def get_fuel_logs(
        self,
        vehicle_id: int,
        *,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """Fuel history for a vehicle with MPG calculation."""
        logs = await self.fuel_repo.list_for_vehicle(
            vehicle_id, limit=limit, offset=offset
        )
        enriched = []
        for log in logs:
            enriched.append(await self._enrich_with_mpg(log))
        return enriched

    async def get_fleet_fuel_logs(
        self,
        *,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict]:
        """Fleet-wide fuel logs."""
        return await self.fuel_repo.list_fleet(limit=limit, offset=offset)

    async def get_fuel_summary(
        self,
        vehicle_id: int | None = None,
        period_start: str | None = None,
        period_end: str | None = None,
    ) -> dict:
        """Aggregate fuel stats: cost, gallons, avg price, MPG."""
        summary = await self.fuel_repo.get_summary(
            vehicle_id=vehicle_id,
            period_start=period_start,
            period_end=period_end,
        )

        # Calculate avg MPG from odometer range
        avg_mpg = None
        if vehicle_id and summary["fill_count"] >= 2:
            odo = await self.fuel_repo.get_odometer_range(
                vehicle_id,
                period_start=period_start,
                period_end=period_end,
            )
            if odo["min_odo"] and odo["max_odo"]:
                miles = odo["max_odo"] - odo["min_odo"]
                if summary["total_gallons"] > 0 and miles > 0:
                    avg_mpg = round(miles / summary["total_gallons"], 1)

        summary["avg_mpg"] = avg_mpg
        total_miles = None
        if vehicle_id:
            odo = await self.fuel_repo.get_odometer_range(
                vehicle_id, period_start=period_start, period_end=period_end
            )
            if odo["min_odo"] and odo["max_odo"]:
                total_miles = odo["max_odo"] - odo["min_odo"]
        summary["total_miles_driven"] = total_miles

        return summary

    async def _enrich_with_mpg(self, record: dict) -> dict:
        """Calculate MPG by comparing to previous fill-up."""
        if not record:
            return record

        prev = await self.fuel_repo.get_previous_fill(
            record["vehicle_id"],
            record["fill_date"],
            current_id=record.get("id"),
        )

        mpg = None
        if prev and record.get("odometer_reading") and prev.get("odometer_reading"):
            miles = record["odometer_reading"] - prev["odometer_reading"]
            gallons = record.get("gallons", 0)
            if gallons > 0 and miles > 0:
                mpg = round(miles / gallons, 1)

        record["mpg"] = mpg
        return record
