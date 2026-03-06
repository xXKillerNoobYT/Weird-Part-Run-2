-- ═══════════════════════════════════════════════════════════════════
-- Migration 022 — Phase 7E: Quality of Life
--
-- 1. notification_sounds    — per-type audio preferences
-- 2. ALTER parts            — QR image URLs + completion flag
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Notification sound settings ──────────────────────────────
CREATE TABLE IF NOT EXISTS notification_sounds (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         INTEGER NOT NULL REFERENCES users(id),
    notification_type TEXT NOT NULL,
    sound_enabled   INTEGER DEFAULT 0,
    sound_file      TEXT    DEFAULT 'chime.mp3',
    UNIQUE(user_id, notification_type)
);

CREATE INDEX IF NOT EXISTS idx_notif_sounds_user
    ON notification_sounds(user_id);

-- ── 2. QR image columns on parts ────────────────────────────────
ALTER TABLE parts ADD COLUMN device_image_url TEXT;
ALTER TABLE parts ADD COLUMN box_image_url TEXT;
ALTER TABLE parts ADD COLUMN qr_images_complete INTEGER DEFAULT 0;
