/**
 * Settings API functions — theme, app configuration, and company profiles.
 */

import apiClient from './client';
import type {
  ApiResponse,
  StatusMessage,
  ThemeSettings,
  PDFSettings,
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

// ── Generic key-value settings ──────────────────────────────────

/** Get a single setting by key. Returns null if not set. */
export async function getSetting(key: string): Promise<string | null> {
  try {
    const { data } = await apiClient.get<ApiResponse<{ key: string; value: string | null }>>(
      `/settings/${key}`,
    );
    return data.data?.value ?? null;
  } catch {
    return null;
  }
}

/** Update a single setting by key. */
export async function updateSetting(key: string, value: string, category = 'general'): Promise<void> {
  await apiClient.put(`/settings/${key}`, { value, category });
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


// ── PDF Settings ────────────────────────────────────────────

/** Get PDF template/document settings (accent color, columns, footer, etc.). */
export async function getPDFSettings(): Promise<PDFSettings> {
  const { data } = await apiClient.get<ApiResponse<PDFSettings>>(
    '/settings/pdf',
  );
  return data.data!;
}

/** Update PDF template/document settings. */
export async function updatePDFSettings(
  settings: PDFSettings,
): Promise<PDFSettings> {
  const { data } = await apiClient.put<ApiResponse<PDFSettings>>(
    '/settings/pdf',
    settings,
  );
  return data.data!;
}


// ── Company Logo Upload ─────────────────────────────────────

/** Upload or replace the primary company logo. Returns the new logo path. */
export async function uploadCompanyLogo(
  file: File,
): Promise<{ logo_path: string; filename: string }> {
  const formData = new FormData();
  formData.append('file', file);

  const { data } = await apiClient.post<
    ApiResponse<{ logo_path: string; filename: string }>
  >(
    '/settings/company-logo',
    formData,
    { headers: { 'Content-Type': 'multipart/form-data' } },
  );
  return data.data!;
}


// ── Billing Cycle & Pay Period Settings ─────────────────────────

export interface BillingCycleSettings {
  cycle_type: string;
  start_day: number;
}

export interface PayPeriodSettings {
  period_type: string;
  start_day: number;
}

export interface PayrollColumnConfig {
  columns: string[];
}

/** Get billing cycle configuration. */
export async function getBillingCycle(): Promise<BillingCycleSettings> {
  const { data } = await apiClient.get<ApiResponse<BillingCycleSettings>>(
    '/settings/billing-cycle',
  );
  return data.data!;
}

/** Update billing cycle configuration. */
export async function updateBillingCycle(
  settings: BillingCycleSettings,
): Promise<BillingCycleSettings> {
  const { data } = await apiClient.put<ApiResponse<BillingCycleSettings>>(
    '/settings/billing-cycle',
    settings,
  );
  return data.data!;
}

/** Get pay period configuration. */
export async function getPayPeriod(): Promise<PayPeriodSettings> {
  const { data } = await apiClient.get<ApiResponse<PayPeriodSettings>>(
    '/settings/pay-period',
  );
  return data.data!;
}

/** Update pay period configuration. */
export async function updatePayPeriod(
  settings: PayPeriodSettings,
): Promise<PayPeriodSettings> {
  const { data } = await apiClient.put<ApiResponse<PayPeriodSettings>>(
    '/settings/pay-period',
    settings,
  );
  return data.data!;
}

/** Get customizable payroll export columns. */
export async function getPayrollColumns(): Promise<PayrollColumnConfig> {
  const { data } = await apiClient.get<ApiResponse<PayrollColumnConfig>>(
    '/settings/payroll-columns',
  );
  return data.data!;
}

/** Update customizable payroll export columns. */
export async function updatePayrollColumns(
  config: PayrollColumnConfig,
): Promise<PayrollColumnConfig> {
  const { data } = await apiClient.put<ApiResponse<PayrollColumnConfig>>(
    '/settings/payroll-columns',
    config,
  );
  return data.data!;
}
