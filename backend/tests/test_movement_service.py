"""
Tests for the Movement Service — stock movements between locations.

Covers:
- Moving parts between warehouse, truck, pulled, job locations
- Insufficient stock validation
- Movement history recording
- Atomic batch operations
"""

from __future__ import annotations

import pytest
import pytest_asyncio
import aiosqlite

from tests.conftest import seed_part, seed_stock, seed_job

from app.models.warehouse import MovementRequest, MovementLineItem
from app.services.movement_service import MovementService


# ── Helper: ensure a truck exists ──────────────────────────────────
async def _ensure_truck(db: aiosqlite.Connection, truck_id: int = 1) -> None:
    await db.execute(
        "INSERT OR IGNORE INTO vehicles (id, vehicle_number, vehicle_name, vehicle_type, status) "
        "VALUES (?, ?, ?, 'company_truck', 'active')",
        (truck_id, f"T-{truck_id:03d}", f"Test Truck {truck_id}"),
    )
    await db.commit()


async def _ensure_trailer(db: aiosqlite.Connection, trailer_id: int = 1) -> None:
    await db.execute(
        "INSERT OR IGNORE INTO job_trailers (id, trailer_code, name, status, is_active) "
        "VALUES (?, ?, ?, 'active', 1)",
        (trailer_id, f"TR-{trailer_id:03d}", f"Test Trailer {trailer_id}"),
    )
    await db.commit()


# ══════════════════════════════════════════════════════════════════
# Validation
# ══════════════════════════════════════════════════════════════════


class TestMovementValidation:
    """Pre-flight validation checks without executing moves."""

    @pytest.mark.asyncio
    async def test_valid_warehouse_to_truck_movement(self, db: aiosqlite.Connection):
        """A valid movement should pass validation."""
        part_id = await seed_part(db)
        await seed_stock(db, part_id, "warehouse", 1, qty=50)
        await _ensure_truck(db)

        svc = MovementService(db)
        req = MovementRequest(
            from_location_type="warehouse",
            from_location_id=1,
            to_location_type="truck",
            to_location_id=1,
            items=[MovementLineItem(part_id=part_id, qty=10)],
        )
        result = await svc.validate_movement(req)
        assert result.valid is True
        assert len(result.errors) == 0

    @pytest.mark.asyncio
    async def test_insufficient_stock_fails_validation(self, db: aiosqlite.Connection):
        """Cannot move more than available stock."""
        part_id = await seed_part(db)
        await seed_stock(db, part_id, "warehouse", 1, qty=5)
        await _ensure_truck(db)

        svc = MovementService(db)
        req = MovementRequest(
            from_location_type="warehouse",
            from_location_id=1,
            to_location_type="truck",
            to_location_id=1,
            items=[MovementLineItem(part_id=part_id, qty=10)],
        )
        result = await svc.validate_movement(req)
        assert result.valid is False
        assert len(result.errors) > 0

    @pytest.mark.asyncio
    async def test_valid_warehouse_to_trailer_movement(self, db: aiosqlite.Connection):
        """Trailer preload path should validate like other transfer paths."""
        part_id = await seed_part(db)
        await seed_stock(db, part_id, "warehouse", 1, qty=25)
        await _ensure_trailer(db, trailer_id=1)

        svc = MovementService(db)
        req = MovementRequest(
            from_location_type="warehouse",
            from_location_id=1,
            to_location_type="trailer",
            to_location_id=1,
            items=[MovementLineItem(part_id=part_id, qty=10)],
        )
        result = await svc.validate_movement(req)
        assert result.valid is True
        assert not result.errors


# ══════════════════════════════════════════════════════════════════
# Execution
# ══════════════════════════════════════════════════════════════════


