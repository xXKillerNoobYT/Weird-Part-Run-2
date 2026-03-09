"""
Backup service — database and application backup management.

Supports two independent backup types:
  - Database (db): Hot-copy via sqlite3.backup() — safe with WAL mode
  - Application (app): Zip archive of backend/ code (excluding venv, pycache, backups)

Settings are persisted via the generic key-value settings API under
category "backup". Retention cleanup deletes old backups beyond the
configured count.
"""

from __future__ import annotations

import logging
import os
import shutil
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Any

import aiosqlite

from app.config import settings
from app.repositories.settings_repo import SettingsRepo

logger = logging.getLogger(__name__)

# Resolved once — backend/ directory (services/ → app/ → backend/)
_BACKEND_DIR = Path(__file__).resolve().parent.parent.parent


# ── Default settings ──────────────────────────────────────────────

_DEFAULTS: dict[str, str] = {
    "backup_db_enabled": "true",
    "backup_db_hour": "2",
    "backup_db_minute": "0",
    "backup_db_retention": "7",
    "backup_app_enabled": "false",
    "backup_app_hour": "3",
    "backup_app_minute": "0",
    "backup_app_retention": "3",
    "backup_dir": "",
    "backup_before_update": "true",
}


class BackupService:
    """Handles database and application backup lifecycle."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self._settings_repo = SettingsRepo(db)

    # ── Settings ──────────────────────────────────────────────────

    async def get_settings(self) -> dict[str, Any]:
        """Read backup settings, falling back to defaults for unset keys."""
        stored = await self._settings_repo.get_by_category("backup")
        result: dict[str, Any] = {}
        for key, default in _DEFAULTS.items():
            raw = stored.get(key, default)
            # Convert "true"/"false" → bool, numeric strings → int
            if raw in ("true", "false", True, False):
                result[key] = raw in ("true", True)
            else:
                try:
                    result[key] = int(raw)
                except (ValueError, TypeError):
                    result[key] = str(raw) if raw is not None else default
        return result

    async def update_settings(self, updates: dict[str, Any]) -> dict[str, Any]:
        """Persist backup setting changes. Returns the full merged settings."""
        for key, value in updates.items():
            full_key = key if key.startswith("backup_") else f"backup_{key}"
            if full_key in _DEFAULTS:
                await self._settings_repo.set_value(
                    full_key, str(value).lower() if isinstance(value, bool) else str(value),
                    category="backup",
                )
        return await self.get_settings()

    def _resolve_backup_dir(self, backup_dir_setting: str = "") -> Path:
        """Resolve the backup directory path.

        Empty string → default location at backend/backups/.
        Relative paths resolve from backend/.
        Absolute paths used as-is.
        """
        if not backup_dir_setting:
            return _BACKEND_DIR / "backups"
        p = Path(backup_dir_setting)
        return p if p.is_absolute() else (_BACKEND_DIR / p).resolve()

    # ── Database Backup ───────────────────────────────────────────

    async def run_db_backup(self) -> dict[str, Any]:
        """Create a hot-copy backup of the SQLite database.

        Uses sqlite3.backup() which safely handles WAL mode —
        the backup is a consistent snapshot even while the app is running.
        """
        cfg = await self.get_settings()
        backup_root = self._resolve_backup_dir(cfg.get("backup_dir", ""))
        db_dir = backup_root / "db"
        db_dir.mkdir(parents=True, exist_ok=True)

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"wiredpart_{timestamp}.db"
        dest_path = db_dir / filename

        # sqlite3.backup() requires synchronous connections
        src_path = str(settings.db_path)
        src_conn = sqlite3.connect(src_path)
        dst_conn = sqlite3.connect(str(dest_path))

        try:
            src_conn.backup(dst_conn)
            dst_conn.close()
            src_conn.close()
        except Exception:
            dst_conn.close()
            src_conn.close()
            # Clean up partial file
            if dest_path.exists():
                dest_path.unlink()
            raise

        size_bytes = dest_path.stat().st_size

        # Record in tracking table
        await self.db.execute(
            """
            INSERT INTO _backups (backup_type, file_path, file_name, size_bytes)
            VALUES ('db', ?, ?, ?)
            """,
            (str(dest_path), filename, size_bytes),
        )
        await self.db.commit()

        logger.info("DB backup created: %s (%d bytes)", filename, size_bytes)

        return {
            "backup_type": "db",
            "file_name": filename,
            "file_path": str(dest_path),
            "size_bytes": size_bytes,
        }

    # ── App Backup ────────────────────────────────────────────────

    async def run_app_backup(self) -> dict[str, Any]:
        """Create a zip archive of the backend application code.

        Excludes virtual environments, caches, logs, and existing backups.
        """
        cfg = await self.get_settings()
        backup_root = self._resolve_backup_dir(cfg.get("backup_dir", ""))
        app_dir = backup_root / "app"
        app_dir.mkdir(parents=True, exist_ok=True)

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        archive_name = f"app_{timestamp}"
        dest_base = app_dir / archive_name

        # Create zip archive of backend/ excluding noise
        def _filter(path: str, names: list[str]) -> set[str]:
            """Return names to exclude from copytree/archive."""
            excluded = set()
            for name in names:
                if name in (
                    ".venv", "venv", "__pycache__", ".git", "node_modules",
                    "backups", "logs", ".pytest_cache", ".mypy_cache",
                ):
                    excluded.add(name)
                if name.endswith((".pyc", ".pyo")):
                    excluded.add(name)
            return excluded

        # shutil.make_archive doesn't support ignore, so use copytree → archive
        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            staging = Path(tmpdir) / "backend"
            shutil.copytree(str(_BACKEND_DIR), str(staging), ignore=_filter)
            archive_path = shutil.make_archive(str(dest_base), "zip", str(tmpdir))

        size_bytes = Path(archive_path).stat().st_size
        filename = Path(archive_path).name

        # Record in tracking table
        await self.db.execute(
            """
            INSERT INTO _backups (backup_type, file_path, file_name, size_bytes)
            VALUES ('app', ?, ?, ?)
            """,
            (str(archive_path), filename, size_bytes),
        )
        await self.db.commit()

        logger.info("App backup created: %s (%d bytes)", filename, size_bytes)

        return {
            "backup_type": "app",
            "file_name": filename,
            "file_path": str(archive_path),
            "size_bytes": size_bytes,
        }

    # ── List / Delete ─────────────────────────────────────────────

    async def list_backups(self, backup_type: str) -> list[dict[str, Any]]:
        """List all backups of a given type, newest first."""
        cursor = await self.db.execute(
            """
            SELECT id, backup_type, file_path, file_name, size_bytes, created_at
            FROM _backups
            WHERE backup_type = ?
            ORDER BY created_at DESC
            """,
            (backup_type,),
        )
        return await cursor.fetchall()

    async def delete_backup(self, backup_id: int) -> bool:
        """Delete a backup record and its file from disk."""
        cursor = await self.db.execute(
            "SELECT file_path FROM _backups WHERE id = ?",
            (backup_id,),
        )
        row = await cursor.fetchone()
        if not row:
            return False

        # Remove file from disk
        file_path = Path(row["file_path"])
        if file_path.exists():
            file_path.unlink()
            logger.info("Deleted backup file: %s", file_path)

        # Remove from tracking table
        await self.db.execute("DELETE FROM _backups WHERE id = ?", (backup_id,))
        await self.db.commit()
        return True

    # ── Restore ───────────────────────────────────────────────────

    async def restore_db_backup(self, backup_id: int) -> dict[str, Any]:
        """Restore a database backup.

        Safety: Creates a pre-restore backup first so we can roll back.
        The actual restore replaces the database file — a server restart
        is required to pick up the restored database.

        Also cleans up WAL and SHM journal files to prevent stale journal
        data from corrupting the restored database on restart.
        """
        cursor = await self.db.execute(
            "SELECT file_path, file_name FROM _backups WHERE id = ? AND backup_type = 'db'",
            (backup_id,),
        )
        row = await cursor.fetchone()
        if not row:
            raise ValueError(f"DB backup #{backup_id} not found")

        backup_path = Path(row["file_path"])
        if not backup_path.exists():
            raise FileNotFoundError(f"Backup file missing: {backup_path}")

        # Create a safety backup before restore
        logger.info("Creating pre-restore safety backup...")
        safety = await self.run_db_backup()

        # Copy backup over current database
        db_path = Path(settings.db_path)
        logger.info("Restoring DB from %s → %s", backup_path, db_path)

        # Copy the backup into place — the current connection still uses
        # the old file until the server restarts.
        shutil.copy2(str(backup_path), str(db_path))

        # Clean up WAL and SHM journal files. These are stale after a
        # restore and would corrupt the database if SQLite tried to
        # replay them on the next open.
        for suffix in ("-wal", "-shm"):
            journal = db_path.with_name(db_path.name + suffix)
            if journal.exists():
                journal.unlink()
                logger.info("Removed stale journal file: %s", journal)

        return {
            "restored_from": row["file_name"],
            "safety_backup": safety["file_name"],
            "message": "Database restored. Restart the server to apply changes.",
        }

    # ── Retention Cleanup ─────────────────────────────────────────

    async def cleanup_old_backups(self, backup_type: str, retention: int | None = None) -> int:
        """Delete backups beyond the retention count for a given type.

        Keeps the N most recent backups, deletes the rest.
        Returns the number of backups deleted.
        """
        if retention is None:
            cfg = await self.get_settings()
            key = f"backup_{backup_type}_retention"
            retention = cfg.get(key, 7)

        cursor = await self.db.execute(
            """
            SELECT id, file_path FROM _backups
            WHERE backup_type = ?
            ORDER BY created_at DESC
            """,
            (backup_type,),
        )
        all_rows = await cursor.fetchall()

        if len(all_rows) <= retention:
            return 0

        to_delete = all_rows[retention:]
        count = 0
        for row in to_delete:
            file_path = Path(row["file_path"])
            if file_path.exists():
                file_path.unlink()
            await self.db.execute("DELETE FROM _backups WHERE id = ?", (row["id"],))
            count += 1

        await self.db.commit()
        if count > 0:
            logger.info(
                "Retention cleanup: deleted %d old '%s' backups (keeping %d)",
                count, backup_type, retention,
            )
        return count
