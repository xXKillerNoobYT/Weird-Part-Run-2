"""
Supplier preference repository — cascade lookup for preferred suppliers.

Preferred suppliers can be set at any hierarchy level:
  part → type → style → category

Resolution walks up the hierarchy until a preference is found.
"""

from __future__ import annotations

import aiosqlite

from app.repositories.base import BaseRepo


class SupplierPrefRepo(BaseRepo):
    """Data access for supplier preferences with cascade resolution."""

    TABLE = "supplier_preferences"

    async def get_preference(self, scope_type: str, scope_id: int) -> dict | None:
        """Get the preferred supplier for a specific scope."""
        cursor = await self.db.execute(
            """SELECT sp.*, s.name AS supplier_name
               FROM supplier_preferences sp
               JOIN suppliers s ON s.id = sp.supplier_id
               WHERE sp.scope_type = ? AND sp.scope_id = ?""",
            (scope_type, scope_id),
        )
        return await cursor.fetchone()

    async def set_preference(
        self, scope_type: str, scope_id: int, supplier_id: int
    ) -> int:
        """Set or update the preferred supplier for a scope level."""
        cursor = await self.db.execute(
            """INSERT INTO supplier_preferences (scope_type, scope_id, supplier_id)
               VALUES (?, ?, ?)
               ON CONFLICT(scope_type, scope_id) DO UPDATE SET
                   supplier_id = excluded.supplier_id,
                   created_at = datetime('now')""",
            (scope_type, scope_id, supplier_id),
        )
        await self.db.commit()
        return cursor.lastrowid or 0

    async def remove_preference(self, scope_type: str, scope_id: int) -> bool:
        """Remove a preferred supplier for a scope level."""
        cursor = await self.db.execute(
            "DELETE FROM supplier_preferences WHERE scope_type = ? AND scope_id = ?",
            (scope_type, scope_id),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def resolve_for_part(self, part_id: int) -> dict | None:
        """Cascade resolution: part → type → style → category → None.

        Returns the first match found walking up the hierarchy,
        including which level it was resolved from.
        """
        # Get the part's hierarchy IDs
        cursor = await self.db.execute(
            "SELECT category_id, style_id, type_id FROM parts WHERE id = ?",
            (part_id,),
        )
        part = await cursor.fetchone()
        if not part:
            return None

        # Check each level in cascade order
        scopes = [("part", part_id)]
        if part["type_id"]:
            scopes.append(("type", part["type_id"]))
        if part["style_id"]:
            scopes.append(("style", part["style_id"]))
        if part["category_id"]:
            scopes.append(("category", part["category_id"]))

        for scope_type, scope_id in scopes:
            pref = await self.get_preference(scope_type, scope_id)
            if pref:
                return {
                    **dict(pref),
                    "resolved_from": scope_type,
                }

        return None

    async def get_all_preferences(self) -> list[dict]:
        """List all supplier preferences with supplier names."""
        cursor = await self.db.execute(
            """SELECT sp.*, s.name AS supplier_name
               FROM supplier_preferences sp
               JOIN suppliers s ON s.id = sp.supplier_id
               ORDER BY sp.scope_type, sp.scope_id"""
        )
        return await cursor.fetchall()
