"""
Repositories for staging zones and zone assignments.

Staging zones are physical QR-labeled areas in the warehouse.
Zone assignments link jobs to physical zones (many-to-many, with overflow).
"""

from __future__ import annotations

from typing import Any

import aiosqlite

from app.repositories.base import BaseRepo


class StagingZoneRepo(BaseRepo):
    TABLE = "staging_zones"
    HAS_UPDATED_AT = True

    async def get_active_zones(self) -> list[dict]:
        """Get all active staging zones with current item counts."""
        cursor = await self.db.execute(
            """
            SELECT sz.*,
                   j.job_name,
                   COALESCE(
                       (SELECT COUNT(DISTINCT sm.part_id)
                        FROM stock_movements sm
                        WHERE sm.to_location_type = 'staging'
                          AND sm.to_location_id = sz.id
                          -- Only count items still in staging (not moved out)
                       ), 0
                   ) AS item_count
            FROM staging_zones sz
            LEFT JOIN jobs j ON j.id = sz.current_job_id
            WHERE sz.is_active = 1
            ORDER BY sz.label
            """
        )
        return await cursor.fetchall()

    async def get_available_zone(self, zone_type: str = "general") -> dict | None:
        """Find an available (unassigned) zone of the given type."""
        cursor = await self.db.execute(
            """
            SELECT * FROM staging_zones
            WHERE is_active = 1
              AND zone_type = ?
              AND current_job_id IS NULL
            ORDER BY id
            LIMIT 1
            """,
            (zone_type,),
        )
        return await cursor.fetchone()

    async def get_zones_for_job(self, job_id: int) -> list[dict]:
        """Get all active zones assigned to a job."""
        cursor = await self.db.execute(
            """
            SELECT sz.*
            FROM staging_zones sz
            JOIN staging_zone_assignments sza ON sza.zone_id = sz.id
            WHERE sza.job_id = ? AND sza.released_at IS NULL
            ORDER BY sz.label
            """,
            (job_id,),
        )
        return await cursor.fetchall()

    async def assign_to_job(self, zone_id: int, job_id: int) -> None:
        """Assign a zone to a job and update the zone's current_job_id."""
        await self.db.execute(
            "UPDATE staging_zones SET current_job_id = ?, zone_type = 'job_assigned' WHERE id = ?",
            (job_id, zone_id),
        )
        await self.db.commit()

    async def release_from_job(self, zone_id: int) -> None:
        """Release a zone from its current job assignment."""
        await self.db.execute(
            "UPDATE staging_zones SET current_job_id = NULL, zone_type = 'general' WHERE id = ?",
            (zone_id,),
        )
        await self.db.commit()

    async def get_by_qr_code(self, qr_code: str) -> dict | None:
        """Look up a staging zone by its QR code."""
        cursor = await self.db.execute(
            "SELECT * FROM staging_zones WHERE qr_code = ?",
            (qr_code,),
        )
        return await cursor.fetchone()


class StagingAssignmentRepo(BaseRepo):
    TABLE = "staging_zone_assignments"

    async def get_active_for_job(self, job_id: int) -> list[dict]:
        """Get all active zone assignments for a job."""
        cursor = await self.db.execute(
            """
            SELECT sza.*, sz.label AS zone_label, sz.qr_code
            FROM staging_zone_assignments sza
            JOIN staging_zones sz ON sz.id = sza.zone_id
            WHERE sza.job_id = ? AND sza.released_at IS NULL
            ORDER BY sza.assigned_at
            """,
            (job_id,),
        )
        return await cursor.fetchall()

    async def create_assignment(self, zone_id: int, job_id: int) -> int:
        """Create a zone-to-job assignment."""
        return await self.insert({
            "zone_id": zone_id,
            "job_id": job_id,
        })

    async def release_assignment(self, zone_id: int, job_id: int) -> None:
        """Release (soft-close) a zone-to-job assignment."""
        await self.db.execute(
            """
            UPDATE staging_zone_assignments
            SET released_at = datetime('now')
            WHERE zone_id = ? AND job_id = ? AND released_at IS NULL
            """,
            (zone_id, job_id),
        )
        await self.db.commit()

    async def get_active_for_zone(self, zone_id: int) -> list[dict]:
        """Get all active job assignments for a zone."""
        cursor = await self.db.execute(
            """
            SELECT sza.*, j.job_name, j.job_number
            FROM staging_zone_assignments sza
            JOIN jobs j ON j.id = sza.job_id
            WHERE sza.zone_id = ? AND sza.released_at IS NULL
            ORDER BY sza.assigned_at
            """,
            (zone_id,),
        )
        return await cursor.fetchall()
