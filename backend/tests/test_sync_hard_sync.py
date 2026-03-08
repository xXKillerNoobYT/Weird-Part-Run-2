"""Tests for hard-sync backup/recovery endpoints."""

from __future__ import annotations

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_hard_sync_request_returns_package(auth_client: AsyncClient):
    resp = await auth_client.post(
        "/api/sync/hard-sync/request",
        json={
            "device_id": "device-hard-sync-001",
            "reason_code": "stale_data",
            "pending_outbound_hashes": ["abc123", "def456"],
            "preserve_pending_data": True,
        },
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()["data"]

    assert data["device_id"] == "device-hard-sync-001"
    assert data["hard_sync_id"] > 0
    assert data["sync_batch_id"]
    assert data["table_count"] >= 1
    assert isinstance(data["tables"], dict)


@pytest.mark.asyncio
async def test_hard_sync_complete_and_history(auth_client: AsyncClient):
    # Request package first
    resp = await auth_client.post(
        "/api/sync/hard-sync/request",
        json={
            "device_id": "device-hard-sync-002",
            "reason_code": "partial_state",
        },
    )
    assert resp.status_code == 200, resp.text
    pkg = resp.json()["data"]

    # Complete it
    resp = await auth_client.post(
        "/api/sync/hard-sync/complete",
        json={
            "hard_sync_id": pkg["hard_sync_id"],
            "device_id": pkg["device_id"],
            "sync_batch_id": pkg["sync_batch_id"],
            "applied_tables": ["users", "jobs"],
            "restored_pending_count": 2,
            "notes": "Completed in test",
        },
    )
    assert resp.status_code == 200, resp.text
    complete = resp.json()["data"]
    assert complete["hard_sync_id"] == pkg["hard_sync_id"]

    # History should include the event
    resp = await auth_client.get(
        "/api/sync/hard-sync/history",
        params={"device_id": "device-hard-sync-002", "limit": 10},
    )
    assert resp.status_code == 200, resp.text
    rows = resp.json()["data"]
    assert len(rows) >= 1
    assert rows[0]["device_id"] == "device-hard-sync-002"
