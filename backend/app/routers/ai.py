"""
AI routes — Local LLM assistant via LM Studio.

Endpoints:
  POST /api/ai/ask                  — Ask a question (NL query with tool calling)
  POST /api/ai/summarize            — Summarize report data
  GET  /api/ai/anomalies            — Get cached anomaly flags
  GET  /api/ai/predictions          — Get cached ordering predictions
  GET  /api/ai/status               — Check LM Studio connectivity + model info
  GET  /api/ai/prompts              — Get context-aware suggested prompts
  POST /api/ai/anomalies/dismiss    — Dismiss an anomaly
  POST /api/ai/anomalies/refresh    — Force re-run anomaly detection now
  POST /api/ai/predictions/refresh  — Force re-run prediction generation now
  GET  /api/ai/anomaly-count        — Badge count for AI panel

All AI endpoints require the use_ai permission except anomaly-count
(which just returns a number for the badge indicator).
"""

from __future__ import annotations

import logging
from typing import Any

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse
from app.services.ai_service import AiService, get_context_prompts

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/ai", tags=["AI"])


# ── Request / Response Models ────────────────────────────────────

class AskRequest(BaseModel):
    """Natural language question with optional conversation history."""
    question: str = Field(..., min_length=1, max_length=2000)
    conversation_history: list[dict[str, str]] | None = None
    page_context: str | None = None  # e.g. "jobs", "warehouse", "dashboard"


class AskResponse(BaseModel):
    answer: str
    tool_calls_made: int = 0
    model: str = "unknown"


class SummarizeRequest(BaseModel):
    report_type: str = Field(..., description="daily, weekly, job_cost, pre_billing")
    data: dict[str, Any] = Field(..., description="Report data to summarize")


class SummarizeResponse(BaseModel):
    summary: str
    model: str = "unknown"


class DismissRequest(BaseModel):
    result_id: int


class ConnectionStatus(BaseModel):
    status: str  # connected, unreachable, error
    url: str
    models: list[str] = []
    model_count: int = 0
    error: str | None = None


class CachedResult(BaseModel):
    id: int
    category: str
    title: str
    body: str
    severity: str | None = None
    context_json: str | None = None
    is_dismissed: int = 0
    created_at: str
    expires_at: str | None = None


class PromptsResponse(BaseModel):
    page_context: str
    prompts: list[str]


# ── Endpoints ────────────────────────────────────────────────────

@router.get(
    "/status",
    response_model=ApiResponse[ConnectionStatus],
)
async def get_ai_status(
    _user=Depends(require_permission("use_ai")),
    db: aiosqlite.Connection = Depends(get_db),
) -> ApiResponse[ConnectionStatus]:
    """Check LM Studio connectivity and list available models."""
    svc = AiService(db)
    result = await svc.check_connection()
    return ApiResponse(data=ConnectionStatus(**result))


@router.post(
    "/ask",
    response_model=ApiResponse[AskResponse],
)
async def ask_question(
    body: AskRequest,
    _user=Depends(require_permission("use_ai")),
    db: aiosqlite.Connection = Depends(get_db),
) -> ApiResponse[AskResponse]:
    """Ask a natural language question. Supports tool-calling for data lookups."""
    svc = AiService(db)
    result = await svc.ask(
        question=body.question,
        conversation_history=body.conversation_history,
        page_context=body.page_context,
    )
    return ApiResponse(data=AskResponse(**result))


@router.post(
    "/summarize",
    response_model=ApiResponse[SummarizeResponse],
)
async def summarize_report(
    body: SummarizeRequest,
    _user=Depends(require_permission("use_ai")),
    db: aiosqlite.Connection = Depends(get_db),
) -> ApiResponse[SummarizeResponse]:
    """Generate a natural language summary of report data."""
    svc = AiService(db)
    result = await svc.summarize_report(body.report_type, body.data)
    return ApiResponse(data=SummarizeResponse(**result))


@router.get(
    "/anomalies",
    response_model=ApiResponse[list[CachedResult]],
)
async def get_anomalies(
    include_dismissed: bool = Query(False),
    _user=Depends(require_permission("use_ai")),
    db: aiosqlite.Connection = Depends(get_db),
) -> ApiResponse[list[CachedResult]]:
    """Get cached anomaly detection results."""
    svc = AiService(db)
    results = await svc.get_cached_anomalies(include_dismissed=include_dismissed)
    return ApiResponse(data=[CachedResult(**r) for r in results])


@router.get(
    "/predictions",
    response_model=ApiResponse[list[CachedResult]],
)
async def get_predictions(
    _user=Depends(require_permission("use_ai")),
    db: aiosqlite.Connection = Depends(get_db),
) -> ApiResponse[list[CachedResult]]:
    """Get cached ordering predictions."""
    svc = AiService(db)
    results = await svc.get_cached_predictions()
    return ApiResponse(data=[CachedResult(**r) for r in results])


@router.post(
    "/anomalies/dismiss",
    response_model=ApiResponse[dict],
)
async def dismiss_anomaly(
    body: DismissRequest,
    user=Depends(require_permission("use_ai")),
    db: aiosqlite.Connection = Depends(get_db),
) -> ApiResponse[dict]:
    """Dismiss a cached anomaly so it no longer appears in the list."""
    svc = AiService(db)
    dismissed = await svc.dismiss_cached_result(body.result_id, user.id)
    if not dismissed:
        raise HTTPException(status_code=404, detail="Result not found or already dismissed")
    return ApiResponse(data={"dismissed": True})


@router.post(
    "/anomalies/refresh",
    response_model=ApiResponse[list[CachedResult]],
)
async def refresh_anomalies(
    _user=Depends(require_permission("use_ai")),
    db: aiosqlite.Connection = Depends(get_db),
) -> ApiResponse[list[CachedResult]]:
    """Force re-run anomaly detection now (instead of waiting for scheduled job)."""
    svc = AiService(db)
    anomalies = await svc.detect_anomalies()
    results = await svc.get_cached_anomalies()
    return ApiResponse(
        data=[CachedResult(**r) for r in results],
        message=f"Detected {len(anomalies)} anomalies",
    )


@router.post(
    "/predictions/refresh",
    response_model=ApiResponse[list[CachedResult]],
)
async def refresh_predictions(
    days_ahead: int = Query(30, ge=7, le=90),
    _user=Depends(require_permission("use_ai")),
    db: aiosqlite.Connection = Depends(get_db),
) -> ApiResponse[list[CachedResult]]:
    """Force re-run ordering predictions now."""
    svc = AiService(db)
    predictions = await svc.predict_ordering(days_ahead=days_ahead)
    results = await svc.get_cached_predictions()
    return ApiResponse(
        data=[CachedResult(**r) for r in results],
        message=f"Generated {len(predictions)} predictions",
    )


@router.get(
    "/prompts",
    response_model=ApiResponse[PromptsResponse],
)
async def get_prompts(
    page_context: str = Query("default", description="Current page context"),
    _user=Depends(require_permission("use_ai")),
    db: aiosqlite.Connection = Depends(get_db),
) -> ApiResponse[PromptsResponse]:
    """Get context-aware suggested prompts for the current page."""
    prompts = get_context_prompts(page_context)
    return ApiResponse(data=PromptsResponse(page_context=page_context, prompts=prompts))


@router.get(
    "/anomaly-count",
    response_model=ApiResponse[dict],
)
async def get_anomaly_count(
    _user=Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
) -> ApiResponse[dict]:
    """Get count of active anomalies (for badge indicator). Requires basic auth only."""
    svc = AiService(db)
    count = await svc.get_anomaly_count()
    return ApiResponse(data={"count": count})
