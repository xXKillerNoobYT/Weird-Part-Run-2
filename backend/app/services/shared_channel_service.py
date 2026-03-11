"""
Shared Channel Service — cross-company data sharing with scope enforcement.

Provides the backbone for shop↔shop and multi-site data exchange:
1. Channel lifecycle (create, update, renew, revoke, expire)
2. Scope enforcement — filter data by channel scope (job_ids, data_types, table whitelist)
3. Redaction engine — strip/mask/hash sensitive fields before sharing cross-company
4. Outbound preparation — gather changes → filter by scope → apply redactions → package
5. Inbound processing — verify channel active + accepted → apply with origin tracking
6. Data exchange audit trail via _shared_data_log
7. Auto-expire check — deactivate channels past expires_at or auto_expire_days
"""

from __future__ import annotations

import hashlib
import json
import logging
from datetime import datetime, timedelta, timezone
from typing import Any

import aiosqlite

logger = logging.getLogger(__name__)


# ── Default redacted fields per table (safety net) ───────────────
# Even without explicit rules, these fields are NEVER shared cross-company.
ALWAYS_REDACTED = {
    "users": {"password_hash", "email", "phone", "pin_hash"},
    "employee_notes": {"note_content"},
    "labor_entries": {"hourly_rate", "total_cost"},
    "certifications": {"document_path"},
    "_company_keys": {"root_key_encrypted", "sync_key", "shop_node_encrypted"},
    "_device_certificates": {"certificate_data", "signature"},
}

# Tables that may NEVER be shared cross-company regardless of channel scope.
BLOCKED_TABLES = {
    "_company_keys", "_device_certificates", "_device_registry",
    "_device_sync_profiles", "_security_audit_log",
    "_remote_sync_config", "_remote_failban",
    "permissions", "hat_permissions", "user_hats",
    "period_locks",
}


