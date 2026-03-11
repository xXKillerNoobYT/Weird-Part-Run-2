"""
Remote Sync routes — internet sync, peer management, shared channels, file sync.

Endpoints:
  ──── Remote Sync Config ────
  GET    /api/remote-sync/config              → Get remote sync configuration
  PUT    /api/remote-sync/config              → Update remote sync configuration

  ──── Peer Management ────
  POST   /api/remote-sync/peers               → Register a remote peer
  GET    /api/remote-sync/peers               → List remote peers
  GET    /api/remote-sync/peers/:peer_id      → Get a single peer
  PUT    /api/remote-sync/peers/:peer_id      → Update a peer
  POST   /api/remote-sync/peers/:peer_id/verify    → Verify a peer (key exchange)
  POST   /api/remote-sync/peers/:peer_id/deactivate → Deactivate a peer

  ──── Sync Sessions ────
  GET    /api/remote-sync/sessions            → List sync sessions
  GET    /api/remote-sync/sessions/:session_id → Get session details
  GET    /api/remote-sync/dashboard           → Remote sync overview dashboard

  ──── Remote Device Auth ────
  POST   /api/remote-sync/auth/device         → Authenticate a remote device
  POST   /api/remote-sync/auth/peer           → Authenticate a peer shop

  ──── Multi-Site ────
  GET    /api/remote-sync/multi-site          → Get multi-site status
  PUT    /api/remote-sync/multi-site/role     → Set multi-site role

  ──── Fail2Ban ────
  GET    /api/remote-sync/failban             → List fail2ban entries
  DELETE /api/remote-sync/failban             → Clear fail2ban (all or by IP)

  ──── Shared Channels (Enhanced) ────
  POST   /api/remote-sync/channels            → Create shared channel
  GET    /api/remote-sync/channels            → List shared channels
  GET    /api/remote-sync/channels/:id        → Get channel details
  PUT    /api/remote-sync/channels/:id        → Update channel scope/permissions
  POST   /api/remote-sync/channels/:id/renew  → Renew channel expiry
  POST   /api/remote-sync/channels/:id/revoke → Revoke channel
  POST   /api/remote-sync/channels/:id/accept → Accept channel invitation

  ──── Redaction Rules ────
  POST   /api/remote-sync/channels/:id/redactions       → Add redaction rule
  GET    /api/remote-sync/channels/:id/redactions       → List redaction rules
  DELETE /api/remote-sync/channels/:id/redactions/:rule_id → Remove redaction rule

  ──── Data Exchange Log ────
  GET    /api/remote-sync/channels/:id/data-log   → Channel data exchange log
  GET    /api/remote-sync/channels/:id/stats      → Channel exchange statistics

  ──── File-Based Sync ────
  POST   /api/remote-sync/file-sync/export        → Export sync package
  POST   /api/remote-sync/file-sync/import        → Import sync package
  GET    /api/remote-sync/file-sync/packages       → List file sync packages
  GET    /api/remote-sync/file-sync/packages/:id   → Get package details

  ──── Peer Health ────
  GET    /api/remote-sync/health                   → Check peer health
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel, Field
from typing import Any

import aiosqlite

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse
from app.services.remote_sync_service import RemoteSyncService
from app.services.shared_channel_service import SharedChannelService
from app.services.file_sync_service import FileSyncService

router = APIRouter(prefix="/api/remote-sync", tags=["Remote Sync"])


# ══════════════════════════════════════════════════════════════════
# Request Models
# ══════════════════════════════════════════════════════════════════


class ConfigUpdatePayload(BaseModel):
    fields: dict = Field(default_factory=dict)


class PeerCreatePayload(BaseModel):
    peer_name: str
    peer_url: str
    peer_type: str = "partner"
    company_id: str | None = None
    public_key: str | None = None


class PeerUpdatePayload(BaseModel):
    peer_name: str | None = None
    peer_url: str | None = None
    peer_type: str | None = None
    company_id: str | None = None
    public_key: str | None = None
    is_active: bool | None = None


class PeerVerifyPayload(BaseModel):
    public_key: str


class DeviceAuthPayload(BaseModel):
    device_id: str
    company_id: str
    certificate_data: str
    signature: str


class PeerAuthPayload(BaseModel):
    peer_id: str
    public_key: str
    challenge_response: str | None = None


class MultiSiteRolePayload(BaseModel):
    role: str  # standalone, primary, secondary
    primary_shop_url: str | None = None
    primary_shop_id: str | None = None


class ChannelCreatePayload(BaseModel):
    channel_name: str
    owner_company_id: str
    partner_company_ids: list[str] = Field(default_factory=list)
    scope: dict = Field(default_factory=dict)
    permissions: dict = Field(default_factory=dict)
    description: str | None = None
    expires_at: str | None = None
    auto_expire_days: int | None = None


class ChannelUpdatePayload(BaseModel):
    scope: dict | None = None
    permissions: dict | None = None
    description: str | None = None
    expires_at: str | None = None
    auto_expire_days: int | None = None


class ChannelRenewPayload(BaseModel):
    new_expires_at: str | None = None


class ChannelRevokePayload(BaseModel):
    reason: str | None = None


class RedactionRulePayload(BaseModel):
    table_name: str
    field_name: str
    redaction_type: str = "remove"
    replacement_value: str | None = None


class FileExportPayload(BaseModel):
    tables: list[str] | None = None
    changes_since: str | None = None
    passphrase: str | None = None
    key_hint: str | None = None
    expires_days: int = 30


class FileImportPayload(BaseModel):
    file_path: str
    passphrase: str | None = None


# ══════════════════════════════════════════════════════════════════
# Remote Sync Config
# ══════════════════════════════════════════════════════════════════


@router.get("/config")
async def get_config(
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get the remote sync configuration."""
    svc = RemoteSyncService(db)
    cfg = await svc.get_config()
    return ApiResponse(data=cfg)


