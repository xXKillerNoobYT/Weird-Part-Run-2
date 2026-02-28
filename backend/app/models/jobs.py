"""
Pydantic models for Jobs, Labor, Clock-Out Questions, and Daily Reports.

Covers all request/response shapes for Phase 4 endpoints.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field


# ── Bill Rate Types ───────────────────────────────────────────────────

class BillRateTypeCreate(BaseModel):
    """Create a new bill rate type."""
    name: str = Field(..., min_length=1, max_length=100)
    description: str | None = None


class BillRateTypeUpdate(BaseModel):
    """Update a bill rate type."""
    name: str | None = Field(None, min_length=1, max_length=100)
    description: str | None = None
    is_active: bool | None = None


class BillRateTypeResponse(BaseModel):
    """Bill rate type lookup entry."""
    id: int
    name: str
    description: str | None = None
    sort_order: int = 0
    is_active: bool = True
    created_at: str | None = None


# ── Jobs ──────────────────────────────────────────────────────────────

class JobCreate(BaseModel):
    """Create a new job."""
    job_number: str
    job_name: str
    customer_name: str
    address_line1: str | None = None
    address_line2: str | None = None
    city: str | None = None
    state: str | None = None
    zip: str | None = None
    gps_lat: float | None = None
    gps_lng: float | None = None
    status: str = "active"
    priority: str = "normal"
    job_type: str = "service"
    bill_rate_type_id: int | None = None
    lead_user_id: int | None = None
    start_date: str | None = None
    due_date: str | None = None
    notes: str | None = None
    # On Call / Warranty sub-type fields
    on_call_type: str | None = None  # 'on_call' or 'warranty'
    warranty_start_date: str | None = None
    warranty_end_date: str | None = None


class JobUpdate(BaseModel):
    """Update an existing job. All fields optional."""
    job_name: str | None = None
    customer_name: str | None = None
    status: str | None = None
    address_line1: str | None = None
    address_line2: str | None = None
    city: str | None = None
    state: str | None = None
    zip: str | None = None
    gps_lat: float | None = None
    gps_lng: float | None = None
    priority: str | None = None
    job_type: str | None = None
    bill_rate_type_id: int | None = None
    lead_user_id: int | None = None
    start_date: str | None = None
    due_date: str | None = None
    notes: str | None = None
    # On Call / Warranty sub-type fields
    on_call_type: str | None = None
    warranty_start_date: str | None = None
    warranty_end_date: str | None = None


class JobStatusUpdate(BaseModel):
    """Change job status (separate from general update for audit trail)."""
    # pending, active, on_hold, completed, cancelled,
    # continuous_maintenance, on_call
    status: str


class JobResponse(BaseModel):
    """Full job detail response."""
    id: int
    job_number: str
    job_name: str
    customer_name: str
    address_line1: str | None = None
    address_line2: str | None = None
    city: str | None = None
    state: str | None = None
    zip: str | None = None
    gps_lat: float | None = None
    gps_lng: float | None = None
    status: str
    priority: str
    job_type: str
    bill_rate_type_id: int | None = None
    bill_rate_type_name: str | None = None
    lead_user_id: int | None = None
    lead_user_name: str | None = None
    start_date: str | None = None
    due_date: str | None = None
    completed_date: str | None = None
    notes: str | None = None
    # On Call / Warranty sub-type fields
    on_call_type: str | None = None
    warranty_start_date: str | None = None
    warranty_end_date: str | None = None
    warranty_days_remaining: int | None = None  # computed by service layer
    created_at: str | None = None
    updated_at: str | None = None
    # Aggregated stats (populated by service layer)
    total_labor_hours: float | None = None
    total_parts_cost: float | None = None
    active_workers: int | None = None
    # Notebook task aggregation
    open_task_count: int = 0
    task_summary: dict | None = None

    # Formatted address for display
    @property
    def full_address(self) -> str | None:
        parts = [
            self.address_line1,
            self.address_line2,
            ", ".join(filter(None, [self.city, self.state])),
            self.zip,
        ]
        addr = " ".join(filter(None, parts))
        return addr if addr.strip() else None


class JobListItem(BaseModel):
    """Lightweight job for list views."""
    id: int
    job_number: str
    job_name: str
    customer_name: str
    address_line1: str | None = None
    city: str | None = None
    state: str | None = None
    zip: str | None = None
    gps_lat: float | None = None
    gps_lng: float | None = None
    status: str
    priority: str
    job_type: str
    bill_rate_type_name: str | None = None
    lead_user_name: str | None = None
    # On Call / Warranty sub-type (for displaying sub-type in lists)
    on_call_type: str | None = None
    warranty_end_date: str | None = None
    active_workers: int = 0
    total_labor_hours: float = 0
    total_parts_cost: float = 0
    open_task_count: int = 0
    created_at: str | None = None


# ── Labor Entries ─────────────────────────────────────────────────────

class ClockInRequest(BaseModel):
    """Clock in to a job."""
    gps_lat: float | None = None
    gps_lng: float | None = None
    # photo_path handled via file upload separately


class ClockOutRequest(BaseModel):
    """Clock out — includes GPS, optional photo, and question responses."""
    labor_entry_id: int
    gps_lat: float | None = None
    gps_lng: float | None = None
    drive_time_minutes: int = 0
    notes: str | None = None
    # Responses to global clock-out questions
    responses: list[ClockOutResponseInput] = Field(default_factory=list)
    # Answers to one-time questions
    one_time_answers: list[OneTimeAnswerInput] = Field(default_factory=list)


class ClockOutResponseInput(BaseModel):
    """Single answer to a global clock-out question."""
    question_id: int
    answer_text: str | None = None
    answer_bool: bool | None = None
    # photo_path handled via file upload


class OneTimeAnswerInput(BaseModel):
    """Answer to a one-time per-job question."""
    question_id: int
    answer_text: str | None = None
    # photo_path handled via file upload


class LaborEntryResponse(BaseModel):
    """Labor entry with user and job context."""
    id: int
    user_id: int
    user_name: str | None = None
    job_id: int
    job_name: str | None = None
    job_number: str | None = None
    clock_in: str
    clock_out: str | None = None
    regular_hours: float | None = None
    overtime_hours: float | None = None
    drive_time_minutes: int = 0
    clock_in_gps_lat: float | None = None
    clock_in_gps_lng: float | None = None
    clock_out_gps_lat: float | None = None
    clock_out_gps_lng: float | None = None
    clock_in_photo_path: str | None = None
    clock_out_photo_path: str | None = None
    status: str
    notes: str | None = None
    created_at: str | None = None


class ActiveClockResponse(BaseModel):
    """Current user's active clock-in, if any."""
    is_clocked_in: bool
    entry: LaborEntryResponse | None = None


