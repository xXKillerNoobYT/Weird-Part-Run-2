"""
Report PDF generation — timesheets, labor overviews, pre-billing, profitability.

Uses fpdf2 (same lib as PO PDFs). Generates to backend/tmp/pdfs/ with auto-cleanup.
Falls back to CSV on error.
"""

from __future__ import annotations

import logging
import os
from datetime import datetime
from pathlib import Path
from typing import Any

import aiosqlite

logger = logging.getLogger(__name__)

_BACKEND_DIR = Path(__file__).resolve().parent.parent
PDF_OUTPUT_DIR = _BACKEND_DIR / "tmp" / "pdfs"


class ReportPDFService:
    """Generates PDF exports for reports."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    async def generate_timesheet_pdf(
        self,
        employee_id: int | None,
        start: str,
        end: str,
        group_by: str = "day",
    ) -> str | None:
        """Generate a timesheet PDF. Returns file path or None on failure."""
        try:
            from fpdf import FPDF
        except ImportError:
            logger.warning("fpdf2 not installed, cannot generate PDF")
            return None

        # Fetch data
        conditions = [
            "le.status IN ('clocked_out', 'edited', 'approved')",
            "DATE(le.clock_in) >= ?",
            "DATE(le.clock_in) <= ?",
        ]
        params: list[Any] = [start, end]
        employee_name = "All Employees"

        if employee_id:
            conditions.append("le.user_id = ?")
            params.append(employee_id)
            cursor = await self.db.execute(
                "SELECT display_name FROM users WHERE id = ?", (employee_id,)
            )
            row = await cursor.fetchone()
            if row:
                employee_name = row["display_name"]

        where = " AND ".join(conditions)
        cursor = await self.db.execute(
            f"""SELECT u.display_name, DATE(le.clock_in) AS work_date,
                       le.clock_in, le.clock_out,
                       j.job_name, j.job_number,
                       COALESCE(le.regular_hours, 0) AS reg,
                       COALESCE(le.overtime_hours, 0) AS ot
                FROM labor_entries le
                JOIN users u ON u.id = le.user_id
                LEFT JOIN jobs j ON j.id = le.job_id
                WHERE {where}
                ORDER BY le.clock_in ASC""",
            params,
        )
        rows = await cursor.fetchall()

        company = await self._get_company()

        # Build PDF
        pdf = FPDF()
        pdf.set_auto_page_break(auto=True, margin=15)
        pdf.add_page()

        # Header
        self._pdf_header(pdf, company, "Timesheet Report")
        pdf.set_font("Helvetica", "I", 10)
        pdf.cell(0, 6, f"Employee: {employee_name}  |  Period: {start} to {end}  |  Grouped by: {group_by}", ln=True)
        pdf.ln(4)

        # Table header
        col_widths = [35, 25, 30, 30, 20, 20, 20]
        headers = ["Employee", "Date", "Clock In", "Clock Out", "Reg Hrs", "OT Hrs", "Total"]
        pdf.set_font("Helvetica", "B", 9)
        pdf.set_fill_color(240, 240, 240)
        for i, h in enumerate(headers):
            pdf.cell(col_widths[i], 7, h, border=1, fill=True)
        pdf.ln()

        # Data rows
        pdf.set_font("Helvetica", "", 8)
        total_reg = 0.0
        total_ot = 0.0
        for row in rows:
            reg = row["reg"]
            ot = row["ot"]
            total_reg += reg
            total_ot += ot
            vals = [
                row["display_name"][:18],
                row["work_date"],
                row["clock_in"][-8:] if row["clock_in"] else "",
                row["clock_out"][-8:] if row["clock_out"] else "",
                f"{reg:.2f}",
                f"{ot:.2f}",
                f"{reg + ot:.2f}",
            ]
            for i, v in enumerate(vals):
                pdf.cell(col_widths[i], 6, str(v), border=1)
            pdf.ln()

        # Totals row
        pdf.set_font("Helvetica", "B", 9)
        pdf.cell(sum(col_widths[:4]), 7, "TOTALS", border=1, fill=True)
        pdf.cell(col_widths[4], 7, f"{total_reg:.2f}", border=1, fill=True)
        pdf.cell(col_widths[5], 7, f"{total_ot:.2f}", border=1, fill=True)
        pdf.cell(col_widths[6], 7, f"{total_reg + total_ot:.2f}", border=1, fill=True)
        pdf.ln()

        return self._save_pdf(pdf, f"timesheet_{start}_{end}")

    async def generate_labor_overview_pdf(
        self, start: str, end: str
    ) -> str | None:
        """Generate labor overview PDF. Returns file path or None."""
        try:
            from fpdf import FPDF
        except ImportError:
            return None

        cursor = await self.db.execute(
            """SELECT u.display_name,
                      SUM(COALESCE(le.regular_hours, 0)) AS reg,
                      SUM(COALESCE(le.overtime_hours, 0)) AS ot,
                      COUNT(DISTINCT DATE(le.clock_in)) AS days,
                      COUNT(DISTINCT le.job_id) AS jobs
               FROM labor_entries le
               JOIN users u ON u.id = le.user_id
               WHERE le.status IN ('clocked_out', 'edited', 'approved')
                 AND DATE(le.clock_in) >= ? AND DATE(le.clock_in) <= ?
               GROUP BY le.user_id, u.display_name
               ORDER BY u.display_name""",
            (start, end),
        )
        rows = await cursor.fetchall()

        company = await self._get_company()

        pdf = FPDF()
        pdf.set_auto_page_break(auto=True, margin=15)
        pdf.add_page()

        self._pdf_header(pdf, company, "Labor Overview Report")
        pdf.set_font("Helvetica", "I", 10)
        pdf.cell(0, 6, f"Period: {start} to {end}", ln=True)
        pdf.ln(4)

        col_widths = [50, 25, 25, 25, 25, 25]
        headers = ["Employee", "Reg Hrs", "OT Hrs", "Total Hrs", "Days", "Jobs"]
        pdf.set_font("Helvetica", "B", 9)
        pdf.set_fill_color(240, 240, 240)
        for i, h in enumerate(headers):
            pdf.cell(col_widths[i], 7, h, border=1, fill=True)
        pdf.ln()

        pdf.set_font("Helvetica", "", 8)
        grand_reg = 0.0
        grand_ot = 0.0
        for row in rows:
            reg = round(row["reg"], 2)
            ot = round(row["ot"], 2)
            grand_reg += reg
            grand_ot += ot
            vals = [
                row["display_name"][:25],
                f"{reg:.2f}",
                f"{ot:.2f}",
                f"{reg + ot:.2f}",
                str(row["days"]),
                str(row["jobs"]),
            ]
            for i, v in enumerate(vals):
                pdf.cell(col_widths[i], 6, str(v), border=1)
            pdf.ln()

        pdf.set_font("Helvetica", "B", 9)
        pdf.cell(col_widths[0], 7, "TOTALS", border=1, fill=True)
        pdf.cell(col_widths[1], 7, f"{grand_reg:.2f}", border=1, fill=True)
        pdf.cell(col_widths[2], 7, f"{grand_ot:.2f}", border=1, fill=True)
        pdf.cell(col_widths[3], 7, f"{grand_reg + grand_ot:.2f}", border=1, fill=True)
        pdf.cell(col_widths[4], 7, "", border=1, fill=True)
        pdf.cell(col_widths[5], 7, "", border=1, fill=True)
        pdf.ln()

        return self._save_pdf(pdf, f"labor_overview_{start}_{end}")

    async def generate_pre_billing_pdf(
        self, job_id: int, start: str, end: str
    ) -> str | None:
        """Generate pre-billing PDF for a job."""
        try:
            from fpdf import FPDF
        except ImportError:
            return None

        cursor = await self.db.execute(
            "SELECT job_name, job_number FROM jobs WHERE id = ?", (job_id,)
        )
        job = await cursor.fetchone()
        job_label = f"{job['job_number']} - {job['job_name']}" if job else f"Job #{job_id}"

        # Labor data
        cursor = await self.db.execute(
            """SELECT u.display_name, DATE(le.clock_in) AS work_date,
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
        labor_rows = await cursor.fetchall()

        # Material data
        cursor = await self.db.execute(
            """SELECT p.part_number, p.description, wm.quantity, wm.created_at
               FROM warehouse_movements wm
               JOIN parts p ON p.id = wm.part_id
               WHERE wm.job_id = ?
                 AND wm.movement_type = 'pull'
                 AND DATE(wm.created_at) >= ? AND DATE(wm.created_at) <= ?
               ORDER BY wm.created_at ASC""",
            (job_id, start, end),
        )
        material_rows = await cursor.fetchall()

        company = await self._get_company()

        pdf = FPDF()
        pdf.set_auto_page_break(auto=True, margin=15)
        pdf.add_page()

        self._pdf_header(pdf, company, "Pre-Billing Report")
        pdf.set_font("Helvetica", "I", 10)
        pdf.cell(0, 6, f"Job: {job_label}  |  Period: {start} to {end}", ln=True)
        pdf.ln(4)

        # --- Labor section ---
        pdf.set_font("Helvetica", "B", 11)
        pdf.cell(0, 8, "LABOR", ln=True)

        col_widths = [50, 30, 30, 30, 30]
        headers_l = ["Employee", "Date", "Reg Hrs", "OT Hrs", "Total"]
        pdf.set_font("Helvetica", "B", 9)
        pdf.set_fill_color(240, 240, 240)
        for i, h in enumerate(headers_l):
            pdf.cell(col_widths[i], 7, h, border=1, fill=True)
        pdf.ln()

        pdf.set_font("Helvetica", "", 8)
        total_reg = 0.0
        total_ot = 0.0
        for row in labor_rows:
            reg = row["reg"]
            ot = row["ot"]
            total_reg += reg
            total_ot += ot
            vals = [row["display_name"][:25], row["work_date"], f"{reg:.2f}", f"{ot:.2f}", f"{reg + ot:.2f}"]
            for i, v in enumerate(vals):
                pdf.cell(col_widths[i], 6, str(v), border=1)
            pdf.ln()

        pdf.set_font("Helvetica", "B", 9)
        pdf.cell(sum(col_widths[:2]), 7, "LABOR TOTALS", border=1, fill=True)
        pdf.cell(col_widths[2], 7, f"{total_reg:.2f}", border=1, fill=True)
        pdf.cell(col_widths[3], 7, f"{total_ot:.2f}", border=1, fill=True)
        pdf.cell(col_widths[4], 7, f"{total_reg + total_ot:.2f}", border=1, fill=True)
        pdf.ln(10)

        # --- Materials section ---
        pdf.set_font("Helvetica", "B", 11)
        pdf.cell(0, 8, "MATERIALS", ln=True)

        col_widths_m = [40, 70, 25, 40]
        headers_m = ["Part #", "Description", "Qty", "Date"]
        pdf.set_font("Helvetica", "B", 9)
        for i, h in enumerate(headers_m):
            pdf.cell(col_widths_m[i], 7, h, border=1, fill=True)
        pdf.ln()

        pdf.set_font("Helvetica", "", 8)
        for row in material_rows:
            vals = [
                str(row["part_number"] or "")[:20],
                str(row["description"] or "")[:35],
                str(row["quantity"]),
                str(row["created_at"])[:10],
            ]
            for i, v in enumerate(vals):
                pdf.cell(col_widths_m[i], 6, v, border=1)
            pdf.ln()

        return self._save_pdf(pdf, f"prebilling_{job_id}_{start}_{end}")

    async def generate_profitability_pdf(
        self, start: str, end: str, job_id: int | None = None
    ) -> str | None:
        """Generate profitability PDF. Returns file path or None."""
        try:
            from fpdf import FPDF
        except ImportError:
            return None

        conditions = [
            "DATE(le.clock_in) >= ?",
            "DATE(le.clock_in) <= ?",
            "le.status IN ('clocked_out', 'edited', 'approved')",
        ]
        params: list[Any] = [start, end]
        if job_id:
            conditions.append("le.job_id = ?")
            params.append(job_id)

        cursor = await self.db.execute(
            f"""SELECT j.id AS job_id, j.job_name, j.job_number,
                       SUM(COALESCE(le.regular_hours, 0) + COALESCE(le.overtime_hours, 0)) AS total_hours,
                       COUNT(DISTINCT le.user_id) AS employees,
                       COUNT(DISTINCT DATE(le.clock_in)) AS days
                FROM labor_entries le
                LEFT JOIN jobs j ON j.id = le.job_id
                WHERE {' AND '.join(conditions)}
                GROUP BY j.id, j.job_name, j.job_number
                ORDER BY total_hours DESC""",
            params,
        )
        rows = await cursor.fetchall()

        company = await self._get_company()

        pdf = FPDF()
        pdf.set_auto_page_break(auto=True, margin=15)
        pdf.add_page()

        self._pdf_header(pdf, company, "Profitability Report")
        pdf.set_font("Helvetica", "I", 10)
        pdf.cell(0, 6, f"Period: {start} to {end}", ln=True)
        pdf.ln(4)

        col_widths = [20, 50, 30, 30, 25, 25]
        headers = ["Job #", "Job Name", "Hours", "Employees", "Days", "Avg Hrs/Day"]
        pdf.set_font("Helvetica", "B", 9)
        pdf.set_fill_color(240, 240, 240)
        for i, h in enumerate(headers):
            pdf.cell(col_widths[i], 7, h, border=1, fill=True)
        pdf.ln()

        pdf.set_font("Helvetica", "", 8)
        for row in rows:
            avg = round(row["total_hours"] / max(row["days"], 1), 2)
            vals = [
                str(row["job_number"] or "?")[:10],
                str(row["job_name"] or "Unknown")[:25],
                f"{row['total_hours']:.2f}",
                str(row["employees"]),
                str(row["days"]),
                f"{avg:.2f}",
            ]
            for i, v in enumerate(vals):
                pdf.cell(col_widths[i], 6, v, border=1)
            pdf.ln()

        return self._save_pdf(pdf, f"profitability_{start}_{end}")

    # ── Helpers ─────────────────────────────────────────────────

    async def _get_company(self) -> dict[str, Any]:
        """Get primary company profile for header."""
        cursor = await self.db.execute(
            "SELECT * FROM company_profiles WHERE is_primary = 1 LIMIT 1"
        )
        row = await cursor.fetchone()
        if row:
            return dict(row)
        return {"company_name": "Company", "address_line1": "", "city": "", "state": "", "zip_code": ""}

    def _pdf_header(self, pdf: Any, company: dict, title: str) -> None:
        """Render company header and report title."""
        # Company name
        pdf.set_font("Helvetica", "B", 16)
        pdf.cell(0, 10, company.get("company_name", "Company"), ln=True)

        # Address
        pdf.set_font("Helvetica", "", 9)
        addr = company.get("address_line1", "")
        city_state = f"{company.get('city', '')}, {company.get('state', '')} {company.get('zip_code', '')}"
        if addr:
            pdf.cell(0, 5, addr, ln=True)
        if city_state.strip(", "):
            pdf.cell(0, 5, city_state, ln=True)
        pdf.ln(3)

        # Report title
        pdf.set_font("Helvetica", "B", 14)
        pdf.cell(0, 10, title, ln=True)
        pdf.set_draw_color(59, 130, 246)  # Blue accent line
        pdf.line(10, pdf.get_y(), 200, pdf.get_y())
        pdf.ln(5)

    def _save_pdf(self, pdf: Any, filename_base: str) -> str:
        """Save PDF to tmp directory and return file path."""
        PDF_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{filename_base}_{timestamp}.pdf"
        filepath = PDF_OUTPUT_DIR / filename
        pdf.output(str(filepath))
        logger.info("Generated report PDF: %s", filepath)
        return str(filepath)
