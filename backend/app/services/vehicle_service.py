"""
Vehicle service — vehicle CRUD, driver assignments, fleet dashboard,
vehicle inventory (delegates to StockRepo with location_type='truck').

Handles:
  - Vehicle creation with duplicate-number guard
  - Driver assignments (primary/authorized/temporary) with conflict checks
  - Take-home toggling
  - "My Vehicle" dashboard assembly (bundles vehicle, assignment, deliveries, alerts)
  - Fleet-wide dashboard stats aggregation
  - Vehicle inventory read-through (wraps existing stock system)
  - Warehouse location CRUD with primary-location enforcement
"""

from __future__ import annotations

import logging
from typing import Any

import aiosqlite

from app.repositories.stock_repo import StockRepo
from app.repositories.vehicle_repo import (
    MaintenanceScheduleRepo,
    MileageLogRepo,
    ReimbursementRepo,
    VehicleAssignmentRepo,
    VehicleDeliveryRepo,
    VehicleRepo,
    WarehouseLocationRepo,
)

logger = logging.getLogger(__name__)


class VehicleService:
    """Orchestrates vehicle lifecycle, assignments, and fleet dashboard."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.vehicle_repo = VehicleRepo(db)
        self.assignment_repo = VehicleAssignmentRepo(db)
        self.delivery_repo = VehicleDeliveryRepo(db)
        self.schedule_repo = MaintenanceScheduleRepo(db)
        self.mileage_repo = MileageLogRepo(db)
        self.reimbursement_repo = ReimbursementRepo(db)
        self.stock_repo = StockRepo(db)
        self.warehouse_repo = WarehouseLocationRepo(db)

    # ── Vehicle CRUD ───────────────────────────────────────────

    async def create_vehicle(self, data: dict) -> dict:
        """Create a new vehicle.

        Validates:
          - vehicle_number is unique
          - private_vehicle requires owner_user_id
        """
        # Check unique vehicle number
        existing = await self.vehicle_repo.get_by_number(data["vehicle_number"])
        if existing:
            raise ValueError(
                f"Vehicle number '{data['vehicle_number']}' already exists"
            )

        # Validate private vehicle has owner
        if data.get("vehicle_type") == "private_vehicle" and not data.get("owner_user_id"):
            raise ValueError("Private vehicles require an owner_user_id")

        vehicle_id = await self.vehicle_repo.insert(data)
        await self.db.commit()

        return await self.vehicle_repo.get_with_details(vehicle_id)

    async def update_vehicle(self, vehicle_id: int, data: dict) -> dict | None:
        """Update vehicle fields.  Strips None values before patching."""
        vehicle = await self.vehicle_repo.get_by_id(vehicle_id)
        if not vehicle:
            return None

        # Filter out None values — only send real changes
        patch = {k: v for k, v in data.items() if v is not None}
        if patch:
            await self.vehicle_repo.update(vehicle_id, patch)
            await self.db.commit()

        return await self.vehicle_repo.get_with_details(vehicle_id)

    async def deactivate_vehicle(self, vehicle_id: int) -> bool:
        """Soft-delete: set is_active=0, status='retired'."""
        vehicle = await self.vehicle_repo.get_by_id(vehicle_id)
        if not vehicle:
            return False

        await self.vehicle_repo.update(vehicle_id, {
            "is_active": 0,
            "status": "retired",
        })
        await self.db.commit()
        return True

    # ── Driver Assignments ─────────────────────────────────────

    async def assign_driver(
        self,
        vehicle_id: int,
        data: dict,
    ) -> dict:
        """Assign a driver to a vehicle.

        Business rules:
          - Only one primary driver per vehicle at a time
          - If assigning a new primary, end the old primary assignment first
          - Same user can't have duplicate active assignments of the same type
        """
        vehicle = await self.vehicle_repo.get_by_id(vehicle_id)
        if not vehicle:
            raise ValueError(f"Vehicle {vehicle_id} not found")

        user_id = data["user_id"]
        assignment_type = data.get("assignment_type", "primary")

        # If assigning as primary, end existing primary (if different user)
        if assignment_type == "primary":
            current_primary = await self.assignment_repo.get_primary_driver(vehicle_id)
            if current_primary and current_primary["user_id"] != user_id:
                await self.assignment_repo.end_assignment(
                    vehicle_id, current_primary["user_id"]
                )
            elif current_primary and current_primary["user_id"] == user_id:
                # Already assigned as primary — just update if needed
                patch = {
                    k: v for k, v in data.items()
                    if k not in ("user_id", "vehicle_id") and v is not None
                }
                if patch:
                    await self.assignment_repo.update(current_primary["id"], patch)
                    await self.db.commit()
                return dict(current_primary)

        # Check for duplicate active assignment of same type
        active = await self.assignment_repo.get_active_for_vehicle(vehicle_id)
        for a in active:
            if a["user_id"] == user_id and a["assignment_type"] == assignment_type:
                return dict(a)  # Already exists

        # Create assignment
        from datetime import date as _date

        assignment_data = {
            "vehicle_id": vehicle_id,
            "user_id": user_id,
            "assignment_type": assignment_type,
            "is_take_home": int(data.get("is_take_home", False)),
            "home_to_shop_miles": data.get("home_to_shop_miles"),
            "home_address_street": data.get("home_address_street"),
            "home_address_city": data.get("home_address_city"),
            "home_address_state": data.get("home_address_state"),
            "home_address_zip": data.get("home_address_zip"),
            "start_date": data.get("start_date") or _date.today().isoformat(),
            "notes": data.get("notes"),
        }

        new_id = await self.assignment_repo.insert(assignment_data)

        # Update user's default_truck_id if this is a primary assignment
        if assignment_type == "primary":
            await self.db.execute(
                "UPDATE users SET default_truck_id = ? WHERE id = ?",
                (vehicle_id, user_id),
            )

        await self.db.commit()
        return await self.assignment_repo.get_by_id(new_id)

    async def unassign_driver(self, vehicle_id: int, user_id: int) -> bool:
        """End all active assignments for a user on a vehicle."""
        result = await self.assignment_repo.end_assignment(vehicle_id, user_id)

        # Clear user's default_truck_id if this was their primary vehicle
        if result:
            vehicle = await self.vehicle_repo.get_by_user(user_id)
            if not vehicle:
                await self.db.execute(
                    "UPDATE users SET default_truck_id = NULL WHERE id = ?",
                    (user_id,),
                )
                await self.db.commit()

        return result

    async def toggle_take_home(
        self, vehicle_id: int, user_id: int, is_take_home: bool
    ) -> bool:
        """Toggle the take-home flag for a user's assignment."""
        active = await self.assignment_repo.get_active_for_vehicle(vehicle_id)
        for a in active:
            if a["user_id"] == user_id:
                await self.assignment_repo.update(a["id"], {
                    "is_take_home": int(is_take_home),
                })
                await self.db.commit()
                return True
        return False

    # ── My Vehicle Dashboard ───────────────────────────────────

    async def get_my_vehicle_dashboard(self, user_id: int) -> dict:
        """Assemble the driver's personal vehicle dashboard.

        Bundles: vehicle info, assignment, today's mileage, pending
        deliveries, and maintenance alerts — all in one call.
        """
        from datetime import date

        vehicle = await self.vehicle_repo.get_by_user(user_id)
        if not vehicle:
            return {"vehicle": None}

        vehicle_id = vehicle["id"]
        vehicle_details = await self.vehicle_repo.get_with_details(vehicle_id)

        # Get the user's active assignment for this vehicle
        assignments = await self.assignment_repo.get_active_for_user(user_id)
        assignment = next(
            (a for a in assignments if a["vehicle_id"] == vehicle_id), None
        )

        # Today's mileage log
        today = date.today().isoformat()
        todays_mileage = await self.mileage_repo.get_daily(vehicle_id, today)

        # Pending delivery items
        pending_deliveries = await self.delivery_repo.get_for_vehicle(
            vehicle_id, status="assigned", limit=20
        )
        # Also include loaded/in_transit items
        loaded = await self.delivery_repo.get_for_vehicle(
            vehicle_id, status="loaded", limit=20
        )
        in_transit = await self.delivery_repo.get_for_vehicle(
            vehicle_id, status="in_transit", limit=20
        )
        all_pending = list(pending_deliveries) + list(loaded) + list(in_transit)

        # Maintenance alerts (overdue + upcoming 14 days)
        overdue = await self.schedule_repo.get_overdue(vehicle_id=vehicle_id)
        upcoming = await self.schedule_repo.get_upcoming(
            days_ahead=14, vehicle_id=vehicle_id
        )

        # Build maintenance alert objects
        alerts = []
        for item in overdue:
            alerts.append({
                **dict(item),
                "is_overdue": True,
                "urgency": "overdue",
            })
        for item in upcoming:
            days = item.get("days_until_due", 999)
            alerts.append({
                **dict(item),
                "is_overdue": False,
                "urgency": "soon" if days <= 7 else "normal",
            })

        # Recent mileage (last 7 entries)
        recent_mileage = await self.mileage_repo.get_for_vehicle(
            vehicle_id, limit=7
        )

        return {
            "vehicle": dict(vehicle_details) if vehicle_details else None,
            "assignment": dict(assignment) if assignment else None,
            "todays_mileage": dict(todays_mileage) if todays_mileage else None,
            "pending_deliveries": [dict(d) for d in all_pending],
            "maintenance_alerts": alerts,
            "recent_mileage": [dict(m) for m in recent_mileage],
        }

    # ── Fleet Dashboard ────────────────────────────────────────

    async def get_fleet_dashboard(self) -> dict:
        """Assemble fleet-wide dashboard stats.

        Combines vehicle counts, monthly miles, maintenance alerts,
        and pending reimbursement count.
        """
        from app.repositories.vehicle_repo import MaintenanceRecordRepo

        fleet_stats = await self.vehicle_repo.get_fleet_stats()
        monthly_miles = await self.mileage_repo.get_fleet_month_miles()

        overdue = await self.schedule_repo.get_overdue()
        upcoming = await self.schedule_repo.get_upcoming(days_ahead=30)

        pending_reimbursements = await self.reimbursement_repo.get_pending_count()

        # Monthly maintenance costs
        record_repo = MaintenanceRecordRepo(self.db)
        from datetime import date
        month_start = date.today().replace(day=1).isoformat()
        month_end = date.today().isoformat()
        cost_summary = await record_repo.get_cost_summary(
            0,  # vehicle_id=0 won't match, need fleet-wide
            period_start=month_start,
            period_end=month_end,
        )
        # For fleet-wide cost, query directly
        cursor = await self.db.execute(
            """
            SELECT COALESCE(SUM(cost), 0) AS total
            FROM vehicle_maintenance_records
            WHERE service_date >= date('now', 'start of month')
            """
        )
        row = await cursor.fetchone()
        monthly_cost = row["total"] if row else 0

        # Count vehicles needing state inspection (registration_expiry approaching)
        cursor = await self.db.execute(
            """
            SELECT COUNT(*) AS cnt FROM vehicles
            WHERE is_active = 1
              AND registration_expiry IS NOT NULL
              AND registration_expiry <= date('now', '+30 days')
            """
        )
        row = await cursor.fetchone()
        vehicles_needing_inspection = row["cnt"] if row else 0

        return {
            **fleet_stats,
            "total_fleet_miles_month": monthly_miles,
            "total_maintenance_cost_month": monthly_cost,
            "overdue_maintenance_count": len(overdue),
            "upcoming_maintenance_count": len(upcoming),
            "pending_reimbursements": pending_reimbursements,
            "vehicles_needing_inspection": vehicles_needing_inspection,
        }

    # ── Vehicle Inventory (Stock System) ───────────────────────

    async def get_vehicle_inventory(
        self, vehicle_id: int, *, search: str | None = None
    ) -> list[dict]:
        """Get parts inventory on a vehicle.

        Delegates to the existing stock system with location_type='truck'.
        """
        cursor = await self.db.execute(
            """
            SELECT s.id, s.part_id, s.qty, s.supplier_id,
                   p.code AS part_number, p.name AS part_description,
                   pc.name AS category, b.name AS brand,
                   sup.name AS supplier_name
            FROM stock s
            JOIN parts p ON p.id = s.part_id
            LEFT JOIN part_categories pc ON pc.id = p.category_id
            LEFT JOIN brands b ON b.id = p.brand_id
            LEFT JOIN suppliers sup ON sup.id = s.supplier_id
            WHERE s.location_type = 'truck' AND s.location_id = ?
              AND s.qty > 0
            """
            + (" AND (p.code LIKE ? OR p.name LIKE ?)" if search else "")
            + " ORDER BY p.code ASC",
            (vehicle_id,) + ((f"%{search}%", f"%{search}%") if search else ()),
        )
        return await cursor.fetchall()

    async def add_to_vehicle_inventory(
        self,
        vehicle_id: int,
        part_id: int,
        qty: int,
        user_id: int,
        *,
        from_location_type: str = "warehouse",
        from_location_id: int = 1,
        notes: str | None = None,
    ) -> dict:
        """Add parts to a vehicle (stock movement from source to truck).

        Creates a stock_movement record and updates stock levels.
        """
        # Verify vehicle exists
        vehicle = await self.vehicle_repo.get_by_id(vehicle_id)
        if not vehicle:
            raise ValueError(f"Vehicle {vehicle_id} not found")

        # Create stock movement
        await self.db.execute(
            """
            INSERT INTO stock_movements (
                part_id, qty, movement_type,
                from_location_type, from_location_id,
                to_location_type, to_location_id,
                performed_by, notes
            ) VALUES (?, ?, 'transfer', ?, ?, 'truck', ?, ?, ?)
            """,
            (
                part_id, qty,
                from_location_type, from_location_id,
                vehicle_id,
                user_id,
                notes or f"Added to vehicle {vehicle.get('vehicle_number', vehicle_id)}",
            ),
        )

        # Decrement source stock
        await self.db.execute(
            """
            UPDATE stock SET qty = MAX(qty - ?, 0), updated_at = datetime('now')
            WHERE part_id = ? AND location_type = ? AND location_id = ?
            """,
            (qty, part_id, from_location_type, from_location_id),
        )

        # Increment truck stock (upsert)
        await self.stock_repo.add_stock(part_id, "truck", vehicle_id, qty)

        return {"part_id": part_id, "qty_added": qty, "vehicle_id": vehicle_id}

    async def remove_from_vehicle_inventory(
        self,
        vehicle_id: int,
        part_id: int,
        qty: int,
        user_id: int,
        *,
        to_location_type: str = "warehouse",
        to_location_id: int = 1,
        notes: str | None = None,
    ) -> dict:
        """Remove parts from a vehicle back to a destination.

        Creates a stock_movement record and updates stock levels.
        """
        vehicle = await self.vehicle_repo.get_by_id(vehicle_id)
        if not vehicle:
            raise ValueError(f"Vehicle {vehicle_id} not found")

        # Create stock movement
        await self.db.execute(
            """
            INSERT INTO stock_movements (
                part_id, qty, movement_type,
                from_location_type, from_location_id,
                to_location_type, to_location_id,
                performed_by, notes
            ) VALUES (?, ?, 'transfer', 'truck', ?, ?, ?, ?, ?)
            """,
            (
                part_id, qty,
                vehicle_id,
                to_location_type, to_location_id,
                user_id,
                notes or f"Removed from vehicle {vehicle.get('vehicle_number', vehicle_id)}",
            ),
        )

        # Decrement truck stock
        await self.db.execute(
            """
            UPDATE stock SET qty = MAX(qty - ?, 0), updated_at = datetime('now')
            WHERE part_id = ? AND location_type = 'truck' AND location_id = ?
            """,
            (qty, part_id, vehicle_id),
        )

        # Increment destination stock
        await self.stock_repo.add_stock(part_id, to_location_type, to_location_id, qty)

        return {"part_id": part_id, "qty_removed": qty, "vehicle_id": vehicle_id}

    # ── Warehouse Locations ────────────────────────────────────

    async def create_warehouse_location(self, data: dict) -> dict:
        """Create a new warehouse/shop location.

        If is_primary=True, clears existing primary first.
        """
        if data.get("is_primary"):
            await self.warehouse_repo.set_primary(-1)  # Clear existing

        new_id = await self.warehouse_repo.insert(data)

        if data.get("is_primary"):
            await self.warehouse_repo.set_primary(new_id)

        await self.db.commit()
        return await self.warehouse_repo.get_by_id(new_id)

    async def update_warehouse_location(
        self, location_id: int, data: dict
    ) -> dict | None:
        """Update a warehouse location.  Handles primary flag toggle."""
        location = await self.warehouse_repo.get_by_id(location_id)
        if not location:
            return None

        patch = {k: v for k, v in data.items() if v is not None}

        # Handle primary flag — ensure only one is primary
        if patch.get("is_primary"):
            await self.warehouse_repo.set_primary(location_id)
            patch.pop("is_primary", None)  # Already handled

        if patch:
            await self.warehouse_repo.update(location_id, patch)

        await self.db.commit()
        return await self.warehouse_repo.get_by_id(location_id)

    async def deactivate_warehouse_location(self, location_id: int) -> bool:
        """Soft-delete a warehouse location."""
        location = await self.warehouse_repo.get_by_id(location_id)
        if not location:
            return False

        await self.warehouse_repo.update(location_id, {"is_active": 0})
        await self.db.commit()
        return True
