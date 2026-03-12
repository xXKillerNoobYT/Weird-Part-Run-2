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
    JobTrailerRepo,
    MaintenanceScheduleRepo,
    MileageLogRepo,
    ReimbursementRepo,
    TrailerLocationEventRepo,
    VehicleAssignmentRepo,
    VehicleDeliveryRepo,
    VehicleRepo,
    WarehouseLocationRepo,
)
from app.services.movement_service import MovementService
from app.models.warehouse import MovementLineItem, MovementRequest

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
        self.trailer_repo = JobTrailerRepo(db)
        self.trailer_location_repo = TrailerLocationEventRepo(db)

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
        """Add parts to a vehicle via MovementService (atomic, supplier-preserving).

        Routes through the standard movement engine so FIFO, audit trail,
        and supplier tracking are all handled consistently.
        """
        vehicle = await self.vehicle_repo.get_by_id(vehicle_id)
        if not vehicle:
            raise ValueError(f"Vehicle {vehicle_id} not found")

        movement_service = MovementService(self.db)
        req = MovementRequest(
            from_location_type=from_location_type,
            from_location_id=from_location_id,
            to_location_type="truck",
            to_location_id=vehicle_id,
            items=[MovementLineItem(part_id=part_id, qty=qty)],
            reason="Vehicle Stock",
            notes=notes or f"Added to vehicle {vehicle.get('vehicle_number', vehicle_id)}",
        )
        result = await movement_service.execute_movement(req, performed_by=user_id)
        return {
            "part_id": part_id,
            "qty_added": qty,
            "vehicle_id": vehicle_id,
            "movement_count": len(result.movements),
        }

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
        """Remove parts from a vehicle via MovementService (atomic, supplier-preserving).

        Routes through the standard movement engine for FIFO order,
        audit trail, and supplier tracking consistency.
        """
        vehicle = await self.vehicle_repo.get_by_id(vehicle_id)
        if not vehicle:
            raise ValueError(f"Vehicle {vehicle_id} not found")

        movement_service = MovementService(self.db)
        req = MovementRequest(
            from_location_type="truck",
            from_location_id=vehicle_id,
            to_location_type=to_location_type,
            to_location_id=to_location_id,
            items=[MovementLineItem(part_id=part_id, qty=qty)],
            reason="Vehicle Return",
            notes=notes or f"Removed from vehicle {vehicle.get('vehicle_number', vehicle_id)}",
        )
        result = await movement_service.execute_movement(req, performed_by=user_id)
        return {
            "part_id": part_id,
            "qty_removed": qty,
            "vehicle_id": vehicle_id,
            "movement_count": len(result.movements),
        }

    # ── Job Trailers ────────────────────────────────────────────

    async def list_trailers(self, *, search: str | None = None) -> list[dict]:
        return await self.trailer_repo.list_active(search=search)

    async def create_trailer(self, data: dict) -> dict:
        existing = await self.trailer_repo.get_by_code(data["trailer_code"])
        if existing:
            raise ValueError(f"Trailer code '{data['trailer_code']}' already exists")

        trailer_id = await self.trailer_repo.insert(data)
        await self.db.commit()
        trailer = await self.trailer_repo.get_by_id(trailer_id)
        return dict(trailer) if trailer else {}

    async def update_trailer(self, trailer_id: int, data: dict) -> dict | None:
        trailer = await self.trailer_repo.get_by_id(trailer_id)
        if not trailer:
            return None
        patch = {k: v for k, v in data.items() if v is not None}
        if patch:
            await self.trailer_repo.update(trailer_id, patch)
            await self.db.commit()
        updated = await self.trailer_repo.get_by_id(trailer_id)
        return dict(updated) if updated else None

    async def deactivate_trailer(self, trailer_id: int) -> bool:
        trailer = await self.trailer_repo.get_by_id(trailer_id)
        if not trailer:
            return False
        await self.trailer_repo.update(trailer_id, {"is_active": 0, "status": "inactive"})
        await self.db.commit()
        return True

    async def get_trailer_inventory(
        self, trailer_id: int, *, search: str | None = None
    ) -> list[dict]:
        trailer = await self.trailer_repo.get_by_id(trailer_id)
        if not trailer:
            raise ValueError(f"Trailer {trailer_id} not found")

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
            WHERE s.location_type = 'trailer' AND s.location_id = ?
              AND s.qty > 0
            """
            + (" AND (p.code LIKE ? OR p.name LIKE ?)" if search else "")
            + " ORDER BY p.code ASC",
            (trailer_id,) + ((f"%{search}%", f"%{search}%") if search else ()),
        )
        return await cursor.fetchall()

    async def preload_trailer_inventory(
        self,
        trailer_id: int,
        part_id: int,
        qty: int,
        user_id: int,
        *,
        from_location_type: str = "warehouse",
        from_location_id: int = 1,
        notes: str | None = None,
    ) -> dict:
        trailer = await self.trailer_repo.get_by_id(trailer_id)
        if not trailer:
            raise ValueError(f"Trailer {trailer_id} not found")

        movement_service = MovementService(self.db)
        req = MovementRequest(
            from_location_type=from_location_type,
            from_location_id=from_location_id,
            to_location_type="trailer",
            to_location_id=trailer_id,
            items=[MovementLineItem(part_id=part_id, qty=qty)],
            reason="Trailer Preload",
            notes=notes or f"Preload to trailer {trailer.get('trailer_code', trailer_id)}",
        )
        result = await movement_service.execute_movement(req, performed_by=user_id)
        return {
            "part_id": part_id,
            "qty_added": qty,
            "trailer_id": trailer_id,
            "movement_count": len(result.movements),
        }

    async def consume_trailer_inventory_to_job(
        self,
        trailer_id: int,
        part_id: int,
        qty: int,
        job_id: int,
        user_id: int,
        *,
        notes: str | None = None,
        photo_path: str | None = None,
        scan_confirmed: bool = False,
    ) -> dict:
        trailer = await self.trailer_repo.get_by_id(trailer_id)
        if not trailer:
            raise ValueError(f"Trailer {trailer_id} not found")

        movement_service = MovementService(self.db)
        req = MovementRequest(
            from_location_type="trailer",
            from_location_id=trailer_id,
            to_location_type="job",
            to_location_id=job_id,
            items=[MovementLineItem(part_id=part_id, qty=qty)],
            reason="Trailer Job Pull",
            notes=notes or f"Consumed from trailer {trailer.get('trailer_code', trailer_id)} to job",
            job_id=job_id,
            photo_path=photo_path,
            scan_confirmed=scan_confirmed,
        )
        result = await movement_service.execute_movement(req, performed_by=user_id)
        return {
            "part_id": part_id,
            "qty_consumed": qty,
            "trailer_id": trailer_id,
            "job_id": job_id,
            "movement_count": len(result.movements),
        }

    async def return_trailer_inventory(
        self,
        trailer_id: int,
        part_id: int,
        qty: int,
        user_id: int,
        *,
        to_location_type: str = "warehouse",
        to_location_id: int = 1,
        notes: str | None = None,
    ) -> dict:
        trailer = await self.trailer_repo.get_by_id(trailer_id)
        if not trailer:
            raise ValueError(f"Trailer {trailer_id} not found")

        movement_service = MovementService(self.db)
        req = MovementRequest(
            from_location_type="trailer",
            from_location_id=trailer_id,
            to_location_type=to_location_type,
            to_location_id=to_location_id,
            items=[MovementLineItem(part_id=part_id, qty=qty)],
            reason="Trailer Return",
            notes=notes or f"Returned from trailer {trailer.get('trailer_code', trailer_id)}",
        )
        result = await movement_service.execute_movement(req, performed_by=user_id)
        return {
            "part_id": part_id,
            "qty_returned": qty,
            "trailer_id": trailer_id,
            "movement_count": len(result.movements),
        }

    async def record_trailer_location_event(
        self,
        trailer_id: int,
        data: dict,
        *,
        recorded_by: int,
    ) -> dict:
        trailer = await self.trailer_repo.get_by_id(trailer_id)
        if not trailer:
            raise ValueError(f"Trailer {trailer_id} not found")

        payload = {
            **data,
            "trailer_id": trailer_id,
            "recorded_by": recorded_by,
        }
        event_id = await self.trailer_location_repo.insert(payload)

        # Keep trailer snapshot columns aligned for quick list rendering.
        patch: dict[str, Any] = {}
        if data.get("job_id") is not None:
            patch["current_job_id"] = data.get("job_id")
        if data.get("warehouse_id") is not None and data.get("location_kind") == "warehouse":
            patch["home_warehouse_id"] = data.get("warehouse_id")
        if data.get("event_type") == "departed":
            patch["status"] = "in_transit"
        elif data.get("event_type") in {"arrived_job", "arrived_warehouse", "check_in", "manual_update"}:
            patch["status"] = "active"
        if patch:
            await self.trailer_repo.update(trailer_id, patch)

        await self.db.commit()
        event = await self.trailer_location_repo.get_by_id(event_id)
        return dict(event) if event else {}

    async def get_trailer_location(self, trailer_id: int) -> dict | None:
        trailer = await self.trailer_repo.get_by_id(trailer_id)
        if not trailer:
            return None
        latest = await self.trailer_location_repo.get_latest_for_trailer(trailer_id)
        if not latest:
            return {
                "trailer_id": trailer_id,
                "location_kind": "other",
                "event_type": "manual_update",
                "message": "No location events recorded",
            }
        return dict(latest)

    async def list_trailer_location_events(self, trailer_id: int, *, limit: int = 100) -> list[dict]:
        trailer = await self.trailer_repo.get_by_id(trailer_id)
        if not trailer:
            raise ValueError(f"Trailer {trailer_id} not found")
        return await self.trailer_location_repo.list_for_trailer(trailer_id, limit=limit)

    # ── Trailer Stock Templates ────────────────────────────────

    async def list_trailer_templates(
        self,
        *,
        trailer_id: int | None = None,
        include_global: bool = True,
    ) -> list[dict]:
        """List stock templates, optionally scoped to a trailer.

        When trailer_id is provided and include_global=True (default),
        returns both trailer-specific *and* global (trailer_id IS NULL) templates.
        """
        if trailer_id is not None:
            if include_global:
                cursor = await self.db.execute(
                    """
                    SELECT t.*, jt.trailer_code
                    FROM trailer_stock_templates t
                    LEFT JOIN job_trailers jt ON jt.id = t.trailer_id
                    WHERE t.trailer_id = ? OR t.trailer_id IS NULL
                    ORDER BY t.trailer_id IS NULL ASC, t.name ASC
                    """,
                    (trailer_id,),
                )
            else:
                cursor = await self.db.execute(
                    """
                    SELECT t.*, jt.trailer_code
                    FROM trailer_stock_templates t
                    LEFT JOIN job_trailers jt ON jt.id = t.trailer_id
                    WHERE t.trailer_id = ?
                    ORDER BY t.name ASC
                    """,
                    (trailer_id,),
                )
        else:
            cursor = await self.db.execute(
                """
                SELECT t.*, jt.trailer_code
                FROM trailer_stock_templates t
                LEFT JOIN job_trailers jt ON jt.id = t.trailer_id
                ORDER BY t.trailer_id IS NULL ASC, t.name ASC
                """,
            )
        return await cursor.fetchall()

    async def get_trailer_template(self, template_id: int) -> dict | None:
        """Get a single template with its lines."""
        cursor = await self.db.execute(
            """
            SELECT t.*, jt.trailer_code
            FROM trailer_stock_templates t
            LEFT JOIN job_trailers jt ON jt.id = t.trailer_id
            WHERE t.id = ?
            """,
            (template_id,),
        )
        template = await cursor.fetchone()
        if not template:
            return None

        lines_cursor = await self.db.execute(
            """
            SELECT tl.*, p.code AS part_code, p.name AS part_name,
                   pc.name AS category_name, b.name AS brand_name
            FROM trailer_stock_template_lines tl
            JOIN parts p ON p.id = tl.part_id
            LEFT JOIN part_categories pc ON pc.id = p.category_id
            LEFT JOIN brands b ON b.id = p.brand_id
            WHERE tl.template_id = ?
            ORDER BY p.code ASC
            """,
            (template_id,),
        )
        lines = await lines_cursor.fetchall()
        result = dict(template)
        result["lines"] = [dict(ln) for ln in lines]
        return result

    async def create_trailer_template(self, data: dict) -> dict:
        """Create a new stock template.

        data keys: name, trailer_id (optional), is_default, notes, lines[]
        """
        # If setting as default, clear other defaults for same scope
        if data.get("is_default"):
            if data.get("trailer_id"):
                await self.db.execute(
                    "UPDATE trailer_stock_templates SET is_default = 0 WHERE trailer_id = ?",
                    (data["trailer_id"],),
                )
            else:
                await self.db.execute(
                    "UPDATE trailer_stock_templates SET is_default = 0 WHERE trailer_id IS NULL",
                )

        cursor = await self.db.execute(
            """
            INSERT INTO trailer_stock_templates (trailer_id, name, is_default, notes)
            VALUES (?, ?, ?, ?)
            """,
            (
                data.get("trailer_id"),
                data["name"],
                1 if data.get("is_default") else 0,
                data.get("notes"),
            ),
        )
        template_id = cursor.lastrowid

        # Insert lines if provided
        for line in data.get("lines", []):
            await self.db.execute(
                """
                INSERT INTO trailer_stock_template_lines
                    (template_id, part_id, target_qty, min_qty)
                VALUES (?, ?, ?, ?)
                """,
                (
                    template_id,
                    line["part_id"],
                    line["target_qty"],
                    line.get("min_qty", 0),
                ),
            )

        await self.db.commit()
        return await self.get_trailer_template(template_id)

    async def update_trailer_template(self, template_id: int, data: dict) -> dict | None:
        """Update template header and optionally replace all lines."""
        cursor = await self.db.execute(
            "SELECT * FROM trailer_stock_templates WHERE id = ?", (template_id,)
        )
        existing = await cursor.fetchone()
        if not existing:
            return None

        # Handle default flag
        if data.get("is_default"):
            trailer_id = data.get("trailer_id", existing["trailer_id"])
            if trailer_id:
                await self.db.execute(
                    "UPDATE trailer_stock_templates SET is_default = 0 WHERE trailer_id = ? AND id != ?",
                    (trailer_id, template_id),
                )
            else:
                await self.db.execute(
                    "UPDATE trailer_stock_templates SET is_default = 0 WHERE trailer_id IS NULL AND id != ?",
                    (template_id,),
                )

        # Update header
        sets = []
        params = []
        for field in ("name", "trailer_id", "is_default", "notes"):
            if field in data:
                sets.append(f"{field} = ?")
                val = data[field]
                if field == "is_default":
                    val = 1 if val else 0
                params.append(val)
        if sets:
            sets.append("updated_at = datetime('now')")
            params.append(template_id)
            await self.db.execute(
                f"UPDATE trailer_stock_templates SET {', '.join(sets)} WHERE id = ?",
                params,
            )

        # Replace lines if provided
        if "lines" in data:
            await self.db.execute(
                "DELETE FROM trailer_stock_template_lines WHERE template_id = ?",
                (template_id,),
            )
            for line in data["lines"]:
                await self.db.execute(
                    """
                    INSERT INTO trailer_stock_template_lines
                        (template_id, part_id, target_qty, min_qty)
                    VALUES (?, ?, ?, ?)
                    """,
                    (
                        template_id,
                        line["part_id"],
                        line["target_qty"],
                        line.get("min_qty", 0),
                    ),
                )

        await self.db.commit()
        return await self.get_trailer_template(template_id)

    async def delete_trailer_template(self, template_id: int) -> bool:
        """Delete a template and its lines (CASCADE via FK)."""
        cursor = await self.db.execute(
            "SELECT id FROM trailer_stock_templates WHERE id = ?", (template_id,)
        )
        if not await cursor.fetchone():
            return False
        await self.db.execute(
            "DELETE FROM trailer_stock_templates WHERE id = ?", (template_id,)
        )
        await self.db.commit()
        return True

    async def get_restock_guidance(self, trailer_id: int) -> dict:
        """Compare trailer actual stock vs template targets.

        Uses the default template for the trailer (or global default if none).
        Returns per-line: part info, target_qty, min_qty, actual_qty, deficit.
        """
        # Find applicable template: trailer-specific default, then global default
        cursor = await self.db.execute(
            """
            SELECT id FROM trailer_stock_templates
            WHERE trailer_id = ? AND is_default = 1
            LIMIT 1
            """,
            (trailer_id,),
        )
        template = await cursor.fetchone()
        if not template:
            cursor = await self.db.execute(
                """
                SELECT id FROM trailer_stock_templates
                WHERE trailer_id IS NULL AND is_default = 1
                LIMIT 1
                """,
            )
            template = await cursor.fetchone()

        if not template:
            return {
                "trailer_id": trailer_id,
                "template_id": None,
                "message": "No default template found",
                "lines": [],
                "summary": {"total_parts": 0, "parts_below_min": 0, "parts_below_target": 0},
            }

        template_id = template["id"]

        # Get template lines + actual stock
        cursor = await self.db.execute(
            """
            SELECT tl.part_id, tl.target_qty, tl.min_qty,
                   p.code AS part_code, p.name AS part_name,
                   pc.name AS category_name,
                   COALESCE(SUM(s.qty), 0) AS actual_qty
            FROM trailer_stock_template_lines tl
            JOIN parts p ON p.id = tl.part_id
            LEFT JOIN part_categories pc ON pc.id = p.category_id
            LEFT JOIN stock s ON s.part_id = tl.part_id
                              AND s.location_type = 'trailer'
                              AND s.location_id = ?
            WHERE tl.template_id = ?
            GROUP BY tl.part_id
            ORDER BY p.code ASC
            """,
            (trailer_id, template_id),
        )
        rows = await cursor.fetchall()

        lines = []
        below_min = 0
        below_target = 0
        for row in rows:
            actual = row["actual_qty"]
            target = row["target_qty"]
            min_qty = row["min_qty"]
            deficit = max(target - actual, 0)
            if actual < min_qty:
                below_min += 1
            if actual < target:
                below_target += 1
            lines.append({
                "part_id": row["part_id"],
                "part_code": row["part_code"],
                "part_name": row["part_name"],
                "category_name": row["category_name"],
                "target_qty": target,
                "min_qty": min_qty,
                "actual_qty": actual,
                "deficit": deficit,
                "status": "critical" if actual < min_qty else ("low" if actual < target else "ok"),
            })

        return {
            "trailer_id": trailer_id,
            "template_id": template_id,
            "lines": lines,
            "summary": {
                "total_parts": len(lines),
                "parts_below_min": below_min,
                "parts_below_target": below_target,
            },
        }

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

    # ── Vehicle Transfers ──────────────────────────────────────

    async def request_transfer(self, data: dict, requested_by: int) -> dict:
        """Request a vehicle transfer between warehouses / shops."""
        from app.repositories.transfer_repo import VehicleTransferRepo

        vehicle = await self.vehicle_repo.get_by_id(data["vehicle_id"])
        if not vehicle:
            raise ValueError(f"Vehicle {data['vehicle_id']} not found")

        transfer_repo = VehicleTransferRepo(self.db)
        insert_data = {
            "vehicle_id": data["vehicle_id"],
            "from_warehouse_id": data.get("from_warehouse_id"),
            "to_warehouse_id": data["to_warehouse_id"],
            "requested_by": requested_by,
            "reason": data.get("reason"),
            "notes": data.get("notes"),
        }
        new_id = await transfer_repo.insert(insert_data)
        await self.db.commit()
        return await transfer_repo.get_with_details(new_id)

    async def approve_transfer(self, transfer_id: int, approved_by: int) -> dict:
        """Approve a pending transfer request."""
        from app.repositories.transfer_repo import VehicleTransferRepo

        transfer_repo = VehicleTransferRepo(self.db)
        transfer = await transfer_repo.get_by_id(transfer_id)
        if not transfer:
            raise ValueError(f"Transfer {transfer_id} not found")
        if transfer["status"] != "requested":
            raise ValueError(f"Transfer is '{transfer['status']}', not 'requested'")

        await transfer_repo.update(transfer_id, {
            "status": "approved",
            "approved_by": approved_by,
            "approved_at": "datetime('now')",
        })
        # Use raw SQL for datetime function
        await self.db.execute(
            "UPDATE vehicle_transfers SET approved_by = ?, approved_at = datetime('now') WHERE id = ?",
            (approved_by, transfer_id),
        )
        await self.db.commit()
        return await transfer_repo.get_with_details(transfer_id)

    async def complete_transfer(self, transfer_id: int) -> dict:
        """Mark a transfer as completed — vehicle arrives at destination."""
        from app.repositories.transfer_repo import VehicleTransferRepo

        transfer_repo = VehicleTransferRepo(self.db)
        transfer = await transfer_repo.get_by_id(transfer_id)
        if not transfer:
            raise ValueError(f"Transfer {transfer_id} not found")
        if transfer["status"] not in ("approved", "in_transit"):
            raise ValueError(
                f"Transfer is '{transfer['status']}', must be 'approved' or 'in_transit'"
            )

        await self.db.execute(
            "UPDATE vehicle_transfers SET status = 'completed', completed_at = datetime('now') WHERE id = ?",
            (transfer_id,),
        )
        await self.db.commit()
        return await transfer_repo.get_with_details(transfer_id)

    async def start_transit(self, transfer_id: int) -> dict:
        """Mark an approved transfer as in_transit."""
        from app.repositories.transfer_repo import VehicleTransferRepo

        transfer_repo = VehicleTransferRepo(self.db)
        transfer = await transfer_repo.get_by_id(transfer_id)
        if not transfer:
            raise ValueError(f"Transfer {transfer_id} not found")
        if transfer["status"] != "approved":
            raise ValueError(f"Transfer is '{transfer['status']}', not 'approved'")

        await transfer_repo.update(transfer_id, {"status": "in_transit"})
        await self.db.commit()
        return await transfer_repo.get_with_details(transfer_id)

    async def cancel_transfer(self, transfer_id: int, reason: str | None = None) -> dict:
        """Cancel a transfer (from any non-completed state)."""
        from app.repositories.transfer_repo import VehicleTransferRepo

        transfer_repo = VehicleTransferRepo(self.db)
        transfer = await transfer_repo.get_by_id(transfer_id)
        if not transfer:
            raise ValueError(f"Transfer {transfer_id} not found")
        if transfer["status"] == "completed":
            raise ValueError("Cannot cancel a completed transfer")

        patch = {"status": "cancelled"}
        if reason:
            patch["notes"] = (transfer.get("notes") or "") + f"\n[Cancelled] {reason}"
        await transfer_repo.update(transfer_id, patch)
        await self.db.commit()
        return await transfer_repo.get_with_details(transfer_id)

    async def list_transfers(
        self,
        *,
        status: str | None = None,
        vehicle_id: int | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """List vehicle transfers with filters."""
        from app.repositories.transfer_repo import VehicleTransferRepo

        transfer_repo = VehicleTransferRepo(self.db)
        return await transfer_repo.list_transfers(
            status=status, vehicle_id=vehicle_id, limit=limit, offset=offset
        )

    # ── Document Expiry Alerts ─────────────────────────────────

    async def get_document_alerts(self, days_ahead: int = 30) -> list[dict]:
        """Find vehicles with insurance or registration expiring within N days.

        Returns a list of alert objects with vehicle details and expiry info.
        """
        cursor = await self.db.execute(
            """
            SELECT v.id, v.vehicle_number, v.year, v.make, v.model, v.status,
                   v.insurance_expiry, v.registration_expiry,
                   CASE
                     WHEN v.insurance_expiry IS NOT NULL
                          AND v.insurance_expiry <= date('now', ? || ' days')
                     THEN 1 ELSE 0
                   END AS insurance_expiring,
                   CASE
                     WHEN v.registration_expiry IS NOT NULL
                          AND v.registration_expiry <= date('now', ? || ' days')
                     THEN 1 ELSE 0
                   END AS registration_expiring,
                   julianday(v.insurance_expiry) - julianday('now') AS insurance_days_left,
                   julianday(v.registration_expiry) - julianday('now') AS registration_days_left
            FROM vehicles v
            WHERE v.is_active = 1
              AND (
                (v.insurance_expiry IS NOT NULL AND v.insurance_expiry <= date('now', ? || ' days'))
                OR
                (v.registration_expiry IS NOT NULL AND v.registration_expiry <= date('now', ? || ' days'))
              )
            ORDER BY
              COALESCE(
                LEAST(
                  COALESCE(julianday(v.insurance_expiry), 9999999),
                  COALESCE(julianday(v.registration_expiry), 9999999)
                ),
                9999999
              ) ASC
            """,
            (str(days_ahead), str(days_ahead), str(days_ahead), str(days_ahead)),
        )
        rows = await cursor.fetchall()

        alerts = []
        for row in rows:
            row_dict = dict(row)
            if row_dict.get("insurance_expiring"):
                alerts.append({
                    "vehicle_id": row_dict["id"],
                    "vehicle_number": row_dict["vehicle_number"],
                    "vehicle_label": f"{row_dict.get('year', '')} {row_dict.get('make', '')} {row_dict.get('model', '')}".strip(),
                    "alert_type": "insurance",
                    "expiry_date": row_dict["insurance_expiry"],
                    "days_remaining": int(row_dict["insurance_days_left"]) if row_dict.get("insurance_days_left") is not None else None,
                    "is_expired": (row_dict.get("insurance_days_left") or 0) < 0,
                })
            if row_dict.get("registration_expiring"):
                alerts.append({
                    "vehicle_id": row_dict["id"],
                    "vehicle_number": row_dict["vehicle_number"],
                    "vehicle_label": f"{row_dict.get('year', '')} {row_dict.get('make', '')} {row_dict.get('model', '')}".strip(),
                    "alert_type": "registration",
                    "expiry_date": row_dict["registration_expiry"],
                    "days_remaining": int(row_dict["registration_days_left"]) if row_dict.get("registration_days_left") is not None else None,
                    "is_expired": (row_dict.get("registration_days_left") or 0) < 0,
                })

        return alerts

    # ── Fleet Utilization Report ───────────────────────────────

    async def get_utilization_report(
        self,
        period_start: str,
        period_end: str,
    ) -> dict:
        """Fleet utilization report: miles, maintenance costs, fuel costs per vehicle.

        Combines data from mileage logs, maintenance records, and fuel logs.
        """
        # Per-vehicle miles in period
        cursor = await self.db.execute(
            """
            SELECT v.id AS vehicle_id, v.vehicle_number,
                   v.year, v.make, v.model, v.status,
                   COALESCE(SUM(ml.total_miles), 0) AS total_miles,
                   COUNT(ml.id) AS mileage_entries
            FROM vehicles v
            LEFT JOIN vehicle_mileage_log ml
              ON ml.vehicle_id = v.id
              AND ml.log_date BETWEEN ? AND ?
            WHERE v.is_active = 1
            GROUP BY v.id
            ORDER BY total_miles DESC
            """,
            (period_start, period_end),
        )
        vehicles = [dict(r) for r in await cursor.fetchall()]

        # Maintenance costs per vehicle
        cursor = await self.db.execute(
            """
            SELECT vehicle_id, COALESCE(SUM(cost), 0) AS maintenance_cost
            FROM vehicle_maintenance_records
            WHERE service_date BETWEEN ? AND ?
            GROUP BY vehicle_id
            """,
            (period_start, period_end),
        )
        maint_costs = {r["vehicle_id"]: r["maintenance_cost"] for r in await cursor.fetchall()}

        # Fuel costs per vehicle (if fuel_logs table exists)
        fuel_costs: dict[int, dict] = {}
        try:
            cursor = await self.db.execute(
                """
                SELECT vehicle_id,
                       COALESCE(SUM(gallons * price_per_gallon), 0) AS fuel_cost,
                       COALESCE(SUM(gallons), 0) AS total_gallons
                FROM vehicle_fuel_logs
                WHERE fill_date BETWEEN ? AND ?
                GROUP BY vehicle_id
                """,
                (period_start, period_end),
            )
            fuel_costs = {
                r["vehicle_id"]: {"fuel_cost": r["fuel_cost"], "total_gallons": r["total_gallons"]}
                for r in await cursor.fetchall()
            }
        except Exception:
            pass  # Table might not exist yet during migration

        # Enrich each vehicle
        fleet_miles = 0
        fleet_maint_cost = 0
        fleet_fuel_cost = 0
        for v in vehicles:
            vid = v["vehicle_id"]
            v["maintenance_cost"] = maint_costs.get(vid, 0)
            v["fuel_cost"] = fuel_costs.get(vid, {}).get("fuel_cost", 0)
            v["total_gallons"] = fuel_costs.get(vid, {}).get("total_gallons", 0)
            v["total_cost"] = v["maintenance_cost"] + v["fuel_cost"]

            # Avg MPG
            if v["total_gallons"] > 0 and v["total_miles"] > 0:
                v["avg_mpg"] = round(v["total_miles"] / v["total_gallons"], 1)
            else:
                v["avg_mpg"] = None

            # Cost per mile
            if v["total_miles"] > 0:
                v["cost_per_mile"] = round(v["total_cost"] / v["total_miles"], 2)
            else:
                v["cost_per_mile"] = None

            fleet_miles += v["total_miles"]
            fleet_maint_cost += v["maintenance_cost"]
            fleet_fuel_cost += v["fuel_cost"]

        return {
            "period_start": period_start,
            "period_end": period_end,
            "vehicles": vehicles,
            "summary": {
                "total_vehicles": len(vehicles),
                "fleet_total_miles": fleet_miles,
                "fleet_maintenance_cost": fleet_maint_cost,
                "fleet_fuel_cost": fleet_fuel_cost,
                "fleet_total_cost": fleet_maint_cost + fleet_fuel_cost,
                "fleet_avg_cost_per_mile": round(
                    (fleet_maint_cost + fleet_fuel_cost) / fleet_miles, 2
                ) if fleet_miles > 0 else None,
            },
        }
