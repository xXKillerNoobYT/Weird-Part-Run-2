"""
Base repository with common database operations.

All repositories inherit from BaseRepo to get standard CRUD helpers.
The connection is injected — repos don't manage their own connections.
"""

from __future__ import annotations

from typing import Any

import aiosqlite


class BaseRepo:
    """Base class for all repositories.

    Provides common CRUD patterns. Subclasses define the table name
    and any domain-specific query methods.

    Usage:
        class UserRepo(BaseRepo):
            TABLE = "users"

        repo = UserRepo(db)
        user = await repo.get_by_id(1)
        users = await repo.get_all(where="is_active = 1", limit=50)
    """

    TABLE: str = ""  # Subclass MUST override

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    async def get_by_id(self, id: int) -> dict | None:
        """Fetch a single row by primary key."""
        cursor = await self.db.execute(
            f"SELECT * FROM {self.TABLE} WHERE id = ?",  # noqa: S608
            (id,),
        )
        return await cursor.fetchone()

    async def get_all(
        self,
        *,
        where: str | None = None,
        params: tuple = (),
        order_by: str = "id ASC",
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict]:
        """Fetch multiple rows with optional filtering and pagination."""
        sql = f"SELECT * FROM {self.TABLE}"  # noqa: S608
        if where:
            sql += f" WHERE {where}"
        sql += f" ORDER BY {order_by} LIMIT ? OFFSET ?"

        cursor = await self.db.execute(sql, (*params, limit, offset))
        return await cursor.fetchall()

    async def count(
        self,
        *,
        where: str | None = None,
        params: tuple = (),
    ) -> int:
        """Count rows with optional filtering."""
        sql = f"SELECT COUNT(*) as cnt FROM {self.TABLE}"  # noqa: S608
        if where:
            sql += f" WHERE {where}"

        cursor = await self.db.execute(sql, params)
        row = await cursor.fetchone()
        return row["cnt"] if row else 0

    async def insert(self, data: dict[str, Any]) -> int:
        """Insert a row and return the new row's ID."""
        columns = ", ".join(data.keys())
        placeholders = ", ".join(["?"] * len(data))

        cursor = await self.db.execute(
            f"INSERT INTO {self.TABLE} ({columns}) VALUES ({placeholders})",  # noqa: S608
            tuple(data.values()),
        )
        await self.db.commit()
        return cursor.lastrowid  # type: ignore[return-value]

    async def update(self, id: int, data: dict[str, Any]) -> bool:
        """Update a row by ID. Returns True if the row was found and updated."""
        if not data:
            return False

        set_clause = ", ".join(f"{k} = ?" for k in data.keys())
        cursor = await self.db.execute(
            f"UPDATE {self.TABLE} SET {set_clause} WHERE id = ?",  # noqa: S608
            (*data.values(), id),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def delete(self, id: int) -> bool:
        """Delete a row by ID. Returns True if the row existed."""
        cursor = await self.db.execute(
            f"DELETE FROM {self.TABLE} WHERE id = ?",  # noqa: S608
            (id,),
        )
        await self.db.commit()
        return cursor.rowcount > 0

    async def exists(self, id: int) -> bool:
        """Check if a row with the given ID exists."""
        cursor = await self.db.execute(
            f"SELECT 1 FROM {self.TABLE} WHERE id = ? LIMIT 1",  # noqa: S608
            (id,),
        )
        return await cursor.fetchone() is not None
