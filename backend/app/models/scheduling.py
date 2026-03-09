"""
Scheduling module Pydantic models — default schedules, time off,
dispatch assignments, subcontractor scheduling, and calendar assembly.

Covers all request/response shapes for the Scheduling management endpoints.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


# ── Shared Literals ───────────────────────────────────────────────

EXCEPTION_TYPES = Literal[
    "time_off", "sick", "vacation", "holiday",
    "modified_hours", "unpaid_leave",
    "jury_duty", "bereavement",
]

DISPATCH_ROLES = Literal["lead", "worker", "apprentice", "helper", "supervisor"]

DISPATCH_STATUSES = Literal[
    "scheduled", "confirmed", "on_site",
    "completed", "no_show", "cancelled",
]

SUB_SCHEDULE_STATUSES = Literal[
    "scheduled", "confirmed", "on_site",
    "completed", "cancelled", "no_show",
]


# ── Default Schedules ─────────────────────────────────────────────

class DefaultScheduleDay(BaseModel):
    """One day in a weekly schedule pattern."""
    day_of_week: int = Field(..., ge=0, le=6)  # 0=Sun, 6=Sat
    start_time: str = "07:00"
    end_time: str = "15:30"
    lunch_start: str | None = None
    lunch_end: str | None = None
    is_working_day: bool = True
    notes: str | None = None


class DefaultScheduleCreate(BaseModel):
    """Set the full 7-day default schedule for an employee."""
    days: list[DefaultScheduleDay] = Field(..., min_length=7, max_length=7)


class DefaultScheduleResponse(BaseModel):
    """Full weekly schedule returned from the API."""
    user_id: int
    user_name: str | None = None
    days: list[DefaultScheduleDayResponse] = Field(default_factory=list)


class DefaultScheduleDayResponse(BaseModel):
    """One day's schedule with its DB id."""
    id: int
    day_of_week: int
    start_time: str = "07:00"
    end_time: str = "15:30"
    lunch_start: str | None = None
    lunch_end: str | None = None
    is_working_day: bool = True
    notes: str | None = None


# ── Schedule Exceptions (Time Off) ────────────────────────────────

class ScheduleExceptionCreate(BaseModel):
    """Request time off or another schedule exception."""
    exception_date: str = Field(..., min_length=10, max_length=10)  # YYYY-MM-DD
    exception_type: EXCEPTION_TYPES
    start_time: str | None = None  # NULL = full day
    end_time: str | None = None
    lunch_start: str | None = None
    lunch_end: str | None = None
    reason: str | None = None
    notes: str | None = None


class ScheduleExceptionUpdate(BaseModel):
    """Partial update for a schedule exception."""
    exception_type: EXCEPTION_TYPES | None = None
    start_time: str | None = None
    end_time: str | None = None
    lunch_start: str | None = None
    lunch_end: str | None = None
    reason: str | None = None
    notes: str | None = None


class ScheduleExceptionResponse(BaseModel):
    """Schedule exception returned from the API."""
    id: int
    user_id: int
    user_name: str | None = None
    exception_date: str
    exception_type: str
    start_time: str | None = None
    end_time: str | None = None
    lunch_start: str | None = None
    lunch_end: str | None = None
    is_approved: bool = False
    approved_by: int | None = None
    approved_by_name: str | None = None
    approved_at: str | None = None
    reason: str | None = None
    notes: str | None = None
    created_at: datetime | None = None


# ── Dispatch ──────────────────────────────────────────────────────

class DispatchCreate(BaseModel):
    """Dispatch a single employee to a job for a date."""
    job_id: int
    user_id: int
    dispatch_date: str = Field(..., min_length=10, max_length=10)
    shift_start: str | None = None
    shift_end: str | None = None
    lunch_start: str | None = None
    lunch_end: str | None = None
    role_on_job: DISPATCH_ROLES = "worker"
    notes: str | None = None


