/**
 * Settings API functions — theme and app configuration.
 */

import apiClient from './client';
import type { ApiResponse, ThemeSettings } from '../lib/types';

/** Get current theme settings. */
export async function getTheme(): Promise<ThemeSettings> {
  const { data } = await apiClient.get<ApiResponse<ThemeSettings>>(
    '/settings/theme',
  );
  return data.data!;
}

/** Update theme settings. */
export async function updateTheme(
  theme: ThemeSettings,
): Promise<ThemeSettings> {
  const { data } = await apiClient.put<ApiResponse<ThemeSettings>>(
    '/settings/theme',
    theme,
  );
  return data.data!;
}

/** Get all settings grouped by category (admin only). */
export async function getAllSettings(): Promise<Record<string, unknown>> {
  const { data } = await apiClient.get<ApiResponse<Record<string, unknown>>>(
    '/settings/',
  );
  return data.data ?? {};
}
