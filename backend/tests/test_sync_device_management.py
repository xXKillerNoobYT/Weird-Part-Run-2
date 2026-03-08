"""Tests for device sync profile and mesh relay management endpoints."""

from __future__ import annotations

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_device_sync_profile_update_flow(auth_client: AsyncClient):
    # Ensure device exists
    resp = await auth_client.post(
        "/api/sync/register",
        json={
            "device_id": "mesh-device-001",
            "device_name": "Foreman Tablet",
            "platform": "android",
        },
    )
    assert resp.status_code == 200, resp.text

    # Update profile
    resp = await auth_client.put(
        "/api/sync/profile/mesh-device-001",
        json={
            "storage_policy": "active_jobs_core_only",
            "media_policy": "assigned_jobs_only",
            "media_retention_days": 21,
            "force_carry_undelivered_media": True,
            "allow_borrowed_user_overrides": False,
            "active_only_sync": True,
        },
    )
    assert resp.status_code == 200, resp.text
    profile = resp.json()["data"]
    assert profile["device_id"] == "mesh-device-001"
    assert profile["active_only_sync"] == 1

    # Read back profile
    resp = await auth_client.get("/api/sync/profile/mesh-device-001")
    assert resp.status_code == 200
    profile = resp.json()["data"]
    assert profile["media_retention_days"] == 21


@pytest.mark.asyncio
async def test_mesh_relay_event_logging_and_listing(auth_client: AsyncClient):
    # Log relay event
    resp = await auth_client.post(
        "/api/sync/mesh/relay-events",
        json={
            "source_device_id": "mesh-device-001",
            "peer_device_id": "mesh-device-002",
            "relay_type": "gossip",
            "carried_change_count": 37,
            "carried_media_count": 4,
            "undelivered_after_count": 3,
            "metadata": {"signal": "bt", "duration_sec": 42},
        },
    )
    assert resp.status_code == 200, resp.text
    event = resp.json()["data"]
    assert event["source_device_id"] == "mesh-device-001"

    # Admin list
    resp = await auth_client.get(
        "/api/sync/mesh/relay-events",
        params={"device_id": "mesh-device-001", "limit": 20},
    )
    assert resp.status_code == 200, resp.text
    rows = resp.json()["data"]
    assert len(rows) >= 1
    assert any(r["source_device_id"] == "mesh-device-001" for r in rows)


@pytest.mark.asyncio
async def test_initial_sync_active_jobs_filter(auth_client: AsyncClient):
    # Active-only initial sync should return only active jobs in jobs table
    resp = await auth_client.post(
        "/api/sync/initial",
        json={
            "device_id": "mesh-device-003",
            "only_active_jobs": True,
            "tables": ["jobs"],
        },
    )
    assert resp.status_code == 200, resp.text
    jobs = resp.json()["data"]["tables"]["jobs"]
    assert isinstance(jobs, list)
    # If jobs exist, they should all be active by filter contract
    if jobs:
        assert all(j.get("status") == "active" for j in jobs)
