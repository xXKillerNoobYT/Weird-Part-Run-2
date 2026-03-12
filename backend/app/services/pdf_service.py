"""
PO PDF generation and clipboard text formatting.

Three delivery methods:
  1. PDF file — branded header (logo, company info), line items table,
     delivery instructions. Stored temporarily, auto-deleted after 3 days.
  2. Plain text — formatted summary for pasting into emails/portals.
  3. Bundled PDF — combined PDF for a PO Group (multiple POs to one supplier).

PDF generation uses fpdf2 (lightweight, pure-Python, no system deps).
If fpdf2 is not installed, falls back to a plain-text file with .txt extension.
"""

from __future__ import annotations

import json
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
        pdf_settings = await self._get_pdf_settings()

        # Ensure output directory exists
        PDF_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

        filename = f"PO-{po['po_number']}-{datetime.now().strftime('%Y%m%d%H%M%S')}.pdf"
        filepath = PDF_OUTPUT_DIR / filename

        try:
            self._build_pdf(filepath, po, company, lines, pdf_settings)
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
        pdf_settings = await self._get_pdf_settings()

        return self._format_clipboard_text(po, company, lines, pdf_settings)

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
        pdf_settings: dict | None = None,
    ) -> None:
        """Build the actual PDF file using fpdf2.

        Layout:
        - Accent bar + company header (logo + address)
        - PO number and date
        - Supplier info
        - Line items table (columns configurable via pdf_settings)
        - Totals
        - Delivery instructions / payment terms / footer
        """
        from fpdf import FPDF  # type: ignore[import-untyped]

        s = pdf_settings or {}
        accent = s.get("accent_color", "#3B82F6")
        show_unit = s.get("show_unit_prices", True)
        show_ext = s.get("show_extended", True)
        footer_text = s.get("footer_text", "")
        payment_terms = s.get("payment_terms", "")
        default_delivery = s.get("delivery_notes", "")

        # Parse accent color to RGB tuple
        accent_rgb = self._hex_to_rgb(accent)

        pdf = FPDF()
        pdf.set_auto_page_break(auto=True, margin=25)
        pdf.add_page()

        # ── Accent Bar ──
        pdf.set_fill_color(*accent_rgb)
        pdf.rect(0, 0, 210, 4, "F")

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
        if payment_terms:
            pdf.cell(0, 6, f"Payment Terms: {payment_terms}", new_x="LMARGIN", new_y="NEXT")

        # ── Supplier ──
        pdf.ln(4)
        pdf.set_font("Helvetica", "B", 11)
        pdf.cell(0, 6, "SHIP FROM:", new_x="LMARGIN", new_y="NEXT")
        pdf.set_font("Helvetica", "", 10)
        pdf.cell(0, 5, po.get("supplier_name") or f"Supplier #{po['supplier_id']}", new_x="LMARGIN", new_y="NEXT")

        # ── Line Items Table ──
        pdf.ln(6)
        pdf.set_font("Helvetica", "B", 9)

        # Build dynamic columns based on settings
        col_widths, headers = self._get_table_columns(show_unit, show_ext)

        # Table header with accent background
        pdf.set_fill_color(*accent_rgb)
        pdf.set_text_color(255, 255, 255)
        for w, h in zip(col_widths, headers):
            pdf.cell(w, 7, h, border=1, fill=True)
        pdf.ln()
        pdf.set_text_color(0, 0, 0)

        # Table rows
        pdf.set_font("Helvetica", "", 9)
        for i, line in enumerate(lines, 1):
            unit = line.get("unit_cost") or 0
            total = unit * line.get("qty_ordered", 0)

            col_idx = 0
            pdf.cell(col_widths[col_idx], 6, str(i), border=1); col_idx += 1
            pdf.cell(col_widths[col_idx], 6, str(line.get("part_code") or ""), border=1); col_idx += 1
            pdf.cell(col_widths[col_idx], 6, str(line.get("part_name") or "")[:45], border=1); col_idx += 1
            pdf.cell(col_widths[col_idx], 6, str(line.get("qty_ordered", 0)), border=1, align="R"); col_idx += 1
            if show_unit:
                pdf.cell(col_widths[col_idx], 6, f"${unit:.2f}" if unit else "-", border=1, align="R"); col_idx += 1
            if show_ext:
                pdf.cell(col_widths[col_idx], 6, f"${total:.2f}" if unit else "-", border=1, align="R")
            pdf.ln()

        # ── Totals ──
        if show_unit or show_ext:
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

        # ── Notes / Delivery Instructions ──
        notes = po.get("notes") or default_delivery
        if notes:
            pdf.ln(6)
            pdf.set_font("Helvetica", "B", 10)
            pdf.cell(0, 6, "Delivery Instructions:", new_x="LMARGIN", new_y="NEXT")
            pdf.set_font("Helvetica", "", 9)
            pdf.multi_cell(0, 5, notes)

        # ── Footer ──
        if footer_text:
            pdf.ln(8)
            pdf.set_draw_color(*accent_rgb)
            pdf.line(10, pdf.get_y(), 200, pdf.get_y())
            pdf.ln(3)
            pdf.set_font("Helvetica", "I", 8)
            pdf.set_text_color(100, 100, 100)
            pdf.multi_cell(0, 4, footer_text, align="C")
            pdf.set_text_color(0, 0, 0)

        # ── Save ──
        pdf.output(str(filepath))

    # ── Helper Methods ─────────────────────────────────────────

    @staticmethod
    def _hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
        """Convert #RRGGBB hex color to (R, G, B) tuple."""
        hex_color = hex_color.lstrip("#")
        if len(hex_color) != 6:
            return (59, 130, 246)  # fallback to blue-500
        try:
            return (
                int(hex_color[0:2], 16),
                int(hex_color[2:4], 16),
                int(hex_color[4:6], 16),
            )
        except ValueError:
            return (59, 130, 246)

    @staticmethod
    def _get_table_columns(show_unit: bool, show_ext: bool) -> tuple[list[int], list[str]]:
        """Build dynamic column widths and headers based on visibility settings.

        Always shows: #, Part #, Description, Qty
        Optionally shows: Unit $, Total $
        Distributes extra width to Description when columns are hidden.
        """
        # Base columns always present
        widths = [15, 30]  # #, Part #
        headers = ["#", "Part #"]

        # Description gets extra space when price columns are hidden
        desc_width = 70
        if not show_unit:
            desc_width += 25
        if not show_ext:
            desc_width += 30

        widths.append(desc_width)
        headers.append("Description")

        widths.append(20)  # Qty
        headers.append("Qty")

        if show_unit:
            widths.append(25)
            headers.append("Unit $")
        if show_ext:
            widths.append(30)
            headers.append("Total $")

        return widths, headers

    # ── Clipboard Text Formatting ─────────────────────────────

    def _format_clipboard_text(
        self,
        po: dict,
        company: dict | None,
        lines: list[dict],
        pdf_settings: dict | None = None,
    ) -> str:
        """Format a PO as plain text for clipboard pasting."""
        s = pdf_settings or {}
        show_unit = s.get("show_unit_prices", True)
        show_ext = s.get("show_extended", True)
        payment_terms = s.get("payment_terms", "")
        default_delivery = s.get("delivery_notes", "")

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
        if payment_terms:
            sections.append(f"Payment Terms: {payment_terms}")
        sections.append("")

        # Line items
        if show_unit and show_ext:
            sections.append(f"{'#':<4} {'Part #':<15} {'Description':<35} {'Qty':>5} {'Unit $':>10} {'Total':>10}")
            sections.append("-" * 82)
        elif show_unit:
            sections.append(f"{'#':<4} {'Part #':<15} {'Description':<35} {'Qty':>5} {'Unit $':>10}")
            sections.append("-" * 72)
        elif show_ext:
            sections.append(f"{'#':<4} {'Part #':<15} {'Description':<35} {'Qty':>5} {'Total':>10}")
            sections.append("-" * 72)
        else:
            sections.append(f"{'#':<4} {'Part #':<15} {'Description':<35} {'Qty':>5}")
            sections.append("-" * 62)

        for i, line in enumerate(lines, 1):
            unit = line.get("unit_cost") or 0
            qty = line.get("qty_ordered", 0)
            total = unit * qty
            code = str(line.get("part_code") or "")[:14]
            desc = str(line.get("part_name") or "")[:34]
            unit_str = f"${unit:.2f}" if unit else "-"
            total_str = f"${total:.2f}" if unit else "-"

            row = f"{i:<4} {code:<15} {desc:<35} {qty:>5}"
            if show_unit:
                row += f" {unit_str:>10}"
            if show_ext:
                row += f" {total_str:>10}"
            sections.append(row)

        sections.append("-" * (82 if (show_unit and show_ext) else 72 if (show_unit or show_ext) else 62))

        # Totals
        if show_unit or show_ext:
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
        notes = po.get("notes") or default_delivery
        if notes:
            sections.append("")
            sections.append(f"Delivery Instructions: {notes}")

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

    async def _get_pdf_settings(self) -> dict:
        """Get PDF template settings from the settings table.

        Returns a dict with sensible defaults if no settings are stored yet.
        These control accent color, column visibility, footer text, etc.
        """
        cursor = await self.db.execute(
            "SELECT key, value FROM settings WHERE category = 'pdf' ORDER BY key"
        )
        rows = await cursor.fetchall()

        settings: dict = {}
        for row in rows:
            try:
                settings[row["key"]] = json.loads(row["value"]) if row["value"] else None
            except (json.JSONDecodeError, TypeError):
                settings[row["key"]] = row["value"]

        return {
            "accent_color": settings.get("pdf_accent_color", "#3B82F6"),
            "show_unit_prices": settings.get("pdf_show_unit_prices", True),
            "show_extended": settings.get("pdf_show_extended", True),
            "footer_text": settings.get("pdf_footer_text", ""),
            "payment_terms": settings.get("pdf_payment_terms", "Net 30"),
            "delivery_notes": settings.get("pdf_delivery_notes", ""),
        }

    # ── Group / Bundled PDF Generation ────────────────────────

    async def generate_group_pdf(self, group_id: int) -> dict | None:
        """Generate a bundled PDF for a PO Group (multiple POs to one supplier).

        Creates a single PDF with:
          - Cover page (group name, supplier info, summary of all POs)
          - One section per PO (header, line items, totals)

        Also generates individual PDFs for each PO and stores references.

        Returns dict with:
          - pdf_path: path to the bundled PDF file
          - individual_pdfs: list of paths to individual PO PDFs
          - po_count: number of POs in the group
        """
        # Fetch group details
        cursor = await self.db.execute(
            """
            SELECT g.*, s.name AS supplier_name
            FROM po_groups g
            LEFT JOIN suppliers s ON s.id = g.supplier_id
            WHERE g.id = ?
            """,
            (group_id,),
        )
        group = await cursor.fetchone()
        if not group:
            return None

        # Fetch member POs
        cursor = await self.db.execute(
            """
            SELECT po.*, s.name AS supplier_name
            FROM po_group_members gm
            JOIN purchase_orders po ON po.id = gm.po_id
            LEFT JOIN suppliers s ON s.id = po.supplier_id
            WHERE gm.group_id = ?
            ORDER BY po.po_number
            """,
            (group_id,),
        )
        pos = await cursor.fetchall()

        if not pos:
            return None

        company = await self._get_primary_company()
        pdf_settings = await self._get_pdf_settings()

        # Generate individual PDFs for each PO
        individual_paths: list[str] = []
        for po in pos:
            path = await self.generate_po_pdf(po["id"])
            if path:
                individual_paths.append(path)

        # Generate bundled PDF
        PDF_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
        group_name_safe = (group["group_name"] or f"Group-{group_id}").replace(" ", "_")[:30]
        filename = f"Bundle-{group_name_safe}-{timestamp}.pdf"
        filepath = PDF_OUTPUT_DIR / filename

        try:
            # Gather all PO lines for each PO
            po_data: list[tuple[dict, list[dict]]] = []
            for po in pos:
                lines = await self._get_po_lines(po["id"])
                po_data.append((dict(po), lines))

            self._build_group_pdf(filepath, group, company, po_data, pdf_settings)
        except ImportError:
            # fpdf2 not installed — fall back to combined text file
            logger.warning("fpdf2 not installed — generating plain text bundle instead")
            filepath = filepath.with_suffix(".txt")
            text = self._format_group_clipboard_text(group, company, po_data)
            filepath.write_text(text, encoding="utf-8")

        # Store the bundled PDF path on the group
        individual_json = json.dumps(individual_paths)
        await self.db.execute(
            "UPDATE po_groups SET pdf_path = ?, individual_pdfs = ? WHERE id = ?",
            (str(filepath), individual_json, group_id),
        )
        await self.db.commit()

        logger.info("Generated bundled PDF for group %d: %s (%d POs)", group_id, filepath, len(pos))

        return {
            "pdf_path": str(filepath),
            "individual_pdfs": individual_paths,
            "po_count": len(pos),
        }

    async def get_group_clipboard_text(self, group_id: int) -> str | None:
        """Generate combined plain text for all POs in a group.

        Useful for pasting into email body when sending bundled orders
        to a supplier.
        """
        # Fetch group
        cursor = await self.db.execute(
            """
            SELECT g.*, s.name AS supplier_name
            FROM po_groups g
            LEFT JOIN suppliers s ON s.id = g.supplier_id
            WHERE g.id = ?
            """,
            (group_id,),
        )
        group = await cursor.fetchone()
        if not group:
            return None

        # Fetch member POs with their lines
        cursor = await self.db.execute(
            """
            SELECT po.*, s.name AS supplier_name
            FROM po_group_members gm
            JOIN purchase_orders po ON po.id = gm.po_id
            LEFT JOIN suppliers s ON s.id = po.supplier_id
            WHERE gm.group_id = ?
            ORDER BY po.po_number
            """,
            (group_id,),
        )
        pos = await cursor.fetchall()

        if not pos:
            return None

        company = await self._get_primary_company()
        pdf_settings = await self._get_pdf_settings()

        po_data: list[tuple[dict, list[dict]]] = []
        for po in pos:
            lines = await self._get_po_lines(po["id"])
            po_data.append((dict(po), lines))

        return self._format_group_clipboard_text(group, company, po_data, pdf_settings)

    def _build_group_pdf(
        self,
        filepath: Path,
        group: dict,
        company: dict | None,
        po_data: list[tuple[dict, list[dict]]],
        pdf_settings: dict | None = None,
    ) -> None:
        """Build a bundled PDF with cover page + individual PO sections.

        Layout:
        - Page 1: Cover sheet (group name, supplier, PO summary table)
        - Page 2+: Each PO gets its own page(s) with full line items
        """
        from fpdf import FPDF  # type: ignore[import-untyped]

        s = pdf_settings or {}
        accent_rgb = self._hex_to_rgb(s.get("accent_color", "#3B82F6"))

        pdf = FPDF()
        pdf.set_auto_page_break(auto=True, margin=25)

        # ══════════════════════════════════════════════════════
        # COVER PAGE
        # ══════════════════════════════════════════════════════
        pdf.add_page()

        # Accent bar
        pdf.set_fill_color(*accent_rgb)
        pdf.rect(0, 0, 210, 4, "F")

        # Company header
        if company:
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

        # Group title
        pdf.ln(10)
        pdf.set_font("Helvetica", "B", 16)
        pdf.cell(0, 10, "PURCHASE ORDER BUNDLE", new_x="LMARGIN", new_y="NEXT")

        pdf.set_font("Helvetica", "", 11)
        pdf.cell(0, 6, f"Group: {group['group_name'] or 'Unnamed'}", new_x="LMARGIN", new_y="NEXT")
        supplier_label = group.get("supplier_name") or f"Supplier #{group.get('supplier_id', '?')}"
        pdf.cell(0, 6, f"Supplier: {supplier_label}", new_x="LMARGIN", new_y="NEXT")
        pdf.cell(0, 6, f"Date: {datetime.now().strftime('%Y-%m-%d')}", new_x="LMARGIN", new_y="NEXT")
        pdf.cell(0, 6, f"Total POs: {len(po_data)}", new_x="LMARGIN", new_y="NEXT")

        # Summary table
        pdf.ln(6)
        pdf.set_font("Helvetica", "B", 10)
        pdf.cell(0, 7, "ORDER SUMMARY", new_x="LMARGIN", new_y="NEXT")

        col_widths = [50, 35, 30, 25, 50]
        headers = ["PO Number", "Date", "Status", "Lines", "Total"]
        pdf.set_font("Helvetica", "B", 9)
        pdf.set_fill_color(*accent_rgb)
        pdf.set_text_color(255, 255, 255)
        for w, h in zip(col_widths, headers):
            pdf.cell(w, 7, h, border=1, fill=True)
        pdf.ln()
        pdf.set_text_color(0, 0, 0)

        pdf.set_font("Helvetica", "", 9)
        grand_total = 0.0
        total_lines = 0
        for po, lines in po_data:
            po_total = po.get("total_cost") or 0
            grand_total += po_total
            total_lines += len(lines)

            pdf.cell(col_widths[0], 6, str(po.get("po_number", "")), border=1)
            pdf.cell(col_widths[1], 6, str(po.get("order_date") or "Draft"), border=1)
            pdf.cell(col_widths[2], 6, str(po.get("status", "")).upper(), border=1)
            pdf.cell(col_widths[3], 6, str(len(lines)), border=1, align="R")
            pdf.cell(col_widths[4], 6, f"${po_total:.2f}", border=1, align="R")
            pdf.ln()

        # Grand total row
        pdf.set_font("Helvetica", "B", 9)
        pdf.cell(col_widths[0] + col_widths[1] + col_widths[2], 7, "GRAND TOTAL", border=1)
        pdf.cell(col_widths[3], 7, str(total_lines), border=1, align="R")
        pdf.cell(col_widths[4], 7, f"${grand_total:.2f}", border=1, align="R")
        pdf.ln()

        # ══════════════════════════════════════════════════════
        # INDIVIDUAL PO PAGES
        # ══════════════════════════════════════════════════════
        for po, lines in po_data:
            pdf.add_page()
            self._render_po_page(pdf, po, company, lines, pdf_settings)

        pdf.output(str(filepath))

    def _render_po_page(
        self,
        pdf: Any,
        po: dict,
        company: dict | None,
        lines: list[dict],
        pdf_settings: dict | None = None,
    ) -> None:
        """Render a single PO section within a multi-page bundled PDF.

        Similar to _build_pdf but skips creating a new FPDF instance —
        writes into the existing pdf object on the current page.
        Uses pdf_settings for column visibility and formatting.
        """
        s = pdf_settings or {}
        show_unit = s.get("show_unit_prices", True)
        show_ext = s.get("show_extended", True)
        accent_rgb = self._hex_to_rgb(s.get("accent_color", "#3B82F6"))
        payment_terms = s.get("payment_terms", "")
        default_delivery = s.get("delivery_notes", "")

        # PO Title
        pdf.set_font("Helvetica", "B", 14)
        pdf.cell(0, 10, f"PURCHASE ORDER: {po.get('po_number', '?')}", new_x="LMARGIN", new_y="NEXT")

        # PO Meta
        pdf.set_font("Helvetica", "", 10)
        pdf.cell(95, 6, f"Date: {po.get('order_date') or 'Draft'}")
        pdf.cell(0, 6, f"Status: {po.get('status', '').upper()}", new_x="LMARGIN", new_y="NEXT")

        if po.get("expected_delivery"):
            pdf.cell(0, 6, f"Expected Delivery: {po['expected_delivery']}", new_x="LMARGIN", new_y="NEXT")
        if po.get("shipping_method"):
            pdf.cell(0, 6, f"Shipping: {po['shipping_method']}", new_x="LMARGIN", new_y="NEXT")
        if payment_terms:
            pdf.cell(0, 6, f"Payment Terms: {payment_terms}", new_x="LMARGIN", new_y="NEXT")

        # Supplier
        pdf.ln(4)
        pdf.set_font("Helvetica", "B", 11)
        pdf.cell(0, 6, "SHIP FROM:", new_x="LMARGIN", new_y="NEXT")
        pdf.set_font("Helvetica", "", 10)
        pdf.cell(0, 5, po.get("supplier_name") or f"Supplier #{po.get('supplier_id', '?')}", new_x="LMARGIN", new_y="NEXT")

        # Line Items Table
        pdf.ln(6)
        pdf.set_font("Helvetica", "B", 9)
        col_widths, headers = self._get_table_columns(show_unit, show_ext)

        # Header with accent
        pdf.set_fill_color(*accent_rgb)
        pdf.set_text_color(255, 255, 255)
        for w, h in zip(col_widths, headers):
            pdf.cell(w, 7, h, border=1, fill=True)
        pdf.ln()
        pdf.set_text_color(0, 0, 0)

        pdf.set_font("Helvetica", "", 9)
        for i, line in enumerate(lines, 1):
            unit = line.get("unit_cost") or 0
            total = unit * line.get("qty_ordered", 0)

            col_idx = 0
            pdf.cell(col_widths[col_idx], 6, str(i), border=1); col_idx += 1
            pdf.cell(col_widths[col_idx], 6, str(line.get("part_code") or ""), border=1); col_idx += 1
            pdf.cell(col_widths[col_idx], 6, str(line.get("part_name") or "")[:45], border=1); col_idx += 1
            pdf.cell(col_widths[col_idx], 6, str(line.get("qty_ordered", 0)), border=1, align="R"); col_idx += 1
            if show_unit:
                pdf.cell(col_widths[col_idx], 6, f"${unit:.2f}" if unit else "-", border=1, align="R"); col_idx += 1
            if show_ext:
                pdf.cell(col_widths[col_idx], 6, f"${total:.2f}" if unit else "-", border=1, align="R")
            pdf.ln()

        # Totals
        if show_unit or show_ext:
            pdf.ln(4)
            pdf.set_font("Helvetica", "", 10)
            subtotal = po.get("subtotal") or 0
            tax = po.get("tax_amount") or 0
            shipping = po.get("shipping_cost") or 0
            total_cost = po.get("total_cost") or 0

            x_label = 130
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

        # Notes
        notes = po.get("notes") or default_delivery
        if notes:
            pdf.ln(6)
            pdf.set_font("Helvetica", "B", 10)
            pdf.cell(0, 6, "Delivery Instructions:", new_x="LMARGIN", new_y="NEXT")
            pdf.set_font("Helvetica", "", 9)
            pdf.multi_cell(0, 5, notes)

    def _format_group_clipboard_text(
        self,
        group: dict,
        company: dict | None,
        po_data: list[tuple[dict, list[dict]]],
        pdf_settings: dict | None = None,
    ) -> str:
        """Format all POs in a group as combined plain text for clipboard."""
        sections: list[str] = []

        # Header
        if company:
            sections.append(company.get("name", ""))
            if company.get("phone"):
                sections.append(f"Phone: {company['phone']}")
            if company.get("email"):
                sections.append(f"Email: {company['email']}")
            sections.append("")

        sections.append("=" * 82)
        sections.append(f"PURCHASE ORDER BUNDLE: {group['group_name'] or 'Unnamed Group'}")
        supplier_label = group.get("supplier_name") or f"Supplier #{group.get('supplier_id', '?')}"
        sections.append(f"Supplier: {supplier_label}")
        sections.append(f"Date: {datetime.now().strftime('%Y-%m-%d')}")
        sections.append(f"Total POs: {len(po_data)}")
        sections.append("=" * 82)
        sections.append("")

        grand_total = 0.0
        for idx, (po, lines) in enumerate(po_data, 1):
            # Single PO text (reuse existing formatter, pass settings)
            po_text = self._format_clipboard_text(po, None, lines, pdf_settings)
            sections.append(f"── PO {idx} of {len(po_data)} ──")
            sections.append(po_text)
            sections.append("")
            grand_total += po.get("total_cost") or 0

        sections.append("=" * 82)
        sections.append(f"{'BUNDLE GRAND TOTAL:':>70} ${grand_total:>10.2f}")
        sections.append("=" * 82)

        return "\n".join(sections)
