/**
 * Notifications API functions — badge count, list, mark-read, preferences.
 *
 * The bell icon polls /badge every 30 seconds for unread count.
 * Full notification list is loaded on demand when the user opens the dropdown.
 */

import apiClient from './client';
import { adaptedRequest } from './adapter';
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
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<NotificationBadge>>(
        '/notifications/badge'
      );
      return data.data!;
    },
    async () => {
      const { getNotificationBadge } = await import('../local/services/notifications-service');
      return getNotificationBadge() as unknown as NotificationBadge;
    },
  );
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
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<NotificationListResponse>>(
        '/notifications',
        { params }
      );
      return data.data!;
    },
    async () => {
      const { listNotifications } = await import('../local/services/notifications-service');
      return listNotifications(params) as unknown as NotificationListResponse;
    },
  );
}

/** Mark specific notifications as read (or all) */
export async function markNotificationsRead(
  payload: NotificationMarkRead
): Promise<StatusMessage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<StatusMessage>>(
        '/notifications/read',
        payload
      );
      return data.data!;
    },
    async () => {
      const { markNotificationsRead } = await import('../local/services/notifications-service');
      return markNotificationsRead(payload) as unknown as StatusMessage;
    },
  );
}


// =================================================================
// NOTIFICATION PREFERENCES
// =================================================================

/** Get notification preferences for the current user */
export async function getNotificationPreferences(): Promise<NotificationPreferenceResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<NotificationPreferenceResponse>>(
        '/notifications/preferences'
      );
      return data.data!;
    },
    async () => {
      const { getNotificationPreferences } = await import('../local/services/notifications-service');
      return getNotificationPreferences() as unknown as NotificationPreferenceResponse;
    },
  );
}

/** Update notification preferences (batch) */
export async function updateNotificationPreferences(
  preferences: NotificationPreference[]
): Promise<StatusMessage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<StatusMessage>>(
        '/notifications/preferences',
        { preferences }
      );
      return data.data!;
    },
    async () => {
      const { updateNotificationPreferences } = await import('../local/services/notifications-service');
      return updateNotificationPreferences(preferences) as unknown as StatusMessage;
    },
  );
}


// =================================================================
// SOUND SETTINGS (Phase 7E)
// =================================================================

/** Get per-type sound settings for the current user */
export async function getNotificationSoundSettings(): Promise<NotificationSoundSettingsResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<NotificationSoundSettingsResponse>>(
        '/notifications/sound-settings'
      );
      return data.data!;
    },
    async () => {
      const { getNotificationSoundSettings } = await import('../local/services/notifications-service');
      return getNotificationSoundSettings() as unknown as NotificationSoundSettingsResponse;
    },
  );
}

/** Update sound settings (batch upsert) */
export async function updateNotificationSoundSettings(
  settings: NotificationSoundSetting[]
): Promise<StatusMessage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<StatusMessage>>(
        '/notifications/sound-settings',
        { settings }
      );
      return data.data!;
    },
    async () => {
      const { updateNotificationSoundSettings } = await import('../local/services/notifications-service');
      return updateNotificationSoundSettings(settings) as unknown as StatusMessage;
    },
  );
}
