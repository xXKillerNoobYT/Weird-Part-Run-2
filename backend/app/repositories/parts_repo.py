"""
Parts repository — data access for the parts catalog, brands, and suppliers.

Handles all CRUD, search, filtering, and pagination for the Parts module.
Joins hierarchy tables (categories, styles, types, colors) for display names.
Stock-specific queries live in stock_repo.py.
"""

from __future__ import annotations

from typing import Any

from app.repositories.base import BaseRepo


# ── Stock totals subquery (reused in search and detail) ──────────
STOCK_SUBQUERY = """
    SELECT part_id,
           SUM(qty) AS total_stock,
           SUM(CASE WHEN location_type = 'warehouse' THEN qty ELSE 0 END) AS warehouse_stock,
           SUM(CASE WHEN location_type = 'truck' THEN qty ELSE 0 END) AS truck_stock,
           SUM(CASE WHEN location_type = 'job' THEN qty ELSE 0 END) AS job_stock,
           SUM(CASE WHEN location_type = 'pulled' THEN qty ELSE 0 END) AS pulled_stock
    FROM stock
    GROUP BY part_id
"""

# ── Hierarchy JOINs (reused in search and detail) ────────────────
HIERARCHY_JOINS = """
    LEFT JOIN part_categories cat ON cat.id = p.category_id
    LEFT JOIN part_styles sty ON sty.id = p.style_id
    LEFT JOIN part_types typ ON typ.id = p.type_id
    LEFT JOIN part_colors col ON col.id = p.color_id
    LEFT JOIN brands b ON b.id = p.brand_id
"""


class BrandRepo(BaseRepo):
    """Data access for brands."""

    TABLE = "brands"

    async def get_all_with_counts(
        self,
        *,
        is_active: bool | None = None,
        search: str | None = None,
        order_by: str = "name ASC",
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict]:
        """Get all brands with part count and supplier count."""
        where_clauses: list[str] = []
        params: list[Any] = []

        if is_active is not None:
            where_clauses.append("b.is_active = ?")
            params.append(int(is_active))

        if search:
            where_clauses.append("b.name LIKE ?")
            params.append(f"%{search}%")

        where_sql = f"WHERE {' AND '.join(where_clauses)}" if where_clauses else ""

        sql = f"""
            SELECT b.*,
                   COALESCE(pc.cnt, 0) AS part_count,
                   COALESCE(sc.cnt, 0) AS supplier_count
            FROM brands b
            LEFT JOIN (
                SELECT brand_id, COUNT(*) AS cnt
                FROM parts
                GROUP BY brand_id
            ) pc ON pc.brand_id = b.id
            LEFT JOIN (
                SELECT brand_id, COUNT(*) AS cnt
                FROM brand_supplier_links
                GROUP BY brand_id
            ) sc ON sc.brand_id = b.id
            {where_sql}
            ORDER BY {order_by}
            LIMIT ? OFFSET ?
        """
        params.extend([limit, offset])

        cursor = await self.db.execute(sql, params)
        return await cursor.fetchall()

    async def count_filtered(
        self,
        *,
        is_active: bool | None = None,
        search: str | None = None,
    ) -> int:
        """Count brands with optional filtering."""
        where_clauses: list[str] = []
        params: list[Any] = []

        if is_active is not None:
            where_clauses.append("is_active = ?")
            params.append(int(is_active))

        if search:
            where_clauses.append("name LIKE ?")
            params.append(f"%{search}%")

        where_sql = f"WHERE {' AND '.join(where_clauses)}" if where_clauses else ""
        cursor = await self.db.execute(
            f"SELECT COUNT(*) AS cnt FROM brands {where_sql}", params  # noqa: S608
        )
        row = await cursor.fetchone()
        return row["cnt"] if row else 0

    async def get_by_name(self, name: str) -> dict | None:
        """Find a brand by exact name (case-insensitive)."""
        cursor = await self.db.execute(
            "SELECT * FROM brands WHERE LOWER(name) = LOWER(?)", (name,)
        )
        return await cursor.fetchone()


