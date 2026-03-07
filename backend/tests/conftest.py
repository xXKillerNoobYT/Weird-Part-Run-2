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


# ── Authenticated client ───────────────────────────────────────────
@pytest_asyncio.fixture
async def auth_client(client: AsyncClient) -> AsyncClient:
    """Test client with admin JWT pre-set in headers.

    Logs in via device-login + pin-login to get a real JWT,
    then sets Authorization header on the client.
    """
    # Step 1: Register device
    resp = await client.post("/api/auth/device-login", json={
        "device_fingerprint": "test-device-00001234",
        "device_name": "Test Device",
    })
    data = resp.json()
    device_id = data["data"]["device_id"]

    # Step 2: PIN login as admin (user_id=1, PIN=1234)
    resp = await client.post("/api/auth/pin-login", json={
        "user_id": 1,
        "pin": "1234",
        "device_fingerprint": "test-device-00001234",
        "device_name": "Test Device",
    })
    token = resp.json()["data"]["access_token"]
    client.headers["Authorization"] = f"Bearer {token}"
    return client


# ── Auth helper ─────────────────────────────────────────────────────
def make_auth_header(token: str) -> dict[str, str]:
    """Create an Authorization header from a JWT token."""
    return {"Authorization": f"Bearer {token}"}


# ── Seed data helpers ──────────────────────────────────────────────

# Track seed counts to generate unique values per test
_seed_counters: dict[str, int] = {}


def _next_id(prefix: str) -> int:
    _seed_counters[prefix] = _seed_counters.get(prefix, 0) + 1
    return _seed_counters[prefix]


async def seed_category(db: aiosqlite.Connection, name: str = "Test Category") -> int:
    """Insert a test part_category and return its ID."""
    n = _next_id("cat")
    cursor = await db.execute(
        "INSERT INTO part_categories (name) VALUES (?)",
        (f"{name} {n}",),
    )
    await db.commit()
    return cursor.lastrowid


async def seed_part(db: aiosqlite.Connection, **overrides) -> int:
    """Insert a test part and return its ID.

    Automatically creates a category if category_id not provided.
    """
    if "category_id" not in overrides or overrides["category_id"] is None:
        overrides["category_id"] = await seed_category(db)

    n = _next_id("part")
    defaults = {
        "name": f"Test Wire {n}",
        "category_id": overrides["category_id"],
        "company_cost_price": 10.0,
        "company_markup_percent": 50.0,
    }
    defaults.update(overrides)
    # company_sell_price is GENERATED — don't try to insert it
    defaults.pop("company_sell_price", None)
    cursor = await db.execute(
        """INSERT INTO parts (name, category_id,
           company_cost_price, company_markup_percent)
           VALUES (:name, :category_id,
                   :company_cost_price, :company_markup_percent)""",
        defaults,
    )
    await db.commit()
    return cursor.lastrowid


async def seed_stock(
    db: aiosqlite.Connection,
    part_id: int,
    location_type: str = "warehouse",
    location_id: int = 1,
    qty: int = 100,
    supplier_id: int | None = None,
) -> None:
    """Set stock level for a part at a location."""
    await db.execute(
        """INSERT OR REPLACE INTO stock
           (part_id, location_type, location_id, qty, supplier_id)
           VALUES (?, ?, ?, ?, ?)""",
        (part_id, location_type, location_id, qty, supplier_id),
    )
    await db.commit()


async def seed_job(db: aiosqlite.Connection, **overrides) -> int:
    """Insert a test job and return its ID."""
    n = _next_id("job")
    defaults = {
        "job_name": f"Test Job {n}",
        "job_number": f"TJ-{n:03d}",
        "customer_name": "Test Customer",
        "status": "active",
    }
    defaults.update(overrides)
    cursor = await db.execute(
        """INSERT INTO jobs (job_name, job_number, customer_name, status)
           VALUES (:job_name, :job_number, :customer_name, :status)""",
        defaults,
    )
    await db.commit()
    return cursor.lastrowid


async def seed_supplier(db: aiosqlite.Connection, **overrides) -> int:
    """Insert a test supplier and return its ID."""
    n = _next_id("sup")
    defaults = {"name": f"Test Supplier {n}"}
    defaults.update(overrides)
    cursor = await db.execute(
        "INSERT INTO suppliers (name) VALUES (:name)",
        defaults,
    )
    await db.commit()
    return cursor.lastrowid
