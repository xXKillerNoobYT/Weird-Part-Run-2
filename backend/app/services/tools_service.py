"""
Tools & Kits service — business logic for Phase 9.

Orchestrates all 8 tool repositories to provide:
  - Tool CRUD with automatic registration movements
  - Checkout / Return workflow with kit verification triggers
  - Kit template management (auto-toggle has_kit flag)
  - Kit verification sessions (pre-populate + complete)
  - Maintenance cascade (log service → update schedule → recompute next_due)
  - Dashboard stats aggregation
  - QR barcode lookup
"""

from __future__ import annotations

import logging
from datetime import date, timedelta
from typing import Any

import aiosqlite

from app.repositories.tools_repo import (
    KitTemplateRepo,
    KitVerificationItemRepo,
    KitVerificationSessionRepo,
    ToolMaintenanceRecordRepo,
    ToolMaintenanceScheduleRepo,
    ToolMaintenanceTypeRepo,
    ToolMovementRepo,
    ToolRepo,
)

logger = logging.getLogger(__name__)


class ToolsService:
    """Central service for all tool-related business logic."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.tool_repo = ToolRepo(db)
        self.kit_repo = KitTemplateRepo(db)
        self.movement_repo = ToolMovementRepo(db)
        self.verification_session_repo = KitVerificationSessionRepo(db)
        self.verification_item_repo = KitVerificationItemRepo(db)
        self.maint_type_repo = ToolMaintenanceTypeRepo(db)
        self.maint_schedule_repo = ToolMaintenanceScheduleRepo(db)
        self.maint_record_repo = ToolMaintenanceRecordRepo(db)

    # ═══════════════════════════════════════════════════════════════
    # TOOL CRUD
    # ═══════════════════════════════════════════════════════════════

    async def list_tools(
        self,
        *,
        category: str | None = None,
        status: str | None = None,
        location_type: str | None = None,
        search: str | None = None,
        is_active: bool = True,
        limit: int = 100,
        offset: int = 0,
    ) -> dict:
        """List tools with pagination and filters.

        Returns {items: [...], total: int}.
        """
        items = await self.tool_repo.list_with_details(
            category=category,
            status=status,
            location_type=location_type,
            search=search,
            is_active=is_active,
            limit=limit,
            offset=offset,
        )
        total = await self.tool_repo.count_filtered(
            category=category,
            status=status,
            location_type=location_type,
            search=search,
            is_active=is_active,
        )
        return {"items": [dict(r) for r in items], "total": total}

    async def create_tool(self, data: dict, user_id: int) -> dict:
        """Register a new tool.

        - Validates tool_number uniqueness
        - Generates barcode value from tool_number
        - Inserts tool row
        - Creates a 'register' movement entry
        - Initializes default maintenance schedules
        - Returns the full tool record with joined details
        """
        # Duplicate guard
        existing = await self.tool_repo.get_by_number(data["tool_number"])
        if existing:
            raise ValueError(
                f"Tool number '{data['tool_number']}' already exists"
            )

        # Auto-generate barcode from tool_number
        data["barcode"] = f"/tools/scan/{data['tool_number']}"

        tool_id = await self.tool_repo.insert(data)

        # Log the registration movement
        await self.movement_repo.insert({
            "tool_id": tool_id,
            "to_location_type": data.get("location_type", "warehouse"),
            "to_location_id": data.get("location_id"),
            "movement_type": "register",
            "performed_by": user_id,
            "condition_at_move": data.get("condition_rating", 5),
        })

        # Initialize default maintenance schedules from all active types
        await self._init_default_schedules(tool_id)

        return await self.get_tool(tool_id)

    async def get_tool(self, tool_id: int) -> dict | None:
        """Get a single tool with full details."""
        row = await self.tool_repo.get_with_details(tool_id)
        return dict(row) if row else None

    async def get_tool_by_number(self, tool_number: str) -> dict | None:
        """Look up a tool by its tool_number (used by QR scan)."""
        row = await self.tool_repo.get_by_number(tool_number)
        if not row:
            return None
        return await self.get_tool(row["id"])

    async def get_tool_by_barcode(self, barcode: str) -> dict | None:
        """Look up a tool by QR barcode value."""
        row = await self.tool_repo.get_by_barcode(barcode)
        if not row:
            return None
        return await self.get_tool(row["id"])

    async def update_tool(self, tool_id: int, data: dict) -> dict | None:
        """Update tool fields. Returns updated tool or None if not found."""
        tool = await self.tool_repo.get_by_id(tool_id)
        if not tool:
            return None

        # Strip None values — only update fields that were provided
        patch = {k: v for k, v in data.items() if v is not None}
        if patch:
            await self.tool_repo.update(tool_id, patch)

        return await self.get_tool(tool_id)

    async def retire_tool(self, tool_id: int, user_id: int) -> dict | None:
        """Retire a tool (soft delete).

        Sets status='retired', is_active=0, logs a retirement movement.
        """
        tool = await self.tool_repo.get_by_id(tool_id)
        if not tool:
            return None

        await self.tool_repo.update(tool_id, {
            "status": "retired",
            "is_active": 0,
        })

        await self.movement_repo.insert({
            "tool_id": tool_id,
            "from_location_type": tool["location_type"],
            "from_location_id": tool["location_id"],
            "movement_type": "retire",
            "performed_by": user_id,
        })

        return await self.get_tool(tool_id)

    # ═══════════════════════════════════════════════════════════════
    # CHECKOUT / RETURN
    # ═══════════════════════════════════════════════════════════════

    async def checkout_tool(
        self, tool_id: int, data: dict, user_id: int
    ) -> dict:
        """Check out a tool from its current location to a new one.

        Validates tool is available, updates location/status,
        logs a checkout movement. Returns the updated tool.
        """
        tool = await self.tool_repo.get_by_id(tool_id)
        if not tool:
            raise ValueError(f"Tool {tool_id} not found")

        if tool["status"] not in ("available",):
            raise ValueError(
                f"Tool is currently '{tool['status']}' — only available tools "
                f"can be checked out"
            )

        to_type = data["to_location_type"]
        to_id = data["to_location_id"]

        # Update tool location and status
        await self.tool_repo.update_location(
            tool_id,
            location_type=to_type,
            location_id=to_id,
            status="checked_out",
            assigned_to=user_id,
        )

        # Log the movement
        movement_id = await self.movement_repo.insert({
            "tool_id": tool_id,
            "from_location_type": tool["location_type"],
            "from_location_id": tool["location_id"],
            "to_location_type": to_type,
            "to_location_id": to_id,
            "movement_type": "checkout",
            "reason": data.get("reason"),
            "job_id": data.get("job_id"),
            "performed_by": user_id,
            "condition_at_move": data.get("condition_at_move"),
        })

        updated = await self.get_tool(tool_id)

        # Attach movement_id for kit verification trigger (caller may use)
        if updated:
            updated["_movement_id"] = movement_id

        return updated

    async def return_tool(
        self, tool_id: int, data: dict, user_id: int
    ) -> dict:
        """Return a tool (typically back to warehouse).

        Validates tool is checked_out, resets location/status,
        logs a return movement. Returns the updated tool.
        """
        tool = await self.tool_repo.get_by_id(tool_id)
        if not tool:
            raise ValueError(f"Tool {tool_id} not found")

        if tool["status"] not in ("checked_out",):
            raise ValueError(
                f"Tool is currently '{tool['status']}' — only checked-out "
                f"tools can be returned"
            )

        to_type = data.get("to_location_type", "warehouse")
        to_id = data.get("to_location_id")

        # Update tool location and status
        await self.tool_repo.update_location(
            tool_id,
            location_type=to_type,
            location_id=to_id,
            status="available",
            assigned_to=None,  # clear assignee on return
        )

        # Log the movement
        movement_id = await self.movement_repo.insert({
            "tool_id": tool_id,
            "from_location_type": tool["location_type"],
            "from_location_id": tool["location_id"],
            "to_location_type": to_type,
            "to_location_id": to_id,
            "movement_type": "return",
            "reason": data.get("reason"),
            "performed_by": user_id,
            "condition_at_move": data.get("condition_at_move"),
        })

        updated = await self.get_tool(tool_id)
        if updated:
            updated["_movement_id"] = movement_id

        return updated

    # ═══════════════════════════════════════════════════════════════
    # KIT TEMPLATES
    # ═══════════════════════════════════════════════════════════════

    async def get_kit_template(self, tool_id: int) -> list[dict]:
        """Get all kit template items for a tool."""
        items = await self.kit_repo.get_for_tool(tool_id)
        return [dict(r) for r in items]

    async def add_kit_component(
        self, tool_id: int, data: dict
    ) -> dict:
        """Add a required component to a tool's kit template.

        Auto-sets has_kit=1 on the tool if this is the first component.
        """
        tool = await self.tool_repo.get_by_id(tool_id)
        if not tool:
            raise ValueError(f"Tool {tool_id} not found")

        data["tool_id"] = tool_id
        item_id = await self.kit_repo.insert(data)

        # Auto-toggle has_kit flag
        if not tool["has_kit"]:
            await self.tool_repo.update(tool_id, {"has_kit": 1})

        return dict(await self.kit_repo.get_by_id(item_id))

    async def update_kit_component(
        self, tool_id: int, item_id: int, data: dict
    ) -> dict | None:
        """Update a kit template component."""
        item = await self.kit_repo.get_by_id(item_id)
        if not item or item["tool_id"] != tool_id:
            return None

        patch = {k: v for k, v in data.items() if v is not None}
        if patch:
            await self.kit_repo.update(item_id, patch)

        return dict(await self.kit_repo.get_by_id(item_id))

    async def remove_kit_component(self, tool_id: int, item_id: int) -> bool:
        """Remove a component from a tool's kit template.

        Auto-clears has_kit=0 if this was the last component.
        """
        item = await self.kit_repo.get_by_id(item_id)
        if not item or item["tool_id"] != tool_id:
            return False

        await self.kit_repo.delete(item_id)

        # Check if any components remain
        remaining = await self.kit_repo.count_for_tool(tool_id)
        if remaining == 0:
            await self.tool_repo.update(tool_id, {"has_kit": 0})

        return True

    # ═══════════════════════════════════════════════════════════════
    # KIT VERIFICATION
    # ═══════════════════════════════════════════════════════════════

    async def start_verification(
        self,
        tool_id: int,
        trigger_type: str,
        user_id: int,
        movement_id: int | None = None,
    ) -> dict:
        """Start a kit verification session.

        Creates the session and pre-populates checklist items from
        the tool's kit template (all unchecked).

        Returns the session with its items.
        """
        tool = await self.tool_repo.get_by_id(tool_id)
        if not tool:
            raise ValueError(f"Tool {tool_id} not found")

        if not tool["has_kit"]:
            raise ValueError(
                f"Tool '{tool['tool_number']}' has no kit template to verify"
            )

        # Create session
        session_id = await self.verification_session_repo.insert({
            "tool_id": tool_id,
            "movement_id": movement_id,
            "verified_by": user_id,
            "trigger_type": trigger_type,
        })

        # Pre-populate checklist items from kit template
        template_items = await self.kit_repo.get_for_tool(tool_id)
        if template_items:
            await self.verification_item_repo.bulk_insert(
                session_id, [dict(t) for t in template_items]
            )

        return await self._get_session_with_items(session_id)

    async def complete_verification(
        self,
        tool_id: int,
        session_id: int,
        items: list[dict],
        notes: str | None = None,
    ) -> dict:
        """Complete a verification session.

        Updates each checklist item, computes missing_count for
        critical items, marks the session as complete.
        """
        session = await self.verification_session_repo.get_by_id(session_id)
        if not session:
            raise ValueError(f"Verification session {session_id} not found")
        if session["tool_id"] != tool_id:
            raise ValueError("Session does not belong to this tool")
        if session["is_complete"]:
            raise ValueError("Session is already complete")

        # Update each item
        for item_data in items:
            item_id = item_data["item_id"]
            update_fields: dict[str, Any] = {
                "is_present": 1 if item_data["is_present"] else 0,
            }
            if item_data.get("condition_rating") is not None:
                update_fields["condition_rating"] = item_data["condition_rating"]
            if item_data.get("notes") is not None:
                update_fields["notes"] = item_data["notes"]

            await self.verification_item_repo.update(item_id, update_fields)

        # Compute missing count (only critical items)
        all_items = await self.verification_item_repo.get_for_session(session_id)
        missing_count = sum(
            1 for i in all_items
            if i["is_critical"] and not i["is_present"]
        )

        # Mark session complete
        await self.verification_session_repo.update(session_id, {
            "is_complete": 1,
            "missing_count": missing_count,
            "notes": notes,
        })

        return await self._get_session_with_items(session_id)

    async def get_verification_history(
        self, tool_id: int, *, limit: int = 20
    ) -> list[dict]:
        """Get verification sessions for a tool."""
        sessions = await self.verification_session_repo.get_for_tool(
            tool_id, limit=limit
        )
        return [dict(s) for s in sessions]

    async def _get_session_with_items(self, session_id: int) -> dict:
        """Get a verification session with all its checklist items."""
        session = await self.verification_session_repo.get_by_id(session_id)
        if not session:
            raise ValueError(f"Session {session_id} not found")

        items = await self.verification_item_repo.get_for_session(session_id)
        result = dict(session)
        result["items"] = [dict(i) for i in items]
        return result

    # ═══════════════════════════════════════════════════════════════
    # TOOL MOVEMENTS
    # ═══════════════════════════════════════════════════════════════

    async def get_movement_history(
        self, tool_id: int, *, limit: int = 50, offset: int = 0
    ) -> list[dict]:
        """Get movement history for a tool."""
        rows = await self.movement_repo.get_for_tool(
            tool_id, limit=limit, offset=offset
        )
        return [dict(r) for r in rows]

    async def get_recent_movements(self, *, limit: int = 20) -> list[dict]:
        """Get most recent movements across all tools."""
        rows = await self.movement_repo.get_recent(limit=limit)
        return [dict(r) for r in rows]

    # ═══════════════════════════════════════════════════════════════
    # MAINTENANCE TYPES (admin config)
    # ═══════════════════════════════════════════════════════════════

    async def list_maintenance_types(self) -> list[dict]:
        """Get all active maintenance types."""
        rows = await self.maint_type_repo.list_active()
        return [dict(r) for r in rows]

    async def create_maintenance_type(self, data: dict) -> dict:
        """Create a new maintenance type."""
        existing = await self.maint_type_repo.get_by_name(data["name"])
        if existing:
            raise ValueError(
                f"Maintenance type '{data['name']}' already exists"
            )
        type_id = await self.maint_type_repo.insert(data)
        return dict(await self.maint_type_repo.get_by_id(type_id))

    async def update_maintenance_type(
        self, type_id: int, data: dict
    ) -> dict | None:
        """Update a maintenance type."""
        existing = await self.maint_type_repo.get_by_id(type_id)
        if not existing:
            return None
        patch = {k: v for k, v in data.items() if v is not None}
        if patch:
            await self.maint_type_repo.update(type_id, patch)
        return dict(await self.maint_type_repo.get_by_id(type_id))

    async def delete_maintenance_type(self, type_id: int) -> bool:
        """Soft-delete a maintenance type (set is_active = 0).

        Hard delete would violate FK constraints from schedules/records.
        """
        existing = await self.maint_type_repo.get_by_id(type_id)
        if not existing:
            return False
        await self.maint_type_repo.update(type_id, {"is_active": 0})
        return True

    # ═══════════════════════════════════════════════════════════════
    # PER-TOOL MAINTENANCE SCHEDULES
    # ═══════════════════════════════════════════════════════════════

    async def get_tool_schedule(self, tool_id: int) -> list[dict]:
        """Get maintenance schedules for a specific tool."""
        rows = await self.maint_schedule_repo.get_for_tool(tool_id)
        return [dict(r) for r in rows]

    async def set_tool_schedule(
        self, tool_id: int, data: dict
    ) -> dict:
        """Create or update a maintenance schedule for a tool.

        Uses upsert — if a schedule for this tool+type exists,
        it's updated; otherwise a new one is created.
        """
        tool = await self.tool_repo.get_by_id(tool_id)
        if not tool:
            raise ValueError(f"Tool {tool_id} not found")

        maint_type = await self.maint_type_repo.get_by_id(
            data["maintenance_type_id"]
        )
        if not maint_type:
            raise ValueError(
                f"Maintenance type {data['maintenance_type_id']} not found"
            )

        schedule_data = {
            "interval_days": data.get("interval_days")
                or maint_type.get("default_interval_days"),
            "is_enabled": data.get("is_enabled", True),
            "notes": data.get("notes"),
        }

        schedule_id = await self.maint_schedule_repo.upsert(
            tool_id, data["maintenance_type_id"], schedule_data
        )

        row = await self.maint_schedule_repo.get_by_id(schedule_id)
        return dict(row) if row else {}

    async def _init_default_schedules(self, tool_id: int) -> None:
        """Initialize default maintenance schedules for a newly registered tool.

        Creates schedule entries for all active maintenance types that have
        a default_interval_days. Calculates next_due_date from today.
        """
        types = await self.maint_type_repo.list_active()
        today = date.today().isoformat()

        for mtype in types:
            interval = mtype["default_interval_days"]
            if not interval:
                continue  # skip types with no default interval

            next_due = (
                date.today() + timedelta(days=interval)
            ).isoformat()

            await self.maint_schedule_repo.insert({
                "tool_id": tool_id,
                "maintenance_type_id": mtype["id"],
                "interval_days": interval,
                "last_performed_at": today,
                "next_due_date": next_due,
                "is_enabled": 1,
            })

    # ═══════════════════════════════════════════════════════════════
    # MAINTENANCE RECORDS (service history)
    # ═══════════════════════════════════════════════════════════════

    async def log_service(
        self, tool_id: int, data: dict, user_id: int
    ) -> dict:
        """Log a maintenance service performed on a tool.

        - Inserts an immutable maintenance record
        - Cascades to the schedule: updates last_performed_at
          and recomputes next_due_date
        - Returns the new record with joined fields
        """
        tool = await self.tool_repo.get_by_id(tool_id)
        if not tool:
            raise ValueError(f"Tool {tool_id} not found")

        maint_type = await self.maint_type_repo.get_by_id(
            data["maintenance_type_id"]
        )
        if not maint_type:
            raise ValueError(
                f"Maintenance type {data['maintenance_type_id']} not found"
            )

        service_date = data.get("service_date") or date.today().isoformat()

        record_id = await self.maint_record_repo.insert({
            "tool_id": tool_id,
            "maintenance_type_id": data["maintenance_type_id"],
            "service_date": service_date,
            "cost": data.get("cost", 0),
            "vendor": data.get("vendor"),
            "description": data.get("description"),
            "performed_by": user_id,
            "notes": data.get("notes"),
        })

        # Cascade: update schedule's last_performed_at and recompute next_due
        await self._cascade_schedule_update(
            tool_id, data["maintenance_type_id"], service_date
        )

        row = await self.maint_record_repo.get_by_id(record_id)
        return dict(row) if row else {}

    async def _cascade_schedule_update(
        self,
        tool_id: int,
        maintenance_type_id: int,
        service_date: str,
    ) -> None:
        """After logging a service, update the matching schedule.

        Sets last_performed_at = service_date and recomputes
        next_due_date = service_date + interval_days.
        """
        # Find the schedule for this tool + type
        schedules = await self.maint_schedule_repo.get_for_tool(tool_id)
        target = None
        for s in schedules:
            if s["maintenance_type_id"] == maintenance_type_id:
                target = s
                break

        if not target:
            # No schedule exists — create one using type defaults
            mtype = await self.maint_type_repo.get_by_id(maintenance_type_id)
            interval = mtype["default_interval_days"] if mtype else None
            next_due = None
            if interval:
                next_due = (
                    date.fromisoformat(service_date) + timedelta(days=interval)
                ).isoformat()

            await self.maint_schedule_repo.insert({
                "tool_id": tool_id,
                "maintenance_type_id": maintenance_type_id,
                "interval_days": interval,
                "last_performed_at": service_date,
                "next_due_date": next_due,
                "is_enabled": 1,
            })
            return

        # Update existing schedule
        interval = target["interval_days"]
        next_due = None
        if interval:
            next_due = (
                date.fromisoformat(service_date) + timedelta(days=interval)
            ).isoformat()

        await self.maint_schedule_repo.update(target["id"], {
            "last_performed_at": service_date,
            "next_due_date": next_due,
        })

    async def get_service_history(
        self, tool_id: int, *, limit: int = 50, offset: int = 0
    ) -> list[dict]:
        """Get maintenance service history for a tool."""
        rows = await self.maint_record_repo.get_for_tool(
            tool_id, limit=limit, offset=offset
        )
        return [dict(r) for r in rows]

    async def get_cost_summary(self, tool_id: int) -> dict:
        """Get total maintenance cost summary for a tool."""
        row = await self.maint_record_repo.get_cost_summary(tool_id)
        return dict(row) if row else {"total_services": 0, "total_cost": 0}

    # ═══════════════════════════════════════════════════════════════
    # MAINTENANCE ALERTS
    # ═══════════════════════════════════════════════════════════════

    async def get_maintenance_alerts(
        self, *, days_ahead: int = 14
    ) -> dict:
        """Get all maintenance alerts — overdue + upcoming.

        Returns {overdue: [...], upcoming: [...]} with tool details.
        """
        overdue = await self.maint_schedule_repo.get_overdue()
        upcoming = await self.maint_schedule_repo.get_upcoming(
            days_ahead=days_ahead
        )

        return {
            "overdue": [
                {
                    **dict(r),
                    "is_overdue": True,
                    "days_until_due": -r["days_overdue"],
                }
                for r in overdue
            ],
            "upcoming": [
                {
                    **dict(r),
                    "is_overdue": False,
                }
                for r in upcoming
            ],
        }

    # ═══════════════════════════════════════════════════════════════
    # DASHBOARD
    # ═══════════════════════════════════════════════════════════════

    async def get_dashboard_stats(self) -> dict:
        """Aggregate dashboard stats for all active tools.

        Combines tool status/location counts with maintenance alerts
        and kit verification gaps.
        """
        counts = await self.tool_repo.get_dashboard_counts()
        stats = dict(counts) if counts else {}

        # Add overdue maintenance count
        overdue_maint = await self.maint_schedule_repo.count_overdue()
        stats["overdue_maintenance"] = overdue_maint

        # Count kits with missing items (from most recent complete verifications)
        kits_missing = await self._count_kits_with_missing()
        stats["kits_with_missing_items"] = kits_missing

        return stats

    async def _count_kits_with_missing(self) -> int:
        """Count tools whose most recent kit verification had missing critical items."""
        cursor = await self.db.execute("""
            SELECT COUNT(DISTINCT tool_id) AS cnt
            FROM kit_verification_sessions
            WHERE is_complete = 1 AND missing_count > 0
              AND id IN (
                  SELECT MAX(id) FROM kit_verification_sessions
                  WHERE is_complete = 1
                  GROUP BY tool_id
              )
        """)
        row = await cursor.fetchone()
        return row["cnt"] if row else 0

    # ═══════════════════════════════════════════════════════════════
    # LOCATION QUERIES (cross-module visibility)
    # ═══════════════════════════════════════════════════════════════

    async def get_tools_at_location(
        self, location_type: str, location_id: int
    ) -> list[dict]:
        """Get all active tools at a specific location.

        Used by warehouse, truck, and job detail views.
        """
        rows = await self.tool_repo.get_at_location(location_type, location_id)
        return [dict(r) for r in rows]
