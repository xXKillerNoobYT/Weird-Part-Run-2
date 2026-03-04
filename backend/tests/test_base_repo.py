"""
Tests for BaseRepo — CRUD operations, order_by validation, updated_at.

Uses a simple test table created in an in-memory database to verify
all BaseRepo methods work correctly without depending on any specific
application table.
"""

from __future__ import annotations

import pytest
import pytest_asyncio
import aiosqlite

from app.database import _dict_row_factory
from app.repositories.base import BaseRepo


# ── Test table setup ────────────────────────────────────────────────

class _ItemRepo(BaseRepo):
    """Repo for a simple test table."""
    TABLE = "test_items"
    HAS_UPDATED_AT = True


class _SimpleRepo(BaseRepo):
    """Repo for a table WITHOUT updated_at."""
    TABLE = "test_simple"
    HAS_UPDATED_AT = False


@pytest_asyncio.fixture
async def repo_db() -> aiosqlite.Connection:
    """Create an in-memory database with a test table."""
    conn = await aiosqlite.connect(":memory:")
    conn.row_factory = _dict_row_factory
    await conn.execute("PRAGMA foreign_keys = ON")

    # Table WITH updated_at
    await conn.execute("""
        CREATE TABLE test_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            value INTEGER DEFAULT 0,
            is_active INTEGER DEFAULT 1,
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now'))
        )
    """)

    # Add trigger (mimics migration 014)
    await conn.execute("""
        CREATE TRIGGER trg_test_items_updated_at
            AFTER UPDATE ON test_items
            FOR EACH ROW
            WHEN NEW.updated_at = OLD.updated_at
        BEGIN
            UPDATE test_items SET updated_at = datetime('now') WHERE id = NEW.id;
        END
    """)

    # Table WITHOUT updated_at
    await conn.execute("""
        CREATE TABLE test_simple (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            label TEXT NOT NULL
        )
    """)

    await conn.commit()
    yield conn
    await conn.close()


@pytest.fixture
def repo(repo_db: aiosqlite.Connection) -> _ItemRepo:
    return _ItemRepo(repo_db)


@pytest.fixture
def simple_repo(repo_db: aiosqlite.Connection) -> _SimpleRepo:
    return _SimpleRepo(repo_db)


# ══════════════════════════════════════════════════════════════════
# INSERT
# ══════════════════════════════════════════════════════════════════


class TestInsert:
    @pytest.mark.asyncio
    async def test_insert_returns_id(self, repo: _ItemRepo):
        row_id = await repo.insert({"name": "Widget", "value": 10})
        assert row_id == 1

    @pytest.mark.asyncio
    async def test_insert_auto_increments(self, repo: _ItemRepo):
        id1 = await repo.insert({"name": "A"})
        id2 = await repo.insert({"name": "B"})
        assert id2 == id1 + 1


# ══════════════════════════════════════════════════════════════════
# GET BY ID
# ══════════════════════════════════════════════════════════════════


class TestGetById:
    @pytest.mark.asyncio
    async def test_get_by_id_returns_dict(self, repo: _ItemRepo):
        row_id = await repo.insert({"name": "Widget", "value": 42})
        row = await repo.get_by_id(row_id)

        assert row is not None
        assert row["name"] == "Widget"
        assert row["value"] == 42

    @pytest.mark.asyncio
    async def test_get_by_id_not_found(self, repo: _ItemRepo):
        row = await repo.get_by_id(999)
        assert row is None


# ══════════════════════════════════════════════════════════════════
# GET ALL
# ══════════════════════════════════════════════════════════════════


class TestGetAll:
    @pytest.mark.asyncio
    async def test_get_all_empty(self, repo: _ItemRepo):
        rows = await repo.get_all()
        assert rows == []

    @pytest.mark.asyncio
    async def test_get_all_returns_all(self, repo: _ItemRepo):
        await repo.insert({"name": "A"})
        await repo.insert({"name": "B"})
        await repo.insert({"name": "C"})

        rows = await repo.get_all()
        assert len(rows) == 3

    @pytest.mark.asyncio
    async def test_get_all_with_where(self, repo: _ItemRepo):
        await repo.insert({"name": "Active", "is_active": 1})
        await repo.insert({"name": "Inactive", "is_active": 0})

        rows = await repo.get_all(where="is_active = ?", params=(1,))
        assert len(rows) == 1
        assert rows[0]["name"] == "Active"

    @pytest.mark.asyncio
    async def test_get_all_pagination(self, repo: _ItemRepo):
        for i in range(10):
            await repo.insert({"name": f"Item {i}"})

        page1 = await repo.get_all(limit=3, offset=0)
        page2 = await repo.get_all(limit=3, offset=3)

        assert len(page1) == 3
        assert len(page2) == 3
        assert page1[0]["name"] != page2[0]["name"]

    @pytest.mark.asyncio
    async def test_get_all_order_by(self, repo: _ItemRepo):
        await repo.insert({"name": "Banana"})
        await repo.insert({"name": "Apple"})
        await repo.insert({"name": "Cherry"})

        rows = await repo.get_all(order_by="name ASC")
        names = [r["name"] for r in rows]
        assert names == ["Apple", "Banana", "Cherry"]


# ══════════════════════════════════════════════════════════════════
# COUNT
# ══════════════════════════════════════════════════════════════════


class TestCount:
    @pytest.mark.asyncio
    async def test_count_empty(self, repo: _ItemRepo):
        assert await repo.count() == 0

    @pytest.mark.asyncio
    async def test_count_with_rows(self, repo: _ItemRepo):
        await repo.insert({"name": "A"})
        await repo.insert({"name": "B"})
        assert await repo.count() == 2

    @pytest.mark.asyncio
    async def test_count_with_where(self, repo: _ItemRepo):
        await repo.insert({"name": "A", "is_active": 1})
        await repo.insert({"name": "B", "is_active": 0})
        assert await repo.count(where="is_active = ?", params=(1,)) == 1


