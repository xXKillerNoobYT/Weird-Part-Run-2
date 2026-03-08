"""
Repositories for the Fleet & Vehicle Management system.

Covers vehicles, assignments, warehouse locations, delivery items,
maintenance (types, schedules, records), mileage logs, trip legs,
and mileage reimbursements.  Each repo extends BaseRepo for standard
CRUD; domain-specific queries live here.
"""

from __future__ import annotations

from typing import Any

from app.repositories.base import BaseRepo


# ═══════════════════════════════════════════════════════════════
# Vehicle Repository
# ═══════════════════════════════════════════════════════════════

class VehicleRepo(BaseRepo):
    """Data access for vehicles — company trucks, vans, cars, and private vehicles."""

    TABLE = "vehicles"
    HAS_UPDATED_AT = True

    async def list_with_details(
        self,
        *,
        vehicle_type: str | None = None,
        status: str | None = None,
        driver_id: int | None = None,
        search: str | None = None,
        is_active: bool | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """List vehicles with primary driver info, assignment counts, and
        next maintenance due date.  Supports filtering by type, status,
        driver, and free-text search."""
        conditions: list[str] = []
        params: list[Any] = []

        if vehicle_type:
            conditions.append("v.vehicle_type = ?")
            params.append(vehicle_type)
        if status:
            conditions.append("v.status = ?")
            params.append(status)
        if is_active is not None:
            conditions.append("v.is_active = ?")
            params.append(int(is_active))
        if driver_id:
            conditions.append("pd.user_id = ?")
            params.append(driver_id)
        if search:
            conditions.append(
                "(v.vehicle_number LIKE ? OR v.vehicle_name LIKE ? "
                "OR v.make LIKE ? OR v.model LIKE ? OR v.license_plate LIKE ?)"
            )
            params.extend([f"%{search}%"] * 5)

        where_sql = f"WHERE {' AND '.join(conditions)}" if conditions else ""

        sql = f"""
            SELECT v.*,
                   pd.user_id AS primary_driver_id,
                   u.display_name AS primary_driver_name,
                   COALESCE(ac.cnt, 0) AS assignment_count,
                   ms.next_due_date AS next_maintenance_due,
                   COALESCE(omc.cnt, 0) AS overdue_maintenance_count
            FROM vehicles v
            LEFT JOIN (
                SELECT vehicle_id, user_id
                FROM vehicle_assignments
                WHERE assignment_type = 'primary' AND end_date IS NULL
            ) pd ON pd.vehicle_id = v.id
            LEFT JOIN users u ON u.id = pd.user_id
            LEFT JOIN (
                SELECT vehicle_id, COUNT(*) AS cnt
                FROM vehicle_assignments
                WHERE end_date IS NULL
                GROUP BY vehicle_id
            ) ac ON ac.vehicle_id = v.id
            LEFT JOIN (
                SELECT vehicle_id, MIN(next_due_date) AS next_due_date
                FROM vehicle_maintenance_schedules
                WHERE is_enabled = 1 AND next_due_date IS NOT NULL
                GROUP BY vehicle_id
            ) ms ON ms.vehicle_id = v.id
            LEFT JOIN (
                SELECT vehicle_id, COUNT(*) AS cnt
                FROM vehicle_maintenance_schedules
                WHERE is_enabled = 1
                  AND (next_due_date <= date('now') OR next_due_miles <= (
                      SELECT current_odometer FROM vehicles WHERE id = vehicle_id
                  ))
                GROUP BY vehicle_id
            ) omc ON omc.vehicle_id = v.id
            {where_sql}
            ORDER BY v.vehicle_number ASC
            LIMIT ? OFFSET ?
        """
        params.extend([limit, offset])

        cursor = await self.db.execute(sql, tuple(params))
        return await cursor.fetchall()

    async def count_filtered(
        self,
        *,
        vehicle_type: str | None = None,
        status: str | None = None,
        driver_id: int | None = None,
        search: str | None = None,
        is_active: bool | None = None,
    ) -> int:
        """Count vehicles matching the same filters as list_with_details."""
        conditions: list[str] = []
        params: list[Any] = []

        if vehicle_type:
            conditions.append("v.vehicle_type = ?")
            params.append(vehicle_type)
        if status:
            conditions.append("v.status = ?")
            params.append(status)
        if is_active is not None:
            conditions.append("v.is_active = ?")
            params.append(int(is_active))
        if driver_id:
            conditions.append("""
                EXISTS (
                    SELECT 1 FROM vehicle_assignments va
                    WHERE va.vehicle_id = v.id AND va.user_id = ?
                      AND va.end_date IS NULL
                )
            """)
            params.append(driver_id)
        if search:
            conditions.append(
                "(v.vehicle_number LIKE ? OR v.vehicle_name LIKE ? "
                "OR v.make LIKE ? OR v.model LIKE ? OR v.license_plate LIKE ?)"
            )
            params.extend([f"%{search}%"] * 5)

        where_sql = f"WHERE {' AND '.join(conditions)}" if conditions else ""

        cursor = await self.db.execute(
            f"SELECT COUNT(*) AS cnt FROM vehicles v {where_sql}",
            tuple(params),
        )
        row = await cursor.fetchone()
        return row["cnt"] if row else 0

    async def get_with_details(self, vehicle_id: int) -> dict | None:
        """Get a single vehicle with all joined info (driver, owner, maintenance)."""
        cursor = await self.db.execute(
            """
            SELECT v.*,
                   ow.display_name AS owner_name,
                   pd.user_id AS primary_driver_id,
                   pu.display_name AS primary_driver_name,
                   COALESCE(ac.cnt, 0) AS assignment_count,
                   ms.next_due_date AS next_maintenance_due,
                   ms.mtype AS next_maintenance_type
            FROM vehicles v
            LEFT JOIN users ow ON ow.id = v.owner_user_id
            LEFT JOIN (
                SELECT vehicle_id, user_id
                FROM vehicle_assignments
                WHERE assignment_type = 'primary' AND end_date IS NULL
            ) pd ON pd.vehicle_id = v.id
            LEFT JOIN users pu ON pu.id = pd.user_id
            LEFT JOIN (
                SELECT vehicle_id, COUNT(*) AS cnt
                FROM vehicle_assignments
                WHERE end_date IS NULL
                GROUP BY vehicle_id
            ) ac ON ac.vehicle_id = v.id
            LEFT JOIN (
                SELECT vms.vehicle_id, vms.next_due_date, mt.name AS mtype
                FROM vehicle_maintenance_schedules vms
                JOIN maintenance_types mt ON mt.id = vms.maintenance_type_id
                WHERE vms.is_enabled = 1 AND vms.next_due_date IS NOT NULL
                ORDER BY vms.next_due_date ASC
                LIMIT 1
            ) ms ON ms.vehicle_id = v.id
            WHERE v.id = ?
            """,
            (vehicle_id,),
        )
        return await cursor.fetchone()

    async def get_by_user(self, user_id: int) -> dict | None:
        """Get the vehicle currently assigned (primary) to a user."""
        cursor = await self.db.execute(
            """
            SELECT v.*
            FROM vehicles v
            JOIN vehicle_assignments va ON va.vehicle_id = v.id
            WHERE va.user_id = ? AND va.assignment_type = 'primary'
              AND va.end_date IS NULL AND v.is_active = 1
            LIMIT 1
            """,
            (user_id,),
        )
        return await cursor.fetchone()

    async def get_fleet_stats(self) -> dict:
        """Dashboard stats for the entire fleet."""
        cursor = await self.db.execute("""
            SELECT
                COUNT(*) AS total_vehicles,
                COALESCE(SUM(CASE WHEN status = 'active' AND is_active = 1
                             THEN 1 ELSE 0 END), 0) AS active_vehicles,
                COALESCE(SUM(CASE WHEN status = 'maintenance'
                             THEN 1 ELSE 0 END), 0) AS in_maintenance,
                COALESCE(SUM(CASE WHEN status = 'retired' OR is_active = 0
                             THEN 1 ELSE 0 END), 0) AS retired_vehicles,
                COALESCE(SUM(CASE WHEN vehicle_type != 'private_vehicle'
                             THEN 1 ELSE 0 END), 0) AS company_vehicles,
                COALESCE(SUM(CASE WHEN vehicle_type = 'private_vehicle'
                             THEN 1 ELSE 0 END), 0) AS private_vehicles
            FROM vehicles
        """)
        return dict(await cursor.fetchone() or {})

    async def get_by_number(self, vehicle_number: str) -> dict | None:
        """Find a vehicle by its unique number (e.g. 'T-001')."""
        cursor = await self.db.execute(
            "SELECT * FROM vehicles WHERE vehicle_number = ?",
            (vehicle_number,),
        )
        return await cursor.fetchone()


# ═══════════════════════════════════════════════════════════════
# Vehicle Assignment Repository
# ═══════════════════════════════════════════════════════════════

class VehicleAssignmentRepo(BaseRepo):
    """Data access for driver-to-vehicle assignments."""

    TABLE = "vehicle_assignments"
    HAS_UPDATED_AT = True

    async def get_active_for_vehicle(self, vehicle_id: int) -> list[dict]:
        """Get all current (no end_date) assignments for a vehicle."""
        cursor = await self.db.execute(
            """
            SELECT va.*, u.display_name AS user_name,
                   v.vehicle_name, v.vehicle_number
            FROM vehicle_assignments va
            JOIN users u ON u.id = va.user_id
            JOIN vehicles v ON v.id = va.vehicle_id
            WHERE va.vehicle_id = ? AND va.end_date IS NULL
            ORDER BY va.assignment_type ASC
            """,
            (vehicle_id,),
        )
        return await cursor.fetchall()

    async def get_active_for_user(self, user_id: int) -> list[dict]:
        """Get all current assignments for a user (may have multiple vehicles)."""
        cursor = await self.db.execute(
            """
            SELECT va.*, v.vehicle_name, v.vehicle_number, v.vehicle_type,
                   u.display_name AS user_name
            FROM vehicle_assignments va
            JOIN vehicles v ON v.id = va.vehicle_id
            JOIN users u ON u.id = va.user_id
            WHERE va.user_id = ? AND va.end_date IS NULL
            ORDER BY va.assignment_type ASC
            """,
            (user_id,),
        )
        return await cursor.fetchall()

    async def get_primary_driver(self, vehicle_id: int) -> dict | None:
        """Get the primary driver assignment for a vehicle (if any)."""
        cursor = await self.db.execute(
            """
            SELECT va.*, u.display_name AS user_name
            FROM vehicle_assignments va
            JOIN users u ON u.id = va.user_id
            WHERE va.vehicle_id = ? AND va.assignment_type = 'primary'
              AND va.end_date IS NULL
            LIMIT 1
            """,
            (vehicle_id,),
        )
        return await cursor.fetchone()

    async def end_assignment(self, vehicle_id: int, user_id: int) -> bool:
        """End a current assignment by setting end_date."""
        cursor = await self.db.execute(
            """
            UPDATE vehicle_assignments
            SET end_date = date('now'), updated_at = datetime('now')
            WHERE vehicle_id = ? AND user_id = ? AND end_date IS NULL
            """,
            (vehicle_id, user_id),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def has_primary_driver(self, vehicle_id: int) -> bool:
        """Check if a vehicle already has an active primary driver."""
        cursor = await self.db.execute(
            """
            SELECT 1 FROM vehicle_assignments
            WHERE vehicle_id = ? AND assignment_type = 'primary'
              AND end_date IS NULL
            LIMIT 1
            """,
            (vehicle_id,),
        )
        return await cursor.fetchone() is not None


# ═══════════════════════════════════════════════════════════════
# Warehouse Location Repository
# ═══════════════════════════════════════════════════════════════

class WarehouseLocationRepo(BaseRepo):
    """Data access for physical shop/warehouse addresses."""

    TABLE = "warehouse_locations"
    HAS_UPDATED_AT = True

    async def list_active(self) -> list[dict]:
        """Get all active warehouse locations ordered by primary first."""
        cursor = await self.db.execute(
            """
            SELECT * FROM warehouse_locations
            WHERE is_active = 1
            ORDER BY is_primary DESC, name ASC
            """
        )
        return await cursor.fetchall()

    async def get_primary(self) -> dict | None:
        """Get the primary (main shop) location."""
        cursor = await self.db.execute(
            "SELECT * FROM warehouse_locations WHERE is_primary = 1 LIMIT 1"
        )
        return await cursor.fetchone()

    async def set_primary(self, location_id: int) -> None:
        """Make a location the primary, clearing any existing primary."""
        await self.db.execute(
            "UPDATE warehouse_locations SET is_primary = 0 WHERE is_primary = 1"
        )
        await self.db.execute(
            "UPDATE warehouse_locations SET is_primary = 1 WHERE id = ?",
            (location_id,),
        )
        await self.db.commit()


# ═══════════════════════════════════════════════════════════════
# Job Trailers Repository
# ═══════════════════════════════════════════════════════════════

class JobTrailerRepo(BaseRepo):
    """Data access for job trailers (mobile mini-warehouses)."""

    TABLE = "job_trailers"
    HAS_UPDATED_AT = True

    async def get_by_code(self, trailer_code: str) -> dict | None:
        cursor = await self.db.execute(
            "SELECT * FROM job_trailers WHERE trailer_code = ?",
            (trailer_code,),
        )
        return await cursor.fetchone()

    async def list_active(self, *, search: str | None = None) -> list[dict]:
        params: list[Any] = []
        where = "WHERE jt.is_active = 1"
        if search:
            where += " AND (jt.trailer_code LIKE ? OR jt.name LIKE ?)"
            params.extend([f"%{search}%", f"%{search}%"])

        cursor = await self.db.execute(
            f"""
            SELECT jt.*,
                   wh.name AS home_warehouse_name,
                   j.job_name AS current_job_name,
                   u.display_name AS assigned_driver_name
            FROM job_trailers jt
            LEFT JOIN warehouse_locations wh ON wh.id = jt.home_warehouse_id
            LEFT JOIN jobs j ON j.id = jt.current_job_id
            LEFT JOIN users u ON u.id = jt.assigned_driver_user_id
            {where}
            ORDER BY jt.trailer_code ASC
            """,
            tuple(params),
        )
        return await cursor.fetchall()


class TrailerLocationEventRepo(BaseRepo):
    """Data access for trailer location timeline events."""

    TABLE = "trailer_location_events"
    HAS_UPDATED_AT = False

    async def list_for_trailer(self, trailer_id: int, *, limit: int = 100) -> list[dict]:
        cursor = await self.db.execute(
            """
            SELECT tle.*,
                   u.display_name AS recorded_by_name,
                   wh.name AS warehouse_name,
                   j.job_name AS job_name
            FROM trailer_location_events tle
            LEFT JOIN users u ON u.id = tle.recorded_by
            LEFT JOIN warehouse_locations wh ON wh.id = tle.warehouse_id
            LEFT JOIN jobs j ON j.id = tle.job_id
            WHERE tle.trailer_id = ?
            ORDER BY tle.recorded_at DESC, tle.id DESC
            LIMIT ?
            """,
            (trailer_id, limit),
        )
        return await cursor.fetchall()

    async def get_latest_for_trailer(self, trailer_id: int) -> dict | None:
        cursor = await self.db.execute(
            """
            SELECT tle.*,
                   u.display_name AS recorded_by_name,
                   wh.name AS warehouse_name,
                   j.job_name AS job_name
            FROM trailer_location_events tle
            LEFT JOIN users u ON u.id = tle.recorded_by
            LEFT JOIN warehouse_locations wh ON wh.id = tle.warehouse_id
            LEFT JOIN jobs j ON j.id = tle.job_id
            WHERE tle.trailer_id = ?
            ORDER BY tle.recorded_at DESC, tle.id DESC
            LIMIT 1
            """,
            (trailer_id,),
        )
        return await cursor.fetchone()


# ═══════════════════════════════════════════════════════════════
# Vehicle Delivery Items Repository
# ═══════════════════════════════════════════════════════════════

class VehicleDeliveryRepo(BaseRepo):
    """Data access for job-bound delivery items on vehicles."""

    TABLE = "vehicle_delivery_items"
    HAS_UPDATED_AT = True

    async def get_for_vehicle(
        self,
        vehicle_id: int,
        *,
        status: str | None = None,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict]:
        """Get delivery items on a vehicle with part and job info."""
        conditions = ["di.vehicle_id = ?"]
        params: list[Any] = [vehicle_id]

        if status:
            conditions.append("di.status = ?")
            params.append(status)

        where_sql = " AND ".join(conditions)

        sql = f"""
            SELECT di.*,
                   j.job_name,
                   p.code AS part_number, p.name AS part_description,
                   u.display_name AS assigner_name
            FROM vehicle_delivery_items di
            JOIN jobs j ON j.id = di.job_id
            JOIN parts p ON p.id = di.part_id
            LEFT JOIN users u ON u.id = di.assigned_by
            WHERE {where_sql}
            ORDER BY di.status ASC, j.job_name ASC
            LIMIT ? OFFSET ?
        """
        params.extend([limit, offset])

        cursor = await self.db.execute(sql, tuple(params))
        return await cursor.fetchall()

    async def get_for_job(
        self, job_id: int, *, vehicle_id: int | None = None
    ) -> list[dict]:
        """Get all delivery items destined for a specific job."""
        conditions = ["di.job_id = ?"]
        params: list[Any] = [job_id]

        if vehicle_id:
            conditions.append("di.vehicle_id = ?")
            params.append(vehicle_id)

        where_sql = " AND ".join(conditions)

        sql = f"""
            SELECT di.*,
                   v.vehicle_number, v.vehicle_name,
                   p.code AS part_number, p.name AS part_description,
                   u.display_name AS assigner_name
            FROM vehicle_delivery_items di
            JOIN vehicles v ON v.id = di.vehicle_id
            JOIN parts p ON p.id = di.part_id
            LEFT JOIN users u ON u.id = di.assigned_by
            WHERE {where_sql}
            ORDER BY di.created_at DESC
        """

        cursor = await self.db.execute(sql, tuple(params))
        return await cursor.fetchall()

    async def get_pending_count(self, vehicle_id: int) -> int:
        """Count undelivered items for a vehicle."""
        cursor = await self.db.execute(
            """
            SELECT COUNT(*) AS cnt FROM vehicle_delivery_items
            WHERE vehicle_id = ? AND status NOT IN ('delivered', 'returned')
            """,
            (vehicle_id,),
        )
        row = await cursor.fetchone()
        return row["cnt"] if row else 0

    async def bulk_insert(
        self, vehicle_id: int, items: list[dict]
    ) -> list[int]:
        """Insert multiple delivery items at once. Returns list of new IDs."""
        ids = []
        for item in items:
            item["vehicle_id"] = vehicle_id
            new_id = await self.insert(item)
            ids.append(new_id)
        return ids


# ═══════════════════════════════════════════════════════════════
# Maintenance Type Repository
# ═══════════════════════════════════════════════════════════════

class MaintenanceTypeRepo(BaseRepo):
    """Data access for configurable maintenance service categories."""

    TABLE = "maintenance_types"

    async def list_active(self) -> list[dict]:
        """Get all active maintenance types sorted by sort_order."""
        cursor = await self.db.execute(
            """
            SELECT * FROM maintenance_types
            WHERE is_active = 1
            ORDER BY sort_order ASC, name ASC
            """
        )
        return await cursor.fetchall()

    async def get_by_name(self, name: str) -> dict | None:
        """Find a maintenance type by exact name."""
        cursor = await self.db.execute(
            "SELECT * FROM maintenance_types WHERE LOWER(name) = LOWER(?)",
            (name,),
        )
        return await cursor.fetchone()


# ═══════════════════════════════════════════════════════════════
# Maintenance Schedule Repository
# ═══════════════════════════════════════════════════════════════

class MaintenanceScheduleRepo(BaseRepo):
    """Data access for per-vehicle maintenance interval schedules."""

    TABLE = "vehicle_maintenance_schedules"
    HAS_UPDATED_AT = True

    async def get_for_vehicle(self, vehicle_id: int) -> list[dict]:
        """Get all schedule entries for a vehicle with type names."""
        cursor = await self.db.execute(
            """
            SELECT vms.*,
                   mt.name AS maintenance_type_name,
                   v.vehicle_name, v.vehicle_number, v.current_odometer
            FROM vehicle_maintenance_schedules vms
            JOIN maintenance_types mt ON mt.id = vms.maintenance_type_id
            JOIN vehicles v ON v.id = vms.vehicle_id
            WHERE vms.vehicle_id = ?
            ORDER BY mt.sort_order ASC
            """,
            (vehicle_id,),
        )
        return await cursor.fetchall()

    async def get_overdue(self, *, vehicle_id: int | None = None) -> list[dict]:
        """Get overdue maintenance items across the fleet (or for one vehicle).

        An item is overdue if its next_due_date has passed OR if the vehicle's
        current_odometer exceeds next_due_miles.
        """
        conditions = [
            "vms.is_enabled = 1",
            """(
                (vms.next_due_date IS NOT NULL AND vms.next_due_date <= date('now'))
                OR
                (vms.next_due_miles IS NOT NULL AND vms.next_due_miles <= v.current_odometer)
            )""",
        ]
        params: list[Any] = []

        if vehicle_id:
            conditions.append("vms.vehicle_id = ?")
            params.append(vehicle_id)

        where_sql = " AND ".join(conditions)

        sql = f"""
            SELECT vms.*,
                   mt.name AS maintenance_type_name,
                   v.vehicle_name, v.vehicle_number, v.current_odometer,
                   CASE
                       WHEN vms.next_due_miles IS NOT NULL
                       THEN vms.next_due_miles - v.current_odometer
                       ELSE NULL
                   END AS miles_until_due,
                   CASE
                       WHEN vms.next_due_date IS NOT NULL
                       THEN CAST(julianday(vms.next_due_date) - julianday('now') AS INTEGER)
                       ELSE NULL
                   END AS days_until_due
            FROM vehicle_maintenance_schedules vms
            JOIN maintenance_types mt ON mt.id = vms.maintenance_type_id
            JOIN vehicles v ON v.id = vms.vehicle_id
            WHERE {where_sql}
            ORDER BY vms.next_due_date ASC NULLS LAST
        """

        cursor = await self.db.execute(sql, tuple(params))
        return await cursor.fetchall()

    async def get_upcoming(
        self,
        *,
        days_ahead: int = 30,
        vehicle_id: int | None = None,
    ) -> list[dict]:
        """Get maintenance due within the next N days (but not yet overdue)."""
        conditions = [
            "vms.is_enabled = 1",
            "vms.next_due_date IS NOT NULL",
            "vms.next_due_date > date('now')",
            "vms.next_due_date <= date('now', ? || ' days')",
        ]
        params: list[Any] = [str(days_ahead)]

        if vehicle_id:
            conditions.append("vms.vehicle_id = ?")
            params.append(vehicle_id)

        where_sql = " AND ".join(conditions)

        sql = f"""
            SELECT vms.*,
                   mt.name AS maintenance_type_name,
                   v.vehicle_name, v.vehicle_number, v.current_odometer,
                   CAST(julianday(vms.next_due_date) - julianday('now') AS INTEGER)
                       AS days_until_due
            FROM vehicle_maintenance_schedules vms
            JOIN maintenance_types mt ON mt.id = vms.maintenance_type_id
            JOIN vehicles v ON v.id = vms.vehicle_id
            WHERE {where_sql}
            ORDER BY vms.next_due_date ASC
        """

        cursor = await self.db.execute(sql, tuple(params))
        return await cursor.fetchall()

    async def get_or_create(
        self, vehicle_id: int, maintenance_type_id: int
    ) -> dict:
        """Get an existing schedule entry or create a blank one."""
        cursor = await self.db.execute(
            """
            SELECT * FROM vehicle_maintenance_schedules
            WHERE vehicle_id = ? AND maintenance_type_id = ?
            """,
            (vehicle_id, maintenance_type_id),
        )
        row = await cursor.fetchone()
        if row:
            return dict(row)

        new_id = await self.insert({
            "vehicle_id": vehicle_id,
            "maintenance_type_id": maintenance_type_id,
        })
        return {"id": new_id, "vehicle_id": vehicle_id,
                "maintenance_type_id": maintenance_type_id}


# ═══════════════════════════════════════════════════════════════
# Maintenance Record Repository
# ═══════════════════════════════════════════════════════════════

class MaintenanceRecordRepo(BaseRepo):
    """Data access for actual service history entries."""

    TABLE = "vehicle_maintenance_records"

    async def get_for_vehicle(
        self,
        vehicle_id: int,
        *,
        maintenance_type_id: int | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """Get service history for a vehicle with type names."""
        conditions = ["mr.vehicle_id = ?"]
        params: list[Any] = [vehicle_id]

        if maintenance_type_id:
            conditions.append("mr.maintenance_type_id = ?")
            params.append(maintenance_type_id)

        where_sql = " AND ".join(conditions)

        sql = f"""
            SELECT mr.*,
                   mt.name AS maintenance_type_name,
                   u.display_name AS performer_name,
                   v.vehicle_name
            FROM vehicle_maintenance_records mr
            JOIN maintenance_types mt ON mt.id = mr.maintenance_type_id
            JOIN vehicles v ON v.id = mr.vehicle_id
            LEFT JOIN users u ON u.id = mr.performed_by
            WHERE {where_sql}
            ORDER BY mr.service_date DESC
            LIMIT ? OFFSET ?
        """
        params.extend([limit, offset])

        cursor = await self.db.execute(sql, tuple(params))
        return await cursor.fetchall()

    async def get_cost_summary(
        self,
        vehicle_id: int,
        *,
        period_start: str | None = None,
        period_end: str | None = None,
    ) -> dict:
        """Get total maintenance cost (and per-type breakdown) for a vehicle."""
        conditions = ["mr.vehicle_id = ?"]
        params: list[Any] = [vehicle_id]

        if period_start:
            conditions.append("mr.service_date >= ?")
            params.append(period_start)
        if period_end:
            conditions.append("mr.service_date <= ?")
            params.append(period_end)

        where_sql = " AND ".join(conditions)

        # Total cost
        cursor = await self.db.execute(
            f"""
            SELECT COALESCE(SUM(mr.cost), 0) AS total_cost,
                   COUNT(*) AS record_count
            FROM vehicle_maintenance_records mr
            WHERE {where_sql}
            """,
            tuple(params),
        )
        totals = dict(await cursor.fetchone() or {})

        # Per-type breakdown
        cursor = await self.db.execute(
            f"""
            SELECT mt.name AS maintenance_type,
                   COUNT(*) AS record_count,
                   COALESCE(SUM(mr.cost), 0) AS total_cost
            FROM vehicle_maintenance_records mr
            JOIN maintenance_types mt ON mt.id = mr.maintenance_type_id
            WHERE {where_sql}
            GROUP BY mt.name
            ORDER BY total_cost DESC
            """,
            tuple(params),
        )
        breakdown = await cursor.fetchall()
        totals["breakdown"] = [dict(r) for r in breakdown]

        return totals

    async def get_last_for_type(
        self, vehicle_id: int, maintenance_type_id: int
    ) -> dict | None:
        """Get the most recent service record of a given type for a vehicle."""
        cursor = await self.db.execute(
            """
            SELECT * FROM vehicle_maintenance_records
            WHERE vehicle_id = ? AND maintenance_type_id = ?
            ORDER BY service_date DESC
            LIMIT 1
            """,
            (vehicle_id, maintenance_type_id),
        )
        return await cursor.fetchone()


# ═══════════════════════════════════════════════════════════════
# Mileage Log Repository
# ═══════════════════════════════════════════════════════════════

class MileageLogRepo(BaseRepo):
    """Data access for daily vehicle mileage (odometer) logs."""

    TABLE = "vehicle_mileage_logs"
    HAS_UPDATED_AT = True

    async def get_for_vehicle(
        self,
        vehicle_id: int,
        *,
        limit: int = 30,
        offset: int = 0,
    ) -> list[dict]:
        """Get mileage logs for a vehicle, newest first."""
        cursor = await self.db.execute(
            """
            SELECT ml.*,
                   u.display_name AS driver_name,
                   v.vehicle_name, v.vehicle_number
            FROM vehicle_mileage_logs ml
            JOIN users u ON u.id = ml.driver_id
            JOIN vehicles v ON v.id = ml.vehicle_id
            WHERE ml.vehicle_id = ?
            ORDER BY ml.log_date DESC
            LIMIT ? OFFSET ?
            """,
            (vehicle_id, limit, offset),
        )
        return await cursor.fetchall()

    async def get_for_driver(
        self,
        driver_id: int,
        *,
        limit: int = 30,
        offset: int = 0,
    ) -> list[dict]:
        """Get mileage logs for a driver across all vehicles."""
        cursor = await self.db.execute(
            """
            SELECT ml.*,
                   u.display_name AS driver_name,
                   v.vehicle_name, v.vehicle_number
            FROM vehicle_mileage_logs ml
            JOIN users u ON u.id = ml.driver_id
            JOIN vehicles v ON v.id = ml.vehicle_id
            WHERE ml.driver_id = ?
            ORDER BY ml.log_date DESC
            LIMIT ? OFFSET ?
            """,
            (driver_id, limit, offset),
        )
        return await cursor.fetchall()

    async def get_daily(
        self, vehicle_id: int, log_date: str
    ) -> dict | None:
        """Get the mileage log for a specific vehicle + date."""
        cursor = await self.db.execute(
            """
            SELECT ml.*, u.display_name AS driver_name
            FROM vehicle_mileage_logs ml
            JOIN users u ON u.id = ml.driver_id
            WHERE ml.vehicle_id = ? AND ml.log_date = ?
            """,
            (vehicle_id, log_date),
        )
        return await cursor.fetchone()

    async def get_period_summary(
        self,
        *,
        vehicle_id: int | None = None,
        driver_id: int | None = None,
        period_start: str,
        period_end: str,
    ) -> dict:
        """Summarize mileage over a date range."""
        conditions = ["ml.log_date >= ?", "ml.log_date <= ?"]
        params: list[Any] = [period_start, period_end]

        if vehicle_id:
            conditions.append("ml.vehicle_id = ?")
            params.append(vehicle_id)
        if driver_id:
            conditions.append("ml.driver_id = ?")
            params.append(driver_id)

        where_sql = " AND ".join(conditions)

        cursor = await self.db.execute(
            f"""
            SELECT
                COALESCE(SUM(ml.total_miles), 0) AS total_miles,
                COUNT(*) AS total_days_logged,
                COALESCE(SUM(CASE WHEN ml.is_take_home_day = 1 THEN 1 ELSE 0 END), 0)
                    AS total_take_home_days
            FROM vehicle_mileage_logs ml
            WHERE {where_sql}
            """,
            tuple(params),
        )
        row = await cursor.fetchone()
        summary = dict(row) if row else {
            "total_miles": 0, "total_days_logged": 0, "total_take_home_days": 0,
        }

        # Also get total billable drive minutes from trip legs in this period
        cursor = await self.db.execute(
            f"""
            SELECT COALESCE(SUM(tl.actual_drive_minutes), 0) AS total_billable_minutes
            FROM vehicle_trip_legs tl
            JOIN vehicle_mileage_logs ml ON ml.id = tl.mileage_log_id
            WHERE tl.is_billable = 1 AND {where_sql}
            """,
            tuple(params),
        )
        row = await cursor.fetchone()
        summary["total_billable_drive_minutes"] = (
            row["total_billable_minutes"] if row else 0
        )

        return summary

    async def get_fleet_month_miles(self) -> int:
        """Total miles across all vehicles for the current month (for dashboard)."""
        cursor = await self.db.execute(
            """
            SELECT COALESCE(SUM(total_miles), 0) AS total
            FROM vehicle_mileage_logs
            WHERE log_date >= date('now', 'start of month')
            """
        )
        row = await cursor.fetchone()
        return row["total"] if row else 0


# ═══════════════════════════════════════════════════════════════
# Trip Leg Repository
# ═══════════════════════════════════════════════════════════════

class TripLegRepo(BaseRepo):
    """Data access for individual trip segments within a mileage log."""

    TABLE = "vehicle_trip_legs"

    async def get_for_log(self, mileage_log_id: int) -> list[dict]:
        """Get all trip legs for a mileage log entry, ordered by sequence."""
        cursor = await self.db.execute(
            """
            SELECT tl.*,
                   fj.job_name AS from_job_name,
                   tj.job_name AS to_job_name
            FROM vehicle_trip_legs tl
            LEFT JOIN jobs fj ON fj.id = tl.from_job_id
            LEFT JOIN jobs tj ON tj.id = tl.to_job_id
            WHERE tl.mileage_log_id = ?
            ORDER BY tl.leg_order ASC
            """,
            (mileage_log_id,),
        )
        return await cursor.fetchall()

    async def get_for_job(self, job_id: int, *, limit: int = 50) -> list[dict]:
        """Get all trip legs referencing a specific job (from or to)."""
        cursor = await self.db.execute(
            """
            SELECT tl.*,
                   ml.log_date, ml.vehicle_id, ml.driver_id,
                   u.display_name AS driver_name,
                   v.vehicle_number
            FROM vehicle_trip_legs tl
            JOIN vehicle_mileage_logs ml ON ml.id = tl.mileage_log_id
            JOIN users u ON u.id = ml.driver_id
            JOIN vehicles v ON v.id = ml.vehicle_id
            WHERE tl.from_job_id = ? OR tl.to_job_id = ?
            ORDER BY ml.log_date DESC
            LIMIT ?
            """,
            (job_id, job_id, limit),
        )
        return await cursor.fetchall()

    async def bulk_insert(
        self, mileage_log_id: int, legs: list[dict]
    ) -> list[int]:
        """Insert multiple trip legs at once."""
        ids = []
        for leg in legs:
            leg["mileage_log_id"] = mileage_log_id
            new_id = await self.insert(leg)
            ids.append(new_id)
        return ids

    async def get_billable_minutes_for_period(
        self,
        driver_id: int,
        period_start: str,
        period_end: str,
    ) -> int:
        """Sum billable drive minutes for a driver in a date range."""
        cursor = await self.db.execute(
            """
            SELECT COALESCE(SUM(tl.actual_drive_minutes), 0) AS total
            FROM vehicle_trip_legs tl
            JOIN vehicle_mileage_logs ml ON ml.id = tl.mileage_log_id
            WHERE ml.driver_id = ? AND tl.is_billable = 1
              AND ml.log_date >= ? AND ml.log_date <= ?
            """,
            (driver_id, period_start, period_end),
        )
        row = await cursor.fetchone()
        return row["total"] if row else 0


# ═══════════════════════════════════════════════════════════════
# Mileage Reimbursement Repository
# ═══════════════════════════════════════════════════════════════

class ReimbursementRepo(BaseRepo):
    """Data access for private vehicle mileage reimbursements."""

    TABLE = "mileage_reimbursements"
    HAS_UPDATED_AT = True

    async def get_for_user(
        self,
        user_id: int,
        *,
        status: str | None = None,
        limit: int = 20,
        offset: int = 0,
    ) -> list[dict]:
        """Get reimbursements for a user with vehicle info."""
        conditions = ["r.user_id = ?"]
        params: list[Any] = [user_id]

        if status:
            conditions.append("r.status = ?")
            params.append(status)

        where_sql = " AND ".join(conditions)

        sql = f"""
            SELECT r.*,
                   u.display_name AS user_name,
                   v.vehicle_name,
                   a.display_name AS approver_name
            FROM mileage_reimbursements r
            JOIN users u ON u.id = r.user_id
            JOIN vehicles v ON v.id = r.vehicle_id
            LEFT JOIN users a ON a.id = r.approved_by
            WHERE {where_sql}
            ORDER BY r.period_end DESC
            LIMIT ? OFFSET ?
        """
        params.extend([limit, offset])

        cursor = await self.db.execute(sql, tuple(params))
        return await cursor.fetchall()

    async def get_pending(self, *, limit: int = 50) -> list[dict]:
        """Get all pending reimbursements (for manager approval queue)."""
        cursor = await self.db.execute(
            """
            SELECT r.*,
                   u.display_name AS user_name,
                   v.vehicle_name
            FROM mileage_reimbursements r
            JOIN users u ON u.id = r.user_id
            JOIN vehicles v ON v.id = r.vehicle_id
            WHERE r.status = 'pending'
            ORDER BY r.created_at ASC
            LIMIT ?
            """,
            (limit,),
        )
        return await cursor.fetchall()

    async def get_with_details(self, reimbursement_id: int) -> dict | None:
        """Get a single reimbursement with all joined info."""
        cursor = await self.db.execute(
            """
            SELECT r.*,
                   u.display_name AS user_name,
                   v.vehicle_name,
                   a.display_name AS approver_name
            FROM mileage_reimbursements r
            JOIN users u ON u.id = r.user_id
            JOIN vehicles v ON v.id = r.vehicle_id
            LEFT JOIN users a ON a.id = r.approved_by
            WHERE r.id = ?
            """,
            (reimbursement_id,),
        )
        return await cursor.fetchone()

    async def get_pending_count(self) -> int:
        """Count pending reimbursements (for dashboard badge)."""
        cursor = await self.db.execute(
            "SELECT COUNT(*) AS cnt FROM mileage_reimbursements WHERE status = 'pending'"
        )
        row = await cursor.fetchone()
        return row["cnt"] if row else 0
