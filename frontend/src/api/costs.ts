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
  const { data } = await apiClient.get<ApiResponse<CompanySetting[]>>(
    '/costs/settings',
  );
  return data.data!;
}

/** Update a company cost setting. */
export async function updateCompanySetting(
  key: string,
  settingValue: string,
): Promise<CompanySetting> {
  const { data } = await apiClient.put<ApiResponse<CompanySetting>>(
    `/costs/settings/${key}`,
    { setting_value: settingValue },
  );
  return data.data!;
}


// ── Per-Part Cost Layers & History ────────────────────────────────

/** Get active cost layers for a part (FIFO audit view). */
export async function getCostLayers(partId: number): Promise<CostLayer[]> {
  const { data } = await apiClient.get<ApiResponse<CostLayer[]>>(
    `/costs/part/${partId}/layers`,
  );
  return data.data!;
}

/** Get cost history for sparkline charts. */
export async function getCostHistory(
  partId: number,
  days = 90,
): Promise<CostHistoryPoint[]> {
  const { data } = await apiClient.get<ApiResponse<CostHistoryPoint[]>>(
    `/costs/part/${partId}/history`,
    { params: { days } },
  );
  return data.data!;
}

/** Get consolidated cost summary for a part. */
export async function getPartCostSummary(
  partId: number,
): Promise<PartCostSummary> {
  const { data } = await apiClient.get<ApiResponse<PartCostSummary>>(
    `/costs/part/${partId}/summary`,
  );
  return data.data!;
}


// ── Margin Management ─────────────────────────────────────────────

/** Set a custom margin override on a part. */
export async function setCustomMargin(
  partId: number,
  marginPercent: number,
): Promise<PartCostSummary> {
  const { data } = await apiClient.put<ApiResponse<PartCostSummary>>(
    `/costs/part/${partId}/margin`,
    { margin_percent: marginPercent },
  );
  return data.data!;
}

/** Remove custom margin — revert to company default. */
export async function clearCustomMargin(
  partId: number,
): Promise<PartCostSummary> {
  const { data } = await apiClient.delete<ApiResponse<PartCostSummary>>(
    `/costs/part/${partId}/margin`,
  );
  return data.data!;
}

/** Reset ALL parts to company default margin. */
export async function enforceDefaultMargin(): Promise<{
  cleared_count: number;
  message: string;
}> {
  const { data } = await apiClient.post<
    ApiResponse<{ cleared_count: number; message: string }>
  >('/costs/enforce-default-margin');
  return data.data!;
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
  const { data } = await apiClient.get<ApiResponse<SpendingSummary>>(
    '/costs/dashboard',
    { params },
  );
  return data.data!;
}

/** Spending breakdown by supplier. */
export async function getSpendingBySupplier(
  params?: DateRangeParams,
): Promise<SupplierSpend[]> {
  const { data } = await apiClient.get<ApiResponse<SupplierSpend[]>>(
    '/costs/spending/by-supplier',
    { params },
  );
  return data.data!;
}

/** Spending breakdown by part category. */
export async function getSpendingByCategory(
  params?: DateRangeParams,
): Promise<CategorySpend[]> {
  const { data } = await apiClient.get<ApiResponse<CategorySpend[]>>(
    '/costs/spending/by-category',
    { params },
  );
  return data.data!;
}

/** Spending breakdown by job. */
export async function getSpendingByJob(
  params?: DateRangeParams,
): Promise<JobSpend[]> {
  const { data } = await apiClient.get<ApiResponse<JobSpend[]>>(
    '/costs/spending/by-job',
    { params },
  );
  return data.data!;
}

/** Spending trend over time (monthly or weekly). */
export async function getSpendingTrend(
  params?: DateRangeParams & { group_by?: 'month' | 'week' },
): Promise<SpendingTrendPoint[]> {
  const { data } = await apiClient.get<ApiResponse<SpendingTrendPoint[]>>(
    '/costs/spending/trend',
    { params },
  );
  return data.data!;
}


// ── Job Cost Rollup & Budget ──────────────────────────────────────

/** Full cost rollup for a job. */
export async function getJobCostRollup(
  jobId: number,
): Promise<JobCostRollup> {
  const { data } = await apiClient.get<ApiResponse<JobCostRollup>>(
    `/costs/job/${jobId}/rollup`,
  );
  return data.data!;
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
  const { data } = await apiClient.get<ApiResponse<any>>(
    `/costs/job/${jobId}/budget-status`,
  );
  return data.data!;
}


// ── Price Variance & Budget Alerts ────────────────────────────────

/** Price variance report: received vs quoted. */
export async function getPriceVarianceReport(
  params?: DateRangeParams,
): Promise<PriceVarianceItem[]> {
  const { data } = await apiClient.get<ApiResponse<PriceVarianceItem[]>>(
    '/costs/variance-report',
    { params },
  );
  return data.data!;
}

/** Get all active budget alerts. */
export async function getBudgetAlerts(): Promise<BudgetAlert[]> {
  const { data } = await apiClient.get<ApiResponse<BudgetAlert[]>>(
    '/costs/budget-alerts',
  );
  return data.data!;
}


// ── Daily Report ──────────────────────────────────────────────────

/** Live daily report data. */
export async function getDailyReport(): Promise<DailyReportData> {
  const { data } = await apiClient.get<ApiResponse<DailyReportData>>(
    '/costs/daily-report',
  );
  return data.data!;
}