class SharedChannelService:
    """Manages cross-company shared channels with scope/redaction enforcement."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    # ══════════════════════════════════════════════════════════════
    # Channel Lifecycle
    # ══════════════════════════════════════════════════════════════

    async def create_channel(
        self,
        *,
        channel_name: str,
        owner_company_id: str,
        partner_company_ids: list[str],
        scope: dict | None = None,
        permissions: dict | None = None,
        description: str | None = None,
        expires_at: str | None = None,
        auto_expire_days: int | None = None,
        created_by: int | None = None,
    ) -> dict:
        """Create a shared channel with scope and optional auto-expire.

        Scope format:
            {
                "tables": ["jobs", "parts", ...],   # allowed tables (whitelist)
                "job_ids": [1, 2, 3],                # restrict to specific jobs
                "data_types": ["rfi", "schedule"],   # logical data categories
            }

        Permissions format:
            {
                "read": true,
                "write": false,
                "delete": false,
            }
        """
        cursor = await self.db.execute(
            """
            INSERT INTO _shared_channels (
                channel_name, owner_company_id, scope_json, permissions_json,
                description, expires_at, auto_expire_days, created_by
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                channel_name,
                owner_company_id,
                json.dumps(scope or {}),
                json.dumps(permissions or {"read": True, "write": False, "delete": False}),
                description,
                expires_at,
                auto_expire_days,
                created_by,
            ),
        )
        channel_id = cursor.lastrowid
        await self.db.commit()

        # Add owner as member
        await self.db.execute(
            """INSERT INTO _shared_channel_members
               (channel_id, company_id, role, accepted_at)
               VALUES (?, ?, 'owner', datetime('now'))""",
            (channel_id, owner_company_id),
        )

        # Add partners
        for pid in partner_company_ids:
            await self.db.execute(
                """INSERT INTO _shared_channel_members
                   (channel_id, company_id, role)
                   VALUES (?, ?, 'participant')""",
                (channel_id, pid),
            )
        await self.db.commit()

        await self._audit(
            "shared_channel_created",
            company_id=owner_company_id,
            actor=created_by,
            details={
                "channel_id": channel_id,
                "channel_name": channel_name,
                "partners": partner_company_ids,
                "scope": scope,
                "auto_expire_days": auto_expire_days,
            },
        )

        return await self.get_channel(channel_id)

    async def get_channel(self, channel_id: int) -> dict:
        """Get a single channel with its members and redaction rules."""
        cursor = await self.db.execute(
            "SELECT * FROM _shared_channels WHERE id = ?", (channel_id,),
        )
        row = await cursor.fetchone()
        if not row:
            return {}
        ch = dict(row)
        ch["scope"] = json.loads(ch.get("scope_json") or "{}")
        ch["permissions"] = json.loads(ch.get("permissions_json") or "{}")

        # Members
        cur2 = await self.db.execute(
            "SELECT * FROM _shared_channel_members WHERE channel_id = ?", (channel_id,),
        )
        ch["members"] = [dict(m) for m in await cur2.fetchall()]

        # Redaction rules
        cur3 = await self.db.execute(
            "SELECT * FROM _redaction_rules WHERE channel_id = ? AND is_active = 1",
            (channel_id,),
        )
        ch["redaction_rules"] = [dict(r) for r in await cur3.fetchall()]

        return ch

    async def list_channels(
        self,
        *,
        company_id: str | None = None,
        include_inactive: bool = False,
    ) -> list[dict]:
        """List shared channels, optionally filtered by company membership."""
        if company_id:
            sql = """
                SELECT sc.* FROM _shared_channels sc
                JOIN _shared_channel_members scm ON sc.id = scm.channel_id
                WHERE scm.company_id = ?
            """
            params: list[Any] = [company_id]
            if not include_inactive:
                sql += " AND sc.is_active = 1 AND sc.revoked_at IS NULL"
            sql += " ORDER BY sc.created_at DESC"
            cursor = await self.db.execute(sql, tuple(params))
        else:
            sql = "SELECT * FROM _shared_channels"
            if not include_inactive:
                sql += " WHERE is_active = 1 AND revoked_at IS NULL"
            sql += " ORDER BY created_at DESC"
            cursor = await self.db.execute(sql)

        rows = await cursor.fetchall()
        channels = []
        for r in rows:
            ch = dict(r)
            ch["scope"] = json.loads(ch.get("scope_json") or "{}")
            ch["permissions"] = json.loads(ch.get("permissions_json") or "{}")
            # Members (lightweight — no redaction rules for list)
            cur2 = await self.db.execute(
                "SELECT * FROM _shared_channel_members WHERE channel_id = ?",
                (ch["id"],),
            )
            ch["members"] = [dict(m) for m in await cur2.fetchall()]
            channels.append(ch)
        return channels

    async def update_channel(
        self,
        channel_id: int,
        *,
        scope: dict | None = None,
        permissions: dict | None = None,
        description: str | None = None,
        expires_at: str | None = None,
        auto_expire_days: int | None = None,
        updated_by: int | None = None,
    ) -> dict:
        """Update a channel's scope, permissions, or expiry."""
        parts: list[str] = []
        params: list[Any] = []
        if scope is not None:
            parts.append("scope_json = ?")
            params.append(json.dumps(scope))
        if permissions is not None:
            parts.append("permissions_json = ?")
            params.append(json.dumps(permissions))
        if description is not None:
            parts.append("description = ?")
            params.append(description)
        if expires_at is not None:
            parts.append("expires_at = ?")
            params.append(expires_at)
        if auto_expire_days is not None:
            parts.append("auto_expire_days = ?")
            params.append(auto_expire_days)
        if not parts:
            return await self.get_channel(channel_id)

        parts.append("updated_at = datetime('now')")
        set_sql = ", ".join(parts)
        params.append(channel_id)
        await self.db.execute(
            f"UPDATE _shared_channels SET {set_sql} WHERE id = ?", tuple(params),
        )
        await self.db.commit()

        await self._audit(
            "shared_channel_updated",
            actor=updated_by,
            details={"channel_id": channel_id},
        )
        return await self.get_channel(channel_id)

    async def renew_channel(
        self,
        channel_id: int,
        *,
        new_expires_at: str | None = None,
        renewed_by: int | None = None,
    ) -> dict:
        """Renew a channel's expiry date (extend its life)."""
        ch = await self.get_channel(channel_id)
        if not ch:
            return {}

        if not new_expires_at and ch.get("auto_expire_days"):
            days = ch["auto_expire_days"]
            new_exp = datetime.now(timezone.utc) + timedelta(days=days)
            new_expires_at = new_exp.isoformat()

        await self.db.execute(
            """UPDATE _shared_channels
               SET expires_at = ?, last_renewed_at = datetime('now'), renewed_by = ?,
                   updated_at = datetime('now')
               WHERE id = ?""",
            (new_expires_at, renewed_by, channel_id),
        )
        await self.db.commit()

        await self._audit(
            "shared_channel_renewed",
            actor=renewed_by,
            details={"channel_id": channel_id, "new_expires_at": new_expires_at},
        )
        return await self.get_channel(channel_id)

    async def revoke_channel(
        self,
        channel_id: int,
        *,
        reason: str | None = None,
        revoked_by: int | None = None,
    ) -> bool:
        """Revoke a shared channel immediately (hard disable, not soft deactivate)."""
        cursor = await self.db.execute(
            """UPDATE _shared_channels
               SET is_active = 0, revoked_at = datetime('now'),
                   revoked_by = ?, revoke_reason = ?,
                   updated_at = datetime('now')
               WHERE id = ? AND revoked_at IS NULL""",
            (revoked_by, reason, channel_id),
        )
        await self.db.commit()
        revoked = (cursor.rowcount or 0) > 0
        if revoked:
            await self._audit(
                "shared_channel_revoked",
                actor=revoked_by,
                details={"channel_id": channel_id, "reason": reason},
            )
        return revoked

    async def accept_invitation(self, channel_id: int, company_id: str) -> bool:
        """Accept a pending channel invitation."""
        cursor = await self.db.execute(
            """UPDATE _shared_channel_members
               SET accepted_at = datetime('now')
               WHERE channel_id = ? AND company_id = ? AND accepted_at IS NULL""",
            (channel_id, company_id),
        )
        await self.db.commit()
        return (cursor.rowcount or 0) > 0

    async def expire_stale_channels(self) -> int:
        """Deactivate channels that have passed their expires_at date.

        Returns the number of channels expired.
        """
        cursor = await self.db.execute(
            """UPDATE _shared_channels
               SET is_active = 0, updated_at = datetime('now')
               WHERE is_active = 1 AND revoked_at IS NULL
                 AND expires_at IS NOT NULL AND expires_at < datetime('now')""",
        )
        await self.db.commit()
        expired = cursor.rowcount or 0
        if expired:
            logger.info("Auto-expired %d shared channels", expired)
            await self._audit(
                "shared_channels_auto_expired",
                details={"count": expired},
            )
        return expired

    # ══════════════════════════════════════════════════════════════
    # Redaction Rules
    # ══════════════════════════════════════════════════════════════

    async def add_redaction_rule(
        self,
        *,
        channel_id: int,
        table_name: str,
        field_name: str,
        redaction_type: str = "remove",
        replacement_value: str | None = None,
    ) -> dict:
        """Add a field-level redaction rule for a shared channel."""
        cursor = await self.db.execute(
            """INSERT INTO _redaction_rules
               (channel_id, table_name, field_name, redaction_type, replacement_value)
               VALUES (?, ?, ?, ?, ?)
               ON CONFLICT(channel_id, table_name, field_name) DO UPDATE SET
                 redaction_type = excluded.redaction_type,
                 replacement_value = excluded.replacement_value,
                 is_active = 1""",
            (channel_id, table_name, field_name, redaction_type, replacement_value),
        )
        await self.db.commit()
        row_id = cursor.lastrowid
        cur = await self.db.execute("SELECT * FROM _redaction_rules WHERE id = ?", (row_id,))
        row = await cur.fetchone()
        return dict(row) if row else {}

    async def list_redaction_rules(self, channel_id: int) -> list[dict]:
        """List all active redaction rules for a channel."""
        cursor = await self.db.execute(
            "SELECT * FROM _redaction_rules WHERE channel_id = ? AND is_active = 1 ORDER BY table_name, field_name",
            (channel_id,),
        )
        return [dict(r) for r in await cursor.fetchall()]

    async def remove_redaction_rule(self, rule_id: int) -> bool:
        """Soft-deactivate a redaction rule."""
        cursor = await self.db.execute(
            "UPDATE _redaction_rules SET is_active = 0 WHERE id = ?", (rule_id,),
        )
        await self.db.commit()
        return (cursor.rowcount or 0) > 0

    # ══════════════════════════════════════════════════════════════
    # Scope Enforcement & Redaction Engine
    # ══════════════════════════════════════════════════════════════

    def is_table_allowed(self, table_name: str, scope: dict) -> bool:
        """Check if a table is within the channel's scope.

        Rules:
        1. If scope.tables is defined, table must be in the whitelist.
        2. Table must not be in BLOCKED_TABLES (security invariant).
        3. If scope is empty/unlisted, all non-blocked synced tables are allowed.
        """
        if table_name in BLOCKED_TABLES:
            return False

        allowed_tables = scope.get("tables")
        if allowed_tables:
            return table_name in allowed_tables
        return True  # no whitelist = allow non-blocked tables

    def filter_records_by_scope(
        self,
        records: list[dict],
        table_name: str,
        scope: dict,
    ) -> list[dict]:
        """Filter records based on channel scope constraints.

        Currently handles:
        - job_ids: restrict job-related records to specific jobs
        """
        job_ids = scope.get("job_ids")
        if not job_ids:
            return records  # no job filter

        job_id_set = set(job_ids)

        # Tables that have a direct job_id column
        job_fk_tables = {
            "jobs", "job_parts", "labor_entries", "daily_reports",
            "job_lead_elevations", "job_parts_orders", "jpo_line_items",
            "job_customers", "job_general_contractors", "job_trailers",
            "job_dispatch", "notebook_entries", "notebooks",
        }

        if table_name in job_fk_tables:
            return [r for r in records if r.get("job_id") in job_id_set]

        if table_name == "jobs":
            return [r for r in records if r.get("id") in job_id_set]

        # Other tables pass through (parts catalog, etc.)
        return records

    def apply_redactions(
        self,
        record: dict,
        table_name: str,
        channel_rules: list[dict],
    ) -> tuple[dict, list[str]]:
        """Apply redaction rules to a record before cross-company sharing.

        Returns (redacted_record, list_of_redacted_field_names).

        Redaction types:
        - remove: delete the field entirely
        - mask: replace with '***'
        - hash: replace with SHA-256 hash (one-way, for matching not reading)
        - truncate: keep first 3 chars + '...'
        - replace: substitute with replacement_value
        """
        redacted = dict(record)  # shallow copy
        redacted_fields: list[str] = []

        # 1. Apply ALWAYS_REDACTED safety net
        always = ALWAYS_REDACTED.get(table_name, set())
        for field in always:
            if field in redacted:
                del redacted[field]
                redacted_fields.append(field)

        # 2. Apply channel-specific rules
        table_rules = [r for r in channel_rules if r["table_name"] == table_name]
        for rule in table_rules:
            field = rule["field_name"]
            if field not in redacted:
                continue

            rtype = rule["redaction_type"]
            value = redacted[field]

            if rtype == "remove":
                del redacted[field]
            elif rtype == "mask":
                redacted[field] = "***"
            elif rtype == "hash":
                h = hashlib.sha256(str(value).encode()).hexdigest()[:16]
                redacted[field] = f"hash:{h}"
            elif rtype == "truncate":
                s = str(value)
                redacted[field] = s[:3] + "..." if len(s) > 3 else s
            elif rtype == "replace":
                redacted[field] = rule.get("replacement_value", "")

            redacted_fields.append(field)

        return redacted, redacted_fields

    # ══════════════════════════════════════════════════════════════
    # Outbound Data Preparation
    # ══════════════════════════════════════════════════════════════

    async def prepare_outbound(
        self,
        *,
        channel_id: int,
        changes: dict[str, list[dict]],
        peer_id: str | None = None,
        session_id: str | None = None,
    ) -> dict:
        """Filter and redact changes for a shared channel before sending.

        Args:
            channel_id: shared channel to use for scope/redaction
            changes: {table_name: [records]} — the raw data to share
            peer_id: ID of the remote peer receiving the data
            session_id: sync session ID for audit trail

        Returns:
            {
                "outbound": {table_name: [redacted_records]},
                "stats": {table: {total, shared, redacted_fields}},
                "audit_entries": int   # entries logged to _shared_data_log
            }
        """
        channel = await self.get_channel(channel_id)
        if not channel or not channel.get("is_active"):
            return {"outbound": {}, "stats": {}, "audit_entries": 0, "error": "channel_inactive"}

        scope = channel.get("scope", {})
        rules = channel.get("redaction_rules", [])

        outbound: dict[str, list[dict]] = {}
        stats: dict[str, dict] = {}
        audit_count = 0

        for table_name, records in changes.items():
            if not self.is_table_allowed(table_name, scope):
                continue

            # Scope filtering
            filtered = self.filter_records_by_scope(records, table_name, scope)
            if not filtered:
                continue

            # Apply redactions
            redacted_records = []
            table_redacted_fields: set[str] = set()
            for rec in filtered:
                redacted, fields = self.apply_redactions(rec, table_name, rules)
                redacted_records.append(redacted)
                table_redacted_fields.update(fields)

                # Audit each shared record
                data_hash = hashlib.sha256(
                    json.dumps(redacted, sort_keys=True, default=str).encode()
                ).hexdigest()[:32]
                await self.db.execute(
                    """INSERT INTO _shared_data_log
                       (shared_channel_id, direction, table_name, record_id,
                        operation, redactions_applied, data_hash, peer_id, session_id)
                       VALUES (?, 'outbound', ?, ?, 'UPDATE', ?, ?, ?, ?)""",
                    (
                        channel_id, table_name, rec.get("id", 0),
                        json.dumps(list(table_redacted_fields)) if table_redacted_fields else None,
                        data_hash, peer_id, session_id,
                    ),
                )
                audit_count += 1

            outbound[table_name] = redacted_records
            stats[table_name] = {
                "total": len(records),
                "shared": len(redacted_records),
                "redacted_fields": sorted(table_redacted_fields),
            }

        await self.db.commit()
        return {"outbound": outbound, "stats": stats, "audit_entries": audit_count}

    # ══════════════════════════════════════════════════════════════
    # Inbound Data Processing
    # ══════════════════════════════════════════════════════════════

    async def process_inbound(
        self,
        *,
        channel_id: int,
        company_id: str,
        changes: dict[str, list[dict]],
        peer_id: str | None = None,
        session_id: str | None = None,
    ) -> dict:
        """Process incoming data from a shared channel partner.

        Validates the channel is active + that this company has accepted the invitation,
        then logs each record to the shared data log.

        Returns:
            {
                "accepted": {table_name: count},
                "rejected": {table_name: count},
                "audit_entries": int,
                "error": str | None
            }
        """
        channel = await self.get_channel(channel_id)
        if not channel or not channel.get("is_active"):
            return {"accepted": {}, "rejected": {}, "audit_entries": 0, "error": "channel_inactive"}

        if channel.get("revoked_at"):
            return {"accepted": {}, "rejected": {}, "audit_entries": 0, "error": "channel_revoked"}

        # Verify this company is an accepted member
        members = channel.get("members", [])
        our_member = next((m for m in members if m["company_id"] == company_id), None)
        if not our_member or not our_member.get("accepted_at"):
            return {"accepted": {}, "rejected": {}, "audit_entries": 0, "error": "not_accepted"}

        scope = channel.get("scope", {})
        perms = channel.get("permissions", {})

        accepted: dict[str, int] = {}
        rejected: dict[str, int] = {}
        audit_count = 0

        for table_name, records in changes.items():
            if not self.is_table_allowed(table_name, scope):
                rejected[table_name] = len(records)
                continue

            if not perms.get("write", False) and not perms.get("read", True):
                rejected[table_name] = len(records)
                continue

            filtered = self.filter_records_by_scope(records, table_name, scope)
            accepted[table_name] = len(filtered)
            rejected[table_name] = len(records) - len(filtered)

            for rec in filtered:
                data_hash = hashlib.sha256(
                    json.dumps(rec, sort_keys=True, default=str).encode()
                ).hexdigest()[:32]
                await self.db.execute(
                    """INSERT INTO _shared_data_log
                       (shared_channel_id, direction, table_name, record_id,
                        operation, data_hash, peer_id, session_id)
                       VALUES (?, 'inbound', ?, ?, 'UPDATE', ?, ?, ?)""",
                    (channel_id, table_name, rec.get("id", 0), data_hash, peer_id, session_id),
                )
                audit_count += 1

        # Update member sync stats
        total_received = sum(accepted.values())
        await self.db.execute(
            """UPDATE _shared_channel_members
               SET last_sync_at = datetime('now'),
                   data_received_count = COALESCE(data_received_count, 0) + ?
               WHERE channel_id = ? AND company_id = ?""",
            (total_received, channel_id, company_id),
        )
        await self.db.commit()

        return {
            "accepted": accepted,
            "rejected": rejected,
            "audit_entries": audit_count,
            "error": None,
        }

    # ══════════════════════════════════════════════════════════════
    # Data Exchange Log
    # ══════════════════════════════════════════════════════════════

    async def get_data_log(
        self,
        *,
        channel_id: int | None = None,
        direction: str | None = None,
        table_name: str | None = None,
        limit: int = 200,
    ) -> list[dict]:
        """Query the shared data exchange audit log."""
        sql = "SELECT * FROM _shared_data_log WHERE 1=1"
        params: list[Any] = []
        if channel_id:
            sql += " AND shared_channel_id = ?"
            params.append(channel_id)
        if direction:
            sql += " AND direction = ?"
            params.append(direction)
        if table_name:
            sql += " AND table_name = ?"
            params.append(table_name)
        sql += " ORDER BY synced_at DESC, id DESC LIMIT ?"
        params.append(limit)

        cursor = await self.db.execute(sql, tuple(params))
        rows = await cursor.fetchall()
        results = []
        for r in rows:
            d = dict(r)
            d["redactions_applied"] = json.loads(d.get("redactions_applied") or "[]")
            results.append(d)
        return results

    async def get_channel_stats(self, channel_id: int) -> dict:
        """Get exchange statistics for a shared channel."""
        cursor = await self.db.execute(
            """SELECT
                 direction,
                 COUNT(*) as record_count,
                 COUNT(DISTINCT table_name) as table_count,
                 MIN(synced_at) as first_exchange,
                 MAX(synced_at) as last_exchange
               FROM _shared_data_log
               WHERE shared_channel_id = ?
               GROUP BY direction""",
            (channel_id,),
        )
        rows = await cursor.fetchall()
        stats = {
            "outbound": {"record_count": 0, "table_count": 0},
            "inbound": {"record_count": 0, "table_count": 0},
        }
        for r in rows:
            d = dict(r)
            direction = d.pop("direction")
            stats[direction] = d
        return stats

    # ══════════════════════════════════════════════════════════════
    # Internal Helpers
    # ══════════════════════════════════════════════════════════════

    async def _audit(
        self,
        event_type: str,
        *,
        device_id: str | None = None,
        company_id: str | None = None,
        actor: int | None = None,
        details: dict | None = None,
        ip_address: str | None = None,
    ) -> None:
        """Append event to security audit log."""
        await self.db.execute(
            """INSERT INTO _security_audit_log
               (event_type, device_id, company_id,
                actor_user_id, details_json, ip_address)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (event_type, device_id, company_id, actor,
             json.dumps(details or {}), ip_address),
        )
        await self.db.commit()
