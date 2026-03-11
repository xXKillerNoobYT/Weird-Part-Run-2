"""
File-Based Sync Service — USB / sneakernet sync fallback.

Provides:
1. Export sync package — gather changes → encrypt → compress → write to file
2. Import sync package — verify → decrypt → decompress → apply changes
3. Package lifecycle tracking in _file_sync_packages
4. AES-256-GCM encryption with passphrase-derived key
"""

from __future__ import annotations

import gzip
import hashlib
import json
import logging
import os
import secrets
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4

import aiosqlite

from app.config import settings

logger = logging.getLogger(__name__)

# backend/ root
_BACKEND_DIR = Path(__file__).resolve().parent.parent.parent
_FILE_SYNC_DIR = _BACKEND_DIR / "file_sync_packages"


def _derive_key(passphrase: str, salt: bytes) -> bytes:
    """Derive a 32-byte AES key from a passphrase via PBKDF2-SHA256."""
    return hashlib.pbkdf2_hmac("sha256", passphrase.encode(), salt, iterations=100_000)


class FileSyncService:
    """Handles file-based sync package export/import."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    # ══════════════════════════════════════════════════════════════
    # Export
    # ══════════════════════════════════════════════════════════════

    async def export_package(
        self,
        *,
        tables: list[str] | None = None,
        changes_since: str | None = None,
        passphrase: str | None = None,
        key_hint: str | None = None,
        created_by: int | None = None,
        expires_days: int = 30,
    ) -> dict:
        """Export a sync package to a file.

        If tables is None, exports all synced tables.
        If changes_since is provided, only exports changes after that timestamp (incremental).
        Otherwise does a full export.

        The package is a gzipped JSON file containing:
        {
            "package_id": "...",
            "exported_at": "...",
            "package_type": "full_export" | "incremental_export",
            "changes_since": "..." (if incremental),
            "tables": {
                "table_name": [rows...],
                ...
            },
            "record_count": N,
        }

        If passphrase is provided, the gzipped JSON is encrypted with AES-256-GCM
        and the file extension is .fsp.enc. Otherwise it's .fsp.gz.
        """
        package_id = str(uuid4())
        package_type = "incremental_export" if changes_since else "full_export"
        now = datetime.now(timezone.utc)

        # Gather data
        from app.services.sync_service import SYNCED_TABLES_ORDERED, SYNCED_TABLES
        export_tables = tables or list(SYNCED_TABLES_ORDERED)
        # Filter to only synced tables
        export_tables = [t for t in export_tables if t in SYNCED_TABLES]

        data: dict[str, list[dict]] = {}
        record_count = 0

        if changes_since:
            # Incremental: get changes from the change log
            cursor = await self.db.execute(
                """SELECT DISTINCT table_name, record_id, operation, changed_fields
                   FROM _shop_change_log
                   WHERE timestamp > ?
                   ORDER BY timestamp""",
                (changes_since,),
            )
            changes = await cursor.fetchall()
            # Group changes by table and fetch full records
            table_record_ids: dict[str, list[int]] = {}
            for ch in changes:
                ch_dict = dict(ch)
                tn = ch_dict["table_name"]
                if tn in SYNCED_TABLES and (not tables or tn in tables):
                    table_record_ids.setdefault(tn, []).append(ch_dict["record_id"])

            for tn, rids in table_record_ids.items():
                unique_ids = list(set(rids))
                placeholders = ",".join("?" for _ in unique_ids)
                cur2 = await self.db.execute(
                    f"SELECT * FROM {tn} WHERE id IN ({placeholders})", unique_ids,
                )
                rows = [dict(r) for r in await cur2.fetchall()]
                if rows:
                    data[tn] = rows
                    record_count += len(rows)
        else:
            # Full export: dump all rows from each table
            for tn in export_tables:
                try:
                    cur = await self.db.execute(f"SELECT * FROM {tn}")
                    rows = [dict(r) for r in await cur.fetchall()]
                    if rows:
                        data[tn] = rows
                        record_count += len(rows)
                except Exception as exc:
                    logger.warning("Skipping table %s in file sync export: %s", tn, exc)

        # Build the package payload
        payload = {
            "package_id": package_id,
            "exported_at": now.isoformat(),
            "package_type": package_type,
            "changes_since": changes_since,
            "changes_until": now.isoformat(),
            "tables": data,
            "table_names": list(data.keys()),
            "record_count": record_count,
        }

        # Serialize and compress
        payload_json = json.dumps(payload, default=str).encode("utf-8")
        compressed = gzip.compress(payload_json, compresslevel=6)

        # Determine encryption and file name
        encrypted = False
        encryption_method: str | None = None
        file_bytes = compressed

        if passphrase:
            try:
                from cryptography.hazmat.primitives.ciphers.aead import AESGCM
                salt = os.urandom(16)
                key = _derive_key(passphrase, salt)
                nonce = os.urandom(12)
                aesgcm = AESGCM(key)
                ciphertext = aesgcm.encrypt(nonce, compressed, None)
                # File format: [16-byte salt][12-byte nonce][ciphertext]
                file_bytes = salt + nonce + ciphertext
                encrypted = True
                encryption_method = "aes-256-gcm"
            except ImportError:
                logger.warning("cryptography not available — exporting unencrypted")

        # Write to file
        _FILE_SYNC_DIR.mkdir(parents=True, exist_ok=True)
        ext = ".fsp.enc" if encrypted else ".fsp.gz"
        file_name = f"sync-{package_id[:8]}-{now.strftime('%Y%m%d-%H%M%S')}{ext}"
        file_path = _FILE_SYNC_DIR / file_name

        file_path.write_bytes(file_bytes)
        file_size = len(file_bytes)

        # Expiry date
        expires_at = (now + timedelta(days=expires_days)).isoformat() if expires_days else None

        # Record in DB
        await self.db.execute(
            """INSERT INTO _file_sync_packages
               (package_id, package_type, direction, file_name, file_path,
                file_size_bytes, encryption_method, key_hint, tables_included,
                record_count, changes_since, changes_until, status, created_by, expires_at)
               VALUES (?, ?, 'export', ?, ?, ?, ?, ?, ?, ?, ?, ?, 'ready', ?, ?)""",
            (
                package_id, package_type, file_name, str(file_path),
                file_size, encryption_method, key_hint,
                json.dumps(list(data.keys())),
                record_count, changes_since, now.isoformat(),
                created_by, expires_at,
            ),
        )
        await self.db.commit()

        logger.info(
            "Exported file sync package %s: %d records across %d tables (%d bytes, encrypted=%s)",
            package_id[:8], record_count, len(data), file_size, encrypted,
        )

        return await self.get_package(package_id)

    # ══════════════════════════════════════════════════════════════
    # Import
    # ══════════════════════════════════════════════════════════════

    async def import_package(
        self,
        *,
        file_path: str,
        passphrase: str | None = None,
        imported_by: int | None = None,
    ) -> dict:
        """Import a sync package from a file.

        Reads the file, decrypts if needed, decompresses, and applies changes.
        """
        path = Path(file_path)
        if not path.exists():
            return {"error": "file_not_found", "file_path": file_path}

        file_bytes = path.read_bytes()
        file_size = len(file_bytes)

        # Decrypt if encrypted (.enc extension)
        if path.suffix == ".enc" or (passphrase and len(file_bytes) > 28):
            if not passphrase:
                return {"error": "passphrase_required"}
            try:
                from cryptography.hazmat.primitives.ciphers.aead import AESGCM
                salt = file_bytes[:16]
                nonce = file_bytes[16:28]
                ciphertext = file_bytes[28:]
                key = _derive_key(passphrase, salt)
                aesgcm = AESGCM(key)
                compressed = aesgcm.decrypt(nonce, ciphertext, None)
            except ImportError:
                return {"error": "cryptography_not_available"}
            except Exception as exc:
                return {"error": "decryption_failed", "detail": str(exc)}
        else:
            compressed = file_bytes

        # Decompress
        try:
            payload_json = gzip.decompress(compressed)
        except Exception as exc:
            return {"error": "decompression_failed", "detail": str(exc)}

        # Parse
        try:
            payload = json.loads(payload_json.decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            return {"error": "invalid_payload", "detail": str(exc)}

        package_id = payload.get("package_id", str(uuid4()))
        tables: dict[str, list[dict]] = payload.get("tables", {})
        record_count = payload.get("record_count", 0)

        # Record the import in DB
        await self.db.execute(
            """INSERT INTO _file_sync_packages
               (package_id, package_type, direction, file_name, file_path,
                file_size_bytes, tables_included, record_count,
                changes_since, changes_until, status, applied_by)
               VALUES (?, 'import', 'import', ?, ?, ?, ?, ?, ?, ?, 'importing', ?)""",
            (
                package_id, path.name, file_path,
                file_size,
                json.dumps(payload.get("table_names", list(tables.keys()))),
                record_count,
                payload.get("changes_since"),
                payload.get("changes_until"),
                imported_by,
            ),
        )
        await self.db.commit()

        # Apply the data — use SyncService patterns (insert/upsert)
        applied_count = 0
        errors: list[str] = []

        from app.services.sync_service import SYNCED_TABLES

        for table_name, rows in tables.items():
            if table_name not in SYNCED_TABLES:
                errors.append(f"Skipped non-synced table: {table_name}")
                continue

            for row in rows:
                try:
                    record_id = row.get("id")
                    if record_id is None:
                        continue

                    # Check if record exists
                    cur = await self.db.execute(
                        f"SELECT id FROM {table_name} WHERE id = ?", (record_id,),
                    )
                    existing = await cur.fetchone()

                    if existing:
                        # Update
                        update_fields = {k: v for k, v in row.items() if k != "id"}
                        if update_fields:
                            set_parts = [f"{k} = ?" for k in update_fields]
                            values = list(update_fields.values()) + [record_id]
                            await self.db.execute(
                                f"UPDATE {table_name} SET {', '.join(set_parts)} WHERE id = ?",
                                values,
                            )
                    else:
                        # Insert
                        keys = list(row.keys())
                        placeholders = ", ".join("?" for _ in keys)
                        values = [row[k] for k in keys]
                        await self.db.execute(
                            f"INSERT INTO {table_name} ({', '.join(keys)}) VALUES ({placeholders})",
                            values,
                        )
                    applied_count += 1
                except Exception as exc:
                    errors.append(f"{table_name}[{row.get('id')}]: {exc}")

        await self.db.commit()

        # Update package status
        status = "applied" if not errors else "applied"  # partial = still applied
        await self.db.execute(
            """UPDATE _file_sync_packages
               SET status = ?, applied_at = datetime('now'),
                   applied_by = ?, error_message = ?
               WHERE package_id = ?""",
            (
                status,
                imported_by,
                json.dumps(errors) if errors else None,
                package_id,
            ),
        )
        await self.db.commit()

        logger.info(
            "Imported file sync package %s: %d/%d records applied, %d errors",
            package_id[:8], applied_count, record_count, len(errors),
        )

        result = await self.get_package(package_id)
        result["applied_count"] = applied_count
        result["errors"] = errors
        return result

    # ══════════════════════════════════════════════════════════════
    # Package Management
    # ══════════════════════════════════════════════════════════════

    async def get_package(self, package_id: str) -> dict:
        """Get a single file sync package record."""
        cursor = await self.db.execute(
            "SELECT * FROM _file_sync_packages WHERE package_id = ?", (package_id,),
        )
        row = await cursor.fetchone()
        if not row:
            return {}
        pkg = dict(row)
        pkg["tables_included"] = json.loads(pkg.get("tables_included") or "[]")
        return pkg

    async def list_packages(
        self,
        *,
        direction: str | None = None,
        status: str | None = None,
        limit: int = 50,
    ) -> list[dict]:
        """List file sync packages."""
        sql = "SELECT * FROM _file_sync_packages WHERE 1=1"
        params: list[Any] = []
        if direction:
            sql += " AND direction = ?"
            params.append(direction)
        if status:
            sql += " AND status = ?"
            params.append(status)
        sql += " ORDER BY created_at DESC LIMIT ?"
        params.append(limit)
        cursor = await self.db.execute(sql, tuple(params))
        rows = await cursor.fetchall()
        results = []
        for r in rows:
            pkg = dict(r)
            pkg["tables_included"] = json.loads(pkg.get("tables_included") or "[]")
            results.append(pkg)
        return results

    async def cleanup_expired_packages(self) -> int:
        """Delete expired file sync packages from disk and DB.

        Returns the number of packages cleaned up.
        """
        cursor = await self.db.execute(
            """SELECT * FROM _file_sync_packages
               WHERE expires_at IS NOT NULL AND expires_at < datetime('now')
                 AND status NOT IN ('importing', 'exporting')""",
        )
        expired = await cursor.fetchall()
        cleaned = 0

        for row in expired:
            pkg = dict(row)
            fp = pkg.get("file_path")
            if fp:
                try:
                    p = Path(fp)
                    if p.exists():
                        p.unlink()
                except Exception as exc:
                    logger.warning("Failed to delete expired package file %s: %s", fp, exc)

            await self.db.execute(
                "UPDATE _file_sync_packages SET status = 'expired' WHERE package_id = ?",
                (pkg["package_id"],),
            )
            cleaned += 1

        if cleaned:
            await self.db.commit()
            logger.info("Cleaned up %d expired file sync packages", cleaned)
        return cleaned
