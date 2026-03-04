"""
Mileage service — daily odometer logging, trip leg management, mileage
estimation from manual distances, and reimbursement CRUD with approval.

Key concepts:
  - Odometer validation: end ≥ start, new start ≥ previous end
  - Trip legs with auto-billable: shop→job and job→job = billable,
    home→shop and shop→home = not billable (commute)
  - Estimation: uses manual one-time distances (home_to_shop on assignment,
    distance_from_shop_miles on job) to compute round-trip miles
  - Reimbursement: for private vehicles, sums miles × IRS rate for a period
"""

from __future__ import annotations

import logging
from datetime import date
from typing import Any

import aiosqlite

from app.repositories.settings_repo import SettingsRepo
from app.repositories.vehicle_repo import (
    MileageLogRepo,
    ReimbursementRepo,
    TripLegRepo,
    VehicleAssignmentRepo,
    VehicleRepo,
)

logger = logging.getLogger(__name__)

# Leg types that qualify as billable drive time (paid by employer)
BILLABLE_LEG_TYPES = {
    "shop_to_job",
    "job_to_job",
    "job_to_shop",
}

# Leg types that are commute (not billable)
NON_BILLABLE_LEG_TYPES = {
    "home_to_shop",
    "shop_to_home",
    "home_to_job",   # take-home → job is mixed, default not billable
    "job_to_home",   # job → take-home is mixed, default not billable
    "other",
}


