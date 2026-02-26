"""
Part Alternatives repository — bidirectional cross-linking between parts.

A single row links two parts. Queries always check BOTH directions
(part_id = X OR alternative_part_id = X) so a single DB row serves
both parts' alternative lists.
"""

from __future__ import annotations

from typing import Any

import aiosqlite

from app.repositories.base import BaseRepo


class PartAlternativesRepo(BaseRepo):
    """Data access for part alternative links.

    Key design choice: bidirectional from a single row.
    When part A is linked to part B, only ONE row exists in the table.
    Queries check both columns so it shows up for both parts.
    """

    TABLE = "part_alternatives"

    async def get_for_part(self, part_id: int) -> list[dict]:
        """Get all alternatives for a part (bidirectional lookup).

        Returns the 'other' part's details regardless of which column
        the queried part appears in.
        """
        sql = """
            SELECT
                pa.id,
                pa.part_id,
                pa.alternative_part_id,
                pa.relationship,
                pa.preference,
                pa.notes,
                pa.created_by,
                pa.created_at,
                -- Resolve the 'other' part's details
                CASE WHEN pa.part_id = ? THEN p_alt.name ELSE p_main.name END
                    AS alternative_name,
                CASE WHEN pa.part_id = ? THEN p_alt.code ELSE p_main.code END
                    AS alternative_code,
                CASE WHEN pa.part_id = ? THEN b_alt.name ELSE b_main.name END
                    AS alternative_brand_name,
                -- Also include the 'this' part's info for display context
                CASE WHEN pa.part_id = ? THEN p_main.name ELSE p_alt.name END
                    AS part_name,
                CASE WHEN pa.part_id = ? THEN p_main.code ELSE p_alt.code END
                    AS part_code
            FROM part_alternatives pa
            JOIN parts p_main ON p_main.id = pa.part_id
            JOIN parts p_alt  ON p_alt.id  = pa.alternative_part_id
            LEFT JOIN brands b_main ON b_main.id = p_main.brand_id
            LEFT JOIN brands b_alt  ON b_alt.id  = p_alt.brand_id
            WHERE pa.part_id = ? OR pa.alternative_part_id = ?
            ORDER BY pa.preference DESC, pa.created_at ASC
        """
        # The part_id param appears 7 times in the query
        cursor = await self.db.execute(
            sql, (part_id, part_id, part_id, part_id, part_id, part_id, part_id)
        )
        return [dict(row) for row in await cursor.fetchall()]

    async def link(
        self,
        part_id: int,
        alternative_part_id: int,
        relationship: str = "substitute",
        preference: int = 0,
        notes: str | None = None,
        created_by: int | None = None,
    ) -> int:
        """Create a bidirectional alternative link between two parts.

        Normalizes the order: smaller ID always goes as `part_id` to
        prevent duplicate rows (the UNIQUE constraint covers this, but
        normalizing makes lookups more predictable).
        """
        # Normalize: smaller id first
        if part_id > alternative_part_id:
            part_id, alternative_part_id = alternative_part_id, part_id

        data: dict[str, Any] = {
            "part_id": part_id,
            "alternative_part_id": alternative_part_id,
            "relationship": relationship,
            "preference": preference,
            "notes": notes,
            "created_by": created_by,
        }
        return await self.insert(data)

    async def update_link(
        self,
        link_id: int,
        data: dict[str, Any],
    ) -> bool:
        """Update relationship, preference, or notes on an existing link."""
        return await self.update(link_id, data)

    async def unlink(self, link_id: int) -> bool:
        """Remove an alternative link."""
        return await self.delete(link_id)

    async def link_exists(
        self, part_id: int, alternative_part_id: int
    ) -> bool:
        """Check if a link already exists (either direction)."""
        # Normalize
        a, b = min(part_id, alternative_part_id), max(part_id, alternative_part_id)
        cursor = await self.db.execute(
            """SELECT 1 FROM part_alternatives
               WHERE part_id = ? AND alternative_part_id = ?
               LIMIT 1""",
            (a, b),
        )
        return await cursor.fetchone() is not None
