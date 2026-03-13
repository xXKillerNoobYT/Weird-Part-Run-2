/**
 * Local Notifications Service — badge count, list, mark-read, preferences, sound settings.
 *
 * Mirrors the HTTP API in `src/api/notifications.ts` for offline use.
 * Supports: badge polling, paginated list, mark-read, preference toggles, sound settings.
 *
 * Source tables: migration 001_foundation (notifications, notification_preferences, settings)
 */

import { getDb } from '../db';

// ── Types ──────────────────────────────────────────────────────────

export interface NotificationCreate {
  user_id: number;
  type?: string;
  title: string;
  message?: string;
  body?: string;
  severity?: 'info' | 'warning' | 'error' | 'critical';
  source?: string;
  link?: string;
  entity_type?: string;
  entity_id?: number;
}

interface ListParams {
  unread_only?: boolean;
  limit?: number;
  offset?: number;
}

interface MarkReadPayload {
  all?: boolean;
  ids?: number[];
}

interface PreferenceInput {
  type: string;
  enabled: boolean;
  channels?: string[];
}

interface SoundSettingInput {
  type: string;
  sound: string;
  volume: number;
  enabled: boolean;
}

// ── Default preference types ───────────────────────────────────────

const DEFAULT_PREF_TYPES = [
  'order_update',
  'job_update',
  'system',
  'warehouse',
  'approval',
  'chat',
];

const DEFAULT_SOUND_TYPES = [
  'order_update',
  'job_update',
  'system',
  'warehouse',
  'approval',
  'chat',
];


// ═══════════════════════════════════════════════════════════════════
// BADGE
// ═══════════════════════════════════════════════════════════════════

/** Get unread notification count for the bell icon badge. */
export async function getNotificationBadge(userId: number) {
  const db = getDb();
  const result = await db.query(
    `SELECT COUNT(*) AS cnt FROM notifications WHERE user_id = ? AND is_read = 0`,
    [userId],
  );
  const count = result.values[0]?.cnt ?? 0;
  return { unread_count: Number(count) };
}


// ═══════════════════════════════════════════════════════════════════
// NOTIFICATION LIST
// ═══════════════════════════════════════════════════════════════════

/** Get paginated notifications for a user. */
export async function listNotifications(userId: number, params?: ListParams) {
  const db = getDb();
  const limit = params?.limit ?? 20;
  const offset = params?.offset ?? 0;
  const unreadOnly = params?.unread_only ?? false;

  const whereClauses = ['user_id = ?'];
  const queryParams: any[] = [userId];

  if (unreadOnly) {
    whereClauses.push('is_read = 0');
  }

  const where = whereClauses.join(' AND ');

  // Total count
  const countResult = await db.query(
    `SELECT COUNT(*) AS cnt FROM notifications WHERE ${where}`,
    queryParams,
  );
  const total = Number(countResult.values[0]?.cnt ?? 0);

  // Unread count (always full, ignoring unread_only filter)
  const unreadResult = await db.query(
    `SELECT COUNT(*) AS cnt FROM notifications WHERE user_id = ? AND is_read = 0`,
    [userId],
  );
  const unread_count = Number(unreadResult.values[0]?.cnt ?? 0);

  // Paginated rows
  const rows = await db.query(
    `SELECT * FROM notifications WHERE ${where} ORDER BY created_at DESC LIMIT ? OFFSET ?`,
    [...queryParams, limit, offset],
  );

  return {
    notifications: rows.values.map(normalizeNotification),
    total,
    unread_count,
  };
}

/** Normalize SQLite integer booleans to JS booleans for the frontend. */
function normalizeNotification(row: Record<string, any>) {
  return {
    ...row,
    is_read: row.is_read === 1 || row.is_read === true,
  };
}


// ═══════════════════════════════════════════════════════════════════
// MARK READ
// ═══════════════════════════════════════════════════════════════════

/** Mark notifications as read — all, or specific IDs. */
export async function markNotificationsRead(userId: number, payload: MarkReadPayload) {
  const db = getDb();

  if (payload.all) {
    await db.run(
      `UPDATE notifications SET is_read = 1 WHERE user_id = ? AND is_read = 0`,
      [userId],
    );
  } else if (payload.ids && payload.ids.length > 0) {
    const placeholders = payload.ids.map(() => '?').join(', ');
    await db.run(
      `UPDATE notifications SET is_read = 1 WHERE user_id = ? AND id IN (${placeholders})`,
      [userId, ...payload.ids],
    );
  }

  return { message: 'ok' };
}


// ═══════════════════════════════════════════════════════════════════
// NOTIFICATION PREFERENCES
// ═══════════════════════════════════════════════════════════════════

