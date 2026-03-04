"""
PO PDF generation and clipboard text formatting.

Two delivery methods:
  1. PDF file — branded header (logo, company info), line items table,
     delivery instructions. Stored temporarily, auto-deleted after 3 days.
  2. Plain text — formatted summary for pasting into emails/portals.

PDF generation uses fpdf2 (lightweight, pure-Python, no system deps).
If fpdf2 is not installed, falls back to a plain-text file with .txt extension.
"""

from __future__ import annotations

import logging
import os
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any

import aiosqlite

logger = logging.getLogger(__name__)

# Directory for temporary PDF files
_BACKEND_DIR = Path(__file__).resolve().parent.parent
PDF_OUTPUT_DIR = _BACKEND_DIR / "tmp" / "pdfs"


class PDFService:
    """Generates PO PDFs and formatted clipboard text."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    async def generate_po_pdf(self, po_id: int) -> str | None:
        """Generate a branded PDF for a purchase order.

        Returns the file path to the generated PDF, or None on failure.
        The file is stored in backend/tmp/pdfs/ and auto-cleaned after 3 days.
        """
        po = await self._get_po_full(po_id)
        if not po:
            return None

        company = await self._get_primary_company()
        lines = await self._get_po_lines(po_id)

        # Ensure output directory exists
        PDF_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

        filename = f"PO-{po['po_number']}-{datetime.now().strftime('%Y%m%d%H%M%S')}.pdf"
        filepath = PDF_OUTPUT_DIR / filename

        try:
            self._build_pdf(filepath, po, company, lines)
        except ImportError:
            # fpdf2 not installed — fall back to text file
            logger.warning("fpdf2 not installed — generating plain text PO instead")
            filepath = filepath.with_suffix(".txt")
            text = self._format_clipboard_text(po, company, lines)
            filepath.write_text(text, encoding="utf-8")

        # Record the PDF path and generation time on the PO
        await self.db.execute(
            "UPDATE purchase_orders SET pdf_path = ?, pdf_generated_at = datetime('now') WHERE id = ?",
            (str(filepath), po_id),
        )
        await self.db.commit()

        logger.info("Generated PO PDF: %s", filepath)
        return str(filepath)

    async def get_clipboard_text(self, po_id: int) -> str | None:
        """Generate formatted plain text for clipboard copy.

        This is the lightweight alternative to PDF — for pasting into
        emails, supplier portals, or chat messages.
        """
        po = await self._get_po_full(po_id)
        if not po:
            return None

        company = await self._get_primary_company()
        lines = await self._get_po_lines(po_id)

        return self._format_clipboard_text(po, company, lines)

    async def cleanup_old_pdfs(self, max_age_days: int = 3) -> int:
        """Delete PDF files older than N days and clear pdf_path in DB.

        Called by the scheduler every night. PDF data is ephemeral —
        the PO data in the DB is permanent and PDFs can be re-generated.
        """
        count = 0

        # Find POs with old PDF files
        cursor = await self.db.execute(
            """
            SELECT id, pdf_path FROM purchase_orders
            WHERE pdf_path IS NOT NULL
              AND pdf_generated_at < datetime('now', ?)
            """,
            (f"-{max_age_days} days",),
        )
        rows = await cursor.fetchall()

        for row in rows:
            path = Path(row["pdf_path"])
            if path.exists():
                try:
                    path.unlink()
                    count += 1
                except OSError as e:
                    logger.warning("Failed to delete PDF %s: %s", path, e)

            # Clear the path in DB regardless (file may have been manually removed)
            await self.db.execute(
                "UPDATE purchase_orders SET pdf_path = NULL, pdf_generated_at = NULL WHERE id = ?",
                (row["id"],),
            )

        if count > 0:
            await self.db.commit()
            logger.info("Cleaned up %d old PO PDFs (>%d days)", count, max_age_days)

        return count

    # ── PDF Building ──────────────────────────────────────────

    def _build_pdf(
        self,
        filepath: Path,
        po: dict,
        company: dict | None,
        lines: list[dict],
    ) -> None:
        """Build the actual PDF file using fpdf2.

        Layout:
        - Company header (logo + address)
        - PO number and date
        - Supplier info
        - Line items table
        - Totals
        - Delivery instructions
        """
        from fpdf import FPDF  # type: ignore[import-untyped]

        pdf = FPDF()
        pdf.set_auto_page_break(auto=True, margin=25)
        pdf.add_page()

        # ── Company Header ──
        if company:
            # Logo (if available)
            logo_path = company.get("logo_path")
            if logo_path and Path(logo_path).exists():
                try:
                    pdf.image(logo_path, x=10, y=10, w=40)
                    pdf.set_xy(55, 10)
                except Exception:
                    pdf.set_xy(10, 10)
            else:
                pdf.set_xy(10, 10)

            pdf.set_font("Helvetica", "B", 16)
            pdf.cell(0, 8, company.get("name", ""), new_x="LMARGIN", new_y="NEXT")

            pdf.set_font("Helvetica", "", 9)
            addr_parts = []
            if company.get("address_street"):
                addr_parts.append(company["address_street"])
            city_state = ""
            if company.get("address_city"):
                city_state = company["address_city"]
            if company.get("address_state"):
                city_state += f", {company['address_state']}"
            if company.get("address_zip"):
                city_state += f" {company['address_zip']}"
            if city_state:
                addr_parts.append(city_state)
            if company.get("phone"):
                addr_parts.append(f"Phone: {company['phone']}")
            if company.get("email"):
                addr_parts.append(f"Email: {company['email']}")

            for line in addr_parts:
                pdf.cell(0, 4, line, new_x="LMARGIN", new_y="NEXT")

            if company.get("contractor_license"):
                pdf.cell(0, 4, f"License: {company['contractor_license']}", new_x="LMARGIN", new_y="NEXT")

        # ── PO Title ──
        pdf.ln(8)
        pdf.set_font("Helvetica", "B", 14)
        pdf.cell(0, 10, f"PURCHASE ORDER: {po['po_number']}", new_x="LMARGIN", new_y="NEXT")

        # ── PO Meta ──
        pdf.set_font("Helvetica", "", 10)
        pdf.cell(95, 6, f"Date: {po.get('order_date') or 'Draft'}")
        pdf.cell(0, 6, f"Status: {po['status'].upper()}", new_x="LMARGIN", new_y="NEXT")

        if po.get("expected_delivery"):
            pdf.cell(0, 6, f"Expected Delivery: {po['expected_delivery']}", new_x="LMARGIN", new_y="NEXT")
        if po.get("shipping_method"):
            pdf.cell(0, 6, f"Shipping: {po['shipping_method']}", new_x="LMARGIN", new_y="NEXT")

        # ── Supplier ──
        pdf.ln(4)
        pdf.set_font("Helvetica", "B", 11)
        pdf.cell(0, 6, "SHIP FROM:", new_x="LMARGIN", new_y="NEXT")
        pdf.set_font("Helvetica", "", 10)
        pdf.cell(0, 5, po.get("supplier_name") or f"Supplier #{po['supplier_id']}", new_x="LMARGIN", new_y="NEXT")

        # ── Line Items Table ──
        pdf.ln(6)
        pdf.set_font("Helvetica", "B", 9)

        # Table header
        col_widths = [15, 30, 70, 20, 25, 30]
        headers = ["#", "Part #", "Description", "Qty", "Unit $", "Total $"]
        for w, h in zip(col_widths, headers):
            pdf.cell(w, 7, h, border=1)
        pdf.ln()

        # Table rows
        pdf.set_font("Helvetica", "", 9)
        for i, line in enumerate(lines, 1):
            unit = line.get("unit_cost") or 0
            total = unit * line.get("qty_ordered", 0)

            pdf.cell(col_widths[0], 6, str(i), border=1)
            pdf.cell(col_widths[1], 6, str(line.get("part_code") or ""), border=1)
            pdf.cell(col_widths[2], 6, str(line.get("part_name") or "")[:45], border=1)
            pdf.cell(col_widths[3], 6, str(line.get("qty_ordered", 0)), border=1, align="R")
            pdf.cell(col_widths[4], 6, f"${unit:.2f}" if unit else "-", border=1, align="R")
            pdf.cell(col_widths[5], 6, f"${total:.2f}" if unit else "-", border=1, align="R")
            pdf.ln()

        # ── Totals ──
        pdf.ln(4)
        pdf.set_font("Helvetica", "", 10)
        subtotal = po.get("subtotal") or 0
        tax = po.get("tax_amount") or 0
        shipping = po.get("shipping_cost") or 0
        total_cost = po.get("total_cost") or 0

        x_label = 130
        x_value = 165
        pdf.set_x(x_label)
        pdf.cell(35, 6, "Subtotal:")
        pdf.cell(25, 6, f"${subtotal:.2f}", align="R", new_x="LMARGIN", new_y="NEXT")

        if tax > 0:
            pdf.set_x(x_label)
            pdf.cell(35, 6, "Tax:")
            pdf.cell(25, 6, f"${tax:.2f}", align="R", new_x="LMARGIN", new_y="NEXT")

        if shipping > 0:
            pdf.set_x(x_label)
            pdf.cell(35, 6, "Shipping:")
            pdf.cell(25, 6, f"${shipping:.2f}", align="R", new_x="LMARGIN", new_y="NEXT")

        pdf.set_font("Helvetica", "B", 11)
        pdf.set_x(x_label)
        pdf.cell(35, 7, "TOTAL:")
        pdf.cell(25, 7, f"${total_cost:.2f}", align="R", new_x="LMARGIN", new_y="NEXT")

        # ── Notes ──
        if po.get("notes"):
            pdf.ln(6)
            pdf.set_font("Helvetica", "B", 10)
            pdf.cell(0, 6, "Delivery Instructions:", new_x="LMARGIN", new_y="NEXT")
            pdf.set_font("Helvetica", "", 9)
            pdf.multi_cell(0, 5, po["notes"])

        # ── Save ──
        pdf.output(str(filepath))

    # ── Clipboard Text Formatting ─────────────────────────────

    def _format_clipboard_text(
        self,
        po: dict,
        company: dict | None,
        lines: list[dict],
    ) -> str:
        """Format a PO as plain text for clipboard pasting."""
        sections: list[str] = []

        # Header
        if company:
            sections.append(company.get("name", ""))
            if company.get("phone"):
                sections.append(f"Phone: {company['phone']}")
            if company.get("email"):
                sections.append(f"Email: {company['email']}")
            sections.append("")

        sections.append(f"PURCHASE ORDER: {po['po_number']}")
        sections.append(f"Date: {po.get('order_date') or 'Draft'}")
        supplier_label = po.get("supplier_name") or "Supplier #{}".format(po.get("supplier_id", "?"))
        sections.append(f"Supplier: {supplier_label}")

        if po.get("expected_delivery"):
            sections.append(f"Expected Delivery: {po['expected_delivery']}")
        sections.append("")

        # Line items
        sections.append(f"{'#':<4} {'Part #':<15} {'Description':<35} {'Qty':>5} {'Unit $':>10} {'Total':>10}")
        sections.append("-" * 82)

        for i, line in enumerate(lines, 1):
            unit = line.get("unit_cost") or 0
            qty = line.get("qty_ordered", 0)
            total = unit * qty
            code = str(line.get("part_code") or "")[:14]
            desc = str(line.get("part_name") or "")[:34]
            unit_str = f"${unit:.2f}" if unit else "-"
            total_str = f"${total:.2f}" if unit else "-"
            sections.append(f"{i:<4} {code:<15} {desc:<35} {qty:>5} {unit_str:>10} {total_str:>10}")

        sections.append("-" * 82)

        # Totals
        subtotal = po.get("subtotal") or 0
        tax = po.get("tax_amount") or 0
        shipping = po.get("shipping_cost") or 0
        total_cost = po.get("total_cost") or 0

        sections.append(f"{'Subtotal:':>70} ${subtotal:>10.2f}")
        if tax > 0:
            sections.append(f"{'Tax:':>70} ${tax:>10.2f}")
        if shipping > 0:
            sections.append(f"{'Shipping:':>70} ${shipping:>10.2f}")
        sections.append(f"{'TOTAL:':>70} ${total_cost:>10.2f}")

        # Notes
        if po.get("notes"):
            sections.append("")
            sections.append(f"Delivery Instructions: {po['notes']}")

        return "\n".join(sections)

    # ── Data Fetching ─────────────────────────────────────────

    async def _get_po_full(self, po_id: int) -> dict | None:
        """Get PO with supplier name."""
        cursor = await self.db.execute(
            """
            SELECT po.*, s.name AS supplier_name
            FROM purchase_orders po
            LEFT JOIN suppliers s ON s.id = po.supplier_id
            WHERE po.id = ?
            """,
            (po_id,),
        )
        return await cursor.fetchone()

    async def _get_po_lines(self, po_id: int) -> list[dict]:
        """Get PO line items with part details."""
        cursor = await self.db.execute(
            """
            SELECT pli.*, p.name AS part_name, p.code AS part_code
            FROM po_line_items pli
            LEFT JOIN parts p ON p.id = pli.part_id
            WHERE pli.po_id = ?
            ORDER BY pli.id
            """,
            (po_id,),
        )
        return await cursor.fetchall()

    async def _get_primary_company(self) -> dict | None:
        """Get the primary company profile for branding."""
        cursor = await self.db.execute(
            "SELECT * FROM company_profiles WHERE is_primary = 1 ORDER BY id LIMIT 1"
        )
        return await cursor.fetchone()
