"""
Pydantic models for Phase 11: Reports & Pre-Billing.

Covers response shapes for pre-billing, timesheets, labor overview,
and export generation endpoints.

NOTE: Labor sections report HOURS ONLY — no dollar amounts.
The bookkeeper handles actual bill-out rates externally.
"""

from __future__ import annotations

from pydantic import BaseModel, Field


# ── Pre-Billing ─────────────────────────────────────────────────────

class PreBillingLaborEntry(BaseModel):
    """Single labor entry in a pre-billing bundle — hours only, no dollar rate."""
    employee_id: int
    employee: str
    date: str
    clock_in: str | None = None
    clock_out: str | None = None
    regular_hours: float = 0
    overtime_hours: float = 0
    total_hours: float = 0
    bill_rate_type: str | None = None


class PreBillingPartItem(BaseModel):
    """Part consumed on a job for pre-billing."""
    part_id: int
    part_name: str
    part_code: str | None = None
    qty: int = 0
    unit_cost: float = 0
    sell_price: float = 0
    total_cost: float = 0
    total_sell: float = 0


class PreBillingMovement(BaseModel):
    """Stock movement related to the job."""
    date: str
    part_name: str
    from_location: str | None = None
    to_location: str | None = None
    qty: int = 0
    movement_type: str = "transfer"


class PreBillingSummary(BaseModel):
    """Totals for a pre-billing bundle.

    Labor is hours only — no dollar total. Parts include cost + sell.
    """
    total_labor_hours: float = 0
    total_regular_hours: float = 0
    total_overtime_hours: float = 0
    total_parts_cost: float = 0
    total_parts_sell: float = 0
    budget_limit: float | None = None
    budget_used_pct: float | None = None


class PreBillingBundle(BaseModel):
    """Complete pre-billing data for a job + date range."""
    job_id: int
    job_name: str
    job_number: str
    bill_rate_type: str | None = None
    period_start: str
    period_end: str
    labor: list[PreBillingLaborEntry] = Field(default_factory=list)
    parts: list[PreBillingPartItem] = Field(default_factory=list)
    movements: list[PreBillingMovement] = Field(default_factory=list)
    summary: PreBillingSummary = Field(default_factory=PreBillingSummary)


# ── Timesheets ──────────────────────────────────────────────────────

class TimesheetEntry(BaseModel):
    """Single clock entry in a timesheet."""
    id: int
    date: str
    job_id: int
    job_name: str
    job_number: str
    clock_in: str
    clock_out: str | None = None
    regular_hours: float = 0
    overtime_hours: float = 0
    total_hours: float = 0
    bill_rate_type: str | None = None
    gps_in: dict | None = None
    gps_out: dict | None = None


class TimesheetDayGroup(BaseModel):
    """Entries grouped by day."""
    date: str
    entries: list[TimesheetEntry] = Field(default_factory=list)
    total_hours: float = 0
    regular_hours: float = 0
    overtime_hours: float = 0


class TimesheetSummary(BaseModel):
    """Summary totals for a timesheet."""
    total_hours: float = 0
    regular_hours: float = 0
    overtime_hours: float = 0
    days_worked: int = 0
    jobs_worked: int = 0


class TimesheetReport(BaseModel):
    """Complete timesheet for an employee + date range."""
    employee_id: int | None = None
    employee_name: str | None = None
    period_start: str
    period_end: str
    group_by: str = "day"
    entries: list[TimesheetEntry] = Field(default_factory=list)
    day_groups: list[TimesheetDayGroup] = Field(default_factory=list)
    summary: TimesheetSummary = Field(default_factory=TimesheetSummary)


# ── Labor Overview ──────────────────────────────────────────────────

class LaborByEmployee(BaseModel):
    """Labor aggregated per employee."""
    employee_id: int
    employee: str
    total_hours: float = 0
    regular_hours: float = 0
    overtime_hours: float = 0
    jobs_worked: int = 0
    days_worked: int = 0
    avg_hours_per_day: float = 0


