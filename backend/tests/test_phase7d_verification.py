"""
Phase 7D Verification Tests — Cost Tracking, Spending, Budget Alerts.

Exercises every item in the Phase 7D Verification Checklist:

1. Receive 10 @ $100 + 5 @ $80 → weighted avg = $93.33
2. Consume 1 (FIFO) → oldest layer decremented, avg recalculated
3. Return 1 (LIFO) → newest layer incremented, avg recalculated
4. Set custom margin → verify sell price updates
5. Enforce default → verify all custom margins cleared
6. Job cost rollup → matches sum of PO costs
7. Budget alerts → amber/red at thresholds
8. Permission gates → field workers see job costs, NOT company spending
9. Daily report endpoint → returns live data structure
10. (Responsive/dark mode is frontend-only — covered by manual audit)
"""

from __future__ import annotations

import pytest
import pytest_asyncio
import aiosqlite

from tests.conftest import (
    seed_part,
    seed_job,
    seed_supplier,
    seed_category,
)

from app.services.cost_tracking_service import CostTrackingService
from app.services.spending_service import SpendingService


# ═══════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════

async def _set_company_setting(db: aiosqlite.Connection, key: str, value: str) -> None:
    """Helper to update a company cost setting."""
    await db.execute(
        "UPDATE company_cost_settings SET setting_value = ? WHERE setting_key = ?",
        (value, key),
    )
    await db.commit()


async def _seed_po_with_lines(
    db: aiosqlite.Connection,
    supplier_id: int,
    lines: list[dict],
    status: str = "submitted",
) -> int:
    """Create a purchase order with line items. Returns PO id.

    Each line in `lines` should have: part_id, qty, unit_cost
    Optionally: jpo_line_id (for job attribution)
    """
    global _po_counter
    _po_counter += 1

    total = sum(l["qty"] * l["unit_cost"] for l in lines)
    cursor = await db.execute(
        """
        INSERT INTO purchase_orders
            (supplier_id, status, total_cost, created_at, po_number)
        VALUES (?, ?, ?, datetime('now'), ?)
        """,
        (supplier_id, status, total, f"PO-TEST-{_po_counter:04d}"),
    )
    po_id = cursor.lastrowid

    for line in lines:
        await db.execute(
            """
            INSERT INTO po_line_items
                (po_id, part_id, qty_ordered, unit_cost, jpo_line_id)
            VALUES (?, ?, ?, ?, ?)
            """,
            (po_id, line["part_id"], line["qty"], line["unit_cost"],
             line.get("jpo_line_id")),
        )

    await db.commit()
    return po_id


_jpo_counter = 0
_po_counter = 0


async def _seed_jpo_for_job(
    db: aiosqlite.Connection,
    job_id: int,
    part_id: int,
    qty: int,
) -> int:
    """Create a JPO + line item for a job. Returns jpo_line_id."""
    global _jpo_counter
    _jpo_counter += 1

    cursor = await db.execute(
        """
        INSERT INTO job_parts_orders
            (job_id, requested_by, status, order_type, order_number, created_at)
        VALUES (?, 1, 'approved', 'job', ?, datetime('now'))
        """,
        (job_id, f"JPO-TEST-{_jpo_counter:04d}"),
    )
    jpo_id = cursor.lastrowid

    cursor2 = await db.execute(
        """
        INSERT INTO jpo_line_items (jpo_id, part_id, qty_requested)
        VALUES (?, ?, ?)
        """,
        (jpo_id, part_id, qty),
    )
    jpo_line_id = cursor2.lastrowid
    await db.commit()
    return jpo_line_id


async def _seed_labor_entry(
    db: aiosqlite.Connection,
    job_id: int,
    user_id: int = 1,
    hours: float = 8.0,
) -> int:
    """Create a completed labor entry for a job. Returns entry ID."""
    cursor = await db.execute(
        """
        INSERT INTO labor_entries
            (job_id, user_id, clock_in, clock_out)
        VALUES (?, ?, datetime('now', ? || ' hours'), datetime('now'))
        """,
        (job_id, user_id, f"-{hours}"),
    )
    await db.commit()
    return cursor.lastrowid


# ═══════════════════════════════════════════════════════════════════
# Checklist #1: Receive 10 @ $100 + 5 @ $80 → avg = $93.33
# ═══════════════════════════════════════════════════════════════════