class BulkDispatchCreate(BaseModel):
    """Dispatch multiple employees to a job for a date."""
    job_id: int
    dispatch_date: str = Field(..., min_length=10, max_length=10)
    user_ids: list[int] = Field(..., min_length=1)
    shift_start: str | None = None
    shift_end: str | None = None
    lunch_start: str | None = None
    lunch_end: str | None = None
    role_on_job: DISPATCH_ROLES = "worker"
    notes: str | None = None


class TeamDispatchCreate(BaseModel):
    """Dispatch an entire employee team to a job for a date."""
    job_id: int
    team_id: int
    dispatch_date: str = Field(..., min_length=10, max_length=10)
    shift_start: str | None = None
    shift_end: str | None = None
    lunch_start: str | None = None
    lunch_end: str | None = None
    role_on_job: DISPATCH_ROLES = "worker"
    notes: str | None = None


class DispatchUpdate(BaseModel):
    """Partial update for a dispatch assignment."""
    shift_start: str | None = None
    shift_end: str | None = None
    lunch_start: str | None = None
    lunch_end: str | None = None
    role_on_job: DISPATCH_ROLES | None = None
    status: DISPATCH_STATUSES | None = None
    notes: str | None = None


class DispatchResponse(BaseModel):
    """Dispatch assignment returned from the API."""
    id: int
    job_id: int
    job_name: str | None = None
    user_id: int
    user_name: str | None = None
    dispatch_date: str
    shift_start: str | None = None
    shift_end: str | None = None
    lunch_start: str | None = None
    lunch_end: str | None = None
    role_on_job: str = "worker"
    status: str = "scheduled"
    dispatched_by: int | None = None
    dispatched_by_name: str | None = None
    notes: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


class DailyDispatchView(BaseModel):
    """Summary of all dispatches for a single date."""
    date: str
    dispatches: list[DispatchResponse] = Field(default_factory=list)
    available_employees: list[AvailableEmployee] = Field(default_factory=list)


class AvailableEmployee(BaseModel):
    """Employee available for dispatch on a given date."""
    id: int
    display_name: str
    default_start: str | None = None
    default_end: str | None = None
    current_dispatches: int = 0  # how many jobs already assigned today


# ── Conflict Detection ────────────────────────────────────────────

class ScheduleConflict(BaseModel):
    """One conflict preventing or warning about a dispatch."""
    conflict_type: str  # 'already_dispatched', 'time_off', 'not_working_day'
    description: str
    related_job_id: int | None = None
    related_job_name: str | None = None
    shift_start: str | None = None
    shift_end: str | None = None
    role_on_job: str | None = None


# ── Subcontractor Schedules ───────────────────────────────────────

class SubScheduleCreate(BaseModel):
    """Schedule a subcontractor (GC) to visit a job site."""
    job_id: int
    gc_id: int
    scheduled_date: str = Field(..., min_length=10, max_length=10)
    arrival_time: str | None = None
    departure_time: str | None = None
    work_description: str | None = None
    notes: str | None = None


class SubScheduleUpdate(BaseModel):
    """Partial update for a subcontractor schedule entry."""
    scheduled_date: str | None = Field(default=None, min_length=10, max_length=10)
    arrival_time: str | None = None
    departure_time: str | None = None
    work_description: str | None = None
    status: SUB_SCHEDULE_STATUSES | None = None
    notes: str | None = None


class SubScheduleResponse(BaseModel):
    """Subcontractor schedule entry returned from the API."""
    id: int
    job_id: int
    job_name: str | None = None
    gc_id: int
    gc_name: str | None = None
    gc_code: str | None = None
    scheduled_date: str
    arrival_time: str | None = None
    departure_time: str | None = None
    work_description: str | None = None
    status: str = "scheduled"
    notes: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


# ── Calendar Assembly ─────────────────────────────────────────────

class CalendarEntry(BaseModel):
    """One entry in the assembled calendar view."""
    date: str
    entry_type: str  # 'dispatch', 'time_off', 'sub_schedule'
    user_id: int | None = None
    user_name: str | None = None
    job_id: int | None = None
    job_name: str | None = None
    gc_id: int | None = None
    gc_name: str | None = None
    status: str | None = None
    role_on_job: str | None = None  # for dispatch entries
    label: str = ""  # human-readable summary


