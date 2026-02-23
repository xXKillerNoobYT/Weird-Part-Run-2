"""
SQLite database connection manager and migration runner.

Handles:
- Async connection pool via aiosqlite
- WAL mode for concurrent reads
- Numbered migration files (001_xxx.sql, 002_xxx.sql, ...)
- Migration tracking (which have been applied)
- Row factory for dict-like access

Usage:
    from app.database import get_db, init_db

    # In FastAPI startup:
    await init_db()

    # In route handlers:
    async def my_route(db = Depends(get_db)):
        row = await db.execute("SELECT * FROM users WHERE id = ?", (1,))
"""

from __future__ import annotations

import logging
import sqlite3
from pathlib import Path
from typing import AsyncGenerator

import aiosqlite

from app.config import settings

logger = logging.getLogger(__name__)

# ── Connection Pool ───────────────────────────────────────────────
# We use a module-level connection for simplicity in local SQLite.
# For multi-worker deployments, each worker gets its own connection.
_db_path: str = settings.DATABASE_PATH


def _dict_row_factory(cursor: sqlite3.Cursor, row: tuple) -> dict:
    """Row factory that returns dicts instead of tuples.

    Allows accessing columns by name: row["id"], row["display_name"], etc.
    """
    columns = [col[0] for col in cursor.description]
    return dict(zip(columns, row))


async def get_connection() -> aiosqlite.Connection:
    """Create a new database connection with our standard configuration."""
    db = await aiosqlite.connect(_db_path)
    db.row_factory = _dict_row_factory

    # Enable WAL mode for better concurrent read performance
    await db.execute("PRAGMA journal_mode = WAL")
    # Enforce foreign key constraints
    await db.execute("PRAGMA foreign_keys = ON")
    # Improve write performance (slightly less durable, fine for local app)
    await db.execute("PRAGMA synchronous = NORMAL")

    return db


async def get_db() -> AsyncGenerator[aiosqlite.Connection, None]:
    """FastAPI dependency that provides a database connection.

    Usage in routes:
        @router.get("/items")
        async def list_items(db = Depends(get_db)):
            cursor = await db.execute("SELECT * FROM items")
            return await cursor.fetchall()
    """
    db = await get_connection()
    try:
        yield db
    finally:
        await db.close()


# ── Migration Runner ──────────────────────────────────────────────

async def init_db() -> None:
    """Initialize the database: create migration tracking table and run pending migrations.

    Called once at application startup. Safe to call multiple times —
    already-applied migrations are skipped.
    """
    db = await get_connection()
    try:
        # Create migration tracking table if it doesn't exist
        await db.execute("""
            CREATE TABLE IF NOT EXISTS _migrations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                filename TEXT NOT NULL UNIQUE,
                applied_at TEXT DEFAULT (datetime('now'))
            )
        """)
        await db.commit()

        # Find and run pending migrations
        migrations_dir = settings.migrations_dir
        if not migrations_dir.exists():
            logger.warning("Migrations directory not found: %s", migrations_dir)
            return

        # Get already-applied migrations
        cursor = await db.execute("SELECT filename FROM _migrations")
        applied = {row["filename"] for row in await cursor.fetchall()}

        # Get all migration SQL files, sorted by number prefix
        migration_files = sorted(
            migrations_dir.glob("*.sql"),
            key=lambda f: f.name,
        )

        for migration_file in migration_files:
            if migration_file.name in applied:
                logger.debug("Migration already applied: %s", migration_file.name)
                continue

            logger.info("Applying migration: %s", migration_file.name)
            sql = migration_file.read_text(encoding="utf-8")

            try:
                await db.executescript(sql)
                await db.execute(
                    "INSERT INTO _migrations (filename) VALUES (?)",
                    (migration_file.name,),
                )
                await db.commit()
                logger.info("Migration applied successfully: %s", migration_file.name)
            except Exception as e:
                logger.error("Migration failed: %s — %s", migration_file.name, e)
                raise

        logger.info(
            "Database initialized. %d migrations applied, %d already up-to-date.",
            len(migration_files) - len(applied),
            len(applied),
        )
    finally:
        await db.close()


async def reset_db() -> None:
    """Drop all tables and re-run migrations. FOR TESTING ONLY.

    This is destructive — it deletes all data.
    """
    import os

    db_path = Path(_db_path)
    if db_path.exists():
        os.remove(db_path)
        # Also remove WAL and SHM files if they exist
        for suffix in ("-wal", "-shm", "-journal"):
            wal_path = db_path.with_suffix(db_path.suffix + suffix)
            if wal_path.exists():
                os.remove(wal_path)

    await init_db()
