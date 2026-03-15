"""
Wired-Part Backend — FastAPI Application Entry Point

This is the main application module. It:
1. Creates the FastAPI app with metadata and lifespan handler
2. Configures CORS for frontend + Capacitor access
3. Runs database migrations on startup
4. Seeds the default admin user's PIN hash
5. Registers all API routers
6. Provides health check + server-info endpoints
7. Serves the built React frontend as static files (production)

Start with:
    Dev:  cd backend && uvicorn app.main:app --reload --port 8000
    Prod: cd backend && uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2 --log-level info
"""

from __future__ import annotations

import importlib
import logging
import os
import socket
from contextlib import asynccontextmanager
from logging.handlers import RotatingFileHandler
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from app.config import settings
from app.database import get_connection, init_db
from app.services.auth_service import hash_pin

# ── Paths ──────────────────────────────────────────────────────────
_BACKEND_DIR = Path(__file__).resolve().parent.parent
_FRONTEND_DIST = _BACKEND_DIR.parent / "dist"

# ── Logging ─────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s │ %(levelname)-8s │ %(name)s │ %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("wiredpart")

# Production file logging — rotating 10MB files, keep 5 backups
_LOG_DIR = _BACKEND_DIR / "logs"
try:
    _LOG_DIR.mkdir(parents=True, exist_ok=True)
    _file_handler = RotatingFileHandler(
        _LOG_DIR / "wiredpart.log", maxBytes=10_000_000, backupCount=5
    )
    _file_handler.setFormatter(
        logging.Formatter("%(asctime)s │ %(levelname)-8s │ %(name)s │ %(message)s")
    )
    logging.getLogger().addHandler(_file_handler)
except OSError:
    pass  # Skip file logging if logs directory can't be created (e.g. OneDrive)


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

    # 0. Auto-generate SECRET_KEY if still using the dev default
    _ensure_secret_key()

    # 1. Run all pending database migrations
    await init_db()
    logger.info("Database initialized at: %s", settings.db_path)

    # 2. Seed the admin user's PIN hash (if still placeholder)
    await _seed_admin_pin()

    # 3. Start the background scheduler (midnight report generation + backups)
    from app.scheduler import (
        start_scheduler, catch_up_missed_reports, schedule_backup_jobs_from_settings,
    )
    start_scheduler()

    # 4. Catch up any missed daily reports (server may have been down at midnight)
    await catch_up_missed_reports()

    # 5. Reschedule backup jobs from saved settings (enables/disables + custom times)
    await schedule_backup_jobs_from_settings()

    # 6. Log LAN access info for field device setup
    try:
        hostname = socket.gethostname()
        lan_ip = socket.gethostbyname(hostname)
        logger.info("LAN access: http://%s:%s", lan_ip, settings.BACKEND_PORT)
    except Exception:
        pass

    if _FRONTEND_DIST.exists():
        logger.info("Serving frontend from: %s", _FRONTEND_DIST)
    else:
        logger.info("No frontend build found — API-only mode")

    logger.info("Startup complete. API docs at /docs")

    yield  # ← Application runs here

    # ── SHUTDOWN ────────────────────────────────────────────────
    from app.scheduler import stop_scheduler
    stop_scheduler()
    logger.info("Shutdown complete.")


_DEV_SECRET = "dev-secret-change-in-production-abc123xyz"


def _ensure_secret_key():
    """Auto-generate a production SECRET_KEY if still using the dev default.

    On first startup, detects the placeholder dev key and replaces it with
    a cryptographically random 64-char hex token. The new key is:
    1. Written into .env so it persists across restarts
    2. Hot-patched onto the running settings instance

    This runs once, ever. After that, .env has a real key and this is a no-op.
    """
    import secrets
    import tempfile
    from app.config import _PROJECT_ROOT

    if settings.SECRET_KEY != _DEV_SECRET:
        return  # Already has a real key — nothing to do

    new_key = secrets.token_hex(32)  # 64 chars, 256-bit entropy
    env_path = _PROJECT_ROOT / ".env"

    # Update .env file (create if missing, replace if present)
    if env_path.exists():
        content = env_path.read_text(encoding="utf-8")
        if f"SECRET_KEY={_DEV_SECRET}" in content:
            content = content.replace(
                f"SECRET_KEY={_DEV_SECRET}",
                f"SECRET_KEY={new_key}",
            )
        elif "SECRET_KEY=" in content:
            # Key exists but with different formatting — replace the line
            import re
            content = re.sub(
                r"^SECRET_KEY=.*$", f"SECRET_KEY={new_key}", content, flags=re.MULTILINE
            )
        else:
            # SECRET_KEY not in .env at all — append it
            content = content.rstrip("\n") + f"\nSECRET_KEY={new_key}\n"
    else:
        # No .env file — create one with just the key
        content = f"SECRET_KEY={new_key}\n"

    # Write via temp file + rename to avoid OneDrive file-descriptor locks.
    # pathlib.write_text() fails with OSError(9) on OneDrive-synced dirs.
    try:
        env_path.write_text(content, encoding="utf-8")
    except OSError:
        # Fallback: atomic write via tempfile in the same directory
        fd, tmp_path = tempfile.mkstemp(
            dir=str(env_path.parent), suffix=".env.tmp"
        )
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(content)
            # os.replace is atomic on the same filesystem
            os.replace(tmp_path, str(env_path))
        except Exception:
            # Last resort: clean up temp file and skip .env writing
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
            logger.warning(
                "Could not write .env — SECRET_KEY will reset on next restart. "
                "Consider moving the project out of OneDrive."
            )

    # Hot-patch the running settings so this process uses the new key immediately
    object.__setattr__(settings, "SECRET_KEY", new_key)

    logger.info("Generated production SECRET_KEY (written to .env)")


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
# Includes dev origins + Capacitor native app origins for sync requests.
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
    "app.routers.contacts",
    "app.routers.scheduling",
    "app.routers.reports",
    "app.routers.costs",
    "app.routers.tools",
    "app.routers.chat",
    "app.routers.bootstrap",
    "app.routers.security",
    "app.routers.updates",
    "app.routers.sync",
    "app.routers.devices",
    "app.routers.backups",
    "app.routers.ai",
    "app.routers.remote_sync",
    "app.routers.supplier_portal",
    "app.routers.public",
    "app.routers.bluetooth",
]

