"""
PO Conversation Service — CRM-style conversation threads per PO (Phase 7B).

Every purchase order gets a conversation thread that can contain:
  - Manual entries: notes, call logs, email summaries, action items
  - System entries: auto-logged when PO status changes, prices update, etc.

The thread is visible on the PO Management tab and provides a full
communication history with the supplier for that order.

Additionally supports supplier-level threads that aggregate all
conversation entries across POs for a single supplier — useful for
seeing the full communication history when managing a supplier
relationship.

Follow-up tracking:
  Any entry can be flagged as "follow_up_needed".  Office staff can
  then filter for open follow-ups and mark them resolved.  This replaces
  sticky notes and email flags.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Any

import aiosqlite

from app.repositories.base import BaseRepo

logger = logging.getLogger(__name__)


# ═══════════════════════════════════════════════════════════════
# Repository
# ═══════════════════════════════════════════════════════════════

class POConversationRepo(BaseRepo):
    TABLE = "po_conversations"
    HAS_UPDATED_AT = False  # entries are immutable after creation

    async def get_thread(
        self,
        po_id: int,
        *,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict]:
        """Get all conversation entries for a PO, newest first.

        Includes the creator's display name for each entry.
        """
        cursor = await self.db.execute(
            """
            SELECT c.*,
                   u.display_name AS creator_name
            FROM po_conversations c
            LEFT JOIN users u ON u.id = c.created_by
            WHERE c.po_id = ?
            ORDER BY c.created_at DESC
            LIMIT ? OFFSET ?
            """,
            (po_id, limit, offset),
        )
        return await cursor.fetchall()

    async def get_supplier_thread(
        self,
        supplier_id: int,
        *,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict]:
        """Get all conversation entries across POs for a supplier.

        Useful for seeing the full communication history with one supplier.
        Each entry includes the PO number so the user can cross-reference.
        """
        cursor = await self.db.execute(
            """
            SELECT c.*,
                   u.display_name AS creator_name,
                   po.po_number
            FROM po_conversations c
            LEFT JOIN users u ON u.id = c.created_by
            LEFT JOIN purchase_orders po ON po.id = c.po_id
            WHERE c.supplier_id = ?
            ORDER BY c.created_at DESC
            LIMIT ? OFFSET ?
            """,
            (supplier_id, limit, offset),
        )
        return await cursor.fetchall()

    async def get_open_follow_ups(
        self,
        *,
        supplier_id: int | None = None,
        limit: int = 50,
    ) -> list[dict]:
        """Get all entries with unresolved follow-ups.

        Optionally filter by supplier.  Used by the Office dashboard to
        surface pending action items.
        """
        sql = """
            SELECT c.*,
                   u.display_name AS creator_name,
                   po.po_number,
                   s.name AS supplier_name
            FROM po_conversations c
            LEFT JOIN users u ON u.id = c.created_by
            LEFT JOIN purchase_orders po ON po.id = c.po_id
            LEFT JOIN suppliers s ON s.id = c.supplier_id
            WHERE c.follow_up_needed = 1
              AND c.follow_up_resolved_at IS NULL
        """
        params: list[Any] = []

        if supplier_id:
            sql += " AND c.supplier_id = ?"
            params.append(supplier_id)

        sql += " ORDER BY c.created_at ASC LIMIT ?"
        params.append(limit)

        cursor = await self.db.execute(sql, params)
        return await cursor.fetchall()

    async def count_open_follow_ups(
        self,
        *,
        supplier_id: int | None = None,
    ) -> int:
        """Count unresolved follow-ups, optionally by supplier."""
        sql = """
            SELECT COUNT(*) AS cnt FROM po_conversations
            WHERE follow_up_needed = 1
              AND follow_up_resolved_at IS NULL
        """
        params: list[Any] = []
        if supplier_id:
            sql += " AND supplier_id = ?"
            params.append(supplier_id)

        cursor = await self.db.execute(sql, params)
        row = await cursor.fetchone()
        return row["cnt"] if row else 0

    async def resolve_follow_up(self, entry_id: int) -> bool:
        """Mark a follow-up as resolved."""
        cursor = await self.db.execute(
            """
            UPDATE po_conversations
            SET follow_up_resolved_at = datetime('now')
            WHERE id = ? AND follow_up_needed = 1
            """,
            (entry_id,),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def unresolve_follow_up(self, entry_id: int) -> bool:
        """Re-open a resolved follow-up."""
        cursor = await self.db.execute(
            """
            UPDATE po_conversations
            SET follow_up_resolved_at = NULL
            WHERE id = ? AND follow_up_needed = 1
            """,
            (entry_id,),
        )
        await self.db.commit()
        return cursor.rowcount > 0


# ═══════════════════════════════════════════════════════════════
# PO Group Repository
# ═══════════════════════════════════════════════════════════════

class POGroupRepo(BaseRepo):
    TABLE = "po_groups"
    HAS_UPDATED_AT = False

    async def get_with_members(self, group_id: int) -> dict | None:
        """Get a PO group with all its member POs."""
        cursor = await self.db.execute(
            """
            SELECT g.*,
                   s.name AS supplier_name,
                   u.display_name AS creator_name
            FROM po_groups g
            LEFT JOIN suppliers s ON s.id = g.supplier_id
            LEFT JOIN users u ON u.id = g.created_by
            WHERE g.id = ?
            """,
            (group_id,),
        )
        group = await cursor.fetchone()
        if not group:
            return None

        group = dict(group)

        # Deserialize individual_pdfs JSON
        if group.get("individual_pdfs"):
            try:
                group["individual_pdfs"] = json.loads(group["individual_pdfs"])
            except (json.JSONDecodeError, TypeError):
                group["individual_pdfs"] = []

        # Fetch member POs
        cursor = await self.db.execute(
            """
            SELECT gm.id, gm.group_id, gm.po_id,
                   po.po_number, po.status, po.total_cost,
                   (SELECT COUNT(*) FROM po_line_items
                    WHERE po_id = po.id) AS line_count
            FROM po_group_members gm
            JOIN purchase_orders po ON po.id = gm.po_id
            WHERE gm.group_id = ?
            ORDER BY po.po_number
            """,
            (group_id,),
        )
        group["members"] = await cursor.fetchall()

        # Calculate total value
        group["total_value"] = sum(
            m["total_cost"] or 0 for m in group["members"]
        )

        return group

    async def list_for_supplier(
        self,
        supplier_id: int,
        *,
        limit: int = 20,
    ) -> list[dict]:
        """List PO groups for a supplier (compact format)."""
        cursor = await self.db.execute(
            """
            SELECT g.id, g.group_name, g.supplier_id,
                   s.name AS supplier_name,
                   g.pdf_path,
                   g.created_at,
                   (SELECT COUNT(*) FROM po_group_members
                    WHERE group_id = g.id) AS po_count,
                   (SELECT COALESCE(SUM(po.total_cost), 0)
                    FROM po_group_members gm
                    JOIN purchase_orders po ON po.id = gm.po_id
                    WHERE gm.group_id = g.id) AS total_value
            FROM po_groups g
            LEFT JOIN suppliers s ON s.id = g.supplier_id
            WHERE g.supplier_id = ?
            ORDER BY g.created_at DESC
            LIMIT ?
            """,
            (supplier_id, limit),
        )
        rows = await cursor.fetchall()
        # Add computed has_pdf field
        return [
            {**dict(r), "has_pdf": bool(r["pdf_path"])}
            for r in rows
        ]

    async def add_members(
        self,
        group_id: int,
        po_ids: list[int],
    ) -> int:
        """Add POs to a group.  Silently skips duplicates (UNIQUE constraint)."""
        added = 0
        for po_id in po_ids:
            try:
                await self.db.execute(
                    "INSERT INTO po_group_members (group_id, po_id) VALUES (?, ?)",
                    (group_id, po_id),
                )
                added += 1
            except Exception:
                # UNIQUE constraint violation — PO already in group
                pass
        await self.db.commit()
        return added

    async def set_pdf_path(
        self,
        group_id: int,
        pdf_path: str | None = None,
        individual_pdfs: list[str] | None = None,
    ) -> bool:
        """Store generated PDF paths on the group."""
        individual_json = json.dumps(individual_pdfs) if individual_pdfs else None
        cursor = await self.db.execute(
            """
            UPDATE po_groups
            SET pdf_path = ?, individual_pdfs = ?
            WHERE id = ?
            """,
            (pdf_path, individual_json, group_id),
        )
        await self.db.commit()
        return cursor.rowcount > 0


# ═══════════════════════════════════════════════════════════════
# Service
# ═══════════════════════════════════════════════════════════════

class POConversationService:
    """Orchestrates PO conversation threads, groups, and confirmation checklists."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.conv_repo = POConversationRepo(db)
        self.group_repo = POGroupRepo(db)

    # ══════════════════════════════════════════════════════════
    # CONVERSATION THREAD
    # ══════════════════════════════════════════════════════════

    async def add_entry(
        self,
        po_id: int,
        entry_type: str,
        message: str,
        user_id: int,
        *,
        follow_up_needed: bool = False,
    ) -> int:
        """Add a manual conversation entry to a PO.

        Also resolves the supplier_id from the PO so that the entry
        appears in both PO-level and supplier-level threads.
        """
        # Get supplier_id from the PO
        cursor = await self.db.execute(
            "SELECT supplier_id FROM purchase_orders WHERE id = ?",
            (po_id,),
        )
        po = await cursor.fetchone()
        supplier_id = po["supplier_id"] if po else None

        entry_id = await self.conv_repo.insert({
            "po_id": po_id,
            "supplier_id": supplier_id,
            "entry_type": entry_type,
            "message": message,
            "follow_up_needed": 1 if follow_up_needed else 0,
            "created_by": user_id,
        })

        logger.info(
            "Added %s entry to PO %d by user %d (follow_up=%s)",
            entry_type, po_id, user_id, follow_up_needed,
        )
        return entry_id

    async def add_system_entry(
        self,
        po_id: int,
        message: str,
    ) -> int:
        """Add an auto-generated system entry to a PO thread.

        System entries have entry_type='system' and no created_by.
        Called by other services when PO status changes, prices update, etc.
        """
        # Get supplier_id from the PO
        cursor = await self.db.execute(
            "SELECT supplier_id FROM purchase_orders WHERE id = ?",
            (po_id,),
        )
        po = await cursor.fetchone()
        supplier_id = po["supplier_id"] if po else None

        entry_id = await self.conv_repo.insert({
            "po_id": po_id,
            "supplier_id": supplier_id,
            "entry_type": "system",
            "message": message,
            "follow_up_needed": 0,
            "created_by": None,
        })

        logger.debug("System entry on PO %d: %s", po_id, message[:80])
        return entry_id

    async def get_thread(
        self,
        po_id: int,
        *,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict]:
        """Get the full conversation thread for a PO."""
        return await self.conv_repo.get_thread(po_id, limit=limit, offset=offset)

    async def get_supplier_thread(
        self,
        supplier_id: int,
        *,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict]:
        """Get all conversation entries across POs for a supplier."""
        return await self.conv_repo.get_supplier_thread(
            supplier_id, limit=limit, offset=offset,
        )

    async def toggle_follow_up(
        self,
        entry_id: int,
        resolved: bool,
    ) -> bool:
        """Toggle the follow-up resolved status on an entry."""
        if resolved:
            return await self.conv_repo.resolve_follow_up(entry_id)
        else:
            return await self.conv_repo.unresolve_follow_up(entry_id)

    async def get_open_follow_ups(
        self,
        *,
        supplier_id: int | None = None,
        limit: int = 50,
    ) -> list[dict]:
        """Get open follow-ups, optionally filtered by supplier."""
        return await self.conv_repo.get_open_follow_ups(
            supplier_id=supplier_id, limit=limit,
        )

    # ══════════════════════════════════════════════════════════
    # PO GROUPS
    # ══════════════════════════════════════════════════════════

    async def create_group(
        self,
        supplier_id: int,
        po_ids: list[int],
        user_id: int,
        *,
        group_name: str | None = None,
    ) -> dict:
        """Create a PO group for bundled sending.

        Validates that all POs belong to the specified supplier before
        creating the group.  Auto-generates a group name if not provided.
        """
        # Validate that all POs belong to this supplier
        placeholders = ",".join(["?"] * len(po_ids))
        cursor = await self.db.execute(
            f"""
            SELECT id, po_number, supplier_id FROM purchase_orders
            WHERE id IN ({placeholders})
            """,
            po_ids,
        )
        pos = await cursor.fetchall()

        if len(pos) != len(po_ids):
            found_ids = {p["id"] for p in pos}
            missing = [pid for pid in po_ids if pid not in found_ids]
            raise ValueError(f"POs not found: {missing}")

        wrong_supplier = [
            p["po_number"] for p in pos if p["supplier_id"] != supplier_id
        ]
        if wrong_supplier:
            raise ValueError(
                f"POs don't belong to supplier {supplier_id}: {wrong_supplier}"
            )

        # Auto-generate name if not provided
        if not group_name:
            # Get supplier name for the auto-name
            cursor = await self.db.execute(
                "SELECT name FROM suppliers WHERE id = ?",
                (supplier_id,),
            )
            supplier = await cursor.fetchone()
            supplier_name = supplier["name"] if supplier else f"Supplier #{supplier_id}"
            group_name = f"{supplier_name} — {len(po_ids)} POs"

        # Create the group
        group_id = await self.group_repo.insert({
            "group_name": group_name,
            "supplier_id": supplier_id,
            "created_by": user_id,
        })

        # Add members
        await self.group_repo.add_members(group_id, po_ids)

        logger.info(
            "Created PO group %d '%s' with %d POs for supplier %d",
            group_id, group_name, len(po_ids), supplier_id,
        )

        return await self.group_repo.get_with_members(group_id)

    async def get_group(self, group_id: int) -> dict | None:
        """Get a PO group with its members."""
        return await self.group_repo.get_with_members(group_id)

    async def list_groups_for_supplier(
        self,
        supplier_id: int,
        *,
        limit: int = 20,
    ) -> list[dict]:
        """List PO groups for a supplier."""
        return await self.group_repo.list_for_supplier(
            supplier_id, limit=limit,
        )

    async def set_group_pdfs(
        self,
        group_id: int,
        pdf_path: str | None = None,
        individual_pdfs: list[str] | None = None,
    ) -> bool:
        """Store PDF paths after generation."""
        return await self.group_repo.set_pdf_path(
            group_id,
            pdf_path=pdf_path,
            individual_pdfs=individual_pdfs,
        )

    # ══════════════════════════════════════════════════════════
    # CONFIRMATION CHECKLIST
    # ══════════════════════════════════════════════════════════

    async def get_confirmation_checklist(self, po_id: int) -> list[dict]:
        """Get the confirmation checklist for a PO.

        If no checklist exists yet, auto-generates one from the PO's
        line items (all unchecked).
        """
        cursor = await self.db.execute(
            "SELECT confirmation_checklist FROM purchase_orders WHERE id = ?",
            (po_id,),
        )
        po = await cursor.fetchone()
        if not po:
            return []

        # Try to parse existing checklist
        raw = po["confirmation_checklist"]
        if raw:
            try:
                items = json.loads(raw)
                # Enrich with part descriptions
                return await self._enrich_checklist(po_id, items)
            except (json.JSONDecodeError, TypeError):
                pass

        # Auto-generate from line items
        cursor = await self.db.execute(
            """
            SELECT li.id AS po_line_id, li.part_id,
                   p.description AS part_description,
                   p.code AS part_number,
                   p.name AS part_name,
                   cat.name AS category_name,
                   typ.name AS type_name,
                   col.name AS color_name,
                   col.hex_code AS color_hex,
                   b.name AS brand_name
            FROM po_line_items li
            JOIN parts p ON p.id = li.part_id
            LEFT JOIN part_categories cat ON cat.id = p.category_id
            LEFT JOIN part_types typ ON typ.id = p.type_id
            LEFT JOIN part_colors col ON col.id = p.color_id
            LEFT JOIN brands b ON b.id = p.brand_id
            WHERE li.po_id = ?
            ORDER BY li.id
            """,
            (po_id,),
        )
        lines = await cursor.fetchall()

        return [
            {
                "po_line_id": line["po_line_id"],
                "part_id": line["part_id"],
                "confirmed": False,
                "confirmed_by": None,
                "confirmed_at": None,
                "part_description": line["part_description"],
                "part_number": line["part_number"],
                "part_name": line["part_name"],
                "category_name": line["category_name"],
                "type_name": line["type_name"],
                "color_name": line["color_name"],
                "color_hex": line["color_hex"],
                "brand_name": line["brand_name"],
                "confirmer_name": None,
            }
            for line in lines
        ]

    async def update_confirmation_checklist(
        self,
        po_id: int,
        checklist: list[dict],
        user_id: int,
    ) -> list[dict]:
        """Update the confirmation checklist for a PO.

        Stamps confirmed_by and confirmed_at on any newly confirmed items.
        Stores the checklist as JSON in the purchase_orders row.
        """
        now = datetime.now(timezone.utc).isoformat()

        # Process each item: stamp user/time on newly confirmed items
        stored_items = []
        for item in checklist:
            stored = {
                "po_line_id": item["po_line_id"],
                "part_id": item["part_id"],
                "confirmed": item.get("confirmed", False),
                "confirmed_by": item.get("confirmed_by"),
                "confirmed_at": item.get("confirmed_at"),
            }
            # If confirmed but no confirmed_by, stamp it now
            if stored["confirmed"] and not stored["confirmed_by"]:
                stored["confirmed_by"] = user_id
                stored["confirmed_at"] = now
            stored_items.append(stored)

        # Persist as JSON
        checklist_json = json.dumps(stored_items)
        await self.db.execute(
            "UPDATE purchase_orders SET confirmation_checklist = ? WHERE id = ?",
            (checklist_json, po_id),
        )
        await self.db.commit()

        logger.info(
            "Updated confirmation checklist for PO %d (%d items, %d confirmed)",
            po_id,
            len(stored_items),
            sum(1 for i in stored_items if i["confirmed"]),
        )

        # Return enriched version
        return await self._enrich_checklist(po_id, stored_items)

    async def _enrich_checklist(
        self,
        po_id: int,
        items: list[dict],
    ) -> list[dict]:
        """Add part descriptions and confirmer names to checklist items."""
        if not items:
            return items

        # Build lookup maps
        part_ids = [i["part_id"] for i in items if i.get("part_id")]
        user_ids = [i["confirmed_by"] for i in items if i.get("confirmed_by")]

        part_map: dict[int, dict] = {}
        if part_ids:
            placeholders = ",".join(["?"] * len(part_ids))
            cursor = await self.db.execute(
                f"""SELECT p.id, p.description, p.code, p.name AS part_name,
                       cat.name AS category_name,
                       typ.name AS type_name,
                       col.name AS color_name,
                       col.hex_code AS color_hex,
                       b.name AS brand_name
                FROM parts p
                LEFT JOIN part_categories cat ON cat.id = p.category_id
                LEFT JOIN part_types typ ON typ.id = p.type_id
                LEFT JOIN part_colors col ON col.id = p.color_id
                LEFT JOIN brands b ON b.id = p.brand_id
                WHERE p.id IN ({placeholders})""",
                part_ids,
            )
            for row in await cursor.fetchall():
                part_map[row["id"]] = dict(row)

        user_names: dict[int, str] = {}
        if user_ids:
            placeholders = ",".join(["?"] * len(user_ids))
            cursor = await self.db.execute(
                f"SELECT id, display_name FROM users WHERE id IN ({placeholders})",
                user_ids,
            )
            for row in await cursor.fetchall():
                user_names[row["id"]] = row["display_name"]

        return [
            {
                **item,
                "part_description": part_map.get(item.get("part_id", 0), {}).get("description"),
                "part_number": part_map.get(item.get("part_id", 0), {}).get("code"),
                "part_name": part_map.get(item.get("part_id", 0), {}).get("part_name"),
                "category_name": part_map.get(item.get("part_id", 0), {}).get("category_name"),
                "type_name": part_map.get(item.get("part_id", 0), {}).get("type_name"),
                "color_name": part_map.get(item.get("part_id", 0), {}).get("color_name"),
                "color_hex": part_map.get(item.get("part_id", 0), {}).get("color_hex"),
                "brand_name": part_map.get(item.get("part_id", 0), {}).get("brand_name"),
                "confirmer_name": user_names.get(item.get("confirmed_by", 0)),
            }
            for item in items
        ]

    # ══════════════════════════════════════════════════════════
    # APPROVAL QUEUE (unified view for office)
    # ══════════════════════════════════════════════════════════

    async def get_pending_approvals(
        self,
        *,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """Get all pending JPOs and pending returns for the approval queue.

        Returns a unified list sorted by created_at (oldest first — FIFO).
        Each item has an `entity_type` field ('jpo' or 'return') so the
        frontend knows which detail page to link to.
        """
        # Pending JPOs
        cursor = await self.db.execute(
            """
            SELECT
                'jpo' AS entity_type,
                jpo.id AS entity_id,
                jpo.order_number AS reference_number,
                jpo.status,
                jpo.priority,
                jpo.order_type,
                NULL AS return_type,
                NULL AS reason,
                jpo.has_special_items,
                jpo.requested_by AS requester_id,
                u.display_name AS requester_name,
                jpo.job_id,
                j.job_name,
                NULL AS supplier_name,
                (SELECT COUNT(*) FROM jpo_line_items WHERE jpo_id = jpo.id) AS line_count,
                jpo.created_at
            FROM job_parts_orders jpo
            LEFT JOIN users u ON u.id = jpo.requested_by
            LEFT JOIN jobs j ON j.id = jpo.job_id
            WHERE jpo.status = 'pending_approval'
            """,
        )
        jpo_items = await cursor.fetchall()

        # Pending returns
        cursor = await self.db.execute(
            """
            SELECT
                'return' AS entity_type,
                r.id AS entity_id,
                r.return_number AS reference_number,
                r.status,
                'normal' AS priority,
                NULL AS order_type,
                r.return_type,
                r.reason,
                0 AS has_special_items,
                r.initiated_by AS requester_id,
                u.display_name AS requester_name,
                r.job_id,
                j.job_name,
                s.name AS supplier_name,
                (SELECT COUNT(*) FROM return_line_items WHERE return_id = r.id) AS line_count,
                r.created_at
            FROM returns r
            LEFT JOIN users u ON u.id = r.initiated_by
            LEFT JOIN jobs j ON j.id = r.job_id
            LEFT JOIN suppliers s ON s.id = r.supplier_id
            WHERE r.status = 'pending_approval'
            """,
        )
        return_items = await cursor.fetchall()

        # Merge and sort by created_at (oldest first — FIFO queue)
        all_items = [dict(r) for r in jpo_items] + [dict(r) for r in return_items]
        all_items.sort(key=lambda x: x.get("created_at") or "")

        # Apply pagination
        return all_items[offset : offset + limit]

    async def count_pending_approvals(self) -> dict:
        """Count pending items by type for the badge on the Approvals tab."""
        cursor = await self.db.execute(
            "SELECT COUNT(*) AS cnt FROM job_parts_orders WHERE status = 'pending_approval'"
        )
        jpo_row = await cursor.fetchone()

        cursor = await self.db.execute(
            "SELECT COUNT(*) AS cnt FROM returns WHERE status = 'pending_approval'"
        )
        return_row = await cursor.fetchone()

        jpo_count = jpo_row["cnt"] if jpo_row else 0
        return_count = return_row["cnt"] if return_row else 0

        return {
            "jpo_count": jpo_count,
            "return_count": return_count,
            "total": jpo_count + return_count,
        }
