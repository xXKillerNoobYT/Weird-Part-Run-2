"""
Device Security routes — company keys, device certificates, and security audit.

Endpoints:
  POST /api/security/company/init      → Initialise company keys (admin)
  GET  /api/security/company            → Get company info (admin)
  GET  /api/security/companies          → List all companies (admin)
  POST /api/security/company/rotate     → Rotate company keys (admin)
  POST /api/security/certs/issue        → Issue a device certificate (admin)
  POST /api/security/certs/verify       → Verify a certificate (any device)
  GET  /api/security/certs/:device_id   → Get a device's active cert
  POST /api/security/certs/revoke       → Revoke a device certificate (admin)
  POST /api/security/channels           → Create a shared channel (admin)
  GET  /api/security/channels           → List shared channels (admin)
  POST /api/security/channels/:id/deactivate → Deactivate a channel (admin)
  POST /api/security/channels/:id/accept     → Accept a channel invite (admin)
  POST /api/security/bt/hello           → Create BT handshake hello (device)
  POST /api/security/bt/verify-hello    → Verify incoming BT hello (device)
  POST /api/security/bt/verify-ack      → Verify BT ACK (device)
  GET  /api/security/audit              → Security audit log (admin)
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

import aiosqlite

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse
from app.services.device_security_service import DeviceSecurityService

router = APIRouter(prefix="/api/security", tags=["Security"])


# ── Request Models ───────────────────────────────────────────────


class CompanyInitPayload(BaseModel):
    company_id: str
    company_name: str = "My Company"


class CertIssuePayload(BaseModel):
    device_id: str
    company_id: str
    device_public_key: str
    validity_days: int = 365


class CertVerifyPayload(BaseModel):
    device_id: str
    company_id: str
    certificate_data: str
    signature: str


class CertRevokePayload(BaseModel):
    device_id: str
    company_id: str
    reason: str = "manual"


class KeyRotatePayload(BaseModel):
    company_id: str


class SharedChannelCreatePayload(BaseModel):
    channel_name: str
    owner_company_id: str
    partner_company_ids: list[str] = Field(default_factory=list)
    scope: dict = Field(default_factory=dict)
    permissions: dict = Field(default_factory=dict)
    expires_at: str | None = None


class BtHelloPayload(BaseModel):
    device_id: str
    company_id: str


class BtVerifyHelloPayload(BaseModel):
    """Incoming BT_HELLO from a peer device."""
    hello: dict
    responder_device_id: str
    responder_company_id: str


class BtVerifyAckPayload(BaseModel):
    """Incoming BT_HELLO_ACK from the responder."""
    ack: dict
    initiator_device_id: str
    initiator_company_id: str
    original_nonce: str


# ── Endpoints ────────────────────────────────────────────────────


@router.post("/company/init")
async def init_company(
    payload: CompanyInitPayload,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Initialise a company with generated keys.

    Idempotent — calling twice with the same company_id returns
    the existing record unchanged.
    """
    svc = DeviceSecurityService(db)
    company = await svc.initialise_company(
        company_id=payload.company_id,
        company_name=payload.company_name,
    )
    return ApiResponse(data=company, message="Company initialised")


