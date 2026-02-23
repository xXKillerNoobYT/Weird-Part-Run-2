"""
Wired-Part Backend — FastAPI Application Entry Point

This is the main application module. It:
1. Creates the FastAPI app with metadata
2. Configures CORS for frontend access
3. Runs database migrations on startup
4. Seeds the default admin user's PIN hash
5. Registers all API routers (auth, settings, and module stubs)
6. Provides a health check endpoint

Start with:
    cd backend
    uvicorn app.main:app --reload --port 8000
"""

from __future__ import annotations

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.database import get_connection, init_db
from app.services.auth_service import hash_pin

# ── Logging ─────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s │ %(levelname)-8s │ %(name)s │ %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("wiredpart")


# ── App Creation ────────────────────────────────────────────────────
app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description=(
        "Wired-Part: Field service management for electrical contractors. "
        "Parts inventory, warehouse ops, truck management, job tracking, "
        "labor hours, procurement, and pre-billing exports."
    ),
    docs_url="/docs",
    redoc_url="/redoc",
)


# ── CORS ────────────────────────────────────────────────────────────
# Allow the React frontend (localhost:5173) to call the API.
# In production, restrict this to the actual domain.
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Startup Event ───────────────────────────────────────────────────
@app.on_event("startup")
async def startup():
    """Run database migrations and seed data on application startup."""
    logger.info("=" * 60)
    logger.info("  %s v%s — Starting up", settings.APP_NAME, settings.APP_VERSION)
    logger.info("=" * 60)

    # 1. Run all pending database migrations
    await init_db()
    logger.info("Database initialized at: %s", settings.DATABASE_PATH)

    # 2. Seed the admin user's PIN hash (if still placeholder)
    await _seed_admin_pin()

    logger.info("Startup complete. API docs at /docs")


async def _seed_admin_pin():
    """Replace the placeholder PIN hash with a real bcrypt hash.

    The migration seeds '__PLACEHOLDER_HASH__' because we can't run
    bcrypt inside SQLite. On first startup, we hash the default PIN
    and update the row.
    """
    db = await get_connection()
    try:
        cursor = await db.execute(
            "SELECT id, pin_hash FROM users WHERE id = 1"
        )
        admin = await cursor.fetchone()

        if admin and admin["pin_hash"] == "__PLACEHOLDER_HASH__":
            real_hash = hash_pin(settings.DEFAULT_ADMIN_PIN)
            await db.execute(
                "UPDATE users SET pin_hash = ? WHERE id = 1",
                (real_hash,),
            )
            await db.commit()
            logger.info("Admin PIN hash seeded (default PIN: %s)", settings.DEFAULT_ADMIN_PIN)
    finally:
        await db.close()


# ── Routers ─────────────────────────────────────────────────────────
# Import and register all route modules.
# Auth + Settings are functional in Phase 1.
# All others return stub responses until their phase.

from app.routers import (  # noqa: E402
    auth,
    app_settings,
    dashboard,
    parts,
    warehouse,
    trucks,
    jobs,
    orders,
    people,
    reports,
)

app.include_router(auth.router)
app.include_router(app_settings.router)
app.include_router(dashboard.router)
app.include_router(parts.router)
app.include_router(warehouse.router)
app.include_router(trucks.router)
app.include_router(jobs.router)
app.include_router(orders.router)
app.include_router(people.router)
app.include_router(reports.router)


# ── Health Check ────────────────────────────────────────────────────
@app.get("/api/health", tags=["System"])
async def health_check():
    """Health check endpoint for monitoring and load balancers."""
    return {
        "status": "healthy",
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
    }


@app.get("/", tags=["System"])
async def root():
    """Root redirect — shows API info."""
    return {
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "docs": "/docs",
        "health": "/api/health",
    }