class SupplierRepo(BaseRepo):
    """Data access for suppliers."""

    TABLE = "suppliers"

    async def get_all_filtered(
        self,
        *,
        is_active: bool | None = None,
        search: str | None = None,
        order_by: str = "name ASC",
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict]:
        """Get suppliers with optional filtering and brand count."""
        where_clauses: list[str] = []
        params: list[Any] = []

        if is_active is not None:
            where_clauses.append("s.is_active = ?")
            params.append(int(is_active))

        if search:
            where_clauses.append(
                "(s.name LIKE ? OR s.contact_name LIKE ? OR s.email LIKE ? "
                "OR s.rep_name LIKE ? OR s.rep_email LIKE ?)"
            )
            params.extend([f"%{search}%"] * 5)

        where_sql = f"WHERE {' AND '.join(where_clauses)}" if where_clauses else ""

        sql = f"""
            SELECT s.*,
                   COALESCE(bc.cnt, 0) AS brand_count
            FROM suppliers s
            LEFT JOIN (
                SELECT supplier_id, COUNT(*) AS cnt
                FROM brand_supplier_links
                GROUP BY supplier_id
            ) bc ON bc.supplier_id = s.id
            {where_sql}
            ORDER BY {order_by}
            LIMIT ? OFFSET ?
        """
        params.extend([limit, offset])

        cursor = await self.db.execute(sql, params)
        return await cursor.fetchall()