for _module_path in ROUTER_MODULES:
    try:
        _mod = importlib.import_module(_module_path)
        app.include_router(_mod.router)
        logger.debug("Router loaded: %s", _module_path)
    except (ImportError, AttributeError) as exc:
        logger.warning("Router skipped (%s): %s", _module_path, exc)


# ── System Endpoints ───────────────────────────────────────────────
@app.get("/api/health", tags=["System"])
async def health_check():
    """Health check endpoint for monitoring and load balancers."""
    return {
        "status": "healthy",
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
    }


@app.get("/api/server-info", tags=["System"])
async def server_info(request: Request):
    """Return server info for mobile device setup and pairing.

    Mobile devices use this to discover the shop server URL.
    The shop can display a QR code with this info for easy setup.
    """
    try:
        hostname = socket.gethostname()
        local_ip = socket.gethostbyname(hostname)
    except Exception:
        hostname = "unknown"
        local_ip = "127.0.0.1"

    return {
        "hostname": hostname,
        "local_ip": local_ip,
        "port": settings.BACKEND_PORT,
        "url": f"http://{local_ip}:{settings.BACKEND_PORT}",
        "version": settings.APP_VERSION,
        "app": settings.APP_NAME,
    }


# ── Static File Serving (Production) ──────────────────────────────
# When frontend/dist/ exists (after `npm run build`), serve it from
# FastAPI so the shop computer needs only one process.
# API routes are registered above, so they always take priority.

if _FRONTEND_DIST.exists():
    # Serve Vite's hashed assets (JS, CSS, fonts, images)
    _assets_dir = _FRONTEND_DIST / "assets"
    if _assets_dir.exists():
        app.mount("/assets", StaticFiles(directory=str(_assets_dir)), name="assets")

    # Serve specific well-known files
    @app.get("/manifest.json", tags=["System"], include_in_schema=False)
    async def serve_manifest():
        manifest_path = _FRONTEND_DIST / "manifest.json"
        if manifest_path.is_file():
            return FileResponse(manifest_path)
        return {"error": "manifest.json not found"}

    @app.get("/favicon.ico", tags=["System"], include_in_schema=False)
    async def serve_favicon():
        favicon_path = _FRONTEND_DIST / "favicon.ico"
        if favicon_path.is_file():
            return FileResponse(favicon_path)
        # Fall back to SVG
        svg_path = _FRONTEND_DIST / "vite.svg"
        if svg_path.is_file():
            return FileResponse(svg_path)
        return FileResponse(_FRONTEND_DIST / "index.html")

    # SPA catch-all — MUST be last. Returns index.html for client-side routing.
    @app.get("/{full_path:path}", include_in_schema=False)
    async def spa_catchall(full_path: str):
        """Serve the React SPA for any non-API route.

        Checks if the path matches an actual file in dist/ first
        (images, fonts, etc.), otherwise returns index.html so
        React Router can handle the route client-side.
        """
        # Prevent path traversal
        if ".." in full_path:
            return FileResponse(_FRONTEND_DIST / "index.html")

        file_path = _FRONTEND_DIST / full_path
        if file_path.is_file():
            return FileResponse(file_path)
        return FileResponse(_FRONTEND_DIST / "index.html")
else:
    # No frontend build — show API info at root
    @app.get("/", tags=["System"])
    async def root():
        """Root — shows API info when no frontend build is present."""
        return {
            "app": settings.APP_NAME,
            "version": settings.APP_VERSION,
            "docs": "/docs",
            "health": "/api/health",
            "note": "No frontend build found. Run 'cd frontend && npm run build' to serve the UI.",
        }
