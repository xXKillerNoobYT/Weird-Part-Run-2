"""
Application configuration loaded from environment variables.

All settings have sensible defaults for local development.
Production deployments should override SECRET_KEY at minimum.
"""

from __future__ import annotations

import json
from pathlib import Path
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Global application settings. Loaded from .env file and environment variables."""

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

    # ── Paths ─────────────────────────────────────────────────────
    @property
    def migrations_dir(self) -> Path:
        """Directory containing SQL migration files."""
        return Path(__file__).parent / "migrations"

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        # Look for .env in backend/ directory and project root
        extra = "ignore"


# Singleton instance — import this everywhere
settings = Settings()
