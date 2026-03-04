"""
Delivery service — assign parts to vehicles for job delivery, mark
items as delivered (triggers stock movement truck → job), and return
undelivered items.

The delivery system is *distinct* from vehicle inventory:
  - Vehicle inventory = general parts stock on a truck (location_type='truck')
  - Delivery items = parts assigned for delivery to a specific job

When an item is "delivered", the stock moves from the truck to the
job site, and the delivery item is marked complete.
"""

from __future__ import annotations

import logging
from typing import Any

import aiosqlite

from app.repositories.stock_repo import StockRepo
from app.repositories.vehicle_repo import VehicleDeliveryRepo, VehicleRepo

logger = logging.getLogger(__name__)


class DeliveryService:
    """Orchestrates job-bound delivery item workflows."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db
        self.delivery_repo = VehicleDeliveryRepo(db)
        self.vehicle_repo = VehicleRepo(db)
        self.stock_repo = StockRepo(db)

    # ── Assign Items ───────────────────────────────────────────

    async def assign_delivery_items(
        self,
        vehicle_id: int,
        job_id: int,
        items: list[dict],
        assigned_by: int,
    ) -> list[dict]:
        """Assign parts to a vehicle for delivery to a specific job.

        Each item: {part_id, qty_assigned, notes?}

        Does NOT move stock yet — items are just "assigned" and wait
        for the driver to load and deliver them.
        """
        vehicle = await self.vehicle_repo.get_by_id(vehicle_id)
        if not vehicle:
            raise ValueError(f"Vehicle {vehicle_id} not found")

        created_ids = []
        for item in items:
            delivery_data = {
                "vehicle_id": vehicle_id,
                "job_id": job_id,
                "part_id": item["part_id"],
                "qty_assigned": item.get("qty_assigned", 1),
                "assigned_by": assigned_by,
                "status": "assigned",
                "notes": item.get("notes"),
            }
            new_id = await self.delivery_repo.insert(delivery_data)
            created_ids.append(new_id)

        await self.db.commit()

        # Return full records so response model gets all required fields
        created_items = []
        for new_id in created_ids:
            record = await self.delivery_repo.get_by_id(new_id)
            if record:
                created_items.append(dict(record))
        return created_items

    # ── Update Status ──────────────────────────────────────────

    async def update_delivery_status(
        self,
        item_id: int,
        new_status: str,
        user_id: int,
    ) -> dict | None:
        """Update a delivery item's status (loaded, in_transit, etc.)."""
        item = await self.delivery_repo.get_by_id(item_id)
        if not item:
            return None

        valid_transitions = {
            "assigned": ["loaded", "returned"],
            "loaded": ["in_transit", "returned"],
            "in_transit": ["delivered", "returned"],
        }

        current = item["status"]
        if current in valid_transitions:
            if new_status not in valid_transitions[current]:
                raise ValueError(
                    f"Cannot transition from '{current}' to '{new_status}'. "
                    f"Valid: {valid_transitions[current]}"
                )

        await self.delivery_repo.update(item_id, {"status": new_status})
        await self.db.commit()

        return await self.delivery_repo.get_by_id(item_id)

    # ── Mark Delivered ─────────────────────────────────────────

    async def mark_delivered(
        self,
        item_id: int,
        delivered_by: int,
        *,
        qty_delivered: int | None = None,
    ) -> dict | None:
        """Mark a delivery item as delivered.

        This triggers a stock movement from the truck to the job:
          1. Decrements truck stock (location_type='truck')
          2. Increments job stock (location_type='job')
          3. Records a stock_movement with type 'transfer'
          4. Updates the delivery item with delivered qty/time/status
        """
        item = await self.delivery_repo.get_by_id(item_id)
        if not item:
            return None

        if item["status"] == "delivered":
            return dict(item)  # Already delivered, no-op

        actual_qty = qty_delivered or item["qty_assigned"]
        vehicle_id = item["vehicle_id"]
        job_id = item["job_id"]
        part_id = item["part_id"]

        # 1. Create stock movement: truck → job
        await self.db.execute(
            """
            INSERT INTO stock_movements (
                part_id, qty, movement_type,
                from_location_type, from_location_id,
                to_location_type, to_location_id,
                job_id, performed_by, notes
            ) VALUES (?, ?, 'transfer', 'truck', ?, 'job', ?, ?, ?, ?)
            """,
            (
                part_id, actual_qty,
                vehicle_id,
                job_id,
                job_id,
                delivered_by,
                f"Delivery item #{item_id} — truck to job",
            ),
        )

        # 2. Decrement truck stock
        await self.db.execute(
            """
            UPDATE stock SET qty = MAX(qty - ?, 0), updated_at = datetime('now')
            WHERE part_id = ? AND location_type = 'truck' AND location_id = ?
            """,
            (actual_qty, part_id, vehicle_id),
        )

        # 3. Increment job stock (upsert)
        await self.stock_repo.add_stock(part_id, "job", job_id, actual_qty)

        # 4. Update delivery item
        await self.delivery_repo.update(item_id, {
            "qty_delivered": actual_qty,
            "delivered_by": delivered_by,
            "status": "delivered",
        })
        # Set delivered_at via SQL expression
        await self.db.execute(
            "UPDATE vehicle_delivery_items SET delivered_at = datetime('now') WHERE id = ?",
            (item_id,),
        )

        await self.db.commit()

        return await self.delivery_repo.get_by_id(item_id)

    # ── Return Undelivered ─────────────────────────────────────

    async def return_undelivered(
        self,
        item_id: int,
        returned_by: int,
        *,
        return_to: str = "truck",
        notes: str | None = None,
    ) -> dict | None:
        """Return an undelivered item.

        If return_to='warehouse', creates a stock movement from
        truck → warehouse.  If 'truck', just marks the delivery
        item as returned (parts stay on the truck).
        """
        item = await self.delivery_repo.get_by_id(item_id)
        if not item:
            return None

        if item["status"] == "delivered":
            raise ValueError("Cannot return an already-delivered item")

        qty = item["qty_assigned"] - (item.get("qty_delivered") or 0)
        if qty <= 0:
            # Everything was already delivered, nothing to return
            await self.delivery_repo.update(item_id, {"status": "delivered"})
            await self.db.commit()
            return await self.delivery_repo.get_by_id(item_id)

        if return_to == "warehouse":
            # Move remaining qty from truck back to warehouse
            vehicle_id = item["vehicle_id"]
            part_id = item["part_id"]

            await self.db.execute(
                """
                INSERT INTO stock_movements (
                    part_id, qty, movement_type,
                    from_location_type, from_location_id,
                    to_location_type, to_location_id,
                    performed_by, notes
                ) VALUES (?, ?, 'transfer', 'truck', ?, 'warehouse', 1, ?, ?)
                """,
                (
                    part_id, qty,
                    vehicle_id,
                    returned_by,
                    notes or f"Returned undelivered item #{item_id}",
                ),
            )

            # Decrement truck stock
            await self.db.execute(
                """
                UPDATE stock SET qty = MAX(qty - ?, 0), updated_at = datetime('now')
                WHERE part_id = ? AND location_type = 'truck' AND location_id = ?
                """,
                (qty, part_id, vehicle_id),
            )

            # Increment warehouse stock
            await self.stock_repo.add_stock(part_id, "warehouse", 1, qty)

        # Mark delivery item as returned
        await self.delivery_repo.update(item_id, {
            "status": "returned",
            "notes": notes or item.get("notes"),
        })

        await self.db.commit()
        return await self.delivery_repo.get_by_id(item_id)

    # ── Bulk Operations ────────────────────────────────────────

    async def get_deliveries_for_vehicle(
        self,
        vehicle_id: int,
        *,
        status: str | None = None,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict]:
        """Get delivery items on a vehicle, optionally filtered by status."""
        return await self.delivery_repo.get_for_vehicle(
            vehicle_id, status=status, limit=limit, offset=offset
        )

    async def get_deliveries_for_job(
        self,
        job_id: int,
        *,
        vehicle_id: int | None = None,
    ) -> list[dict]:
        """Get all delivery items destined for a job."""
        return await self.delivery_repo.get_for_job(
            job_id, vehicle_id=vehicle_id
        )
