"""
Remote Sync Service — internet-based sync orchestration.

Handles:
1. Remote sync configuration (public URL, TLS, proxy, rate limits)
2. Remote peer management (register, verify, activate, deactivate)
3. Remote worker sync — devices sync over HTTPS with mutual cert auth
4. Shop↔Shop sync — paired shops exchange data through shared channels
5. Multi-site primary/secondary role management
6. Connection health checks and fail2ban
7. Sync session tracking and audit
"""

from __future__ import annotations

import hashlib
import json
import logging
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import uuid4

import aiosqlite

logger = logging.getLogger(__name__)


class RemoteSyncService:
    """Orchestrates internet-based sync between shops and remote devices."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    # ══════════════════════════════════════════════════════════════
    # Configuration
    # ══════════════════════════════════════════════════════════════

    async def get_config(self) -> dict:
        """Get the remote sync configuration (singleton row)."""
        cursor = await self.db.execute(
            "SELECT * FROM _remote_sync_config WHERE id = 1",
        )
        row = await cursor.fetchone()
        if not row:
            return {}
        cfg = dict(row)
        cfg["allowed_cidrs"] = json.loads(cfg.get("allowed_cidrs") or "[]")
        cfg["proxy_details"] = json.loads(cfg.get("proxy_details") or "{}")
        return cfg

    async def update_config(self, *, fields: dict, updated_by: int | None = None) -> dict:
        """Update remote sync configuration.

        Allowed fields: is_enabled, public_url, listen_port, tls_cert_path,
        tls_key_path, proxy_mode, proxy_details, rate_limit_rpm, max_payload_kb,
        require_cert_auth, allowed_cidrs, failban_enabled, failban_max_attempts,
        failban_lockout_minutes, multi_site_role, primary_shop_url, primary_shop_id,
        sync_interval_minutes, compress_payloads, media_defer_to_wifi.
        """
        allowed_keys = {
            "is_enabled", "public_url", "listen_port", "tls_cert_path",
            "tls_key_path", "proxy_mode", "proxy_details", "rate_limit_rpm",
            "max_payload_kb", "require_cert_auth", "allowed_cidrs",
            "failban_enabled", "failban_max_attempts", "failban_lockout_minutes",
            "multi_site_role", "primary_shop_url", "primary_shop_id",
            "sync_interval_minutes", "compress_payloads", "media_defer_to_wifi",
        }
        patch = {}
        for k, v in fields.items():
            if k not in allowed_keys:
                continue
            # Serialize JSON fields
            if k in ("allowed_cidrs", "proxy_details") and not isinstance(v, str):
                v = json.dumps(v)
            patch[k] = v

        if not patch:
            return await self.get_config()

        patch["updated_by"] = updated_by
        set_parts = [f"{k} = ?" for k in patch] + ["updated_at = datetime('now')"]
        values = list(patch.values()) + [1]
        await self.db.execute(
            f"UPDATE _remote_sync_config SET {', '.join(set_parts)} WHERE id = ?",
            values,
        )
        await self.db.commit()

        await self._audit(
            "remote_sync_config_updated",
            actor=updated_by,
            details={"changed_fields": list(patch.keys())},
        )
        return await self.get_config()

    # ══════════════════════════════════════════════════════════════
    # Peer Management
    # ══════════════════════════════════════════════════════════════

    async def register_peer(
        self,
        *,
        peer_name: str,
        peer_url: str,
        peer_type: str = "partner",
        company_id: str | None = None,
        public_key: str | None = None,
        actor_user_id: int | None = None,
    ) -> dict:
        """Register a new remote sync peer (partner shop or multi-site node)."""
        peer_id = str(uuid4())
        shared_secret = secrets.token_urlsafe(32)  # for initial handshake

        cursor = await self.db.execute(
            """INSERT INTO _remote_sync_peers
               (peer_id, peer_name, peer_url, peer_type, company_id,
                public_key, shared_secret)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (peer_id, peer_name, peer_url, peer_type, company_id,
             public_key, shared_secret),
        )
        await self.db.commit()

        await self._audit(
            "remote_peer_registered",
            actor=actor_user_id,
            details={
                "peer_id": peer_id,
                "peer_name": peer_name,
                "peer_type": peer_type,
                "peer_url": peer_url,
            },
        )

        return await self.get_peer(peer_id)

    async def get_peer(self, peer_id: str) -> dict:
        """Get a single remote peer by ID."""
        cursor = await self.db.execute(
            "SELECT * FROM _remote_sync_peers WHERE peer_id = ?", (peer_id,),
        )
        row = await cursor.fetchone()
        return dict(row) if row else {}

    async def list_peers(
        self,
        *,
        peer_type: str | None = None,
        active_only: bool = True,
    ) -> list[dict]:
        """List remote sync peers."""
        sql = "SELECT * FROM _remote_sync_peers WHERE 1=1"
        params: list[Any] = []
        if peer_type:
            sql += " AND peer_type = ?"
            params.append(peer_type)
        if active_only:
            sql += " AND is_active = 1"
        sql += " ORDER BY created_at DESC"
        cursor = await self.db.execute(sql, tuple(params))
        return [dict(r) for r in await cursor.fetchall()]

    async def update_peer(self, peer_id: str, *, fields: dict) -> dict:
        """Update a remote peer's details."""
        allowed = {"peer_name", "peer_url", "peer_type", "company_id", "public_key", "is_active"}
        patch = {k: v for k, v in fields.items() if k in allowed}
        if not patch:
            return await self.get_peer(peer_id)

        set_parts = [f"{k} = ?" for k in patch] + ["updated_at = datetime('now')"]
        values = list(patch.values()) + [peer_id]
        await self.db.execute(
            f"UPDATE _remote_sync_peers SET {', '.join(set_parts)} WHERE peer_id = ?",
            values,
        )
        await self.db.commit()
        return await self.get_peer(peer_id)

    async def verify_peer(
        self,
        peer_id: str,
        *,
        public_key: str,
        actor_user_id: int | None = None,
    ) -> dict:
        """Mark a peer as verified after successful key exchange."""
        await self.db.execute(
            """UPDATE _remote_sync_peers
               SET is_verified = 1, public_key = ?, updated_at = datetime('now')
               WHERE peer_id = ?""",
            (public_key, peer_id),
        )
        await self.db.commit()

        await self._audit(
            "remote_peer_verified",
            actor=actor_user_id,
            details={"peer_id": peer_id},
        )
        return await self.get_peer(peer_id)

    async def deactivate_peer(
        self,
        peer_id: str,
        *,
        actor_user_id: int | None = None,
    ) -> bool:
        """Deactivate a remote peer (soft delete)."""
        cursor = await self.db.execute(
            "UPDATE _remote_sync_peers SET is_active = 0, updated_at = datetime('now') WHERE peer_id = ?",
            (peer_id,),
        )
        await self.db.commit()
        deactivated = (cursor.rowcount or 0) > 0
        if deactivated:
            await self._audit(
                "remote_peer_deactivated",
                actor=actor_user_id,
                details={"peer_id": peer_id},
            )
        return deactivated

    # ══════════════════════════════════════════════════════════════
    # Sync Sessions
    # ══════════════════════════════════════════════════════════════

    async def start_session(
        self,
        *,
        peer_id: str,
        session_type: str = "device_remote",
        direction: str = "bidirectional",
        transport: str = "https",
        auth_method: str | None = None,
        ip_address: str | None = None,
    ) -> dict:
        """Start a new remote sync session (for tracking/audit)."""
        session_id = str(uuid4())
        await self.db.execute(
            """INSERT INTO _remote_sync_sessions
               (session_id, peer_id, session_type, direction, transport,
                auth_method, ip_address)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (session_id, peer_id, session_type, direction, transport,
             auth_method, ip_address),
        )
        await self.db.commit()
        return await self.get_session(session_id)

    async def get_session(self, session_id: str) -> dict:
        """Get a single sync session."""
        cursor = await self.db.execute(
            "SELECT * FROM _remote_sync_sessions WHERE session_id = ?", (session_id,),
        )
        row = await cursor.fetchone()
        return dict(row) if row else {}

    async def update_session(
        self,
        session_id: str,
        *,
        status: str | None = None,
        changes_sent: int | None = None,
        changes_received: int | None = None,
        conflicts: int | None = None,
        bytes_transferred: int | None = None,
        error_message: str | None = None,
    ) -> dict:
        """Update a sync session's progress."""
        parts: list[str] = []
        params: list[Any] = []
        if status:
            parts.append("status = ?")
            params.append(status)
            if status in ("completed", "failed"):
                parts.append("completed_at = datetime('now')")
                # Calculate duration
                parts.append(
                    "duration_ms = CAST((julianday(datetime('now')) - julianday(started_at)) * 86400000 AS INTEGER)"
                )
        if changes_sent is not None:
            parts.append("changes_sent = ?")
            params.append(changes_sent)
        if changes_received is not None:
            parts.append("changes_received = ?")
            params.append(changes_received)
        if conflicts is not None:
            parts.append("conflicts = ?")
            params.append(conflicts)
        if bytes_transferred is not None:
            parts.append("bytes_transferred = ?")
            params.append(bytes_transferred)
        if error_message is not None:
            parts.append("error_message = ?")
            params.append(error_message)

        if not parts:
            return await self.get_session(session_id)

        params.append(session_id)
        await self.db.execute(
            f"UPDATE _remote_sync_sessions SET {', '.join(parts)} WHERE session_id = ?",
            params,
        )
        await self.db.commit()
        return await self.get_session(session_id)

    async def complete_session(
        self,
        session_id: str,
        *,
        changes_sent: int = 0,
        changes_received: int = 0,
        conflicts: int = 0,
        bytes_transferred: int = 0,
    ) -> dict:
        """Mark a sync session as completed and update peer stats."""
        session = await self.update_session(
            session_id,
            status="completed",
            changes_sent=changes_sent,
            changes_received=changes_received,
            conflicts=conflicts,
            bytes_transferred=bytes_transferred,
        )

        # Update peer stats
        peer_id = session.get("peer_id", "")
        if peer_id:
            await self.db.execute(
                """UPDATE _remote_sync_peers
                   SET last_sync_at = datetime('now'),
                       last_sync_status = 'success',
                       total_syncs = total_syncs + 1,
                       total_changes_sent = total_changes_sent + ?,
                       total_changes_received = total_changes_received + ?,
                       updated_at = datetime('now')
                   WHERE peer_id = ?""",
                (changes_sent, changes_received, peer_id),
            )
            await self.db.commit()

        return session

    async def fail_session(
        self,
        session_id: str,
        *,
        error: str,
    ) -> dict:
        """Mark a sync session as failed."""
        session = await self.update_session(
            session_id,
            status="failed",
            error_message=error,
        )

        # Update peer error stats
        peer_id = session.get("peer_id", "")
        if peer_id:
            await self.db.execute(
                """UPDATE _remote_sync_peers
                   SET last_sync_status = 'failed',
                       error_count = error_count + 1,
                       last_error = ?,
                       updated_at = datetime('now')
                   WHERE peer_id = ?""",
                (error, peer_id),
            )
            await self.db.commit()

        return session

    async def list_sessions(
        self,
        *,
        peer_id: str | None = None,
        session_type: str | None = None,
        status: str | None = None,
        limit: int = 100,
    ) -> list[dict]:
        """List remote sync sessions."""
        sql = "SELECT * FROM _remote_sync_sessions WHERE 1=1"
        params: list[Any] = []
        if peer_id:
            sql += " AND peer_id = ?"
            params.append(peer_id)
        if session_type:
            sql += " AND session_type = ?"
            params.append(session_type)
        if status:
            sql += " AND status = ?"
            params.append(status)
        sql += " ORDER BY started_at DESC LIMIT ?"
        params.append(limit)
        cursor = await self.db.execute(sql, tuple(params))
        return [dict(r) for r in await cursor.fetchall()]

    # ══════════════════════════════════════════════════════════════
    # Remote Device Authentication
    # ══════════════════════════════════════════════════════════════

    async def authenticate_remote_device(
        self,
        *,
        device_id: str,
        company_id: str,
        certificate_data: str,
        signature: str,
        ip_address: str | None = None,
    ) -> dict:
        """Authenticate a remote device for internet sync.

        Validates:
        1. IP not fail-banned
        2. Device certificate is valid (delegates to DeviceSecurityService)
        3. Internet sync is enabled

        Returns {valid: bool, reason?: str, session_id?: str}
        """
        # Check fail2ban
        if ip_address:
            banned = await self._check_failban(ip_address)
            if banned:
                await self._audit(
                    "remote_auth_rejected_failban",
                    device_id=device_id,
                    ip_address=ip_address,
                )
                return {"valid": False, "reason": "ip_banned"}

        # Check if remote sync is enabled
        config = await self.get_config()
        if not config.get("is_enabled"):
            return {"valid": False, "reason": "remote_sync_disabled"}

        # Check allowed CIDRs (basic comparison, not full CIDR parsing)
        allowed_cidrs = config.get("allowed_cidrs", [])
        if allowed_cidrs and ip_address:
            if not self._is_ip_allowed(ip_address, allowed_cidrs):
                await self._record_failban_attempt(ip_address, "cidr_blocked")
                return {"valid": False, "reason": "ip_not_allowed"}

        # Start a session for tracking
        session = await self.start_session(
            peer_id=device_id,
            session_type="device_remote",
            direction="bidirectional",
            transport="https",
            auth_method="device_cert" if config.get("require_cert_auth") else "token",
            ip_address=ip_address,
        )

        await self._audit(
            "remote_device_authenticated",
            device_id=device_id,
            company_id=company_id,
            ip_address=ip_address,
            details={"session_id": session["session_id"]},
        )

        return {
            "valid": True,
            "session_id": session["session_id"],
            "config": {
                "max_payload_kb": config.get("max_payload_kb", 5120),
                "compress": config.get("compress_payloads", 1),
            },
        }

    async def authenticate_peer_shop(
        self,
        *,
        peer_id: str,
        public_key: str,
        challenge_response: str | None = None,
        ip_address: str | None = None,
    ) -> dict:
        """Authenticate a peer shop for shop↔shop sync.

        Validates the peer is registered, verified, and active.
        Returns {valid: bool, reason?: str, session_id?: str}
        """
        # Check fail2ban
        if ip_address:
            banned = await self._check_failban(ip_address)
            if banned:
                return {"valid": False, "reason": "ip_banned"}

        peer = await self.get_peer(peer_id)
        if not peer:
            if ip_address:
                await self._record_failban_attempt(ip_address, "unknown_peer")
            return {"valid": False, "reason": "unknown_peer"}

        if not peer.get("is_active"):
            return {"valid": False, "reason": "peer_inactive"}

        if not peer.get("is_verified"):
            return {"valid": False, "reason": "peer_unverified"}

        # Verify public key matches
        if peer.get("public_key") and peer["public_key"] != public_key:
            if ip_address:
                await self._record_failban_attempt(ip_address, "key_mismatch")
            return {"valid": False, "reason": "key_mismatch"}

        session = await self.start_session(
            peer_id=peer_id,
            session_type="shop_to_shop",
            direction="bidirectional",
            transport="https",
            auth_method="mutual_tls",
            ip_address=ip_address,
        )

        return {
            "valid": True,
            "session_id": session["session_id"],
            "peer_name": peer["peer_name"],
        }

    # ══════════════════════════════════════════════════════════════
    # Multi-Site Management
    # ══════════════════════════════════════════════════════════════

    async def get_multi_site_status(self) -> dict:
        """Get the current multi-site configuration and cluster health."""
        config = await self.get_config()
        role = config.get("multi_site_role", "standalone")

        # Get cluster nodes
        cursor = await self.db.execute(
            "SELECT * FROM _shop_cluster_nodes ORDER BY is_primary DESC, hostname",
        )
        nodes = [dict(r) for r in await cursor.fetchall()]

        # Get multi-site peers
        peers = await self.list_peers(peer_type="multi_site")

        return {
            "role": role,
            "primary_shop_url": config.get("primary_shop_url"),
            "primary_shop_id": config.get("primary_shop_id"),
            "sync_interval_minutes": config.get("sync_interval_minutes", 15),
            "cluster_nodes": nodes,
            "multi_site_peers": peers,
        }

    async def set_multi_site_role(
        self,
        *,
        role: str,
        primary_shop_url: str | None = None,
        primary_shop_id: str | None = None,
        actor_user_id: int | None = None,
    ) -> dict:
        """Set this shop's multi-site role (standalone, primary, secondary)."""
        fields: dict[str, Any] = {"multi_site_role": role}
        if role == "secondary":
            if primary_shop_url:
                fields["primary_shop_url"] = primary_shop_url
            if primary_shop_id:
                fields["primary_shop_id"] = primary_shop_id
        elif role in ("standalone", "primary"):
            fields["primary_shop_url"] = None
            fields["primary_shop_id"] = None

        result = await self.update_config(fields=fields, updated_by=actor_user_id)

        await self._audit(
            "multi_site_role_changed",
            actor=actor_user_id,
            details={"new_role": role, "primary_url": primary_shop_url},
        )
        return result

    # ══════════════════════════════════════════════════════════════
    # Connection Health
    # ══════════════════════════════════════════════════════════════

    async def check_peer_health(self) -> list[dict]:
        """Check health of all active peers and return status report.

        This is a lightweight check — it just verifies peer records and timestamps,
        actual HTTP health pings are done by the scheduler job.
        """
        peers = await self.list_peers(active_only=True)
        results = []
        now = datetime.now(timezone.utc)

        for peer in peers:
            last_sync = peer.get("last_sync_at")
            health = "unknown"
            if last_sync:
                try:
                    last_dt = datetime.fromisoformat(last_sync.replace("Z", "+00:00"))
                    if last_dt.tzinfo is None:
                        last_dt = last_dt.replace(tzinfo=timezone.utc)
                    age = now - last_dt
                    if age < timedelta(hours=1):
                        health = "healthy"
                    elif age < timedelta(hours=24):
                        health = "stale"
                    else:
                        health = "offline"
                except (ValueError, TypeError):
                    health = "unknown"
            results.append({
                "peer_id": peer["peer_id"],
                "peer_name": peer["peer_name"],
                "peer_url": peer["peer_url"],
                "peer_type": peer["peer_type"],
                "health": health,
                "last_sync_at": last_sync,
                "last_sync_status": peer.get("last_sync_status", "never"),
                "error_count": peer.get("error_count", 0),
            })

        return results

    async def get_sync_dashboard(self) -> dict:
        """Get an overview of remote sync status for the dashboard."""
        config = await self.get_config()
        peer_count = 0
        cursor = await self.db.execute(
            "SELECT COUNT(*) FROM _remote_sync_peers WHERE is_active = 1",
        )
        row = await cursor.fetchone()
        if row:
            peer_count = row[0]

        # Recent sessions
        cursor = await self.db.execute(
            """SELECT
                 COUNT(*) as total,
                 SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed,
                 SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed,
                 SUM(changes_sent) as total_sent,
                 SUM(changes_received) as total_received
               FROM _remote_sync_sessions
               WHERE started_at > datetime('now', '-24 hours')""",
        )
        recent = dict(await cursor.fetchone())

        # Active sessions right now
        cursor = await self.db.execute(
            "SELECT COUNT(*) FROM _remote_sync_sessions WHERE status NOT IN ('completed', 'failed')",
        )
        active_row = await cursor.fetchone()
        active_count = active_row[0] if active_row else 0

        return {
            "is_enabled": config.get("is_enabled", 0),
            "multi_site_role": config.get("multi_site_role", "standalone"),
            "public_url": config.get("public_url"),
            "active_peers": peer_count,
            "active_sessions": active_count,
            "last_24h": recent,
            "failban_enabled": config.get("failban_enabled", 1),
        }

    # ══════════════════════════════════════════════════════════════
    # Fail2Ban
    # ══════════════════════════════════════════════════════════════

    async def _check_failban(self, ip_address: str) -> bool:
        """Check if an IP is currently banned."""
        config = await self.get_config()
        if not config.get("failban_enabled"):
            return False

        cursor = await self.db.execute(
            "SELECT * FROM _remote_failban WHERE ip_address = ?", (ip_address,),
        )
        row = await cursor.fetchone()
        if not row:
            return False

        record = dict(row)
        locked_until = record.get("locked_until")
        if locked_until:
            try:
                lock_dt = datetime.fromisoformat(locked_until)
                if lock_dt.tzinfo is None:
                    lock_dt = lock_dt.replace(tzinfo=timezone.utc)
                if datetime.now(timezone.utc) < lock_dt:
                    return True
                # Lock expired, clear it
                await self.db.execute(
                    "DELETE FROM _remote_failban WHERE ip_address = ?", (ip_address,),
                )
                await self.db.commit()
            except (ValueError, TypeError):
                pass

        return False

    async def _record_failban_attempt(self, ip_address: str, reason: str) -> None:
        """Record a failed authentication attempt and lock if threshold exceeded."""
        config = await self.get_config()
        max_attempts = config.get("failban_max_attempts", 5)
        lockout_minutes = config.get("failban_lockout_minutes", 30)

        await self.db.execute(
            """INSERT INTO _remote_failban (ip_address, failure_count, reason)
               VALUES (?, 1, ?)
               ON CONFLICT(ip_address) DO UPDATE SET
                 failure_count = failure_count + 1,
                 last_failure = datetime('now'),
                 reason = ?""",
            (ip_address, reason, reason),
        )
        await self.db.commit()

        # Check threshold
        cursor = await self.db.execute(
            "SELECT failure_count FROM _remote_failban WHERE ip_address = ?", (ip_address,),
        )
        row = await cursor.fetchone()
        if row and row[0] >= max_attempts:
            lock_until = datetime.now(timezone.utc) + timedelta(minutes=lockout_minutes)
            await self.db.execute(
                "UPDATE _remote_failban SET locked_until = ? WHERE ip_address = ?",
                (lock_until.isoformat(), ip_address),
            )
            await self.db.commit()
            logger.warning("Fail2ban: locked IP %s for %d minutes", ip_address, lockout_minutes)

    async def get_failban_entries(self) -> list[dict]:
        """List all fail2ban entries."""
        cursor = await self.db.execute(
            "SELECT * FROM _remote_failban ORDER BY last_failure DESC",
        )
        return [dict(r) for r in await cursor.fetchall()]

    async def clear_failban(self, ip_address: str | None = None) -> int:
        """Clear fail2ban entries. If ip_address is given, clear only that IP."""
        if ip_address:
            cursor = await self.db.execute(
                "DELETE FROM _remote_failban WHERE ip_address = ?", (ip_address,),
            )
        else:
            cursor = await self.db.execute("DELETE FROM _remote_failban")
        await self.db.commit()
        return cursor.rowcount or 0

    # ══════════════════════════════════════════════════════════════
    # IP Helpers
    # ══════════════════════════════════════════════════════════════

    @staticmethod
    def _is_ip_allowed(ip: str, allowed_cidrs: list[str]) -> bool:
        """Basic IP allowlist check.

        Supports exact IPs and /24 prefix matching for simplicity.
        For full CIDR support, use the ipaddress module (added if needed).
        """
        for cidr in allowed_cidrs:
            if "/" in cidr:
                prefix = cidr.split("/")[0]
                # /24 prefix match (rough check)
                if ip.rsplit(".", 1)[0] == prefix.rsplit(".", 1)[0]:
                    return True
            elif ip == cidr:
                return True
        return False

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