class CalendarData(BaseModel):
    """Assembled calendar data for a date range."""
    date_from: str
    date_to: str
    entries: list[CalendarEntry] = Field(default_factory=list)


# ── Dispatch Templates ──────────────────────────────────────────

class DispatchTemplateMember(BaseModel):
    """One crew member in a dispatch template."""
    user_id: int
    role_on_job: DISPATCH_ROLES = "worker"


class DispatchTemplateCreate(BaseModel):
    """Create a recurring dispatch template."""
    name: str = Field(..., min_length=1, max_length=200)
    job_id: int
    shift_start: str | None = None
    shift_end: str | None = None
    lunch_start: str | None = None
    lunch_end: str | None = None
    role_on_job: DISPATCH_ROLES = "worker"
    days_of_week: int = Field(62, ge=0, le=127)  # bitmask: bit0=Sun..bit6=Sat
    members: list[DispatchTemplateMember] = Field(default_factory=list)
    notes: str | None = None


class DispatchTemplateUpdate(BaseModel):
    """Partial update for a dispatch template."""
    name: str | None = None
    job_id: int | None = None
    shift_start: str | None = None
    shift_end: str | None = None
    lunch_start: str | None = None
    lunch_end: str | None = None
    role_on_job: DISPATCH_ROLES | None = None
    days_of_week: int | None = Field(default=None, ge=0, le=127)
    members: list[DispatchTemplateMember] | None = None
    notes: str | None = None


class DispatchTemplateResponse(BaseModel):
    """Dispatch template returned from the API."""
    id: int
    name: str
    job_id: int
    job_name: str | None = None
    shift_start: str | None = None
    shift_end: str | None = None
    lunch_start: str | None = None
    lunch_end: str | None = None
    role_on_job: str = "worker"
    days_of_week: int = 62
    days_labels: list[str] = Field(default_factory=list)  # e.g. ["Mon","Tue",...]
    members: list[DispatchTemplateMemberResponse] = Field(default_factory=list)
    notes: str | None = None
    is_active: bool = True
    created_at: datetime | None = None


class DispatchTemplateMemberResponse(BaseModel):
    """Template member with user name."""
    user_id: int
    user_name: str | None = None
    role_on_job: str = "worker"


class DispatchTemplateApply(BaseModel):
    """Apply a template to generate dispatches for a date range."""
    date_from: str = Field(..., min_length=10, max_length=10)
    date_to: str = Field(..., min_length=10, max_length=10)
    skip_conflicts: bool = False  # if True, skip dates with conflicts


# ── Shift Patterns ───────────────────────────────────────────────

class ShiftPatternDayCreate(BaseModel):
    """One day in a shift pattern."""
    day_of_week: int = Field(..., ge=0, le=6)
    start_time: str = "07:00"
    end_time: str = "15:30"
    lunch_start: str | None = None
    lunch_end: str | None = None
    is_working_day: bool = True


class ShiftPatternCreate(BaseModel):
    """Create a named shift pattern."""
    name: str = Field(..., min_length=1, max_length=100)
    description: str | None = None
    days: list[ShiftPatternDayCreate] = Field(..., min_length=7, max_length=7)


class ShiftPatternUpdate(BaseModel):
    """Partial update for a shift pattern."""
    name: str | None = None
    description: str | None = None
    days: list[ShiftPatternDayCreate] | None = None


class ShiftPatternDayResponse(BaseModel):
    """One day in a shift pattern response."""
    id: int
    day_of_week: int
    start_time: str
    end_time: str
    lunch_start: str | None = None
    lunch_end: str | None = None
    is_working_day: bool


class ShiftPatternResponse(BaseModel):
    """Named shift pattern returned from the API."""
    id: int
    name: str
    description: str | None = None
    is_active: bool = True
    days: list[ShiftPatternDayResponse] = Field(default_factory=list)
    created_at: datetime | None = None
