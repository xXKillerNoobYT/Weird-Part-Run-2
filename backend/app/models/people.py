"""
People module Pydantic models — employees, certifications, wages, notes, skills, hats.

Covers all request/response shapes for the People management endpoints.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


# ── Certification ──────────────────────────────────────────────────

CERT_TYPES = Literal[
    "journeyman", "apprentice", "master",
    "osha_10", "osha_30",
    "first_aid", "cpr",
    "forklift", "confined_space",
    "custom",
]


class CertificationCreate(BaseModel):
    """Create a new certification for an employee."""
    cert_type: CERT_TYPES
    cert_name: str = Field(..., min_length=1, max_length=200)
    issuing_authority: str | None = None
    cert_number: str | None = None
    issued_date: str | None = None
    expiry_date: str | None = None
    notes: str | None = None


class CertificationUpdate(BaseModel):
    """Partial update for an existing certification."""
    cert_type: CERT_TYPES | None = None
    cert_name: str | None = Field(default=None, min_length=1, max_length=200)
    issuing_authority: str | None = None
    cert_number: str | None = None
    issued_date: str | None = None
    expiry_date: str | None = None
    is_active: bool | None = None
    notes: str | None = None


class CertificationResponse(BaseModel):
    """Certification record returned from the API."""
    id: int
    user_id: int
    cert_type: str
    cert_name: str
    issuing_authority: str | None = None
    cert_number: str | None = None
    issued_date: str | None = None
    expiry_date: str | None = None
    is_active: bool = True
    notes: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


# ── Wage History ───────────────────────────────────────────────────

WAGE_REASONS = Literal[
    "hire", "raise", "promotion", "demotion", "adjustment", "correction",
]


class WageHistoryCreate(BaseModel):
    """Record a pay rate change."""
    pay_rate: float = Field(..., gt=0)
    effective_date: str = Field(..., min_length=10, max_length=10)  # YYYY-MM-DD
    reason: WAGE_REASONS | None = None


class WageHistoryResponse(BaseModel):
    """Wage history entry returned from the API."""
    id: int
    user_id: int
    pay_rate: float
    effective_date: str
    reason: str | None = None
    changed_by: int | None = None
    changed_by_name: str | None = None
    created_at: datetime | None = None


# ── Employee Notes ─────────────────────────────────────────────────

NOTE_TYPES = Literal[
    "general", "performance", "incident",
    "commendation", "training", "disciplinary",
]


class EmployeeNoteCreate(BaseModel):
    """Create a note on an employee's record."""
    note_type: NOTE_TYPES = "general"
    title: str = Field(..., min_length=1, max_length=200)
    body: str = Field(..., min_length=1)
    is_private: bool = False


class EmployeeNoteUpdate(BaseModel):
    """Partial update for a note."""
    note_type: NOTE_TYPES | None = None
    title: str | None = Field(default=None, min_length=1, max_length=200)
    body: str | None = Field(default=None, min_length=1)
    is_private: bool | None = None


class EmployeeNoteResponse(BaseModel):
    """Employee note returned from the API."""
    id: int
    user_id: int
    note_type: str
    title: str
    body: str
    is_private: bool = False
    created_by: int | None = None
    created_by_name: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


# ── User Skills ────────────────────────────────────────────────────

PROFICIENCY_LEVELS = Literal["beginner", "intermediate", "advanced", "expert"]


class UserSkillCreate(BaseModel):
    """Add a skill to an employee."""
    skill_name: str = Field(..., min_length=1, max_length=100)
    proficiency: PROFICIENCY_LEVELS = "intermediate"
    years_experience: float | None = None


class UserSkillUpdate(BaseModel):
    """Partial update for a skill."""
    skill_name: str | None = Field(default=None, min_length=1, max_length=100)
    proficiency: PROFICIENCY_LEVELS | None = None
    years_experience: float | None = None


class UserSkillResponse(BaseModel):
    """Skill record returned from the API."""
    id: int
    user_id: int
    skill_name: str
    proficiency: str
    years_experience: float | None = None
    verified_by: int | None = None
    verified_by_name: str | None = None
    verified_at: str | None = None
    created_at: datetime | None = None


# ── Employees ──────────────────────────────────────────────────────

CERTIFICATION_LEVELS = Literal["journeyman", "apprentice", "master"]


class EmployeeCreate(BaseModel):
    """Create a new employee (user)."""
    display_name: str = Field(..., min_length=1, max_length=100)
    pin: str = Field(..., min_length=4, max_length=6, pattern=r"^\d{4,6}$")
    email: str | None = None
    phone: str | None = None
    certification: CERTIFICATION_LEVELS | None = None
    hire_date: str | None = None
    pay_rate: float | None = Field(default=None, ge=0)
    hat_ids: list[int] | None = None
    emergency_contact_name: str | None = None
    emergency_contact_phone: str | None = None


class EmployeeUpdate(BaseModel):
    """Partial update for an employee."""
    display_name: str | None = Field(default=None, min_length=1, max_length=100)
    email: str | None = None
    phone: str | None = None
    certification: CERTIFICATION_LEVELS | None = None
    hire_date: str | None = None
    pay_rate: float | None = Field(default=None, ge=0)
    emergency_contact_name: str | None = None
    emergency_contact_phone: str | None = None