class TestMovementExecution:
    """Execute movements and verify stock level changes."""

    @pytest.mark.asyncio
    async def test_move_decrements_source_increments_dest(self, db: aiosqlite.Connection):
        """Stock should decrease at source and increase at destination."""
        part_id = await seed_part(db)
        await seed_stock(db, part_id, "warehouse", 1, qty=100)
        await seed_stock(db, part_id, "truck", 1, qty=0)
        await _ensure_truck(db)

        svc = MovementService(db)
        req = MovementRequest(
            from_location_type="warehouse",
            from_location_id=1,
            to_location_type="truck",
            to_location_id=1,
            items=[MovementLineItem(part_id=part_id, qty=25)],
            reason="Truck Restock",
        )
        result = await svc.execute_movement(req, performed_by=1)
        assert result.success is True
        assert result.total_qty == 25

        # Verify source decreased
        cursor = await db.execute(
            "SELECT SUM(qty) as total FROM stock WHERE part_id = ? AND location_type = 'warehouse' AND location_id = 1",
            (part_id,),
        )
        row = await cursor.fetchone()
        assert row["total"] == 75

        # Verify destination increased
        cursor = await db.execute(
            "SELECT SUM(qty) as total FROM stock WHERE part_id = ? AND location_type = 'truck' AND location_id = 1",
            (part_id,),
        )
        row = await cursor.fetchone()
        assert row["total"] == 25

    @pytest.mark.asyncio
    async def test_move_more_than_available_fails(self, db: aiosqlite.Connection):
        """Executing a move with insufficient stock should fail."""
        part_id = await seed_part(db)
        await seed_stock(db, part_id, "warehouse", 1, qty=5)
        await _ensure_truck(db)

        svc = MovementService(db)
        req = MovementRequest(
            from_location_type="warehouse",
            from_location_id=1,
            to_location_type="truck",
            to_location_id=1,
            items=[MovementLineItem(part_id=part_id, qty=10)],
        )
        # Should either fail validation or raise error during execution
        with pytest.raises(Exception):
            await svc.execute_movement(req, performed_by=1)

    @pytest.mark.asyncio
    async def test_movement_creates_history_record(self, db: aiosqlite.Connection):
        """Each movement should create a record in stock_movements."""
        part_id = await seed_part(db)
        await seed_stock(db, part_id, "warehouse", 1, qty=50)
        await _ensure_truck(db)

        svc = MovementService(db)
        req = MovementRequest(
            from_location_type="warehouse",
            from_location_id=1,
            to_location_type="truck",
            to_location_id=1,
            items=[MovementLineItem(part_id=part_id, qty=10)],
            reason="Truck Restock",
        )
        await svc.execute_movement(req, performed_by=1)

        cursor = await db.execute(
            "SELECT COUNT(*) as cnt FROM stock_movements WHERE part_id = ?",
            (part_id,),
        )
        row = await cursor.fetchone()
        assert row["cnt"] >= 1

    @pytest.mark.asyncio
    async def test_staged_movement_through_pulled(self, db: aiosqlite.Connection):
        """Move warehouse→pulled, then pulled→truck should work correctly."""
        part_id = await seed_part(db)
        await seed_stock(db, part_id, "warehouse", 1, qty=100)
        await _ensure_truck(db)

        svc = MovementService(db)

        # Step 1: warehouse → pulled (staging)
        req1 = MovementRequest(
            from_location_type="warehouse",
            from_location_id=1,
            to_location_type="pulled",
            to_location_id=1,
            items=[MovementLineItem(part_id=part_id, qty=20)],
            reason="Staging",
            destination_type="truck",
            destination_id=1,
        )
        result1 = await svc.execute_movement(req1, performed_by=1)
        assert result1.success is True

        # Step 2: pulled → truck
        req2 = MovementRequest(
            from_location_type="pulled",
            from_location_id=1,
            to_location_type="truck",
            to_location_id=1,
            items=[MovementLineItem(part_id=part_id, qty=20)],
            reason="Truck Restock",
        )
        result2 = await svc.execute_movement(req2, performed_by=1)
        assert result2.success is True

        # Verify final state: warehouse=80, truck=20
        cursor = await db.execute(
            "SELECT SUM(qty) as total FROM stock WHERE part_id = ? AND location_type = 'warehouse'",
            (part_id,),
        )
        assert (await cursor.fetchone())["total"] == 80

        cursor = await db.execute(
            "SELECT SUM(qty) as total FROM stock WHERE part_id = ? AND location_type = 'truck' AND location_id = 1",
            (part_id,),
        )
        assert (await cursor.fetchone())["total"] == 20

    @pytest.mark.asyncio
    async def test_batch_movement_multiple_items(self, db: aiosqlite.Connection):
        """A batch with multiple items should move all atomically."""
        part_a = await seed_part(db, name="Wire A")
        part_b = await seed_part(db, name="Wire B")
        await seed_stock(db, part_a, "warehouse", 1, qty=50)
        await seed_stock(db, part_b, "warehouse", 1, qty=30)
        await _ensure_truck(db)

        svc = MovementService(db)
        req = MovementRequest(
            from_location_type="warehouse",
            from_location_id=1,
            to_location_type="truck",
            to_location_id=1,
            items=[
                MovementLineItem(part_id=part_a, qty=10),
                MovementLineItem(part_id=part_b, qty=5),
            ],
            reason="Truck Restock",
        )
        result = await svc.execute_movement(req, performed_by=1)
        assert result.success is True
        assert result.total_items == 2
        assert result.total_qty == 15

    @pytest.mark.asyncio
    async def test_trailer_preload_and_job_consume_flow(self, db: aiosqlite.Connection):
        """warehouse→trailer preload should transfer only; trailer→job should consume."""
        part_id = await seed_part(db)
        job_id = await seed_job(db)
        await seed_stock(db, part_id, "warehouse", 1, qty=40)
        await _ensure_trailer(db, trailer_id=1)

        svc = MovementService(db)

        preload = MovementRequest(
            from_location_type="warehouse",
            from_location_id=1,
            to_location_type="trailer",
            to_location_id=1,
            items=[MovementLineItem(part_id=part_id, qty=15)],
            reason="Trailer Preload",
        )
        preload_result = await svc.execute_movement(preload, performed_by=1)
        assert preload_result.success is True

        consume = MovementRequest(
            from_location_type="trailer",
            from_location_id=1,
            to_location_type="job",
            to_location_id=job_id,
            items=[MovementLineItem(part_id=part_id, qty=6)],
            reason="Trailer Job Pull",
            job_id=job_id,
        )
        consume_result = await svc.execute_movement(consume, performed_by=1)
        assert consume_result.success is True

        # warehouse: 40 - 15 = 25
        cursor = await db.execute(
            "SELECT COALESCE(SUM(qty), 0) as total FROM stock WHERE part_id = ? AND location_type = 'warehouse' AND location_id = 1",
            (part_id,),
        )
        assert (await cursor.fetchone())["total"] == 25

        # trailer: 15 - 6 = 9
        cursor = await db.execute(
            "SELECT COALESCE(SUM(qty), 0) as total FROM stock WHERE part_id = ? AND location_type = 'trailer' AND location_id = 1",
            (part_id,),
        )
        assert (await cursor.fetchone())["total"] == 9

        # job: +6
        cursor = await db.execute(
            "SELECT COALESCE(SUM(qty), 0) as total FROM stock WHERE part_id = ? AND location_type = 'job' AND location_id = ?",
            (part_id, job_id),
        )
        assert (await cursor.fetchone())["total"] == 6
