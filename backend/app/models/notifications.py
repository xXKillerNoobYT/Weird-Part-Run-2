"""
Pydantic models for the cross-module notification system.

Notifications are persisted in the DB with 30-day auto-cleanup.
Each user can customize which notification types they receive,
tied to the hat/role system with defaults OFF.
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


# ═══════════════════════════════════════════════════════════════
# Notification Models
# ═══════════════════════════════════════════════════════════════

class NotificationResponse(BaseModel):
    """A notification in API responses."""
    id: int
    user_id: int
    type: str
    title: str
    message: str | None = None
    link: str | None = None
    entity_type: str | None = None
    entity_id: int | None = None
    is_read: bool = False
    created_at: datetime | None = None


class NotificationListResponse(BaseModel):
    """Paginated notifications list."""
    items: list[NotificationResponse] = Field(default_factory=list)
    total: int = 0
    unread_count: int = 0


class NotificationCreate(BaseModel):
    """Create a notification (internal use by services)."""
    user_id: int
    type: str
    title: str
    message: str | None = None
    link: str | None = None
    entity_type: str | None = None
    entity_id: int | None = None


class NotificationMarkRead(BaseModel):
    """Mark one or more notifications as read."""
    notification_ids: list[int] = Field(default_factory=list)
    mark_all: bool = False


# ═══════════════════════════════════════════════════════════════
# Notification Preference Models
# ═══════════════════════════════════════════════════════════════

class NotificationPreference(BaseModel):
    """A single notification preference."""
    notification_type: str
    is_enabled: bool = False


class NotificationPreferenceUpdate(BaseModel):
    """Update notification preferences (batch)."""
    preferences: list[NotificationPreference]


class NotificationPreferenceResponse(BaseModel):
    """All preferences for a user."""
    user_id: int
    preferences: list[NotificationPreference] = Field(default_factory=list)


# ═══════════════════════════════════════════════════════════════
# Notification Badge/Count Models
# ═══════════════════════════════════════════════════════════════

class NotificationBadge(BaseModel):
    """Unread count for the bell icon badge."""
    unread_count: int = 0
    has_urgent: bool = False


# ═══════════════════════════════════════════════════════════════
# Sound Preference Models (Phase 7E)
# ═══════════════════════════════════════════════════════════════

class NotificationSoundSetting(BaseModel):
    """A single notification type's sound setting."""
    notification_type: str
    sound_enabled: bool = False
    sound_file: str = "chime.mp3"


class NotificationSoundSettingsResponse(BaseModel):
    """All sound settings for a user."""
    user_id: int
    settings: list[NotificationSoundSetting] = Field(default_factory=list)


class NotificationSoundSettingsUpdate(BaseModel):
    """Update sound settings (batch)."""
    settings: list[NotificationSoundSetting]
