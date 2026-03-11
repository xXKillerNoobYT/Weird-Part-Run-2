"""Bootstrap router for App-Store shell pairing and program handoff."""

from __future__ import annotations

import aiosqlite
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.database import get_db
from app.middleware.auth import require_permission
from app.models.common import ApiResponse
from app.services.bootstrap_service import BootstrapService

router = APIRouter(prefix="/api/bootstrap", tags=["Bootstrap"])


class PairingCodeCreatePayload(BaseModel):
    ttl_minutes: int = Field(15, ge=1, le=120)
    notes: str | None = None


class HandshakePayload(BaseModel):
    pairing_code: str
    device_id: str
    device_name: str = "Bootstrap Device"
    platform: str = Field(..., pattern="^(ios|android|windows|macos)$")
    bootstrap_version: str = "0.0.0-bootstrap"
    public_key: str | None = None


class BootstrapArtifactUpsertPayload(BaseModel):
    platform: str = Field(..., pattern="^(ios|android|windows|macos)$")
    version: str
    manifest: dict = Field(default_factory=dict)
    download_url: str
    checksum_sha256: str
    signature: str | None = None
    min_bootstrap_version: str = "0.0.0-bootstrap"


class InstallEventPayload(BaseModel):
    pairing_code: str
    device_id: str
    platform: str = Field(..., pattern="^(ios|android|windows|macos)$")
    artifact_id: int | None = None
    status: str = Field(..., pattern="^(requested|downloading|downloaded|verifying|verified|installing|installed|failed)$")
    error_message: str | None = None
    metadata: dict = Field(default_factory=dict)
    progress_pct: float = 0
    bytes_downloaded: int = 0
    bytes_total: int = 0
    checksum_computed: str | None = None
    checksum_verified: bool = False
    signature_verified: bool | None = None


class ArtifactVerifyPayload(BaseModel):
    """Device submits computed SHA-256 checksum for server-side verification."""
    artifact_id: int
    client_checksum_sha256: str


@router.post("/pairing-codes")
async def create_pairing_code(
    payload: PairingCodeCreatePayload,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    svc = BootstrapService(db)
    row = await svc.create_pairing_code(
        created_by=user.get("id"),
        ttl_minutes=payload.ttl_minutes,
        notes=payload.notes,
    )
    return ApiResponse(data=row, message="Pairing code created")


@router.get("/pairing-codes")
async def list_pairing_codes(
    limit: int = Query(100, ge=1, le=500),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    svc = BootstrapService(db)
    rows = await svc.list_pairing_codes(limit=limit)
    return ApiResponse(data=rows, message=f"{len(rows)} pairing codes")


@router.post("/handshake")
async def bootstrap_handshake(
    payload: HandshakePayload,
    db: aiosqlite.Connection = Depends(get_db),
):
    svc = BootstrapService(db)
    try:
        result = await svc.bootstrap_handshake(
            pairing_code=payload.pairing_code,
            device_id=payload.device_id,
            device_name=payload.device_name,
            platform=payload.platform,
            bootstrap_version=payload.bootstrap_version,
            public_key=payload.public_key,
        )
        return ApiResponse(data=result, message="Bootstrap handshake complete")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/artifacts")
async def upsert_bootstrap_artifact(
    payload: BootstrapArtifactUpsertPayload,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    svc = BootstrapService(db)
    artifact = await svc.upsert_artifact(
        platform=payload.platform,
        version=payload.version,
        manifest=payload.manifest,
        download_url=payload.download_url,
        checksum_sha256=payload.checksum_sha256,
        signature=payload.signature,
        min_bootstrap_version=payload.min_bootstrap_version,
        created_by=user.get("id"),
    )
    return ApiResponse(data=artifact, message="Bootstrap artifact activated")


@router.get("/artifacts")
async def list_bootstrap_artifacts(
    platform: str | None = Query(None),
    limit: int = Query(50, ge=1, le=200),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    svc = BootstrapService(db)
    rows = await svc.list_artifacts(platform=platform, limit=limit)
    return ApiResponse(data=rows, message=f"{len(rows)} artifacts")


@router.post("/install-events")
async def log_bootstrap_install_event(
    payload: InstallEventPayload,
    db: aiosqlite.Connection = Depends(get_db),
):
    svc = BootstrapService(db)
    code = await svc.validate_pairing_code(payload.pairing_code)
    if not code and payload.status not in ("installed", "failed", "verified"):
        # allow late success/failure/verified events after code consumed
        # still restrict non-final spam if no valid code exists
        raise HTTPException(status_code=400, detail="Invalid pairing code for install event")

    row = await svc.log_install_event(
        device_id=payload.device_id,
        platform=payload.platform,
        artifact_id=payload.artifact_id,
        status=payload.status,
        error_message=payload.error_message,
        metadata=payload.metadata,
        progress_pct=payload.progress_pct,
        bytes_downloaded=payload.bytes_downloaded,
        bytes_total=payload.bytes_total,
        checksum_computed=payload.checksum_computed,
        checksum_verified=payload.checksum_verified,
        signature_verified=payload.signature_verified,
    )
    return ApiResponse(data=row, message="Install event logged")


@router.get("/install-events")
async def list_bootstrap_install_events(
    device_id: str | None = Query(None),
    limit: int = Query(100, ge=1, le=500),
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    svc = BootstrapService(db)
    rows = await svc.list_install_events(device_id=device_id, limit=limit)
    return ApiResponse(data=rows, message=f"{len(rows)} install events")


# ── Artifact Verification & Signing ─────────────────────────────


@router.post("/artifacts/verify")
async def verify_artifact(
    payload: ArtifactVerifyPayload,
    db: aiosqlite.Connection = Depends(get_db),
):
    """Device verifies a downloaded artifact against registered checksum.

    No auth required — devices call this during bootstrap install
    before they have session credentials. The artifact_id and checksum
    provide sufficient proof-of-download.
    """
    svc = BootstrapService(db)
    result = await svc.verify_artifact(
        artifact_id=payload.artifact_id,
        client_checksum_sha256=payload.client_checksum_sha256,
    )
    return ApiResponse(data=result, message=result["detail"])


@router.get("/artifacts/active/{platform}")
async def get_active_artifact(
    platform: str,
    db: aiosqlite.Connection = Depends(get_db),
):
    """Fetch the currently active artifact for a platform.

    No auth required — bootstrap devices need to check latest version
    without credentials.
    """
    svc = BootstrapService(db)
    artifact = await svc.get_active_artifact(platform)
    if not artifact:
        raise HTTPException(status_code=404, detail=f"No active artifact for platform '{platform}'")
    return ApiResponse(data=artifact, message="Active artifact")


@router.post("/artifacts/{artifact_id}/sign")
async def sign_artifact(
    artifact_id: int,
    user: dict = Depends(require_permission("manage_people")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Sign an artifact with the shop's Ed25519 key for tamper-proof verification.

    Admin-only. Signs: "{platform}:{version}:{checksum_sha256}".
    """
    svc = BootstrapService(db)
    try:
        artifact = await svc.sign_artifact(artifact_id=artifact_id)
        return ApiResponse(data=artifact, message="Artifact signed")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
