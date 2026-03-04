"""
Pydantic models for Company Profiles.

Used for PO PDF branding (logo, address, contact info) and
multi-branch support for electrical contractors with multiple offices.
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class CompanyProfileCreate(BaseModel):
    """Create a new company profile / branch."""
    name: str = Field(..., min_length=1, max_length=200)
    address_street: str | None = None
    address_city: str | None = None
    address_state: str | None = None
    address_zip: str | None = None
    phone: str | None = None
    email: str | None = None
    website: str | None = None
    contractor_license: str | None = None
    insurance_info: str | None = None
    tax_id: str | None = None
    is_primary: bool = False
    branch_name: str | None = None
    notes: str | None = None


class CompanyProfileUpdate(BaseModel):
    """Update an existing company profile."""
    name: str | None = Field(None, min_length=1, max_length=200)
    address_street: str | None = None
    address_city: str | None = None
    address_state: str | None = None
    address_zip: str | None = None
    phone: str | None = None
    email: str | None = None
    website: str | None = None
    logo_path: str | None = None
    contractor_license: str | None = None
    insurance_info: str | None = None
    tax_id: str | None = None
    is_primary: bool | None = None
    branch_name: str | None = None
    notes: str | None = None


class CompanyProfileResponse(BaseModel):
    """Company profile in API responses."""
    id: int
    name: str
    address_street: str | None = None
    address_city: str | None = None
    address_state: str | None = None
    address_zip: str | None = None
    phone: str | None = None
    email: str | None = None
    website: str | None = None
    logo_path: str | None = None
    contractor_license: str | None = None
    insurance_info: str | None = None
    tax_id: str | None = None
    is_primary: bool = False
    branch_name: str | None = None
    notes: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None

    @property
    def full_address(self) -> str:
        """Format full address for display/PDF."""
        parts = [
            self.address_street,
            f"{self.address_city}, {self.address_state} {self.address_zip}"
            if self.address_city else None,
        ]
        return "\n".join(p for p in parts if p)