/** Get notification preferences for a user.  Uses the notification_preferences table. */
export async function getNotificationPreferences(userId: number) {
  const db = getDb();

  const result = await db.query(
    `SELECT notification_type, is_enabled FROM notification_preferences WHERE user_id = ?`,
    [userId],
  );

  // Build map of saved prefs
  const savedMap = new Map<string, boolean>();
  for (const row of result.values) {
    savedMap.set(row.notification_type, row.is_enabled === 1 || row.is_enabled === true);
  }

  // Merge with defaults — all enabled by default
  const preferences: { type: string; enabled: boolean; channels: string[] }[] =
    DEFAULT_PREF_TYPES.map((type) => ({
      type,
      enabled: savedMap.has(type) ? savedMap.get(type)! : true,
      channels: ['in_app'], // local-only supports in-app
    }));

  // Include any extra types saved but not in defaults
  for (const [type, enabled] of savedMap) {
    if (!DEFAULT_PREF_TYPES.includes(type)) {
      preferences.push({ type, enabled, channels: ['in_app'] });
    }
  }

  return { preferences };
}

/** Save notification preferences — upserts into notification_preferences table. */
export async function updateNotificationPreferences(
  userId: number,
  preferences: PreferenceInput[],
) {
  const db = getDb();

  for (const pref of preferences) {
    await db.run(
      `INSERT INTO notification_preferences (user_id, notification_type, is_enabled)
       VALUES (?, ?, ?)
       ON CONFLICT(user_id, notification_type) DO UPDATE SET is_enabled = excluded.is_enabled`,
      [userId, pref.type, pref.enabled ? 1 : 0],
    );
  }

  return { message: 'ok' };
}


// ═══════════════════════════════════════════════════════════════════
// SOUND SETTINGS (stored in settings table)
// ═══════════════════════════════════════════════════════════════════

/** Get per-type sound settings for a user.  Stored as JSON in the settings table. */
export async function getNotificationSoundSettings(userId: number) {
  const db = getDb();

  const prefix = `notification_sound_${userId}_`;
  const result = await db.query(
    `SELECT key, value FROM settings WHERE key LIKE ?`,
    [`${prefix}%`],
  );

  const settings: { type: string; sound: string; volume: number; enabled: boolean }[] = [];

  for (const row of result.values) {
    const type = (row.key as string).replace(prefix, '');
    try {
      const parsed = JSON.parse(row.value as string);
      settings.push({
        type,
        sound: parsed.sound ?? 'default',
        volume: parsed.volume ?? 0.5,
        enabled: parsed.enabled ?? true,
      });
    } catch {
      // Corrupted setting — skip
    }
  }

  // Fill defaults for any missing types
  const savedTypes = new Set(settings.map((s) => s.type));
  for (const type of DEFAULT_SOUND_TYPES) {
    if (!savedTypes.has(type)) {
      settings.push({ type, sound: 'default', volume: 0.5, enabled: true });
    }
  }

  return { settings };
}

/** Save per-type sound settings — upserts JSON into settings table. */
export async function updateNotificationSoundSettings(
  userId: number,
  settings: SoundSettingInput[],
) {
  const db = getDb();

  for (const s of settings) {
    const key = `notification_sound_${userId}_${s.type}`;
    const value = JSON.stringify({ sound: s.sound, volume: s.volume, enabled: s.enabled });

    await db.run(
      `INSERT INTO settings (key, value, category, updated_at)
       VALUES (?, ?, 'notification_sound', datetime('now'))
       ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now')`,
      [key, value],
    );
  }

  return { message: 'ok' };
}


// ═══════════════════════════════════════════════════════════════════
// CREATE NOTIFICATION (used by other local services)
// ═══════════════════════════════════════════════════════════════════

/** Insert a new local notification. Returns the new notification ID.
 *  Also fires an OS-level notification in Tauri mode. */
export async function createNotification(notification: NotificationCreate) {
  const db = getDb();

  const result = await db.run(
    `INSERT INTO notifications (user_id, type, title, message, body, severity, source, link, entity_type, entity_id, is_read, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, datetime('now'))`,
    [
      notification.user_id,
      notification.type ?? 'system',
      notification.title,
      notification.message ?? null,
      notification.body ?? null,
      notification.severity ?? 'info',
      notification.source ?? 'system',
      notification.link ?? null,
      notification.entity_type ?? null,
      notification.entity_id ?? null,
    ],
  );

  // Fire native OS notification in Tauri mode
  fireNativeNotification(notification.title, notification.message ?? notification.body);

  return { id: result.changes.lastId };
}


// ═══════════════════════════════════════════════════════════════════
// NATIVE OS NOTIFICATIONS (Tauri only)
// ═══════════════════════════════════════════════════════════════════

/**
 * Fire a native OS notification (macOS Notification Center / Windows toast).
 * No-op in browser mode. Non-blocking — errors are swallowed.
 */
async function fireNativeNotification(
  title: string,
  body?: string | null,
): Promise<void> {
  try {
    const { isTauri } = await import('../../lib/environment');
    if (!isTauri()) return;

    const {
      isPermissionGranted,
      requestPermission,
      sendNotification,
    } = await import('@tauri-apps/plugin-notification');

    let permitted = await isPermissionGranted();
    if (!permitted) {
      const result = await requestPermission();
      permitted = result === 'granted';
    }
    if (!permitted) return;

    sendNotification({ title, body: body ?? undefined });
  } catch {
    // Notification plugin unavailable or errored — proceed silently
  }
}
