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


class PDFSettings(BaseModel):
    """PDF template configuration — maps to settings with category='pdf'.

    Controls the formatting and display preferences for PO PDF generation.
    Company info (name, address, logo) comes from company_profiles, not here.
    """
    accent_color: str = "#3B82F6"         # Hex color for header accent bar
    show_unit_prices: bool = True         # Show unit price column in line items
    show_extended: bool = True            # Show extended/total column in line items
    footer_text: str = ""                 # Custom footer text (e.g. "Thank you for your business!")
    payment_terms: str = "Net 30"         # Default payment terms
    delivery_notes: str = ""              # Default delivery instructions


class SettingsBulkUpdate(BaseModel):
    """Bulk update multiple settings at once."""
    settings: dict[str, str] = Field(default_factory=dict)  # key → JSON value