@router.get("/company")
async def get_company(
    company_id: str = Query(...),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get company key metadata (public keys only to non-root users)."""
    svc = DeviceSecurityService(db)
    company = await svc.get_company(company_id)
    if not company:
        return ApiResponse(data=None, message="Company not found")
    return ApiResponse(data=company)


@router.get("/companies")
async def list_companies(
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all companies (summary view — no private keys)."""
    svc = DeviceSecurityService(db)
    companies = await svc.list_companies()
    return ApiResponse(data=companies, message=f"{len(companies)} companies")


@router.post("/company/rotate")
async def rotate_company_keys(
    payload: KeyRotatePayload,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Rotate company root + shop keys.  All device certs are revoked."""
    svc = DeviceSecurityService(db)
    try:
        company = await svc.rotate_keys(
            payload.company_id,
            actor_user_id=user.get("id"),
        )
    except ValueError as exc:
        return ApiResponse(data=None, message=str(exc))
    return ApiResponse(data=company, message="Keys rotated — all device certs revoked")


# ── Certificates ─────────────────────────────────────────────────


@router.post("/certs/issue")
async def issue_certificate(
    payload: CertIssuePayload,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Issue a signed certificate for a device (admin)."""
    svc = DeviceSecurityService(db)
    try:
        cert = await svc.issue_certificate(
            device_id=payload.device_id,
            company_id=payload.company_id,
            device_public_key=payload.device_public_key,
            issued_by=user.get("id"),
            validity_days=payload.validity_days,
        )
    except ValueError as exc:
        return ApiResponse(data=None, message=str(exc))
    return ApiResponse(data=cert, message="Certificate issued")


@router.post("/certs/verify")
async def verify_certificate(
    payload: CertVerifyPayload,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Verify a device certificate against the company root key.

    Used by devices during sync handshake to authenticate each other.
    """
    svc = DeviceSecurityService(db)
    result = await svc.verify_certificate(
        device_id=payload.device_id,
        company_id=payload.company_id,
        certificate_data=payload.certificate_data,
        signature=payload.signature,
    )
    msg = "Certificate valid" if result["valid"] else f"Invalid: {result.get('reason')}"
    return ApiResponse(data=result, message=msg)


@router.get("/certs/{device_id}")
async def get_device_cert(
    device_id: str,
    company_id: str = Query(...),
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Get the current active certificate for a device."""
    svc = DeviceSecurityService(db)
    cert = await svc.get_device_certificate(device_id, company_id)
    if not cert:
        return ApiResponse(data=None, message="No active certificate found")
    return ApiResponse(data=cert)


@router.post("/certs/revoke")
async def revoke_certificate(
    payload: CertRevokePayload,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Revoke a device's certificate.  Blocks the device from syncing."""
    svc = DeviceSecurityService(db)
    revoked = await svc.revoke_certificate(
        device_id=payload.device_id,
        company_id=payload.company_id,
        reason=payload.reason,
        actor_user_id=user.get("id"),
    )
    msg = "Certificate revoked" if revoked else "No active cert to revoke"
    return ApiResponse(data={"revoked": revoked}, message=msg)


# ── Shared Channels ──────────────────────────────────────────────


@router.post("/channels")
async def create_shared_channel(
    payload: SharedChannelCreatePayload,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a cross-company sharing channel (backbone for GC sharing)."""
    svc = DeviceSecurityService(db)
    channel = await svc.create_shared_channel(
        channel_name=payload.channel_name,
        owner_company_id=payload.owner_company_id,
        partner_company_ids=payload.partner_company_ids,
        scope=payload.scope,
        permissions=payload.permissions,
        expires_at=payload.expires_at,
        created_by=user.get("id"),
    )
    return ApiResponse(data=channel, message="Shared channel created")


@router.get("/channels")
async def list_shared_channels(
    company_id: str | None = Query(None),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List active shared channels, optionally filtered by company."""
    svc = DeviceSecurityService(db)
    channels = await svc.list_shared_channels(company_id)
    return ApiResponse(data=channels, message=f"{len(channels)} shared channels")


@router.post("/channels/{channel_id}/deactivate")
async def deactivate_shared_channel(
    channel_id: int,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Deactivate (soft-delete) a shared channel."""
    svc = DeviceSecurityService(db)
    deactivated = await svc.deactivate_shared_channel(channel_id, actor_user_id=user.get("id"))
    msg = "Channel deactivated" if deactivated else "Channel not found or already inactive"
    return ApiResponse(data={"deactivated": deactivated}, message=msg)


@router.post("/channels/{channel_id}/accept")
async def accept_channel_invitation(
    channel_id: int,
    company_id: str = Query(...),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Accept a pending channel invitation for a company."""
    svc = DeviceSecurityService(db)
    accepted = await svc.accept_channel_invitation(channel_id, company_id)
    msg = "Invitation accepted" if accepted else "No pending invitation found"
    return ApiResponse(data={"accepted": accepted}, message=msg)


# ── Bluetooth Handshake ──────────────────────────────────────────


@router.post("/bt/hello")
async def bt_create_hello(
    payload: BtHelloPayload,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Create a BT_HELLO payload for initiating a Bluetooth handshake.

    The device calls this before starting a BT sync session with a peer.
    Returns the hello payload to send to the other device.
    """
    svc = DeviceSecurityService(db)
    hello = await svc.bt_create_hello(
        device_id=payload.device_id,
        company_id=payload.company_id,
    )
    if not hello:
        return ApiResponse(data=None, message="No active certificate — device must pair first")
    return ApiResponse(data=hello, message="BT hello created")


@router.post("/bt/verify-hello")
async def bt_verify_hello(
    payload: BtVerifyHelloPayload,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Verify an incoming BT_HELLO from a peer and return a BT_HELLO_ACK.

    Called by the responder device when it receives a handshake initiation.
    """
    svc = DeviceSecurityService(db)
    result = await svc.bt_verify_hello(
        hello=payload.hello,
        responder_device_id=payload.responder_device_id,
        responder_company_id=payload.responder_company_id,
    )
    if result["valid"]:
        return ApiResponse(data=result["ack"], message="Handshake accepted — send ACK to peer")
    return ApiResponse(data={"valid": False, "reason": result.get("reason")},
                       message=f"Handshake rejected: {result.get('reason')}")


@router.post("/bt/verify-ack")
async def bt_verify_ack(
    payload: BtVerifyAckPayload,
    user: dict = Depends(require_user),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Verify a BT_HELLO_ACK from the responder — completing mutual authentication.

    Called by the initiator after receiving the responder's ACK.
    If valid, both devices have verified each other's certificates.
    """
    svc = DeviceSecurityService(db)
    result = await svc.bt_verify_ack(
        ack=payload.ack,
        initiator_device_id=payload.initiator_device_id,
        initiator_company_id=payload.initiator_company_id,
        original_nonce=payload.original_nonce,
    )
    if result["valid"]:
        return ApiResponse(data=result, message="Mutual trust established — sync can proceed")
    return ApiResponse(data={"valid": False, "reason": result.get("reason")},
                       message=f"ACK verification failed: {result.get('reason')}")


# ── Audit ────────────────────────────────────────────────────────


@router.get("/audit")
async def security_audit_log(
    event_type: str | None = Query(None),
    device_id: str | None = Query(None),
    company_id: str | None = Query(None),
    limit: int = Query(100, ge=1, le=500),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Immutable security audit log — pairing, cert, key events."""
    svc = DeviceSecurityService(db)
    events = await svc.get_audit_log(
        event_type=event_type,
        device_id=device_id,
        company_id=company_id,
        limit=limit,
    )
    return ApiResponse(data=events, message=f"{len(events)} audit events")
