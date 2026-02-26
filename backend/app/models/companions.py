"""
Companion Rules, Suggestions, Co-Occurrence, and Part Alternatives models.

Covers all request/response schemas for:
- Companion Rules (category-level linking with sources/targets)
- Companion Suggestions (generated/pending/approved/discarded)
- Co-occurrence learning (from historical job consumption)
- Companion feedback (for learning loop)
- Part Alternatives (individual part cross-linking)
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


# =================================================================
# COMPANION RULES — user-defined category relationships
# =================================================================

class CompanionRuleSourceCreate(BaseModel):
    """A single source entry in a companion rule."""
    category_id: int
    style_id: int | None = None


class CompanionRuleTargetCreate(BaseModel):
    """A single target entry in a companion rule."""
    category_id: int
    style_id: int | None = None


class CompanionRuleCreate(BaseModel):
    """Request body for creating a companion rule with sources + targets."""
    name: str = Field(..., min_length=1, max_length=200)
    description: str | None = None
    style_match: Literal["auto", "any", "explicit"] = "auto"
    qty_mode: Literal["sum", "max", "ratio"] = "sum"
    qty_ratio: float = 1.0
    is_active: bool = True
    sources: list[CompanionRuleSourceCreate] = Field(..., min_length=1)
    targets: list[CompanionRuleTargetCreate] = Field(..., min_length=1)


class CompanionRuleUpdate(BaseModel):
    """Request body for updating a companion rule. Full replace of sources/targets."""
    name: str | None = Field(None, min_length=1, max_length=200)
    description: str | None = None
    style_match: Literal["auto", "any", "explicit"] | None = None
    qty_mode: Literal["sum", "max", "ratio"] | None = None
    qty_ratio: float | None = None
    is_active: bool | None = None
    sources: list[CompanionRuleSourceCreate] | None = None
    targets: list[CompanionRuleTargetCreate] | None = None


class CompanionRuleSourceResponse(BaseModel):
    """A resolved source in a rule response (with names)."""
    id: int
    category_id: int
    category_name: str | None = None
    style_id: int | None = None
    style_name: str | None = None


class CompanionRuleTargetResponse(BaseModel):
    """A resolved target in a rule response (with names)."""
    id: int
    category_id: int
    category_name: str | None = None
    style_id: int | None = None
    style_name: str | None = None


class CompanionRuleResponse(BaseModel):
    """Full companion rule as returned from the API."""
    id: int
    name: str
    description: str | None = None
    style_match: str = "auto"
    qty_mode: str = "sum"
    qty_ratio: float = 1.0
    is_active: bool = True
    sources: list[CompanionRuleSourceResponse] = []
    targets: list[CompanionRuleTargetResponse] = []
    created_by: int | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


# =================================================================
# COMPANION SUGGESTIONS — generated/pending/approved/discarded
# =================================================================

class SuggestionSourceResponse(BaseModel):
    """A source item that triggered a suggestion."""
    id: int
    category_id: int
    category_name: str | None = None
    style_id: int | None = None
    style_name: str | None = None
    qty: int


class CompanionSuggestionResponse(BaseModel):
    """A generated suggestion as returned from the API."""
    id: int
    rule_id: int | None = None
    target_category_id: int
    target_style_id: int | None = None
    target_description: str
    suggested_qty: int
    approved_qty: int | None = None
    reason_type: str = "rule"
    reason_text: str
    status: str = "pending"
    sources: list[SuggestionSourceResponse] = []
    triggered_by: int | None = None
    decided_by: int | None = None
    decided_at: datetime | None = None
    order_id: int | None = None
    notes: str | None = None
    created_at: datetime | None = None


class SuggestionDecisionRequest(BaseModel):
    """Request body for approving or discarding a suggestion."""
    action: Literal["approved", "discarded"]
    approved_qty: int | None = None  # Override qty (only for approve)
    notes: str | None = None


class SuggestionListParams(BaseModel):
    """Query parameters for listing suggestions."""
    status: Literal["pending", "approved", "discarded"] | None = None
    page: int = Field(default=1, ge=1)
    page_size: int = Field(default=50, ge=1, le=200)


# =================================================================
# MANUAL TRIGGER — "What should I also order?"
# =================================================================

class ManualTriggerItem(BaseModel):
    """A single item in the manual trigger input."""
    category_id: int
    style_id: int | None = None
    qty: int = Field(..., ge=1)


class ManualTriggerRequest(BaseModel):
    """Request body for manually triggering suggestion generation."""
    items: list[ManualTriggerItem] = Field(..., min_length=1)


# =================================================================
# CO-OCCURRENCE — learned patterns from job consumption
# =================================================================

class CoOccurrencePairResponse(BaseModel):
    """A learned co-occurrence pair as returned from the API."""
    id: int
    category_a_id: int
    category_a_name: str | None = None
    category_b_id: int
    category_b_name: str | None = None
    co_occurrence_count: int = 0
    total_jobs_a: int = 0
    total_jobs_b: int = 0
    avg_ratio_a_to_b: float = 1.0
    confidence: float = 0.0
    last_computed: datetime | None = None


# =================================================================
# COMPANION STATS — KPI summary
# =================================================================

class CompanionStats(BaseModel):
    """Summary counts for the companion dashboard KPI cards."""
    total_rules: int = 0
    active_rules: int = 0
    pending_suggestions: int = 0
    approved_count: int = 0
    discarded_count: int = 0
    co_occurrence_pairs: int = 0


# =================================================================
# PART ALTERNATIVES — individual part cross-linking
# =================================================================

class PartAlternativeCreate(BaseModel):
    """Request body for linking an alternative part."""
    alternative_part_id: int
    relationship: Literal["substitute", "upgrade", "compatible"] = "substitute"
    preference: int = Field(default=0, ge=0)
    notes: str | None = None


class PartAlternativeUpdate(BaseModel):
    """Request body for updating an alternative link."""
    relationship: Literal["substitute", "upgrade", "compatible"] | None = None
    preference: int | None = Field(default=None, ge=0)
    notes: str | None = None


class PartAlternativeResponse(BaseModel):
    """A part alternative link with resolved part details."""
    id: int
    part_id: int
    part_name: str | None = None
    part_code: str | None = None
    alternative_part_id: int
    alternative_name: str | None = None
    alternative_code: str | None = None
    alternative_brand_name: str | None = None
    relationship: str = "substitute"
    preference: int = 0
    notes: str | None = None
    created_by: int | None = None
    created_at: datetime | None = None
