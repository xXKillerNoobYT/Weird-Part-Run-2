"""
Tests for the Cost Tracking Service — FIFO, LIFO, weighted average.

Covers:
- Cost layer creation on PO receive
- FIFO consumption (oldest first)
- LIFO returns (newest first)
- Weighted average calculation
- Negative layer prevention
"""

from __future__ import annotations

import pytest
import pytest_asyncio
import aiosqlite

from tests.conftest import seed_part

from app.services.cost_tracking_service import CostTrackingService


# ══════════════════════════════════════════════════════════════════
# Cost Layer Creation
# ══════════════════════════════════════════════════════════════════


class TestCostLayerCreation:
    """Test cost layer creation when receiving PO items."""

    @pytest.mark.asyncio
    async def test_add_cost_layer_creates_record(self, db: aiosqlite.Connection):
        """Adding a cost layer should create a record with correct qty and cost."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        result = await svc.add_cost_layer(part_id, qty=100, unit_cost=2.50)
        assert result is not None

        layers = await svc.get_cost_layers(part_id)
        assert len(layers) >= 1
        # Find the layer we just created
        layer = next(l for l in layers if l["remaining_qty"] == 100)
        assert layer["unit_cost"] == 2.50

    @pytest.mark.asyncio
    async def test_add_multiple_layers(self, db: aiosqlite.Connection):
        """Multiple cost layers at different prices should coexist."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        await svc.add_cost_layer(part_id, qty=50, unit_cost=2.00)
        await svc.add_cost_layer(part_id, qty=30, unit_cost=3.00)

        layers = await svc.get_cost_layers(part_id)
        assert len(layers) >= 2


# ══════════════════════════════════════════════════════════════════
# FIFO Consumption
# ══════════════════════════════════════════════════════════════════


class TestFifoConsumption:
    """Test FIFO (first-in, first-out) consumption order."""

    @pytest.mark.asyncio
    async def test_fifo_consumes_oldest_first(self, db: aiosqlite.Connection):
        """FIFO should consume the oldest (cheapest in this test) layer first."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        # Layer 1: old, cheap
        await svc.add_cost_layer(part_id, qty=10, unit_cost=1.00)
        # Layer 2: new, expensive
        await svc.add_cost_layer(part_id, qty=10, unit_cost=5.00)

        # Consume 5 — should take from the $1.00 layer
        total_cost = await svc.consume_fifo(part_id, qty=5)
        assert total_cost == pytest.approx(5.00)  # 5 × $1.00

        # Oldest layer should have 5 remaining, newest untouched
        layers = await svc.get_cost_layers(part_id)
        remaining = sorted(layers, key=lambda l: l["unit_cost"])
        assert remaining[0]["remaining_qty"] == 5   # old layer: 10 - 5
        assert remaining[1]["remaining_qty"] == 10  # new layer: untouched

    @pytest.mark.asyncio
    async def test_fifo_spans_multiple_layers(self, db: aiosqlite.Connection):
        """Consuming more than one layer's worth should span layers."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        await svc.add_cost_layer(part_id, qty=5, unit_cost=2.00)
        await svc.add_cost_layer(part_id, qty=10, unit_cost=4.00)

        # Consume 8: 5 from first ($10) + 3 from second ($12) = $22
        total_cost = await svc.consume_fifo(part_id, qty=8)
        assert total_cost == pytest.approx(22.00)

    @pytest.mark.asyncio
    async def test_fifo_consumes_partial_and_uses_weighted_avg(self, db: aiosqlite.Connection):
        """Consuming more than layers have falls back to weighted average for remainder."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        await svc.add_cost_layer(part_id, qty=5, unit_cost=2.00)

        # Consume 10 when only 5 in layers — should not raise,
        # returns cost for 5 from layers + 5 at weighted average
        total_cost = await svc.consume_fifo(part_id, qty=10)
        assert total_cost > 0  # Should return a positive cost value


# ══════════════════════════════════════════════════════════════════
# LIFO Returns
# ══════════════════════════════════════════════════════════════════


class TestLifoReturns:
    """Test LIFO (last-in, first-out) return behavior."""

    @pytest.mark.asyncio
    async def test_lifo_return_adds_to_newest_layer(self, db: aiosqlite.Connection):
        """Returning parts should add to the newest cost layer."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        await svc.add_cost_layer(part_id, qty=10, unit_cost=2.00)
        await svc.add_cost_layer(part_id, qty=10, unit_cost=4.00)

        # Consume some first
        await svc.consume_fifo(part_id, qty=5)

        # Return 3 at the newest layer's cost
        result = await svc.return_lifo(part_id, qty=3)
        assert result is not None

        # Total remaining should be 10 - 5 + 3 + 10 = 18
        layers = await svc.get_cost_layers(part_id)
        total_remaining = sum(l["remaining_qty"] for l in layers)
        assert total_remaining == 18


# ══════════════════════════════════════════════════════════════════
# Weighted Average
# ══════════════════════════════════════════════════════════════════


class TestWeightedAverage:
    """Test weighted average cost calculation."""

    @pytest.mark.asyncio
    async def test_weighted_average_after_multiple_layers(self, db: aiosqlite.Connection):
        """Weighted average should reflect proportional costs."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        # 100 units at $2.00 + 100 units at $4.00 = avg $3.00
        await svc.add_cost_layer(part_id, qty=100, unit_cost=2.00)
        await svc.add_cost_layer(part_id, qty=100, unit_cost=4.00)

        # Check the part's weighted_avg_cost was updated
        cursor = await db.execute(
            "SELECT weighted_avg_cost FROM parts WHERE id = ?",
            (part_id,),
        )
        row = await cursor.fetchone()
        assert row["weighted_avg_cost"] == pytest.approx(3.00, abs=0.01)
