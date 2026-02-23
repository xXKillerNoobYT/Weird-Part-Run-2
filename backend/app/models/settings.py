"""
Settings-related Pydantic models.

Covers reading/updating app settings and theme configuration.
"""

from __future__ import annotations

from pydantic import BaseModel, Field


class SettingItem(BaseModel):
    """A single key-value setting from the settings table."""
    key: str
    value: str | None = None  # JSON-encoded value
    category: str = "general"


class SettingUpdate(BaseModel):
    """Request to update a single setting."""
    value: str  # JSON-encoded value


class ThemeSettings(BaseModel):
    """Theme configuration — maps to settings with category='theme'."""
    theme_mode: str = "system"       # "light", "dark", "system"
    primary_color: str = "#3B82F6"   # hex color
    font_family: str = "Inter"


class SettingsBulkUpdate(BaseModel):
    """Bulk update multiple settings at once."""
    settings: dict[str, str] = Field(default_factory=dict)  # key → JSON value
