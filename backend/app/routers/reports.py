"""
Reports routes — pre-billing, timesheets, labor overview, exports.

Phase 11: Full implementation with real data queries against existing tables.
No new migrations needed — all data already exists.
"""

from __future__ import annotations

import csv
import io
import json
import logging
import secrets
import zipfile
from datetime import date, datetime, timedelta

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse

from app.database import get_db
from app.middleware.auth import require_permission
from app.models.common import ApiResponse
from app.models.reports import (
    BillingPeriod,
    BillingPeriodCreate,
    BookkeeperExportRequest,
    CompanyProfitabilityTotals,
    ExportBundleRequest,
    ExportRequest,
    JobProfitability,
    LaborByBillRate,
    LaborByEmployee,
    LaborByJob,
    LaborOverviewReport,
    LaborOverviewTotals,
    PreBillingBundle,
    PreBillingLaborEntry,
    PreBillingMovement,
    PreBillingPartItem,
    PreBillingSummary,
    ProfitabilityReport,
    ReportAnnotationCreate,
    ReportAnnotationResponse,
    ReportAnnotationUpdate,
    ReportShareTokenCreate,
    ReportShareTokenResponse,
    ReportTemplateCreate,
    ReportTemplateResponse,
    ReportTemplateUpdate,
    TimesheetDayGroup,
    TimesheetEntry,
    TimesheetReport,
    TimesheetSummary,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/reports", tags=["Reports"])


# ═══════════════════════════════════════════════════════════════════
# Endpoint 1: Pre-Billing
# ═══════════════════════════════════════════════════════════════════

@router.get("/pre-billing", response_model=ApiResponse[PreBillingBundle])
async def pre_billing(
    job_id: int = Query(..., description="Job to generate pre-billing for"),
    start_date: str = Query(..., description="Period start (YYYY-MM-DD)"),
    end_date: str = Query(..., description="Period end (YYYY-MM-DD)"),
    user: dict = Depends(require_permission("view_reports")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Pre-billing bundle: labor, parts, movements, and cost summary for a job."""

    # Validate job exists
    cursor = await db.execute(
        """SELECT j.id, j.job_name, j.job_number,
                  j.budget_limit, brt.name AS bill_rate_type_name
           FROM jobs j
           LEFT JOIN bill_rate_types brt ON brt.id = j.bill_rate_type_id
           WHERE j.id = ?""",
        (job_id,),
    )
    job = await cursor.fetchone()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    # ── Labor entries (hours only — bookkeeper handles rates) ──
    cursor = await db.execute(
        """SELECT le.id, le.user_id, u.display_name, DATE(le.clock_in) AS work_date,
                  le.clock_in, le.clock_out,
                  COALESCE(le.regular_hours, 0) AS regular_hours,
                  COALESCE(le.overtime_hours, 0) AS overtime_hours,
                  brt.name AS bill_rate_type_name
           FROM labor_entries le
           JOIN users u ON u.id = le.user_id
           LEFT JOIN jobs j2 ON j2.id = le.job_id
           LEFT JOIN bill_rate_types brt ON brt.id = j2.bill_rate_type_id
           WHERE le.job_id = ?
             AND le.status IN ('clocked_out', 'edited', 'approved')
             AND DATE(le.clock_in) >= ? AND DATE(le.clock_in) <= ?
           ORDER BY le.clock_in ASC""",
        (job_id, start_date, end_date),
    )
    labor_rows = await cursor.fetchall()

    labor_entries = []
    total_labor_hours = 0.0
    total_reg_hours = 0.0
    total_ot_hours = 0.0

    for row in labor_rows:
        reg = row["regular_hours"]
        ot = row["overtime_hours"]
        total_h = round(reg + ot, 2)
        total_labor_hours += total_h
        total_reg_hours += reg
        total_ot_hours += ot

        labor_entries.append(PreBillingLaborEntry(
            employee_id=row["user_id"],
            employee=row["display_name"],
            date=row["work_date"],
            clock_in=row["clock_in"],
            clock_out=row["clock_out"],
            regular_hours=reg,
            overtime_hours=ot,
            total_hours=total_h,
            bill_rate_type=row["bill_rate_type_name"],
        ))

    # ── Parts consumed (via job_parts + stock movements) ──────
    cursor = await db.execute(
        """SELECT sm.part_id, p.name AS part_name, p.code AS part_code,
                  SUM(sm.qty) AS total_qty,
                  AVG(COALESCE(sm.unit_cost_at_move, p.weighted_avg_cost, 0)) AS avg_unit_cost,
                  AVG(COALESCE(sm.unit_sell_at_move, p.company_sell_price, 0)) AS avg_sell_price
           FROM stock_movements sm
           JOIN parts p ON p.id = sm.part_id
           WHERE sm.job_id = ?
             AND sm.movement_type IN ('consume', 'transfer')
             AND sm.to_location_type = 'job'
             AND DATE(sm.created_at) >= ? AND DATE(sm.created_at) <= ?
           GROUP BY sm.part_id, p.name, p.code
           ORDER BY p.name ASC""",
        (job_id, start_date, end_date),
    )
    parts_rows = await cursor.fetchall()

    parts_items = []
    total_parts_cost = 0.0
    total_parts_sell = 0.0

    for row in parts_rows:
        qty = row["total_qty"] or 0
        unit_cost = round(row["avg_unit_cost"] or 0, 4)
        sell_price = round(row["avg_sell_price"] or 0, 4)
        t_cost = round(qty * unit_cost, 2)
        t_sell = round(qty * sell_price, 2)
        total_parts_cost += t_cost
        total_parts_sell += t_sell

        parts_items.append(PreBillingPartItem(
            part_id=row["part_id"],
            part_name=row["part_name"],
            part_code=row["part_code"],
            qty=qty,
            unit_cost=unit_cost,
            sell_price=sell_price,
            total_cost=t_cost,
            total_sell=t_sell,
        ))

    # ── Stock movements history ────────────────────────────────
    cursor = await db.execute(
        """SELECT DATE(sm.created_at) AS move_date,
                  p.name AS part_name,
                  sm.from_location_type, sm.from_location_id,
                  sm.to_location_type, sm.to_location_id,
                  sm.qty, sm.movement_type
           FROM stock_movements sm
           JOIN parts p ON p.id = sm.part_id
           WHERE sm.job_id = ?
             AND DATE(sm.created_at) >= ? AND DATE(sm.created_at) <= ?
           ORDER BY sm.created_at ASC""",
        (job_id, start_date, end_date),
    )
    movement_rows = await cursor.fetchall()

    movements = []
    for row in movement_rows:
        from_loc = _format_location(row["from_location_type"], row["from_location_id"])
        to_loc = _format_location(row["to_location_type"], row["to_location_id"])
        movements.append(PreBillingMovement(
            date=row["move_date"],
            part_name=row["part_name"],
            from_location=from_loc,
            to_location=to_loc,
            qty=row["qty"],
            movement_type=row["movement_type"],
        ))

    # ── Summary (labor = hours only, parts = dollars) ────────
    budget_limit = job["budget_limit"]
    # Budget % based on parts cost only (labor rates handled by bookkeeper)
    budget_pct = (
        round(total_parts_cost / budget_limit * 100, 1)
        if budget_limit and budget_limit > 0
        else None
    )

    bundle = PreBillingBundle(
        job_id=job_id,
        job_name=job["job_name"],
        job_number=job["job_number"],
        bill_rate_type=job["bill_rate_type_name"],
        period_start=start_date,
        period_end=end_date,
        labor=labor_entries,
        parts=parts_items,
        movements=movements,
        summary=PreBillingSummary(
            total_labor_hours=round(total_labor_hours, 2),
            total_regular_hours=round(total_reg_hours, 2),
            total_overtime_hours=round(total_ot_hours, 2),
            total_parts_cost=round(total_parts_cost, 2),
            total_parts_sell=round(total_parts_sell, 2),
            budget_limit=budget_limit,
            budget_used_pct=budget_pct,
        ),
    )

    return ApiResponse(data=bundle, message="Pre-billing bundle generated")


@router.get("/pre-billing/all-jobs")
async def pre_billing_all_jobs(
    start_date: str = Query(..., description="Period start (YYYY-MM-DD)"),
    end_date: str = Query(..., description="Period end (YYYY-MM-DD)"),
    user: dict = Depends(require_permission("view_reports")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Summary row per job for the given date range (all active/recent jobs).

    Returns lightweight rows: job_id, job_number, job_name, total_hours,
    total_parts_cost, total_parts_sell, budget_limit, budget_used_pct.
    """
    cursor = await db.execute(
        """
        SELECT j.id AS job_id,
               j.job_number,
               j.job_name,
               j.budget_limit,

               ROUND(COALESCE((
                   SELECT SUM(
                       (julianday(COALESCE(le2.clock_out, datetime('now')))
                        - julianday(le2.clock_in)) * 24
                   )
                   FROM labor_entries le2
                   WHERE le2.job_id = j.id
                     AND DATE(le2.clock_in) BETWEEN ? AND ?
                     AND le2.clock_out IS NOT NULL
               ), 0), 2) AS total_labor_hours,

               ROUND(COALESCE((
                   SELECT SUM(sm2.qty * COALESCE(sm2.unit_cost, 0))
                   FROM stock_movements sm2
                   WHERE sm2.to_location_type = 'job'
                     AND sm2.to_location_id = j.id
                     AND DATE(sm2.moved_at) BETWEEN ? AND ?
               ), 0), 2) AS total_parts_cost,

               ROUND(COALESCE((
                   SELECT SUM(sm3.qty * COALESCE(sm3.unit_sell, 0))
                   FROM stock_movements sm3
                   WHERE sm3.to_location_type = 'job'
                     AND sm3.to_location_id = j.id
                     AND DATE(sm3.moved_at) BETWEEN ? AND ?
               ), 0), 2) AS total_parts_sell

        FROM jobs j
        WHERE j.status IN ('active', 'completed')
          AND j.created_at >= date(?, '-6 months')
        ORDER BY j.job_number
        """,
        (start_date, end_date, start_date, end_date, start_date, end_date, start_date),
    )
    rows = await cursor.fetchall()

    summary = []
    for row in rows:
        budget = row["budget_limit"]
        parts_cost = float(row["total_parts_cost"] or 0)
        budget_pct = round(parts_cost / float(budget) * 100, 1) if budget else None
        summary.append({
            "job_id": row["job_id"],
            "job_number": row["job_number"],
            "job_name": row["job_name"],
            "total_labor_hours": float(row["total_labor_hours"] or 0),
            "total_parts_cost": parts_cost,
            "total_parts_sell": float(row["total_parts_sell"] or 0),
            "budget_limit": budget,
            "budget_used_pct": budget_pct,
        })

    return ApiResponse(data=summary, message=f"{len(summary)} jobs in period")


# ═══════════════════════════════════════════════════════════════════
# Endpoint 2: Timesheets
# ═══════════════════════════════════════════════════════════════════

@router.get("/timesheets", response_model=ApiResponse[TimesheetReport])
async def timesheets(
    start_date: str = Query(..., description="Period start (YYYY-MM-DD)"),
    end_date: str = Query(..., description="Period end (YYYY-MM-DD)"),
    employee_id: int | None = Query(None, description="Filter to specific employee"),
    group_by: str = Query("day", description="Group by: day, week, pay_period"),
    user: dict = Depends(require_permission("view_reports")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Employee timesheet data with grouping and overtime calculation."""

    conditions = [
        "le.status IN ('clocked_out', 'edited', 'approved')",
        "DATE(le.clock_in) >= ?",
        "DATE(le.clock_in) <= ?",
    ]
    params: list = [start_date, end_date]

    employee_name = None
    if employee_id:
        conditions.append("le.user_id = ?")
        params.append(employee_id)
        # Get employee name
        cursor = await db.execute(
            "SELECT display_name FROM users WHERE id = ?", (employee_id,)
        )
        emp_row = await cursor.fetchone()
        employee_name = emp_row["display_name"] if emp_row else None

    where = " AND ".join(conditions)
    cursor = await db.execute(
        f"""SELECT le.id, le.user_id, u.display_name,
                   DATE(le.clock_in) AS work_date,
                   le.job_id, j.job_name, j.job_number,
                   le.clock_in, le.clock_out,
                   COALESCE(le.regular_hours, 0) AS regular_hours,
                   COALESCE(le.overtime_hours, 0) AS overtime_hours,
                   brt.name AS bill_rate_type_name,
                   le.clock_in_gps_lat, le.clock_in_gps_lng,
                   le.clock_out_gps_lat, le.clock_out_gps_lng
            FROM labor_entries le
            JOIN users u ON u.id = le.user_id
            LEFT JOIN jobs j ON j.id = le.job_id
            LEFT JOIN bill_rate_types brt ON brt.id = j.bill_rate_type_id
            WHERE {where}
            ORDER BY le.clock_in ASC""",
        params,
    )
    rows = await cursor.fetchall()

    entries = []
    total_reg = 0.0
    total_ot = 0.0
    job_ids = set()
    day_dates = set()

    for row in rows:
        reg = row["regular_hours"]
        ot = row["overtime_hours"]
        total_h = round(reg + ot, 2)
        total_reg += reg
        total_ot += ot
        job_ids.add(row["job_id"])
        day_dates.add(row["work_date"])

        gps_in = None
        if row["clock_in_gps_lat"] is not None:
            gps_in = {"lat": row["clock_in_gps_lat"], "lng": row["clock_in_gps_lng"]}
        gps_out = None
        if row["clock_out_gps_lat"] is not None:
            gps_out = {"lat": row["clock_out_gps_lat"], "lng": row["clock_out_gps_lng"]}

        entries.append(TimesheetEntry(
            id=row["id"],
            date=row["work_date"],
            job_id=row["job_id"],
            job_name=row["job_name"] or "Unknown",
            job_number=row["job_number"] or "?",
            clock_in=row["clock_in"],
            clock_out=row["clock_out"],
            regular_hours=reg,
            overtime_hours=ot,
            total_hours=total_h,
            bill_rate_type=row["bill_rate_type_name"],
            gps_in=gps_in,
            gps_out=gps_out,
        ))

    # Group entries dynamically based on group_by parameter
    group_map: dict[str, list[TimesheetEntry]] = {}

    if group_by == "week":
        # ISO week grouping
        for entry in entries:
            from datetime import datetime as DT
            d = DT.strptime(entry.date, "%Y-%m-%d").date()
            iso_year, iso_week, _ = d.isocalendar()
            key = f"{iso_year}-W{iso_week:02d}"
            group_map.setdefault(key, []).append(entry)
    elif group_by == "month":
        for entry in entries:
            key = entry.date[:7]  # YYYY-MM
            group_map.setdefault(key, []).append(entry)
    elif group_by in ("pay_period", "billing_period"):
        from app.services.period_helper import PeriodHelper
        helper = PeriodHelper(db)
        if group_by == "pay_period":
            periods = await helper.get_pay_periods(start_date, end_date)
        else:
            periods = await helper.get_billing_periods(start_date, end_date)
        # Build a lookup from each period's range to its label
        for entry in entries:
            placed = False
            for p in periods:
                if p["start"] <= entry.date <= p["end"]:
                    key = f"{p['start']}|{p['label']}"
                    group_map.setdefault(key, []).append(entry)
                    placed = True
                    break
            if not placed:
                group_map.setdefault(entry.date, []).append(entry)
    else:
        # Default: group by day
        for entry in entries:
            group_map.setdefault(entry.date, []).append(entry)

    day_groups = []
    for key in sorted(group_map.keys()):
        grp_entries = group_map[key]
        grp_reg = sum(e.regular_hours for e in grp_entries)
        grp_ot = sum(e.overtime_hours for e in grp_entries)
        # Use the label from period-based grouping, or the key itself
        label = key.split("|")[1] if "|" in key else key
        day_groups.append(TimesheetDayGroup(
            date=label,
            entries=grp_entries,
            total_hours=round(grp_reg + grp_ot, 2),
            regular_hours=round(grp_reg, 2),
            overtime_hours=round(grp_ot, 2),
        ))

    report = TimesheetReport(
        employee_id=employee_id,
        employee_name=employee_name,
        period_start=start_date,
        period_end=end_date,
        group_by=group_by,
        entries=entries,
        day_groups=day_groups,
        summary=TimesheetSummary(
            total_hours=round(total_reg + total_ot, 2),
            regular_hours=round(total_reg, 2),
            overtime_hours=round(total_ot, 2),
            days_worked=len(day_dates),
            jobs_worked=len(job_ids),
        ),
    )

    return ApiResponse(data=report, message="Timesheet generated")


# ═══════════════════════════════════════════════════════════════════
# Endpoint 3: Labor Overview
# ═══════════════════════════════════════════════════════════════════

@router.get("/labor-overview", response_model=ApiResponse[LaborOverviewReport])
async def labor_overview(
    start_date: str = Query(..., description="Period start (YYYY-MM-DD)"),
    end_date: str = Query(..., description="Period end (YYYY-MM-DD)"),
    job_id: int | None = Query(None, description="Optional job filter"),
    user: dict = Depends(require_permission("view_reports")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Cross-job labor analytics: by employee, by job, by bill rate."""

    job_filter = ""
    params: list = [start_date, end_date]
    if job_id:
        job_filter = "AND le.job_id = ?"
        params.append(job_id)

    # ── By Employee ────────────────────────────────────────────
    cursor = await db.execute(
        f"""SELECT le.user_id, u.display_name,
                   SUM(COALESCE(le.regular_hours, 0)) AS total_reg,
                   SUM(COALESCE(le.overtime_hours, 0)) AS total_ot,
                   COUNT(DISTINCT le.job_id) AS jobs_worked,
                   COUNT(DISTINCT DATE(le.clock_in)) AS days_worked
            FROM labor_entries le
            JOIN users u ON u.id = le.user_id
            WHERE le.status IN ('clocked_out', 'edited', 'approved')
              AND DATE(le.clock_in) >= ? AND DATE(le.clock_in) <= ?
              {job_filter}
            GROUP BY le.user_id, u.display_name
            ORDER BY (total_reg + total_ot) DESC""",
        params,
    )
    by_employee_rows = await cursor.fetchall()

    by_employee = []
    for row in by_employee_rows:
        reg = row["total_reg"]
        ot = row["total_ot"]
        total_h = round(reg + ot, 2)
        days = row["days_worked"] or 1
        by_employee.append(LaborByEmployee(
            employee_id=row["user_id"],
            employee=row["display_name"],
            total_hours=total_h,
            regular_hours=round(reg, 2),
            overtime_hours=round(ot, 2),
            jobs_worked=row["jobs_worked"],
            days_worked=days,
            avg_hours_per_day=round(total_h / days, 2),
        ))

    # ── By Job (hours only — no dollar rates) ────────────────
    cursor = await db.execute(
        f"""SELECT le.job_id, j.job_name, j.job_number,
                   SUM(COALESCE(le.regular_hours, 0) + COALESCE(le.overtime_hours, 0)) AS total_hours,
                   COUNT(DISTINCT le.user_id) AS employee_count
            FROM labor_entries le
            LEFT JOIN jobs j ON j.id = le.job_id
            WHERE le.status IN ('clocked_out', 'edited', 'approved')
              AND DATE(le.clock_in) >= ? AND DATE(le.clock_in) <= ?
              {job_filter}
            GROUP BY le.job_id, j.job_name, j.job_number
            ORDER BY total_hours DESC""",
        params,
    )
    by_job_rows = await cursor.fetchall()

    by_job = [
        LaborByJob(
            job_id=row["job_id"],
            job_name=row["job_name"] or "Unknown",
            job_number=row["job_number"] or "?",
            total_hours=round(row["total_hours"], 2),
            employee_count=row["employee_count"],
        )
        for row in by_job_rows
    ]

    # ── By Bill Rate Type ──────────────────────────────────────
    cursor = await db.execute(
        f"""SELECT COALESCE(brt.name, 'Unassigned') AS rate_type,
                   SUM(COALESCE(le.regular_hours, 0) + COALESCE(le.overtime_hours, 0)) AS total_hours,
                   COUNT(le.id) AS entry_count
            FROM labor_entries le
            LEFT JOIN jobs j ON j.id = le.job_id
            LEFT JOIN bill_rate_types brt ON brt.id = j.bill_rate_type_id
            WHERE le.status IN ('clocked_out', 'edited', 'approved')
              AND DATE(le.clock_in) >= ? AND DATE(le.clock_in) <= ?
              {job_filter}
            GROUP BY rate_type
            ORDER BY total_hours DESC""",
        params,
    )
    by_rate_rows = await cursor.fetchall()

    by_bill_rate = [
        LaborByBillRate(
            rate_type=row["rate_type"],
            total_hours=round(row["total_hours"], 2),
            entry_count=row["entry_count"],
        )
        for row in by_rate_rows
    ]

    # ── Totals ─────────────────────────────────────────────────
    all_reg = sum(e.regular_hours for e in by_employee)
    all_ot = sum(e.overtime_hours for e in by_employee)

    # Count unique work days across all employees
    cursor = await db.execute(
        f"""SELECT COUNT(DISTINCT DATE(le.clock_in)) AS total_days
            FROM labor_entries le
            WHERE le.status IN ('clocked_out', 'edited', 'approved')
              AND DATE(le.clock_in) >= ? AND DATE(le.clock_in) <= ?
              {job_filter}""",
        params,
    )
    days_row = await cursor.fetchone()

    report = LaborOverviewReport(
        period_start=start_date,
        period_end=end_date,
        by_employee=by_employee,
        by_job=by_job,
        by_bill_rate=by_bill_rate,
        totals=LaborOverviewTotals(
            total_hours=round(all_reg + all_ot, 2),
            regular_hours=round(all_reg, 2),
            overtime_hours=round(all_ot, 2),
            total_employees=len(by_employee),
            total_jobs=len(by_job),
            total_days=days_row["total_days"] if days_row else 0,
        ),
    )

    return ApiResponse(data=report, message="Labor overview generated")


# ═══════════════════════════════════════════════════════════════════
# Endpoint 4: Exports (CSV streaming)
# ═══════════════════════════════════════════════════════════════════

@router.post("/exports")
async def exports(
    req: ExportRequest,
    user: dict = Depends(require_permission("export_reports")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Generate a downloadable CSV or PDF export of a report."""
    from pathlib import Path

    start = req.start_date or (date.today() - timedelta(days=30)).isoformat()
    end = req.end_date or date.today().isoformat()

    if req.format == "pdf":
        from app.services.report_pdf_service import ReportPDFService
        pdf_svc = ReportPDFService(db)

        filepath: str | None = None
        if req.report_type == "timesheet":
            filepath = await pdf_svc.generate_timesheet_pdf(
                req.employee_id, start, end, req.group_by
            )
        elif req.report_type == "labor-overview":
            filepath = await pdf_svc.generate_labor_overview_pdf(start, end)
        elif req.report_type == "pre-billing":
            if not req.job_id:
                raise HTTPException(status_code=400, detail="job_id required for pre-billing export")
            filepath = await pdf_svc.generate_pre_billing_pdf(req.job_id, start, end)
        elif req.report_type == "profitability":
            filepath = await pdf_svc.generate_profitability_pdf(start, end, req.job_id)
        else:
            raise HTTPException(status_code=400, detail=f"Unknown report type: {req.report_type}")

        if not filepath or not Path(filepath).exists():
            raise HTTPException(status_code=500, detail="PDF generation failed")

        # Stream the file and delete after sending
        def _pdf_iter():
            with open(filepath, "rb") as f:
                yield from iter(lambda: f.read(65536), b"")

        fname = Path(filepath).name
        return StreamingResponse(
            _pdf_iter(),
            media_type="application/pdf",
            headers={"Content-Disposition": f'attachment; filename="{fname}"'},
        )

    if req.report_type == "pre-billing":
        if not req.job_id:
            raise HTTPException(status_code=400, detail="job_id required for pre-billing export")
        return await _export_pre_billing_csv(db, req.job_id, start, end)

    elif req.report_type == "timesheet":
        return await _export_timesheet_csv(db, req.employee_id, start, end)

    elif req.report_type == "labor-overview":
        return await _export_labor_overview_csv(db, start, end)

    elif req.report_type == "profitability":
        return await _export_profitability_csv(db, start, end, req.job_id)

    raise HTTPException(status_code=400, detail=f"Unknown report type: {req.report_type}")


# ═══════════════════════════════════════════════════════════════════
# CSV Export Helpers
# ═══════════════════════════════════════════════════════════════════

async def _export_pre_billing_csv(
    db: aiosqlite.Connection, job_id: int, start: str, end: str
) -> StreamingResponse:
    """Generate pre-billing CSV for a job."""
    cursor = await db.execute(
        "SELECT job_name, job_number FROM jobs WHERE id = ?", (job_id,)
    )
    job = await cursor.fetchone()
    job_label = f"{job['job_number']}_{job['job_name']}" if job else str(job_id)

    output = io.StringIO()
    writer = csv.writer(output)

    # Labor section
    writer.writerow(["=== LABOR ==="])
    writer.writerow(["Employee", "Date", "Clock In", "Clock Out", "Regular Hours", "OT Hours", "Total Hours"])

    cursor = await db.execute(
        """SELECT u.display_name, DATE(le.clock_in) AS work_date,
                  le.clock_in, le.clock_out,
                  COALESCE(le.regular_hours, 0) AS reg,
                  COALESCE(le.overtime_hours, 0) AS ot
           FROM labor_entries le
           JOIN users u ON u.id = le.user_id
           WHERE le.job_id = ?
             AND le.status IN ('clocked_out', 'edited', 'approved')
             AND DATE(le.clock_in) >= ? AND DATE(le.clock_in) <= ?
           ORDER BY le.clock_in ASC""",
        (job_id, start, end),
    )
    for row in await cursor.fetchall():
        writer.writerow([
            row["display_name"], row["work_date"],
            row["clock_in"], row["clock_out"],
            row["reg"], row["ot"], round(row["reg"] + row["ot"], 2),
        ])

    # Parts section
    writer.writerow([])
    writer.writerow(["=== PARTS ==="])
    writer.writerow(["Part", "Code", "Qty", "Unit Cost", "Sell Price", "Total Cost", "Total Sell"])

    cursor = await db.execute(
        """SELECT p.name, p.code, SUM(sm.qty) AS qty,
                  AVG(COALESCE(sm.unit_cost_at_move, 0)) AS unit_cost,
                  AVG(COALESCE(sm.unit_sell_at_move, 0)) AS sell_price
           FROM stock_movements sm
           JOIN parts p ON p.id = sm.part_id
           WHERE sm.job_id = ?
             AND sm.movement_type IN ('consume', 'transfer')
             AND sm.to_location_type = 'job'
             AND DATE(sm.created_at) >= ? AND DATE(sm.created_at) <= ?
           GROUP BY sm.part_id, p.name, p.code
           ORDER BY p.name""",
        (job_id, start, end),
    )
    for row in await cursor.fetchall():
        qty = row["qty"] or 0
        uc = round(row["unit_cost"], 4)
        sp = round(row["sell_price"], 4)
        writer.writerow([
            row["name"], row["code"], qty, uc, sp,
            round(qty * uc, 2), round(qty * sp, 2),
        ])

    output.seek(0)
    filename = format_report_filename("pre-billing", start, end, subject=job_label)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


async def _export_timesheet_csv(
    db: aiosqlite.Connection, employee_id: int | None, start: str, end: str
) -> StreamingResponse:
    """Generate timesheet CSV."""
    conditions = [
        "le.status IN ('clocked_out', 'edited', 'approved')",
        "DATE(le.clock_in) >= ?",
        "DATE(le.clock_in) <= ?",
    ]
    params: list = [start, end]
    if employee_id:
        conditions.append("le.user_id = ?")
        params.append(employee_id)

    where = " AND ".join(conditions)

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow([
        "Employee", "Date", "Job", "Job #", "Clock In", "Clock Out",
        "Regular Hours", "OT Hours", "Total Hours", "Bill Rate Type",
    ])

    cursor = await db.execute(
        f"""SELECT u.display_name, DATE(le.clock_in) AS work_date,
                   j.job_name, j.job_number,
                   le.clock_in, le.clock_out,
                   COALESCE(le.regular_hours, 0) AS reg,
                   COALESCE(le.overtime_hours, 0) AS ot,
                   brt.name AS rate_type
            FROM labor_entries le
            JOIN users u ON u.id = le.user_id
            LEFT JOIN jobs j ON j.id = le.job_id
            LEFT JOIN bill_rate_types brt ON brt.id = j.bill_rate_type_id
            WHERE {where}
            ORDER BY le.clock_in ASC""",
        params,
    )
    for row in await cursor.fetchall():
        writer.writerow([
            row["display_name"], row["work_date"],
            row["job_name"], row["job_number"],
            row["clock_in"], row["clock_out"],
            row["reg"], row["ot"],
            round(row["reg"] + row["ot"], 2),
            row["rate_type"] or "",
        ])

    output.seek(0)
    # Look up employee name for filename
    subject = "AllEmployees"
    if employee_id:
        cur = await db.execute("SELECT display_name FROM users WHERE id = ?", (employee_id,))
        emp_row = await cur.fetchone()
        subject = emp_row["display_name"] if emp_row else f"Employee-{employee_id}"
    filename = format_report_filename("timesheet", start, end, subject=subject)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


async def _export_labor_overview_csv(
    db: aiosqlite.Connection, start: str, end: str
) -> StreamingResponse:
    """Generate labor overview CSV."""
    output = io.StringIO()
    writer = csv.writer(output)

    # By Employee
    writer.writerow(["=== BY EMPLOYEE ==="])
    writer.writerow(["Employee", "Total Hours", "Regular", "OT", "Jobs Worked", "Days Worked", "Avg Hrs/Day"])

    cursor = await db.execute(
        """SELECT u.display_name,
                  SUM(COALESCE(le.regular_hours, 0)) AS reg,
                  SUM(COALESCE(le.overtime_hours, 0)) AS ot,
                  COUNT(DISTINCT le.job_id) AS jobs,
                  COUNT(DISTINCT DATE(le.clock_in)) AS days
           FROM labor_entries le
           JOIN users u ON u.id = le.user_id
           WHERE le.status IN ('clocked_out', 'edited', 'approved')
             AND DATE(le.clock_in) >= ? AND DATE(le.clock_in) <= ?
           GROUP BY le.user_id, u.display_name
           ORDER BY (reg + ot) DESC""",
        (start, end),
    )
    for row in await cursor.fetchall():
        total = round(row["reg"] + row["ot"], 2)
        days = row["days"] or 1
        writer.writerow([
            row["display_name"], total,
            round(row["reg"], 2), round(row["ot"], 2),
            row["jobs"], days, round(total / days, 2),
        ])

    # By Job
    writer.writerow([])
    writer.writerow(["=== BY JOB ==="])
    writer.writerow(["Job", "Job #", "Total Hours", "Employees"])

    cursor = await db.execute(
        """SELECT j.job_name, j.job_number,
                  SUM(COALESCE(le.regular_hours, 0) + COALESCE(le.overtime_hours, 0)) AS hours,
                  COUNT(DISTINCT le.user_id) AS emps
           FROM labor_entries le
           LEFT JOIN jobs j ON j.id = le.job_id
           WHERE le.status IN ('clocked_out', 'edited', 'approved')
             AND DATE(le.clock_in) >= ? AND DATE(le.clock_in) <= ?
           GROUP BY le.job_id, j.job_name, j.job_number
           ORDER BY hours DESC""",
        (start, end),
    )
    for row in await cursor.fetchall():
        writer.writerow([
            row["job_name"], row["job_number"],
            round(row["hours"], 2), row["emps"],
        ])

    output.seek(0)
    filename = format_report_filename("labor-overview", start, end)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


async def _export_profitability_csv(
    db: aiosqlite.Connection, start: str, end: str, job_id: int | None = None,
) -> StreamingResponse:
    """Generate profitability CSV — labor cost, parts cost/sell/margin, budget per job."""
    job_filter = ""
    params: list = [start, end]
    if job_id:
        job_filter = "AND le.job_id = ?"
        params.append(job_id)

    # Labor cost per job
    cursor = await db.execute(
        f"""SELECT le.job_id, j.job_name, j.job_number, j.budget_limit,
                   SUM(COALESCE(le.regular_hours, 0) + COALESCE(le.overtime_hours, 0)) AS total_hours,
                   SUM(
                       (COALESCE(le.regular_hours, 0) + COALESCE(le.overtime_hours, 0))
                       * COALESCE(
                           (SELECT wh.pay_rate FROM wage_history wh
                            WHERE wh.user_id = le.user_id
                              AND wh.effective_date <= DATE(le.clock_in)
                            ORDER BY wh.effective_date DESC LIMIT 1),
                           u.pay_rate, 0)
                   ) AS labor_cost
            FROM labor_entries le
            JOIN users u ON u.id = le.user_id
            LEFT JOIN jobs j ON j.id = le.job_id
            WHERE le.status IN ('clocked_out', 'edited', 'approved')
              AND DATE(le.clock_in) >= ? AND DATE(le.clock_in) <= ?
              {job_filter}
            GROUP BY le.job_id
            ORDER BY labor_cost DESC""",
        params,
    )
    labor_rows = {row["job_id"]: row for row in await cursor.fetchall()}

    # Parts cost + sell per job
    parts_params: list = [start, end]
    parts_filter = ""
    if job_id:
        parts_filter = "AND sm.job_id = ?"
        parts_params.append(job_id)

    cursor = await db.execute(
        f"""SELECT sm.job_id,
                   SUM(sm.qty * COALESCE(sm.unit_cost_at_move, p.weighted_avg_cost, 0)) AS parts_cost,
                   SUM(sm.qty * COALESCE(sm.unit_sell_at_move, p.company_sell_price, 0)) AS parts_sell
            FROM stock_movements sm
            JOIN parts p ON p.id = sm.part_id
            WHERE sm.movement_type IN ('consume', 'transfer')
              AND sm.to_location_type = 'job'
              AND DATE(sm.created_at) >= ? AND DATE(sm.created_at) <= ?
              {parts_filter}
            GROUP BY sm.job_id""",
        parts_params,
    )
    parts_rows = {row["job_id"]: row for row in await cursor.fetchall()}

    # Build CSV
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow([
        "Job Name", "Job Number", "Labor Hours", "Labor Cost",
        "Parts Cost", "Parts Sell", "Parts Margin", "Total Cost",
        "Budget", "Budget Used %",
    ])

    all_job_ids = sorted(set(labor_rows.keys()) | set(parts_rows.keys()))
    for jid in all_job_ids:
        lr = labor_rows.get(jid, {})
        pr = parts_rows.get(jid, {})
        labor_hours = round(lr.get("total_hours", 0) or 0, 2)
        labor_cost = round(lr.get("labor_cost", 0) or 0, 2)
        parts_cost = round(pr.get("parts_cost", 0) or 0, 2)
        parts_sell = round(pr.get("parts_sell", 0) or 0, 2)
        total_cost = round(labor_cost + parts_cost, 2)
        parts_margin = round(parts_sell - parts_cost, 2)
        budget = lr.get("budget_limit")
        budget_pct = round(total_cost / budget * 100, 1) if budget and budget > 0 else ""

        writer.writerow([
            lr.get("job_name") or "Unknown",
            lr.get("job_number") or "?",
            labor_hours, labor_cost,
            parts_cost, parts_sell, parts_margin, total_cost,
            budget or "", budget_pct,
        ])

    output.seek(0)
    filename = format_report_filename("profitability", start, end)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# ═══════════════════════════════════════════════════════════════════
# Endpoint 5: Billing Periods (Period Locking)
# ═══════════════════════════════════════════════════════════════════

@router.get("/billing-periods", response_model=ApiResponse[list[BillingPeriod]])
async def list_billing_periods(
    job_id: int | None = Query(None, description="Filter to specific job"),
    user: dict = Depends(require_permission("view_reports")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List billing periods, optionally filtered by job."""
    conditions = ["1=1"]
    params: list = []

    if job_id is not None:
        conditions.append("bp.job_id = ?")
        params.append(job_id)

    where = " AND ".join(conditions)
    cursor = await db.execute(
        f"""SELECT bp.id, bp.job_id, bp.period_start, bp.period_end,
                   bp.locked_at, bp.locked_by, bp.notes, bp.created_at,
                   j.job_name, j.job_number,
                   u.display_name AS locked_by_name
            FROM billing_periods bp
            LEFT JOIN jobs j ON j.id = bp.job_id
            LEFT JOIN users u ON u.id = bp.locked_by
            WHERE {where}
            ORDER BY bp.period_start DESC""",
        params,
    )
    rows = await cursor.fetchall()

    periods = [
        BillingPeriod(
            id=row["id"],
            job_id=row["job_id"],
            job_name=row["job_name"],
            job_number=row["job_number"],
            period_start=row["period_start"],
            period_end=row["period_end"],
            locked_at=row["locked_at"],
            locked_by=row["locked_by"],
            locked_by_name=row["locked_by_name"],
            notes=row["notes"],
            created_at=row["created_at"],
        )
        for row in rows
    ]

    return ApiResponse(data=periods, message=f"{len(periods)} billing period(s)")


@router.post("/billing-periods", response_model=ApiResponse[BillingPeriod])
async def create_billing_period(
    body: BillingPeriodCreate,
    user: dict = Depends(require_permission("lock_billing_periods")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a new (open) billing period."""
    try:
        cursor = await db.execute(
            """INSERT INTO billing_periods (job_id, period_start, period_end, notes)
               VALUES (?, ?, ?, ?)""",
            (body.job_id, body.period_start, body.period_end, body.notes),
        )
        await db.commit()
        period_id = cursor.lastrowid
    except Exception as e:
        if "UNIQUE constraint" in str(e):
            raise HTTPException(
                status_code=409,
                detail="A billing period already exists for this job and date range.",
            )
        raise

    # Fetch the created period
    cursor = await db.execute(
        """SELECT bp.id, bp.job_id, bp.period_start, bp.period_end,
                  bp.locked_at, bp.locked_by, bp.notes, bp.created_at,
                  j.job_name, j.job_number
           FROM billing_periods bp
           LEFT JOIN jobs j ON j.id = bp.job_id
           WHERE bp.id = ?""",
        (period_id,),
    )
    row = await cursor.fetchone()

    return ApiResponse(
        data=BillingPeriod(
            id=row["id"],
            job_id=row["job_id"],
            job_name=row["job_name"],
            job_number=row["job_number"],
            period_start=row["period_start"],
            period_end=row["period_end"],
            locked_at=row["locked_at"],
            locked_by=row["locked_by"],
            notes=row["notes"],
            created_at=row["created_at"],
        ),
        message="Billing period created",
    )


@router.patch("/billing-periods/{period_id}/lock", response_model=ApiResponse[BillingPeriod])
async def lock_billing_period(
    period_id: int,
    user: dict = Depends(require_permission("lock_billing_periods")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Lock a billing period — prevents edits to labor/parts in this date range."""
    cursor = await db.execute(
        "SELECT id, locked_at FROM billing_periods WHERE id = ?", (period_id,)
    )
    row = await cursor.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Billing period not found")
    if row["locked_at"]:
        raise HTTPException(status_code=409, detail="Period is already locked")

    now = datetime.now().isoformat()
    user_id = user.get("user_id") or user.get("id")
    await db.execute(
        """UPDATE billing_periods
           SET locked_at = ?, locked_by = ?, updated_at = ?
           WHERE id = ?""",
        (now, user_id, now, period_id),
    )
    await db.commit()

    # Fetch updated
    cursor = await db.execute(
        """SELECT bp.*, j.job_name, j.job_number, u.display_name AS locked_by_name
           FROM billing_periods bp
           LEFT JOIN jobs j ON j.id = bp.job_id
           LEFT JOIN users u ON u.id = bp.locked_by
           WHERE bp.id = ?""",
        (period_id,),
    )
    row = await cursor.fetchone()

    return ApiResponse(
        data=BillingPeriod(
            id=row["id"],
            job_id=row["job_id"],
            job_name=row["job_name"],
            job_number=row["job_number"],
            period_start=row["period_start"],
            period_end=row["period_end"],
            locked_at=row["locked_at"],
            locked_by=row["locked_by"],
            locked_by_name=row["locked_by_name"],
            notes=row["notes"],
            created_at=row["created_at"],
        ),
        message="Period locked",
    )


@router.patch("/billing-periods/{period_id}/unlock", response_model=ApiResponse[BillingPeriod])
async def unlock_billing_period(
    period_id: int,
    user: dict = Depends(require_permission("lock_billing_periods")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Unlock a billing period — admin action, allows edits again."""
    cursor = await db.execute(
        "SELECT id, locked_at FROM billing_periods WHERE id = ?", (period_id,)
    )
    row = await cursor.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Billing period not found")
    if not row["locked_at"]:
        raise HTTPException(status_code=409, detail="Period is not locked")

    now = datetime.now().isoformat()
    await db.execute(
        """UPDATE billing_periods
           SET locked_at = NULL, locked_by = NULL, updated_at = ?
           WHERE id = ?""",
        (now, period_id),
    )
    await db.commit()

    cursor = await db.execute(
        """SELECT bp.*, j.job_name, j.job_number
           FROM billing_periods bp
           LEFT JOIN jobs j ON j.id = bp.job_id
           WHERE bp.id = ?""",
        (period_id,),
    )
    row = await cursor.fetchone()

    return ApiResponse(
        data=BillingPeriod(
            id=row["id"],
            job_id=row["job_id"],
            job_name=row["job_name"],
            job_number=row["job_number"],
            period_start=row["period_start"],
            period_end=row["period_end"],
            locked_at=None,
            locked_by=None,
            notes=row["notes"],
            created_at=row["created_at"],
        ),
        message="Period unlocked",
    )


# ═══════════════════════════════════════════════════════════════════
# Endpoint 6: Profitability Analysis
# ═══════════════════════════════════════════════════════════════════

@router.get("/profitability", response_model=ApiResponse[ProfitabilityReport])
async def profitability(
    start_date: str = Query(..., description="Period start (YYYY-MM-DD)"),
    end_date: str = Query(..., description="Period end (YYYY-MM-DD)"),
    job_id: int | None = Query(None, description="Optional job filter"),
    user: dict = Depends(require_permission("view_reports")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Profitability analysis: labor cost + parts margin per job vs budget."""

    job_filter = ""
    params: list = [start_date, end_date]
    if job_id:
        job_filter = "AND le.job_id = ?"
        params.append(job_id)

    # ── Labor cost per job (hours × employee pay_rate) ──────────
    cursor = await db.execute(
        f"""SELECT le.job_id, j.job_name, j.job_number, j.status,
                   j.budget_limit,
                   SUM(COALESCE(le.regular_hours, 0) + COALESCE(le.overtime_hours, 0)) AS total_hours,
                   SUM(
                       (COALESCE(le.regular_hours, 0) + COALESCE(le.overtime_hours, 0))
                       * COALESCE(
                           (SELECT wh.pay_rate FROM wage_history wh
                            WHERE wh.user_id = le.user_id
                              AND wh.effective_date <= DATE(le.clock_in)
                            ORDER BY wh.effective_date DESC LIMIT 1),
                           u.pay_rate,
                           0
                       )
                   ) AS labor_cost
            FROM labor_entries le
            JOIN users u ON u.id = le.user_id
            LEFT JOIN jobs j ON j.id = le.job_id
            WHERE le.status IN ('clocked_out', 'edited', 'approved')
              AND DATE(le.clock_in) >= ? AND DATE(le.clock_in) <= ?
              {job_filter}
            GROUP BY le.job_id
            ORDER BY labor_cost DESC""",
        params,
    )
    labor_rows = {row["job_id"]: row for row in await cursor.fetchall()}

    # ── Parts cost + sell per job (from stock movements) ────────
    parts_params: list = [start_date, end_date]
    parts_filter = ""
    if job_id:
        parts_filter = "AND sm.job_id = ?"
        parts_params.append(job_id)

    cursor = await db.execute(
        f"""SELECT sm.job_id,
                   SUM(sm.qty * COALESCE(sm.unit_cost_at_move, p.weighted_avg_cost, 0)) AS parts_cost,
                   SUM(sm.qty * COALESCE(sm.unit_sell_at_move, p.company_sell_price, 0)) AS parts_sell
            FROM stock_movements sm
            JOIN parts p ON p.id = sm.part_id
            WHERE sm.movement_type IN ('consume', 'transfer')
              AND sm.to_location_type = 'job'
              AND DATE(sm.created_at) >= ? AND DATE(sm.created_at) <= ?
              {parts_filter}
            GROUP BY sm.job_id""",
        parts_params,
    )
    parts_rows = {row["job_id"]: row for row in await cursor.fetchall()}

    # ── Merge into per-job profitability ────────────────────────
    all_job_ids = set(labor_rows.keys()) | set(parts_rows.keys())
    by_job = []
    totals = CompanyProfitabilityTotals()

    for jid in sorted(all_job_ids):
        labor_row = labor_rows.get(jid)
        parts_row = parts_rows.get(jid)

        job_name = (labor_row or {}).get("job_name") or "Unknown"
        job_number = (labor_row or {}).get("job_number") or "?"
        status = (labor_row or {}).get("status") or "active"
        budget_limit = (labor_row or {}).get("budget_limit")

        labor_hours = round((labor_row or {}).get("total_hours", 0) or 0, 2)
        labor_cost = round((labor_row or {}).get("labor_cost", 0) or 0, 2)
        parts_cost = round((parts_row or {}).get("parts_cost", 0) or 0, 2)
        parts_sell = round((parts_row or {}).get("parts_sell", 0) or 0, 2)

        total_cost = round(labor_cost + parts_cost, 2)
        parts_margin = round(parts_sell - parts_cost, 2)

        budget_remaining = None
        budget_pct = None
        if budget_limit and budget_limit > 0:
            budget_remaining = round(budget_limit - total_cost, 2)
            budget_pct = round(total_cost / budget_limit * 100, 1)

        jp = JobProfitability(
            job_id=jid,
            job_name=job_name,
            job_number=job_number,
            status=status,
            labor_hours=labor_hours,
            labor_cost=labor_cost,
            parts_cost=parts_cost,
            parts_sell=parts_sell,
            total_cost=total_cost,
            parts_margin=parts_margin,
            budget_limit=budget_limit,
            budget_remaining=budget_remaining,
            budget_utilization_pct=budget_pct,
        )
        by_job.append(jp)

        # Accumulate totals
        totals.total_labor_cost += labor_cost
        totals.total_parts_cost += parts_cost
        totals.total_parts_sell += parts_sell
        totals.total_combined_cost += total_cost
        totals.total_parts_margin += parts_margin
        totals.total_labor_hours += labor_hours

        if budget_limit and budget_limit > 0:
            if total_cost <= budget_limit:
                totals.jobs_under_budget += 1
            else:
                totals.jobs_over_budget += 1
        else:
            totals.jobs_no_budget += 1

    # Round totals
    totals.total_labor_cost = round(totals.total_labor_cost, 2)
    totals.total_parts_cost = round(totals.total_parts_cost, 2)
    totals.total_parts_sell = round(totals.total_parts_sell, 2)
    totals.total_combined_cost = round(totals.total_combined_cost, 2)
    totals.total_parts_margin = round(totals.total_parts_margin, 2)
    totals.total_labor_hours = round(totals.total_labor_hours, 2)

    report = ProfitabilityReport(
        period_start=start_date,
        period_end=end_date,
        by_job=by_job,
        totals=totals,
    )

    return ApiResponse(data=report, message="Profitability report generated")


# ═══════════════════════════════════════════════════════════════════
# Endpoint 7: Bookkeeper Exports
# ═══════════════════════════════════════════════════════════════════

@router.post("/exports/bookkeeper")
async def bookkeeper_export(
    req: BookkeeperExportRequest,
    user: dict = Depends(require_permission("export_reports")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Generate a bookkeeper-formatted export (QuickBooks IIF, GL CSV, or Payroll CSV)."""

    if req.format == "quickbooks":
        return await _export_quickbooks_iif(db, req)
    elif req.format == "general_ledger":
        return await _export_general_ledger_csv(db, req)
    elif req.format == "payroll":
        return await _export_payroll_csv(db, req)

    raise HTTPException(status_code=400, detail=f"Unknown format: {req.format}")


# ═══════════════════════════════════════════════════════════════════
# Period Lock Enforcement Helper
# ═══════════════════════════════════════════════════════════════════

async def check_period_lock(
    db: aiosqlite.Connection, job_id: int | None, target_date: str
) -> None:
    """Raise 409 if the target date falls within a locked billing period for the job.

    Called by labor and movement endpoints before creating/updating entries.
    """
    cursor = await db.execute(
        """SELECT id, period_start, period_end FROM billing_periods
           WHERE locked_at IS NOT NULL
             AND (job_id = ? OR job_id IS NULL)
             AND ? >= period_start AND ? <= period_end
           LIMIT 1""",
        (job_id, target_date, target_date),
    )
    row = await cursor.fetchone()
    if row:
        raise HTTPException(
            status_code=409,
            detail=f"Date {target_date} falls within locked billing period "
                   f"{row['period_start']} to {row['period_end']}. "
                   f"Unlock the period before making changes.",
        )


# ═══════════════════════════════════════════════════════════════════
# Bookkeeper Export Helpers
# ═══════════════════════════════════════════════════════════════════

async def _get_job_filter_clause(job_ids: list[int] | None) -> tuple[str, list]:
    """Build a SQL WHERE clause for optional job_ids filter."""
    if not job_ids:
        return "", []
    placeholders = ",".join("?" for _ in job_ids)
    return f"AND le.job_id IN ({placeholders})", list(job_ids)


async def _export_quickbooks_iif(
    db: aiosqlite.Connection, req: BookkeeperExportRequest
) -> StreamingResponse:
    """Generate QuickBooks-compatible IIF file."""
    output = io.StringIO()

    # IIF header
    output.write("!TRNS\tTRNSID\tTRNSTYPE\tDATE\tACCNT\tNAME\tCLASS\tAMOUNT\tMEMO\n")
    output.write("!SPL\tSPLID\tTRNSTYPE\tDATE\tACCNT\tNAME\tCLASS\tAMOUNT\tMEMO\n")
    output.write("!ENDTRNS\n")

    # Format date for QuickBooks (MM/DD/YYYY)
    end_dt = datetime.strptime(req.period_end, "%Y-%m-%d")
    qb_date = end_dt.strftime("%m/%d/%Y")

    if req.include_labor:
        # Get labor hours per job
        job_clause, job_params = await _get_job_filter_clause(req.job_ids)
        cursor = await db.execute(
            f"""SELECT le.job_id, j.job_name,
                       SUM(COALESCE(le.regular_hours, 0) + COALESCE(le.overtime_hours, 0)) AS total_hours
                FROM labor_entries le
                LEFT JOIN jobs j ON j.id = le.job_id
                WHERE le.status IN ('clocked_out', 'edited', 'approved')
                  AND DATE(le.clock_in) >= ? AND DATE(le.clock_in) <= ?
                  {job_clause}
                GROUP BY le.job_id""",
            [req.period_start, req.period_end] + job_params,
        )
        for row in await cursor.fetchall():
            job_name = row["job_name"] or f"Job #{row['job_id']}"
            hours = round(row["total_hours"], 2)
            memo = f"Labor {req.period_start} to {req.period_end} ({hours} hrs)"
            # TRNS line (debit to A/R)
            output.write(f"TRNS\t\tINVOICE\t{qb_date}\tAccounts Receivable\t{job_name}\tLabor\t{hours}\t{memo}\n")
            # SPL line (credit to Revenue)
            output.write(f"SPL\t\tINVOICE\t{qb_date}\tLabor Revenue\t{job_name}\tLabor\t{-hours}\t\n")
            output.write("ENDTRNS\n")

    if req.include_parts:
        # Get parts sell per job
        job_clause_sm = ""
        job_params_sm: list = []
        if req.job_ids:
            placeholders = ",".join("?" for _ in req.job_ids)
            job_clause_sm = f"AND sm.job_id IN ({placeholders})"
            job_params_sm = list(req.job_ids)

        cursor = await db.execute(
            f"""SELECT sm.job_id, j.job_name,
                       SUM(sm.qty * COALESCE(sm.unit_sell_at_move, p.company_sell_price, 0)) AS parts_sell
                FROM stock_movements sm
                JOIN parts p ON p.id = sm.part_id
                LEFT JOIN jobs j ON j.id = sm.job_id
                WHERE sm.movement_type IN ('consume', 'transfer')
                  AND sm.to_location_type = 'job'
                  AND DATE(sm.created_at) >= ? AND DATE(sm.created_at) <= ?
                  {job_clause_sm}
                GROUP BY sm.job_id""",
            [req.period_start, req.period_end] + job_params_sm,
        )
        for row in await cursor.fetchall():
            job_name = row["job_name"] or f"Job #{row['job_id']}"
            sell = round(row["parts_sell"] or 0, 2)
            if sell > 0:
                memo = f"Parts {req.period_start} to {req.period_end}"
                output.write(f"TRNS\t\tINVOICE\t{qb_date}\tAccounts Receivable\t{job_name}\tParts\t{sell}\t{memo}\n")
                output.write(f"SPL\t\tINVOICE\t{qb_date}\tParts Revenue\t{job_name}\tParts\t{-sell}\t\n")
                output.write("ENDTRNS\n")

    output.seek(0)
    filename = format_report_filename("quickbooks", req.period_start, req.period_end, ext="iif")
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/plain",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


async def _export_general_ledger_csv(
    db: aiosqlite.Connection, req: BookkeeperExportRequest
) -> StreamingResponse:
    """Generate General Ledger CSV — simple debit/credit format for any accounting system."""
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["Date", "Job", "Category", "Description", "Debit", "Credit", "Account"])

    end_date_formatted = req.period_end

    if req.include_labor:
        job_clause, job_params = await _get_job_filter_clause(req.job_ids)
        cursor = await db.execute(
            f"""SELECT le.job_id, j.job_name, j.job_number,
                       SUM(COALESCE(le.regular_hours, 0) + COALESCE(le.overtime_hours, 0)) AS total_hours
                FROM labor_entries le
                LEFT JOIN jobs j ON j.id = le.job_id
                WHERE le.status IN ('clocked_out', 'edited', 'approved')
                  AND DATE(le.clock_in) >= ? AND DATE(le.clock_in) <= ?
                  {job_clause}
                GROUP BY le.job_id""",
            [req.period_start, req.period_end] + job_params,
        )
        for row in await cursor.fetchall():
            job_label = f"{row['job_number'] or '?'} {row['job_name'] or 'Unknown'}"
            hours = round(row["total_hours"], 2)
            desc = f"{req.period_start} to {req.period_end} labor ({hours} hrs)"
            # Debit A/R, Credit Revenue (using hours as the amount — bookkeeper adds rates)
            writer.writerow([end_date_formatted, job_label, "Labor", desc, hours, "", "Labor Hours"])

    if req.include_parts:
        job_clause_sm = ""
        job_params_sm: list = []
        if req.job_ids:
            placeholders = ",".join("?" for _ in req.job_ids)
            job_clause_sm = f"AND sm.job_id IN ({placeholders})"
            job_params_sm = list(req.job_ids)

        cursor = await db.execute(
            f"""SELECT sm.job_id, j.job_name, j.job_number,
                       SUM(sm.qty * COALESCE(sm.unit_cost_at_move, p.weighted_avg_cost, 0)) AS parts_cost,
                       SUM(sm.qty * COALESCE(sm.unit_sell_at_move, p.company_sell_price, 0)) AS parts_sell
                FROM stock_movements sm
                JOIN parts p ON p.id = sm.part_id
                LEFT JOIN jobs j ON j.id = sm.job_id
                WHERE sm.movement_type IN ('consume', 'transfer')
                  AND sm.to_location_type = 'job'
                  AND DATE(sm.created_at) >= ? AND DATE(sm.created_at) <= ?
                  {job_clause_sm}
                GROUP BY sm.job_id""",
            [req.period_start, req.period_end] + job_params_sm,
        )
        for row in await cursor.fetchall():
            job_label = f"{row['job_number'] or '?'} {row['job_name'] or 'Unknown'}"
            cost = round(row["parts_cost"] or 0, 2)
            sell = round(row["parts_sell"] or 0, 2)
            desc = f"{req.period_start} to {req.period_end} parts"
            writer.writerow([end_date_formatted, job_label, "Parts", desc, sell, "", "Accounts Receivable"])
            writer.writerow([end_date_formatted, job_label, "Parts", desc, "", sell, "Parts Revenue"])
            writer.writerow([end_date_formatted, job_label, "COGS-Parts", desc, cost, "", "COGS-Parts"])

    output.seek(0)
    filename = format_report_filename("general_ledger", req.period_start, req.period_end)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


async def _export_payroll_csv(
    db: aiosqlite.Connection, req: BookkeeperExportRequest
) -> StreamingResponse:
    """Generate Payroll CSV for ADP/Gusto — employee hours + pay rate.

    Columns are customizable via the payroll_columns setting.
    Available columns: Employee ID, Employee Name, Period Start, Period End,
    Regular Hours, Overtime Hours, Total Hours, Pay Rate, Gross Pay,
    Job Name, Job Number, Bill Rate Type.
    """
    import json as _json

    # Load customizable columns from settings
    default_cols = [
        "Employee ID", "Employee Name", "Period Start", "Period End",
        "Regular Hours", "Overtime Hours", "Total Hours", "Pay Rate",
    ]
    cursor = await db.execute(
        "SELECT value FROM settings WHERE key = 'payroll_columns'"
    )
    col_row = await cursor.fetchone()
    if col_row and col_row["value"]:
        try:
            cols = _json.loads(col_row["value"])
            if isinstance(cols, list) and len(cols) > 0:
                default_cols = cols
        except (ValueError, TypeError):
            pass

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(default_cols)

    cursor = await db.execute(
        """SELECT le.user_id, u.display_name,
                  SUM(COALESCE(le.regular_hours, 0)) AS reg_hours,
                  SUM(COALESCE(le.overtime_hours, 0)) AS ot_hours,
                  COALESCE(
                      (SELECT wh.pay_rate FROM wage_history wh
                       WHERE wh.user_id = le.user_id
                         AND wh.effective_date <= ?
                       ORDER BY wh.effective_date DESC LIMIT 1),
                      u.pay_rate,
                      0
                  ) AS pay_rate
           FROM labor_entries le
           JOIN users u ON u.id = le.user_id
           WHERE le.status IN ('clocked_out', 'edited', 'approved')
             AND DATE(le.clock_in) >= ? AND DATE(le.clock_in) <= ?
           GROUP BY le.user_id, u.display_name
           ORDER BY u.display_name""",
        (req.period_end, req.period_start, req.period_end),
    )
    for row in await cursor.fetchall():
        reg = round(row["reg_hours"], 2)
        ot = round(row["ot_hours"], 2)
        rate = round(row["pay_rate"] or 0, 2)
        gross = round((reg * rate) + (ot * rate * 1.5), 2)

        # Build row based on requested columns
        col_map = {
            "Employee ID": row["user_id"],
            "Employee Name": row["display_name"],
            "Period Start": req.period_start,
            "Period End": req.period_end,
            "Regular Hours": reg,
            "Overtime Hours": ot,
            "Total Hours": round(reg + ot, 2),
            "Pay Rate": rate,
            "Gross Pay": gross,
            "Job Name": "",  # Not available in group-by query
            "Job Number": "",
            "Bill Rate Type": "",
        }
        csv_row = [col_map.get(c, "") for c in default_cols]
        writer.writerow(csv_row)

    output.seek(0)
    filename = format_report_filename("payroll", req.period_start, req.period_end)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# ═══════════════════════════════════════════════════════════════════
# Filename + Location Helpers
# ═══════════════════════════════════════════════════════════════════

def format_report_filename(
    report_type: str,
    start: str,
    end: str,
    *,
    subject: str | None = None,
    ext: str = "csv",
) -> str:
    """Build a standardized, filesystem-safe report filename.

    Convention from People Delta plan:
      Timesheet-{Subject}-{Start}-{End}.{ext}
      PreBilling-{Subject}-{Start}-{End}.{ext}
      LaborOverview-{Start}-{End}.{ext}
      Bookkeeper-{Format}-{Start}-{End}.{ext}
      Profitability-{Start}-{End}.{ext}

    Characters unsafe for filenames are replaced with hyphens.
    """
    import re
    type_map = {
        "timesheet": "Timesheet",
        "pre-billing": "PreBilling",
        "pre_billing": "PreBilling",
        "labor-overview": "LaborOverview",
        "labor_overview": "LaborOverview",
        "profitability": "Profitability",
        "bookkeeper": "Bookkeeper",
        "quickbooks": "Bookkeeper-QuickBooks",
        "general_ledger": "Bookkeeper-GeneralLedger",
        "payroll": "Bookkeeper-Payroll",
    }
    prefix = type_map.get(report_type, report_type.title())
    safe_subject = re.sub(r'[^\w\-]', '-', subject) if subject else None
    parts = [prefix]
    if safe_subject:
        parts.append(safe_subject)
    parts.append(start)
    parts.append(end)
    return "-".join(parts) + f".{ext}"


def _format_location(loc_type: str | None, loc_id: int | None) -> str | None:
    """Format a location type + id into a human-readable string."""
    if not loc_type:
        return None
    labels = {
        "warehouse": "Warehouse",
        "truck": "Truck",
        "job": "Job",
        "pulled": "Pulled/Staged",
    }
    prefix = labels.get(loc_type, loc_type.title())
    return f"{prefix} #{loc_id}" if loc_id else prefix


# ══════════════════════════════════════════════════════════════════
# REPORT ANNOTATIONS
# ══════════════════════════════════════════════════════════════════

@router.get("/annotations")
async def list_annotations(
    report_type: str = Query(...),
    context_key: str = Query(...),
    db: aiosqlite.Connection = Depends(get_db),
    _user: dict = Depends(require_permission("view_reports")),
) -> ApiResponse[list[ReportAnnotationResponse]]:
    """List all annotations for a specific report instance."""
    rows = await db.execute_fetchall(
        """
        SELECT a.*, u.display_name AS author_name
        FROM report_annotations a
        JOIN users u ON u.id = a.author_id
        WHERE a.report_type = ? AND a.context_key = ?
        ORDER BY a.created_at ASC
        """,
        (report_type, context_key),
    )
    items = [
        ReportAnnotationResponse(
            id=r["id"],
            report_type=r["report_type"],
            context_key=r["context_key"],
            content=r["content"],
            author_id=r["author_id"],
            author_name=r["author_name"] or "Unknown",
            created_at=r["created_at"],
            updated_at=r["updated_at"],
        )
        for r in rows
    ]
    return ApiResponse(data=items)


@router.post("/annotations", status_code=201)
async def create_annotation(
    body: ReportAnnotationCreate,
    db: aiosqlite.Connection = Depends(get_db),
    user: dict = Depends(require_permission("view_reports")),
) -> ApiResponse[ReportAnnotationResponse]:
    """Add a note to a report."""
    now = datetime.utcnow().isoformat()
    cursor = await db.execute(
        """
        INSERT INTO report_annotations (report_type, context_key, content, author_id, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (body.report_type, body.context_key, body.content, user["id"], now, now),
    )
    await db.commit()
    row_id = cursor.lastrowid
    display_name = user.get("display_name", "Unknown")
    return ApiResponse(
        data=ReportAnnotationResponse(
            id=row_id,
            report_type=body.report_type,
            context_key=body.context_key,
            content=body.content,
            author_id=user["id"],
            author_name=display_name,
            created_at=now,
            updated_at=now,
        )
    )


@router.put("/annotations/{annotation_id}")
async def update_annotation(
    annotation_id: int,
    body: ReportAnnotationUpdate,
    db: aiosqlite.Connection = Depends(get_db),
    user: dict = Depends(require_permission("view_reports")),
) -> ApiResponse[ReportAnnotationResponse]:
    """Edit an annotation (author-only)."""
    cursor = await db.execute(
        "SELECT * FROM report_annotations WHERE id = ?", (annotation_id,)
    )
    row = await cursor.fetchone()
    if not row:
        raise HTTPException(404, "Annotation not found")
    if row["author_id"] != user["id"]:
        raise HTTPException(403, "Only the author can edit this annotation")
    now = datetime.utcnow().isoformat()
    await db.execute(
        "UPDATE report_annotations SET content = ?, updated_at = ? WHERE id = ?",
        (body.content, now, annotation_id),
    )
    await db.commit()
    return ApiResponse(
        data=ReportAnnotationResponse(
            id=annotation_id,
            report_type=row["report_type"],
            context_key=row["context_key"],
            content=body.content,
            author_id=row["author_id"],
            author_name=user.get("display_name", "Unknown"),
            created_at=row["created_at"],
            updated_at=now,
        )
    )


@router.delete("/annotations/{annotation_id}", status_code=204)
async def delete_annotation(
    annotation_id: int,
    db: aiosqlite.Connection = Depends(get_db),
    user: dict = Depends(require_permission("view_reports")),
) -> None:
    """Delete an annotation (author-only or admin)."""
    cursor = await db.execute(
        "SELECT author_id FROM report_annotations WHERE id = ?", (annotation_id,)
    )
    row = await cursor.fetchone()
    if not row:
        raise HTTPException(404, "Annotation not found")
    is_admin = "admin" in (user.get("hats") or [])
    if row["author_id"] != user["id"] and not is_admin:
        raise HTTPException(403, "Only the author or an admin can delete this")
    await db.execute("DELETE FROM report_annotations WHERE id = ?", (annotation_id,))
    await db.commit()


# ══════════════════════════════════════════════════════════════════
# REPORT TEMPLATES
# ══════════════════════════════════════════════════════════════════

@router.get("/templates")
async def list_templates(
    report_type: str | None = Query(None),
    db: aiosqlite.Connection = Depends(get_db),
    _user: dict = Depends(require_permission("view_reports")),
) -> ApiResponse[list[ReportTemplateResponse]]:
    """List all saved report templates, optionally filtered by type."""
    if report_type:
        rows = await db.execute_fetchall(
            "SELECT * FROM report_templates WHERE report_type = ? ORDER BY name",
            (report_type,),
        )
    else:
        rows = await db.execute_fetchall(
            "SELECT * FROM report_templates ORDER BY report_type, name"
        )
    items = [
        ReportTemplateResponse(
            id=r["id"],
            name=r["name"],
            report_type=r["report_type"],
            config_json=json.loads(r["config_json"]) if r["config_json"] else {},
            created_by=r["created_by"],
            created_at=r["created_at"],
            updated_at=r["updated_at"],
        )
        for r in rows
    ]
    return ApiResponse(data=items)


@router.post("/templates", status_code=201)
async def create_template(
    body: ReportTemplateCreate,
    db: aiosqlite.Connection = Depends(get_db),
    user: dict = Depends(require_permission("view_reports")),
) -> ApiResponse[ReportTemplateResponse]:
    """Save current filters as a named template."""
    now = datetime.utcnow().isoformat()
    cursor = await db.execute(
        """
        INSERT INTO report_templates (name, report_type, config_json, created_by, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (body.name, body.report_type, json.dumps(body.config_json), user["id"], now, now),
    )
    await db.commit()
    return ApiResponse(
        data=ReportTemplateResponse(
            id=cursor.lastrowid,
            name=body.name,
            report_type=body.report_type,
            config_json=body.config_json,
            created_by=user["id"],
            created_at=now,
            updated_at=now,
        )
    )


@router.put("/templates/{template_id}")
async def update_template(
    template_id: int,
    body: ReportTemplateUpdate,
    db: aiosqlite.Connection = Depends(get_db),
    user: dict = Depends(require_permission("view_reports")),
) -> ApiResponse[ReportTemplateResponse]:
    """Update a template (creator-only)."""
    cursor = await db.execute(
        "SELECT * FROM report_templates WHERE id = ?", (template_id,)
    )
    row = await cursor.fetchone()
    if not row:
        raise HTTPException(404, "Template not found")
    if row["created_by"] != user["id"]:
        raise HTTPException(403, "Only the creator can edit this template")
    now = datetime.utcnow().isoformat()
    new_name = body.name or row["name"]
    new_config = json.dumps(body.config_json) if body.config_json is not None else row["config_json"]
    await db.execute(
        "UPDATE report_templates SET name = ?, config_json = ?, updated_at = ? WHERE id = ?",
        (new_name, new_config, now, template_id),
    )
    await db.commit()
    return ApiResponse(
        data=ReportTemplateResponse(
            id=template_id,
            name=new_name,
            report_type=row["report_type"],
            config_json=json.loads(new_config) if isinstance(new_config, str) else new_config,
            created_by=row["created_by"],
            created_at=row["created_at"],
            updated_at=now,
        )
    )


@router.delete("/templates/{template_id}", status_code=204)
async def delete_template(
    template_id: int,
    db: aiosqlite.Connection = Depends(get_db),
    user: dict = Depends(require_permission("view_reports")),
) -> None:
    """Delete a template (creator-only)."""
    cursor = await db.execute(
        "SELECT created_by FROM report_templates WHERE id = ?", (template_id,)
    )
    row = await cursor.fetchone()
    if not row:
        raise HTTPException(404, "Template not found")
    if row["created_by"] != user["id"]:
        raise HTTPException(403, "Only the creator can delete this template")
    await db.execute("DELETE FROM report_templates WHERE id = ?", (template_id,))
    await db.commit()


# ══════════════════════════════════════════════════════════════════
# REPORT SHARE TOKENS
# ══════════════════════════════════════════════════════════════════

@router.post("/share-tokens", status_code=201)
async def create_share_token(
    body: ReportShareTokenCreate,
    db: aiosqlite.Connection = Depends(get_db),
    user: dict = Depends(require_permission("view_reports")),
) -> ApiResponse[ReportShareTokenResponse]:
    """Generate a shareable link for a report."""
    token = secrets.token_urlsafe(24)
    now = datetime.utcnow().isoformat()
    expires_at = None
    if body.expires_in_days:
        expires_at = (datetime.utcnow() + timedelta(days=body.expires_in_days)).isoformat()

    cursor = await db.execute(
        """
        INSERT INTO report_share_tokens
            (token, report_type, context_params, label, created_by, expires_at, is_active, created_at)
        VALUES (?, ?, ?, ?, ?, ?, 1, ?)
        """,
        (token, body.report_type, json.dumps(body.context_params), body.label,
         user["id"], expires_at, now),
    )
    await db.commit()
    return ApiResponse(
        data=ReportShareTokenResponse(
            id=cursor.lastrowid,
            token=token,
            report_type=body.report_type,
            context_params=body.context_params,
            label=body.label,
            created_by=user["id"],
            expires_at=expires_at,
            is_active=True,
            created_at=now,
            share_url=f"/public/reports/{token}",
        )
    )


@router.get("/share-tokens")
async def list_share_tokens(
    db: aiosqlite.Connection = Depends(get_db),
    _user: dict = Depends(require_permission("view_reports")),
) -> ApiResponse[list[ReportShareTokenResponse]]:
    """List all active share tokens."""
    rows = await db.execute_fetchall(
        "SELECT * FROM report_share_tokens WHERE is_active = 1 ORDER BY created_at DESC"
    )
    items = [
        ReportShareTokenResponse(
            id=r["id"],
            token=r["token"],
            report_type=r["report_type"],
            context_params=json.loads(r["context_params"]) if r["context_params"] else {},
            label=r["label"],
            created_by=r["created_by"],
            expires_at=r["expires_at"],
            last_accessed_at=r["last_accessed_at"],
            is_active=bool(r["is_active"]),
            created_at=r["created_at"],
            share_url=f"/public/reports/{r['token']}",
        )
        for r in rows
    ]
    return ApiResponse(data=items)


@router.delete("/share-tokens/{token_id}", status_code=204)
async def revoke_share_token(
    token_id: int,
    db: aiosqlite.Connection = Depends(get_db),
    _user: dict = Depends(require_permission("view_reports")),
) -> None:
    """Revoke a share token (deactivate without deleting)."""
    result = await db.execute(
        "UPDATE report_share_tokens SET is_active = 0 WHERE id = ?", (token_id,)
    )
    await db.commit()
    if result.rowcount == 0:
        raise HTTPException(404, "Share token not found")


# ══════════════════════════════════════════════════════════════════
# EXPORT BUNDLE (ZIP)
# ══════════════════════════════════════════════════════════════════

@router.post("/exports/bundle")
async def generate_export_bundle(
    body: ExportBundleRequest,
    db: aiosqlite.Connection = Depends(get_db),
    _user: dict = Depends(require_permission("export_reports")),
) -> StreamingResponse:
    """Generate a ZIP bundle containing multiple CSV exports."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for idx, item in enumerate(body.exports):
            csv_content = await _generate_csv_for_bundle(db, item)
            import re as _re
            safe_type = _re.sub(r'[^\w\-]', '-', item.report_type)
            filename = f"{idx+1:02d}-{safe_type}"
            if item.job_id:
                filename += f"-job{item.job_id}"
            filename += f"-{item.start_date}-to-{item.end_date}.csv"
            zf.writestr(filename, csv_content)
    buf.seek(0)
    return StreamingResponse(
        iter([buf.read()]),
        media_type="application/zip",
        headers={"Content-Disposition": 'attachment; filename="report-bundle.zip"'},
    )


async def _generate_csv_for_bundle(
    db: aiosqlite.Connection, item
) -> str:
    """Generate CSV content for a single export bundle item."""
    output = io.StringIO()
    writer = csv.writer(output)
    rt = item.report_type.replace("-", "_")

    if rt == "pre_billing":
        writer.writerow(["Employee", "Date", "Regular Hours", "OT Hours", "Total Hours", "Bill Rate Type"])
        rows = await db.execute_fetchall(
            """
            SELECT u.display_name, le.work_date, le.regular_hours, le.overtime_hours,
                   (le.regular_hours + le.overtime_hours) AS total, brt.name AS rate_type
            FROM labor_entries le
            JOIN users u ON u.id = le.user_id
            LEFT JOIN bill_rate_types brt ON brt.id = le.bill_rate_type_id
            WHERE le.job_id = ? AND le.work_date BETWEEN ? AND ?
            ORDER BY le.work_date, u.display_name
            """,
            (item.job_id, item.start_date, item.end_date),
        )
        for r in rows:
            writer.writerow([r[0], r[1], r[2], r[3], r[4], r[5] or "Standard"])

    elif rt == "timesheet":
        writer.writerow(["Employee", "Date", "Clock In", "Clock Out", "Regular", "OT", "Total"])
        params = [item.start_date, item.end_date]
        emp_clause = ""
        if item.employee_id:
            emp_clause = "AND le.user_id = ?"
            params.append(item.employee_id)
        rows = await db.execute_fetchall(
            f"""
            SELECT u.display_name, le.work_date, le.clock_in, le.clock_out,
                   le.regular_hours, le.overtime_hours, (le.regular_hours + le.overtime_hours)
            FROM labor_entries le
            JOIN users u ON u.id = le.user_id
            WHERE le.work_date BETWEEN ? AND ? {emp_clause}
            ORDER BY le.work_date, u.display_name
            """,
            params,
        )
        for r in rows:
            writer.writerow(list(r))

    elif rt == "labor_overview":
        writer.writerow(["Employee", "Job", "Total Hours", "Regular", "OT", "Bill Rate Type"])
        rows = await db.execute_fetchall(
            """
            SELECT u.display_name, j.job_name, SUM(le.regular_hours + le.overtime_hours),
                   SUM(le.regular_hours), SUM(le.overtime_hours), brt.name
            FROM labor_entries le
            JOIN users u ON u.id = le.user_id
            JOIN jobs j ON j.id = le.job_id
            LEFT JOIN bill_rate_types brt ON brt.id = le.bill_rate_type_id
            WHERE le.work_date BETWEEN ? AND ?
            GROUP BY u.display_name, j.job_name, brt.name
            ORDER BY u.display_name, j.job_name
            """,
            (item.start_date, item.end_date),
        )
        for r in rows:
            writer.writerow(list(r))

    elif rt == "profitability":
        writer.writerow(["Job", "Total Hours", "Labor Cost", "Parts Cost", "Total Cost"])
        rows = await db.execute_fetchall(
            """
            SELECT j.job_name,
                   COALESCE(SUM(le.regular_hours + le.overtime_hours), 0) AS hours,
                   0.0 AS labor_cost, 0.0 AS parts_cost, 0.0 AS total_cost
            FROM jobs j
            LEFT JOIN labor_entries le ON le.job_id = j.id AND le.work_date BETWEEN ? AND ?
            WHERE j.status = 'active'
            GROUP BY j.id
            ORDER BY j.job_name
            """,
            (item.start_date, item.end_date),
        )
        for r in rows:
            writer.writerow(list(r))

    else:
        writer.writerow(["Info"])
        writer.writerow([f"Report type '{item.report_type}' — export not yet implemented"])

    return output.getvalue()
