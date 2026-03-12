"""
Application configuration loaded from environment variables.

All settings have sensible defaults for local development.
Production deployments should override SECRET_KEY at minimum.

Path resolution:
    .env file  → resolved from config.py's location (…/backend/app/config.py)
                 up to project root, so it works regardless of CWD.
    DATABASE_PATH → relative paths resolve from backend/ directory via db_path.
"""

from __future__ import annotations

import json
from pathlib import Path
from pydantic import ConfigDict
from pydantic_settings import BaseSettings

# Resolve once at import time: config.py → app/ → backend/ → project root
_THIS_FILE = Path(__file__).resolve()
_BACKEND_DIR = _THIS_FILE.parent.parent          # backend/
_PROJECT_ROOT = _BACKEND_DIR.parent               # project root (contains .env)


class Settings(BaseSettings):
    """Global application settings. Loaded from .env file and environment variables."""

    model_config = ConfigDict(
        env_file=str(_PROJECT_ROOT / ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # ── App Identity ──────────────────────────────────────────────
    APP_NAME: str = "Wired-Part"
    APP_VERSION: str = "0.1.0"

    # ── Database ──────────────────────────────────────────────────
    # Path to the SQLite database file (relative to backend/ or absolute)
    DATABASE_PATH: str = "./wiredpart.db"

    # ── Security ──────────────────────────────────────────────────
    SECRET_KEY: str = "dev-secret-change-in-production-abc123xyz"
    PIN_HASH_ROUNDS: int = 12
    DEFAULT_ADMIN_PIN: str = "1234"

    # JWT token expiration (seconds)
    ACCESS_TOKEN_EXPIRE_SECONDS: int = 86400  # 24 hours for device auto-login
    PIN_TOKEN_EXPIRE_SECONDS: int = 300       # 5 minutes for sensitive actions

    # ── CORS ──────────────────────────────────────────────────────
    # JSON-encoded list of allowed origins
    CORS_ORIGINS: str = '["http://localhost:5173","http://127.0.0.1:5173"]'

    @property
    def cors_origins_list(self) -> list[str]:
        """Parse CORS_ORIGINS from JSON string to list."""
        try:
            return json.loads(self.CORS_ORIGINS)
        except (json.JSONDecodeError, TypeError):
            return ["http://localhost:5173"]

    # ── Server ────────────────────────────────────────────────────
    BACKEND_HOST: str = "0.0.0.0"
    BACKEND_PORT: int = 8000

    # ── Email / SMTP ──────────────────────────────────────────────
    # Set EMAIL_ENABLED=true and configure SMTP_* to enable email sending.
    # When disabled, "Send Email" buttons show but prompt to configure first.
    EMAIL_ENABLED: bool = False
    SMTP_HOST: str = ""
    SMTP_PORT: int = 587
    SMTP_USER: str = ""
    SMTP_PASSWORD: str = ""
    SMTP_USE_TLS: bool = True
    EMAIL_FROM: str = ""           # e.g. "orders@mycompany.com"
    EMAIL_FROM_NAME: str = ""      # e.g. "Wired-Part Orders"
    EMAIL_REPLY_TO: str = ""       # optional, defaults to EMAIL_FROM

    # ── Derived Paths ─────────────────────────────────────────────
    @property
    def db_path(self) -> Path:
        """Absolute path to the SQLite database file.

        If DATABASE_PATH is already absolute, return it as-is.
        If relative, resolve from the backend/ directory so it works
        no matter what the process CWD happens to be.
        """
        p = Path(self.DATABASE_PATH)
        if p.is_absolute():
            return p
        return (_BACKEND_DIR / p).resolve()

    @property
    def migrations_dir(self) -> Path:
        """Directory containing SQL migration files."""
        return Path(__file__).parent / "migrations"


# Singleton instance — import this everywhere
settings = Settings()
