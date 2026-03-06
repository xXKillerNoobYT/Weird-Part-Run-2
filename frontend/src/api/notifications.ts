/**
 * Notifications API functions — badge count, list, mark-read, preferences.
 *
 * The bell icon polls /badge every 30 seconds for unread count.
 * Full notification list is loaded on demand when the user opens the dropdown.
 */

import apiClient from './client';
import type { ApiResponse, StatusMessage } from '../lib/types';
import type {
  NotificationBadge,
  NotificationListResponse,
  NotificationMarkRead,
  NotificationPreference,
  NotificationPreferenceResponse,
  NotificationSoundSetting,
  NotificationSoundSettingsResponse,
} from '../lib/types';


// =================================================================
// BADGE (polled by NotificationBell component)
// =================================================================

/** Get unread count for the bell icon badge */
export async function getNotificationBadge(): Promise<NotificationBadge> {
  const { data } = await apiClient.get<ApiResponse<NotificationBadge>>(
    '/notifications/badge'
  );
  return data.data!;
}


// =================================================================
// NOTIFICATION LIST
// =================================================================

/** Get paginated notifications for the current user */
export async function listNotifications(params?: {
  unread_only?: boolean;
  limit?: number;
  offset?: number;
}): Promise<NotificationListResponse> {
  const { data } = await apiClient.get<ApiResponse<NotificationListResponse>>(
    '/notifications',
    { params }
  );
  return data.data!;
}

/** Mark specific notifications as read (or all) */
export async function markNotificationsRead(
  payload: NotificationMarkRead
): Promise<StatusMessage> {
  const { data } = await apiClient.post<ApiResponse<StatusMessage>>(
    '/notifications/read',
    payload
  );
  return data.data!;
}


// =================================================================
// NOTIFICATION PREFERENCES
// =================================================================

/** Get notification preferences for the current user */
export async function getNotificationPreferences(): Promise<NotificationPreferenceResponse> {
  const { data } = await apiClient.get<ApiResponse<NotificationPreferenceResponse>>(
    '/notifications/preferences'
  );
  return data.data!;
}

/** Update notification preferences (batch) */
export async function updateNotificationPreferences(
  preferences: NotificationPreference[]
): Promise<StatusMessage> {
  const { data } = await apiClient.put<ApiResponse<StatusMessage>>(
    '/notifications/preferences',
    { preferences }
  );
  return data.data!;
}


// =================================================================
// SOUND SETTINGS (Phase 7E)
// =================================================================

/** Get per-type sound settings for the current user */
export async function getNotificationSoundSettings(): Promise<NotificationSoundSettingsResponse> {
  const { data } = await apiClient.get<ApiResponse<NotificationSoundSettingsResponse>>(
    '/notifications/sound-settings'
  );
  return data.data!;
}

/** Update sound settings (batch upsert) */
export async function updateNotificationSoundSettings(
  settings: NotificationSoundSetting[]
): Promise<StatusMessage> {
  const { data } = await apiClient.put<ApiResponse<StatusMessage>>(
    '/notifications/sound-settings',
    { settings }
  );
  return data.data!;
}
