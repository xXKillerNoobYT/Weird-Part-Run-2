"""
Inspection service — manage templates, start inspections, submit results.

Workflow:
  1. Admin creates a template with checklist items
  2. Driver starts an inspection → record created with items from template
  3. Driver submits each item (pass/fail/na + optional photo + notes)
  4. Driver completes the inspection → overall_result calculated
  5. Manager can review failed inspections across the fleet

Business rules:
  - overall_result: "pass" if all items pass/na, "fail" if any critical fails,
    "needs_attention" if any warning/info fails
  - An inspection cannot be completed until all items are submitted (not pending)
"""

from __future__ import annotations

import logging
from datetime import date as _date, datetime
from typing import Any

import aiosqlite

from app.repositories.inspection_repo import (
    InspectionRecordItemRepo,
    InspectionRecordRepo,
    InspectionTemplateItemRepo,
    InspectionTemplateRepo,
)

logger = logging.getLogger(__name__)


class InspectionService:
    """Orchestrates vehicle inspection workflows."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.template_repo = InspectionTemplateRepo(db)
        self.template_item_repo = InspectionTemplateItemRepo(db)
        self.record_repo = InspectionRecordRepo(db)
        self.record_item_repo = InspectionRecordItemRepo(db)

    # ── Template Management ────────────────────────────────────

    async def create_template(self, data: dict) -> dict:
        """Create a template with items."""
        items = data.pop("items", [])

        template_id = await self.template_repo.insert({
            "name": data["name"],
            "description": data.get("description"),
            "vehicle_type": data.get("vehicle_type"),
            "inspection_type": data.get("inspection_type", "pre_trip"),
        })

        for idx, item in enumerate(items):
            await self.template_item_repo.insert({
                "template_id": template_id,
                "sort_order": item.get("sort_order", idx),
                "category": item.get("category", "General"),
                "item_name": item["item_name"],
                "description": item.get("description"),
                "severity": item.get("severity", "warning"),
                "requires_photo": int(item.get("requires_photo", False)),
            })

        await self.db.commit()
        return await self.template_repo.get_with_items(template_id)

    async def update_template(self, template_id: int, data: dict) -> dict | None:
        """Update template metadata and optionally replace items."""
        existing = await self.template_repo.get_by_id(template_id)
        if not existing:
            return None

        items = data.pop("items", None)

        # Update template fields
        patch = {k: v for k, v in data.items() if v is not None}
        if patch:
            await self.template_repo.update(template_id, patch)

        # Replace items if provided
        if items is not None:
            await self.template_item_repo.delete_for_template(template_id)
            for idx, item in enumerate(items):
                await self.template_item_repo.insert({
                    "template_id": template_id,
                    "sort_order": item.get("sort_order", idx),
                    "category": item.get("category", "General"),
                    "item_name": item["item_name"],
                    "description": item.get("description"),
                    "severity": item.get("severity", "warning"),
                    "requires_photo": int(item.get("requires_photo", False)),
                })

        await self.db.commit()
        return await self.template_repo.get_with_items(template_id)

    async def get_templates(
        self,
        *,
        vehicle_type: str | None = None,
        inspection_type: str | None = None,
        active_only: bool = True,
    ) -> list[dict]:
        """List inspection templates."""
        return await self.template_repo.list_templates(
            vehicle_type=vehicle_type,
            inspection_type=inspection_type,
            active_only=active_only,
        )

    async def get_template(self, template_id: int) -> dict | None:
        """Get a single template with items."""
        return await self.template_repo.get_with_items(template_id)

    # ── Inspection Workflow ────────────────────────────────────

    async def start_inspection(
        self,
        vehicle_id: int,
        inspector_id: int,
        data: dict,
    ) -> dict:
        """Start an inspection from a template.

        Creates the record and populates items from the template.
        """
        template = await self.template_repo.get_with_items(data["template_id"])
        if not template:
            raise ValueError(f"Template {data['template_id']} not found")

        if not template.get("items"):
            raise ValueError("Template has no items — cannot start inspection")

        record_id = await self.record_repo.insert({
            "vehicle_id": vehicle_id,
            "template_id": data["template_id"],
            "inspector_id": inspector_id,
            "inspection_type": data.get("inspection_type") or template["inspection_type"],
            "inspection_date": _date.today().isoformat(),
            "odometer_reading": data.get("odometer_reading"),
            "notes": data.get("notes"),
        })

        # Create record items from template items
        for item in template["items"]:
            await self.record_item_repo.insert({
                "record_id": record_id,
                "template_item_id": item["id"],
                "item_name": item["item_name"],
                "category": item.get("category", "General"),
                "status": "pending",
                "severity": item.get("severity", "warning"),
            })

        await self.db.commit()
        return await self.record_repo.get_with_items(record_id)

    async def submit_item(
        self,
        record_id: int,
        item_id: int,
        data: dict,
    ) -> dict:
        """Submit pass/fail result for a single inspection item."""
        item = await self.record_item_repo.get_by_id(item_id)
        if not item or item["record_id"] != record_id:
            raise ValueError("Inspection item not found")

        record = await self.record_repo.get_by_id(record_id)
        if not record:
            raise ValueError("Inspection record not found")
        if record.get("completed_at"):
            raise ValueError("Inspection already completed — cannot modify items")

        patch = {
            "status": data.get("status", "pass"),
        }
        if "photo" in data:
            patch["photo"] = data["photo"]
        if "notes" in data:
            patch["notes"] = data["notes"]

        await self.record_item_repo.update(item_id, patch)
        await self.db.commit()

        return await self.record_repo.get_with_items(record_id)

    async def complete_inspection(self, record_id: int) -> dict:
        """Finalize an inspection and calculate overall_result.

        Rules:
          - All items must be submitted (not 'pending')
          - Any critical fail → overall = 'fail'
          - Any warning/info fail → overall = 'needs_attention'
          - All pass/na → overall = 'pass'
        """
        items = await self.record_item_repo.get_for_record(record_id)
        if not items:
            raise ValueError("No inspection items found")

        pending = [i for i in items if i["status"] == "pending"]
        if pending:
            raise ValueError(
                f"{len(pending)} items still pending — complete all items first"
            )

        # Determine overall result
        has_critical_fail = any(
            i["status"] == "fail" and i["severity"] == "critical"
            for i in items
        )
        has_any_fail = any(i["status"] == "fail" for i in items)

        if has_critical_fail:
            overall = "fail"
        elif has_any_fail:
            overall = "needs_attention"
        else:
            overall = "pass"

        await self.record_repo.update(record_id, {
            "overall_result": overall,
            "completed_at": datetime.now().isoformat(),
        })
        await self.db.commit()

        return await self.record_repo.get_with_items(record_id)

    # ── Query Methods ──────────────────────────────────────────

    async def get_vehicle_inspections(
        self,
        vehicle_id: int,
        *,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """Inspection history for a vehicle."""
        return await self.record_repo.list_for_vehicle(
            vehicle_id, limit=limit, offset=offset
        )

    async def get_inspection(self, record_id: int) -> dict | None:
        """Get a single inspection with all items."""
        return await self.record_repo.get_with_items(record_id)

    async def get_pending_inspections(self) -> list[dict]:
        """Fleet-wide incomplete inspections."""
        return await self.record_repo.get_pending()

    async def get_failed_inspections(self) -> list[dict]:
        """Failed/needs_attention inspections for manager review."""
        return await self.record_repo.get_failed()
