"""
Tests for the Parts Router — CRUD operations via /api/parts/catalog.

Covers:
- Create part
- Get parts list
- Search parts by name
- Update part
"""

from __future__ import annotations

import pytest
import pytest_asyncio
import aiosqlite
from httpx import AsyncClient


# ── Helper to create a category via DB ─────────────────────────────
async def _ensure_category(db: aiosqlite.Connection) -> int:
    """Insert a test category, return its ID."""
    cursor = await db.execute(
        "INSERT INTO part_categories (name) VALUES (?)",
        ("Router Test Cat",),
    )
    await db.commit()
    return cursor.lastrowid


# ══════════════════════════════════════════════════════════════════
# Create Part
# ══════════════════════════════════════════════════════════════════


class TestCreatePart:
    """Test part creation via API."""

    @pytest.mark.asyncio
    async def test_create_part_returns_success(self, auth_client: AsyncClient, db_with_admin: aiosqlite.Connection):
        """Creating a valid part should succeed."""
        cat_id = await _ensure_category(db_with_admin)
        resp = await auth_client.post("/api/parts/catalog", json={
            "name": "Test Wire 14/2",
            "category_id": cat_id,
            "company_cost_price": 12.50,
        })
        assert resp.status_code in (200, 201)
        data = resp.json()["data"]
        assert data["id"] is not None
        assert data["name"] == "Test Wire 14/2"

    @pytest.mark.asyncio
    async def test_create_part_without_auth_fails(self, client: AsyncClient):
        """Creating a part without authentication should fail."""
        resp = await client.post("/api/parts/catalog", json={
            "name": "Unauthorized Part",
            "category_id": 1,
        })
        assert resp.status_code == 401


# ══════════════════════════════════════════════════════════════════
# Get Parts
# ══════════════════════════════════════════════════════════════════


class TestGetParts:
    """Test parts listing and retrieval."""

    @pytest.mark.asyncio
    async def test_get_parts_list(self, auth_client: AsyncClient, db_with_admin: aiosqlite.Connection):
        """Should return a paginated list of parts."""
        cat_id = await _ensure_category(db_with_admin)
        await auth_client.post("/api/parts/catalog", json={
            "name": "List Test Part",
            "category_id": cat_id,
        })

        resp = await auth_client.get("/api/parts/catalog")
        assert resp.status_code == 200
        data = resp.json()["data"]
        items = data if isinstance(data, list) else data.get("items", [])
        assert len(items) >= 1

    @pytest.mark.asyncio
    async def test_search_parts_by_name(self, auth_client: AsyncClient, db_with_admin: aiosqlite.Connection):
        """Searching parts by name should return matching results."""
        cat_id = await _ensure_category(db_with_admin)
        await auth_client.post("/api/parts/catalog", json={
            "name": "Unique Conduit Fitting",
            "category_id": cat_id,
        })

        resp = await auth_client.get("/api/parts/catalog", params={"search": "Unique Conduit"})
        assert resp.status_code == 200
        data = resp.json()["data"]
        items = data if isinstance(data, list) else data.get("items", [])
        names = [p["name"] for p in items]
        assert any("Unique Conduit" in n for n in names)


# ══════════════════════════════════════════════════════════════════
# Update Part
# ══════════════════════════════════════════════════════════════════


class TestUpdatePart:
    """Test part update via API."""

    @pytest.mark.asyncio
    async def test_update_part_name(self, auth_client: AsyncClient, db_with_admin: aiosqlite.Connection):
        """Updating a part's name should persist the change."""
        cat_id = await _ensure_category(db_with_admin)
        resp = await auth_client.post("/api/parts/catalog", json={
            "name": "Before Update",
            "category_id": cat_id,
        })
        part_id = resp.json()["data"]["id"]

        resp = await auth_client.put(f"/api/parts/catalog/{part_id}", json={
            "name": "After Update",
        })
        assert resp.status_code == 200

        resp = await auth_client.get(f"/api/parts/catalog/{part_id}")
        assert resp.json()["data"]["name"] == "After Update"
