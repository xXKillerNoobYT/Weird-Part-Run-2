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


class BillingCycleSettings(BaseModel):
    """Billing cycle configuration.

    Controls how billing periods are computed for job cost rollups,
    profitability reports, and bookkeeper exports.
    """
    cycle_type: str = "monthly"  # weekly | biweekly | semi_monthly | monthly | quarterly | yearly
    start_day: int = 1           # day-of-week (1=Mon) or day-of-month (1-28)


class PayPeriodSettings(BaseModel):
    """Pay period configuration.

    Controls how pay periods are computed for timesheets,
    labor reports, and payroll exports.
    """
    period_type: str = "weekly"  # weekly | biweekly | semi_monthly | monthly
    start_day: int = 1           # day-of-week (1=Mon) or day-of-month (1-28)


class PayrollColumnConfig(BaseModel):
    """Customizable payroll export columns.

    Allows admins to pick which columns appear in payroll CSV exports.
    """
    columns: list[str] = Field(default_factory=lambda: [
        "Employee ID",
        "Employee Name",
        "Period Start",
        "Period End",
        "Regular Hours",
        "Overtime Hours",
        "Total Hours",
        "Pay Rate",
    ])
