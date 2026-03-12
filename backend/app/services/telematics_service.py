"""
Telematics service — device registration, position ingestion, event ingestion.

Devices authenticate via unique auth_token (not user auth) for ingestion.
Admin endpoints use standard user auth for device management.

Business rules:
  - Devices auto-generate auth_token on registration
  - Position ingestion updates device last_seen_at
  - High-frequency position data is NOT synced (TRACK_CHANGES = False on repos)
  - Fleet overview returns last-known position per vehicle
"""

from __future__ import annotations

import logging
import secrets
from typing import Any

import aiosqlite

from app.repositories.telematics_repo import (
    TelematicsDeviceRepo,
    TelematicsEventRepo,
    TelematicsPositionRepo,
)
from app.repositories.vehicle_repo import VehicleRepo

logger = logging.getLogger(__name__)


class TelematicsService:
    """Orchestrates telematics device operations and data ingestion."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.device_repo = TelematicsDeviceRepo(db)
        self.position_repo = TelematicsPositionRepo(db)
        self.event_repo = TelematicsEventRepo(db)
        self.vehicle_repo = VehicleRepo(db)

    # ── Device Management ──────────────────────────────────────

    async def register_device(self, data: dict) -> dict:
        """Register a telematics device on a vehicle.

        Generates a unique auth_token for device-to-server communication.
        """
        vehicle = await self.vehicle_repo.get_by_id(data["vehicle_id"])
        if not vehicle:
            raise ValueError(f"Vehicle {data['vehicle_id']} not found")

        # Check serial uniqueness
        existing = await self.device_repo.get_by_serial(data["device_serial"])
        if existing:
            raise ValueError(
                f"Device serial '{data['device_serial']}' already registered"
            )

        auth_token = secrets.token_urlsafe(32)

        insert_data = {
            "vehicle_id": data["vehicle_id"],
            "device_type": data.get("device_type", "gps_tracker"),
            "device_serial": data["device_serial"],
            "device_name": data.get("device_name"),
            "auth_token": auth_token,
        }

        new_id = await self.device_repo.insert(insert_data)
        await self.db.commit()

        return await self.device_repo.get_by_id(new_id)

    async def deactivate_device(self, device_id: int) -> bool:
        """Soft-deactivate a device."""
        device = await self.device_repo.get_by_id(device_id)
        if not device:
            return False

        await self.device_repo.update(device_id, {"is_active": 0})
        await self.db.commit()
        return True

    async def list_devices(self, *, active_only: bool = True) -> list[dict]:
        """List all registered devices."""
        return await self.device_repo.list_all(active_only=active_only)

    # ── Position Ingestion ─────────────────────────────────────

    async def ingest_position(
        self,
        auth_token: str,
        data: dict,
    ) -> dict:
        """Device pushes a GPS position reading.

        Auth is via device token, not user session.
        Updates device.last_seen_at and optionally vehicle odometer.
        """
        device = await self.device_repo.get_by_token(auth_token)
        if not device:
            raise ValueError("Invalid device token")

        insert_data = {
            "device_id": device["id"],
            "vehicle_id": device["vehicle_id"],
            "lat": data["lat"],
            "lng": data["lng"],
            "speed_mph": data.get("speed_mph"),
            "heading": data.get("heading"),
            "altitude_ft": data.get("altitude_ft"),
            "odometer_reading": data.get("odometer_reading"),
            "engine_on": int(data.get("engine_on", True)),
            "recorded_at": data["recorded_at"],
        }

        new_id = await self.position_repo.insert(insert_data)

        # Update device last_seen_at
        await self.device_repo.update(device["id"], {
            "last_seen_at": data["recorded_at"],
        })

        # Update vehicle odometer if higher
        if data.get("odometer_reading"):
            vehicle = await self.vehicle_repo.get_by_id(device["vehicle_id"])
            if vehicle and data["odometer_reading"] > (vehicle.get("current_odometer") or 0):
                await self.vehicle_repo.update(
                    device["vehicle_id"],
                    {"current_odometer": data["odometer_reading"]},
                )

        await self.db.commit()
        return await self.position_repo.get_by_id(new_id)

    # ── Event Ingestion ────────────────────────────────────────

    async def ingest_event(
        self,
        auth_token: str,
        data: dict,
    ) -> dict:
        """Device pushes a telematics event (hard brake, speeding, DTC, etc.)."""
        device = await self.device_repo.get_by_token(auth_token)
        if not device:
            raise ValueError("Invalid device token")

        insert_data = {
            "device_id": device["id"],
            "vehicle_id": device["vehicle_id"],
            "event_type": data["event_type"],
            "event_data": data.get("event_data"),
            "lat": data.get("lat"),
            "lng": data.get("lng"),
            "recorded_at": data["recorded_at"],
        }

        new_id = await self.event_repo.insert(insert_data)
        await self.db.commit()
        return await self.event_repo.get_by_id(new_id)

    # ── Query Methods ──────────────────────────────────────────

    async def get_vehicle_positions(
        self,
        vehicle_id: int,
        *,
        since: str | None = None,
        limit: int = 200,
    ) -> list[dict]:
        """Recent GPS breadcrumbs for a vehicle."""
        return await self.position_repo.list_for_vehicle(
            vehicle_id, since=since, limit=limit
        )

    async def get_vehicle_events(
        self,
        vehicle_id: int,
        *,
        since: str | None = None,
        event_type: str | None = None,
        limit: int = 100,
    ) -> list[dict]:
        """Recent events for a vehicle."""
        return await self.event_repo.list_for_vehicle(
            vehicle_id, since=since, event_type=event_type, limit=limit
        )

    async def get_fleet_positions(self) -> list[dict]:
        """Last known location for every vehicle with a device."""
        return await self.position_repo.get_last_known_all()
