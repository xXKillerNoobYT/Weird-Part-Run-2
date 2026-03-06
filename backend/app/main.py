"""
Wired-Part Backend — FastAPI Application Entry Point

This is the main application module. It:
1. Creates the FastAPI app with metadata and lifespan handler
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

import importlib
import logging
from contextlib import asynccontextmanager

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


# ── Lifespan (replaces deprecated on_event) ────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown logic for the application.

    Startup: run migrations, seed admin PIN, start scheduler.
    Shutdown: stop scheduler gracefully.
    """
    # ── STARTUP ─────────────────────────────────────────────────
    logger.info("=" * 60)
    logger.info("  %s v%s — Starting up", settings.APP_NAME, settings.APP_VERSION)
    logger.info("=" * 60)

    # 1. Run all pending database migrations
    await init_db()
    logger.info("Database initialized at: %s", settings.db_path)

    # 2. Seed the admin user's PIN hash (if still placeholder)
    await _seed_admin_pin()

    # 3. Start the background scheduler (midnight report generation)
    from app.scheduler import start_scheduler, catch_up_missed_reports
    start_scheduler()

    # 4. Catch up any missed daily reports (server may have been down at midnight)
    await catch_up_missed_reports()

    logger.info("Startup complete. API docs at /docs")

    yield  # ← Application runs here

    # ── SHUTDOWN ────────────────────────────────────────────────
    from app.scheduler import stop_scheduler
    stop_scheduler()
    logger.info("Shutdown complete.")


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
    lifespan=lifespan,
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


# ── Safe Router Registration ───────────────────────────────────────
# Each router is imported individually with error handling so a missing
# or broken module doesn't prevent the entire app from starting.

ROUTER_MODULES = [
    "app.routers.auth",
    "app.routers.app_settings",
    "app.routers.dashboard",
    "app.routers.parts",
    "app.routers.companions",
    "app.routers.warehouse",
    "app.routers.trucks",
    "app.routers.jobs",
    "app.routers.notebooks",
    "app.routers.orders",
    "app.routers.notifications",
    "app.routers.people",
    "app.routers.reports",
    "app.routers.costs",
    "app.routers.tools",
]

for _module_path in ROUTER_MODULES:
    try:
        _mod = importlib.import_module(_module_path)
        app.include_router(_mod.router)
        logger.debug("Router loaded: %s", _module_path)
    except (ImportError, AttributeError) as exc:
        logger.warning("Router skipped (%s): %s", _module_path, exc)


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
