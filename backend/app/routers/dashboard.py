"""
Dashboard routes — KPI cards, fast drive list, and quick actions.

Provides:
  GET  /api/dashboard            → real KPI counts + quick actions + user context
  GET  /api/dashboard/fast-drive → driving destinations ranked by 30-day history
  POST /api/dashboard/fast-drive/start → log a trip leg (and optionally navigate)
"""

from __future__ import annotations

import logging
from datetime import date

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel

from app.database import get_db
from app.middleware.auth import require_permission, require_user
from app.models.common import ApiResponse
from app.services.mileage_service import MileageService
from app.services.people_service import PeopleService

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/dashboard", tags=["Dashboard"], redirect_slashes=False)


# ── Request / response models ────────────────────────────────


class FastDriveStartRequest(BaseModel):
    """Frontend sends the full leg info so the backend just logs it."""
    leg_type: str              # e.g. "shop_to_job", "home_to_shop"
    from_label: str            # "Shop", "Home", or job name
    to_label: str              # destination label
    estimated_miles: float | None = None
    to_job_id: int | None = None
    from_job_id: int | None = None


# ── Endpoints ─────────────────────────────────────────────────


@router.get("", response_model=ApiResponse[dict])
async def get_dashboard(user: dict = Depends(require_user), db=Depends(get_db)):
    """Get dashboard data — live KPI counts and quick actions."""

    # ── KPI queries ───────────────────────────────────────────
    async def _count(sql: str) -> int:
        """Run a COUNT query and return the scalar result."""
        try:
            cursor = await db.execute(sql)
            row = await cursor.fetchone()
            return row[0] if row else 0
        except Exception as exc:
            # Table may not exist yet (e.g. purchase_orders before migration 015)
            logger.debug("Dashboard KPI query failed: %s — %s", sql[:60], exc)
            return 0

    total_parts = await _count(
        "SELECT COUNT(*) FROM parts WHERE is_active = 1"
    )
    active_jobs = await _count(
        "SELECT COUNT(*) FROM jobs WHERE status IN ('active', 'in_progress')"
    )
    pending_orders = await _count(
        "SELECT COUNT(*) FROM purchase_orders WHERE status = 'pending'"
    )
    # Low stock = warehouse qty fell below part's min_stock_level
    low_stock = await _count("""
        SELECT COUNT(*) FROM (
            SELECT p.id
            FROM parts p
            JOIN stock s ON s.part_id = p.id AND s.location_type = 'warehouse'
            WHERE p.is_active = 1
              AND p.min_stock_level > 0
            GROUP BY p.id
            HAVING SUM(s.qty) < p.min_stock_level
        )
    """)

    return ApiResponse(
        data={
            "kpis": {
                "total_parts": total_parts,
                "active_jobs": active_jobs,
                "pending_orders": pending_orders,
                "low_stock_alerts": low_stock,
            },
            "quick_actions": [
                {"label": "New Job", "icon": "briefcase", "route": "/jobs/active"},
                {"label": "Create PO", "icon": "shopping-cart", "route": "/orders/purchase-orders/new"},
                {"label": "Stock Check", "icon": "search", "route": "/warehouse/inventory"},
                {"label": "Pull Parts", "icon": "arrow-right-left", "route": "/warehouse/staging"},
            ],
            "user_name": user["display_name"],
        },
    )


