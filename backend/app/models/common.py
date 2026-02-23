"""
Common Pydantic models shared across the application.

Contains base response wrappers, pagination, and utility models.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any, Generic, TypeVar

from pydantic import BaseModel, Field

T = TypeVar("T")


# ── Standard API Responses ──────────────────────────────────────────

class ApiResponse(BaseModel, Generic[T]):
    """Standard wrapper for all API responses.

    Every endpoint returns this shape so the frontend can rely on
    a consistent contract: { success, data?, message?, error? }
    """
    success: bool = True
    data: T | None = None
    message: str | None = None
    error: str | None = None


class PaginatedData(BaseModel, Generic[T]):
    """Paginated list response with metadata."""
    items: list[T] = Field(default_factory=list)
    total: int = 0
    page: int = 1
    page_size: int = 50
    total_pages: int = 0


# ── Common Field Models ─────────────────────────────────────────────

class TimestampMixin(BaseModel):
    """Fields present on most database entities."""
    created_at: datetime | None = None
    updated_at: datetime | None = None


class StatusMessage(BaseModel):
    """Simple status response for stubs and health checks."""
    status: str
    module: str | None = None
    message: str | None = None
