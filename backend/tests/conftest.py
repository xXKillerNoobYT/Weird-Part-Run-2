"""
Test configuration and shared fixtures.

Provides:
- In-memory SQLite database with all migrations applied
- FastAPI test client (httpx AsyncClient)
- Pre-seeded admin user for auth tests
- Helpers for creating test JWTs
"""

from __future__ import annotations

import asyncio
from typing import AsyncGenerator

import pytest
import pytest_asyncio
import aiosqlite
from httpx import ASGITransport, AsyncClient

from app.config import settings
from app.database import _dict_row_factory, _split_sql_statements


# ── Event loop fixture ──────────────────────────────────────────────
@pytest.fixture(scope="session")
def event_loop():
    """Use a single event loop for the entire test session."""
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


# ── In-memory database ─────────────────────────────────────────────
@pytest_asyncio.fixture
async def db() -> AsyncGenerator[aiosqlite.Connection, None]:
    """Create a fresh in-memory SQLite database with all migrations applied.

    Each test gets its own database so tests don't interfere with each other.
    """
    conn = await aiosqlite.connect(":memory:")
    conn.row_factory = _dict_row_factory
    await conn.execute("PRAGMA journal_mode = WAL")
    await conn.execute("PRAGMA foreign_keys = ON")
    await conn.execute("PRAGMA synchronous = NORMAL")

    # Create migration tracking table
    await conn.execute("""
        CREATE TABLE IF NOT EXISTS _migrations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filename TEXT NOT NULL UNIQUE,
            applied_at TEXT DEFAULT (datetime('now'))
        )
    """)
    await conn.commit()

    # Run all migrations in order
    migrations_dir = settings.migrations_dir
    migration_files = sorted(
        migrations_dir.glob("*.sql"),
        key=lambda f: f.name,
    )

    for migration_file in migration_files:
        sql = migration_file.read_text(encoding="utf-8")
        for statement in _split_sql_statements(sql):
            try:
                await conn.execute(statement)
            except Exception:
                pass  # Ignore duplicate column / idempotent errors in test
        await conn.execute(
            "INSERT OR IGNORE INTO _migrations (filename) VALUES (?)",
            (migration_file.name,),
        )
        await conn.commit()

    yield conn
    await conn.close()


# ── Database with seeded admin ──────────────────────────────────────
@pytest_asyncio.fixture
async def db_with_admin(db: aiosqlite.Connection) -> aiosqlite.Connection:
    """In-memory database with the admin user's PIN hash set properly.

    The migration seeds __PLACEHOLDER_HASH__. This fixture replaces it
    with a real bcrypt hash for the default PIN (1234).
    """
    from app.services.auth_service import hash_pin

    real_hash = hash_pin(settings.DEFAULT_ADMIN_PIN)
    await db.execute(
        "UPDATE users SET pin_hash = ? WHERE id = 1",
        (real_hash,),
    )
    await db.commit()
    return db


# ── FastAPI test client ─────────────────────────────────────────────
@pytest_asyncio.fixture
async def client(db_with_admin: aiosqlite.Connection) -> AsyncGenerator[AsyncClient, None]:
    """Async HTTP test client with database dependency overridden.

    Uses the seeded in-memory database instead of the real file-based one.
    """
    from app.main import app
    from app.database import get_db

    async def _override_get_db():
        yield db_with_admin

    app.dependency_overrides[get_db] = _override_get_db

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac

    app.dependency_overrides.clear()


# ── Auth helper ─────────────────────────────────────────────────────
def make_auth_header(token: str) -> dict[str, str]:
    """Create an Authorization header from a JWT token."""
    return {"Authorization": f"Bearer {token}"}
