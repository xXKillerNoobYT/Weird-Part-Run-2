"""
Movement Service — the atomic engine for all stock movements.

Every stock change in the system flows through this service. It guarantees:
1. Atomic transactions (all-or-nothing)
2. Supplier chain preservation (supplier_id follows the stock)
3. FIFO with preferred supplier override
4. Pricing snapshots at time of move
5. Forecast recalculation after each move
6. Low-stock detection → spot-check task creation

No stock is ever modified directly — always through execute_movement().
"""

from __future__ import annotations

import logging
from datetime import datetime
from typing import Any

import aiosqlite

from app.models.warehouse import (
    MOVEMENT_RULES,
    VALID_LOCATION_TYPES,
    MovementLineItem,
    MovementPreview,
    MovementPreviewLine,
    MovementRequest,
    MovementResult,
    MovementExecuteResponse,
    ReceiveStockRequest,
    ReceiveStockResult,
    ValidationError,
    ValidationResult,
)

logger = logging.getLogger(__name__)


class MovementService:
    """Orchestrates all stock movements with atomic transactions."""

    def __init__(self, db: aiosqlite.Connection) -> None:
        self.db = db

    # ── Public API ────────────────────────────────────────────────

    async def validate_movement(self, req: MovementRequest) -> ValidationResult:
        """Pre-flight validation. Returns errors and warnings without executing."""
        errors: list[ValidationError] = []
        warnings: list[str] = []

        # Check valid path
        path = (req.from_location_type, req.to_location_type)
        if path not in MOVEMENT_RULES:
            errors.append(ValidationError(
                message=f"Invalid movement path: {req.from_location_type} → {req.to_location_type}",
            ))
            return ValidationResult(valid=False, errors=errors)

        # Check each line item
        for item in req.items:
            # Check part exists
            part = await self._get_part(item.part_id)
            if not part:
                errors.append(ValidationError(
                    part_id=item.part_id,
                    message=f"Part ID {item.part_id} not found",
                ))
                continue

            # Check stock at source
            available = await self._get_available_qty(
                item.part_id, req.from_location_type, req.from_location_id
            )
            if item.qty > available:
                errors.append(ValidationError(
                    part_id=item.part_id,
                    field="qty",
                    message=f"{part['name']}: requested {item.qty}, only {available} available",
                ))

            # Warnings for edge cases
            if available - item.qty == 0:
                warnings.append(f"{part['name']}: source will be at 0 units after move")

            # Check if destination would exceed max
            dest_qty = await self._get_available_qty(
                item.part_id, req.to_location_type, req.to_location_id
            )
            max_stock = part.get("max_stock_level", 0) or 0
            if max_stock > 0 and dest_qty + item.qty > max_stock:
                warnings.append(
                    f"{part['name']}: destination will be {dest_qty + item.qty}, "
                    f"exceeding max of {max_stock}"
                )

        return ValidationResult(
            valid=len(errors) == 0,
            errors=errors,
            warnings=warnings,
        )

    async def calculate_preview(self, req: MovementRequest) -> MovementPreview:
        """Calculate before/after state for the preview step."""
        path = (req.from_location_type, req.to_location_type)
        rules = MOVEMENT_RULES.get(path, {})

        lines: list[MovementPreviewLine] = []
        warnings: list[str] = []
        total_qty = 0
        total_value = 0.0

        for item in req.items:
            part = await self._get_part(item.part_id)
            if not part:
                continue

            source_qty = await self._get_available_qty(
                item.part_id, req.from_location_type, req.from_location_id
            )
            dest_qty = await self._get_available_qty(
                item.part_id, req.to_location_type, req.to_location_id
            )

            # Resolve supplier
            supplier_id, supplier_name, supplier_source = await self._resolve_supplier(
                item, req.from_location_type, req.from_location_id
            )

            unit_cost = part.get("company_cost_price") or 0.0
            line_value = unit_cost * item.qty

            lines.append(MovementPreviewLine(
                part_id=item.part_id,
                part_name=part["name"],
                part_code=part.get("code"),
                qty=item.qty,
                supplier_id=supplier_id,
                supplier_name=supplier_name,
                supplier_source=supplier_source,
                source_before=source_qty,
                source_after=source_qty - item.qty,
                dest_before=dest_qty,
                dest_after=dest_qty + item.qty,
                unit_cost=unit_cost,
                line_value=line_value,
            ))

            total_qty += item.qty
            total_value += line_value

            if source_qty - item.qty == 0:
                warnings.append(f"{part['name']}: source will be at 0 units")

        return MovementPreview(
            lines=lines,
            total_qty=total_qty,
            total_value=total_value if total_value > 0 else None,
            movement_type=rules.get("type", "transfer"),
            photo_required=rules.get("photo_required", False),
            warnings=warnings,
        )

    async def execute_movement(
        self, req: MovementRequest, performed_by: int
    ) -> MovementExecuteResponse:
        """Execute a batch movement atomically.

        All items succeed or all fail. The transaction is committed only
        after all items are processed.
        """
        # Validate first
        validation = await self.validate_movement(req)
        if not validation.valid:
            error_msgs = "; ".join(e.message for e in validation.errors)
            raise ValueError(f"Validation failed: {error_msgs}")

        path = (req.from_location_type, req.to_location_type)
        rules = MOVEMENT_RULES.get(path, {})
        movement_type = rules.get("type", "transfer")

        results: list[MovementResult] = []
        total_qty = 0

        try:
            for item in req.items:
                result = await self._execute_single_line(
                    item=item,
                    req=req,
                    movement_type=movement_type,
                    performed_by=performed_by,
                )
                results.append(result)
                total_qty += item.qty

            # All lines succeeded — commit the whole batch
            await self.db.commit()

            # Post-commit side effects (non-transactional — OK if these fail)
            affected_part_ids = {item.part_id for item in req.items}
            for part_id in affected_part_ids:
                await self._update_forecast(part_id)
                await self._check_low_stock(part_id)

        except Exception:
            # Rollback on any error
            await self.db.rollback()
            raise

        return MovementExecuteResponse(
            success=True,
            movements=results,
            total_items=len(results),
            total_qty=total_qty,
        )

    async def receive_stock(
        self, req: ReceiveStockRequest, performed_by: int
    ) -> ReceiveStockResult:
        """Receive new stock into the warehouse from outside the system.

        Unlike execute_movement (location-to-location), this creates stock from
        nothing — e.g., a delivery arrived, or we're doing initial inventory setup.
        Each item:
        1. Validates the part exists
        2. UPSERTs into the stock table (warehouse, location_id=1)
        3. Logs a 'receive' movement for the audit trail
        4. Updates parts.shelf_location if provided
        5. Recalculates forecast
        """
        movement_ids: list[int] = []
        total_qty = 0

        try:
            for item in req.items:
                part = await self._get_part(item.part_id)
                if not part:
                    raise ValueError(f"Part ID {item.part_id} not found")

                # Step 1: Add stock to warehouse (UPSERT)
                await self._add_stock(
                    part_id=item.part_id,
                    location_type="warehouse",
                    location_id=1,
                    qty=item.qty,
                    supplier_id=item.supplier_id,
                )

                # Step 2: Log the receive movement (audit trail)
                movement_id = await self._log_movement(
                    part_id=item.part_id,
                    qty=item.qty,
                    to_location_type="warehouse",
                    to_location_id=1,
                    supplier_id=item.supplier_id,
                    movement_type="receive",
                    reason=req.reason,
                    notes=item.notes or req.notes,
                    reference_number=req.reference_number,
                    performed_by=performed_by,
                    unit_cost_at_move=part.get("company_cost_price"),
                    unit_sell_at_move=part.get("company_sell_price"),
                )
                movement_ids.append(movement_id)
                total_qty += item.qty

                # Step 3: Update location fields on the part if provided
                location_updates: list[str] = []
                location_params: list = []
                if item.shelf_location is not None:
                    location_updates.append("shelf_location = ?")
                    location_params.append(item.shelf_location)
                if item.bin_location is not None:
                    location_updates.append("bin_location = ?")
                    location_params.append(item.bin_location)
                if location_updates:
                    location_params.append(item.part_id)
                    await self.db.execute(
                        f"UPDATE parts SET {', '.join(location_updates)} WHERE id = ?",
                        location_params,
                    )

            # Commit all changes atomically
            await self.db.commit()

            # Post-commit: recalculate forecasts (non-transactional, OK if fails)
            affected_part_ids = {item.part_id for item in req.items}
            for part_id in affected_part_ids:
                await self._update_forecast(part_id)

        except Exception:
            await self.db.rollback()
            raise

        return ReceiveStockResult(
            success=True,
            items_received=len(req.items),
            total_qty=total_qty,
            movement_ids=movement_ids,
        )

    # ── Private: Single Line Execution ────────────────────────────

    async def _execute_single_line(
        self,
        item: MovementLineItem,
        req: MovementRequest,
        movement_type: str,
        performed_by: int,
    ) -> MovementResult:
        """Execute a single line item within the batch transaction.

        Does NOT commit — the caller manages the transaction boundary.
        """
        part = await self._get_part(item.part_id)
        if not part:
            raise ValueError(f"Part {item.part_id} not found")

        # Step 1: Resolve supplier (preferred > FIFO)
        supplier_id, _, _ = await self._resolve_supplier(
            item, req.from_location_type, req.from_location_id
        )

        # Step 2: Deduct from source (atomic guard: qty >= requested)
        deducted = await self._deduct_stock(
            part_id=item.part_id,
            location_type=req.from_location_type,
            location_id=req.from_location_id,
            qty=item.qty,
            supplier_id=supplier_id,
        )
        if not deducted:
            raise ValueError(
                f"Insufficient stock for {part['name']}: "
                f"cannot deduct {item.qty} from {req.from_location_type}"
            )

        # Step 3: Add to destination (UPSERT)
        stock_id = await self._add_stock(
            part_id=item.part_id,
            location_type=req.to_location_type,
            location_id=req.to_location_id,
            qty=item.qty,
            supplier_id=supplier_id,
        )

        # Step 4: Tag staging if moving to pulled
        if req.to_location_type == "pulled" and req.destination_type:
            await self._tag_staging(
                stock_id=stock_id,
                destination_type=req.destination_type,
                destination_id=req.destination_id or 0,
                destination_label=req.destination_label,
                tagged_by=performed_by,
            )

        # Step 5: Clear staging tag if moving FROM pulled
        if req.from_location_type == "pulled":
            await self._clear_staging_tag_for_part(
                part_id=item.part_id,
                location_id=req.from_location_id,
                supplier_id=supplier_id,
            )

        # Step 6: Log movement (immutable audit trail)
        movement_id = await self._log_movement(
            part_id=item.part_id,
            qty=item.qty,
            from_location_type=req.from_location_type,
            from_location_id=req.from_location_id,
            to_location_type=req.to_location_type,
            to_location_id=req.to_location_id,
            supplier_id=supplier_id,
            movement_type=movement_type,
            reason=req.reason,
            notes=req.notes,
            reference_number=req.reference_number,
            job_id=req.job_id,
            performed_by=performed_by,
            photo_path=req.photo_path,
            scan_confirmed=req.scan_confirmed,
            gps_lat=req.gps_lat,
            gps_lng=req.gps_lng,
            unit_cost_at_move=part.get("company_cost_price"),
            unit_sell_at_move=part.get("company_sell_price"),
        )

        return MovementResult(
            movement_id=movement_id,
            part_id=item.part_id,
            part_name=part["name"],
            qty=item.qty,
            movement_type=movement_type,
            from_location_type=req.from_location_type,
            to_location_type=req.to_location_type,
        )

    # ── Private: Stock Operations ─────────────────────────────────

    async def _deduct_stock(
        self,
        part_id: int,
        location_type: str,
        location_id: int,
        qty: int,
        supplier_id: int | None,
    ) -> bool:
        """Atomically deduct stock. Returns False if insufficient.

        The WHERE qty >= ? guard prevents negative stock at the DB level.
        """
        if supplier_id is not None:
            cursor = await self.db.execute(
                """UPDATE stock SET qty = qty - ?, updated_at = datetime('now')
                   WHERE part_id = ? AND location_type = ? AND location_id = ?
                     AND supplier_id = ? AND qty >= ?""",
                (qty, part_id, location_type, location_id, supplier_id, qty),
            )
        else:
            cursor = await self.db.execute(
                """UPDATE stock SET qty = qty - ?, updated_at = datetime('now')
                   WHERE part_id = ? AND location_type = ? AND location_id = ?
                     AND supplier_id IS NULL AND qty >= ?""",
                (qty, part_id, location_type, location_id, qty),
            )

        if cursor.rowcount > 0:
            # Clean up zero-qty rows
            await self.db.execute(
                "DELETE FROM stock WHERE part_id = ? AND location_type = ? "
                "AND location_id = ? AND qty = 0",
                (part_id, location_type, location_id),
            )
            return True

        # Supplier-specific row didn't have enough — try pooled deduction
        # (deduct from any supplier's stock at this location, FIFO order)
        if supplier_id is not None:
            return await self._deduct_stock_pooled(
                part_id, location_type, location_id, qty
            )

        return False

    async def _deduct_stock_pooled(
        self,
        part_id: int,
        location_type: str,
        location_id: int,
        qty_needed: int,
    ) -> bool:
        """Deduct from multiple supplier rows at a location (FIFO by updated_at)."""
        cursor = await self.db.execute(
            """SELECT id, qty, supplier_id FROM stock
               WHERE part_id = ? AND location_type = ? AND location_id = ? AND qty > 0
               ORDER BY updated_at ASC""",
            (part_id, location_type, location_id),
        )
        rows = await cursor.fetchall()

        total_available = sum(r["qty"] for r in rows)
        if total_available < qty_needed:
            return False

        remaining = qty_needed
        for row in rows:
            if remaining <= 0:
                break
            take = min(row["qty"], remaining)
            await self.db.execute(
                "UPDATE stock SET qty = qty - ?, updated_at = datetime('now') WHERE id = ?",
                (take, row["id"]),
            )
            remaining -= take

        # Clean up zero-qty rows
        await self.db.execute(
            "DELETE FROM stock WHERE part_id = ? AND location_type = ? "
            "AND location_id = ? AND qty = 0",
            (part_id, location_type, location_id),
        )
        return True

    async def _add_stock(
        self,
        part_id: int,
        location_type: str,
        location_id: int,
        qty: int,
        supplier_id: int | None,
    ) -> int:
        """Add stock to a location. UPSERT: increment existing row or create new."""
        # Try update existing row
        if supplier_id is not None:
            cursor = await self.db.execute(
                """UPDATE stock SET qty = qty + ?, updated_at = datetime('now')
                   WHERE part_id = ? AND location_type = ? AND location_id = ?
                     AND supplier_id = ?""",
                (qty, part_id, location_type, location_id, supplier_id),
            )
        else:
            cursor = await self.db.execute(
                """UPDATE stock SET qty = qty + ?, updated_at = datetime('now')
                   WHERE part_id = ? AND location_type = ? AND location_id = ?
                     AND supplier_id IS NULL""",
                (qty, part_id, location_type, location_id),
            )

        if cursor.rowcount > 0:
            # Return existing row ID
            id_cursor = await self.db.execute(
                """SELECT id FROM stock
                   WHERE part_id = ? AND location_type = ? AND location_id = ?
                     AND (supplier_id = ? OR (supplier_id IS NULL AND ? IS NULL))""",
                (part_id, location_type, location_id, supplier_id, supplier_id),
            )
            row = await id_cursor.fetchone()
            return row["id"] if row else 0

        # Insert new row
        cursor = await self.db.execute(
            """INSERT INTO stock (part_id, location_type, location_id, qty, supplier_id, updated_at)
               VALUES (?, ?, ?, ?, ?, datetime('now'))""",
            (part_id, location_type, location_id, qty, supplier_id),
        )
        return cursor.lastrowid or 0

    # ── Private: Staging Tags ─────────────────────────────────────

    async def _tag_staging(
        self,
        stock_id: int,
        destination_type: str,
        destination_id: int,
        destination_label: str | None,
        tagged_by: int,
    ) -> None:
        """Create or update a staging destination tag."""
        await self.db.execute(
            """INSERT INTO staging_tags
                   (stock_id, destination_type, destination_id, destination_label, tagged_by)
               VALUES (?, ?, ?, ?, ?)
               ON CONFLICT(stock_id) DO UPDATE SET
                   destination_type = excluded.destination_type,
                   destination_id = excluded.destination_id,
                   destination_label = excluded.destination_label,
                   tagged_by = excluded.tagged_by,
                   created_at = datetime('now')""",
            (stock_id, destination_type, destination_id, destination_label, tagged_by),
        )

    async def _clear_staging_tag_for_part(
        self,
        part_id: int,
        location_id: int,
        supplier_id: int | None,
    ) -> None:
        """Remove staging tag when stock leaves the pulled area."""
        if supplier_id is not None:
            await self.db.execute(
                """DELETE FROM staging_tags WHERE stock_id IN (
                       SELECT id FROM stock
                       WHERE part_id = ? AND location_type = 'pulled'
                         AND location_id = ? AND supplier_id = ?
                   )""",
                (part_id, location_id, supplier_id),
            )
        else:
            await self.db.execute(
                """DELETE FROM staging_tags WHERE stock_id IN (
                       SELECT id FROM stock
                       WHERE part_id = ? AND location_type = 'pulled'
                         AND location_id = ? AND supplier_id IS NULL
                   )""",
                (part_id, location_id),
            )

    # ── Private: Movement Log ─────────────────────────────────────

    async def _log_movement(self, **kwargs: Any) -> int:
        """Insert an immutable movement log entry."""
        data = {k: v for k, v in kwargs.items() if v is not None}
        # Convert booleans to int for SQLite
        if "scan_confirmed" in data:
            data["scan_confirmed"] = int(data["scan_confirmed"])

        columns = ", ".join(data.keys())
        placeholders = ", ".join(["?"] * len(data))
        cursor = await self.db.execute(
            f"INSERT INTO stock_movements ({columns}) VALUES ({placeholders})",
            tuple(data.values()),
        )
        return cursor.lastrowid or 0

    # ── Private: Supplier Resolution ──────────────────────────────

    async def _resolve_supplier(
        self,
        item: MovementLineItem,
        from_location_type: str,
        from_location_id: int,
    ) -> tuple[int | None, str | None, str | None]:
        """Resolve which supplier's stock to move.

        Priority:
        1. Explicit supplier_id on the line item
        2. Preferred supplier (cascade: part → type → style → category)
        3. FIFO (oldest stock at source location)

        Returns (supplier_id, supplier_name, source_label).
        """
        # 1. Explicit supplier
        if item.supplier_id:
            name = await self._get_supplier_name(item.supplier_id)
            return (item.supplier_id, name, "explicit")

        # 2. Preferred supplier cascade
        preferred = await self._get_preferred_supplier(item.part_id)
        if preferred:
            # Check if this supplier has stock at the source
            cursor = await self.db.execute(
                """SELECT qty FROM stock
                   WHERE part_id = ? AND location_type = ? AND location_id = ?
                     AND supplier_id = ? AND qty > 0""",
                (item.part_id, from_location_type, from_location_id, preferred["supplier_id"]),
            )
            row = await cursor.fetchone()
            if row and row["qty"] >= item.qty:
                return (preferred["supplier_id"], preferred["supplier_name"], "preferred")

        # 3. FIFO — oldest stock at source
        cursor = await self.db.execute(
            """SELECT s.supplier_id, sup.name AS supplier_name
               FROM stock s
               LEFT JOIN suppliers sup ON sup.id = s.supplier_id
               WHERE s.part_id = ? AND s.location_type = ? AND s.location_id = ?
                 AND s.qty > 0
               ORDER BY s.updated_at ASC
               LIMIT 1""",
            (item.part_id, from_location_type, from_location_id),
        )
        row = await cursor.fetchone()
        if row:
            return (row["supplier_id"], row["supplier_name"], "fifo")

        return (None, None, None)

    async def _get_preferred_supplier(self, part_id: int) -> dict | None:
        """Cascade lookup: part → type → style → category → None."""
        part = await self._get_part(part_id)
        if not part:
            return None

        # Check each level in cascade order
        scopes = [
            ("part", part_id),
        ]
        if part.get("type_id"):
            scopes.append(("type", part["type_id"]))
        if part.get("style_id"):
            scopes.append(("style", part["style_id"]))
        if part.get("category_id"):
            scopes.append(("category", part["category_id"]))

        for scope_type, scope_id in scopes:
            cursor = await self.db.execute(
                """SELECT sp.supplier_id, s.name AS supplier_name
                   FROM supplier_preferences sp
                   JOIN suppliers s ON s.id = sp.supplier_id
                   WHERE sp.scope_type = ? AND sp.scope_id = ?""",
                (scope_type, scope_id),
            )
            row = await cursor.fetchone()
            if row:
                return dict(row)

        return None

    # ── Private: Helpers ──────────────────────────────────────────

    async def _get_part(self, part_id: int) -> dict | None:
        """Fetch a part by ID."""
        cursor = await self.db.execute("SELECT * FROM parts WHERE id = ?", (part_id,))
        return await cursor.fetchone()

    async def _get_available_qty(
        self, part_id: int, location_type: str, location_id: int
    ) -> int:
        """Get total available qty for a part at a location (all suppliers)."""
        cursor = await self.db.execute(
            """SELECT COALESCE(SUM(qty), 0) AS total FROM stock
               WHERE part_id = ? AND location_type = ? AND location_id = ?""",
            (part_id, location_type, location_id),
        )
        row = await cursor.fetchone()
        return row["total"] if row else 0

    async def _get_supplier_name(self, supplier_id: int) -> str | None:
        """Look up a supplier's name."""
        cursor = await self.db.execute(
            "SELECT name FROM suppliers WHERE id = ?", (supplier_id,)
        )
        row = await cursor.fetchone()
        return row["name"] if row else None

    # ── Private: Post-Move Side Effects ───────────────────────────

    async def _update_forecast(self, part_id: int) -> None:
        """Recalculate forecast fields for a part after a movement.

        Updates: forecast_adu_30, forecast_days_until_low, forecast_suggested_order.
        """
        try:
            # Calculate ADU (Average Daily Usage) from last 30 days of consumption movements
            cursor = await self.db.execute(
                """SELECT COALESCE(SUM(qty), 0) AS consumed
                   FROM stock_movements
                   WHERE part_id = ? AND movement_type IN ('consume', 'transfer')
                     AND to_location_type IN ('job', 'truck')
                     AND created_at >= datetime('now', '-30 days')""",
                (part_id,),
            )
            row = await cursor.fetchone()
            consumed_30 = row["consumed"] if row else 0
            adu_30 = consumed_30 / 30.0

            # 90-day ADU
            cursor = await self.db.execute(
                """SELECT COALESCE(SUM(qty), 0) AS consumed
                   FROM stock_movements
                   WHERE part_id = ? AND movement_type IN ('consume', 'transfer')
                     AND to_location_type IN ('job', 'truck')
                     AND created_at >= datetime('now', '-90 days')""",
                (part_id,),
            )
            row = await cursor.fetchone()
            consumed_90 = row["consumed"] if row else 0
            adu_90 = consumed_90 / 90.0

            # Current warehouse stock
            cursor = await self.db.execute(
                """SELECT COALESCE(SUM(qty), 0) AS wh_qty FROM stock
                   WHERE part_id = ? AND location_type = 'warehouse'""",
                (part_id,),
            )
            row = await cursor.fetchone()
            wh_qty = row["wh_qty"] if row else 0

            # Part targets
            part = await self._get_part(part_id)
            if not part:
                return

            min_level = part.get("min_stock_level") or 0
            target_level = part.get("target_stock_level") or 0

            # Days until low (using 30-day ADU)
            if adu_30 > 0:
                days_until_low = max(-1, int((wh_qty - min_level) / adu_30))
            elif wh_qty <= min_level:
                days_until_low = -1
            else:
                days_until_low = 999

            # Suggested order qty
            if wh_qty < target_level:
                suggested_order = target_level - wh_qty
            else:
                suggested_order = 0

            # Reorder point (min + 7 days of usage buffer)
            reorder_point = min_level + int(adu_30 * 7)

            await self.db.execute(
                """UPDATE parts SET
                       forecast_adu_30 = ?,
                       forecast_adu_90 = ?,
                       forecast_days_until_low = ?,
                       forecast_suggested_order = ?,
                       forecast_reorder_point = ?,
                       forecast_target_qty = ?,
                       forecast_last_run = datetime('now')
                   WHERE id = ?""",
                (adu_30, adu_90, days_until_low, suggested_order, reorder_point, target_level, part_id),
            )
            await self.db.commit()
        except Exception as e:
            logger.warning("Forecast update failed for part %d: %s", part_id, e)

    async def _check_low_stock(self, part_id: int) -> None:
        """If part dropped below min, create a pending spot-check task."""
        try:
            part = await self._get_part(part_id)
            if not part:
                return

            # Skip winding-down items (target = 0)
            target = part.get("target_stock_level") or 0
            if target == 0:
                return

            min_level = part.get("min_stock_level") or 0
            if min_level <= 0:
                return

            # Check current warehouse qty
            cursor = await self.db.execute(
                """SELECT COALESCE(SUM(qty), 0) AS wh_qty FROM stock
                   WHERE part_id = ? AND location_type = 'warehouse'""",
                (part_id,),
            )
            row = await cursor.fetchone()
            wh_qty = row["wh_qty"] if row else 0

            if wh_qty < min_level:
                # Check if there's already a pending spot-check for this part
                cursor = await self.db.execute(
                    """SELECT 1 FROM audits a
                       JOIN audit_items ai ON ai.audit_id = a.id
                       WHERE a.audit_type = 'spot_check'
                         AND a.status IN ('in_progress', 'paused')
                         AND ai.part_id = ?
                       LIMIT 1""",
                    (part_id,),
                )
                existing = await cursor.fetchone()
                if existing:
                    return  # Already has a pending spot check

                # Create a 1-item spot-check audit
                cursor = await self.db.execute(
                    """INSERT INTO audits
                           (audit_type, location_type, location_id, started_by,
                            total_items, notes)
                       VALUES ('spot_check', 'warehouse', 1, 1,
                               1, ?)""",
                    (f"Auto-created: {part['name']} dropped below minimum ({wh_qty} < {min_level})",),
                )
                audit_id = cursor.lastrowid

                await self.db.execute(
                    """INSERT INTO audit_items (audit_id, part_id, expected_qty)
                       VALUES (?, ?, ?)""",
                    (audit_id, part_id, wh_qty),
                )
                await self.db.commit()
                logger.info(
                    "Created spot-check audit %d for part %d (%s) — below min stock",
                    audit_id, part_id, part["name"],
                )
        except Exception as e:
            logger.warning("Low stock check failed for part %d: %s", part_id, e)