class LaborByJob(BaseModel):
    """Labor aggregated per job — hours only."""
    job_id: int
    job_name: str
    job_number: str
    total_hours: float = 0
    employee_count: int = 0


class LaborByBillRate(BaseModel):
    """Labor aggregated per bill rate type."""
    rate_type: str
    total_hours: float = 0
    entry_count: int = 0


class LaborOverviewTotals(BaseModel):
    """Top-level totals for labor overview."""
    total_hours: float = 0
    regular_hours: float = 0
    overtime_hours: float = 0
    total_employees: int = 0
    total_jobs: int = 0
    total_days: int = 0


class LaborOverviewReport(BaseModel):
    """Complete labor overview for a date range."""
    period_start: str
    period_end: str
    by_employee: list[LaborByEmployee] = Field(default_factory=list)
    by_job: list[LaborByJob] = Field(default_factory=list)
    by_bill_rate: list[LaborByBillRate] = Field(default_factory=list)
    totals: LaborOverviewTotals = Field(default_factory=LaborOverviewTotals)


# ── Exports ─────────────────────────────────────────────────────────

class ExportRequest(BaseModel):
    """Request to generate a downloadable export."""
    report_type: str = Field(..., pattern="^(pre-billing|timesheet|labor-overview)$")
    format: str = Field(..., pattern="^(csv|pdf)$")
    job_id: int | None = None
    employee_id: int | None = None
    start_date: str | None = None
    end_date: str | None = None
    group_by: str = "day"


# ── Billing Periods (Period Locking) ───────────────────────────────

class BillingPeriod(BaseModel):
    """A billing period that can be locked to prevent edits."""
    id: int
    job_id: int | None = None
    job_name: str | None = None
    job_number: str | None = None
    period_start: str
    period_end: str
    locked_at: str | None = None
    locked_by: int | None = None
    locked_by_name: str | None = None
    notes: str | None = None
    created_at: str | None = None


class BillingPeriodCreate(BaseModel):
    """Create a new billing period."""
    job_id: int | None = None
    period_start: str
    period_end: str
    notes: str | None = None


# ── Profitability Analysis ─────────────────────────────────────────

class JobProfitability(BaseModel):
    """Cost analysis for a single job."""
    job_id: int
    job_name: str
    job_number: str
    status: str = "active"
    labor_hours: float = 0
    labor_cost: float = 0           # hours × employee pay rate
    parts_cost: float = 0           # qty × weighted avg cost
    parts_sell: float = 0           # qty × company sell price
    total_cost: float = 0           # labor_cost + parts_cost
    parts_margin: float = 0         # parts_sell - parts_cost
    budget_limit: float | None = None
    budget_remaining: float | None = None
    budget_utilization_pct: float | None = None


class CompanyProfitabilityTotals(BaseModel):
    """Company-wide profitability summary."""
    total_labor_cost: float = 0
    total_parts_cost: float = 0
    total_parts_sell: float = 0
    total_combined_cost: float = 0
    total_parts_margin: float = 0
    total_labor_hours: float = 0
    jobs_under_budget: int = 0
    jobs_over_budget: int = 0
    jobs_no_budget: int = 0


class ProfitabilityReport(BaseModel):
    """Complete profitability analysis for a date range."""
    period_start: str
    period_end: str
    by_job: list[JobProfitability] = Field(default_factory=list)
    totals: CompanyProfitabilityTotals = Field(default_factory=CompanyProfitabilityTotals)


# ── Bookkeeper Exports ─────────────────────────────────────────────

class BookkeeperExportRequest(BaseModel):
    """Request a bookkeeper-formatted export."""
    format: str = Field(..., pattern="^(quickbooks|general_ledger|payroll)$")
    job_ids: list[int] | None = None
    period_start: str
    period_end: str
    include_labor: bool = True
    include_parts: bool = True
