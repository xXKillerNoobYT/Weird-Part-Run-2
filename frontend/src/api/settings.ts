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

// ── Warranty Settings ───────────────────────────────────────────

/** Get default warranty length in days from global settings. */
export async function getWarrantyLengthDays(): Promise<number> {
  const { data } = await apiClient.get<ApiResponse<{ key: string; value: string | null }>>(
    '/settings/warranty_length_days',
  );
  return data.data?.value ? parseInt(data.data.value, 10) : 365;
}

/** Update default warranty length in days. */
export async function updateWarrantyLengthDays(days: number): Promise<void> {
  await apiClient.put('/settings/warranty_length_days', {
    value: String(days),
  });
}