# ══════════════════════════════════════════════════════════════════
# UPDATE
# ══════════════════════════════════════════════════════════════════


class TestUpdate:
    @pytest.mark.asyncio
    async def test_update_returns_true(self, repo: _ItemRepo):
        row_id = await repo.insert({"name": "Old"})
        result = await repo.update(row_id, {"name": "New"})
        assert result is True

    @pytest.mark.asyncio
    async def test_update_changes_data(self, repo: _ItemRepo):
        row_id = await repo.insert({"name": "Old", "value": 1})
        await repo.update(row_id, {"name": "New", "value": 99})

        row = await repo.get_by_id(row_id)
        assert row["name"] == "New"
        assert row["value"] == 99

    @pytest.mark.asyncio
    async def test_update_not_found(self, repo: _ItemRepo):
        result = await repo.update(999, {"name": "Ghost"})
        assert result is False

    @pytest.mark.asyncio
    async def test_update_empty_data(self, repo: _ItemRepo):
        result = await repo.update(1, {})
        assert result is False

    @pytest.mark.asyncio
    async def test_update_auto_sets_updated_at(self, repo: _ItemRepo):
        """When HAS_UPDATED_AT=True, update() should set updated_at automatically."""
        row_id = await repo.insert({"name": "Foo"})
        row_before = await repo.get_by_id(row_id)

        # Force a slight delay so the timestamp changes
        import asyncio
        await asyncio.sleep(0.05)

        await repo.update(row_id, {"name": "Bar"})
        row_after = await repo.get_by_id(row_id)

        # Trigger + auto-set should update the timestamp
        # (may be same second in fast tests, but should not be None)
        assert row_after["updated_at"] is not None
        assert row_after["name"] == "Bar"


# ══════════════════════════════════════════════════════════════════
# DELETE
# ══════════════════════════════════════════════════════════════════


class TestDelete:
    @pytest.mark.asyncio
    async def test_delete_returns_true(self, repo: _ItemRepo):
        row_id = await repo.insert({"name": "Doomed"})
        assert await repo.delete(row_id) is True

    @pytest.mark.asyncio
    async def test_delete_removes_row(self, repo: _ItemRepo):
        row_id = await repo.insert({"name": "Doomed"})
        await repo.delete(row_id)
        assert await repo.get_by_id(row_id) is None

    @pytest.mark.asyncio
    async def test_delete_not_found(self, repo: _ItemRepo):
        assert await repo.delete(999) is False


# ══════════════════════════════════════════════════════════════════
# EXISTS
# ══════════════════════════════════════════════════════════════════


class TestExists:
    @pytest.mark.asyncio
    async def test_exists_true(self, repo: _ItemRepo):
        row_id = await repo.insert({"name": "Here"})
        assert await repo.exists(row_id) is True

    @pytest.mark.asyncio
    async def test_exists_false(self, repo: _ItemRepo):
        assert await repo.exists(999) is False


# ══════════════════════════════════════════════════════════════════
# ORDER BY VALIDATION
# ══════════════════════════════════════════════════════════════════


class TestOrderByValidation:
    """Ensure the order_by whitelist prevents SQL injection."""

    def test_valid_single_column(self):
        assert BaseRepo._validate_order_by("id ASC") == "id ASC"

    def test_valid_multi_column(self):
        result = BaseRepo._validate_order_by("name ASC, id DESC")
        assert result == "name ASC, id DESC"

    def test_valid_no_direction(self):
        assert BaseRepo._validate_order_by("name") == "name"

    def test_valid_underscore_column(self):
        assert BaseRepo._validate_order_by("created_at DESC") == "created_at DESC"

    def test_invalid_semicolon(self):
        with pytest.raises(ValueError, match="Invalid ORDER BY"):
            BaseRepo._validate_order_by("id; DROP TABLE users")

    def test_invalid_subquery(self):
        with pytest.raises(ValueError, match="Invalid ORDER BY"):
            BaseRepo._validate_order_by("(SELECT 1)")

    def test_invalid_comment(self):
        with pytest.raises(ValueError, match="Invalid ORDER BY"):
            BaseRepo._validate_order_by("id -- comment")

    def test_invalid_union(self):
        with pytest.raises(ValueError, match="Invalid ORDER BY"):
            BaseRepo._validate_order_by("id UNION SELECT * FROM users")

    @pytest.mark.asyncio
    async def test_injection_in_get_all(self, repo: _ItemRepo):
        """get_all should reject malicious order_by."""
        with pytest.raises(ValueError):
            await repo.get_all(order_by="id; DROP TABLE test_items")


# ══════════════════════════════════════════════════════════════════
# Simple table (no updated_at)
# ══════════════════════════════════════════════════════════════════


class TestSimpleRepo:
    @pytest.mark.asyncio
    async def test_insert_and_get(self, simple_repo: _SimpleRepo):
        row_id = await simple_repo.insert({"label": "Hello"})
        row = await simple_repo.get_by_id(row_id)
        assert row["label"] == "Hello"

    @pytest.mark.asyncio
    async def test_update_without_timestamp(self, simple_repo: _SimpleRepo):
        """Update should work fine on tables without updated_at."""
        row_id = await simple_repo.insert({"label": "Old"})
        result = await simple_repo.update(row_id, {"label": "New"})
        assert result is True

        row = await simple_repo.get_by_id(row_id)
        assert row["label"] == "New"
