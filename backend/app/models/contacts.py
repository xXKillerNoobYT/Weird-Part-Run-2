"""
Contacts module Pydantic models — customers, general contractors,
entity contacts, and job linking junctions.

Covers all request/response shapes for the Contacts management endpoints.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


# ── Shared Literals ───────────────────────────────────────────────

CUSTOMER_TYPES = Literal["residential", "commercial", "government", "other"]

GC_TRADE_TYPES = Literal[
    "general", "electrical", "plumbing", "hvac",
    "mechanical", "fire_protection", "low_voltage", "other",
]

ENTITY_TYPES = Literal["customer", "general_contractor", "supplier"]

CONTACT_ROLES = Literal[
    "owner", "property_manager", "tenant",
    "site_contact", "billing", "other",
]

GC_RELATIONSHIPS = Literal["they_are_gc", "we_hired_them"]


# ── Customer ──────────────────────────────────────────────────────

class CustomerCreate(BaseModel):
    """Create a new customer."""
    company_name: str | None = None
    first_name: str = Field(..., min_length=1, max_length=100)
    last_name: str = Field(..., min_length=1, max_length=100)
    phone: str | None = None
    email: str | None = None
    address_line1: str | None = None
    address_line2: str | None = None
    city: str | None = None
    state: str | None = None
    zip: str | None = None
    customer_type: CUSTOMER_TYPES = "residential"
    notes: str | None = None


class CustomerUpdate(BaseModel):
    """Partial update for an existing customer."""
    company_name: str | None = None
    first_name: str | None = Field(default=None, min_length=1, max_length=100)
    last_name: str | None = Field(default=None, min_length=1, max_length=100)
    phone: str | None = None
    email: str | None = None
    address_line1: str | None = None
    address_line2: str | None = None
    city: str | None = None
    state: str | None = None
    zip: str | None = None
    customer_type: CUSTOMER_TYPES | None = None
    notes: str | None = None


class CustomerResponse(BaseModel):
    """Full customer detail returned from the API."""
    id: int
    company_name: str | None = None
    first_name: str
    last_name: str
    display_name: str | None = None
    phone: str | None = None
    email: str | None = None
    address_line1: str | None = None
    address_line2: str | None = None
    city: str | None = None
    state: str | None = None
    zip: str | None = None
    customer_type: str = "residential"
    notes: str | None = None
    is_active: bool = True
    created_at: datetime | None = None
    updated_at: datetime | None = None

    # Hydrated in detail endpoint
    contacts: list[EntityContactResponse] = Field(default_factory=list)
    job_count: int = 0


class CustomerListItem(BaseModel):
    """Lightweight customer for list views."""
    id: int
    company_name: str | None = None
    first_name: str
    last_name: str
    display_name: str | None = None
    phone: str | None = None
    email: str | None = None
    customer_type: str = "residential"
    is_active: bool = True
    job_count: int = 0
    contact_count: int = 0


# ── General Contractor ────────────────────────────────────────────

class GCCreate(BaseModel):
    """Create a new general contractor."""
    company_name: str = Field(..., min_length=1, max_length=200)
    gc_code: str = Field(..., min_length=1, max_length=20)
    license_number: str | None = None
    trade_type: GC_TRADE_TYPES = "general"
    phone: str | None = None
    email: str | None = None
    website: str | None = None
    address_line1: str | None = None
    address_line2: str | None = None
    city: str | None = None
    state: str | None = None
    zip: str | None = None
    insurance_info: str | None = None
    notes: str | None = None


class GCUpdate(BaseModel):
    """Partial update for an existing GC."""
    company_name: str | None = Field(default=None, min_length=1, max_length=200)
    gc_code: str | None = Field(default=None, min_length=1, max_length=20)
    license_number: str | None = None
    trade_type: GC_TRADE_TYPES | None = None
    phone: str | None = None
    email: str | None = None
    website: str | None = None
    address_line1: str | None = None
    address_line2: str | None = None
    city: str | None = None
    state: str | None = None
    zip: str | None = None
    insurance_info: str | None = None
    notes: str | None = None


class GCResponse(BaseModel):
    """Full GC detail returned from the API."""
    id: int
    company_name: str
    gc_code: str
    license_number: str | None = None
    trade_type: str = "general"
    phone: str | None = None
    email: str | None = None
    website: str | None = None
    address_line1: str | None = None
    address_line2: str | None = None
    city: str | None = None
    state: str | None = None
    zip: str | None = None
    insurance_info: str | None = None
    notes: str | None = None
    is_active: bool = True
    created_at: datetime | None = None
    updated_at: datetime | None = None

    # Hydrated in detail endpoint
    contacts: list[EntityContactResponse] = Field(default_factory=list)
    job_count: int = 0


class GCListItem(BaseModel):
    """Lightweight GC for list views."""
    id: int
    company_name: str
    gc_code: str
    trade_type: str = "general"
    phone: str | None = None
    email: str | None = None
    is_active: bool = True
    job_count: int = 0
    contact_count: int = 0


# ── Entity Contact ────────────────────────────────────────────────

class EntityContactCreate(BaseModel):
    """Add a contact to a customer, GC, or supplier."""
    first_name: str = Field(..., min_length=1, max_length=100)
    last_name: str = Field(default="", max_length=100)
    role: str = Field(..., min_length=1, max_length=100)  # freetext
    phone: str = Field(..., min_length=1)  # mandatory
    email: str | None = None
    is_primary: bool = False
    notes: str | None = None


class EntityContactUpdate(BaseModel):
    """Partial update for an entity contact."""
    first_name: str | None = Field(default=None, min_length=1, max_length=100)
    last_name: str | None = Field(default=None, max_length=100)
    role: str | None = Field(default=None, min_length=1, max_length=100)
    phone: str | None = Field(default=None, min_length=1)
    email: str | None = None
    is_primary: bool | None = None
    notes: str | None = None


class EntityContactResponse(BaseModel):
    """Entity contact returned from the API."""
    id: int
    entity_type: str
    entity_id: int
    first_name: str
    last_name: str = ""
    role: str
    phone: str
    email: str | None = None
    is_primary: bool = False
    notes: str | None = None
    is_active: bool = True
    created_at: datetime | None = None
    updated_at: datetime | None = None


# ── Directory (Unified Contact Search) ────────────────────────────

class DirectoryContactResult(BaseModel):
    """Unified search result across all entity_contacts."""
    id: int
    first_name: str
    last_name: str = ""
    role: str
    phone: str
    email: str | None = None
    entity_type: str          # 'customer', 'general_contractor', 'supplier'
    entity_id: int
    entity_name: str = ""     # resolved parent name (customer display_name, gc company_name, supplier name)


# ── Job ↔ Customer Linking ────────────────────────────────────────

class JobCustomerCreate(BaseModel):
    """Link a customer to a job."""
    customer_id: int
    contact_role: CONTACT_ROLES = "owner"
    is_primary: bool = False
    notes: str | None = None


class JobCustomerResponse(BaseModel):
    """Job-customer link returned from the API."""
    id: int
    job_id: int
    customer_id: int
    contact_role: str = "owner"
    is_primary: bool = False
    notes: str | None = None
    created_at: datetime | None = None

    # Hydrated from customer
    customer_name: str | None = None
    company_name: str | None = None
    phone: str | None = None
    email: str | None = None


# ── Job ↔ GC Linking ─────────────────────────────────────────────

class JobGCCreate(BaseModel):
    """Link a general contractor to a job."""
    gc_id: int
    relationship: GC_RELATIONSHIPS
    contract_amount: float | None = None
    contract_number: str | None = None
    is_primary: bool = False
    notes: str | None = None


class JobGCResponse(BaseModel):
    """Job-GC link returned from the API."""
    id: int
    job_id: int
    gc_id: int
    relationship: str
    contract_amount: float | None = None
    contract_number: str | None = None
    is_primary: bool = False
    notes: str | None = None
    created_at: datetime | None = None

    # Hydrated from GC
    company_name: str | None = None
    gc_code: str | None = None
    trade_type: str | None = None
    phone: str | None = None
    email: str | None = None
