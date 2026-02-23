"""
Repositories for the parts hierarchy lookup tables and brand-supplier links.

Covers: PartCategories, PartStyles, PartTypes, PartColors, BrandSupplierLinks.
Each inherits BaseRepo for standard CRUD and adds domain-specific queries.
"""

from __future__ import annotations

from .base import BaseRepo


class PartCategoryRepo(BaseRepo):
    """Repository for part categories (top-level grouping)."""

    TABLE = "part_categories"

    async def get_all_with_counts(
        self,
        *,
        search: str | None = None,
        is_active: bool | None = None,
    ) -> list[dict]:
        """Get all categories with child style count and part count."""
        sql = """
            SELECT
                c.*,
                COALESCE(sc.style_count, 0) AS style_count,
                COALESCE(pc.part_count, 0) AS part_count
            FROM part_categories c
            LEFT JOIN (
                SELECT category_id, COUNT(*) AS style_count
                FROM part_styles
                GROUP BY category_id
            ) sc ON sc.category_id = c.id
            LEFT JOIN (
                SELECT category_id, COUNT(*) AS part_count
                FROM parts
                GROUP BY category_id
            ) pc ON pc.category_id = c.id
        """
        conditions: list[str] = []
        params: list = []

        if search:
            conditions.append("c.name LIKE ?")
            params.append(f"%{search}%")
        if is_active is not None:
            conditions.append("c.is_active = ?")
            params.append(int(is_active))

        if conditions:
            sql += " WHERE " + " AND ".join(conditions)

        sql += " ORDER BY c.sort_order ASC, c.name ASC"

        cursor = await self.db.execute(sql, tuple(params))
        return await cursor.fetchall()

    async def get_by_name(self, name: str) -> dict | None:
        """Find a category by exact name (case-insensitive)."""
        cursor = await self.db.execute(
            "SELECT * FROM part_categories WHERE LOWER(name) = LOWER(?)",
            (name,),
        )
        return await cursor.fetchone()


class PartStyleRepo(BaseRepo):
    """Repository for part styles (per-category visual/form-factor)."""

    TABLE = "part_styles"

    async def get_by_category(
        self,
        category_id: int,
        *,
        is_active: bool | None = None,
    ) -> list[dict]:
        """Get all styles for a specific category, with child counts."""
        sql = """
            SELECT
                s.*,
                pc.name AS category_name,
                COALESCE(tc.type_count, 0) AS type_count,
                COALESCE(ptc.part_count, 0) AS part_count
            FROM part_styles s
            JOIN part_categories pc ON pc.id = s.category_id
            LEFT JOIN (
                SELECT style_id, COUNT(*) AS type_count
                FROM part_types
                GROUP BY style_id
            ) tc ON tc.style_id = s.id
            LEFT JOIN (
                SELECT style_id, COUNT(*) AS part_count
                FROM parts
                WHERE style_id IS NOT NULL
                GROUP BY style_id
            ) ptc ON ptc.style_id = s.id
            WHERE s.category_id = ?
        """
        params: list = [category_id]

        if is_active is not None:
            sql += " AND s.is_active = ?"
            params.append(int(is_active))

        sql += " ORDER BY s.sort_order ASC, s.name ASC"

        cursor = await self.db.execute(sql, tuple(params))
        return await cursor.fetchall()

    async def get_by_name_in_category(self, category_id: int, name: str) -> dict | None:
        """Find a style by name within a category (case-insensitive)."""
        cursor = await self.db.execute(
            "SELECT * FROM part_styles WHERE category_id = ? AND LOWER(name) = LOWER(?)",
            (category_id, name),
        )
        return await cursor.fetchone()


