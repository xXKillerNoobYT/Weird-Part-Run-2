"""
Backup management routes — database & app backups.

Endpoints:
  GET    /api/backups/settings              → Get backup settings
  PUT    /api/backups/settings              → Update settings + reschedule
  GET    /api/backups/list/{backup_type}    → List backups (db or app)
  POST   /api/backups/run/{backup_type}     → Trigger manual backup
  POST   /api/backups/restore/{backup_id}   → Restore a DB backup
  GET    /api/backups/download/{backup_id}  → Download a backup file
  DELETE /api/backups/{backup_id}           → Delete a backup
  POST   /api/backups/cleanup/{backup_type} → Run retention cleanup
"""

from __future__ import annotations

import logging
from pathlib import Path as FilePath

from fastapi import APIRouter, Depends, Path
from fastapi.responses import FileResponse

import aiosqlite

from app.database import get_db
from app.middleware.auth import require_permission
from app.models.backup import BackupSettingsUpdate
from app.models.common import ApiResponse
from app.services.backup_service import BackupService

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/backups", tags=["Backups"])


# ── Settings ──────────────────────────────────────────────────────


@router.get("/settings", response_model=ApiResponse[dict])
async def get_backup_settings(
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Return current backup configuration."""
    svc = BackupService(db)
    cfg = await svc.get_settings()
    return ApiResponse(data=cfg)


@router.put("/settings", response_model=ApiResponse[dict])
async def update_backup_settings(
    payload: BackupSettingsUpdate,
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Update backup settings and reschedule backup jobs.

    Only provided fields are updated; omitted fields keep their
    current values.
    """
    updates = {k: v for k, v in payload.model_dump().items() if v is not None}
    svc = BackupService(db)
    cfg = await svc.update_settings(updates)

    # Reschedule the backup cron jobs to match new settings
    try:
        from app.scheduler import reschedule_backup_jobs
        reschedule_backup_jobs(cfg)
    except Exception:
        logger.exception("Failed to reschedule backup jobs")

    return ApiResponse(data=cfg, message="Backup settings updated")


# ── List ──────────────────────────────────────────────────────────


@router.get("/list/{backup_type}", response_model=ApiResponse[list])
async def list_backups(
    backup_type: str = Path(..., pattern="^(db|app)$"),
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """List all backups of a given type (db or app), newest first."""
    svc = BackupService(db)
    backups = await svc.list_backups(backup_type)
    return ApiResponse(data=backups, message=f"{len(backups)} {backup_type} backups")


# ── Manual Trigger ────────────────────────────────────────────────


@router.post("/run/{backup_type}", response_model=ApiResponse[dict])
async def run_backup(
    backup_type: str = Path(..., pattern="^(db|app)$"),
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Trigger an immediate manual backup."""
    svc = BackupService(db)
    try:
        if backup_type == "db":
            result = await svc.run_db_backup()
        else:
            result = await svc.run_app_backup()
        return ApiResponse(data=result, message=f"{backup_type.upper()} backup complete")
    except Exception as exc:
        logger.exception("Manual %s backup failed", backup_type)
        return ApiResponse(success=False, error=str(exc))


# ── Restore ───────────────────────────────────────────────────────


@router.post("/restore/{backup_id}", response_model=ApiResponse[dict])
async def restore_backup(
    backup_id: int,
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Restore a database backup. Creates a safety backup first.

    After restore, the server must be restarted to use the restored database.
    """
    svc = BackupService(db)
    try:
        result = await svc.restore_db_backup(backup_id)
        return ApiResponse(data=result, message="Database restored — restart server to apply")
    except (ValueError, FileNotFoundError) as exc:
        return ApiResponse(success=False, error=str(exc))
    except Exception as exc:
        logger.exception("Restore failed for backup #%d", backup_id)
        return ApiResponse(success=False, error=str(exc))


# ── Download ─────────────────────────────────────────────────────


@router.get("/download/{backup_id}")
async def download_backup(
    backup_id: int,
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Download a backup file directly.

    Returns the file as a download attachment. Useful for off-site storage
    or manual restore on another machine.
    """
    cursor = await db.execute(
        "SELECT file_path, file_name, backup_type FROM _backups WHERE id = ?",
        (backup_id,),
    )
    row = await cursor.fetchone()
    if not row:
        return ApiResponse(success=False, error="Backup not found")

    file_path = FilePath(row["file_path"])
    if not file_path.exists():
        return ApiResponse(success=False, error="Backup file missing from disk")

    # Determine media type from backup type
    media_type = (
        "application/x-sqlite3" if row["backup_type"] == "db"
        else "application/zip"
    )

    return FileResponse(
        path=str(file_path),
        filename=row["file_name"],
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{row["file_name"]}"'},
    )


# ── Delete ────────────────────────────────────────────────────────


@router.delete("/{backup_id}", response_model=ApiResponse[dict])
async def delete_backup(
    backup_id: int,
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Delete a single backup (file + DB record)."""
    svc = BackupService(db)
    deleted = await svc.delete_backup(backup_id)
    if deleted:
        return ApiResponse(data={"deleted": True}, message="Backup deleted")
    return ApiResponse(success=False, error="Backup not found")


# ── Cleanup ───────────────────────────────────────────────────────


@router.post("/cleanup/{backup_type}", response_model=ApiResponse[dict])
async def cleanup_backups(
    backup_type: str = Path(..., pattern="^(db|app)$"),
    user: dict = Depends(require_permission("manage_settings")),
    db: aiosqlite.Connection = Depends(get_db),
):
    """Run retention cleanup now — delete backups beyond retention count."""
    svc = BackupService(db)
    count = await svc.cleanup_old_backups(backup_type)
    return ApiResponse(
        data={"deleted_count": count},
        message=f"Cleaned up {count} old {backup_type} backups",
    )