class PartsRepo(BaseRepo):
    """Data access for the parts catalog.

    Handles:
    - Full-text search across code, name, description
    - Filtering by hierarchy (category, style, type, color), brand, status, stock
    - Pagination with total count
    - Joined queries for hierarchy names, brand names, and stock totals
    - Pending part numbers queue for branded parts missing MPN
    """

    TABLE = "parts"

    # Allowed sort columns to prevent SQL injection
    SORT_COLUMNS = {
        "code", "name", "part_type", "brand_name", "unit_of_measure",
        "category_name", "style_name", "type_name", "color_name",
        "company_cost_price", "company_sell_price", "total_stock",
        "forecast_adu_30", "forecast_days_until_low", "forecast_suggested_order",
        "created_at", "updated_at",
    }

    async def search(
        self,
        *,
        search: str | None = None,
        category_id: int | None = None,
        style_id: int | None = None,
        type_id: int | None = None,
        color_id: int | None = None,
        part_type: str | None = None,
        brand_id: int | None = None,
        has_pending_pn: bool | None = None,
        is_deprecated: bool | None = None,
        is_qr_tagged: bool | None = None,
        low_stock: bool | None = None,
        sort_by: str = "name",
        sort_dir: str = "asc",
        page: int = 1,
        page_size: int = 50,
    ) -> tuple[list[dict], int]:
        """Search the parts catalog with filters, sorting, and pagination.

        Returns a tuple of (items, total_count) for pagination metadata.
        Each item includes hierarchy names, brand_name, and stock totals.
        """
        where_clauses: list[str] = []
        params: list[Any] = []

        # Text search across code, name, description
        if search:
            where_clauses.append(
                "(p.code LIKE ? OR p.name LIKE ? OR p.description LIKE ?)"
            )
            params.extend([f"%{search}%"] * 3)

        # Hierarchy filters
        if category_id is not None:
            where_clauses.append("p.category_id = ?")
            params.append(category_id)
        if style_id is not None:
            where_clauses.append("p.style_id = ?")
            params.append(style_id)
        if type_id is not None:
            where_clauses.append("p.type_id = ?")
            params.append(type_id)
        if color_id is not None:
            where_clauses.append("p.color_id = ?")
            params.append(color_id)

        # Classification filters
        if part_type:
            where_clauses.append("p.part_type = ?")
            params.append(part_type)
        if brand_id is not None:
            where_clauses.append("p.brand_id = ?")
            params.append(brand_id)
        if has_pending_pn:
            where_clauses.append(
                "p.part_type = 'specific' AND p.manufacturer_part_number IS NULL"
            )

        # Status filters
        if is_deprecated is not None:
            where_clauses.append("p.is_deprecated = ?")
            params.append(int(is_deprecated))
        if is_qr_tagged is not None:
            where_clauses.append("p.is_qr_tagged = ?")
            params.append(int(is_qr_tagged))
        if low_stock:
            where_clauses.append(
                "COALESCE(stock_totals.total_stock, 0) < p.min_stock_level "
                "AND p.min_stock_level > 0"
            )

        where_sql = f"WHERE {' AND '.join(where_clauses)}" if where_clauses else ""

        # Validate sort column
        if sort_by not in self.SORT_COLUMNS:
            sort_by = "name"
        sort_direction = "DESC" if sort_dir.lower() == "desc" else "ASC"

        # Map sort columns from joined data
        sort_column_map = {
            "brand_name": "b.name",
            "category_name": "cat.name",
            "style_name": "sty.name",
            "type_name": "typ.name",
            "color_name": "col.name",
            "total_stock": "COALESCE(stock_totals.total_stock, 0)",
        }
        actual_sort = sort_column_map.get(sort_by, f"p.{sort_by}")

        # Count query
        count_sql = f"""
            SELECT COUNT(*) AS cnt
            FROM parts p
            {HIERARCHY_JOINS}
            LEFT JOIN ({STOCK_SUBQUERY}) stock_totals ON stock_totals.part_id = p.id
            {where_sql}
        """
        count_cursor = await self.db.execute(count_sql, params)
        count_row = await count_cursor.fetchone()
        total = count_row["cnt"] if count_row else 0

        # Main query with hierarchy joins and pagination
        offset = (page - 1) * page_size
        sql = f"""
            SELECT p.*,
                   cat.name AS category_name,
                   sty.name AS style_name,
                   typ.name AS type_name,
                   col.name AS color_name,
                   b.name AS brand_name,
                   COALESCE(stock_totals.total_stock, 0) AS total_stock,
                   COALESCE(stock_totals.warehouse_stock, 0) AS warehouse_stock,
                   COALESCE(stock_totals.truck_stock, 0) AS truck_stock,
                   COALESCE(stock_totals.job_stock, 0) AS job_stock,
                   COALESCE(stock_totals.pulled_stock, 0) AS pulled_stock,
                   CASE
                       WHEN p.part_type = 'specific' AND p.manufacturer_part_number IS NULL
                       THEN 1 ELSE 0
                   END AS has_pending_part_number
            FROM parts p
            {HIERARCHY_JOINS}
            LEFT JOIN ({STOCK_SUBQUERY}) stock_totals ON stock_totals.part_id = p.id
            {where_sql}
            ORDER BY {actual_sort} {sort_direction}
            LIMIT ? OFFSET ?
        """
        main_params = [*params, page_size, offset]
        cursor = await self.db.execute(sql, main_params)
        items = await cursor.fetchall()

        return items, total

    async def get_by_id_full(self, part_id: int) -> dict | None:
        """Get a single part with hierarchy names, brand, and stock totals."""
        sql = f"""
            SELECT p.*,
                   cat.name AS category_name,
                   sty.name AS style_name,
                   typ.name AS type_name,
                   col.name AS color_name,
                   col.hex_code AS color_hex,
                   b.name AS brand_name,
                   COALESCE(st.total_stock, 0) AS total_stock,
                   COALESCE(st.warehouse_stock, 0) AS warehouse_stock,
                   COALESCE(st.truck_stock, 0) AS truck_stock,
                   COALESCE(st.job_stock, 0) AS job_stock,
                   COALESCE(st.pulled_stock, 0) AS pulled_stock,
                   CASE
                       WHEN p.part_type = 'specific' AND p.manufacturer_part_number IS NULL
                       THEN 1 ELSE 0
                   END AS has_pending_part_number
            FROM parts p
            {HIERARCHY_JOINS}
            LEFT JOIN ({STOCK_SUBQUERY}) st ON st.part_id = p.id
            WHERE p.id = ?
        """
        cursor = await self.db.execute(sql, (part_id,))
        return await cursor.fetchone()

    async def get_by_code(self, code: str) -> dict | None:
        """Find a part by its unique code. Returns None if code is None."""
        if not code:
            return None
        cursor = await self.db.execute(
            "SELECT * FROM parts WHERE code = ?", (code,)
        )
        return await cursor.fetchone()

    async def get_supplier_links(self, part_id: int) -> list[dict]:
        """Get all supplier links for a part with supplier names."""
        sql = """
            SELECT psl.*, s.name AS supplier_name
            FROM part_supplier_links psl
            JOIN suppliers s ON s.id = psl.supplier_id
            WHERE psl.part_id = ?
            ORDER BY psl.is_preferred DESC, s.name ASC
        """
        cursor = await self.db.execute(sql, (part_id,))
        return await cursor.fetchall()

    async def add_supplier_link(self, part_id: int, data: dict) -> int:
        """Add a supplier link to a part."""
        data["part_id"] = part_id
        columns = ", ".join(data.keys())
        placeholders = ", ".join(["?"] * len(data))
        cursor = await self.db.execute(
            f"INSERT INTO part_supplier_links ({columns}) VALUES ({placeholders})",  # noqa: S608
            tuple(data.values()),
        )
        await self.db.commit()
        return cursor.lastrowid  # type: ignore[return-value]

    async def remove_supplier_link(self, link_id: int) -> bool:
        """Remove a supplier link."""
        cursor = await self.db.execute(
            "DELETE FROM part_supplier_links WHERE id = ?", (link_id,)
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def update_pricing(
        self, part_id: int, cost: float, markup: float
    ) -> bool:
        """Update only the pricing fields on a part."""
        cursor = await self.db.execute(
            """UPDATE parts
               SET company_cost_price = ?,
                   company_markup_percent = ?,
                   updated_at = datetime('now')
               WHERE id = ?""",
            (cost, markup, part_id),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def get_pending_part_numbers(
        self,
        *,
        brand_id: int | None = None,
        page: int = 1,
        page_size: int = 50,
    ) -> tuple[list[dict], int]:
        """Get branded parts that are missing manufacturer_part_number.

        Returns (items, total_count) for the Pending Part Numbers queue.
        """
        where = "p.part_type = 'specific' AND p.manufacturer_part_number IS NULL"
        params: list[Any] = []

        if brand_id is not None:
            where += " AND p.brand_id = ?"
            params.append(brand_id)

        # Count
        count_sql = f"""
            SELECT COUNT(*) AS cnt FROM parts p WHERE {where}
        """
        count_cursor = await self.db.execute(count_sql, params)
        count_row = await count_cursor.fetchone()
        total = count_row["cnt"] if count_row else 0

        # Items with hierarchy names
        offset = (page - 1) * page_size
        sql = f"""
            SELECT p.id, p.name, p.brand_id, p.created_at,
                   cat.name AS category_name,
                   sty.name AS style_name,
                   typ.name AS type_name,
                   col.name AS color_name,
                   b.name AS brand_name
            FROM parts p
            {HIERARCHY_JOINS}
            WHERE {where}
            ORDER BY p.created_at ASC
            LIMIT ? OFFSET ?
        """
        cursor = await self.db.execute(sql, [*params, page_size, offset])
        items = await cursor.fetchall()

        return items, total

    async def count_pending_part_numbers(self) -> int:
        """Count branded parts missing manufacturer_part_number (for badge)."""
        cursor = await self.db.execute(
            "SELECT COUNT(*) AS cnt FROM parts "
            "WHERE part_type = 'specific' AND manufacturer_part_number IS NULL"
        )
        row = await cursor.fetchone()
        return row["cnt"] if row else 0

    async def get_catalog_groups(
        self,
        *,
        search: str | None = None,
        category_id: int | None = None,
        is_deprecated: bool | None = None,
    ) -> list[dict]:
        """Get parts grouped by (category_id, brand_id) for the product card view.

        Returns a list of groups, each containing aggregate data (variant count,
        total stock, price range) and nested variant details.  The grouping key
        is (category_id, brand_id) where brand_id=NULL → "General".

        A single query fetches everything; Python does the grouping via
        OrderedDict to preserve the ORDER BY sort.
        """
        where_clauses: list[str] = []
        params: list[Any] = []

        if search:
            where_clauses.append(
                "(p.code LIKE ? OR p.name LIKE ? OR p.description LIKE ?)"
            )
            params.extend([f"%{search}%"] * 3)
        if category_id is not None:
            where_clauses.append("p.category_id = ?")
            params.append(category_id)
        if is_deprecated is not None:
            where_clauses.append("p.is_deprecated = ?")
            params.append(int(is_deprecated))

        where_sql = (
            f"WHERE {' AND '.join(where_clauses)}" if where_clauses else ""
        )

        sql = f"""
            SELECT p.id, p.name, p.code, p.part_type, p.image_url,
                   p.category_id, p.brand_id,
                   p.manufacturer_part_number,
                   p.unit_of_measure,
                   p.company_cost_price,
                   p.company_sell_price,
                   p.is_deprecated,
                   cat.name AS category_name,
                   cat.image_url AS category_image_url,
                   cat.sort_order AS category_sort_order,
                   sty.name AS style_name,
                   typ.name AS type_name,
                   col.name AS color_name,
                   b.name AS brand_name,
                   COALESCE(stock_totals.total_stock, 0) AS total_stock,
                   CASE WHEN p.part_type = 'specific'
                             AND p.manufacturer_part_number IS NULL
                        THEN 1 ELSE 0
                   END AS has_pending_part_number
            FROM parts p
            {HIERARCHY_JOINS}
            LEFT JOIN ({STOCK_SUBQUERY}) stock_totals
                ON stock_totals.part_id = p.id
            {where_sql}
            ORDER BY cat.sort_order ASC, cat.name ASC,
                     CASE WHEN p.brand_id IS NULL THEN 0 ELSE 1 END,
                     b.name ASC,
                     sty.sort_order, typ.sort_order, col.sort_order, p.name
        """

        cursor = await self.db.execute(sql, params)
        rows = await cursor.fetchall()

        # Group in Python by (category_id, brand_id) — preserves SQL order
        from collections import OrderedDict

        groups: OrderedDict[tuple, dict] = OrderedDict()

        for row in rows:
            key = (row["category_id"], row["brand_id"])
            if key not in groups:
                groups[key] = {
                    "category_id": row["category_id"],
                    "category_name": row["category_name"],
                    "brand_id": row["brand_id"],
                    "brand_name": row["brand_name"],
                    "image_url": row.get("category_image_url"),
                    "variant_count": 0,
                    "total_stock": 0,
                    "price_range_low": None,
                    "price_range_high": None,
                    "variants": [],
                }

            group = groups[key]
            group["variant_count"] += 1
            group["total_stock"] += row.get("total_stock", 0)

            sell_price = row.get("company_sell_price")
            if sell_price is not None:
                if (
                    group["price_range_low"] is None
                    or sell_price < group["price_range_low"]
                ):
                    group["price_range_low"] = sell_price
                if (
                    group["price_range_high"] is None
                    or sell_price > group["price_range_high"]
                ):
                    group["price_range_high"] = sell_price

            group["variants"].append(
                {
                    "id": row["id"],
                    "style_name": row.get("style_name"),
                    "type_name": row.get("type_name"),
                    "color_name": row.get("color_name"),
                    "code": row.get("code"),
                    "name": row["name"],
                    "manufacturer_part_number": row.get(
                        "manufacturer_part_number"
                    ),
                    "has_pending_part_number": bool(
                        row.get("has_pending_part_number", 0)
                    ),
                    "unit_of_measure": row.get("unit_of_measure", "each"),
                    "company_cost_price": row.get("company_cost_price"),
                    "company_sell_price": row.get("company_sell_price"),
                    "total_stock": row.get("total_stock", 0),
                    "image_url": row.get("image_url"),
                    "is_deprecated": bool(row.get("is_deprecated", 0)),
                }
            )

        return list(groups.values())

    async def get_catalog_stats(self) -> dict:
        """Get summary statistics for the parts catalog."""
        sql = """
            SELECT
                COUNT(*) AS total_parts,
                SUM(CASE WHEN is_deprecated = 1 THEN 1 ELSE 0 END) AS deprecated_parts,
                SUM(CASE WHEN part_type = 'general' THEN 1 ELSE 0 END) AS general_parts,
                SUM(CASE WHEN part_type = 'specific' THEN 1 ELSE 0 END) AS specific_parts,
                COUNT(DISTINCT brand_id) AS unique_brands,
                COUNT(DISTINCT category_id) AS unique_categories,
                SUM(CASE WHEN part_type = 'specific' AND manufacturer_part_number IS NULL
                    THEN 1 ELSE 0 END) AS pending_part_numbers
            FROM parts
        """
        cursor = await self.db.execute(sql)
        row = await cursor.fetchone()
        return dict(row) if row else {}