class PartTypeRepo(BaseRepo):
    """Repository for part types (per-style functional variety)."""

    TABLE = "part_types"

    async def get_by_style(
        self,
        style_id: int,
        *,
        is_active: bool | None = None,
    ) -> list[dict]:
        """Get all types for a specific style, with part count."""
        sql = """
            SELECT
                t.*,
                ps.name AS style_name,
                pc.name AS category_name,
                COALESCE(ptc.part_count, 0) AS part_count
            FROM part_types t
            JOIN part_styles ps ON ps.id = t.style_id
            JOIN part_categories pc ON pc.id = ps.category_id
            LEFT JOIN (
                SELECT type_id, COUNT(*) AS part_count
                FROM parts
                WHERE type_id IS NOT NULL
                GROUP BY type_id
            ) ptc ON ptc.type_id = t.id
            WHERE t.style_id = ?
        """
        params: list = [style_id]

        if is_active is not None:
            sql += " AND t.is_active = ?"
            params.append(int(is_active))

        sql += " ORDER BY t.sort_order ASC, t.name ASC"

        cursor = await self.db.execute(sql, tuple(params))
        return await cursor.fetchall()

    async def get_by_name_in_style(self, style_id: int, name: str) -> dict | None:
        """Find a type by name within a style (case-insensitive)."""
        cursor = await self.db.execute(
            "SELECT * FROM part_types WHERE style_id = ? AND LOWER(name) = LOWER(?)",
            (style_id, name),
        )
        return await cursor.fetchone()


class PartColorRepo(BaseRepo):
    """Repository for part colors (global lookup)."""

    TABLE = "part_colors"

    async def get_all_with_counts(
        self,
        *,
        search: str | None = None,
        is_active: bool | None = None,
    ) -> list[dict]:
        """Get all colors with part count."""
        sql = """
            SELECT
                c.*,
                COALESCE(pc.part_count, 0) AS part_count
            FROM part_colors c
            LEFT JOIN (
                SELECT color_id, COUNT(*) AS part_count
                FROM parts
                WHERE color_id IS NOT NULL
                GROUP BY color_id
            ) pc ON pc.color_id = c.id
        """
        conditions: list[str] = []
        params: list = []

        if search:
            conditions.append("c.name LIKE ?")
            params.append(f"%{search}%")
        if is_active is not None:
            conditions.append("c.is_active = ?")
            params.append(int(is_active))

        if conditions:
            sql += " WHERE " + " AND ".join(conditions)

        sql += " ORDER BY c.sort_order ASC, c.name ASC"

        cursor = await self.db.execute(sql, tuple(params))
        return await cursor.fetchall()

    async def get_by_name(self, name: str) -> dict | None:
        """Find a color by exact name (case-insensitive)."""
        cursor = await self.db.execute(
            "SELECT * FROM part_colors WHERE LOWER(name) = LOWER(?)",
            (name,),
        )
        return await cursor.fetchone()


class BrandSupplierLinkRepo(BaseRepo):
    """Repository for brand ↔ supplier many-to-many links."""

    TABLE = "brand_supplier_links"

    async def get_by_brand(self, brand_id: int) -> list[dict]:
        """Get all suppliers that carry a specific brand."""
        sql = """
            SELECT
                bsl.*,
                b.name AS brand_name,
                s.name AS supplier_name
            FROM brand_supplier_links bsl
            JOIN brands b ON b.id = bsl.brand_id
            JOIN suppliers s ON s.id = bsl.supplier_id
            WHERE bsl.brand_id = ?
            ORDER BY s.name ASC
        """
        cursor = await self.db.execute(sql, (brand_id,))
        return await cursor.fetchall()

    async def get_by_supplier(self, supplier_id: int) -> list[dict]:
        """Get all brands carried by a specific supplier."""
        sql = """
            SELECT
                bsl.*,
                b.name AS brand_name,
                s.name AS supplier_name
            FROM brand_supplier_links bsl
            JOIN brands b ON b.id = bsl.brand_id
            JOIN suppliers s ON s.id = bsl.supplier_id
            WHERE bsl.supplier_id = ?
            ORDER BY b.name ASC
        """
        cursor = await self.db.execute(sql, (supplier_id,))
        return await cursor.fetchall()

    async def link_exists(self, brand_id: int, supplier_id: int) -> bool:
        """Check if a brand-supplier link already exists."""
        cursor = await self.db.execute(
            "SELECT 1 FROM brand_supplier_links WHERE brand_id = ? AND supplier_id = ? LIMIT 1",
            (brand_id, supplier_id),
        )
        return await cursor.fetchone() is not None
