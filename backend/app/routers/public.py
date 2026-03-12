"""
Public routes — unauthenticated access to shared resources.

Currently supports shared report tokens.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException

from app.database import get_db
from app.models.common import ApiResponse
from app.models.reports import PublicReportData, ReportAnnotationResponse

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/public", tags=["Public"])


@router.get("/reports/{token}")
async def get_shared_report(
    token: str,
    db: aiosqlite.Connection = Depends(get_db),
) -> ApiResponse[PublicReportData]:
    """
    Access a report via a share token.  No authentication required.

    Returns the report data with any annotations, or 404/410 if the
    token is invalid, expired, or revoked.
    """
    row = await db.execute_fetchone(
        "SELECT * FROM report_share_tokens WHERE token = ?", (token,)
    )
    if not row:
        raise HTTPException(404, "Share link not found")
    if not row["is_active"]:
        raise HTTPException(410, "This share link has been revoked")
    if row["expires_at"]:
        expires = datetime.fromisoformat(row["expires_at"])
        if datetime.utcnow() > expires:
            raise HTTPException(410, "This share link has expired")

    # Mark last accessed
    await db.execute(
        "UPDATE report_share_tokens SET last_accessed_at = ? WHERE id = ?",
        (datetime.utcnow().isoformat(), row["id"]),
    )
    await db.commit()

    context_params = json.loads(row["context_params"]) if row["context_params"] else {}
    report_type = row["report_type"]

    # Fetch annotations for this report
    context_key = _build_context_key(report_type, context_params)
    annotation_rows = await db.execute_fetchall(
        """
        SELECT a.*, u.display_name AS author_name
        FROM report_annotations a
        JOIN users u ON u.id = a.author_id
        WHERE a.report_type = ? AND a.context_key = ?
        ORDER BY a.created_at ASC
        """,
        (report_type, context_key),
    )
    annotations = [
        ReportAnnotationResponse(
            id=a["id"],
            report_type=a["report_type"],
            context_key=a["context_key"],
            content=a["content"],
            author_id=a["author_id"],
            author_name=a["author_name"] or "Unknown",
            created_at=a["created_at"],
            updated_at=a["updated_at"],
        )
        for a in annotation_rows
    ]

    # Generate report data based on type
    data = await _generate_report_data(db, report_type, context_params)

    return ApiResponse(
        data=PublicReportData(
            report_type=report_type,
            label=row["label"],
            generated_at=datetime.utcnow().isoformat(),
            context_params=context_params,
            data=data,
            annotations=annotations,
        )
    )


def _build_context_key(report_type: str, params: dict) -> str:
    """Build a context_key from report type and params."""
    parts = [report_type]
    if params.get("job_id"):
        parts.append(f"job:{params['job_id']}")
    if params.get("employee_id"):
        parts.append(f"emp:{params['employee_id']}")
    if params.get("start_date"):
        parts.append(params["start_date"])
    if params.get("end_date"):
        parts.append(params["end_date"])
    return "|".join(parts)


async def _generate_report_data(
    db: aiosqlite.Connection, report_type: str, params: dict
) -> dict:
    """Generate report data dict based on type. Simplified versions for sharing."""
    start = params.get("start_date", "2020-01-01")
    end = params.get("end_date", "2099-12-31")

    if report_type == "pre_billing":
        job_id = params.get("job_id")
        if not job_id:
            return {"error": "Missing job_id in share context"}
        rows = await db.execute_fetchall(
            """
            SELECT u.display_name AS employee, le.work_date, le.regular_hours,
                   le.overtime_hours, (le.regular_hours + le.overtime_hours) AS total,
                   brt.name AS bill_rate_type
            FROM labor_entries le
            JOIN users u ON u.id = le.user_id
            LEFT JOIN bill_rate_types brt ON brt.id = le.bill_rate_type_id
            WHERE le.job_id = ? AND le.work_date BETWEEN ? AND ?
            ORDER BY le.work_date, u.display_name
            """,
            (job_id, start, end),
        )
        return {
            "job_id": job_id,
            "entries": [dict(r) for r in rows],
            "total_hours": sum(float(r["total"] or 0) for r in rows),
        }

    elif report_type == "timesheet":
        emp_id = params.get("employee_id")
        clause = "AND le.user_id = ?" if emp_id else ""
        bind = [start, end] + ([emp_id] if emp_id else [])
        rows = await db.execute_fetchall(
            f"""
            SELECT u.display_name AS employee, le.work_date, le.clock_in, le.clock_out,
                   le.regular_hours, le.overtime_hours
            FROM labor_entries le
            JOIN users u ON u.id = le.user_id
            WHERE le.work_date BETWEEN ? AND ? {clause}
            ORDER BY u.display_name, le.work_date
            """,
            bind,
        )
        return {"entries": [dict(r) for r in rows]}

    elif report_type == "labor_overview":
        rows = await db.execute_fetchall(
            """
            SELECT u.display_name AS employee, j.name AS job_name,
                   SUM(le.regular_hours) AS regular,
                   SUM(le.overtime_hours) AS overtime,
                   SUM(le.regular_hours + le.overtime_hours) AS total
            FROM labor_entries le
            JOIN users u ON u.id = le.user_id
            JOIN jobs j ON j.id = le.job_id
            WHERE le.work_date BETWEEN ? AND ?
            GROUP BY u.id, j.id
            ORDER BY u.display_name, j.name
            """,
            (start, end),
        )
        return {"entries": [dict(r) for r in rows]}

    elif report_type == "profitability":
        rows = await db.execute_fetchall(
            """
            SELECT j.name AS job_name,
                   COALESCE(SUM(le.regular_hours + le.overtime_hours), 0) AS total_hours
            FROM jobs j
            LEFT JOIN labor_entries le ON le.job_id = j.id AND le.work_date BETWEEN ? AND ?
            WHERE j.status = 'active'
            GROUP BY j.id
            ORDER BY j.name
            """,
            (start, end),
        )
        return {"jobs": [dict(r) for r in rows]}

    elif report_type == "daily_report":
        job_id = params.get("job_id")
        report_date = params.get("date", start)
        if not job_id:
            return {"error": "Missing job_id in share context"}
        row = await db.execute_fetchone(
            """
            SELECT dr.*, j.name AS job_name
            FROM daily_reports dr
            JOIN jobs j ON j.id = dr.job_id
            WHERE dr.job_id = ? AND dr.report_date = ?
            """,
            (job_id, report_date),
        )
        if not row:
            return {"error": "Daily report not found"}
        return dict(row)

    return {"info": f"Report type '{report_type}' not yet supported for sharing"}