# ── Clock-Out Questions ───────────────────────────────────────────────

class ClockOutQuestionCreate(BaseModel):
    """Create or update a global clock-out question."""
    question_text: str
    answer_type: str = "text"  # text, yes_no, photo
    is_required: bool = True
    sort_order: int = 0


class ClockOutQuestionResponse(BaseModel):
    """Global clock-out question definition."""
    id: int
    question_text: str
    answer_type: str
    is_required: bool
    sort_order: int
    is_active: bool
    created_at: str | None = None


class QuestionReorderRequest(BaseModel):
    """Reorder questions by providing ordered list of IDs."""
    ordered_ids: list[int]


# ── One-Time Questions ────────────────────────────────────────────────

class OneTimeQuestionCreate(BaseModel):
    """Boss creates a one-time question for a specific job/worker."""
    question_text: str
    answer_type: str = "text"
    target_user_id: int | None = None  # NULL = ask everyone


class OneTimeQuestionResponse(BaseModel):
    """One-time question with current status."""
    id: int
    job_id: int
    target_user_id: int | None = None
    target_user_name: str | None = None
    question_text: str
    answer_type: str
    status: str
    created_by: int
    created_by_name: str | None = None
    answered_by: int | None = None
    answer_text: str | None = None
    answer_photo_path: str | None = None
    created_at: str | None = None
    answered_at: str | None = None


# ── Clock-Out Bundle ──────────────────────────────────────────────────

class ClockOutBundle(BaseModel):
    """Everything needed for the clock-out flow UI.

    Combines global questions + pending one-time questions into a single
    payload so the frontend can render the full questionnaire in one fetch.
    """
    global_questions: list[ClockOutQuestionResponse] = Field(default_factory=list)
    one_time_questions: list[OneTimeQuestionResponse] = Field(default_factory=list)


# ── Job Parts ─────────────────────────────────────────────────────────

class JobPartConsumeRequest(BaseModel):
    """Record parts consumed on a job."""
    part_id: int
    qty_consumed: int
    notes: str | None = None


class JobPartResponse(BaseModel):
    """Part consumed on a job."""
    id: int
    job_id: int
    part_id: int
    part_name: str | None = None
    part_code: str | None = None
    qty_consumed: int
    qty_returned: int
    unit_cost_at_consume: float | None = None
    unit_sell_at_consume: float | None = None
    consumed_by: int | None = None
    consumed_by_name: str | None = None
    consumed_at: str | None = None
    notes: str | None = None


# ── Daily Reports ─────────────────────────────────────────────────────

class DailyReportResponse(BaseModel):
    """Daily report metadata (without the full JSON blob)."""
    id: int
    job_id: int
    job_name: str | None = None
    job_number: str | None = None
    report_date: str
    status: str
    generated_at: str | None = None
    reviewed_by: int | None = None
    reviewed_at: str | None = None
    # Summary fields extracted from report_json
    worker_count: int = 0
    total_labor_hours: float = 0
    total_parts_cost: float = 0


class DailyReportFull(BaseModel):
    """Full daily report including the rendered JSON data."""
    id: int
    job_id: int
    job_name: str | None = None
    job_number: str | None = None
    report_date: str
    status: str
    generated_at: str | None = None
    report_data: dict[str, Any] = Field(default_factory=dict)
