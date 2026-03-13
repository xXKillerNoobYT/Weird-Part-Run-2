/**
 * Cost Tracking & Analytics API — Phase 7D.
 *
 * Endpoints for:
 *   - Company cost settings (margins, cost method)
 *   - Per-part cost layers, history, and margin management
 *   - Spending dashboard (summary, supplier/category/job breakdowns, trends)
 *   - Job cost rollup and budget status
 *   - Price variance reports and budget alerts
 *   - Daily report (live dashboard data)
 */

import apiClient from './client';
import { adaptedRequest } from './adapter';
import type {
  ApiResponse,
  BudgetAlert,
  CategorySpend,
  CompanySetting,
  CostHistoryPoint,
  CostLayer,
  DailyReportData,
  JobCostRollup,
  JobSpend,
  PartCostSummary,
  PriceVarianceItem,
  SpendingSummary,
  SpendingTrendPoint,
  SupplierSpend,
} from '../lib/types';


// ── Company Cost Settings ─────────────────────────────────────────

/** Get all company cost settings. */
export async function getCompanySettings(): Promise<CompanySetting[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<CompanySetting[]>>(
        '/costs/settings',
      );
      return data.data!;
    },
    async () => {
      const { getCompanySettings } = await import('../local/services/costs-service');
      return getCompanySettings() as unknown as CompanySetting[];
    },
  );
}

/** Update a company cost setting. */
export async function updateCompanySetting(
  key: string,
  settingValue: string,
): Promise<CompanySetting> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<CompanySetting>>(
        `/costs/settings/${key}`,
        { setting_value: settingValue },
      );
      return data.data!;
    },
    async () => {
      const { updateCompanySetting } = await import('../local/services/costs-service');
      return updateCompanySetting(key, settingValue) as unknown as CompanySetting;
    },
  );
}


// ── Per-Part Cost Layers & History ────────────────────────────────

/** Get active cost layers for a part (FIFO audit view). */
export async function getCostLayers(partId: number): Promise<CostLayer[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<CostLayer[]>>(
        `/costs/part/${partId}/layers`,
      );
      return data.data!;
    },
    async () => {
      const { getCostLayers } = await import('../local/services/costs-service');
      return getCostLayers(partId) as unknown as CostLayer[];
    },
  );
}

/** Get cost history for sparkline charts. */
export async function getCostHistory(
  partId: number,
  days = 90,
): Promise<CostHistoryPoint[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<CostHistoryPoint[]>>(
        `/costs/part/${partId}/history`,
        { params: { days } },
      );
      return data.data!;
    },
    async () => {
      const { getCostHistory } = await import('../local/services/costs-service');
      return getCostHistory(partId, days) as unknown as CostHistoryPoint[];
    },
  );
}

/** Get consolidated cost summary for a part. */
export async function getPartCostSummary(
  partId: number,
): Promise<PartCostSummary> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PartCostSummary>>(
        `/costs/part/${partId}/summary`,
      );
      return data.data!;
    },
    async () => {
      const { getPartCostSummary } = await import('../local/services/costs-service');
      return getPartCostSummary(partId) as unknown as PartCostSummary;
    },
  );
}


// ── Margin Management ─────────────────────────────────────────────

/** Set a custom margin override on a part. */
export async function setCustomMargin(
  partId: number,
  marginPercent: number,
): Promise<PartCostSummary> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<PartCostSummary>>(
        `/costs/part/${partId}/margin`,
        { margin_percent: marginPercent },
      );
      return data.data!;
    },
    async () => {
      const { setCustomMargin } = await import('../local/services/costs-service');
      return setCustomMargin(partId, marginPercent) as unknown as PartCostSummary;
    },
  );
}

/** Remove custom margin — revert to company default. */
export async function clearCustomMargin(
  partId: number,
): Promise<PartCostSummary> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.delete<ApiResponse<PartCostSummary>>(
        `/costs/part/${partId}/margin`,
      );
      return data.data!;
    },
    async () => {
      const { clearCustomMargin } = await import('../local/services/costs-service');
      return clearCustomMargin(partId) as unknown as PartCostSummary;
    },
  );
}

/** Reset ALL parts to company default margin. */
export async function enforceDefaultMargin(): Promise<{
  cleared_count: number;
  message: string;
}> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<
        ApiResponse<{ cleared_count: number; message: string }>
      >('/costs/enforce-default-margin');
      return data.data!;
    },
    async () => {
      const { enforceDefaultMargin } = await import('../local/services/costs-service');
      return enforceDefaultMargin() as unknown as { cleared_count: number; message: string };
    },
  );
}


// ── Spending Dashboard ────────────────────────────────────────────

interface DateRangeParams {
  date_from?: string;
  date_to?: string;
}

