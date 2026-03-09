"""
Backup-related Pydantic models.

Covers backup records, settings, and API request/response shapes.
"""

from __future__ import annotations

from pydantic import BaseModel, Field


class BackupRecord(BaseModel):
    """A single backup entry stored in the _backups table."""
    id: int
    backup_type: str               # "db" or "app"
    file_path: str
    file_name: str
    size_bytes: int | None = None
    created_at: str | None = None


class BackupSettings(BaseModel):
    """User-configurable backup settings (stored as key-value pairs)."""
    db_enabled: bool = True
    db_hour: int = Field(default=2, ge=0, le=23)
    db_minute: int = Field(default=0, ge=0, le=59)
    db_retention: int = Field(default=7, ge=1, le=90)

    app_enabled: bool = False
    app_hour: int = Field(default=3, ge=0, le=23)
    app_minute: int = Field(default=0, ge=0, le=59)
    app_retention: int = Field(default=3, ge=1, le=30)

    backup_dir: str = ""  # empty = default (backend/backups/)
    backup_before_update: bool = True  # auto-backup before applying updates


class BackupSettingsUpdate(BaseModel):
    """Request to update backup settings."""
    db_enabled: bool | None = None
    db_hour: int | None = Field(default=None, ge=0, le=23)
    db_minute: int | None = Field(default=None, ge=0, le=59)
    db_retention: int | None = Field(default=None, ge=1, le=90)

    app_enabled: bool | None = None
    app_hour: int | None = Field(default=None, ge=0, le=23)
    app_minute: int | None = Field(default=None, ge=0, le=59)
    app_retention: int | None = Field(default=None, ge=1, le=30)

    backup_dir: str | None = None
    backup_before_update: bool | None = None
