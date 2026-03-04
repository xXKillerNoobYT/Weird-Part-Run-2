/**
 * Settings API functions — theme, app configuration, and company profiles.
 */

import apiClient from './client';
import type {
  ApiResponse,
  StatusMessage,
  ThemeSettings,
  CompanyProfile,
  CompanyProfileCreate,
  CompanyProfileUpdate,
} from '../lib/types';

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
    '/settings',
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


// ── Company Profiles ────────────────────────────────────────────

/** List all company profiles / branches. */
export async function listCompanyProfiles(): Promise<CompanyProfile[]> {
  const { data } = await apiClient.get<ApiResponse<CompanyProfile[]>>(
    '/settings/company-profiles',
  );
  return data.data ?? [];
}

/** Get a single company profile by ID. */
export async function getCompanyProfile(id: number): Promise<CompanyProfile> {
  const { data } = await apiClient.get<ApiResponse<CompanyProfile>>(
    `/settings/company-profiles/${id}`,
  );
  return data.data!;
}

/** Create a new company profile / branch. */
export async function createCompanyProfile(
  profile: CompanyProfileCreate,
): Promise<{ id: number }> {
  const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
    '/settings/company-profiles',
    profile,
  );
  return data.data!;
}

/** Update an existing company profile. */
export async function updateCompanyProfile(
  id: number,
  profile: CompanyProfileUpdate,
): Promise<StatusMessage> {
  const { data } = await apiClient.put<ApiResponse<StatusMessage>>(
    `/settings/company-profiles/${id}`,
    profile,
  );
  return data.data!;
}

/** Delete a company profile. */
export async function deleteCompanyProfile(id: number): Promise<StatusMessage> {
  const { data } = await apiClient.delete<ApiResponse<StatusMessage>>(
    `/settings/company-profiles/${id}`,
  );
  return data.data!;
}