@router.put("/config")
async def update_config(
    payload: ConfigUpdatePayload,
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update remote sync configuration settings."""
    svc = RemoteSyncService(db)
    cfg = await svc.update_config(fields=payload.fields, updated_by=user.get("id"))
    return ApiResponse(data=cfg, message="Remote sync config updated")


# ══════════════════════════════════════════════════════════════════
# Peer Management
# ══════════════════════════════════════════════════════════════════


@router.post("/peers")
async def register_peer(
    payload: PeerCreatePayload,
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Register a new remote sync peer."""
    svc = RemoteSyncService(db)
    peer = await svc.register_peer(
        peer_name=payload.peer_name,
        peer_url=payload.peer_url,
        peer_type=payload.peer_type,
        company_id=payload.company_id,
        public_key=payload.public_key,
        actor_user_id=user.get("id"),
    )
    return ApiResponse(data=peer, message="Peer registered")


@router.get("/peers")
async def list_peers(
    peer_type: str | None = Query(None),
    active_only: bool = Query(True),
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List remote sync peers."""
    svc = RemoteSyncService(db)
    peers = await svc.list_peers(peer_type=peer_type, active_only=active_only)
    return ApiResponse(data=peers, message=f"{len(peers)} peers")


@router.get("/peers/{peer_id}")
async def get_peer(
    peer_id: str,
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a single remote peer."""
    svc = RemoteSyncService(db)
    peer = await svc.get_peer(peer_id)
    if not peer:
        return ApiResponse(data=None, message="Peer not found")
    return ApiResponse(data=peer)


@router.put("/peers/{peer_id}")
async def update_peer(
    peer_id: str,
    payload: PeerUpdatePayload,
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a remote peer's details."""
    svc = RemoteSyncService(db)
    fields = payload.model_dump(exclude_none=True)
    peer = await svc.update_peer(peer_id, fields=fields)
    return ApiResponse(data=peer, message="Peer updated")


@router.post("/peers/{peer_id}/verify")
async def verify_peer(
    peer_id: str,
    payload: PeerVerifyPayload,
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Verify a peer's identity via public key exchange."""
    svc = RemoteSyncService(db)
    peer = await svc.verify_peer(
        peer_id, public_key=payload.public_key, actor_user_id=user.get("id"),
    )
    return ApiResponse(data=peer, message="Peer verified")


@router.post("/peers/{peer_id}/deactivate")
async def deactivate_peer(
    peer_id: str,
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Deactivate a remote peer (soft delete)."""
    svc = RemoteSyncService(db)
    ok = await svc.deactivate_peer(peer_id, actor_user_id=user.get("id"))
    msg = "Peer deactivated" if ok else "Peer not found or already inactive"
    return ApiResponse(data={"deactivated": ok}, message=msg)


# ══════════════════════════════════════════════════════════════════
# Sync Sessions
# ══════════════════════════════════════════════════════════════════


@router.get("/sessions")
async def list_sessions(
    peer_id: str | None = Query(None),
    session_type: str | None = Query(None),
    status: str | None = Query(None),
    limit: int = Query(100, le=500),
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List remote sync sessions."""
    svc = RemoteSyncService(db)
    sessions = await svc.list_sessions(
        peer_id=peer_id, session_type=session_type, status=status, limit=limit,
    )
    return ApiResponse(data=sessions, message=f"{len(sessions)} sessions")


@router.get("/sessions/{session_id}")
async def get_session(
    session_id: str,
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a single sync session."""
    svc = RemoteSyncService(db)
    session = await svc.get_session(session_id)
    if not session:
        return ApiResponse(data=None, message="Session not found")
    return ApiResponse(data=session)


@router.get("/dashboard")
async def sync_dashboard(
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get the remote sync overview dashboard."""
    svc = RemoteSyncService(db)
    data = await svc.get_sync_dashboard()
    return ApiResponse(data=data)


# ══════════════════════════════════════════════════════════════════
# Remote Authentication
# ══════════════════════════════════════════════════════════════════


@router.post("/auth/device")
async def authenticate_device(
    payload: DeviceAuthPayload,
    request: Request,
    db: aiosqlite.Connection = Depends(get_db),
):
    """Authenticate a remote device for internet sync.

    No user auth required — the device authenticates via certificate.
    """
    svc = RemoteSyncService(db)
    ip = request.client.host if request.client else None
    result = await svc.authenticate_remote_device(
        device_id=payload.device_id,
        company_id=payload.company_id,
        certificate_data=payload.certificate_data,
        signature=payload.signature,
        ip_address=ip,
    )
    return ApiResponse(data=result)


@router.post("/auth/peer")
async def authenticate_peer(
    payload: PeerAuthPayload,
    request: Request,
    db: aiosqlite.Connection = Depends(get_db),
):
    """Authenticate a peer shop for shop-to-shop sync.

    No user auth required — the peer authenticates via public key.
    """
    svc = RemoteSyncService(db)
    ip = request.client.host if request.client else None
    result = await svc.authenticate_peer_shop(
        peer_id=payload.peer_id,
        public_key=payload.public_key,
        challenge_response=payload.challenge_response,
        ip_address=ip,
    )
    return ApiResponse(data=result)


# ══════════════════════════════════════════════════════════════════
# Multi-Site
# ══════════════════════════════════════════════════════════════════


@router.get("/multi-site")
async def get_multi_site_status(
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get multi-site configuration and cluster health."""
    svc = RemoteSyncService(db)
    data = await svc.get_multi_site_status()
    return ApiResponse(data=data)


@router.put("/multi-site/role")
async def set_multi_site_role(
    payload: MultiSiteRolePayload,
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Set this shop's multi-site role (standalone, primary, secondary)."""
    svc = RemoteSyncService(db)
    cfg = await svc.set_multi_site_role(
        role=payload.role,
        primary_shop_url=payload.primary_shop_url,
        primary_shop_id=payload.primary_shop_id,
        actor_user_id=user.get("id"),
    )
    return ApiResponse(data=cfg, message=f"Multi-site role set to {payload.role}")


# ══════════════════════════════════════════════════════════════════
# Fail2Ban
# ══════════════════════════════════════════════════════════════════


@router.get("/failban")
async def list_failban(
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List fail2ban entries."""
    svc = RemoteSyncService(db)
    entries = await svc.get_failban_entries()
    return ApiResponse(data=entries, message=f"{len(entries)} entries")


@router.delete("/failban")
async def clear_failban(
    ip: str | None = Query(None),
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Clear fail2ban entries (all or specific IP)."""
    svc = RemoteSyncService(db)
    cleared = await svc.clear_failban(ip_address=ip)
    return ApiResponse(data={"cleared": cleared}, message=f"Cleared {cleared} entries")


# ══════════════════════════════════════════════════════════════════
# Shared Channels (Enhanced)
# ══════════════════════════════════════════════════════════════════


@router.post("/channels")
async def create_channel(
    payload: ChannelCreatePayload,
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a cross-company shared channel with scope and redaction support."""
    svc = SharedChannelService(db)
    ch = await svc.create_channel(
        channel_name=payload.channel_name,
        owner_company_id=payload.owner_company_id,
        partner_company_ids=payload.partner_company_ids,
        scope=payload.scope,
        permissions=payload.permissions,
        description=payload.description,
        expires_at=payload.expires_at,
        auto_expire_days=payload.auto_expire_days,
        created_by=user.get("id"),
    )
    return ApiResponse(data=ch, message="Shared channel created")


@router.get("/channels")
async def list_channels(
    company_id: str | None = Query(None),
    include_inactive: bool = Query(False),
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List shared channels."""
    svc = SharedChannelService(db)
    channels = await svc.list_channels(
        company_id=company_id, include_inactive=include_inactive,
    )
    return ApiResponse(data=channels, message=f"{len(channels)} channels")


@router.get("/channels/{channel_id}")
async def get_channel(
    channel_id: int,
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a shared channel with members and redaction rules."""
    svc = SharedChannelService(db)
    ch = await svc.get_channel(channel_id)
    if not ch:
        return ApiResponse(data=None, message="Channel not found")
    return ApiResponse(data=ch)


@router.put("/channels/{channel_id}")
async def update_channel(
    channel_id: int,
    payload: ChannelUpdatePayload,
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update a shared channel's scope, permissions, or expiry."""
    svc = SharedChannelService(db)
    ch = await svc.update_channel(
        channel_id,
        scope=payload.scope,
        permissions=payload.permissions,
        description=payload.description,
        expires_at=payload.expires_at,
        auto_expire_days=payload.auto_expire_days,
        updated_by=user.get("id"),
    )
    return ApiResponse(data=ch, message="Channel updated")


@router.post("/channels/{channel_id}/renew")
async def renew_channel(
    channel_id: int,
    payload: ChannelRenewPayload,
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Renew a shared channel's expiry date."""
    svc = SharedChannelService(db)
    ch = await svc.renew_channel(
        channel_id,
        new_expires_at=payload.new_expires_at,
        renewed_by=user.get("id"),
    )
    return ApiResponse(data=ch, message="Channel renewed")


@router.post("/channels/{channel_id}/revoke")
async def revoke_channel(
    channel_id: int,
    payload: ChannelRevokePayload,
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Revoke a shared channel immediately."""
    svc = SharedChannelService(db)
    ok = await svc.revoke_channel(
        channel_id, reason=payload.reason, revoked_by=user.get("id"),
    )
    msg = "Channel revoked" if ok else "Channel not found or already revoked"
    return ApiResponse(data={"revoked": ok}, message=msg)


@router.post("/channels/{channel_id}/accept")
async def accept_channel(
    channel_id: int,
    company_id: str = Query(...),
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Accept a shared channel invitation for a company."""
    svc = SharedChannelService(db)
    ok = await svc.accept_invitation(channel_id, company_id)
    msg = "Invitation accepted" if ok else "No pending invitation found"
    return ApiResponse(data={"accepted": ok}, message=msg)


# ══════════════════════════════════════════════════════════════════
# Redaction Rules
# ══════════════════════════════════════════════════════════════════


@router.post("/channels/{channel_id}/redactions")
async def add_redaction_rule(
    channel_id: int,
    payload: RedactionRulePayload,
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Add or update a field-level redaction rule for a shared channel."""
    svc = SharedChannelService(db)
    rule = await svc.add_redaction_rule(
        channel_id=channel_id,
        table_name=payload.table_name,
        field_name=payload.field_name,
        redaction_type=payload.redaction_type,
        replacement_value=payload.replacement_value,
    )
    return ApiResponse(data=rule, message="Redaction rule saved")


@router.get("/channels/{channel_id}/redactions")
async def list_redaction_rules(
    channel_id: int,
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List active redaction rules for a shared channel."""
    svc = SharedChannelService(db)
    rules = await svc.list_redaction_rules(channel_id)
    return ApiResponse(data=rules, message=f"{len(rules)} rules")


@router.delete("/channels/{channel_id}/redactions/{rule_id}")
async def remove_redaction_rule(
    channel_id: int,
    rule_id: int,
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Remove (deactivate) a redaction rule."""
    svc = SharedChannelService(db)
    ok = await svc.remove_redaction_rule(rule_id)
    msg = "Rule removed" if ok else "Rule not found"
    return ApiResponse(data={"removed": ok}, message=msg)


# ══════════════════════════════════════════════════════════════════
# Data Exchange Log
# ══════════════════════════════════════════════════════════════════


@router.get("/channels/{channel_id}/data-log")
async def get_data_log(
    channel_id: int,
    direction: str | None = Query(None),
    table_name: str | None = Query(None),
    limit: int = Query(200, le=1000),
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get the data exchange audit log for a shared channel."""
    svc = SharedChannelService(db)
    log = await svc.get_data_log(
        channel_id=channel_id, direction=direction,
        table_name=table_name, limit=limit,
    )
    return ApiResponse(data=log, message=f"{len(log)} entries")


@router.get("/channels/{channel_id}/stats")
async def get_channel_stats(
    channel_id: int,
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get exchange statistics for a shared channel."""
    svc = SharedChannelService(db)
    stats = await svc.get_channel_stats(channel_id)
    return ApiResponse(data=stats)


# ══════════════════════════════════════════════════════════════════
# File-Based Sync
# ══════════════════════════════════════════════════════════════════


@router.post("/file-sync/export")
async def export_file_sync(
    payload: FileExportPayload,
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Export a sync package to a file (for USB/sneakernet transfer)."""
    svc = FileSyncService(db)
    pkg = await svc.export_package(
        tables=payload.tables,
        changes_since=payload.changes_since,
        passphrase=payload.passphrase,
        key_hint=payload.key_hint,
        created_by=user.get("id"),
        expires_days=payload.expires_days,
    )
    return ApiResponse(data=pkg, message="File sync package exported")


@router.post("/file-sync/import")
async def import_file_sync(
    payload: FileImportPayload,
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Import a sync package from a file."""
    svc = FileSyncService(db)
    result = await svc.import_package(
        file_path=payload.file_path,
        passphrase=payload.passphrase,
        imported_by=user.get("id"),
    )
    if result.get("error"):
        return ApiResponse(data=result, message=f"Import failed: {result['error']}")
    return ApiResponse(data=result, message="File sync package imported")


@router.get("/file-sync/packages")
async def list_file_sync_packages(
    direction: str | None = Query(None),
    status: str | None = Query(None),
    limit: int = Query(50, le=200),
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List file sync packages."""
    svc = FileSyncService(db)
    packages = await svc.list_packages(direction=direction, status=status, limit=limit)
    return ApiResponse(data=packages, message=f"{len(packages)} packages")


@router.get("/file-sync/packages/{package_id}")
async def get_file_sync_package(
    package_id: str,
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get a single file sync package."""
    svc = FileSyncService(db)
    pkg = await svc.get_package(package_id)
    if not pkg:
        return ApiResponse(data=None, message="Package not found")
    return ApiResponse(data=pkg)


# ══════════════════════════════════════════════════════════════════
# Peer Health
# ══════════════════════════════════════════════════════════════════


@router.get("/health")
async def check_health(
    user: dict = Depends(require_permission("manage_remote_sync")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Check health of all active remote peers."""
    svc = RemoteSyncService(db)
    results = await svc.check_peer_health()
    return ApiResponse(data=results, message=f"{len(results)} peers checked")
