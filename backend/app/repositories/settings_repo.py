"""
Settings repository — data access for app configuration.

Settings are stored as key-value pairs with JSON-encoded values.
Categories help group related settings (theme, general, sync, ai, procurement).
"""

from __future__ import annotations

import json
from typing import Any

from app.repositories.base import BaseRepo


class SettingsRepo(BaseRepo):
    TABLE = "settings"

    async def get_by_key(self, key: str) -> Any:
        """Get a single setting value, JSON-decoded.

        Returns None if the key doesn't exist.
        """
        cursor = await self.db.execute(
            "SELECT value FROM settings WHERE key = ?",
            (key,),
        )
        row = await cursor.fetchone()
        if not row or row["value"] is None:
            return None

        try:
            return json.loads(row["value"])
        except (json.JSONDecodeError, TypeError):
            return row["value"]

    async def set_value(self, key: str, value: Any, category: str = "general") -> None:
        """Set a setting value (upsert). Value is JSON-encoded.

        If the key already exists, updates it. Otherwise inserts a new row.
        """
        json_value = json.dumps(value)

        await self.db.execute(
            """
            INSERT INTO settings (key, value, category, updated_at)
            VALUES (?, ?, ?, datetime('now'))
            ON CONFLICT(key) DO UPDATE SET
                value = excluded.value,
                updated_at = datetime('now')
            """,
            (key, json_value, category),
        )
        await self.db.commit()

    async def get_by_category(self, category: str) -> dict[str, Any]:
        """Get all settings in a category as a {key: decoded_value} dict."""
        cursor = await self.db.execute(
            "SELECT key, value FROM settings WHERE category = ? ORDER BY key",
            (category,),
        )
        rows = await cursor.fetchall()

        result = {}
        for row in rows:
            try:
                result[row["key"]] = json.loads(row["value"]) if row["value"] else None
            except (json.JSONDecodeError, TypeError):
                result[row["key"]] = row["value"]

        return result

    async def get_all_settings(self) -> dict[str, dict[str, Any]]:
        """Get all settings grouped by category.

        Returns: { "theme": {"theme_mode": "system", ...}, "general": {...}, ... }
        """
        cursor = await self.db.execute(
            "SELECT key, value, category FROM settings ORDER BY category, key"
        )
        rows = await cursor.fetchall()

        grouped: dict[str, dict[str, Any]] = {}
        for row in rows:
            cat = row["category"] or "general"
            if cat not in grouped:
                grouped[cat] = {}
            try:
                grouped[cat][row["key"]] = json.loads(row["value"]) if row["value"] else None
            except (json.JSONDecodeError, TypeError):
                grouped[cat][row["key"]] = row["value"]

        return grouped

    async def bulk_update(self, updates: dict[str, str]) -> int:
        """Update multiple settings at once. Returns count of updated settings."""
        count = 0
        for key, value in updates.items():
            await self.db.execute(
                """
                UPDATE settings SET value = ?, updated_at = datetime('now')
                WHERE key = ?
                """,
                (value, key),
            )
            count += 1

        await self.db.commit()
        return count