/** Top-level spending KPIs. */
export async function getSpendingSummary(
  params?: DateRangeParams,
): Promise<SpendingSummary> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<SpendingSummary>>(
        '/costs/dashboard',
        { params },
      );
      return data.data!;
    },
    async () => {
      const { getSpendingSummary } = await import('../local/services/costs-service');
      return getSpendingSummary(params) as unknown as SpendingSummary;
    },
  );
}

/** Spending breakdown by supplier. */
export async function getSpendingBySupplier(
  params?: DateRangeParams,
): Promise<SupplierSpend[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<SupplierSpend[]>>(
        '/costs/spending/by-supplier',
        { params },
      );
      return data.data!;
    },
    async () => {
      const { getSpendingBySupplier } = await import('../local/services/costs-service');
      return getSpendingBySupplier(params) as unknown as SupplierSpend[];
    },
  );
}

/** Spending breakdown by part category. */
export async function getSpendingByCategory(
  params?: DateRangeParams,
): Promise<CategorySpend[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<CategorySpend[]>>(
        '/costs/spending/by-category',
        { params },
      );
      return data.data!;
    },
    async () => {
      const { getSpendingByCategory } = await import('../local/services/costs-service');
      return getSpendingByCategory(params) as unknown as CategorySpend[];
    },
  );
}

/** Spending breakdown by job. */
export async function getSpendingByJob(
  params?: DateRangeParams,
): Promise<JobSpend[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<JobSpend[]>>(
        '/costs/spending/by-job',
        { params },
      );
      return data.data!;
    },
    async () => {
      const { getSpendingByJob } = await import('../local/services/costs-service');
      return getSpendingByJob(params) as unknown as JobSpend[];
    },
  );
}

/** Spending trend over time (monthly or weekly). */
export async function getSpendingTrend(
  params?: DateRangeParams & { group_by?: 'month' | 'week' },
): Promise<SpendingTrendPoint[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<SpendingTrendPoint[]>>(
        '/costs/spending/trend',
        { params },
      );
      return data.data!;
    },
    async () => {
      const { getSpendingTrend } = await import('../local/services/costs-service');
      return getSpendingTrend(params) as unknown as SpendingTrendPoint[];
    },
  );
}


// ── Job Cost Rollup & Budget ──────────────────────────────────────

/** Full cost rollup for a job. */
export async function getJobCostRollup(
  jobId: number,
): Promise<JobCostRollup> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<JobCostRollup>>(
        `/costs/job/${jobId}/rollup`,
      );
      return data.data!;
    },
    async () => {
      const { getJobCostRollup } = await import('../local/services/costs-service');
      return getJobCostRollup(jobId) as unknown as JobCostRollup;
    },
  );
}

/** Quick budget status for a job. */
export async function getJobBudgetStatus(
  jobId: number,
): Promise<{
  job_id: number;
  budget_limit: number | null;
  current_spend: number;
  budget_pct: number | null;
  alert_level: string | null;
}> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<{
        job_id: number;
        budget_limit: number | null;
        current_spend: number;
        budget_pct: number | null;
        alert_level: string | null;
      }>>(
        `/costs/job/${jobId}/budget-status`,
      );
      return data.data!;
    },
    async () => {
      const { getJobBudgetStatus } = await import('../local/services/costs-service');
      return getJobBudgetStatus(jobId) as unknown as {
        job_id: number;
        budget_limit: number | null;
        current_spend: number;
        budget_pct: number | null;
        alert_level: string | null;
      };
    },
  );
}


// ── Price Variance & Budget Alerts ────────────────────────────────

/** Price variance report: received vs quoted. */
export async function getPriceVarianceReport(
  params?: DateRangeParams,
): Promise<PriceVarianceItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PriceVarianceItem[]>>(
        '/costs/variance-report',
        { params },
      );
      return data.data!;
    },
    async () => {
      const { getPriceVarianceReport } = await import('../local/services/costs-service');
      return getPriceVarianceReport(params) as unknown as PriceVarianceItem[];
    },
  );
}

/** Get all active budget alerts. */
export async function getBudgetAlerts(): Promise<BudgetAlert[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<BudgetAlert[]>>(
        '/costs/budget-alerts',
      );
      return data.data!;
    },
    async () => {
      const { getBudgetAlerts } = await import('../local/services/costs-service');
      return getBudgetAlerts() as unknown as BudgetAlert[];
    },
  );
}


// ── Daily Report ──────────────────────────────────────────────────

/** Live daily report data. */
export async function getDailyReport(): Promise<DailyReportData> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<DailyReportData>>(
        '/costs/daily-report',
      );
      return data.data!;
    },
    async () => {
      const { getDailyReport } = await import('../local/services/costs-service');
      return getDailyReport() as unknown as DailyReportData;
    },
  );
}
