"""
Tools & Kits repositories.

Eight repo classes for the tools module, all extending BaseRepo.
Each handles a specific table with domain-specific query methods
including JOINs for human-readable names and subqueries for counts.
"""

from __future__ import annotations

from app.repositories.base import BaseRepo


# ─── 1. ToolRepo ─────────────────────────────────────────────────────

class ToolRepo(BaseRepo):
    """Repository for the `tools` table."""
    TABLE = "tools"
    HAS_UPDATED_AT = True

    async def list_with_details(
        self,
        *,
        category: str | None = None,
        status: str | None = None,
        location_type: str | None = None,
        search: str | None = None,
        is_active: bool = True,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict]:
        """List tools with joined names, kit counts, and maintenance info."""
        conditions = []
        params: list = []

        if is_active is not None:
            conditions.append("t.is_active = ?")
            params.append(1 if is_active else 0)
        if category:
            conditions.append("t.category = ?")
            params.append(category)
        if status:
            conditions.append("t.status = ?")
            params.append(status)
        if location_type:
            conditions.append("t.location_type = ?")
            params.append(location_type)
        if search:
            conditions.append(
                "(t.tool_number LIKE ? OR t.name LIKE ? OR t.brand LIKE ?)"
            )
            like = f"%{search}%"
            params.extend([like, like, like])

        where = " AND ".join(conditions) if conditions else "1=1"

        sql = f"""
            SELECT t.*,
                   u.display_name AS assigned_to_name,
                   CASE t.location_type
                       WHEN 'warehouse' THEN wl.name
                       WHEN 'truck'     THEN v.vehicle_name
                       WHEN 'job'       THEN j.job_name
                   END AS location_name,
                   COALESCE(kit_cnt.cnt, 0)  AS kit_component_count,
                   maint_next.next_due       AS next_maintenance_due,
                   COALESCE(maint_over.cnt, 0) AS overdue_maintenance_count
            FROM tools t
            LEFT JOIN users u ON u.id = t.assigned_to
            LEFT JOIN warehouse_locations wl
                ON t.location_type = 'warehouse' AND wl.id = t.location_id
            LEFT JOIN vehicles v
                ON t.location_type = 'truck' AND v.id = t.location_id
            LEFT JOIN jobs j
                ON t.location_type = 'job' AND j.id = t.location_id
            LEFT JOIN (
                SELECT tool_id, COUNT(*) AS cnt
                FROM kit_templates GROUP BY tool_id
            ) kit_cnt ON kit_cnt.tool_id = t.id
            LEFT JOIN (
                SELECT tool_id, MIN(next_due_date) AS next_due
                FROM tool_maintenance_schedules
                WHERE is_enabled = 1 AND next_due_date IS NOT NULL
                GROUP BY tool_id
            ) maint_next ON maint_next.tool_id = t.id
            LEFT JOIN (
                SELECT tool_id, COUNT(*) AS cnt
                FROM tool_maintenance_schedules
                WHERE is_enabled = 1
                  AND next_due_date IS NOT NULL
                  AND next_due_date < date('now')
                GROUP BY tool_id
            ) maint_over ON maint_over.tool_id = t.id
            WHERE {where}
            ORDER BY t.tool_number ASC
            LIMIT ? OFFSET ?
        """
        params.extend([limit, offset])
        cursor = await self.db.execute(sql, params)
        return await cursor.fetchall()

    async def count_filtered(
        self,
        *,
        category: str | None = None,
        status: str | None = None,
        location_type: str | None = None,
        search: str | None = None,
        is_active: bool = True,
    ) -> int:
        """Count tools matching filters."""
        conditions = []
        params: list = []

        if is_active is not None:
            conditions.append("is_active = ?")
            params.append(1 if is_active else 0)
        if category:
            conditions.append("category = ?")
            params.append(category)
        if status:
            conditions.append("status = ?")
            params.append(status)
        if location_type:
            conditions.append("location_type = ?")
            params.append(location_type)
        if search:
            conditions.append(
                "(tool_number LIKE ? OR name LIKE ? OR brand LIKE ?)"
            )
            like = f"%{search}%"
            params.extend([like, like, like])

        where = " AND ".join(conditions) if conditions else "1=1"
        cursor = await self.db.execute(
            f"SELECT COUNT(*) AS cnt FROM tools WHERE {where}", params
        )
        row = await cursor.fetchone()
        return row["cnt"] if row else 0

    async def get_with_details(self, tool_id: int) -> dict | None:
        """Get a single tool with all joined details."""
        sql = """
            SELECT t.*,
                   u.display_name AS assigned_to_name,
                   CASE t.location_type
                       WHEN 'warehouse' THEN wl.name
                       WHEN 'truck'     THEN v.vehicle_name
                       WHEN 'job'       THEN j.job_name
                   END AS location_name,
                   COALESCE(kit_cnt.cnt, 0)  AS kit_component_count,
                   maint_next.next_due       AS next_maintenance_due,
                   COALESCE(maint_over.cnt, 0) AS overdue_maintenance_count
            FROM tools t
            LEFT JOIN users u ON u.id = t.assigned_to
            LEFT JOIN warehouse_locations wl
                ON t.location_type = 'warehouse' AND wl.id = t.location_id
            LEFT JOIN vehicles v
                ON t.location_type = 'truck' AND v.id = t.location_id
            LEFT JOIN jobs j
                ON t.location_type = 'job' AND j.id = t.location_id
            LEFT JOIN (
                SELECT tool_id, COUNT(*) AS cnt
                FROM kit_templates GROUP BY tool_id
            ) kit_cnt ON kit_cnt.tool_id = t.id
            LEFT JOIN (
                SELECT tool_id, MIN(next_due_date) AS next_due
                FROM tool_maintenance_schedules
                WHERE is_enabled = 1 AND next_due_date IS NOT NULL
                GROUP BY tool_id
            ) maint_next ON maint_next.tool_id = t.id
            LEFT JOIN (
                SELECT tool_id, COUNT(*) AS cnt
                FROM tool_maintenance_schedules
                WHERE is_enabled = 1
                  AND next_due_date IS NOT NULL
                  AND next_due_date < date('now')
                GROUP BY tool_id
            ) maint_over ON maint_over.tool_id = t.id
            WHERE t.id = ?
        """
        cursor = await self.db.execute(sql, (tool_id,))
        return await cursor.fetchone()

    async def get_at_location(
        self, location_type: str, location_id: int
    ) -> list[dict]:
        """Get all active tools at a specific location."""
        sql = """
            SELECT t.*,
                   u.display_name AS assigned_to_name,
                   COALESCE(kit_cnt.cnt, 0) AS kit_component_count
            FROM tools t
            LEFT JOIN users u ON u.id = t.assigned_to
            LEFT JOIN (
                SELECT tool_id, COUNT(*) AS cnt
                FROM kit_templates GROUP BY tool_id
            ) kit_cnt ON kit_cnt.tool_id = t.id
            WHERE t.location_type = ? AND t.location_id = ?
              AND t.is_active = 1
            ORDER BY t.tool_number ASC
        """
        cursor = await self.db.execute(sql, (location_type, location_id))
        return await cursor.fetchall()

    async def get_by_barcode(self, barcode: str) -> dict | None:
        """Look up a tool by its QR barcode value."""
        cursor = await self.db.execute(
            "SELECT * FROM tools WHERE barcode = ? AND is_active = 1",
            (barcode,),
        )
        return await cursor.fetchone()

    async def get_by_number(self, tool_number: str) -> dict | None:
        """Look up a tool by tool_number."""
        cursor = await self.db.execute(
            "SELECT * FROM tools WHERE tool_number = ?", (tool_number,)
        )
        return await cursor.fetchone()

    async def update_location(
        self,
        tool_id: int,
        location_type: str,
        location_id: int | None,
        status: str,
        assigned_to: int | None = None,
    ) -> bool:
        """Update a tool's location, status, and assignee in one query."""
        cursor = await self.db.execute(
            """UPDATE tools
               SET location_type = ?, location_id = ?,
                   status = ?, assigned_to = ?
               WHERE id = ?""",
            (location_type, location_id, status, assigned_to, tool_id),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def get_dashboard_counts(self) -> dict:
        """Get aggregate counts for the tools dashboard."""
        sql = """
            SELECT
                COUNT(*) AS total_tools,
                COALESCE(SUM(CASE WHEN status = 'available' THEN 1 ELSE 0 END), 0) AS available,
                COALESCE(SUM(CASE WHEN status = 'checked_out' THEN 1 ELSE 0 END), 0) AS checked_out,
                COALESCE(SUM(CASE WHEN status = 'in_maintenance' THEN 1 ELSE 0 END), 0) AS in_maintenance,
                COALESCE(SUM(CASE WHEN status IN ('lost', 'damaged') THEN 1 ELSE 0 END), 0) AS lost_or_damaged,
                COALESCE(SUM(CASE WHEN location_type = 'warehouse' THEN 1 ELSE 0 END), 0) AS at_warehouse,
                COALESCE(SUM(CASE WHEN location_type = 'truck' THEN 1 ELSE 0 END), 0) AS on_trucks,
                COALESCE(SUM(CASE WHEN location_type = 'job' THEN 1 ELSE 0 END), 0) AS at_jobs
            FROM tools
            WHERE is_active = 1
        """
        cursor = await self.db.execute(sql)
        return await cursor.fetchone()


# ─── 2. KitTemplateRepo ──────────────────────────────────────────────

class KitTemplateRepo(BaseRepo):
    """Repository for the `kit_templates` table."""
    TABLE = "kit_templates"

    async def get_for_tool(self, tool_id: int) -> list[dict]:
        """Get all kit template items for a tool, ordered by sort_order."""
        cursor = await self.db.execute(
            """SELECT * FROM kit_templates
               WHERE tool_id = ? ORDER BY sort_order ASC, id ASC""",
            (tool_id,),
        )
        return await cursor.fetchall()

    async def count_for_tool(self, tool_id: int) -> int:
        """Count kit template items for a tool."""
        cursor = await self.db.execute(
            "SELECT COUNT(*) AS cnt FROM kit_templates WHERE tool_id = ?",
            (tool_id,),
        )
        row = await cursor.fetchone()
        return row["cnt"] if row else 0


# ─── 3. ToolMovementRepo ─────────────────────────────────────────────

class ToolMovementRepo(BaseRepo):
    """Repository for the `tool_movements` table (insert-only audit log)."""
    TABLE = "tool_movements"

    async def get_for_tool(
        self, tool_id: int, *, limit: int = 50, offset: int = 0
    ) -> list[dict]:
        """Get movement history for a tool with performer names."""
        sql = """
            SELECT tm.*,
                   pu.display_name AS performed_by_name,
                   vu.display_name AS verified_by_name,
                   t.tool_number, t.name AS tool_name
            FROM tool_movements tm
            LEFT JOIN users pu ON pu.id = tm.performed_by
            LEFT JOIN users vu ON vu.id = tm.verified_by
            LEFT JOIN tools t ON t.id = tm.tool_id
            WHERE tm.tool_id = ?
            ORDER BY tm.created_at DESC
            LIMIT ? OFFSET ?
        """
        cursor = await self.db.execute(sql, (tool_id, limit, offset))
        return await cursor.fetchall()

    async def get_recent(self, *, limit: int = 20) -> list[dict]:
        """Get most recent movements across all tools."""
        sql = """
            SELECT tm.*,
                   pu.display_name AS performed_by_name,
                   t.tool_number, t.name AS tool_name
            FROM tool_movements tm
            LEFT JOIN users pu ON pu.id = tm.performed_by
            LEFT JOIN tools t ON t.id = tm.tool_id
            ORDER BY tm.created_at DESC
            LIMIT ?
        """
        cursor = await self.db.execute(sql, (limit,))
        return await cursor.fetchall()


# ─── 4. KitVerificationSessionRepo ───────────────────────────────────

class KitVerificationSessionRepo(BaseRepo):
    """Repository for `kit_verification_sessions`."""
    TABLE = "kit_verification_sessions"

    async def get_for_tool(
        self, tool_id: int, *, limit: int = 20
    ) -> list[dict]:
        """Get verification sessions for a tool."""
        sql = """
            SELECT kvs.*,
                   u.display_name AS verified_by_name,
                   t.tool_number, t.name AS tool_name
            FROM kit_verification_sessions kvs
            LEFT JOIN users u ON u.id = kvs.verified_by
            LEFT JOIN tools t ON t.id = kvs.tool_id
            WHERE kvs.tool_id = ?
            ORDER BY kvs.created_at DESC
            LIMIT ?
        """
        cursor = await self.db.execute(sql, (tool_id, limit))
        return await cursor.fetchall()

    async def get_latest_for_tool(self, tool_id: int) -> dict | None:
        """Get the most recent verification session for a tool."""
        sql = """
            SELECT kvs.*,
                   u.display_name AS verified_by_name
            FROM kit_verification_sessions kvs
            LEFT JOIN users u ON u.id = kvs.verified_by
            WHERE kvs.tool_id = ?
            ORDER BY kvs.created_at DESC
            LIMIT 1
        """
        cursor = await self.db.execute(sql, (tool_id,))
        return await cursor.fetchone()


# ─── 5. KitVerificationItemRepo ──────────────────────────────────────

class KitVerificationItemRepo(BaseRepo):
    """Repository for `kit_verification_items`."""
    TABLE = "kit_verification_items"

    async def get_for_session(self, session_id: int) -> list[dict]:
        """Get all checklist items for a session, joined with template data."""
        sql = """
            SELECT kvi.*,
                   kt.component_name, kt.component_type,
                   kt.qty_required, kt.is_critical
            FROM kit_verification_items kvi
            LEFT JOIN kit_templates kt ON kt.id = kvi.template_item_id
            WHERE kvi.session_id = ?
            ORDER BY kt.sort_order ASC, kt.id ASC
        """
        cursor = await self.db.execute(sql, (session_id,))
        return await cursor.fetchall()

    async def bulk_insert(
        self, session_id: int, template_items: list[dict]
    ) -> None:
        """Pre-populate verification items from kit templates."""
        for item in template_items:
            await self.db.execute(
                """INSERT INTO kit_verification_items
                   (session_id, template_item_id, is_present)
                   VALUES (?, ?, 0)""",
                (session_id, item["id"]),
            )
        await self.db.commit()


# ─── 6. ToolMaintenanceTypeRepo ──────────────────────────────────────

class ToolMaintenanceTypeRepo(BaseRepo):
    """Repository for `tool_maintenance_types`."""
    TABLE = "tool_maintenance_types"

    async def list_active(self) -> list[dict]:
        """Get all active maintenance types, sorted."""
        cursor = await self.db.execute(
            """SELECT * FROM tool_maintenance_types
               WHERE is_active = 1
               ORDER BY sort_order ASC, id ASC"""
        )
        return await cursor.fetchall()

    async def get_by_name(self, name: str) -> dict | None:
        """Look up a maintenance type by name."""
        cursor = await self.db.execute(
            "SELECT * FROM tool_maintenance_types WHERE name = ?", (name,)
        )
        return await cursor.fetchone()


# ─── 7. ToolMaintenanceScheduleRepo ──────────────────────────────────

class ToolMaintenanceScheduleRepo(BaseRepo):
    """Repository for `tool_maintenance_schedules`."""
    TABLE = "tool_maintenance_schedules"
    HAS_UPDATED_AT = True

    async def get_for_tool(self, tool_id: int) -> list[dict]:
        """Get all maintenance schedules for a tool with type names."""
        sql = """
            SELECT tms.*, tmt.name AS maintenance_type_name
            FROM tool_maintenance_schedules tms
            LEFT JOIN tool_maintenance_types tmt ON tmt.id = tms.maintenance_type_id
            WHERE tms.tool_id = ?
            ORDER BY tmt.sort_order ASC, tms.id ASC
        """
        cursor = await self.db.execute(sql, (tool_id,))
        return await cursor.fetchall()

    async def get_overdue(self, *, limit: int = 50) -> list[dict]:
        """Get overdue maintenance schedules across all tools."""
        sql = """
            SELECT tms.*, tmt.name AS maintenance_type_name,
                   t.tool_number, t.name AS tool_name,
                   CAST(julianday('now') - julianday(tms.next_due_date) AS INTEGER) AS days_overdue
            FROM tool_maintenance_schedules tms
            JOIN tool_maintenance_types tmt ON tmt.id = tms.maintenance_type_id
            JOIN tools t ON t.id = tms.tool_id
            WHERE tms.is_enabled = 1
              AND tms.next_due_date IS NOT NULL
              AND tms.next_due_date < date('now')
              AND t.is_active = 1
            ORDER BY tms.next_due_date ASC
            LIMIT ?
        """
        cursor = await self.db.execute(sql, (limit,))
        return await cursor.fetchall()

    async def get_upcoming(self, *, days_ahead: int = 14, limit: int = 50) -> list[dict]:
        """Get maintenance schedules due within N days."""
        sql = """
            SELECT tms.*, tmt.name AS maintenance_type_name,
                   t.tool_number, t.name AS tool_name,
                   CAST(julianday(tms.next_due_date) - julianday('now') AS INTEGER) AS days_until_due
            FROM tool_maintenance_schedules tms
            JOIN tool_maintenance_types tmt ON tmt.id = tms.maintenance_type_id
            JOIN tools t ON t.id = tms.tool_id
            WHERE tms.is_enabled = 1
              AND tms.next_due_date IS NOT NULL
              AND tms.next_due_date >= date('now')
              AND tms.next_due_date <= date('now', '+' || ? || ' days')
              AND t.is_active = 1
            ORDER BY tms.next_due_date ASC
            LIMIT ?
        """
        cursor = await self.db.execute(sql, (days_ahead, limit))
        return await cursor.fetchall()

    async def upsert(
        self, tool_id: int, maintenance_type_id: int, data: dict
    ) -> int:
        """Insert or update a schedule entry (UNIQUE on tool+type)."""
        existing = await self.db.execute(
            """SELECT id FROM tool_maintenance_schedules
               WHERE tool_id = ? AND maintenance_type_id = ?""",
            (tool_id, maintenance_type_id),
        )
        row = await existing.fetchone()
        if row:
            await self.update(row["id"], data)
            return row["id"]
        else:
            return await self.insert({
                "tool_id": tool_id,
                "maintenance_type_id": maintenance_type_id,
                **data,
            })

    async def count_overdue(self) -> int:
        """Count total overdue maintenance items across all active tools."""
        cursor = await self.db.execute(
            """SELECT COUNT(*) AS cnt
               FROM tool_maintenance_schedules tms
               JOIN tools t ON t.id = tms.tool_id
               WHERE tms.is_enabled = 1
                 AND tms.next_due_date IS NOT NULL
                 AND tms.next_due_date < date('now')
                 AND t.is_active = 1"""
        )
        row = await cursor.fetchone()
        return row["cnt"] if row else 0


# ─── 8. ToolMaintenanceRecordRepo ────────────────────────────────────

class ToolMaintenanceRecordRepo(BaseRepo):
    """Repository for `tool_maintenance_records` (immutable service history)."""
    TABLE = "tool_maintenance_records"

    async def get_for_tool(
        self, tool_id: int, *, limit: int = 50, offset: int = 0
    ) -> list[dict]:
        """Get service history for a tool with type name and performer."""
        sql = """
            SELECT tmr.*,
                   tmt.name AS maintenance_type_name,
                   u.display_name AS performed_by_name
            FROM tool_maintenance_records tmr
            LEFT JOIN tool_maintenance_types tmt ON tmt.id = tmr.maintenance_type_id
            LEFT JOIN users u ON u.id = tmr.performed_by
            WHERE tmr.tool_id = ?
            ORDER BY tmr.service_date DESC, tmr.id DESC
            LIMIT ? OFFSET ?
        """
        cursor = await self.db.execute(sql, (tool_id, limit, offset))
        return await cursor.fetchall()

    async def get_cost_summary(self, tool_id: int) -> dict:
        """Get total cost and count of services for a tool."""
        cursor = await self.db.execute(
            """SELECT COUNT(*) AS total_services,
                      COALESCE(SUM(cost), 0) AS total_cost
               FROM tool_maintenance_records WHERE tool_id = ?""",
            (tool_id,),
        )
        return await cursor.fetchone()