@router.get("/fast-drive", response_model=ApiResponse[dict])
async def get_fast_drive_context(
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Build the Fast Drive destination list for the current user.

    Returns the user's assigned vehicle, ranked destinations (top 3 by
    30-day trip frequency), and the full destination list (home, shop,
    all active jobs).
    """
    user_id = user["id"]

    # 1. Get active vehicle assignment
    cursor = await db.execute(
        """SELECT va.vehicle_id, va.is_take_home,
                  va.home_address_street, va.home_address_city,
                  va.home_address_state, va.home_address_zip,
                  va.home_to_shop_miles,
                  v.vehicle_name, v.vehicle_number
           FROM vehicle_assignments va
           JOIN vehicles v ON v.id = va.vehicle_id
           WHERE va.user_id = ?
                 AND (va.end_date IS NULL OR va.end_date >= date('now'))
           LIMIT 1""",
        (user_id,),
    )
    assignment = await cursor.fetchone()

    if not assignment:
        return ApiResponse(data={"has_vehicle": False})

    vehicle_id = assignment["vehicle_id"]
    vehicle_name = assignment["vehicle_name"]
    vehicle_number = assignment["vehicle_number"]

    # 2. Build destinations list
    destinations: list[dict] = []

    # 2a. Home (only if take-home is enabled and address exists)
    if assignment["is_take_home"] and assignment["home_address_street"]:
        addr_parts = [
            assignment["home_address_street"],
            assignment["home_address_city"],
            assignment["home_address_state"],
            assignment["home_address_zip"],
        ]
        home_addr = ", ".join(p for p in addr_parts if p)
        destinations.append({
            "type": "home",
            "label": "Home",
            "address": home_addr,
            "gps_lat": None,  # home GPS not stored in assignments
            "gps_lng": None,
            "miles_estimate": assignment["home_to_shop_miles"],
            "job_id": None,
            "trip_count_30d": 0,
        })

    # 2b. Primary shop location
    cursor = await db.execute(
        """SELECT name, address_street, address_city, address_state,
                  address_zip, gps_lat, gps_lng
           FROM warehouse_locations
           WHERE is_primary = 1 AND is_active = 1
           LIMIT 1"""
    )
    shop = await cursor.fetchone()
    if shop:
        addr_parts = [
            shop["address_street"],
            shop["address_city"],
            shop["address_state"],
            shop["address_zip"],
        ]
        shop_addr = ", ".join(p for p in addr_parts if p)
        destinations.append({
            "type": "shop",
            "label": shop["name"] or "Shop",
            "address": shop_addr if shop_addr else None,
            "gps_lat": shop["gps_lat"],
            "gps_lng": shop["gps_lng"],
            "miles_estimate": assignment["home_to_shop_miles"],
            "job_id": None,
            "trip_count_30d": 0,
        })

    # 2c. Active jobs
    cursor = await db.execute(
        """SELECT id, job_name, address_line1, city, state, zip,
                  gps_lat, gps_lng, distance_from_shop_miles
           FROM jobs
           WHERE status IN ('active', 'in_progress')
           ORDER BY job_name ASC"""
    )
    job_rows = await cursor.fetchall()
    for job in job_rows:
        addr_parts = [
            job["address_line1"],
            job["city"],
            job["state"],
            job["zip"],
        ]
        job_addr = ", ".join(p for p in addr_parts if p)
        destinations.append({
            "type": "job",
            "label": job["job_name"],
            "address": job_addr if job_addr else None,
            "gps_lat": job["gps_lat"],
            "gps_lng": job["gps_lng"],
            "miles_estimate": job["distance_from_shop_miles"],
            "job_id": job["id"],
            "trip_count_30d": 0,
        })

    # 3. Rank by 30-day trip frequency
    cursor = await db.execute(
        """SELECT vtl.to_label, COUNT(*) as trip_count
           FROM vehicle_trip_legs vtl
           JOIN vehicle_mileage_logs vml ON vml.id = vtl.mileage_log_id
           WHERE vml.driver_id = ?
             AND vml.log_date >= date('now', '-30 days')
           GROUP BY vtl.to_label
           ORDER BY trip_count DESC""",
        (user_id,),
    )
    freq_rows = await cursor.fetchall()
    freq_map = {r["to_label"]: r["trip_count"] for r in freq_rows}

    # Apply trip counts to destinations
    for dest in destinations:
        dest["trip_count_30d"] = freq_map.get(dest["label"], 0)

    # Sort by trip count descending for suggestions, take top 3
    ranked = sorted(destinations, key=lambda d: d["trip_count_30d"], reverse=True)
    suggested = ranked[:3]

    return ApiResponse(
        data={
            "has_vehicle": True,
            "vehicle_id": vehicle_id,
            "vehicle_name": vehicle_name,
            "vehicle_number": vehicle_number,
            "suggested": suggested,
            "all_destinations": destinations,
        },
    )


@router.post("/fast-drive/start", response_model=ApiResponse[dict])
async def start_drive(
    body: FastDriveStartRequest,
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Log a trip leg for the current user's vehicle.

    Creates (or reuses) today's mileage log and adds a single trip leg.
    The frontend handles GPS navigation — this endpoint just does the logging.
    """
    user_id = user["id"]

    # Get user's active vehicle assignment
    cursor = await db.execute(
        """SELECT va.vehicle_id
           FROM vehicle_assignments va
           WHERE va.user_id = ?
                 AND (va.end_date IS NULL OR va.end_date >= date('now'))
           LIMIT 1""",
        (user_id,),
    )
    assignment = await cursor.fetchone()
    if not assignment:
        raise ValueError("No active vehicle assignment found")

    vehicle_id = assignment["vehicle_id"]
    svc = MileageService(db)

    # Create or reuse today's mileage log
    today_str = date.today().isoformat()
    log = await svc.log_daily_mileage(
        vehicle_id=vehicle_id,
        driver_id=user_id,
        data={"log_date": today_str},
    )

    # Add single trip leg
    leg_data = {
        "leg_order": 1,  # will be re-ordered by bulk_insert if needed
        "leg_type": body.leg_type,
        "from_label": body.from_label,
        "to_label": body.to_label,
        "estimated_miles": body.estimated_miles,
        "to_job_id": body.to_job_id,
        "from_job_id": body.from_job_id,
    }

    leg_ids = await svc.add_trip_legs(log["id"], [leg_data])

    return ApiResponse(
        data={
            "mileage_log_id": log["id"],
            "trip_leg_id": leg_ids[0] if leg_ids else None,
        },
        message=f"Trip to {body.to_label} logged.",
    )


