"""
Job Service — CRUD, status lifecycle, address/GPS, aggregation queries.

Handles creation, updates, status transitions, and list queries for jobs.
Also provides aggregated stats (labor hours, parts cost, active workers)
that are merged into job responses for the frontend.
"""

from __future__ import annotations

import logging
from datetime import datetime

import aiosqlite

from app.models.jobs import (
    BillRateTypeCreate,
    BillRateTypeResponse,
    BillRateTypeUpdate,
    JobCreate,
    JobListItem,
    JobResponse,
    JobUpdate,
    JobPartConsumeRequest,
    JobPartResponse,
)

logger = logging.getLogger(__name__)


class JobService:
    """Job CRUD + aggregation queries."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    # ── Create ────────────────────────────────────────────────────

    async def create_job(self, data: JobCreate, created_by: int) -> JobResponse:
        """Create a new job. Returns the full job response."""
        cursor = await self.db.execute(
            """INSERT INTO jobs (
                job_number, job_name, customer_name,
                address_line1, address_line2, city, state, zip,
                gps_lat, gps_lng,
                status, priority, job_type,
                bill_rate_type_id, lead_user_id,
                start_date, due_date, notes
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                data.job_number, data.job_name, data.customer_name,
                data.address_line1, data.address_line2, data.city, data.state, data.zip,
                data.gps_lat, data.gps_lng,
                data.status, data.priority, data.job_type,
                data.bill_rate_type_id, data.lead_user_id,
                data.start_date, data.due_date, data.notes,
            ),
        )
        await self.db.commit()
        job_id = cursor.lastrowid
        return await self.get_job(job_id)

    # ── Read ──────────────────────────────────────────────────────

    async def get_job(self, job_id: int) -> JobResponse | None:
        """Get a single job with aggregated stats."""
        cursor = await self.db.execute(
            """SELECT j.*,
                      u.display_name AS lead_user_name,
                      brt.name AS bill_rate_type_name,
                      -- Labor aggregation
                      COALESCE(labor.total_hours, 0) AS total_labor_hours,
                      COALESCE(labor.active_count, 0) AS active_workers,
                      -- Parts cost aggregation
                      COALESCE(parts.total_cost, 0) AS total_parts_cost
               FROM jobs j
               LEFT JOIN users u ON u.id = j.lead_user_id
               LEFT JOIN bill_rate_types brt ON brt.id = j.bill_rate_type_id
               LEFT JOIN (
                   SELECT job_id,
                          SUM(COALESCE(regular_hours, 0) + COALESCE(overtime_hours, 0)) AS total_hours,
                          SUM(CASE WHEN status = 'clocked_in' THEN 1 ELSE 0 END) AS active_count
                   FROM labor_entries
                   GROUP BY job_id
               ) labor ON labor.job_id = j.id
               LEFT JOIN (
                   SELECT job_id,
                          SUM(qty_consumed * COALESCE(unit_cost_at_consume, 0)) AS total_cost
                   FROM job_parts
                   GROUP BY job_id
               ) parts ON parts.job_id = j.id
               WHERE j.id = ?""",
            (job_id,),
        )
        row = await cursor.fetchone()
        if not row:
            return None
        return self._row_to_response(row)

    async def get_active_jobs(
        self,
        search: str | None = None,
        status: str | None = None,
        job_type: str | None = None,
        priority: str | None = None,
        sort_by: str = "created_at",
        sort_dir: str = "desc",
    ) -> list[JobListItem]:
        """List jobs with optional filters."""
        conditions = []
        params: list = []

        if status:
            conditions.append("j.status = ?")
            params.append(status)
        else:
            # Default: show all non-terminal statuses
            conditions.append(
                "j.status IN ('pending', 'active', 'on_hold', 'continuous_maintenance', 'on_call')"
            )

        if job_type:
            conditions.append("j.job_type = ?")
            params.append(job_type)

        if priority:
            conditions.append("j.priority = ?")
            params.append(priority)

        if search:
            conditions.append(
                "(j.job_name LIKE ? OR j.job_number LIKE ? OR j.customer_name LIKE ?)"
            )
            term = f"%{search}%"
            params.extend([term, term, term])

        where = " AND ".join(conditions) if conditions else "1=1"

        # Validate sort column
        allowed_sorts = {
            "created_at", "job_name", "job_number", "customer_name",
            "priority", "status", "job_type",
        }
        if sort_by not in allowed_sorts:
            sort_by = "created_at"
        if sort_dir not in ("asc", "desc"):
            sort_dir = "desc"

        cursor = await self.db.execute(
            f"""SELECT j.*,
                       u.display_name AS lead_user_name,
                       brt.name AS bill_rate_type_name,
                       COALESCE(labor.total_hours, 0) AS total_labor_hours,
                       COALESCE(labor.active_count, 0) AS active_workers,
                       COALESCE(parts.total_cost, 0) AS total_parts_cost
                FROM jobs j
                LEFT JOIN users u ON u.id = j.lead_user_id
                LEFT JOIN bill_rate_types brt ON brt.id = j.bill_rate_type_id
                LEFT JOIN (
                    SELECT job_id,
                           SUM(COALESCE(regular_hours, 0) + COALESCE(overtime_hours, 0)) AS total_hours,
                           SUM(CASE WHEN status = 'clocked_in' THEN 1 ELSE 0 END) AS active_count
                    FROM labor_entries
                    GROUP BY job_id
                ) labor ON labor.job_id = j.id
                LEFT JOIN (
                    SELECT job_id,
                           SUM(qty_consumed * COALESCE(unit_cost_at_consume, 0)) AS total_cost
                    FROM job_parts
                    GROUP BY job_id
                ) parts ON parts.job_id = j.id
                WHERE {where}
                ORDER BY j.{sort_by} {sort_dir}""",
            params,
        )
        rows = await cursor.fetchall()
        return [self._row_to_list_item(r) for r in rows]

    # ── Update ────────────────────────────────────────────────────

    async def update_job(self, job_id: int, data: JobUpdate) -> JobResponse | None:
        """Update job fields. Only updates non-None fields."""
        updates = []
        params: list = []

        for field, value in data.model_dump(exclude_none=True).items():
            updates.append(f"{field} = ?")
            params.append(value)

        if not updates:
            return await self.get_job(job_id)

        updates.append("updated_at = datetime('now')")
        params.append(job_id)

        await self.db.execute(
            f"UPDATE jobs SET {', '.join(updates)} WHERE id = ?",
            params,
        )
        await self.db.commit()
        return await self.get_job(job_id)

    async def update_status(self, job_id: int, new_status: str) -> JobResponse | None:
        """Change job status. Sets completed_date when completing."""
        extra = ""
        params: list = [new_status]

        if new_status in ("completed", "cancelled"):
            extra = ", completed_date = datetime('now')"
        elif new_status in ("active", "pending", "on_hold", "continuous_maintenance", "on_call"):
            extra = ", completed_date = NULL"

        params.append(job_id)
        await self.db.execute(
            f"UPDATE jobs SET status = ?, updated_at = datetime('now'){extra} WHERE id = ?",
            params,
        )
        await self.db.commit()
        return await self.get_job(job_id)

    # ── Job Parts ─────────────────────────────────────────────────

    async def consume_part(
        self, job_id: int, data: JobPartConsumeRequest, user_id: int
    ) -> JobPartResponse:
        """Record parts consumed on a job. Snapshots current cost."""
        # Get current cost/sell price for the part
        cursor = await self.db.execute(
            "SELECT company_cost_price, company_sell_price FROM parts WHERE id = ?",
            (data.part_id,),
        )
        part_row = await cursor.fetchone()
        unit_cost = part_row["company_cost_price"] if part_row else None
        unit_sell = part_row["company_sell_price"] if part_row else None

        cursor = await self.db.execute(
            """INSERT INTO job_parts (
                job_id, part_id, qty_consumed, unit_cost_at_consume,
                unit_sell_at_consume, consumed_by, notes
            ) VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (job_id, data.part_id, data.qty_consumed, unit_cost, unit_sell, user_id, data.notes),
        )
        await self.db.commit()
        return await self._get_job_part(cursor.lastrowid)

    async def get_job_parts(self, job_id: int) -> list[JobPartResponse]:
        """Get all parts consumed on a job."""
        cursor = await self.db.execute(
            """SELECT jp.*,
                      p.name AS part_name, p.code AS part_code,
                      u.display_name AS consumed_by_name
               FROM job_parts jp
               LEFT JOIN parts p ON p.id = jp.part_id
               LEFT JOIN users u ON u.id = jp.consumed_by
               WHERE jp.job_id = ?
               ORDER BY jp.consumed_at DESC""",
            (job_id,),
        )
        rows = await cursor.fetchall()
        return [
            JobPartResponse(
                id=r["id"], job_id=r["job_id"], part_id=r["part_id"],
                part_name=r["part_name"], part_code=r["part_code"],
                qty_consumed=r["qty_consumed"], qty_returned=r["qty_returned"],
                unit_cost_at_consume=r["unit_cost_at_consume"],
                unit_sell_at_consume=r["unit_sell_at_consume"],
                consumed_by=r["consumed_by"],
                consumed_by_name=r["consumed_by_name"],
                consumed_at=r["consumed_at"], notes=r["notes"],
            )
            for r in rows
        ]

    async def _get_job_part(self, part_entry_id: int) -> JobPartResponse:
        cursor = await self.db.execute(
            """SELECT jp.*,
                      p.name AS part_name, p.code AS part_code,
                      u.display_name AS consumed_by_name
               FROM job_parts jp
               LEFT JOIN parts p ON p.id = jp.part_id
               LEFT JOIN users u ON u.id = jp.consumed_by
               WHERE jp.id = ?""",
            (part_entry_id,),
        )
        r = await cursor.fetchone()
        return JobPartResponse(
            id=r["id"], job_id=r["job_id"], part_id=r["part_id"],
            part_name=r["part_name"], part_code=r["part_code"],
            qty_consumed=r["qty_consumed"], qty_returned=r["qty_returned"],
            unit_cost_at_consume=r["unit_cost_at_consume"],
            unit_sell_at_consume=r["unit_sell_at_consume"],
            consumed_by=r["consumed_by"],
            consumed_by_name=r["consumed_by_name"],
            consumed_at=r["consumed_at"], notes=r["notes"],
        )

    # ── Helpers ───────────────────────────────────────────────────

    def _row_to_response(self, row: aiosqlite.Row) -> JobResponse:
        return JobResponse(
            id=row["id"],
            job_number=row["job_number"],
            job_name=row["job_name"],
            customer_name=row["customer_name"],
            address_line1=row["address_line1"],
            address_line2=row["address_line2"],
            city=row["city"],
            state=row["state"],
            zip=row["zip"],
            gps_lat=row["gps_lat"],
            gps_lng=row["gps_lng"],
            status=row["status"],
            priority=row["priority"],
            job_type=row["job_type"],
            bill_rate_type_id=row["bill_rate_type_id"],
            bill_rate_type_name=row["bill_rate_type_name"],
            lead_user_id=row["lead_user_id"],
            lead_user_name=row["lead_user_name"],
            start_date=row["start_date"],
            due_date=row["due_date"],
            completed_date=row["completed_date"],
            notes=row["notes"],
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            total_labor_hours=row["total_labor_hours"],
            total_parts_cost=row["total_parts_cost"],
            active_workers=row["active_workers"],
        )

    def _row_to_list_item(self, row: aiosqlite.Row) -> JobListItem:
        return JobListItem(
            id=row["id"],
            job_number=row["job_number"],
            job_name=row["job_name"],
            customer_name=row["customer_name"],
            address_line1=row["address_line1"],
            city=row["city"],
            state=row["state"],
            zip=row["zip"],
            gps_lat=row["gps_lat"],
            gps_lng=row["gps_lng"],
            status=row["status"],
            priority=row["priority"],
            job_type=row["job_type"],
            bill_rate_type_name=row["bill_rate_type_name"],
            lead_user_name=row["lead_user_name"],
            active_workers=row["active_workers"] or 0,
            total_labor_hours=row["total_labor_hours"] or 0,
            total_parts_cost=row["total_parts_cost"] or 0,
            created_at=row["created_at"],
        )

    # ── Bill Rate Types CRUD ───────────────────────────────────────

    async def get_bill_rate_types(self, active_only: bool = True) -> list[BillRateTypeResponse]:
        """List bill rate types, optionally filtered to active only."""
        where = "WHERE is_active = 1" if active_only else ""
        cursor = await self.db.execute(
            f"SELECT * FROM bill_rate_types {where} ORDER BY sort_order ASC, name ASC"
        )
        rows = await cursor.fetchall()
        return [
            BillRateTypeResponse(
                id=r["id"], name=r["name"], description=r["description"],
                sort_order=r["sort_order"], is_active=bool(r["is_active"]),
                created_at=r["created_at"],
            )
            for r in rows
        ]

    async def create_bill_rate_type(self, data: BillRateTypeCreate) -> BillRateTypeResponse:
        """Create a new bill rate type."""
        # Auto-assign sort_order to end of list
        cursor = await self.db.execute(
            "SELECT COALESCE(MAX(sort_order), 0) + 1 AS next_order FROM bill_rate_types"
        )
        row = await cursor.fetchone()
        next_order = row["next_order"]

        cursor = await self.db.execute(
            "INSERT INTO bill_rate_types (name, description, sort_order) VALUES (?, ?, ?)",
            (data.name, data.description, next_order),
        )
        await self.db.commit()
        return (await self.get_bill_rate_types(active_only=False))[-1]

    async def update_bill_rate_type(
        self, type_id: int, data: BillRateTypeUpdate
    ) -> BillRateTypeResponse | None:
        """Update a bill rate type."""
        updates = []
        params: list = []
        for field, value in data.model_dump(exclude_none=True).items():
            if field == "is_active":
                updates.append("is_active = ?")
                params.append(1 if value else 0)
            else:
                updates.append(f"{field} = ?")
                params.append(value)

        if not updates:
            return None

        params.append(type_id)
        await self.db.execute(
            f"UPDATE bill_rate_types SET {', '.join(updates)} WHERE id = ?",
            params,
        )
        await self.db.commit()

        cursor = await self.db.execute(
            "SELECT * FROM bill_rate_types WHERE id = ?", (type_id,)
        )
        r = await cursor.fetchone()
        if not r:
            return None
        return BillRateTypeResponse(
            id=r["id"], name=r["name"], description=r["description"],
            sort_order=r["sort_order"], is_active=bool(r["is_active"]),
            created_at=r["created_at"],
        )

    async def delete_bill_rate_type(self, type_id: int) -> bool:
        """Soft-delete a bill rate type (set is_active = 0)."""
        await self.db.execute(
            "UPDATE bill_rate_types SET is_active = 0 WHERE id = ?", (type_id,)
        )
        await self.db.commit()
        return True
