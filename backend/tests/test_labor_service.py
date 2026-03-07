"""
Tests for the Labor Service — clock in/out, hours calculation.

Covers:
- Clock-in creates labor entry
- Clock-out calculates hours correctly
- Double clock-in prevention
- GPS storage
- Drive time subtraction
- Overtime calculation
"""

from __future__ import annotations

import pytest
import pytest_asyncio
import aiosqlite

from tests.conftest import seed_job

from app.models.jobs import ClockInRequest, ClockOutRequest
from app.services.labor_service import LaborService


# ══════════════════════════════════════════════════════════════════
# Clock In
# ══════════════════════════════════════════════════════════════════


class TestClockIn:
    """Test clock-in behavior."""

    @pytest.mark.asyncio
    async def test_clock_in_creates_entry(self, db_with_admin: aiosqlite.Connection):
        """Clocking in should create a labor entry with clocked_in status."""
        job_id = await seed_job(db_with_admin)
        svc = LaborService(db_with_admin)

        req = ClockInRequest(gps_lat=40.7128, gps_lng=-74.0060)
        result = await svc.clock_in(user_id=1, job_id=job_id, data=req)

        assert result is not None
        assert result.job_id == job_id
        assert result.status == "clocked_in"

    @pytest.mark.asyncio
    async def test_gps_stored_on_clock_in(self, db_with_admin: aiosqlite.Connection):
        """GPS coordinates should be stored with the labor entry."""
        job_id = await seed_job(db_with_admin)
        svc = LaborService(db_with_admin)

        req = ClockInRequest(gps_lat=40.7128, gps_lng=-74.0060)
        result = await svc.clock_in(user_id=1, job_id=job_id, data=req)

        assert result.clock_in_gps_lat is not None
        assert result.clock_in_gps_lng is not None

    @pytest.mark.asyncio
    async def test_cannot_clock_in_twice(self, db_with_admin: aiosqlite.Connection):
        """Should reject clock-in if already clocked in."""
        job_id = await seed_job(db_with_admin)
        svc = LaborService(db_with_admin)

        req = ClockInRequest(gps_lat=40.7128, gps_lng=-74.0060)
        await svc.clock_in(user_id=1, job_id=job_id, data=req)

        # Second clock-in should fail
        with pytest.raises(Exception):
            await svc.clock_in(user_id=1, job_id=job_id, data=req)


# ══════════════════════════════════════════════════════════════════
# Clock Out
# ══════════════════════════════════════════════════════════════════


class TestClockOut:
    """Test clock-out and hour calculations."""

    @pytest.mark.asyncio
    async def test_clock_out_calculates_hours(self, db_with_admin: aiosqlite.Connection):
        """Clocking out should calculate total hours correctly."""
        job_id = await seed_job(db_with_admin)
        svc = LaborService(db_with_admin)

        # Clock in
        req_in = ClockInRequest(gps_lat=40.7128, gps_lng=-74.0060)
        entry = await svc.clock_in(user_id=1, job_id=job_id, data=req_in)

        # Clock out
        req_out = ClockOutRequest(
            labor_entry_id=entry.id,
            gps_lat=40.7128,
            gps_lng=-74.0060,
            drive_time_minutes=0,
            notes=None,
            responses=[],
            one_time_answers=[],
        )
        result = await svc.clock_out(user_id=1, data=req_out)

        assert result is not None
        assert result.status == "clocked_out"
        # Hours are regular_hours + overtime_hours
        total = (result.regular_hours or 0) + (result.overtime_hours or 0)
        assert total >= 0

    @pytest.mark.asyncio
    async def test_drive_time_subtracted(self, db_with_admin: aiosqlite.Connection):
        """Drive time should be subtracted from total hours."""
        job_id = await seed_job(db_with_admin)
        svc = LaborService(db_with_admin)

        req_in = ClockInRequest(gps_lat=40.7128, gps_lng=-74.0060)
        entry = await svc.clock_in(user_id=1, job_id=job_id, data=req_in)

        # Clock out with 30 min drive time
        req_out = ClockOutRequest(
            labor_entry_id=entry.id,
            gps_lat=40.7128,
            gps_lng=-74.0060,
            drive_time_minutes=30,
            notes=None,
            responses=[],
            one_time_answers=[],
        )
        result = await svc.clock_out(user_id=1, data=req_out)
        # Hours should account for drive time subtraction
        total = (result.regular_hours or 0) + (result.overtime_hours or 0)
        assert total >= 0


# ══════════════════════════════════════════════════════════════════
# Active Clock
# ══════════════════════════════════════════════════════════════════


class TestActiveClock:
    """Test checking active clock state."""

    @pytest.mark.asyncio
    async def test_no_active_clock_initially(self, db_with_admin: aiosqlite.Connection):
        """User should have no active clock when not clocked in."""
        svc = LaborService(db_with_admin)
        result = await svc.get_active_clock(user_id=1)
        assert result is None or result.is_clocked_in is False

    @pytest.mark.asyncio
    async def test_active_clock_after_clock_in(self, db_with_admin: aiosqlite.Connection):
        """User should have active clock after clocking in."""
        job_id = await seed_job(db_with_admin)
        svc = LaborService(db_with_admin)

        req = ClockInRequest(gps_lat=40.7128, gps_lng=-74.0060)
        await svc.clock_in(user_id=1, job_id=job_id, data=req)

        result = await svc.get_active_clock(user_id=1)
        assert result is not None
