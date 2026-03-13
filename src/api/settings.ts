/**
 * Settings API functions — theme, app configuration, and company profiles.
 */

import apiClient from './client';
import { adaptedRequest } from './adapter';
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
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ThemeSettings>>(
        '/settings/theme',
      );
      return data.data!;
    },
    async () => {
      const { getTheme } = await import('../local/services/settings-service');
      return getTheme() as unknown as ThemeSettings;
    },
  );
}

/** Update theme settings. */
export async function updateTheme(
  theme: ThemeSettings,
): Promise<ThemeSettings> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<ThemeSettings>>(
        '/settings/theme',
        theme,
      );
      return data.data!;
    },
    async () => {
      const { updateTheme } = await import('../local/services/settings-service');
      return updateTheme(theme) as unknown as ThemeSettings;
    },
  );
}

/** Get all settings grouped by category (admin only). */
export async function getAllSettings(): Promise<Record<string, unknown>> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<Record<string, unknown>>>(
        '/settings',
      );
      return data.data ?? {};
    },
    async () => {
      const { getAllSettings } = await import('../local/services/settings-service');
      return getAllSettings() as unknown as Record<string, unknown>;
    },
  );
}

// ── Generic key-value settings ──────────────────────────────────

/** Get a single setting by key. Returns null if not set. */
export async function getSetting(key: string): Promise<string | null> {
  return adaptedRequest(
    async () => {
      try {
        const { data } = await apiClient.get<ApiResponse<{ key: string; value: string | null }>>(
          `/settings/${key}`,
        );
        return data.data?.value ?? null;
      } catch {
        return null;
      }
    },
    async () => {
      const { getSetting } = await import('../local/services/settings-service');
      return getSetting(key) as unknown as string | null;
    },
  );
}

/** Update a single setting by key. */
export async function updateSetting(key: string, value: string, category = 'general'): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.put(`/settings/${key}`, { value, category });
    },
    async () => {
      const { updateSetting } = await import('../local/services/settings-service');
      await updateSetting(key, value, category);
    },
  );
}


// ── Warranty Settings ───────────────────────────────────────────

/** Get default warranty length in days from global settings. */
export async function getWarrantyLengthDays(): Promise<number> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<{ key: string; value: string | null }>>(
        '/settings/warranty_length_days',
      );
      return data.data?.value ? parseInt(data.data.value, 10) : 365;
    },
    async () => {
      const { getWarrantyLengthDays } = await import('../local/services/settings-service');
      return getWarrantyLengthDays() as unknown as number;
    },
  );
}

/** Update default warranty length in days. */
export async function updateWarrantyLengthDays(days: number): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.put('/settings/warranty_length_days', {
        value: String(days),
      });
    },
    async () => {
      const { updateWarrantyLengthDays } = await import('../local/services/settings-service');
      await updateWarrantyLengthDays(days);
    },
  );
}


// ── Company Profiles ────────────────────────────────────────────

/** List all company profiles / branches. */
export async function listCompanyProfiles(): Promise<CompanyProfile[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<CompanyProfile[]>>(
        '/settings/company-profiles',
      );
      return data.data ?? [];
    },
    async () => {
      const { listCompanyProfiles } = await import('../local/services/settings-service');
      return listCompanyProfiles() as unknown as CompanyProfile[];
    },
  );
}

/** Get a single company profile by ID. */
export async function getCompanyProfile(id: number): Promise<CompanyProfile> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<CompanyProfile>>(
        `/settings/company-profiles/${id}`,
      );
      return data.data!;
    },
    async () => {
      const { getCompanyProfile } = await import('../local/services/settings-service');
      return getCompanyProfile(id) as unknown as CompanyProfile;
    },
  );
}

/** Create a new company profile / branch. */
export async function createCompanyProfile(
  profile: CompanyProfileCreate,
): Promise<{ id: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
        '/settings/company-profiles',
        profile,
      );
      return data.data!;
    },
    async () => {
      const { createCompanyProfile } = await import('../local/services/settings-service');
      return createCompanyProfile(profile) as unknown as { id: number };
    },
  );
}

/** Update an existing company profile. */
export async function updateCompanyProfile(
  id: number,
  profile: CompanyProfileUpdate,
): Promise<StatusMessage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<StatusMessage>>(
        `/settings/company-profiles/${id}`,
        profile,
      );
      return data.data!;
    },
    async () => {
      const { updateCompanyProfile } = await import('../local/services/settings-service');
      return updateCompanyProfile(id, profile) as unknown as StatusMessage;
    },
  );
}

