"""
Report Service — Daily report generation, JSON assembly, query.

Generates structured daily reports at midnight (via scheduler) for every
job that had labor activity that day. Reports contain:
- Worker clock data (in/out times, GPS, hours)
- Question responses (global + one-time)
- Parts consumed
- Cost summary

Reports are stored as JSON blobs and rendered as locked "notebook pages"
in the frontend. Once generated, they're read-only.
"""

from __future__ import annotations

import json
import logging
from datetime import date, datetime, timedelta

import aiosqlite

from app.models.jobs import DailyReportFull, DailyReportResponse

logger = logging.getLogger(__name__)


class ReportService:
    """Daily report generation and retrieval."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    # ── Generate ──────────────────────────────────────────────────

    async def generate_daily_report(
        self, job_id: int, report_date: date
    ) -> DailyReportResponse | None:
        """Generate a daily report for a specific job and date.

        Collects all labor entries, question responses, and parts consumed
        for that job on that date, assembles them into a structured JSON
        blob, and stores it in the daily_reports table.

        Returns None if no labor activity on that date.
        """
        date_str = report_date.isoformat()

        # Check if report already exists
        cursor = await self.db.execute(
            "SELECT id FROM daily_reports WHERE job_id = ? AND report_date = ?",
            (job_id, date_str),
        )
        existing = await cursor.fetchone()
        if existing:
            logger.debug("Report already exists for job %d on %s", job_id, date_str)
            return await self.get_report(job_id, date_str)

        # Get labor entries for this job on this date
        cursor = await self.db.execute(
            """SELECT le.*, u.display_name
               FROM labor_entries le
               JOIN users u ON u.id = le.user_id
               WHERE le.job_id = ?
                 AND DATE(le.clock_in) = ?
               ORDER BY le.clock_in ASC""",
            (job_id, date_str),
        )
        labor_rows = await cursor.fetchall()

        if not labor_rows:
            return None  # No activity = no report

        # Get job info (including bill rate type)
        cursor = await self.db.execute(
            """SELECT j.job_name, j.job_number, brt.name AS bill_rate_type_name
               FROM jobs j
               LEFT JOIN bill_rate_types brt ON brt.id = j.bill_rate_type_id
               WHERE j.id = ?""",
            (job_id,),
        )
        job_row = await cursor.fetchone()

        # Build workers array
        workers = []
        for entry in labor_rows:
            worker_data = {
                "user_id": entry["user_id"],
                "display_name": entry["display_name"],
                "clock_in": entry["clock_in"],
                "clock_out": entry["clock_out"],
                "regular_hours": entry["regular_hours"] or 0,
                "overtime_hours": entry["overtime_hours"] or 0,
                "drive_time_minutes": entry["drive_time_minutes"] or 0,
                "clock_in_gps": {
                    "lat": entry["clock_in_gps_lat"],
                    "lng": entry["clock_in_gps_lng"],
                } if entry["clock_in_gps_lat"] else None,
                "clock_out_gps": {
                    "lat": entry["clock_out_gps_lat"],
                    "lng": entry["clock_out_gps_lng"],
                } if entry["clock_out_gps_lat"] else None,
                "clock_in_photo": entry["clock_in_photo_path"],
                "clock_out_photo": entry["clock_out_photo_path"],
                "responses": [],
                "one_time_responses": [],
            }

            # Get global question responses for this labor entry
            cursor = await self.db.execute(
                """SELECT cor.*, coq.question_text, coq.answer_type
                   FROM clock_out_responses cor
                   JOIN clock_out_questions coq ON coq.id = cor.question_id
                   WHERE cor.labor_entry_id = ?
                   ORDER BY coq.sort_order ASC""",
                (entry["id"],),
            )
            responses = await cursor.fetchall()
            for resp in responses:
                worker_data["responses"].append({
                    "question": resp["question_text"],
                    "type": resp["answer_type"],
                    "answer": (
                        bool(resp["answer_bool"]) if resp["answer_type"] == "yes_no"
                        else resp["answer_text"]
                    ),
                    "photo": resp["photo_path"],
                })

            # Get one-time question responses answered by this user on this date
            cursor = await self.db.execute(
                """SELECT * FROM one_time_questions
                   WHERE job_id = ? AND answered_by = ? AND DATE(answered_at) = ?
                   ORDER BY answered_at ASC""",
                (job_id, entry["user_id"], date_str),
            )
            otq_rows = await cursor.fetchall()
            for otq in otq_rows:
                worker_data["one_time_responses"].append({
                    "question": otq["question_text"],
                    "answer": otq["answer_text"],
                    "photo": otq["answer_photo_path"],
                })

            workers.append(worker_data)

        # Get parts consumed on this job on this date
        cursor = await self.db.execute(
            """SELECT jp.*, p.name AS part_name, p.code AS part_code
               FROM job_parts jp
               JOIN parts p ON p.id = jp.part_id
               WHERE jp.job_id = ? AND DATE(jp.consumed_at) = ?
               ORDER BY jp.consumed_at ASC""",
            (job_id, date_str),
        )
        parts_rows = await cursor.fetchall()
        parts_consumed = [
            {
                "part_name": r["part_name"],
                "part_code": r["part_code"],
                "qty": r["qty_consumed"],
                "unit_cost": r["unit_cost_at_consume"] or 0,
                "total": (r["qty_consumed"] or 0) * (r["unit_cost_at_consume"] or 0),
            }
            for r in parts_rows
        ]

        # Build summary
        total_labor = sum(
            (w["regular_hours"] or 0) + (w["overtime_hours"] or 0) for w in workers
        )
        total_parts_cost = sum(p["total"] for p in parts_consumed)

        report_data = {
            "job_id": job_id,
            "job_name": job_row["job_name"] if job_row else "Unknown",
            "job_number": job_row["job_number"] if job_row else "?",
            "bill_rate_type": job_row["bill_rate_type_name"] if job_row else None,
            "report_date": date_str,
            "workers": workers,
            "parts_consumed": parts_consumed,
            "summary": {
                "total_labor_hours": round(total_labor, 2),
                "total_parts_cost": round(total_parts_cost, 2),
                "worker_count": len(workers),
            },
        }

        # Insert the report
        cursor = await self.db.execute(
            """INSERT INTO daily_reports (job_id, report_date, report_json)
               VALUES (?, ?, ?)""",
            (job_id, date_str, json.dumps(report_data)),
        )
        await self.db.commit()

        logger.info(
            "Generated daily report for job %d on %s (%d workers, $%.2f parts)",
            job_id, date_str, len(workers), total_parts_cost,
        )
        return await self.get_report(job_id, date_str)

    async def generate_all_pending_reports(self, target_date: date | None = None) -> list[DailyReportResponse]:
        """Generate reports for all jobs that had activity on the target date.

        Called by the midnight scheduler. If target_date is None, uses yesterday.
        """
        if target_date is None:
            target_date = date.today() - timedelta(days=1)

        date_str = target_date.isoformat()

        # Find all jobs with labor activity on this date that don't have a report yet
        cursor = await self.db.execute(
            """SELECT DISTINCT le.job_id
               FROM labor_entries le
               WHERE DATE(le.clock_in) = ?
                 AND le.job_id NOT IN (
                     SELECT job_id FROM daily_reports WHERE report_date = ?
                 )""",
            (date_str, date_str),
        )
        rows = await cursor.fetchall()
        job_ids = [r["job_id"] for r in rows]

        reports = []
        for job_id in job_ids:
            report = await self.generate_daily_report(job_id, target_date)
            if report:
                reports.append(report)

        logger.info(
            "Generated %d pending reports for %s (checked %d jobs)",
            len(reports), date_str, len(job_ids),
        )
        return reports

    async def catch_up_missed_reports(self) -> int:
        """Generate reports for any dates with labor activity but no report.

        Called on startup to catch up if the server was down at midnight.
        """
        cursor = await self.db.execute(
            """SELECT DISTINCT le.job_id, DATE(le.clock_in) AS work_date
               FROM labor_entries le
               WHERE le.status = 'clocked_out'
                 AND DATE(le.clock_in) < DATE('now')
                 AND NOT EXISTS (
                     SELECT 1 FROM daily_reports dr
                     WHERE dr.job_id = le.job_id AND dr.report_date = DATE(le.clock_in)
                 )"""
        )
        rows = await cursor.fetchall()

        count = 0
        for row in rows:
            report = await self.generate_daily_report(
                row["job_id"], date.fromisoformat(row["work_date"])
            )
            if report:
                count += 1

        if count > 0:
            logger.info("Caught up %d missed daily reports", count)
        return count

    # ── Query ─────────────────────────────────────────────────────

    async def get_report(self, job_id: int, report_date: str) -> DailyReportResponse | None:
        """Get report metadata for a specific job + date."""
        cursor = await self.db.execute(
            """SELECT dr.*, j.job_name, j.job_number
               FROM daily_reports dr
               LEFT JOIN jobs j ON j.id = dr.job_id
               WHERE dr.job_id = ? AND dr.report_date = ?""",
            (job_id, report_date),
        )
        row = await cursor.fetchone()
        if not row:
            return None
        return self._row_to_response(row)

    async def get_report_full(self, job_id: int, report_date: str) -> DailyReportFull | None:
        """Get full report including parsed JSON data."""
        cursor = await self.db.execute(
            """SELECT dr.*, j.job_name, j.job_number
               FROM daily_reports dr
               LEFT JOIN jobs j ON j.id = dr.job_id
               WHERE dr.job_id = ? AND dr.report_date = ?""",
            (job_id, report_date),
        )
        row = await cursor.fetchone()
        if not row:
            return None

        report_data = json.loads(row["report_json"]) if row["report_json"] else {}
        return DailyReportFull(
            id=row["id"],
            job_id=row["job_id"],
            job_name=row["job_name"],
            job_number=row["job_number"],
            report_date=row["report_date"],
            status=row["status"],
            generated_at=row["generated_at"],
            report_data=report_data,
        )

    async def get_reports_for_job(self, job_id: int) -> list[DailyReportResponse]:
        """Get all reports for a job, newest first."""
        cursor = await self.db.execute(
            """SELECT dr.*, j.job_name, j.job_number
               FROM daily_reports dr
               LEFT JOIN jobs j ON j.id = dr.job_id
               WHERE dr.job_id = ?
               ORDER BY dr.report_date DESC""",
            (job_id,),
        )
        rows = await cursor.fetchall()
        return [self._row_to_response(r) for r in rows]

    async def get_all_reports(
        self, date_from: str | None = None, date_to: str | None = None
    ) -> list[DailyReportResponse]:
        """Get all reports across all jobs, optionally filtered by date range."""
        conditions: list[str] = []
        params: list = []

        if date_from:
            conditions.append("dr.report_date >= ?")
            params.append(date_from)
        if date_to:
            conditions.append("dr.report_date <= ?")
            params.append(date_to)

        where = " AND ".join(conditions) if conditions else "1=1"
        cursor = await self.db.execute(
            f"""SELECT dr.*, j.job_name, j.job_number
                FROM daily_reports dr
                LEFT JOIN jobs j ON j.id = dr.job_id
                WHERE {where}
                ORDER BY dr.report_date DESC, j.job_name ASC""",
            params,
        )
        rows = await cursor.fetchall()
        return [self._row_to_response(r) for r in rows]

    # ── Helpers ───────────────────────────────────────────────────

    def _row_to_response(self, row: aiosqlite.Row) -> DailyReportResponse:
        # Extract summary from JSON for list views
        report_data = json.loads(row["report_json"]) if row["report_json"] else {}
        summary = report_data.get("summary", {})

        return DailyReportResponse(
            id=row["id"],
            job_id=row["job_id"],
            job_name=row["job_name"],
            job_number=row["job_number"],
            report_date=row["report_date"],
            status=row["status"],
            generated_at=row["generated_at"],
            reviewed_by=row["reviewed_by"],
            reviewed_at=row["reviewed_at"],
            worker_count=summary.get("worker_count", 0),
            total_labor_hours=summary.get("total_labor_hours", 0),
            total_parts_cost=summary.get("total_parts_cost", 0),
        )