class EmployeeListItem(BaseModel):
    """Employee in a list view — lightweight with key info."""
    id: int
    display_name: str
    email: str | None = None
    phone: str | None = None
    certification: str | None = None
    hire_date: str | None = None
    pay_rate: float | None = None
    is_active: bool = True
    avatar_url: str | None = None
    hat_names: list[str] = Field(default_factory=list)
    active_cert_count: int = 0


class EmployeeDetail(BaseModel):
    """Full employee detail with all related data."""
    id: int
    display_name: str
    email: str | None = None
    phone: str | None = None
    certification: str | None = None
    hire_date: str | None = None
    pay_rate: float | None = None
    is_active: bool = True
    avatar_url: str | None = None
    emergency_contact_name: str | None = None
    emergency_contact_phone: str | None = None

    # Related collections
    hats: list[HatSummaryResponse] = Field(default_factory=list)
    permissions: list[str] = Field(default_factory=list)
    certifications: list[CertificationResponse] = Field(default_factory=list)
    wage_history: list[WageHistoryResponse] = Field(default_factory=list)
    notes: list[EmployeeNoteResponse] = Field(default_factory=list)
    skills: list[UserSkillResponse] = Field(default_factory=list)

    # Timestamps
    created_at: datetime | None = None
    updated_at: datetime | None = None


# ── Hats (Roles) ──────────────────────────────────────────────────

class HatSummaryResponse(BaseModel):
    """Minimal hat info for embedding in employee profiles."""
    id: int
    name: str
    level: int


class HatCreate(BaseModel):
    """Create a new hat (role)."""
    name: str = Field(..., min_length=1, max_length=50)
    description: str | None = None
    level: int = Field(default=5, ge=0, le=10)


class HatUpdate(BaseModel):
    """Partial update for a hat."""
    name: str | None = Field(default=None, min_length=1, max_length=50)
    description: str | None = None
    level: int | None = Field(default=None, ge=0, le=10)


class HatDetailResponse(BaseModel):
    """Full hat detail with permission list."""
    id: int
    name: str
    description: str | None = None
    level: int = 0
    is_builtin: bool = False
    permissions: list[str] = Field(default_factory=list)
    user_count: int = 0
    created_at: datetime | None = None


class PermissionAssignment(BaseModel):
    """Replace all permissions for a hat."""
    permission_keys: list[str] = Field(default_factory=list)


# ── Permission Matrix ──────────────────────────────────────────────

class PermissionMatrixRow(BaseModel):
    """One row (permission key) in the permission matrix grid."""
    permission_key: str
    domain: str  # grouping: 'warehouse', 'orders', 'people', etc.
    hat_values: dict[int, bool] = Field(default_factory=dict)  # hat_id → has_permission


# ── Job Lead Elevations ───────────────────────────────────────────

class JobLeadElevationCreate(BaseModel):
    """Grant a temporary permission elevation to a user for a specific job."""
    job_id: int
    permission_key: str = Field(..., min_length=1)


class JobLeadElevationResponse(BaseModel):
    """Job lead elevation returned from the API."""
    id: int
    user_id: int
    user_name: str | None = None
    job_id: int
    job_name: str | None = None
    permission_key: str
    granted_by: int | None = None
    granted_by_name: str | None = None
    granted_at: datetime | None = None


# ── Cert Expiry Alerts ────────────────────────────────────────────

class CertAlertItem(BaseModel):
    """A certification nearing expiry, for dashboard alerts."""
    cert_id: int
    user_id: int
    user_name: str
    cert_name: str
    cert_type: str
    expiry_date: str
    days_until_expiry: int  # 0 = expires today, positive = days remaining
    severity: str  # 'red' (<30 days), 'amber' (<60 days)


# ── Employee Teams ─────────────────────────────────────────────────

TEAM_MEMBER_ROLE = Literal["lead", "member"]


class EmployeeTeamCreate(BaseModel):
    """Create a new employee team."""
    name: str = Field(..., min_length=1, max_length=100)
    description: str | None = None
    lead_user_id: int | None = None


class EmployeeTeamUpdate(BaseModel):
    """Update an existing team."""
    name: str | None = Field(default=None, min_length=1, max_length=100)
    description: str | None = None
    lead_user_id: int | None = None
    is_active: bool | None = None


class EmployeeTeamResponse(BaseModel):
    """Team response for list views."""
    id: int
    name: str
    description: str | None = None
    lead_user_id: int | None = None
    lead_name: str | None = None
    is_active: bool = True
    member_count: int = 0
    created_at: datetime | None = None
    updated_at: datetime | None = None


class TeamMemberResponse(BaseModel):
    """A member within a team."""
    id: int
    team_id: int
    user_id: int
    display_name: str
    avatar_url: str | None = None
    role: str = "member"
    user_is_active: bool = True
    joined_at: datetime | None = None


class EmployeeTeamDetailResponse(BaseModel):
    """Full team detail with member list."""
    id: int
    name: str
    description: str | None = None
    lead_user_id: int | None = None
    lead_name: str | None = None
    is_active: bool = True
    member_count: int = 0
    members: list[TeamMemberResponse] = Field(default_factory=list)
    created_at: datetime | None = None
    updated_at: datetime | None = None


class TeamMemberAdd(BaseModel):
    """Add a member to a team."""
    user_id: int
    role: TEAM_MEMBER_ROLE = "member"


class TeamMemberRoleUpdate(BaseModel):
    """Update a member's role in a team."""
    role: TEAM_MEMBER_ROLE