/** Delete a company profile. */
export async function deleteCompanyProfile(id: number): Promise<StatusMessage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.delete<ApiResponse<StatusMessage>>(
        `/settings/company-profiles/${id}`,
      );
      return data.data!;
    },
    async () => {
      const { deleteCompanyProfile } = await import('../local/services/settings-service');
      return deleteCompanyProfile(id) as unknown as StatusMessage;
    },
  );
}


// ── PDF Settings ────────────────────────────────────────────

/** Get PDF template/document settings (accent color, columns, footer, etc.). */
export async function getPDFSettings(): Promise<PDFSettings> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PDFSettings>>(
        '/settings/pdf',
      );
      return data.data!;
    },
    async () => {
      const { getPDFSettings } = await import('../local/services/settings-service');
      return getPDFSettings() as unknown as PDFSettings;
    },
  );
}

/** Update PDF template/document settings. */
export async function updatePDFSettings(
  settings: PDFSettings,
): Promise<PDFSettings> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<PDFSettings>>(
        '/settings/pdf',
        settings,
      );
      return data.data!;
    },
    async () => {
      const { updatePDFSettings } = await import('../local/services/settings-service');
      return updatePDFSettings(settings) as unknown as PDFSettings;
    },
  );
}


// ── Company Logo Upload ─────────────────────────────────────

/** Upload or replace the primary company logo. Returns the new logo path. */
export async function uploadCompanyLogo(
  file: File,
): Promise<{ logo_path: string; filename: string }> {
  return adaptedRequest(
    async () => {
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
    },
    async () => {
      const { uploadCompanyLogo } = await import('../local/services/settings-service');
      return uploadCompanyLogo(file) as unknown as { logo_path: string; filename: string };
    },
  );
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
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<BillingCycleSettings>>(
        '/settings/billing-cycle',
      );
      return data.data!;
    },
    async () => {
      const { getBillingCycle } = await import('../local/services/settings-service');
      return getBillingCycle() as unknown as BillingCycleSettings;
    },
  );
}

/** Update billing cycle configuration. */
export async function updateBillingCycle(
  settings: BillingCycleSettings,
): Promise<BillingCycleSettings> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<BillingCycleSettings>>(
        '/settings/billing-cycle',
        settings,
      );
      return data.data!;
    },
    async () => {
      const { updateBillingCycle } = await import('../local/services/settings-service');
      return updateBillingCycle(settings) as unknown as BillingCycleSettings;
    },
  );
}

/** Get pay period configuration. */
export async function getPayPeriod(): Promise<PayPeriodSettings> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PayPeriodSettings>>(
        '/settings/pay-period',
      );
      return data.data!;
    },
    async () => {
      const { getPayPeriod } = await import('../local/services/settings-service');
      return getPayPeriod() as unknown as PayPeriodSettings;
    },
  );
}

/** Update pay period configuration. */
export async function updatePayPeriod(
  settings: PayPeriodSettings,
): Promise<PayPeriodSettings> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<PayPeriodSettings>>(
        '/settings/pay-period',
        settings,
      );
      return data.data!;
    },
    async () => {
      const { updatePayPeriod } = await import('../local/services/settings-service');
      return updatePayPeriod(settings) as unknown as PayPeriodSettings;
    },
  );
}

/** Get customizable payroll export columns. */
export async function getPayrollColumns(): Promise<PayrollColumnConfig> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PayrollColumnConfig>>(
        '/settings/payroll-columns',
      );
      return data.data!;
    },
    async () => {
      const { getPayrollColumns } = await import('../local/services/settings-service');
      return getPayrollColumns() as unknown as PayrollColumnConfig;
    },
  );
}

/** Update customizable payroll export columns. */
export async function updatePayrollColumns(
  config: PayrollColumnConfig,
): Promise<PayrollColumnConfig> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<PayrollColumnConfig>>(
        '/settings/payroll-columns',
        config,
      );
      return data.data!;
    },
    async () => {
      const { updatePayrollColumns } = await import('../local/services/settings-service');
      return updatePayrollColumns(config) as unknown as PayrollColumnConfig;
    },
  );
}
