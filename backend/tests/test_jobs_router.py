"""
Tests for the Jobs Router — CRUD and labor operations.

Covers:
- Create job
- Get job detail
- Job list with filters
- Clock in/out via API
"""

from __future__ import annotations

import pytest
from httpx import AsyncClient


# ══════════════════════════════════════════════════════════════════
# Job CRUD
# ══════════════════════════════════════════════════════════════════


class TestJobCRUD:
    """Test job creation, retrieval, and listing."""

    @pytest.mark.asyncio
    async def test_create_job(self, auth_client: AsyncClient):
        """Creating a job should return it with an ID."""
        resp = await auth_client.post("/api/jobs", json={
            "job_name": "Test Job Alpha",
            "job_number": "TJ-001",
            "customer_name": "Test Customer",
        })
        assert resp.status_code in (200, 201)
        data = resp.json()["data"]
        assert data["id"] is not None
        assert data["job_name"] == "Test Job Alpha"

    @pytest.mark.asyncio
    async def test_get_job_detail(self, auth_client: AsyncClient):
        """Getting a job by ID should return full details."""
        # Create
        resp = await auth_client.post("/api/jobs", json={
            "job_name": "Detail Test Job",
            "job_number": "DTJ-001",
            "customer_name": "Detail Customer",
        })
        job_id = resp.json()["data"]["id"]

        # Get
        resp = await auth_client.get(f"/api/jobs/{job_id}")
        assert resp.status_code == 200
        data = resp.json()["data"]
        assert data["id"] == job_id
        assert data["job_name"] == "Detail Test Job"

    @pytest.mark.asyncio
    async def test_list_jobs(self, auth_client: AsyncClient):
        """Should return a list of jobs."""
        # Create a job
        await auth_client.post("/api/jobs", json={
            "job_name": "List Test Job",
            "job_number": "LTJ-001",
            "customer_name": "List Customer",
        })

        resp = await auth_client.get("/api/jobs/active")
        assert resp.status_code == 200
        data = resp.json()["data"]
        items = data if isinstance(data, list) else data.get("items", [])
        assert len(items) >= 1

    @pytest.mark.asyncio
    async def test_create_job_without_auth_fails(self, client: AsyncClient):
        """Creating a job without auth should return 401."""
        resp = await client.post("/api/jobs", json={
            "job_name": "Unauthorized Job",
            "job_number": "UJ-001",
            "customer_name": "Unauth Customer",
        })
        assert resp.status_code == 401


# ══════════════════════════════════════════════════════════════════
# Clock In/Out via API
# ══════════════════════════════════════════════════════════════════


class TestClockInOutAPI:
    """Test clock in/out through the API layer."""

    @pytest.mark.asyncio
    async def test_clock_in_via_api(self, auth_client: AsyncClient):
        """POST /api/jobs/:id/clock-in should create a labor entry."""
        # Create a job
        resp = await auth_client.post("/api/jobs", json={
            "job_name": "Clock Test Job",
            "job_number": "CTJ-001",
            "customer_name": "Clock Customer",
        })
        job_id = resp.json()["data"]["id"]

        # Clock in
        resp = await auth_client.post(f"/api/jobs/{job_id}/clock-in", json={
            "gps_lat": 40.7128,
            "gps_lng": -74.0060,
        })
        assert resp.status_code in (200, 201)
        data = resp.json()["data"]
        assert data["job_id"] == job_id

    @pytest.mark.asyncio
    async def test_clock_out_via_api(self, auth_client: AsyncClient):
        """POST /api/jobs/:id/clock-out should finalize a labor entry."""
        # Create and clock in
        resp = await auth_client.post("/api/jobs", json={
            "job_name": "Clockout Test Job",
            "job_number": "COJ-001",
            "customer_name": "Clockout Customer",
        })
        job_id = resp.json()["data"]["id"]

        resp = await auth_client.post(f"/api/jobs/{job_id}/clock-in", json={
            "gps_lat": 40.7128,
            "gps_lng": -74.0060,
        })
        entry_id = resp.json()["data"]["id"]

        # Clock out (endpoint is /api/jobs/clock-out, not job-specific)
        resp = await auth_client.post("/api/jobs/clock-out", json={
            "labor_entry_id": entry_id,
            "gps_lat": 40.7128,
            "gps_lng": -74.0060,
            "drive_time_minutes": 15,
            "responses": [],
            "one_time_answers": [],
        })
        assert resp.status_code in (200, 201)
