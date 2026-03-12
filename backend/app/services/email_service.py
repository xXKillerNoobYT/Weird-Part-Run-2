"""
Email Service — SMTP-based email sending for PO delivery.

Sends branded HTML emails with optional PDF attachments.
Used by the Review & Send workflow to deliver POs to suppliers.

Configuration lives in config.py / .env:
  EMAIL_ENABLED   = true to activate
  SMTP_HOST       = SMTP server hostname
  SMTP_PORT       = 587 (TLS) or 465 (SSL) or 25 (plain)
  SMTP_USER       = auth username
  SMTP_PASSWORD   = auth password
  SMTP_USE_TLS    = true for STARTTLS (port 587)
  EMAIL_FROM      = sender address
  EMAIL_FROM_NAME = display name for the From header
  EMAIL_REPLY_TO  = optional reply-to address
"""

from __future__ import annotations

import logging
import smtplib
from email.message import EmailMessage
from email.utils import formataddr
from pathlib import Path
from typing import Any

import aiosqlite

from app.config import settings

logger = logging.getLogger(__name__)


class EmailService:
    """Sends PO emails to suppliers via SMTP.

    Usage:
        svc = EmailService(db)
        result = await svc.send_po_email(
            po_id=42,
            to_email="vendor@example.com",
            subject="PO-0042 — New Purchase Order",
        )
    """

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    @staticmethod
    def is_configured() -> bool:
        """Check if email is configured and enabled."""
        return bool(
            settings.EMAIL_ENABLED
            and settings.SMTP_HOST
            and settings.EMAIL_FROM
        )

    @staticmethod
    def get_config_status() -> dict:
        """Return the current email configuration state (safe, no passwords)."""
        return {
            "enabled": settings.EMAIL_ENABLED,
            "configured": EmailService.is_configured(),
            "smtp_host": settings.SMTP_HOST or None,
            "smtp_port": settings.SMTP_PORT,
            "smtp_use_tls": settings.SMTP_USE_TLS,
            "from_email": settings.EMAIL_FROM or None,
            "from_name": settings.EMAIL_FROM_NAME or None,
            "reply_to": settings.EMAIL_REPLY_TO or None,
        }

    async def send_po_email(
        self,
        po_id: int,
        to_email: str,
        *,
        to_name: str | None = None,
        subject: str | None = None,
        body_text: str | None = None,
        cc: list[str] | None = None,
        attach_pdf: bool = True,
    ) -> dict:
        """Send an email for a single PO.

        If attach_pdf is True, generates a PDF and attaches it.
        The body_text defaults to the clipboard text format.

        Returns: {success: bool, message: str, message_id: str | None}
        """
        if not self.is_configured():
            return {
                "success": False,
                "message": "Email is not configured. Set SMTP settings in .env.",
                "message_id": None,
            }

        # Get PO info for subject line
        cursor = await self.db.execute(
            """
            SELECT po.*, s.name AS supplier_name, s.email AS supplier_email
            FROM purchase_orders po
            LEFT JOIN suppliers s ON s.id = po.supplier_id
            WHERE po.id = ?
            """,
            (po_id,),
        )
        po = await cursor.fetchone()
        if not po:
            return {"success": False, "message": "PO not found", "message_id": None}

        # Determine recipient
        actual_to = to_email or (po.get("supplier_email") if po else None)
        if not actual_to:
            return {
                "success": False,
                "message": "No recipient email provided and supplier has no email on file",
                "message_id": None,
            }

        # Build subject
        if not subject:
            company = await self._get_company_name()
            subject = f"Purchase Order {po['po_number']} from {company}"

        # Build body
        if not body_text:
            from app.services.pdf_service import PDFService
            pdf_svc = PDFService(self.db)
            body_text = await pdf_svc.get_clipboard_text(po_id)

        # Generate PDF attachment
        pdf_path: str | None = None
        if attach_pdf:
            from app.services.pdf_service import PDFService
            pdf_svc = PDFService(self.db)
            pdf_path = await pdf_svc.generate_po_pdf(po_id)

        # Build and send email
        return self._send_email(
            to_email=actual_to,
            to_name=to_name,
            subject=subject,
            body_text=body_text or "",
            cc=cc,
            attachments=[pdf_path] if pdf_path else [],
        )

    async def send_group_email(
        self,
        group_id: int,
        to_email: str,
        *,
        to_name: str | None = None,
        subject: str | None = None,
        body_text: str | None = None,
        cc: list[str] | None = None,
    ) -> dict:
        """Send an email for a PO group (bundled POs).

        Generates the bundled PDF and attaches it.
        Returns: {success: bool, message: str, message_id: str | None}
        """
        if not self.is_configured():
            return {
                "success": False,
                "message": "Email is not configured. Set SMTP settings in .env.",
                "message_id": None,
            }

        # Get group info
        cursor = await self.db.execute(
            """
            SELECT g.*, s.name AS supplier_name, s.email AS supplier_email
            FROM po_groups g
            LEFT JOIN suppliers s ON s.id = g.supplier_id
            WHERE g.id = ?
            """,
            (group_id,),
        )
        group = await cursor.fetchone()
        if not group:
            return {"success": False, "message": "PO group not found", "message_id": None}

        actual_to = to_email or (group.get("supplier_email") if group else None)
        if not actual_to:
            return {
                "success": False,
                "message": "No recipient email provided and supplier has no email on file",
                "message_id": None,
            }

        # Build subject
        if not subject:
            company = await self._get_company_name()
            subject = f"Purchase Order Bundle — {group['group_name']} from {company}"

        # Build body from group clipboard text
        if not body_text:
            from app.services.pdf_service import PDFService
            pdf_svc = PDFService(self.db)
            body_text = await pdf_svc.get_group_clipboard_text(group_id)

        # Generate bundled PDF
        from app.services.pdf_service import PDFService
        pdf_svc = PDFService(self.db)
        result = await pdf_svc.generate_group_pdf(group_id)
        attachments: list[str] = []
        if result and result.get("pdf_path"):
            attachments.append(result["pdf_path"])

        return self._send_email(
            to_email=actual_to,
            to_name=to_name,
            subject=subject,
            body_text=body_text or "",
            cc=cc,
            attachments=attachments,
        )

    def _send_email(
        self,
        to_email: str,
        subject: str,
        body_text: str,
        *,
        to_name: str | None = None,
        cc: list[str] | None = None,
        attachments: list[str] | None = None,
    ) -> dict:
        """Low-level email sending via SMTP.

        Uses STARTTLS on port 587 by default. Set SMTP_USE_TLS=false
        for plain connections (not recommended for production).

        Returns: {success: bool, message: str, message_id: str | None}
        """
        msg = EmailMessage()

        # From
        from_addr = settings.EMAIL_FROM
        from_name = settings.EMAIL_FROM_NAME or settings.APP_NAME
        msg["From"] = formataddr((from_name, from_addr))

        # To
        if to_name:
            msg["To"] = formataddr((to_name, to_email))
        else:
            msg["To"] = to_email

        # CC
        if cc:
            msg["Cc"] = ", ".join(cc)

        # Reply-To
        reply_to = settings.EMAIL_REPLY_TO or from_addr
        msg["Reply-To"] = reply_to

        msg["Subject"] = subject

        # Body — plain text (HTML can be added later as an enhancement)
        msg.set_content(body_text)

        # Attachments
        for attachment_path in (attachments or []):
            path = Path(attachment_path)
            if path.exists():
                with open(path, "rb") as f:
                    file_data = f.read()
                # Determine MIME type based on extension
                if path.suffix.lower() == ".pdf":
                    maintype, subtype = "application", "pdf"
                else:
                    maintype, subtype = "application", "octet-stream"
                msg.add_attachment(
                    file_data,
                    maintype=maintype,
                    subtype=subtype,
                    filename=path.name,
                )
            else:
                logger.warning("Attachment file not found: %s", attachment_path)

        # Send
        try:
            if settings.SMTP_USE_TLS and settings.SMTP_PORT != 465:
                # STARTTLS (port 587 typically)
                with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=30) as server:
                    server.ehlo()
                    server.starttls()
                    server.ehlo()
                    if settings.SMTP_USER and settings.SMTP_PASSWORD:
                        server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
                    server.send_message(msg)
                    message_id = msg.get("Message-ID")
            elif settings.SMTP_PORT == 465:
                # SSL (port 465)
                with smtplib.SMTP_SSL(settings.SMTP_HOST, settings.SMTP_PORT, timeout=30) as server:
                    if settings.SMTP_USER and settings.SMTP_PASSWORD:
                        server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
                    server.send_message(msg)
                    message_id = msg.get("Message-ID")
            else:
                # Plain (not recommended)
                with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=30) as server:
                    if settings.SMTP_USER and settings.SMTP_PASSWORD:
                        server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
                    server.send_message(msg)
                    message_id = msg.get("Message-ID")

            logger.info("Email sent to %s: %s", to_email, subject[:60])
            return {
                "success": True,
                "message": f"Email sent to {to_email}",
                "message_id": message_id,
            }
        except smtplib.SMTPAuthenticationError as exc:
            logger.error("SMTP auth failed: %s", exc)
            return {
                "success": False,
                "message": "SMTP authentication failed — check SMTP_USER and SMTP_PASSWORD",
                "message_id": None,
            }
        except smtplib.SMTPException as exc:
            logger.error("SMTP error sending to %s: %s", to_email, exc)
            return {
                "success": False,
                "message": f"SMTP error: {exc}",
                "message_id": None,
            }
        except Exception as exc:
            logger.error("Email send failed to %s: %s", to_email, exc)
            return {
                "success": False,
                "message": f"Failed to send email: {exc}",
                "message_id": None,
            }

    async def _get_company_name(self) -> str:
        """Get primary company name for email subjects."""
        cursor = await self.db.execute(
            "SELECT name FROM company_profiles WHERE is_primary = 1 LIMIT 1"
        )
        row = await cursor.fetchone()
        return row["name"] if row else settings.APP_NAME