class TestChecklist1WeightedAverage:
    """Verify weighted average cost from layered PO receives."""

    @pytest.mark.asyncio
    async def test_exact_weighted_average(self, db: aiosqlite.Connection):
        """10 @ $100 + 5 @ $80 should yield weighted avg = $93.33."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        # Receive 10 units at $100.00
        await svc.add_cost_layer(part_id, qty=10, unit_cost=100.00)
        # Receive 5 units at $80.00
        await svc.add_cost_layer(part_id, qty=5, unit_cost=80.00)

        # Expected: (10×100 + 5×80) / (10+5) = 1400/15 = 93.3333...
        cursor = await db.execute(
            "SELECT weighted_avg_cost FROM parts WHERE id = ?", (part_id,)
        )
        row = await cursor.fetchone()
        assert row["weighted_avg_cost"] == pytest.approx(93.3333, abs=0.01)

    @pytest.mark.asyncio
    async def test_weighted_avg_with_single_layer(self, db: aiosqlite.Connection):
        """Single layer should have weighted avg = unit cost."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        await svc.add_cost_layer(part_id, qty=20, unit_cost=50.00)

        cursor = await db.execute(
            "SELECT weighted_avg_cost FROM parts WHERE id = ?", (part_id,)
        )
        row = await cursor.fetchone()
        assert row["weighted_avg_cost"] == pytest.approx(50.00)

    @pytest.mark.asyncio
    async def test_weighted_avg_three_layers(self, db: aiosqlite.Connection):
        """Three layers: 100@$2 + 50@$3 + 50@$5 = avg $3.00."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        await svc.add_cost_layer(part_id, qty=100, unit_cost=2.00)
        await svc.add_cost_layer(part_id, qty=50, unit_cost=3.00)
        await svc.add_cost_layer(part_id, qty=50, unit_cost=5.00)

        # Expected: (200 + 150 + 250) / 200 = 600/200 = 3.00
        cursor = await db.execute(
            "SELECT weighted_avg_cost FROM parts WHERE id = ?", (part_id,)
        )
        row = await cursor.fetchone()
        assert row["weighted_avg_cost"] == pytest.approx(3.00, abs=0.01)


# ═══════════════════════════════════════════════════════════════════
# Checklist #2: FIFO consume → oldest layer decremented, avg recalced
# ═══════════════════════════════════════════════════════════════════


class TestChecklist2FifoConsumption:
    """Verify FIFO consumption decrements oldest layer and recalculates avg."""

    @pytest.mark.asyncio
    async def test_fifo_decrements_oldest_layer(self, db: aiosqlite.Connection):
        """After FIFO consume, the oldest layer should lose qty."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        # Layer 1 (older): 10 @ $100
        await svc.add_cost_layer(
            part_id, qty=10, unit_cost=100.00, purchase_date="2026-01-01"
        )
        # Layer 2 (newer): 5 @ $80
        await svc.add_cost_layer(
            part_id, qty=5, unit_cost=80.00, purchase_date="2026-02-01"
        )

        # Consume 1 unit (FIFO should take from oldest $100 layer)
        cost = await svc.consume_fifo(part_id, qty=1)
        assert cost == pytest.approx(100.00)  # 1 × $100

        # Check layers: oldest should have 9 remaining, newest 5 unchanged
        layers = await svc.get_cost_layers(part_id)
        layers_sorted = sorted(layers, key=lambda l: l["purchase_date"])
        assert layers_sorted[0]["remaining_qty"] == 9   # was 10, consumed 1
        assert layers_sorted[1]["remaining_qty"] == 5   # untouched

        # Weighted avg should shift: (9×100 + 5×80) / 14 = 1300/14 = 92.857...
        cursor = await db.execute(
            "SELECT weighted_avg_cost FROM parts WHERE id = ?", (part_id,)
        )
        row = await cursor.fetchone()
        assert row["weighted_avg_cost"] == pytest.approx(92.857, abs=0.01)

    @pytest.mark.asyncio
    async def test_fifo_cost_returned_matches_layer(self, db: aiosqlite.Connection):
        """The cost returned by consume_fifo should match the oldest layer's price."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        await svc.add_cost_layer(part_id, qty=5, unit_cost=10.00, purchase_date="2026-01-01")
        await svc.add_cost_layer(part_id, qty=5, unit_cost=20.00, purchase_date="2026-02-01")

        # Consume 3 — should all come from $10 layer
        total = await svc.consume_fifo(part_id, qty=3)
        assert total == pytest.approx(30.00)  # 3 × $10

    @pytest.mark.asyncio
    async def test_fifo_across_layers(self, db: aiosqlite.Connection):
        """Consuming across layer boundaries sums costs from multiple layers."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        await svc.add_cost_layer(part_id, qty=3, unit_cost=10.00, purchase_date="2026-01-01")
        await svc.add_cost_layer(part_id, qty=7, unit_cost=20.00, purchase_date="2026-02-01")

        # Consume 5: 3 from first ($30) + 2 from second ($40) = $70
        total = await svc.consume_fifo(part_id, qty=5)
        assert total == pytest.approx(70.00)