# ═════════════════════════════════════════════════════════════════
# CERT ALERTS
# ═════════════════════════════════════════════════════════════════


@router.get("/cert-alerts")
async def get_cert_alerts(
    days: int = Query(60, ge=1, le=365, description="Look-ahead window in days"),
    user: dict = Depends(require_permission("view_people")),
    db=Depends(get_db),
):
    """Get certifications expiring within the look-ahead window.

    Returns list of { user_id, user_name, cert_name, expiry_date, days_until_expiry }.
    Used by the dashboard cert alert card.
    """
    svc = PeopleService(db)
    alerts = await svc.get_cert_alerts(days=days)
    return ApiResponse(data=alerts, message=f"{len(alerts)} cert alerts")


# ═════════════════════════════════════════════════════════════════
# VEHICLE EXPIRY ALERTS
# ═════════════════════════════════════════════════════════════════


@router.get("/vehicle-alerts")
async def get_vehicle_expiry_alerts(
    days: int = Query(60, ge=1, le=365, description="Look-ahead window in days"),
    user: dict = Depends(require_user),
    db=Depends(get_db),
):
    """Get vehicles with insurance or registration expiring within the look-ahead window.

    Returns list of { vehicle_id, vehicle_name, vehicle_number, alert_type,
    expiry_date, days_until_expiry }. Used by the dashboard vehicle alert card.
    """
    cursor = await db.execute(
        """SELECT id, vehicle_name, vehicle_number,
                  insurance_expiry, registration_expiry
           FROM vehicles
           WHERE is_active = 1
             AND (
               (insurance_expiry IS NOT NULL
                AND insurance_expiry <= date('now', '+' || ? || ' days')
                AND insurance_expiry >= date('now', '-30 days'))
               OR
               (registration_expiry IS NOT NULL
                AND registration_expiry <= date('now', '+' || ? || ' days')
                AND registration_expiry >= date('now', '-30 days'))
             )
           ORDER BY COALESCE(insurance_expiry, registration_expiry) ASC""",
        (days, days),
    )
    rows = await cursor.fetchall()

    alerts = []
    from datetime import date as dt_date
    today = dt_date.today()

    for v in rows:
        for alert_type, field in [("insurance", "insurance_expiry"), ("registration", "registration_expiry")]:
            expiry = v[field]
            if not expiry:
                continue
            try:
                exp_date = dt_date.fromisoformat(expiry)
            except (ValueError, TypeError):
                continue
            days_until = (exp_date - today).days
            if days_until <= days and days_until >= -30:
                alerts.append({
                    "vehicle_id": v["id"],
                    "vehicle_name": v["vehicle_name"],
                    "vehicle_number": v["vehicle_number"],
                    "alert_type": alert_type,
                    "expiry_date": expiry,
                    "days_until_expiry": days_until,
                })

    alerts.sort(key=lambda a: a["days_until_expiry"])
    return ApiResponse(data=alerts, message=f"{len(alerts)} vehicle expiry alerts")
