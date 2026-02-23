"""
Data access layer (Repository pattern).

Each repository handles CRUD operations for a specific domain entity.
Repositories accept an aiosqlite connection and return dicts or Pydantic models.
Business logic does NOT live here — that's in services/.
"""
