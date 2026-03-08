"""Tests for trailer API endpoints under /api/trucks/trailers."""

from __future__ import annotations

import aiosqlite
import pytest
from httpx import AsyncClient

from tests.conftest import seed_job, seed_part, seed_stock


@pytest.mark.asyncio
async def test_trailer_crud_and_location_events(
    auth_client: AsyncClient,
):
    # Create trailer
    resp = await auth_client.post(
        "/api/trucks/trailers",
        json={
            "trailer_code": "TR-100",
            "name": "Trailer 100",
            "home_warehouse_id": 1,
        },
    )
    assert resp.status_code == 201, resp.text
    trailer = resp.json()["data"]
    trailer_id = trailer["id"]

    # List trailers
    resp = await auth_client.get("/api/trucks/trailers")
    assert resp.status_code == 200
    rows = resp.json()["data"]
    assert any(r["trailer_code"] == "TR-100" for r in rows)

    # Record location event
    resp = await auth_client.post(
        f"/api/trucks/trailers/{trailer_id}/location-events",
        json={
            "event_type": "arrived_job",
            "location_kind": "job",
            "job_id": 1,
            "notes": "Arrived for setup",
        },
    )
    assert resp.status_code == 201, resp.text

    # Fetch latest location snapshot
    resp = await auth_client.get(f"/api/trucks/trailers/{trailer_id}/location")
    assert resp.status_code == 200
    latest = resp.json()["data"]
    assert latest["location_kind"] == "job"

    # Fetch timeline
    resp = await auth_client.get(f"/api/trucks/trailers/{trailer_id}/location-events")
    assert resp.status_code == 200
    events = resp.json()["data"]
    assert len(events) >= 1


@pytest.mark.asyncio
async def test_trailer_inventory_preload_consume_return(
    auth_client: AsyncClient,
    db: aiosqlite.Connection,
):
    # Seed part/job/source stock
    part_id = await seed_part(db)
    job_id = await seed_job(db)
    await seed_stock(db, part_id, "warehouse", 1, qty=30)

    # Create trailer
    resp = await auth_client.post(
        "/api/trucks/trailers",
        json={
            "trailer_code": "TR-200",
            "name": "Trailer 200",
            "home_warehouse_id": 1,
        },
    )
    assert resp.status_code == 201, resp.text
    trailer_id = resp.json()["data"]["id"]

    # Preload 12 from warehouse -> trailer
    resp = await auth_client.post(
        f"/api/trucks/trailers/{trailer_id}/inventory/preload",
        params={"part_id": part_id, "qty": 12, "from_location_type": "warehouse", "from_location_id": 1},
    )
    assert resp.status_code == 200, resp.text

    # Consume 5 from trailer -> job
    resp = await auth_client.post(
        f"/api/trucks/trailers/{trailer_id}/inventory/consume",
        params={"part_id": part_id, "qty": 5, "job_id": job_id},
    )
    assert resp.status_code == 200, resp.text

    # Return 3 from trailer -> warehouse
    resp = await auth_client.post(
        f"/api/trucks/trailers/{trailer_id}/inventory/return",
        params={"part_id": part_id, "qty": 3, "to_location_type": "warehouse", "to_location_id": 1},
    )
    assert resp.status_code == 200, resp.text

    # Verify inventory endpoint sees remaining 4 on trailer (12 - 5 - 3)
    resp = await auth_client.get(f"/api/trucks/trailers/{trailer_id}/inventory")
    assert resp.status_code == 200
    rows = resp.json()["data"]
    target = next((r for r in rows if r["part_id"] == part_id), None)
    assert target is not None
    assert target["qty"] == 4
