"""Tests for Update Protocol — version registry, validations, fleet targets, device updates."""

from __future__ import annotations

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_version_registration_and_publish(auth_client: AsyncClient):
    """Register a version, then publish it."""

    resp = await auth_client.post(
        "/api/updates/versions",
        json={
            "version": "1.0.0",
            "previous_version": None,
            "release_notes": "Initial release",
            "criticality": "normal",
            "source": "github",
            "migration_scripts": ["001_foundation.sql"],
            "rollback_scripts": ["001_rollback.sql"],
        },
    )
    assert resp.status_code == 200, resp.text
    ver = resp.json()["data"]
    assert ver["version"] == "1.0.0"
    assert ver["published_at"] is None

    # Publish it
    resp = await auth_client.post("/api/updates/versions/1.0.0/publish")
    assert resp.status_code == 200, resp.text
    ver = resp.json()["data"]
    assert ver["published_at"] is not None

    # List published
    resp = await auth_client.get(
        "/api/updates/versions", params={"published_only": True},
    )
    versions = resp.json()["data"]
    assert any(v["version"] == "1.0.0" for v in versions)


@pytest.mark.asyncio
async def test_validation_lifecycle(auth_client: AsyncClient):
    """Create, run, and pass a validation."""

    # Register version first
    await auth_client.post(
        "/api/updates/versions",
        json={"version": "1.1.0", "previous_version": "1.0.0"},
    )

    # Create validation for windows
    resp = await auth_client.post(
        "/api/updates/validations",
        json={"version": "1.1.0", "platform": "windows"},
    )
    assert resp.status_code == 200, resp.text
    val = resp.json()["data"]
    assert val["status"] == "pending"

    # Mark as running
    resp = await auth_client.put(
        "/api/updates/validations",
        json={"version": "1.1.0", "platform": "windows", "status": "running"},
    )
    assert resp.json()["data"]["started_at"] is not None

    # Mark as passed
    resp = await auth_client.put(
        "/api/updates/validations",
        json={
            "version": "1.1.0",
            "platform": "windows",
            "status": "passed",
            "schema_diff_ok": True,
            "migration_test_ok": True,
            "rollback_test_ok": True,
            "backward_compat_ok": True,
        },
    )
    assert resp.status_code == 200
    val = resp.json()["data"]
    assert val["status"] == "passed"
    assert val["schema_diff_ok"] == 1
    assert val["completed_at"] is not None


@pytest.mark.asyncio
async def test_fleet_target_and_device_reporting(auth_client: AsyncClient):
    """Set fleet target, have a device report, check counts."""

    # Register + publish version chain
    await auth_client.post(
        "/api/updates/versions",
        json={"version": "2.0.0", "previous_version": None, "source": "manual"},
    )
    await auth_client.post("/api/updates/versions/2.0.0/publish")

    # Set fleet target
    resp = await auth_client.put(
        "/api/updates/fleet/windows",
        json={"current_target": "2.0.0", "latest_validated": "2.0.0"},
    )
    assert resp.status_code == 200, resp.text
    target = resp.json()["data"]
    assert target["current_target"] == "2.0.0"

    # Register device for sync (FK requirement)
    await auth_client.post(
        "/api/sync/register",
        json={"device_id": "update-device-001", "device_name": "Shop PC", "platform": "windows"},
    )

    # Device reports version
    resp = await auth_client.post(
        "/api/updates/devices/report",
        json={
            "device_id": "update-device-001",
            "platform": "windows",
            "current_version": "2.0.0",
        },
    )
    assert resp.status_code == 200, resp.text
    status = resp.json()["data"]
    assert status["current_version"] == "2.0.0"

    # Refresh fleet counts
    resp = await auth_client.post("/api/updates/fleet/windows/refresh")
    assert resp.status_code == 200
    target = resp.json()["data"]
    assert target["devices_total"] >= 1
    assert target["devices_at_target"] >= 1


@pytest.mark.asyncio
async def test_backup_snapshot_lifecycle(auth_client: AsyncClient):
    """Create a backup snapshot and mark it restored."""

    resp = await auth_client.post(
        "/api/updates/backups",
        json={
            "version_before": "1.0.0",
            "version_target": "1.1.0",
            "backup_path": "/backups/pre-1.1.0.tar.gz",
            "backup_size_bytes": 1048576,
        },
    )
    assert resp.status_code == 200, resp.text
    snap = resp.json()["data"]
    assert snap["status"] == "created"

    # Mark as restored
    resp = await auth_client.post(f"/api/updates/backups/{snap['id']}/restore")
    assert resp.status_code == 200
    restored = resp.json()["data"]
    assert restored["status"] == "restored"
    assert restored["restored_at"] is not None

    # List backups
    resp = await auth_client.get("/api/updates/backups")
    assert resp.status_code == 200
    snaps = resp.json()["data"]
    assert len(snaps) >= 1