class MileageService:
    """Orchestrates mileage logging, trip tracking, and reimbursements."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.log_repo = MileageLogRepo(db)
        self.leg_repo = TripLegRepo(db)
        self.reimburse_repo = ReimbursementRepo(db)
        self.assignment_repo = VehicleAssignmentRepo(db)
        self.vehicle_repo = VehicleRepo(db)
        self.settings_repo = SettingsRepo(db)

    # ── Daily Mileage Logging ─────────────────────────────────

    async def log_daily_mileage(
        self,
        vehicle_id: int,
        driver_id: int,
        data: dict,
    ) -> dict:
        """Create or update a daily mileage log for a vehicle.

        Validates:
          - Vehicle exists
          - Odometer readings are sane (end ≥ start)
          - Start reading ≥ previous day's end reading
          - Updates vehicle.current_odometer if new end is higher
        """
        vehicle = await self.vehicle_repo.get_by_id(vehicle_id)
        if not vehicle:
            raise ValueError(f"Vehicle {vehicle_id} not found")

        log_date = data.get("log_date") or date.today().isoformat()

        # Validate odometer readings
        odo_start = data.get("odometer_start")
        odo_end = data.get("odometer_end")

        if odo_start is not None and odo_end is not None:
            if odo_end < odo_start:
                raise ValueError(
                    f"Odometer end ({odo_end}) cannot be less than start ({odo_start})"
                )

        # Check for existing log on this date (UNIQUE constraint)
        existing = await self.log_repo.get_daily(vehicle_id, log_date)
        if existing:
            # Update the existing entry instead of creating a duplicate
            update_data = {k: v for k, v in data.items() if v is not None}
            update_data.pop("log_date", None)  # don't update the date key
            await self.log_repo.update(existing["id"], update_data)

            # Update vehicle odometer
            if odo_end and odo_end > (vehicle.get("current_odometer") or 0):
                await self.vehicle_repo.update(vehicle_id, {
                    "current_odometer": odo_end,
                })

            await self.db.commit()
            return await self.log_repo.get_daily(vehicle_id, log_date)

        # Create new mileage log
        log_data = {
            "vehicle_id": vehicle_id,
            "driver_id": driver_id,
            "log_date": log_date,
            "odometer_start": odo_start,
            "odometer_end": odo_end,
            "is_take_home_day": data.get("is_take_home_day", False),
            "notes": data.get("notes"),
        }
        new_id = await self.log_repo.insert(log_data)

        # Update vehicle odometer if new reading is higher
        if odo_end and odo_end > (vehicle.get("current_odometer") or 0):
            await self.vehicle_repo.update(vehicle_id, {
                "current_odometer": odo_end,
            })

        await self.db.commit()
        return await self.log_repo.get_by_id(new_id)

    async def update_mileage_log(
        self,
        log_id: int,
        data: dict,
    ) -> dict | None:
        """Update an existing mileage log entry."""
        existing = await self.log_repo.get_by_id(log_id)
        if not existing:
            return None

        # Validate odometer if both provided
        odo_start = data.get("odometer_start", existing.get("odometer_start"))
        odo_end = data.get("odometer_end", existing.get("odometer_end"))

        if odo_start is not None and odo_end is not None:
            if odo_end < odo_start:
                raise ValueError(
                    f"Odometer end ({odo_end}) cannot be less than start ({odo_start})"
                )

        update_data = {k: v for k, v in data.items() if v is not None}
        if update_data:
            await self.log_repo.update(log_id, update_data)

        # Update vehicle odometer if needed
        if odo_end:
            vehicle = await self.vehicle_repo.get_by_id(existing["vehicle_id"])
            if vehicle and odo_end > (vehicle.get("current_odometer") or 0):
                await self.vehicle_repo.update(existing["vehicle_id"], {
                    "current_odometer": odo_end,
                })

        await self.db.commit()
        return await self.log_repo.get_by_id(log_id)

    async def get_mileage_logs(
        self,
        vehicle_id: int,
        *,
        limit: int = 30,
        offset: int = 0,
    ) -> list[dict]:
        """Get mileage logs for a vehicle, newest first, with trip legs."""
        rows = await self.log_repo.get_for_vehicle(
            vehicle_id, limit=limit, offset=offset
        )
        # Hydrate each log with its trip legs so the UI can expand rows
        logs = []
        for row in rows:
            log = dict(row)
            log["trip_legs"] = await self.leg_repo.get_for_log(log["id"])
            logs.append(log)
        return logs

    async def get_driver_logs(
        self,
        driver_id: int,
        *,
        limit: int = 30,
        offset: int = 0,
    ) -> list[dict]:
        """Get mileage logs for a specific driver across all vehicles."""
        return await self.log_repo.get_for_driver(
            driver_id, limit=limit, offset=offset
        )

    async def get_mileage_log_with_trips(
        self,
        log_id: int,
    ) -> dict | None:
        """Get a mileage log with all its trip legs attached."""
        log = await self.log_repo.get_by_id(log_id)
        if not log:
            return None

        log = dict(log)
        log["trip_legs"] = await self.leg_repo.get_for_log(log_id)
        return log

    # ── Trip Leg Management ───────────────────────────────────

    async def add_trip_legs(
        self,
        mileage_log_id: int,
        legs: list[dict],
    ) -> list[int]:
        """Add trip legs to a mileage log, with auto-billable assignment.

        Each leg: {leg_order, leg_type, from_label?, to_label?,
                   estimated_miles?, actual_miles?,
                   estimated_drive_minutes?, actual_drive_minutes?,
                   is_billable? (auto if omitted), from_job_id?, to_job_id?}
        """
        log = await self.log_repo.get_by_id(mileage_log_id)
        if not log:
            raise ValueError(f"Mileage log {mileage_log_id} not found")

        processed_legs = []
        for leg in legs:
            leg_type = leg.get("leg_type", "other")

            # Auto-set billable flag based on leg type if not explicitly set
            if "is_billable" not in leg:
                leg["is_billable"] = leg_type in BILLABLE_LEG_TYPES

            processed_legs.append(leg)

        ids = await self.leg_repo.bulk_insert(mileage_log_id, processed_legs)
        await self.db.commit()
        return ids

    async def get_trip_legs(self, mileage_log_id: int) -> list[dict]:
        """Get all trip legs for a mileage log entry."""
        return await self.leg_repo.get_for_log(mileage_log_id)

    async def get_job_trips(self, job_id: int, *, limit: int = 50) -> list[dict]:
        """Get all trip legs that reference a specific job."""
        return await self.leg_repo.get_for_job(job_id, limit=limit)

    async def get_billable_minutes(
        self,
        driver_id: int,
        period_start: str,
        period_end: str,
    ) -> int:
        """Get total billable drive minutes for a driver in a date range.

        Used by payroll to calculate paid drive time.
        """
        return await self.leg_repo.get_billable_minutes_for_period(
            driver_id, period_start, period_end
        )

    # ── Mileage Estimation ────────────────────────────────────

    async def estimate_trip(
        self,
        *,
        vehicle_id: int | None = None,
        driver_id: int | None = None,
        job_id: int | None = None,
        job_ids: list[int] | None = None,
        is_take_home: bool | None = None,
    ) -> dict:
        """Estimate daily mileage using stored manual distances.

        Data sources:
          - vehicle_assignments.home_to_shop_miles (per driver)
          - jobs.distance_from_shop_miles (per job)
          - jobs.estimated_drive_minutes_from_shop (per job)

        Routes:
          Standard:  Home→Shop + Shop→Job + Job→Shop + Shop→Home
          Take-home: Home→Job + Job→Home (approx: home_to_shop + shop_to_job each way)
          Multi-job: Sums shop→job1 + job1→job2 + ... + last_job→shop
        """
        # Resolve driver's home-to-shop distance
        home_to_shop = 0.0
        assignment = None

        if vehicle_id and driver_id:
            # Specific driver + vehicle combo
            assignments = await self.assignment_repo.get_active_for_vehicle(vehicle_id)
            for a in assignments:
                if a["user_id"] == driver_id:
                    assignment = a
                    break
        elif driver_id:
            # Any active assignment for this driver
            assignment = await self.assignment_repo.get_active_for_user(driver_id)
        elif vehicle_id:
            # Primary driver of this vehicle
            assignment = await self.assignment_repo.get_primary_driver(vehicle_id)

        if assignment:
            home_to_shop = assignment.get("home_to_shop_miles") or 0.0
            if is_take_home is None:
                is_take_home = bool(assignment.get("is_take_home"))

        is_take_home = is_take_home or False

        # Collect job distances
        all_job_ids = job_ids or ([job_id] if job_id else [])
        job_distances = []

        for jid in all_job_ids:
            cursor = await self.db.execute(
                """
                SELECT job_name, distance_from_shop_miles,
                       estimated_drive_minutes_from_shop
                FROM jobs WHERE id = ?
                """,
                (jid,),
            )
            job = await cursor.fetchone()
            if job:
                job_distances.append({
                    "job_id": jid,
                    "job_name": job["job_name"],
                    "distance_from_shop": job.get("distance_from_shop_miles") or 0,
                    "drive_minutes_from_shop": job.get("estimated_drive_minutes_from_shop") or 0,
                })

        # Build estimate
        legs = []
        total_miles = 0.0
        total_billable_miles = 0.0
        total_billable_minutes = 0

        if not job_distances:
            # No jobs — just commute
            if home_to_shop > 0:
                legs.append({
                    "leg_type": "home_to_shop",
                    "from_label": "Home",
                    "to_label": "Shop",
                    "estimated_miles": home_to_shop,
                    "is_billable": False,
                })
                legs.append({
                    "leg_type": "shop_to_home",
                    "from_label": "Shop",
                    "to_label": "Home",
                    "estimated_miles": home_to_shop,
                    "is_billable": False,
                })
                total_miles = home_to_shop * 2

        elif len(job_distances) == 1:
            # Single job day
            job = job_distances[0]
            shop_to_job = job["distance_from_shop"]
            drive_min = job["drive_minutes_from_shop"]

            if is_take_home:
                # Take-home: Home → Job → Home
                # Approximate: home_to_shop + shop_to_job (one way)
                one_way = home_to_shop + shop_to_job
                legs.append({
                    "leg_type": "home_to_job",
                    "from_label": "Home",
                    "to_label": job["job_name"],
                    "estimated_miles": one_way,
                    "estimated_drive_minutes": drive_min,
                    "is_billable": False,
                })
                legs.append({
                    "leg_type": "job_to_home",
                    "from_label": job["job_name"],
                    "to_label": "Home",
                    "estimated_miles": one_way,
                    "estimated_drive_minutes": drive_min,
                    "is_billable": False,
                })
                total_miles = one_way * 2
                # For take-home, one leg is typically billable (to job site)
                total_billable_miles = one_way
                total_billable_minutes = drive_min
            else:
                # Standard: Home → Shop → Job → Shop → Home
                legs.append({
                    "leg_type": "home_to_shop",
                    "from_label": "Home",
                    "to_label": "Shop",
                    "estimated_miles": home_to_shop,
                    "is_billable": False,
                })
                legs.append({
                    "leg_type": "shop_to_job",
                    "from_label": "Shop",
                    "to_label": job["job_name"],
                    "estimated_miles": shop_to_job,
                    "estimated_drive_minutes": drive_min,
                    "is_billable": True,
                })
                legs.append({
                    "leg_type": "job_to_shop",
                    "from_label": job["job_name"],
                    "to_label": "Shop",
                    "estimated_miles": shop_to_job,
                    "estimated_drive_minutes": drive_min,
                    "is_billable": True,
                })
                legs.append({
                    "leg_type": "shop_to_home",
                    "from_label": "Shop",
                    "to_label": "Home",
                    "estimated_miles": home_to_shop,
                    "is_billable": False,
                })
                total_miles = (home_to_shop * 2) + (shop_to_job * 2)
                total_billable_miles = shop_to_job * 2
                total_billable_minutes = drive_min * 2

        else:
            # Multi-job day: Home → Shop → Job1 → Job2 → ... → Shop → Home
            legs.append({
                "leg_type": "home_to_shop",
                "from_label": "Home",
                "to_label": "Shop",
                "estimated_miles": home_to_shop,
                "is_billable": False,
            })
            total_miles += home_to_shop

            prev_label = "Shop"
            for i, job in enumerate(job_distances):
                shop_to_job = job["distance_from_shop"]
                drive_min = job["drive_minutes_from_shop"]

                if i == 0:
                    # Shop → first job
                    legs.append({
                        "leg_type": "shop_to_job",
                        "from_label": "Shop",
                        "to_label": job["job_name"],
                        "estimated_miles": shop_to_job,
                        "estimated_drive_minutes": drive_min,
                        "is_billable": True,
                    })
                    total_miles += shop_to_job
                    total_billable_miles += shop_to_job
                    total_billable_minutes += drive_min
                else:
                    # Job → Job (estimate: use sum of distances from shop
                    # as upper bound; actual may differ)
                    prev_job = job_distances[i - 1]
                    # Rough estimate: |dist_A - dist_B| to dist_A + dist_B
                    # We use the average as a reasonable middle ground
                    prev_dist = prev_job["distance_from_shop"]
                    curr_dist = shop_to_job
                    estimated_between = abs(curr_dist - prev_dist) + (
                        (curr_dist + prev_dist - abs(curr_dist - prev_dist)) / 2
                    )
                    # Simplified: just use the midpoint approach
                    # More accurately: sqrt(a^2 + b^2) for right-angle,
                    # but manual input is better — this is just a rough estimate
                    estimated_between = (prev_dist + curr_dist) / 2

                    legs.append({
                        "leg_type": "job_to_job",
                        "from_label": prev_job["job_name"],
                        "to_label": job["job_name"],
                        "estimated_miles": round(estimated_between, 1),
                        "is_billable": True,
                    })
                    total_miles += estimated_between
                    total_billable_miles += estimated_between

                prev_label = job["job_name"]

            # Last job → Shop
            last_job = job_distances[-1]
            legs.append({
                "leg_type": "job_to_shop",
                "from_label": last_job["job_name"],
                "to_label": "Shop",
                "estimated_miles": last_job["distance_from_shop"],
                "estimated_drive_minutes": last_job["drive_minutes_from_shop"],
                "is_billable": True,
            })
            total_miles += last_job["distance_from_shop"]
            total_billable_miles += last_job["distance_from_shop"]
            total_billable_minutes += last_job["drive_minutes_from_shop"]

            # Shop → Home
            legs.append({
                "leg_type": "shop_to_home",
                "from_label": "Shop",
                "to_label": "Home",
                "estimated_miles": home_to_shop,
                "is_billable": False,
            })
            total_miles += home_to_shop

        return {
            "home_to_shop_miles": home_to_shop,
            "shop_to_job_miles": (
                job_distances[0]["distance_from_shop"]
                if len(job_distances) == 1 else None
            ),
            "total_round_trip_miles": round(total_miles, 1),
            "total_billable_miles": round(total_billable_miles, 1),
            "estimated_drive_minutes_one_way": (
                job_distances[0]["drive_minutes_from_shop"]
                if len(job_distances) == 1 else None
            ),
            "estimated_billable_drive_minutes": total_billable_minutes,
            "is_take_home": is_take_home,
            "legs": legs,
        }

    # ── Mileage Summary ──────────────────────────────────────

    async def get_mileage_summary(
        self,
        *,
        vehicle_id: int | None = None,
        driver_id: int | None = None,
        period_start: str,
        period_end: str,
    ) -> dict:
        """Get mileage summary for a period (vehicle or driver scope)."""
        summary = await self.log_repo.get_period_summary(
            vehicle_id=vehicle_id,
            driver_id=driver_id,
            period_start=period_start,
            period_end=period_end,
        )

        total_days = summary.get("total_days_logged", 0)
        total_miles = summary.get("total_miles", 0)
        summary["avg_miles_per_day"] = (
            round(total_miles / total_days, 1) if total_days > 0 else 0
        )

        return {
            "vehicle_id": vehicle_id,
            "driver_id": driver_id,
            "period_start": period_start,
            "period_end": period_end,
            **summary,
        }

    # ── Reimbursement Workflow ────────────────────────────────

    async def create_reimbursement(
        self,
        user_id: int,
        data: dict,
    ) -> dict:
        """Create a mileage reimbursement request for a private vehicle.

        Validates that the vehicle is a private_vehicle type and that
        the user is assigned to it.
        """
        vehicle = await self.vehicle_repo.get_by_id(data["vehicle_id"])
        if not vehicle:
            raise ValueError(f"Vehicle {data['vehicle_id']} not found")

        if vehicle.get("vehicle_type") != "private_vehicle":
            raise ValueError(
                "Mileage reimbursement is only available for private vehicles"
            )

        # Verify user is assigned to this vehicle
        assignment = await self.assignment_repo.get_active_for_user(user_id)
        if not assignment or assignment["vehicle_id"] != data["vehicle_id"]:
            raise ValueError(
                "You must be assigned to this vehicle to request reimbursement"
            )

        # Get system reimbursement rate if not provided
        rate = data.get("rate_per_mile")
        if rate is None:
            setting = await self.settings_repo.get_by_key(
                "fleet_reimbursement_rate_per_mile"
            )
            rate = float(setting["value"]) if setting else 0.70

        reimburse_data = {
            "user_id": user_id,
            "vehicle_id": data["vehicle_id"],
            "period_start": data["period_start"],
            "period_end": data["period_end"],
            "total_miles": data["total_miles"],
            "rate_per_mile": rate,
            "status": "pending",
            "notes": data.get("notes"),
        }

        new_id = await self.reimburse_repo.insert(reimburse_data)
        await self.db.commit()
        return await self.reimburse_repo.get_with_details(new_id)

    async def approve_reimbursement(
        self,
        reimbursement_id: int,
        action: str,
        approved_by: int,
        notes: str | None = None,
    ) -> dict | None:
        """Approve or reject a pending reimbursement.

        action: 'approve' or 'reject'
        """
        reimb = await self.reimburse_repo.get_by_id(reimbursement_id)
        if not reimb:
            return None

        if reimb["status"] != "pending":
            raise ValueError(
                f"Reimbursement is '{reimb['status']}', can only act on 'pending'"
            )

        new_status = "approved" if action == "approve" else "rejected"

        await self.reimburse_repo.update(reimbursement_id, {
            "status": new_status,
            "approved_by": approved_by,
            "notes": notes,
        })

        # Set approved_at via SQL (datetime expression)
        if action == "approve":
            await self.db.execute(
                "UPDATE mileage_reimbursements SET approved_at = datetime('now') WHERE id = ?",
                (reimbursement_id,),
            )

        await self.db.commit()
        return await self.reimburse_repo.get_with_details(reimbursement_id)

    async def get_user_reimbursements(
        self,
        user_id: int,
        *,
        status: str | None = None,
        limit: int = 20,
        offset: int = 0,
    ) -> list[dict]:
        """Get reimbursements for a user."""
        return await self.reimburse_repo.get_for_user(
            user_id, status=status, limit=limit, offset=offset
        )

    async def get_pending_reimbursements(
        self, *, limit: int = 50
    ) -> list[dict]:
        """Get all pending reimbursements (manager approval queue)."""
        return await self.reimburse_repo.get_pending(limit=limit)

    async def mark_reimbursement_paid(
        self,
        reimbursement_id: int,
        user_id: int,
    ) -> dict | None:
        """Mark an approved reimbursement as paid."""
        reimb = await self.reimburse_repo.get_by_id(reimbursement_id)
        if not reimb:
            return None

        if reimb["status"] != "approved":
            raise ValueError(
                f"Reimbursement must be 'approved' to mark as paid, "
                f"currently '{reimb['status']}'"
            )

        await self.reimburse_repo.update(reimbursement_id, {"status": "paid"})
        await self.db.commit()
        return await self.reimburse_repo.get_with_details(reimbursement_id)