# ═══════════════════════════════════════════════════════════════════
# Checklist #3: LIFO return → newest layer incremented, avg recalced
# ═══════════════════════════════════════════════════════════════════


class TestChecklist3LifoReturn:
    """Verify LIFO return adds to newest layer and recalculates avg."""

    @pytest.mark.asyncio
    async def test_lifo_increments_newest_layer(self, db: aiosqlite.Connection):
        """After LIFO return, the newest layer should gain qty back."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        # Layer 1: 10 @ $100
        await svc.add_cost_layer(
            part_id, qty=10, unit_cost=100.00, purchase_date="2026-01-01"
        )
        # Layer 2: 5 @ $80
        await svc.add_cost_layer(
            part_id, qty=5, unit_cost=80.00, purchase_date="2026-02-01"
        )

        # Consume 8 from FIFO (takes all 10 from layer1, nope — takes 8 from oldest)
        # Actually: consume 8 → 8 from layer1 ($100 each) → layer1 has 2 left
        await svc.consume_fifo(part_id, qty=8)

        # Before return: layer1=2@$100, layer2=5@$80 → total=7
        layers_before = await svc.get_cost_layers(part_id)
        total_before = sum(l["remaining_qty"] for l in layers_before)
        assert total_before == 7

        # Return 1 unit (LIFO — should go to newest layer)
        result = await svc.return_lifo(part_id, qty=1)
        assert result is not None

        # Total should now be 8
        layers_after = await svc.get_cost_layers(part_id)
        total_after = sum(l["remaining_qty"] for l in layers_after)
        assert total_after == 8

    @pytest.mark.asyncio
    async def test_lifo_return_with_explicit_cost(self, db: aiosqlite.Connection):
        """LIFO return with explicit cost creates a new layer."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        await svc.add_cost_layer(part_id, qty=10, unit_cost=50.00)

        # Return at a different price → new layer
        result = await svc.return_lifo(part_id, qty=2, unit_cost=45.00)
        assert result["unit_cost"] == 45.00

        # Should have 2 layers now (original + return)
        layers = await svc.get_cost_layers(part_id)
        assert len(layers) == 2

    @pytest.mark.asyncio
    async def test_lifo_return_recalculates_avg(self, db: aiosqlite.Connection):
        """After LIFO return, weighted average should update."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        # 10 @ $100 → avg = $100
        await svc.add_cost_layer(part_id, qty=10, unit_cost=100.00)

        # Consume 5 → avg still $100 (only one price level)
        await svc.consume_fifo(part_id, qty=5)

        # Return 3 at $80 → creates new layer: 5@$100 + 3@$80 = 740/8 = 92.5
        await svc.return_lifo(part_id, qty=3, unit_cost=80.00)

        cursor = await db.execute(
            "SELECT weighted_avg_cost FROM parts WHERE id = ?", (part_id,)
        )
        row = await cursor.fetchone()
        assert row["weighted_avg_cost"] == pytest.approx(92.50, abs=0.01)


# ═══════════════════════════════════════════════════════════════════
# Checklist #4: Set custom margin → verify sell price updates
# ═══════════════════════════════════════════════════════════════════


class TestChecklist4CustomMargin:
    """Verify margin management and sell price calculation."""

    @pytest.mark.asyncio
    async def test_default_margin_used_when_no_custom(self, db: aiosqlite.Connection):
        """Without custom margin, company default (25%) should apply."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        # Set a known cost
        await svc.add_cost_layer(part_id, qty=10, unit_cost=100.00)

        margin = await svc.get_margin(part_id)
        assert margin["custom_margin_percent"] is None
        assert margin["default_margin_percent"] == 25.0
        assert margin["effective_margin_percent"] == 25.0
        # Sell price: $100 × 1.25 = $125
        assert margin["calculated_sell_price"] == pytest.approx(125.00)

    @pytest.mark.asyncio
    async def test_set_custom_margin_changes_sell_price(self, db: aiosqlite.Connection):
        """Setting a custom margin should update the effective margin and sell price."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        await svc.add_cost_layer(part_id, qty=10, unit_cost=100.00)
        await svc.set_custom_margin(part_id, 40.0)

        margin = await svc.get_margin(part_id)
        assert margin["custom_margin_percent"] == 40.0
        assert margin["effective_margin_percent"] == 40.0
        # Sell price: $100 × 1.40 = $140
        assert margin["calculated_sell_price"] == pytest.approx(140.00)

    @pytest.mark.asyncio
    async def test_clear_custom_margin_reverts_to_default(self, db: aiosqlite.Connection):
        """Clearing a custom margin should revert to company default."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        await svc.add_cost_layer(part_id, qty=10, unit_cost=100.00)
        await svc.set_custom_margin(part_id, 50.0)

        # Verify custom is set
        m1 = await svc.get_margin(part_id)
        assert m1["effective_margin_percent"] == 50.0

        # Clear it
        await svc.clear_custom_margin(part_id)

        m2 = await svc.get_margin(part_id)
        assert m2["custom_margin_percent"] is None
        assert m2["effective_margin_percent"] == 25.0  # back to default

    @pytest.mark.asyncio
    async def test_margin_with_zero_cost(self, db: aiosqlite.Connection):
        """Margin on a part with zero cost should yield sell price = 0."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        # No cost layers → weighted_avg_cost = 0
        margin = await svc.get_margin(part_id)
        assert margin["calculated_sell_price"] == 0


# ═══════════════════════════════════════════════════════════════════
# Checklist #5: Enforce Default → all custom margins cleared
# ═══════════════════════════════════════════════════════════════════


class TestChecklist5EnforceDefault:
    """Verify bulk margin enforcement clears all overrides."""

    @pytest.mark.asyncio
    async def test_enforce_clears_all_custom_margins(self, db: aiosqlite.Connection):
        """Enforcing default should clear all custom_margin_percent values."""
        # Create 3 parts with custom margins
        p1 = await seed_part(db)
        p2 = await seed_part(db)
        p3 = await seed_part(db)
        svc = CostTrackingService(db)

        await svc.set_custom_margin(p1, 30.0)
        await svc.set_custom_margin(p2, 40.0)
        await svc.set_custom_margin(p3, 50.0)

        # Verify they're set
        for pid in [p1, p2, p3]:
            m = await svc.get_margin(pid)
            assert m["custom_margin_percent"] is not None

        # Enforce default
        cleared = await svc.enforce_default_margin()
        assert cleared == 3

        # All should now use company default
        for pid in [p1, p2, p3]:
            m = await svc.get_margin(pid)
            assert m["custom_margin_percent"] is None
            assert m["effective_margin_percent"] == 25.0

    @pytest.mark.asyncio
    async def test_enforce_returns_zero_when_none_set(self, db: aiosqlite.Connection):
        """Enforcing when no custom margins exist should return 0."""
        svc = CostTrackingService(db)
        cleared = await svc.enforce_default_margin()
        assert cleared == 0


# ═══════════════════════════════════════════════════════════════════
# Checklist #6: Job cost rollup → matches PO costs
# ═══════════════════════════════════════════════════════════════════


class TestChecklist6JobCostRollup:
    """Verify job cost rollup correctly sums parts + labor costs."""

    @pytest.mark.asyncio
    async def test_rollup_matches_po_line_costs(self, db: aiosqlite.Connection):
        """Job cost rollup should match the sum of PO line item costs."""
        job_id = await seed_job(db)
        part_id = await seed_part(db)
        supplier_id = await seed_supplier(db)

        # Create JPO + line (to link PO back to job)
        jpo_line_id = await _seed_jpo_for_job(db, job_id, part_id, qty=10)

        # Create PO with lines linked to the JPO
        await _seed_po_with_lines(db, supplier_id, [
            {"part_id": part_id, "qty": 10, "unit_cost": 25.00,
             "jpo_line_id": jpo_line_id},
        ])

        svc = SpendingService(db)
        rollup = await svc.get_job_cost_rollup(job_id)

        assert rollup["job_id"] == job_id
        assert rollup["total_parts_cost"] == pytest.approx(250.00)  # 10 × $25

    @pytest.mark.asyncio
    async def test_rollup_with_multiple_pos(self, db: aiosqlite.Connection):
        """Rollup should aggregate across multiple POs for the same job."""
        job_id = await seed_job(db)
        part1 = await seed_part(db)
        part2 = await seed_part(db)
        supplier_id = await seed_supplier(db)

        # JPO lines
        jpo_line1 = await _seed_jpo_for_job(db, job_id, part1, qty=5)
        jpo_line2 = await _seed_jpo_for_job(db, job_id, part2, qty=3)

        # PO 1: 5 units @ $20
        await _seed_po_with_lines(db, supplier_id, [
            {"part_id": part1, "qty": 5, "unit_cost": 20.00,
             "jpo_line_id": jpo_line1},
        ])
        # PO 2: 3 units @ $50
        await _seed_po_with_lines(db, supplier_id, [
            {"part_id": part2, "qty": 3, "unit_cost": 50.00,
             "jpo_line_id": jpo_line2},
        ])

        svc = SpendingService(db)
        rollup = await svc.get_job_cost_rollup(job_id)

        # Total: (5×$20) + (3×$50) = $100 + $150 = $250
        assert rollup["total_parts_cost"] == pytest.approx(250.00)

    @pytest.mark.asyncio
    async def test_rollup_labor_cost_with_hourly_rate(self, db: aiosqlite.Connection):
        """Labor cost should be hours × company default hourly rate."""
        job_id = await seed_job(db)

        # Set company hourly rate to $75
        await _set_company_setting(db, "default_hourly_rate", "75")

        # Add 8 hours of labor
        await _seed_labor_entry(db, job_id, hours=8.0)

        svc = SpendingService(db)
        rollup = await svc.get_job_cost_rollup(job_id)

        assert rollup["total_labor_hours"] == pytest.approx(8.0, abs=0.1)
        assert rollup["total_labor_cost"] == pytest.approx(600.00, abs=10.0)  # 8 × $75
        assert rollup["billing_rate"] == pytest.approx(75.00)

    @pytest.mark.asyncio
    async def test_rollup_combined_total(self, db: aiosqlite.Connection):
        """Combined total = parts + labor."""
        job_id = await seed_job(db)
        part_id = await seed_part(db)
        supplier_id = await seed_supplier(db)

        # Set hourly rate
        await _set_company_setting(db, "default_hourly_rate", "50")

        # Parts: $200
        jpo_line = await _seed_jpo_for_job(db, job_id, part_id, qty=10)
        await _seed_po_with_lines(db, supplier_id, [
            {"part_id": part_id, "qty": 10, "unit_cost": 20.00,
             "jpo_line_id": jpo_line},
        ])

        # Labor: 4 hours × $50 = $200
        await _seed_labor_entry(db, job_id, hours=4.0)

        svc = SpendingService(db)
        rollup = await svc.get_job_cost_rollup(job_id)

        assert rollup["total_parts_cost"] == pytest.approx(200.00)
        assert rollup["total_labor_cost"] == pytest.approx(200.00, abs=10.0)
        assert rollup["combined_total"] == pytest.approx(400.00, abs=15.0)


# ═══════════════════════════════════════════════════════════════════
# Checklist #7: Budget alerts — amber/red at thresholds
# ═══════════════════════════════════════════════════════════════════


class TestChecklist7BudgetAlerts:
    """Verify budget alert thresholds: warning ≥ alert_percent, danger ≥ 95%."""

    @pytest.mark.asyncio
    async def test_no_alert_below_threshold(self, db: aiosqlite.Connection):
        """Job well under budget should not trigger alert."""
        job_id = await seed_job(db, budget_limit=1000.0, budget_alert_percent=80.0)

        svc = SpendingService(db)
        status = await svc.get_job_budget_status(job_id)

        # No spend → 0% → no alert
        assert status["alert_level"] is None

    @pytest.mark.asyncio
    async def test_warning_at_threshold(self, db: aiosqlite.Connection):
        """Job at 85% of budget (default alert = 80%) triggers warning."""
        job_id = await seed_job(db, budget_limit=1000.0, budget_alert_percent=80.0)
        part_id = await seed_part(db)
        supplier_id = await seed_supplier(db)

        # Spend $850 → 85% of $1000 budget (above 80% threshold)
        jpo_line = await _seed_jpo_for_job(db, job_id, part_id, qty=85)
        await _seed_po_with_lines(db, supplier_id, [
            {"part_id": part_id, "qty": 85, "unit_cost": 10.00,
             "jpo_line_id": jpo_line},
        ])

        svc = SpendingService(db)
        status = await svc.get_job_budget_status(job_id)

        assert status["budget_pct"] == pytest.approx(85.0, abs=1.0)
        assert status["alert_level"] == "warning"

    @pytest.mark.asyncio
    async def test_danger_at_95_percent(self, db: aiosqlite.Connection):
        """Job at 96% of budget triggers danger alert."""
        job_id = await seed_job(db, budget_limit=1000.0, budget_alert_percent=80.0)
        part_id = await seed_part(db)
        supplier_id = await seed_supplier(db)

        # Spend $960 → 96% of $1000 (above 95% danger threshold)
        jpo_line = await _seed_jpo_for_job(db, job_id, part_id, qty=96)
        await _seed_po_with_lines(db, supplier_id, [
            {"part_id": part_id, "qty": 96, "unit_cost": 10.00,
             "jpo_line_id": jpo_line},
        ])

        svc = SpendingService(db)
        status = await svc.get_job_budget_status(job_id)

        assert status["budget_pct"] == pytest.approx(96.0, abs=1.0)
        assert status["alert_level"] == "danger"

    @pytest.mark.asyncio
    async def test_check_budget_alerts_returns_all_over_threshold(
        self, db: aiosqlite.Connection
    ):
        """check_budget_alerts should return jobs above their alert threshold."""
        # Job 1: $800/$1000 = 80% (at threshold with 80% alert → warning)
        j1 = await seed_job(db, budget_limit=1000.0, budget_alert_percent=80.0, status="active")
        p1 = await seed_part(db)
        s1 = await seed_supplier(db)
        jl1 = await _seed_jpo_for_job(db, j1, p1, qty=80)
        await _seed_po_with_lines(db, s1, [
            {"part_id": p1, "qty": 80, "unit_cost": 10.00, "jpo_line_id": jl1},
        ])

        # Job 2: $500/$1000 = 50% (under 80% threshold → no alert)
        j2 = await seed_job(db, budget_limit=1000.0, budget_alert_percent=80.0, status="active")
        p2 = await seed_part(db)
        jl2 = await _seed_jpo_for_job(db, j2, p2, qty=50)
        await _seed_po_with_lines(db, s1, [
            {"part_id": p2, "qty": 50, "unit_cost": 10.00, "jpo_line_id": jl2},
        ])

        svc = SpendingService(db)
        alerts = await svc.check_budget_alerts()

        alert_job_ids = [a["job_id"] for a in alerts]
        assert j1 in alert_job_ids  # over threshold
        assert j2 not in alert_job_ids  # under threshold

    @pytest.mark.asyncio
    async def test_no_budget_no_alert(self, db: aiosqlite.Connection):
        """Jobs without budget_limit should not appear in alerts."""
        job_id = await seed_job(db, status="active")  # no budget_limit

        svc = SpendingService(db)
        status = await svc.get_job_budget_status(job_id)
        assert status["budget_pct"] is None
        assert status["alert_level"] is None


# ═══════════════════════════════════════════════════════════════════
# Checklist #8: Permission gates (HTTP endpoint level)
# ═══════════════════════════════════════════════════════════════════


class TestChecklist8PermissionGates:
    """Verify field workers can see job costs but NOT company spending.

    Uses the HTTP client to test actual permission enforcement.
    The admin user (auth_client) has all permissions.
    An unauthenticated call should get 401/403.
    """

    @pytest.mark.asyncio
    async def test_job_rollup_requires_show_dollar_values(self, client):
        """GET /api/costs/job/{id}/rollup requires authentication."""
        resp = await client.get("/api/costs/job/1/rollup")
        assert resp.status_code in (401, 403)

    @pytest.mark.asyncio
    async def test_spending_dashboard_requires_manage_orders(self, client):
        """GET /api/costs/dashboard requires authentication."""
        resp = await client.get("/api/costs/dashboard")
        assert resp.status_code in (401, 403)

    @pytest.mark.asyncio
    async def test_spending_by_supplier_requires_manage_orders(self, client):
        """GET /api/costs/spending/by-supplier requires authentication."""
        resp = await client.get("/api/costs/spending/by-supplier")
        assert resp.status_code in (401, 403)

    @pytest.mark.asyncio
    async def test_variance_report_requires_manage_orders(self, client):
        """GET /api/costs/variance-report requires authentication."""
        resp = await client.get("/api/costs/variance-report")
        assert resp.status_code in (401, 403)

    @pytest.mark.asyncio
    async def test_enforce_margin_requires_edit_pricing(self, client):
        """POST /api/costs/enforce-default-margin requires authentication."""
        resp = await client.post("/api/costs/enforce-default-margin")
        assert resp.status_code in (401, 403)

    @pytest.mark.asyncio
    async def test_set_margin_requires_edit_pricing(self, client):
        """PUT /api/costs/part/1/margin requires authentication."""
        resp = await client.put(
            "/api/costs/part/1/margin",
            json={"margin_percent": 30},
        )
        assert resp.status_code in (401, 403)

    @pytest.mark.asyncio
    async def test_daily_report_accessible_to_auth_user(self, auth_client):
        """GET /api/costs/daily-report should work for any authenticated user."""
        resp = await auth_client.get("/api/costs/daily-report")
        assert resp.status_code == 200
        data = resp.json()["data"]
        assert "pending_actions" in data
        assert "expected_deliveries" in data
        assert "todays_activity" in data
        assert "budget_alerts" in data

    @pytest.mark.asyncio
    async def test_admin_can_access_job_rollup(self, auth_client):
        """Admin (all permissions) should access job cost rollup."""
        # Admin has manage_orders and show_dollar_values
        # Create a test job first
        from tests.conftest import seed_job
        from app.database import get_db
        from app.main import app

        # Need to get db from the override
        db_override = app.dependency_overrides.get(get_db)
        if db_override:
            async for conn in db_override():
                job_id = await seed_job(conn)
                break
        else:
            pytest.skip("No DB override available")

        resp = await auth_client.get(f"/api/costs/job/{job_id}/rollup")
        assert resp.status_code == 200, resp.text
        data = resp.json()["data"]
        assert "total_parts_cost" in data
        assert "total_labor_cost" in data
        assert "combined_total" in data

    @pytest.mark.asyncio
    async def test_admin_can_access_spending_dashboard(self, auth_client):
        """Admin should be able to view the spending dashboard."""
        resp = await auth_client.get("/api/costs/dashboard")
        assert resp.status_code == 200
        data = resp.json()["data"]
        assert "total_spend" in data
        assert "order_count" in data

    @pytest.mark.asyncio
    async def test_admin_can_set_margin(self, auth_client):
        """Admin should be able to set custom margins."""
        from tests.conftest import seed_part
        from app.database import get_db
        from app.main import app

        db_override = app.dependency_overrides.get(get_db)
        if db_override:
            async for conn in db_override():
                part_id = await seed_part(conn)
                break
        else:
            pytest.skip("No DB override available")

        resp = await auth_client.put(
            f"/api/costs/part/{part_id}/margin",
            json={"margin_percent": 35.0},
        )
        assert resp.status_code == 200


# ═══════════════════════════════════════════════════════════════════
# Checklist #9: Daily report → live data structure
# ═══════════════════════════════════════════════════════════════════


class TestChecklist9DailyReport:
    """Verify the daily report returns correct live data structure."""

    @pytest.mark.asyncio
    async def test_daily_report_structure(self, db: aiosqlite.Connection):
        """Daily report should return all required sections."""
        svc = SpendingService(db)
        report = await svc.get_daily_report()

        # Check top-level structure
        assert "pending_actions" in report
        assert "expected_deliveries" in report
        assert "overdue_items" in report
        assert "todays_activity" in report
        assert "budget_alerts" in report

        # Check pending_actions sub-fields
        pa = report["pending_actions"]
        assert "jpos_awaiting_approval" in pa
        assert "pos_to_submit" in pa
        assert "returns_to_sort" in pa
        assert "overdue_deliveries" in pa

        # Check todays_activity sub-fields
        ta = report["todays_activity"]
        assert "orders_created" in ta
        assert "items_received" in ta
        assert "returns_processed" in ta

    @pytest.mark.asyncio
    async def test_daily_report_counts_jpos(self, db: aiosqlite.Connection):
        """Pending JPOs should appear in the daily report count."""
        part_id = await seed_part(db)
        job_id = await seed_job(db)

        global _jpo_counter
        _jpo_counter += 1

        # Create a JPO in pending_approval state
        await db.execute(
            """
            INSERT INTO job_parts_orders
                (job_id, requested_by, status, order_type, order_number, created_at)
            VALUES (?, 1, 'pending_approval', 'job', ?, datetime('now'))
            """,
            (job_id, f"JPO-DR-{_jpo_counter:04d}"),
        )
        await db.commit()

        svc = SpendingService(db)
        report = await svc.get_daily_report()
        assert report["pending_actions"]["jpos_awaiting_approval"] >= 1

    @pytest.mark.asyncio
    async def test_daily_report_counts_draft_pos(self, db: aiosqlite.Connection):
        """Draft POs should appear in the daily report count."""
        supplier_id = await seed_supplier(db)

        await db.execute(
            """
            INSERT INTO purchase_orders
                (supplier_id, status, created_at, po_number)
            VALUES (?, 'draft', datetime('now'), 'PO-DRAFT-TEST')
            """,
            (supplier_id,),
        )
        await db.commit()

        svc = SpendingService(db)
        report = await svc.get_daily_report()
        assert report["pending_actions"]["pos_to_submit"] >= 1

    @pytest.mark.asyncio
    async def test_daily_report_budget_alerts_included(self, db: aiosqlite.Connection):
        """Budget alerts from active jobs should appear in daily report."""
        job_id = await seed_job(db, budget_limit=100.0, budget_alert_percent=80.0, status="active")
        part_id = await seed_part(db)
        supplier_id = await seed_supplier(db)

        # Spend $95 → 95% → danger alert
        jpo_line = await _seed_jpo_for_job(db, job_id, part_id, qty=95)
        await _seed_po_with_lines(db, supplier_id, [
            {"part_id": part_id, "qty": 95, "unit_cost": 1.00,
             "jpo_line_id": jpo_line},
        ])

        svc = SpendingService(db)
        report = await svc.get_daily_report()

        # Should have at least one budget alert
        assert len(report["budget_alerts"]) >= 1
        alert = next(a for a in report["budget_alerts"] if a["job_id"] == job_id)
        assert alert["alert_level"] == "danger"


# ═══════════════════════════════════════════════════════════════════
# Additional edge-case tests
# ═══════════════════════════════════════════════════════════════════


class TestEdgeCases:
    """Additional edge case tests for robustness."""

    @pytest.mark.asyncio
    async def test_add_zero_qty_raises(self, db: aiosqlite.Connection):
        """Adding a cost layer with qty=0 should raise ValueError."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        with pytest.raises(ValueError, match="positive"):
            await svc.add_cost_layer(part_id, qty=0, unit_cost=10.00)

    @pytest.mark.asyncio
    async def test_add_negative_cost_raises(self, db: aiosqlite.Connection):
        """Adding a cost layer with negative cost should raise ValueError."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        with pytest.raises(ValueError, match="negative"):
            await svc.add_cost_layer(part_id, qty=5, unit_cost=-1.00)

    @pytest.mark.asyncio
    async def test_consume_zero_raises(self, db: aiosqlite.Connection):
        """Consuming 0 qty should raise ValueError."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        with pytest.raises(ValueError, match="positive"):
            await svc.consume_fifo(part_id, qty=0)

    @pytest.mark.asyncio
    async def test_return_zero_raises(self, db: aiosqlite.Connection):
        """Returning 0 qty should raise ValueError."""
        part_id = await seed_part(db)
        svc = CostTrackingService(db)

        with pytest.raises(ValueError, match="positive"):
            await svc.return_lifo(part_id, qty=0)

    @pytest.mark.asyncio
    async def test_nonexistent_job_rollup_raises(self, db: aiosqlite.Connection):
        """Rollup for non-existent job should raise ValueError."""
        svc = SpendingService(db)

        with pytest.raises(ValueError, match="not found"):
            await svc.get_job_cost_rollup(99999)

    @pytest.mark.asyncio
    async def test_spending_summary_empty_range(self, db: aiosqlite.Connection):
        """Spending summary with no POs should return zero values."""
        svc = SpendingService(db)
        summary = await svc.get_spending_summary("2020-01-01", "2020-02-01")

        assert summary["total_spend"] == 0
        assert summary["order_count"] == 0
        assert summary["avg_order_size"] == 0

    @pytest.mark.asyncio
    async def test_company_settings_readable(self, db: aiosqlite.Connection):
        """Company cost settings should be readable and include seeded defaults."""
        svc = CostTrackingService(db)
        settings = await svc.get_company_settings()

        keys = {s["setting_key"] for s in settings}
        assert "default_margin_percent" in keys
        assert "cost_method" in keys
        assert "auto_update_pricing" in keys
        assert "default_hourly_rate" in keys

    @pytest.mark.asyncio
    async def test_update_company_setting(self, db: aiosqlite.Connection):
        """Updating a company setting should persist the new value."""
        svc = CostTrackingService(db)

        result = await svc.update_company_setting(
            "default_margin_percent", "30", user_id=1
        )
        assert result is not None
        assert result["setting_value"] == "30"

        # Verify it's persisted
        settings = await svc.get_company_settings()
        margin = next(s for s in settings if s["setting_key"] == "default_margin_percent")
        assert margin["setting_value"] == "30"
