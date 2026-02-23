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
        """Get all types for a specific style, with part count and color count."""
        sql = """
            SELECT
                t.*,
                ps.name AS style_name,
                pc.name AS category_name,
                COALESCE(ptc.part_count, 0) AS part_count,
                COALESCE(cc.color_count, 0) AS color_count
            FROM part_types t
            JOIN part_styles ps ON ps.id = t.style_id
            JOIN part_categories pc ON pc.id = ps.category_id
            LEFT JOIN (
                SELECT type_id, COUNT(*) AS part_count
                FROM parts
                WHERE type_id IS NOT NULL
                GROUP BY type_id
            ) ptc ON ptc.type_id = t.id
            LEFT JOIN (
                SELECT type_id, COUNT(*) AS color_count
                FROM type_color_links
                GROUP BY type_id
            ) cc ON cc.type_id = t.id
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


class TypeColorLinkRepo(BaseRepo):
    """Repository for type ↔ color junction (which colors are valid per type)."""

    TABLE = "type_color_links"

    async def get_by_type(self, type_id: int) -> list[dict]:
        """Get all colors linked to a specific type, with color names."""
        sql = """
            SELECT
                tcl.*,
                pc.name AS color_name,
                pc.hex_code
            FROM type_color_links tcl
            JOIN part_colors pc ON pc.id = tcl.color_id
            WHERE tcl.type_id = ?
            ORDER BY tcl.sort_order ASC, pc.name ASC
        """
        cursor = await self.db.execute(sql, (type_id,))
        return await cursor.fetchall()

    async def get_by_color(self, color_id: int) -> list[dict]:
        """Get all types that use a specific color."""
        sql = """
            SELECT
                tcl.*,
                pt.name AS type_name,
                ps.name AS style_name,
                cat.name AS category_name
            FROM type_color_links tcl
            JOIN part_types pt ON pt.id = tcl.type_id
            JOIN part_styles ps ON ps.id = pt.style_id
            JOIN part_categories cat ON cat.id = ps.category_id
            WHERE tcl.color_id = ?
            ORDER BY cat.sort_order, ps.sort_order, pt.sort_order
        """
        cursor = await self.db.execute(sql, (color_id,))
        return await cursor.fetchall()

    async def link_exists(self, type_id: int, color_id: int) -> bool:
        """Check if a type-color link already exists."""
        cursor = await self.db.execute(
            "SELECT 1 FROM type_color_links WHERE type_id = ? AND color_id = ? LIMIT 1",
            (type_id, color_id),
        )
        return await cursor.fetchone() is not None

    async def bulk_link(self, type_id: int, color_ids: list[int]) -> int:
        """Link multiple colors to a type at once. Skips existing links."""
        created = 0
        for color_id in color_ids:
            try:
                await self.db.execute(
                    "INSERT OR IGNORE INTO type_color_links (type_id, color_id) VALUES (?, ?)",
                    (type_id, color_id),
                )
                created += 1
            except Exception:
                pass
        await self.db.commit()
        return created

    async def unlink(self, type_id: int, color_id: int) -> bool:
        """Remove a specific type-color link."""
        cursor = await self.db.execute(
            "DELETE FROM type_color_links WHERE type_id = ? AND color_id = ?",
            (type_id, color_id),
        )
        await self.db.commit()
        return cursor.rowcount > 0


class TypeBrandLinkRepo(BaseRepo):
    """Repository for type ↔ brand links (which brands are enabled per type).

    brand_id = NULL represents "General" (unbranded commodity parts).
    """

    TABLE = "type_brand_links"

    async def get_by_type(self, type_id: int) -> list[dict]:
        """Get all brands (and General) linked to a type, with part counts."""
        sql = """
            SELECT
                tbl.id,
                tbl.type_id,
                tbl.brand_id,
                CASE WHEN tbl.brand_id IS NULL THEN 'General' ELSE b.name END AS brand_name,
                COALESCE(pc.part_count, 0) AS part_count,
                tbl.created_at
            FROM type_brand_links tbl
            LEFT JOIN brands b ON b.id = tbl.brand_id
            LEFT JOIN (
                SELECT
                    type_id,
                    COALESCE(brand_id, 0) AS brand_key,
                    COUNT(*) AS part_count
                FROM parts
                WHERE type_id IS NOT NULL
                GROUP BY type_id, COALESCE(brand_id, 0)
            ) pc ON pc.type_id = tbl.type_id
                 AND pc.brand_key = COALESCE(tbl.brand_id, 0)
            WHERE tbl.type_id = ?
            ORDER BY
                CASE WHEN tbl.brand_id IS NULL THEN 0 ELSE 1 END,
                b.name ASC
        """
        cursor = await self.db.execute(sql, (type_id,))
        return await cursor.fetchall()

    async def link_brand(self, type_id: int, brand_id: int | None) -> dict:
        """Enable a brand (or General) for a type. Returns the created link."""
        cursor = await self.db.execute(
            "INSERT OR IGNORE INTO type_brand_links (type_id, brand_id) VALUES (?, ?)",
            (type_id, brand_id),
        )
        await self.db.commit()

        # Fetch the link back (may already exist via OR IGNORE)
        if brand_id is None:
            fetch_sql = "SELECT * FROM type_brand_links WHERE type_id = ? AND brand_id IS NULL"
            fetch_cursor = await self.db.execute(fetch_sql, (type_id,))
        else:
            fetch_sql = "SELECT * FROM type_brand_links WHERE type_id = ? AND brand_id = ?"
            fetch_cursor = await self.db.execute(fetch_sql, (type_id, brand_id))

        return await fetch_cursor.fetchone()

    async def unlink_brand(self, type_id: int, brand_id: int | None) -> bool:
        """Disable a brand (or General) for a type."""
        if brand_id is None:
            cursor = await self.db.execute(
                "DELETE FROM type_brand_links WHERE type_id = ? AND brand_id IS NULL",
                (type_id,),
            )
        else:
            cursor = await self.db.execute(
                "DELETE FROM type_brand_links WHERE type_id = ? AND brand_id = ?",
                (type_id, brand_id),
            )
        await self.db.commit()
        return cursor.rowcount > 0

    async def link_exists(self, type_id: int, brand_id: int | None) -> bool:
        """Check if a type-brand link already exists."""
        if brand_id is None:
            cursor = await self.db.execute(
                "SELECT 1 FROM type_brand_links WHERE type_id = ? AND brand_id IS NULL LIMIT 1",
                (type_id,),
            )
        else:
            cursor = await self.db.execute(
                "SELECT 1 FROM type_brand_links WHERE type_id = ? AND brand_id = ? LIMIT 1",
                (type_id, brand_id),
            )
        return await cursor.fetchone() is not None

    async def get_parts_for_type_brand(
        self,
        type_id: int,
        brand_id: int | None,
    ) -> list[dict]:
        """Get all parts under a specific type+brand (or type+General) combo.

        Returns part records with color info for the color-chip UI.
        """
        if brand_id is None:
            where = "p.type_id = ? AND p.brand_id IS NULL"
            params: tuple = (type_id,)
        else:
            where = "p.type_id = ? AND p.brand_id = ?"
            params = (type_id, brand_id)

        sql = f"""
            SELECT
                p.id, p.name, p.code, p.part_type,
                p.color_id, col.name AS color_name, col.hex_code,
                p.brand_id, b.name AS brand_name,
                p.manufacturer_part_number,
                p.company_cost_price, p.company_sell_price,
                p.unit_of_measure, p.image_url,
                p.is_deprecated,
                COALESCE(st.total_stock, 0) AS total_stock,
                CASE WHEN p.part_type = 'specific'
                          AND p.manufacturer_part_number IS NULL
                     THEN 1 ELSE 0
                END AS has_pending_part_number
            FROM parts p
            LEFT JOIN part_colors col ON col.id = p.color_id
            LEFT JOIN brands b ON b.id = p.brand_id
            LEFT JOIN (
                SELECT part_id, SUM(qty) AS total_stock
                FROM stock GROUP BY part_id
            ) st ON st.part_id = p.id
            WHERE {where}
            ORDER BY col.sort_order ASC, col.name ASC
        """
        cursor = await self.db.execute(sql, params)
        return await cursor.fetchall()
