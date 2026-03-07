"""
Settings routes — app configuration, theme, company profiles, staging zones.

Settings are stored as JSON key-value pairs categorized into groups:
general, theme, sync, ai, procurement, device.

Theme settings are separated because they're accessed frequently
and by all users (no permission needed to read your own theme).

Company profiles and staging zones are managed here because they're
"app configuration" rather than transactional data.

IMPORTANT: Route ordering matters! Specific paths like /company-profiles
and /staging-zones MUST be registered before the /{key} catch-all,
otherwise FastAPI will match "company-profiles" as a key parameter.
"""

from __future__ import annotations

import os
import time

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse
from app.models.company import CompanyProfileCreate, CompanyProfileUpdate
from app.models.settings import (
    SettingItem,
    SettingsBulkUpdate,
    SettingUpdate,
    ThemeSettings,
)
from app.models.orders import StagingZoneCreate, StagingZoneUpdate
from app.repositories.settings_repo import SettingsRepo
from app.repositories.staging_repo import StagingZoneRepo

router = APIRouter(prefix="/api/settings", tags=["Settings"], redirect_slashes=False)


# ── Theme (accessible by any authenticated user) ────────────────────

@router.get("/theme", response_model=ApiResponse[ThemeSettings])
async def get_theme(
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get theme settings (mode, color, font).

    Any authenticated user can read theme settings — they need
    this to render the UI correctly.
    """
    repo = SettingsRepo(db)
    theme_data = await repo.get_by_category("theme")

    return ApiResponse(
        data=ThemeSettings(
            theme_mode=theme_data.get("theme_mode", "system"),
            primary_color=theme_data.get("primary_color", "#3B82F6"),
            font_family=theme_data.get("font_family", "Inter"),
        ),
    )


@router.put("/theme", response_model=ApiResponse[ThemeSettings])
async def update_theme(
    theme: ThemeSettings,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update theme settings.

    Any authenticated user can change themes — it's a shared setting
    (all devices show the same theme for consistency).
    """
    repo = SettingsRepo(db)
    await repo.set_value("theme_mode", theme.theme_mode, "theme")
    await repo.set_value("primary_color", theme.primary_color, "theme")
    await repo.set_value("font_family", theme.font_family, "theme")

    return ApiResponse(
        data=theme,
        message="Theme updated successfully.",
    )


# ═══════════════════════════════════════════════════════════════
# Company Profiles (for PO PDFs / branding)
# ═══════════════════════════════════════════════════════════════
# IMPORTANT: These routes must be registered BEFORE the /{key}
# catch-all below, otherwise FastAPI would match "company-profiles"
# as a key parameter and route to get_setting() instead.


@router.get("/company-profiles", response_model=ApiResponse)
async def list_company_profiles(
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all company profiles / branches."""
    cursor = await db.execute(
        "SELECT * FROM company_profiles ORDER BY is_primary DESC, name"
    )
    profiles = [dict(row) for row in await cursor.fetchall()]

    return ApiResponse(data=profiles)


@router.get("/company-profiles/{profile_id}", response_model=ApiResponse)
async def get_company_profile(
    profile_id: int,
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a single company profile."""
    cursor = await db.execute(
        "SELECT * FROM company_profiles WHERE id = ?", (profile_id,)
    )
    profile = await cursor.fetchone()
    if not profile:
        raise HTTPException(404, "Company profile not found")

    return ApiResponse(data=dict(profile))


@router.post("/company-profiles", response_model=ApiResponse)
async def create_company_profile(
    body: CompanyProfileCreate,
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new company profile / branch."""
    data = body.model_dump(exclude_none=True)

    # If setting as primary, unset existing primary
    if data.get("is_primary"):
        await db.execute("UPDATE company_profiles SET is_primary = 0")

    columns = ", ".join(data.keys())
    placeholders = ", ".join(["?"] * len(data))
    cursor = await db.execute(
        f"INSERT INTO company_profiles ({columns}) VALUES ({placeholders})",
        tuple(data.values()),
    )
    await db.commit()

    return ApiResponse(
        data={"id": cursor.lastrowid},
        message="Company profile created.",
    )


@router.put("/company-profiles/{profile_id}", response_model=ApiResponse)
async def update_company_profile(
    profile_id: int,
    body: CompanyProfileUpdate,
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a company profile."""
    data = body.model_dump(exclude_none=True)
    if not data:
        raise HTTPException(400, "No fields to update")

    # If setting as primary, unset existing primary
    if data.get("is_primary"):
        await db.execute("UPDATE company_profiles SET is_primary = 0")

    set_clause = ", ".join(f"{k} = ?" for k in data.keys())
    cursor = await db.execute(
        f"UPDATE company_profiles SET {set_clause} WHERE id = ?",
        (*data.values(), profile_id),
    )
    await db.commit()

    if cursor.rowcount == 0:
        raise HTTPException(404, "Company profile not found")

    return ApiResponse(data={"id": profile_id}, message="Company profile updated.")


@router.delete("/company-profiles/{profile_id}", response_model=ApiResponse)
async def delete_company_profile(
    profile_id: int,
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a company profile."""
    cursor = await db.execute(
        "DELETE FROM company_profiles WHERE id = ?", (profile_id,)
    )
    await db.commit()

    if cursor.rowcount == 0:
        raise HTTPException(404, "Company profile not found")

    return ApiResponse(data={"id": profile_id}, message="Company profile deleted.")


# ═══════════════════════════════════════════════════════════════
# Staging Zones (physical warehouse zones)
# ═══════════════════════════════════════════════════════════════
# Also before /{key} — same reason as company profiles.


@router.get("/staging-zones", response_model=ApiResponse)
async def list_staging_zones(
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all staging zones for warehouse management."""
    repo = StagingZoneRepo(db)
    zones = await repo.get_all()

    return ApiResponse(data=zones)


@router.post("/staging-zones", response_model=ApiResponse)
async def create_staging_zone(
    body: StagingZoneCreate,
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new staging zone."""
    repo = StagingZoneRepo(db)
    zone_id = await repo.insert(body.model_dump(exclude_none=True))

    return ApiResponse(
        data={"id": zone_id},
        message=f"Staging zone '{body.label}' created.",
    )


@router.put("/staging-zones/{zone_id}", response_model=ApiResponse)
async def update_staging_zone(
    zone_id: int,
    body: StagingZoneUpdate,
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a staging zone."""
    repo = StagingZoneRepo(db)
    data = body.model_dump(exclude_none=True)
    if not data:
        raise HTTPException(400, "No fields to update")

    ok = await repo.update(zone_id, data)
    if not ok:
        raise HTTPException(404, "Staging zone not found")

    return ApiResponse(data={"id": zone_id}, message="Staging zone updated.")


# ═══════════════════════════════════════════════════════════════
# System Info (About page)
# ═══════════════════════════════════════════════════════════════

_start_time = time.time()


@router.get("/system-info")
async def system_info(
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get system information for the About page."""
    # Table count
    cursor = await db.execute(
        "SELECT COUNT(*) AS cnt FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    )
    tables = (await cursor.fetchone())["cnt"]

    # DB file size
    cursor = await db.execute("PRAGMA database_list")
    db_row = await cursor.fetchone()
    db_path = db_row["file"] if db_row else ""
    db_size_mb = os.path.getsize(db_path) / (1024 * 1024) if db_path and os.path.exists(db_path) else 0

    # Quick data counts
    counts = {}
    for table, key in [("users", "active_users"), ("jobs", "total_jobs"),
                       ("parts", "total_parts"), ("tools", "total_tools")]:
        try:
            cond = " WHERE is_active = 1" if table == "users" else ""
            cursor = await db.execute(f"SELECT COUNT(*) AS cnt FROM {table}{cond}")
            counts[key] = (await cursor.fetchone())["cnt"]
        except Exception:
            counts[key] = 0

    return ApiResponse(data={
        "db_tables": tables,
        "db_size_mb": round(db_size_mb, 2),
        "uptime_seconds": int(time.time() - _start_time),
        **counts,
    })


# ═══════════════════════════════════════════════════════════════
# General Settings (requires manage_settings permission)
# ═══════════════════════════════════════════════════════════════


@router.get("/", response_model=ApiResponse[dict])
async def get_all_settings(
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get all settings grouped by category.

    Requires manage_settings permission (Admin only by default).
    """
    repo = SettingsRepo(db)
    grouped = await repo.get_all_settings()

    return ApiResponse(data=grouped)


@router.put("/bulk", response_model=ApiResponse[dict])
async def bulk_update_settings(
    updates: SettingsBulkUpdate,
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update multiple settings at once."""
    repo = SettingsRepo(db)
    count = await repo.bulk_update(updates.settings)

    return ApiResponse(
        data={"updated_count": count},
        message=f"{count} settings updated.",
    )


# ── Single key CRUD (catch-all — MUST be last!) ─────────────────────
# These /{key} routes match ANY path segment, so they MUST be
# registered after all specific paths to avoid route collisions.


@router.get("/{key}", response_model=ApiResponse[SettingItem])
async def get_setting(
    key: str,
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a single setting by key."""
    repo = SettingsRepo(db)
    value = await repo.get_by_key(key)

    # Find the category from the raw row
    cursor = await db.execute(
        "SELECT category FROM settings WHERE key = ?", (key,)
    )
    row = await cursor.fetchone()
    category = row["category"] if row else "general"

    return ApiResponse(
        data=SettingItem(
            key=key,
            value=str(value) if value is not None else None,
            category=category,
        ),
    )


@router.put("/{key}", response_model=ApiResponse[SettingItem])
async def update_setting(
    key: str,
    update: SettingUpdate,
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a single setting by key.

    The value should be a JSON-encoded string.
    """
    repo = SettingsRepo(db)

    # Get current category (or default)
    cursor = await db.execute(
        "SELECT category FROM settings WHERE key = ?", (key,)
    )
    row = await cursor.fetchone()
    category = row["category"] if row else "general"

    await repo.set_value(key, update.value, category)

    return ApiResponse(
        data=SettingItem(key=key, value=update.value, category=category),
        message=f"Setting '{key}' updated.",
    )
