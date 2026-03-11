"""
Supplier Portal Service — token-based access for suppliers to view POs.

Generates unique access tokens per supplier so they can:
  - View POs addressed to them (read-only)
  - Acknowledge receipt of POs
  - Provide estimated delivery dates
  - Leave notes on POs

Tokens are time-limited and can be revoked.  Each token is scoped to a
single supplier — they can only see POs where supplier_id matches.

The portal is designed to work on LAN (V1.0) — a supplier rep at the
shop can use any browser.  When remote sync is added (Phase 13+), the
same tokens will work over the internet.
"""

from __future__ import annotations

import logging
import secrets
from datetime import datetime, timezone, timedelta
from typing import Any

import aiosqlite

from app.repositories.base import BaseRepo

logger = logging.getLogger(__name__)


# ═══════════════════════════════════════════════════════════════
# Repository
# ═══════════════════════════════════════════════════════════════

class SupplierPortalTokenRepo(BaseRepo):
    TABLE = "supplier_portal_tokens"
    HAS_UPDATED_AT = False

    async def find_by_token(self, token: str) -> dict | None:
        """Look up a token and return its details with supplier name."""
        cursor = await self.db.execute(
            """
            SELECT t.*, s.name AS supplier_name, s.email AS supplier_email,
                   s.contact_name AS supplier_contact
            FROM supplier_portal_tokens t
            JOIN suppliers s ON s.id = t.supplier_id
            WHERE t.token = ? AND t.is_active = 1
            """,
            (token,),
        )
        return await cursor.fetchone()

    async def list_for_supplier(self, supplier_id: int) -> list[dict]:
        """List all tokens for a supplier (including expired/inactive)."""
        cursor = await self.db.execute(
            """
            SELECT t.*, s.name AS supplier_name,
                   u.display_name AS creator_name
            FROM supplier_portal_tokens t
            JOIN suppliers s ON s.id = t.supplier_id
            LEFT JOIN users u ON u.id = t.created_by
            WHERE t.supplier_id = ?
            ORDER BY t.created_at DESC
            """,
            (supplier_id,),
        )
        return await cursor.fetchall()

    async def list_all_active(self) -> list[dict]:
        """List all active tokens across all suppliers."""
        cursor = await self.db.execute(
            """
            SELECT t.*, s.name AS supplier_name,
                   u.display_name AS creator_name
            FROM supplier_portal_tokens t
            JOIN suppliers s ON s.id = t.supplier_id
            LEFT JOIN users u ON u.id = t.created_by
            WHERE t.is_active = 1
              AND (t.expires_at IS NULL OR t.expires_at > datetime('now'))
            ORDER BY t.created_at DESC
            """
        )
        return await cursor.fetchall()

    async def deactivate(self, token_id: int) -> bool:
        """Revoke a token."""
        cursor = await self.db.execute(
            "UPDATE supplier_portal_tokens SET is_active = 0 WHERE id = ?",
            (token_id,),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def touch(self, token_id: int) -> None:
        """Update last_used_at to now."""
        await self.db.execute(
            "UPDATE supplier_portal_tokens SET last_used_at = datetime('now') WHERE id = ?",
            (token_id,),
        )
        await self.db.commit()


class SupplierAcknowledgmentRepo(BaseRepo):
    TABLE = "supplier_po_acknowledgments"
    HAS_UPDATED_AT = False

    async def get_for_po(self, po_id: int) -> dict | None:
        """Get the acknowledgment for a PO, if any."""
        cursor = await self.db.execute(
            "SELECT * FROM supplier_po_acknowledgments WHERE po_id = ?",
            (po_id,),
        )
        return await cursor.fetchone()


# ═══════════════════════════════════════════════════════════════
# Service
# ═══════════════════════════════════════════════════════════════

class SupplierPortalService:
    """Manages supplier portal tokens and supplier-facing PO access."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.token_repo = SupplierPortalTokenRepo(db)
        self.ack_repo = SupplierAcknowledgmentRepo(db)

    # ── Token Management ──────────────────────────────────────

    async def create_token(
        self,
        supplier_id: int,
        user_id: int,
        *,
        expires_in_days: int = 30,
        note: str | None = None,
    ) -> dict:
        """Generate a new access token for a supplier.

        Returns the token record including the raw token string.
        The token is a 32-character URL-safe random string.
        """
        # Verify supplier exists
        cursor = await self.db.execute(
            "SELECT id, name FROM suppliers WHERE id = ?",
            (supplier_id,),
        )
        supplier = await cursor.fetchone()
        if not supplier:
            raise ValueError(f"Supplier {supplier_id} not found")

        token = secrets.token_urlsafe(24)  # 32 chars
        expires_at = (
            datetime.now(timezone.utc) + timedelta(days=expires_in_days)
        ).isoformat()

        token_id = await self.token_repo.insert({
            "supplier_id": supplier_id,
            "token": token,
            "note": note,
            "is_active": 1,
            "expires_at": expires_at,
            "created_by": user_id,
        })

        logger.info(
            "Created portal token %d for supplier %d (%s), expires in %d days",
            token_id, supplier_id, supplier["name"], expires_in_days,
        )

        return {
            "id": token_id,
            "supplier_id": supplier_id,
            "supplier_name": supplier["name"],
            "token": token,
            "note": note,
            "is_active": True,
            "expires_at": expires_at,
            "last_used_at": None,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }

    async def revoke_token(self, token_id: int) -> bool:
        """Revoke (deactivate) a portal token."""
        ok = await self.token_repo.deactivate(token_id)
        if ok:
            logger.info("Revoked portal token %d", token_id)
        return ok

    async def list_tokens(self, supplier_id: int | None = None) -> list[dict]:
        """List tokens, optionally filtered by supplier."""
        if supplier_id:
            return await self.token_repo.list_for_supplier(supplier_id)
        return await self.token_repo.list_all_active()

    async def validate_token(self, token: str) -> dict | None:
        """Validate a token and return token+supplier info if valid.

        Returns None if the token is invalid, expired, or revoked.
        Updates last_used_at on successful validation.
        """
        record = await self.token_repo.find_by_token(token)
        if not record:
            return None

        # Check expiration
        expires = record.get("expires_at")
        if expires:
            try:
                exp_dt = datetime.fromisoformat(expires)
                if exp_dt.tzinfo is None:
                    exp_dt = exp_dt.replace(tzinfo=timezone.utc)
                if exp_dt < datetime.now(timezone.utc):
                    return None
            except (ValueError, TypeError):
                pass

        # Update last_used_at
        await self.token_repo.touch(record["id"])

        return dict(record)

    # ── Supplier-Facing Operations ────────────────────────────

    async def get_supplier_pos(
        self,
        supplier_id: int,
        *,
        status: str | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict]:
        """Get POs for a supplier (supplier-facing read-only list).

        Returns compact PO info suitable for the supplier portal.
        """
        sql = """
            SELECT po.id, po.po_number, po.status, po.order_date,
                   po.expected_delivery, po.total_cost, po.notes,
                   po.shipping_method,
                   (SELECT COUNT(*) FROM po_line_items WHERE po_id = po.id) AS line_count,
                   CASE WHEN ack.id IS NOT NULL THEN 1 ELSE 0 END AS is_acknowledged,
                   ack.estimated_delivery AS ack_estimated_delivery,
                   ack.supplier_notes AS ack_supplier_notes,
                   ack.acknowledged_at
            FROM purchase_orders po
            LEFT JOIN supplier_po_acknowledgments ack ON ack.po_id = po.id
            WHERE po.supplier_id = ?
              AND po.status NOT IN ('draft', 'cancelled')
        """
        params: list[Any] = [supplier_id]

        if status:
            sql += " AND po.status = ?"
            params.append(status)

        sql += " ORDER BY po.order_date DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])

        cursor = await self.db.execute(sql, params)
        return [dict(row) for row in await cursor.fetchall()]

    async def get_po_detail_for_supplier(
        self,
        po_id: int,
        supplier_id: int,
    ) -> dict | None:
        """Get full PO details for a supplier (including line items).

        Validates that the PO belongs to the specified supplier.
        """
        cursor = await self.db.execute(
            """
            SELECT po.*, s.name AS supplier_name,
                   CASE WHEN ack.id IS NOT NULL THEN 1 ELSE 0 END AS is_acknowledged,
                   ack.estimated_delivery AS ack_estimated_delivery,
                   ack.supplier_notes AS ack_supplier_notes,
                   ack.acknowledged_at
            FROM purchase_orders po
            LEFT JOIN suppliers s ON s.id = po.supplier_id
            LEFT JOIN supplier_po_acknowledgments ack ON ack.po_id = po.id
            WHERE po.id = ? AND po.supplier_id = ?
              AND po.status NOT IN ('draft', 'cancelled')
            """,
            (po_id, supplier_id),
        )
        po = await cursor.fetchone()
        if not po:
            return None

        po = dict(po)

        # Fetch line items
        cursor = await self.db.execute(
            """
            SELECT li.*, p.name AS part_name, p.code AS part_code,
                   p.description AS part_description
            FROM po_line_items li
            LEFT JOIN parts p ON p.id = li.part_id
            WHERE li.po_id = ?
            ORDER BY li.id
            """,
            (po_id,),
        )
        po["lines"] = [dict(row) for row in await cursor.fetchall()]

        return po

    async def acknowledge_po(
        self,
        po_id: int,
        supplier_id: int,
        token_id: int,
        *,
        estimated_delivery: str | None = None,
        supplier_notes: str | None = None,
    ) -> dict:
        """Supplier acknowledges receipt of a PO.

        Creates an acknowledgment record and updates PO status to
        'acknowledged' if appropriate.
        """
        # Verify PO belongs to this supplier
        cursor = await self.db.execute(
            "SELECT id, po_number, status FROM purchase_orders WHERE id = ? AND supplier_id = ?",
            (po_id, supplier_id),
        )
        po = await cursor.fetchone()
        if not po:
            raise ValueError("PO not found or doesn't belong to this supplier")

        # Create or update acknowledgment (UPSERT)
        existing = await self.ack_repo.get_for_po(po_id)
        if existing:
            await self.db.execute(
                """
                UPDATE supplier_po_acknowledgments
                SET estimated_delivery = ?, supplier_notes = ?,
                    acknowledged_at = datetime('now')
                WHERE po_id = ?
                """,
                (estimated_delivery, supplier_notes, po_id),
            )
        else:
            await self.ack_repo.insert({
                "po_id": po_id,
                "supplier_id": supplier_id,
                "token_id": token_id,
                "estimated_delivery": estimated_delivery,
                "supplier_notes": supplier_notes,
            })

        # Update PO status to acknowledged if it's currently 'submitted'
        if po["status"] == "submitted":
            await self.db.execute(
                "UPDATE purchase_orders SET status = 'acknowledged' WHERE id = ?",
                (po_id,),
            )

        await self.db.commit()

        logger.info(
            "Supplier acknowledged PO %s (id=%d), ETA: %s",
            po["po_number"], po_id, estimated_delivery or "not provided",
        )

        return {
            "po_id": po_id,
            "po_number": po["po_number"],
            "acknowledged": True,
            "estimated_delivery": estimated_delivery,
            "supplier_notes": supplier_notes,
        }
