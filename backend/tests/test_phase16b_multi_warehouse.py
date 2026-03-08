"""Tests for Phase 16B: Multi-Warehouse, Warehouse Transfer & Trailer Templates.

Covers:
  1. Warehouse→warehouse transfer via movement engine
  2. Dashboard/KPI/inventory warehouse_id scoping
  3. Trailer stock template CRUD + restock guidance
  4. Vehicle inventory add/remove via MovementService (refactored)
"""

from __future__ import annotations

import aiosqlite
import pytest
from httpx import AsyncClient

from tests.conftest import seed_part, seed_stock


# ── Helpers ─────────────────────────────────────────────────────────


async def _create_second_warehouse(db: aiosqlite.Connection) -> int:
    """Insert a second warehouse_locations row and return its id."""
    cursor = await db.execute(
        """
        INSERT INTO warehouse_locations (name, address_street, is_primary)
        VALUES ('Satellite Shop', '456 Second Ave', 0)
        """
    )
    await db.commit()
    return cursor.lastrowid


async def _create_trailer(client: AsyncClient, code: str = "TR-TPL-01") -> int:
    """Create a trailer via the API and return its id."""
    resp = await client.post(
        "/api/trucks/trailers",
        json={
            "trailer_code": code,
            "name": f"Template Test {code}",
            "home_warehouse_id": 1,
        },
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["data"]["id"]


# ── 1. Warehouse ↔ Warehouse Transfer ──────────────────────────────


@pytest.mark.asyncio
async def test_warehouse_to_warehouse_transfer(
    auth_client: AsyncClient,
    db: aiosqlite.Connection,
):
    """Move parts between two warehouses using the movement wizard."""
    part_id = await seed_part(db)
    wh2_id = await _create_second_warehouse(db)

    # Seed 20 units in warehouse 1
    await seed_stock(db, part_id, "warehouse", 1, qty=20)

    # Transfer 8 from warehouse 1 → warehouse 2
    resp = await auth_client.post(
        "/api/warehouse/movements/execute",
        json={
            "from_location_type": "warehouse",
            "from_location_id": 1,
            "to_location_type": "warehouse",
            "to_location_id": wh2_id,
            "items": [{"part_id": part_id, "qty": 8}],
            "reason": "Inter-warehouse transfer",
            "notes": "Rebalance stock",
        },
    )
    assert resp.status_code in (200, 201), resp.text

    # Verify stock levels via DB
    cursor = await db.execute(
        "SELECT SUM(qty) AS total FROM stock WHERE part_id = ? AND location_type = 'warehouse' AND location_id = 1",
        (part_id,),
    )
    wh1 = await cursor.fetchone()
    assert wh1["total"] == 12

    cursor = await db.execute(
        "SELECT SUM(qty) AS total FROM stock WHERE part_id = ? AND location_type = 'warehouse' AND location_id = ?",
        (part_id, wh2_id),
    )
    wh2 = await cursor.fetchone()
    assert wh2["total"] == 8


# ── 2. Dashboard Warehouse Scoping ─────────────────────────────────


@pytest.mark.asyncio
async def test_dashboard_kpis_with_warehouse_filter(
    auth_client: AsyncClient,
    db: aiosqlite.Connection,
):
    """KPI endpoint accepts warehouse_id and doesn't crash."""
    part_id = await seed_part(db)
    await seed_stock(db, part_id, "warehouse", 1, qty=10)

    # Unscoped call — should include everything
    resp = await auth_client.get("/api/warehouse/dashboard/kpis")
    assert resp.status_code == 200
    kpis_all = resp.json()["data"]
    assert "total_unique_parts" in kpis_all or "total_units" in kpis_all

    # Scoped to warehouse 1
    resp = await auth_client.get("/api/warehouse/dashboard/kpis", params={"warehouse_id": 1})
    assert resp.status_code == 200

    # Scoped to non-existent warehouse — should still return valid response (zeroes)
    resp = await auth_client.get("/api/warehouse/dashboard/kpis", params={"warehouse_id": 9999})
    assert resp.status_code == 200


@pytest.mark.asyncio
async def test_inventory_with_warehouse_filter(
    auth_client: AsyncClient,
    db: aiosqlite.Connection,
):
    """Inventory endpoint respects warehouse_id and includes trailer_qty."""
    part_id = await seed_part(db)
    await seed_stock(db, part_id, "warehouse", 1, qty=15)

    # Unscoped
    resp = await auth_client.get("/api/warehouse/inventory")
    assert resp.status_code == 200
    items = resp.json()["data"]["items"]
    assert len(items) >= 1
    # Check trailer_qty field exists on inventory items
    assert "trailer_qty" in items[0]

    # Scoped
    resp = await auth_client.get("/api/warehouse/inventory", params={"warehouse_id": 1})
    assert resp.status_code == 200


# ── 3. Trailer Stock Template CRUD ─────────────────────────────────


@pytest.mark.asyncio
async def test_trailer_template_crud(
    auth_client: AsyncClient,
    db: aiosqlite.Connection,
):
    """Full CRUD cycle for trailer stock templates + restock guidance."""
    part_id = await seed_part(db)
    trailer_id = await _create_trailer(auth_client, "TR-TPL-CRUD")

    # Create global template
    resp = await auth_client.post(
        "/api/trucks/trailer-templates",
        json={
            "name": "Standard Grab Kit",
            "is_default": True,
            "notes": "Default parts every trailer should carry",
            "lines": [
                {"part_id": part_id, "target_qty": 20, "min_qty": 5},
            ],
        },
    )
    assert resp.status_code == 201, resp.text
    template = resp.json()["data"]
    template_id = template["id"]
    assert template["name"] == "Standard Grab Kit"
    assert template["is_default"] == 1
    assert len(template["lines"]) == 1
    assert template["lines"][0]["target_qty"] == 20

    # List templates
    resp = await auth_client.get("/api/trucks/trailer-templates")
    assert resp.status_code == 200
    templates = resp.json()["data"]
    assert any(t["id"] == template_id for t in templates)

    # Get single template
    resp = await auth_client.get(f"/api/trucks/trailer-templates/{template_id}")
    assert resp.status_code == 200
    fetched = resp.json()["data"]
    assert fetched["id"] == template_id
    assert len(fetched["lines"]) == 1

    # Update template (change name + replace lines)
    resp = await auth_client.put(
        f"/api/trucks/trailer-templates/{template_id}",
        json={
            "name": "Updated Grab Kit",
            "lines": [
                {"part_id": part_id, "target_qty": 30, "min_qty": 10},
            ],
        },
    )
    assert resp.status_code == 200
    updated = resp.json()["data"]
    assert updated["name"] == "Updated Grab Kit"
    assert updated["lines"][0]["target_qty"] == 30

    # Restock guidance — trailer has zero stock, template says 30
    resp = await auth_client.get(
        f"/api/trucks/trailers/{trailer_id}/restock-guidance"
    )
    assert resp.status_code == 200
    guidance = resp.json()["data"]
    assert guidance["template_id"] == template_id
    assert guidance["summary"]["parts_below_target"] == 1
    assert guidance["lines"][0]["deficit"] == 30
    assert guidance["lines"][0]["status"] == "critical"

    # Delete template
    resp = await auth_client.delete(f"/api/trucks/trailer-templates/{template_id}")
    assert resp.status_code == 200
    assert resp.json()["data"]["deleted"] is True

    # Verify deletion
    resp = await auth_client.get(f"/api/trucks/trailer-templates/{template_id}")
    assert resp.status_code == 404


# ── 4. Vehicle Inventory via MovementService ───────────────────────


@pytest.mark.asyncio
async def test_vehicle_add_remove_inventory_uses_movement(
    auth_client: AsyncClient,
    db: aiosqlite.Connection,
):
    """Vehicle add/remove inventory now routes through MovementService."""
    part_id = await seed_part(db)
    await seed_stock(db, part_id, "warehouse", 1, qty=50)

    # Create a vehicle
    resp = await auth_client.post(
        "/api/trucks",
        json={
            "vehicle_number": "V-MOVE-001",
            "vehicle_name": "Move Test Truck",
            "vehicle_type": "company_truck",
            "make": "Ford",
            "model": "F-350",
            "year": 2024,
            "status": "active",
        },
    )
    assert resp.status_code == 201, resp.text
    vehicle_id = resp.json()["data"]["id"]

    # Add 15 to vehicle
    resp = await auth_client.post(
        f"/api/trucks/{vehicle_id}/inventory/add",
        params={"part_id": part_id, "qty": 15},
    )
    assert resp.status_code == 201, resp.text
    result = resp.json()["data"]
    assert result["qty_added"] == 15
    # New: movement_count present (from MovementService)
    assert "movement_count" in result

    # Remove 5 from vehicle
    resp = await auth_client.post(
        f"/api/trucks/{vehicle_id}/inventory/remove",
        params={"part_id": part_id, "qty": 5},
    )
    assert resp.status_code == 200, resp.text
    result = resp.json()["data"]
    assert result["qty_removed"] == 5
    assert "movement_count" in result

    # Verify stock levels: warehouse should have 40 (50-15+5), truck should have 10 (15-5)
    cursor = await db.execute(
        "SELECT SUM(qty) AS total FROM stock WHERE part_id = ? AND location_type = 'warehouse' AND location_id = 1",
        (part_id,),
    )
    wh_stock = await cursor.fetchone()
    assert wh_stock["total"] == 40

    cursor = await db.execute(
        "SELECT SUM(qty) AS total FROM stock WHERE part_id = ? AND location_type = 'truck' AND location_id = ?",
        (part_id, vehicle_id),
    )
    truck_stock = await cursor.fetchone()
    assert truck_stock["total"] == 10
