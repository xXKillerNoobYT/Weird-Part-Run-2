"""
Settings routes — app configuration, theme, and device management.

Settings are stored as JSON key-value pairs categorized into groups:
general, theme, sync, ai, procurement, device.

Theme settings are separated because they're accessed frequently
and by all users (no permission needed to read your own theme).
"""

from __future__ import annotations

import aiosqlite
from fastapi import APIRouter, Depends

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse
from app.models.settings import (
    SettingItem,
    SettingsBulkUpdate,
    SettingUpdate,
    ThemeSettings,
)
from app.repositories.settings_repo import SettingsRepo

router = APIRouter(prefix="/api/settings", tags=["Settings"])


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


# ── General Settings (requires manage_settings permission) ──────────

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
