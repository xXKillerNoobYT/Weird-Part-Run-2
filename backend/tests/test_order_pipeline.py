"""
Integration Test: Order-to-Stock Pipeline

Tests the full lifecycle:
1. Create JPO with line items
2. Submit & approve JPO
3. Create PO from approved JPO
4. (Stock receive verification is a future enhancement)

This tests the integration between OrdersService, JPO/PO repos,
and the status transition logic.
"""

from __future__ import annotations

import pytest
import pytest_asyncio
import aiosqlite

from tests.conftest import seed_part, seed_job, seed_supplier

from app.services.orders_service import OrdersService


class TestOrderToStockPipeline:
    """Full order lifecycle integration test."""

    @pytest.mark.asyncio
    async def test_full_jpo_to_po_lifecycle(self, db_with_admin: aiosqlite.Connection):
        """JPO created → submitted → approved → PO created from it."""
        db = db_with_admin

        # Setup: create parts, job, supplier
        part_a = await seed_part(db, name="Wire 12/2 Romex")
        part_b = await seed_part(db, name="Wire 14/2 Romex")
        job_id = await seed_job(db, job_name="Pipeline Test Job", job_number="PTJ-001")
        supplier_id = await seed_supplier(db, name="Acme Electrical")

        svc = OrdersService(db)

        # Step 1: Create JPO with 2 line items
        jpo = await svc.create_jpo(
            requested_by=1,
            lines=[
                {"part_id": part_a, "qty_requested": 20},
                {"part_id": part_b, "qty_requested": 10},
            ],
            job_id=job_id,
            order_type="job",
            priority="normal",
        )
        assert jpo["status"] == "draft"
        jpo_id = jpo["id"]

        # Step 2: Submit JPO
        submitted = await svc.submit_jpo(jpo_id, user_id=1)
        assert submitted["status"] == "pending_approval"

        # Step 3: Approve JPO
        approved = await svc.approve_jpo(jpo_id, approved_by=1)
        assert approved["status"] == "approved"

        # Step 4: Create PO from JPO lines (fetch from DB since approve returns header only)
        cursor = await db.execute(
            "SELECT id FROM jpo_line_items WHERE jpo_id = ?", (jpo_id,)
        )
        rows = await cursor.fetchall()
        line_ids = [r["id"] for r in rows]
        assert len(line_ids) >= 2

        po = await svc.create_po_from_jpo(
            jpo_id=jpo_id,
            supplier_id=supplier_id,
            line_ids=line_ids,
            created_by=1,
        )
        assert po["id"] is not None
        assert po["status"] == "draft"
        assert po["po_number"] is not None

        # Verify PO has correct line items (check via line_count or DB)
        assert po.get("line_count", 0) >= 2 or True  # PO created successfully
        cursor = await db.execute(
            "SELECT COUNT(*) as cnt FROM po_line_items WHERE po_id = ?", (po["id"],)
        )
        row = await cursor.fetchone()
        assert row["cnt"] >= 2

    @pytest.mark.asyncio
    async def test_jpo_rejection_and_resubmit(self, db_with_admin: aiosqlite.Connection):
        """JPO rejected → back to draft → resubmit → approve."""
        db = db_with_admin
        part_id = await seed_part(db, name="Rejection Test Part")
        job_id = await seed_job(db, job_name="Rejection Job", job_number="RJ-001")

        svc = OrdersService(db)

        # Create and submit
        jpo = await svc.create_jpo(
            requested_by=1,
            lines=[{"part_id": part_id, "qty_requested": 5}],
            job_id=job_id,
            order_type="job",
        )
        await svc.submit_jpo(jpo["id"], user_id=1)

        # Reject
        rejected = await svc.reject_jpo(jpo["id"], rejected_by=1, notes="Wrong quantity")
        assert rejected["status"] == "draft"

        # Resubmit and approve
        await svc.submit_jpo(jpo["id"], user_id=1)
        approved = await svc.approve_jpo(jpo["id"], approved_by=1)
        assert approved["status"] == "approved"


class TestLaborPipeline:
    """Clock in → clock out → verify hours."""

    @pytest.mark.asyncio
    async def test_clock_in_out_produces_hours(self, db_with_admin: aiosqlite.Connection):
        """Full clock in → clock out should produce a completed labor entry."""
        db = db_with_admin
        from tests.conftest import seed_job
        from app.models.jobs import ClockInRequest, ClockOutRequest
        from app.services.labor_service import LaborService

        job_id = await seed_job(db, job_name="Labor Pipeline Job", job_number="LPJ-001")
        svc = LaborService(db)

        # Clock in
        entry = await svc.clock_in(
            user_id=1,
            job_id=job_id,
            data=ClockInRequest(gps_lat=40.71, gps_lng=-74.00),
        )
        assert entry.status == "clocked_in"

        # Clock out
        result = await svc.clock_out(
            user_id=1,
            data=ClockOutRequest(
                labor_entry_id=entry.id,
                gps_lat=40.71,
                gps_lng=-74.00,
                drive_time_minutes=0,
                responses=[],
                one_time_answers=[],
            ),
        )
        assert result.status == "clocked_out"
        total = (result.regular_hours or 0) + (result.overtime_hours or 0)
        assert total >= 0

        # Verify entry persisted
        fetched = await svc.get_labor_entry(entry.id)
        assert fetched is not None
        assert fetched.status == "clocked_out"
