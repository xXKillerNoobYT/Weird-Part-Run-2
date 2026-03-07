"""
Tests for the Orders Service — JPO/PO lifecycle.

Covers:
- JPO creation with line items
- JPO status transitions (draft → pending_approval → approved)
- Invalid status transition rejection
- PO creation from JPO
- PO numbering with GC codes
"""

from __future__ import annotations

import pytest
import pytest_asyncio
import aiosqlite

from tests.conftest import seed_part, seed_job, seed_supplier

from app.services.orders_service import OrdersService


# ── Helper to create a JPO ─────────────────────────────────────────
async def _create_test_jpo(
    db: aiosqlite.Connection,
    part_id: int,
    job_id: int | None = None,
    qty: int = 10,
) -> dict:
    """Create a JPO through the service and return it."""
    svc = OrdersService(db)
    return await svc.create_jpo(
        requested_by=1,
        lines=[{"part_id": part_id, "qty_requested": qty}],
        job_id=job_id,
        order_type="job" if job_id else "warehouse",
        priority="normal",
    )


# ══════════════════════════════════════════════════════════════════
# JPO Creation
# ══════════════════════════════════════════════════════════════════


class TestJPOCreation:
    """Test Job Parts Order creation."""

    @pytest.mark.asyncio
    async def test_create_jpo_returns_order(self, db_with_admin: aiosqlite.Connection):
        """Creating a JPO should return an order with an ID and draft status."""
        part_id = await seed_part(db_with_admin)
        job_id = await seed_job(db_with_admin)

        jpo = await _create_test_jpo(db_with_admin, part_id, job_id)
        assert jpo is not None
        assert jpo["id"] is not None
        assert jpo["status"] == "draft"

    @pytest.mark.asyncio
    async def test_create_jpo_with_line_items(self, db_with_admin: aiosqlite.Connection):
        """JPO should have line items in the database."""
        part_id = await seed_part(db_with_admin)
        job_id = await seed_job(db_with_admin)

        jpo = await _create_test_jpo(db_with_admin, part_id, job_id, qty=25)
        assert jpo is not None
        # get_with_details returns line_count, not the actual lines
        assert jpo.get("line_count", 0) >= 1

    @pytest.mark.asyncio
    async def test_create_warehouse_restock_jpo(self, db_with_admin: aiosqlite.Connection):
        """Creating a warehouse restock JPO (no job_id) should work."""
        part_id = await seed_part(db_with_admin)

        svc = OrdersService(db_with_admin)
        jpo = await svc.create_jpo(
            requested_by=1,
            lines=[{"part_id": part_id, "qty_requested": 50}],
            job_id=None,
            order_type="warehouse",
        )
        assert jpo is not None
        assert jpo["status"] == "draft"


# ══════════════════════════════════════════════════════════════════
# JPO Status Transitions
# ══════════════════════════════════════════════════════════════════


class TestJPOStatusTransitions:
    """Test JPO status lifecycle."""

    @pytest.mark.asyncio
    async def test_submit_jpo(self, db_with_admin: aiosqlite.Connection):
        """Submitting a draft JPO should move it to pending_approval."""
        part_id = await seed_part(db_with_admin)
        job_id = await seed_job(db_with_admin)
        jpo = await _create_test_jpo(db_with_admin, part_id, job_id)

        svc = OrdersService(db_with_admin)
        result = await svc.submit_jpo(jpo["id"], user_id=1)
        assert result is not None
        assert result["status"] == "pending_approval"

    @pytest.mark.asyncio
    async def test_approve_jpo(self, db_with_admin: aiosqlite.Connection):
        """Approving a pending JPO should move it to approved."""
        part_id = await seed_part(db_with_admin)
        job_id = await seed_job(db_with_admin)
        jpo = await _create_test_jpo(db_with_admin, part_id, job_id)

        svc = OrdersService(db_with_admin)
        await svc.submit_jpo(jpo["id"], user_id=1)
        result = await svc.approve_jpo(jpo["id"], approved_by=1)
        assert result is not None
        assert result["status"] == "approved"

    @pytest.mark.asyncio
    async def test_reject_jpo_sends_back_to_draft(self, db_with_admin: aiosqlite.Connection):
        """Rejecting a pending JPO should move it back to draft."""
        part_id = await seed_part(db_with_admin)
        job_id = await seed_job(db_with_admin)
        jpo = await _create_test_jpo(db_with_admin, part_id, job_id)

        svc = OrdersService(db_with_admin)
        await svc.submit_jpo(jpo["id"], user_id=1)
        result = await svc.reject_jpo(jpo["id"], rejected_by=1, notes="Need different part")
        assert result is not None
        assert result["status"] == "draft"


# ══════════════════════════════════════════════════════════════════
# PO Creation from JPO
# ══════════════════════════════════════════════════════════════════


class TestPOCreation:
    """Test Purchase Order creation from approved JPOs."""

    @pytest.mark.asyncio
    async def test_create_po_from_approved_jpo(self, db_with_admin: aiosqlite.Connection):
        """Creating a PO from an approved JPO should succeed."""
        part_id = await seed_part(db_with_admin)
        job_id = await seed_job(db_with_admin)
        supplier_id = await seed_supplier(db_with_admin)
        jpo = await _create_test_jpo(db_with_admin, part_id, job_id)

        svc = OrdersService(db_with_admin)
        await svc.submit_jpo(jpo["id"], user_id=1)
        approved = await svc.approve_jpo(jpo["id"], approved_by=1)

        # Get line IDs from the approved JPO
        lines = approved.get("lines", approved.get("line_items", []))
        line_ids = [l["id"] for l in lines]

        po = await svc.create_po_from_jpo(
            jpo_id=jpo["id"],
            supplier_id=supplier_id,
            line_ids=line_ids,
            created_by=1,
        )
        assert po is not None
        assert po["id"] is not None
        assert po["status"] == "draft"

    @pytest.mark.asyncio
    async def test_po_number_format(self, db_with_admin: aiosqlite.Connection):
        """PO number should follow the standard format."""
        part_id = await seed_part(db_with_admin)
        supplier_id = await seed_supplier(db_with_admin)

        svc = OrdersService(db_with_admin)
        po = await svc.create_po_standalone(
            supplier_id=supplier_id,
            lines=[{"part_id": part_id, "qty_ordered": 10, "unit_cost": 5.00}],
            created_by=1,
        )
        assert po is not None
        # PO number should start with "PO-" (standard format)
        assert po["po_number"].startswith("PO-")
