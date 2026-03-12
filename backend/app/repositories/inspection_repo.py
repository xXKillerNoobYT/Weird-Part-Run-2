"""
Repositories for vehicle inspections — templates and completed records.

Templates define the checklist items; records capture per-vehicle results
with pass/fail, photos, and notes.
"""

from __future__ import annotations

from typing import Any

from app.repositories.base import BaseRepo


class InspectionTemplateRepo(BaseRepo):
    """Inspection template definitions (admin-managed)."""

    TABLE = "inspection_templates"
    HAS_UPDATED_AT = True

    async def list_templates(
        self,
        *,
        vehicle_type: str | None = None,
        inspection_type: str | None = None,
        active_only: bool = True,
    ) -> list[dict]:
        """List templates with optional filters."""
        conditions: list[str] = []
        params: list[Any] = []

        if active_only:
            conditions.append("is_active = 1")
        if vehicle_type:
            conditions.append("(vehicle_type IS NULL OR vehicle_type = ?)")
            params.append(vehicle_type)
        if inspection_type:
            conditions.append("inspection_type = ?")
            params.append(inspection_type)

        where = f"WHERE {' AND '.join(conditions)}" if conditions else ""
        sql = f"SELECT * FROM inspection_templates {where} ORDER BY name"
        rows = await self.db.execute(sql, params)
        return [dict(r) for r in await rows.fetchall()]

    async def get_with_items(self, template_id: int) -> dict | None:
        """Get template with its items."""
        row = await self.db.execute(
            "SELECT * FROM inspection_templates WHERE id = ?", (template_id,)
        )
        template = await row.fetchone()
        if not template:
            return None

        items_row = await self.db.execute(
            """SELECT * FROM inspection_template_items
               WHERE template_id = ? AND is_active = 1
               ORDER BY sort_order, id""",
            (template_id,),
        )
        items = [dict(i) for i in await items_row.fetchall()]

        result = dict(template)
        result["items"] = items
        return result


class InspectionTemplateItemRepo(BaseRepo):
    """Items within inspection templates."""

    TABLE = "inspection_template_items"
    HAS_UPDATED_AT = False

    async def get_for_template(self, template_id: int) -> list[dict]:
        """Get active items for a template, sorted."""
        rows = await self.db.execute(
            """SELECT * FROM inspection_template_items
               WHERE template_id = ? AND is_active = 1
               ORDER BY sort_order, id""",
            (template_id,),
        )
        return [dict(r) for r in await rows.fetchall()]

    async def delete_for_template(self, template_id: int) -> None:
        """Remove all items for a template (for replacement)."""
        await self.db.execute(
            "DELETE FROM inspection_template_items WHERE template_id = ?",
            (template_id,),
        )


class InspectionRecordRepo(BaseRepo):
    """Completed inspection records for vehicles."""

    TABLE = "inspection_records"
    HAS_UPDATED_AT = True

    async def list_for_vehicle(
        self,
        vehicle_id: int,
        *,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """Inspection history for a vehicle with joined names."""
        sql = """
            SELECT ir.*,
                   v.vehicle_name,
                   v.vehicle_number,
                   u.display_name AS inspector_name,
                   it.name AS template_name
            FROM inspection_records ir
            JOIN vehicles v ON v.id = ir.vehicle_id
            JOIN users u ON u.id = ir.inspector_id
            JOIN inspection_templates it ON it.id = ir.template_id
            WHERE ir.vehicle_id = ?
            ORDER BY ir.inspection_date DESC, ir.id DESC
            LIMIT ? OFFSET ?
        """
        rows = await self.db.execute(sql, (vehicle_id, limit, offset))
        return [dict(r) for r in await rows.fetchall()]

    async def get_with_items(self, record_id: int) -> dict | None:
        """Get inspection record with all item results."""
        row = await self.db.execute(
            """SELECT ir.*,
                      v.vehicle_name, v.vehicle_number,
                      u.display_name AS inspector_name,
                      it.name AS template_name
               FROM inspection_records ir
               JOIN vehicles v ON v.id = ir.vehicle_id
               JOIN users u ON u.id = ir.inspector_id
               JOIN inspection_templates it ON it.id = ir.template_id
               WHERE ir.id = ?""",
            (record_id,),
        )
        record = await row.fetchone()
        if not record:
            return None

        items_row = await self.db.execute(
            "SELECT * FROM inspection_record_items WHERE record_id = ? ORDER BY id",
            (record_id,),
        )
        items = [dict(i) for i in await items_row.fetchall()]

        result = dict(record)
        result["items"] = items
        return result

    async def get_pending(self) -> list[dict]:
        """Incomplete inspections across the fleet."""
        sql = """
            SELECT ir.*,
                   v.vehicle_name, v.vehicle_number,
                   u.display_name AS inspector_name,
                   it.name AS template_name
            FROM inspection_records ir
            JOIN vehicles v ON v.id = ir.vehicle_id
            JOIN users u ON u.id = ir.inspector_id
            JOIN inspection_templates it ON it.id = ir.template_id
            WHERE ir.overall_result = 'pending'
            ORDER BY ir.created_at DESC
        """
        rows = await self.db.execute(sql)
        return [dict(r) for r in await rows.fetchall()]

    async def get_failed(self) -> list[dict]:
        """Inspections with failed/needs_attention results for manager review."""
        sql = """
            SELECT ir.*,
                   v.vehicle_name, v.vehicle_number,
                   u.display_name AS inspector_name,
                   it.name AS template_name
            FROM inspection_records ir
            JOIN vehicles v ON v.id = ir.vehicle_id
            JOIN users u ON u.id = ir.inspector_id
            JOIN inspection_templates it ON it.id = ir.template_id
            WHERE ir.overall_result IN ('fail', 'needs_attention')
            ORDER BY ir.inspection_date DESC
        """
        rows = await self.db.execute(sql)
        return [dict(r) for r in await rows.fetchall()]


class InspectionRecordItemRepo(BaseRepo):
    """Individual check items within a completed inspection."""

    TABLE = "inspection_record_items"
    HAS_UPDATED_AT = False

    async def get_for_record(self, record_id: int) -> list[dict]:
        """Get all items for a record."""
        rows = await self.db.execute(
            "SELECT * FROM inspection_record_items WHERE record_id = ? ORDER BY id",
            (record_id,),
        )
        return [dict(r) for r in await rows.fetchall()]
