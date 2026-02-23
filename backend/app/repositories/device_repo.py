"""
Device repository — data access for device tracking and assignment.

Devices are identified by a browser fingerprint. Each device can be:
- Assigned to a specific user (auto-login on that device)
- Marked as "public" (always requires PIN login — e.g., warehouse tablet)
- Unassigned (requires user selection + PIN on each use)
"""

from __future__ import annotations

from app.repositories.base import BaseRepo


class DeviceRepo(BaseRepo):
    TABLE = "devices"

    async def get_by_fingerprint(self, fingerprint: str) -> dict | None:
        """Find a device by its unique browser/device fingerprint."""
        cursor = await self.db.execute(
            "SELECT * FROM devices WHERE device_fingerprint = ? LIMIT 1",
            (fingerprint,),
        )
        return await cursor.fetchone()

    async def register_device(
        self,
        fingerprint: str,
        device_name: str,
        *,
        assigned_user_id: int | None = None,
        is_public: bool = False,
    ) -> int:
        """Register a new device. Returns the device ID.

        Called the first time we see a device fingerprint.
        """
        return await self.insert({
            "device_fingerprint": fingerprint,
            "device_name": device_name,
            "assigned_user_id": assigned_user_id,
            "is_public": 1 if is_public else 0,
        })

    async def assign_user(self, device_id: int, user_id: int | None) -> bool:
        """Assign or unassign a user to/from a device.

        Pass user_id=None to unassign.
        """
        return await self.update(device_id, {
            "assigned_user_id": user_id,
        })

    async def set_public(self, device_id: int, is_public: bool) -> bool:
        """Toggle the public flag on a device."""
        return await self.update(device_id, {
            "is_public": 1 if is_public else 0,
        })

    async def touch(self, device_id: int) -> None:
        """Update the last_seen timestamp for a device."""
        await self.db.execute(
            "UPDATE devices SET last_seen = datetime('now') WHERE id = ?",
            (device_id,),
        )
        await self.db.commit()

    async def get_all_devices(self) -> list[dict]:
        """Get all registered devices with their assigned user info."""
        cursor = await self.db.execute(
            """
            SELECT d.*, u.display_name as assigned_user_name
            FROM devices d
            LEFT JOIN users u ON u.id = d.assigned_user_id
            ORDER BY d.last_seen DESC NULLS LAST
            """
        )
        return await cursor.fetchall()
