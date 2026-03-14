/**
 * Reports API functions — pre-billing, timesheets, labor overview, exports.
 *
 * All functions follow: call apiClient → unwrap ApiResponse → return typed data.
 *
 * NOTE: Labor data is HOURS ONLY — no dollar amounts.
 * The bookkeeper handles actual bill-out rates externally.
 */

import apiClient from './client';
import { adaptedRequest } from './adapter';
import type { ApiResponse } from '../lib/types';


// ── Types ─────────────────────────────────────────────────────────

export interface PreBillingLaborEntry {
  employee_id: number;
  employee: string;
  date: string;
  clock_in: string | null;
  clock_out: string | null;
  regular_hours: number;
  overtime_hours: number;
  total_hours: number;
  bill_rate_type: string | null;
}

export interface PreBillingPartItem {
  part_id: number;
  part_name: string;
  part_code: string | null;
  qty: number;
  unit_cost: number;
  sell_price: number;
  total_cost: number;
  total_sell: number;
}

export interface PreBillingMovement {
  date: string;
  part_name: string;
  from_location: string | null;
  to_location: string | null;
  qty: number;
  movement_type: string;
}

export interface PreBillingSummary {
  total_labor_hours: number;
  total_regular_hours: number;
  total_overtime_hours: number;
  total_parts_cost: number;
  total_parts_sell: number;
  budget_limit: number | null;
  budget_used_pct: number | null;
}

export interface PreBillingBundle {
  job_id: number;
  job_name: string;
  job_number: string;
  bill_rate_type: string | null;
  period_start: string;
  period_end: string;
  labor: PreBillingLaborEntry[];
  parts: PreBillingPartItem[];
  movements: PreBillingMovement[];
  summary: PreBillingSummary;
}

export interface TimesheetEntry {
  id: number;
  date: string;
  job_id: number;
  job_name: string;
  job_number: string;
  clock_in: string;
  clock_out: string | null;
  regular_hours: number;
  overtime_hours: number;
  total_hours: number;
  bill_rate_type: string | null;
  gps_in: { lat: number; lng: number } | null;
  gps_out: { lat: number; lng: number } | null;
}

export interface TimesheetDayGroup {
  date: string;
  entries: TimesheetEntry[];
  total_hours: number;
  regular_hours: number;
  overtime_hours: number;
}

export interface TimesheetSummary {
  total_hours: number;
  regular_hours: number;
  overtime_hours: number;
  days_worked: number;
  jobs_worked: number;
}

export interface TimesheetReport {
  employee_id: number | null;
  employee_name: string | null;
  period_start: string;
  period_end: string;
  group_by: string;
  entries: TimesheetEntry[];
  day_groups: TimesheetDayGroup[];
  summary: TimesheetSummary;
}

export interface LaborByEmployee {
  employee_id: number;
  employee: string;
  total_hours: number;
  regular_hours: number;
  overtime_hours: number;
  jobs_worked: number;
  days_worked: number;
  avg_hours_per_day: number;
}

export interface LaborByJob {
  job_id: number;
  job_name: string;
  job_number: string;
  total_hours: number;
  employee_count: number;
}

export interface LaborByBillRate {
  rate_type: string;
  total_hours: number;
  entry_count: number;
}

export interface LaborOverviewTotals {
  total_hours: number;
  regular_hours: number;
  overtime_hours: number;
  total_employees: number;
  total_jobs: number;
  total_days: number;
}

export interface LaborOverviewReport {
  period_start: string;
  period_end: string;
  by_employee: LaborByEmployee[];
  by_job: LaborByJob[];
  by_bill_rate: LaborByBillRate[];
  totals: LaborOverviewTotals;
}


// ── API Functions ─────────────────────────────────────────────────

export interface PreBillingJobSummary {
  job_id: number;
  job_number: string;
  job_name: string;
  total_labor_hours: number;
  total_parts_cost: number;
  total_parts_sell: number;
  budget_limit: number | null;
  budget_used_pct: number | null;
}

/** All-jobs pre-billing summary for a date range */
export async function getPreBillingAllJobs(params: {
  start_date: string;
  end_date: string;
}): Promise<PreBillingJobSummary[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PreBillingJobSummary[]>>(
        '/reports/pre-billing/all-jobs',
        { params },
      );
      return data.data ?? [];
    },
    async () => {
      const { getPreBillingAllJobs } = await import('../local/services/report-service');
      return getPreBillingAllJobs(params) as unknown as PreBillingJobSummary[];
    },
  );
}

/** Pre-billing bundle for a job + date range */
export async function getPreBilling(params: {
  job_id: number;
  start_date: string;
  end_date: string;
}): Promise<PreBillingBundle> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PreBillingBundle>>(
        '/reports/pre-billing',
        { params },
      );
      return data.data!;
    },
    async () => {
      const { getPreBilling } = await import('../local/services/report-service');
      return getPreBilling(params) as unknown as PreBillingBundle;
    },
  );
}

/** Employee timesheet for a date range */
export async function getTimesheets(params: {
  start_date: string;
  end_date: string;
  employee_id?: number;
  group_by?: 'day' | 'week' | 'month' | 'pay_period' | 'billing_period';
}): Promise<TimesheetReport> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<TimesheetReport>>(
        '/reports/timesheets',
        { params },
      );
      return data.data!;
    },
    async () => {
      const { getTimesheets } = await import('../local/services/report-service');
      return getTimesheets(params) as unknown as TimesheetReport;
    },
  );
}

/** Cross-job labor overview for a date range */
export async function getLaborOverview(params: {
  start_date: string;
  end_date: string;
  job_id?: number;
}): Promise<LaborOverviewReport> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<LaborOverviewReport>>(
        '/reports/labor-overview',
        { params },
      );
      return data.data!;
    },
    async () => {
      const { getLaborOverview } = await import('../local/services/report-service');
      return getLaborOverview(params) as unknown as LaborOverviewReport;
    },
  );
}

/** Generate and download a CSV export */
export async function generateExport(params: {
  report_type: 'pre-billing' | 'timesheet' | 'labor-overview' | 'profitability';
  format: 'csv' | 'pdf';
  job_id?: number;
  employee_id?: number;
  start_date?: string;
  end_date?: string;
}): Promise<Blob> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post('/reports/exports', params, {
        responseType: 'blob',
      });
      return data;
    },
    async () => {
      const { generateExport } = await import('../local/services/report-service');
      return generateExport(params) as unknown as Blob;
    },
  );
}

/**
 * Helper: trigger download/save of a blob.
 *
 * In Tauri mode: opens a native "Save As" dialog and writes to disk.
 * In browser mode: uses the standard createObjectURL + <a>.click() trick.
 */
export async function downloadBlob(blob: Blob, filename: string): Promise<void> {
  const { exportFile } = await import('../local/services/file-export-service');
  await exportFile(blob, filename);
}


// ── Billing Periods (Period Locking) ──────────────────────────────

export interface BillingPeriod {
  id: number;
  job_id: number | null;
  job_name: string | null;
  job_number: string | null;
  period_start: string;
  period_end: string;
  locked_at: string | null;
  locked_by: number | null;
  locked_by_name: string | null;
  notes: string | null;
  created_at: string | null;
}

/** List billing periods, optionally filtered by job */
export async function getBillingPeriods(params?: {
  job_id?: number;
}): Promise<BillingPeriod[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<BillingPeriod[]>>(
        '/reports/billing-periods',
        { params },
      );
      return data.data!;
    },
    async () => {
      const { listBillingPeriods } = await import('../local/services/billing-service');
      return listBillingPeriods(params) as unknown as BillingPeriod[];
    },
  );
}

/** Create a new (open) billing period */
export async function createBillingPeriod(body: {
  job_id?: number;
  period_start: string;
  period_end: string;
  notes?: string;
}): Promise<BillingPeriod> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<BillingPeriod>>(
        '/reports/billing-periods',
        body,
      );
      return data.data!;
    },
    async () => {
      const { createBillingPeriod } = await import('../local/services/billing-service');
      return createBillingPeriod(body) as unknown as BillingPeriod;
    },
  );
}

/** Lock a billing period */
export async function lockBillingPeriod(periodId: number): Promise<BillingPeriod> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.patch<ApiResponse<BillingPeriod>>(
        `/reports/billing-periods/${periodId}/lock`,
      );
      return data.data!;
    },
    async () => {
      const { lockBillingPeriod } = await import('../local/services/billing-service');
      return lockBillingPeriod(periodId, 0) as unknown as BillingPeriod;
    },
  );
}

/** Unlock a billing period */
export async function unlockBillingPeriod(periodId: number): Promise<BillingPeriod> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.patch<ApiResponse<BillingPeriod>>(
        `/reports/billing-periods/${periodId}/unlock`,
      );
      return data.data!;
    },
    async () => {
      const { unlockBillingPeriod } = await import('../local/services/billing-service');
      return unlockBillingPeriod(periodId) as unknown as BillingPeriod;
    },
  );
}


// ── Profitability Analysis ────────────────────────────────────────

export interface JobProfitability {
  job_id: number;
  job_name: string;
  job_number: string;
  status: string;
  labor_hours: number;
  labor_cost: number;
  parts_cost: number;
  parts_sell: number;
  total_cost: number;
  parts_margin: number;
  budget_limit: number | null;
  budget_remaining: number | null;
  budget_utilization_pct: number | null;
}

export interface CompanyProfitabilityTotals {
  total_labor_cost: number;
  total_parts_cost: number;
  total_parts_sell: number;
  total_combined_cost: number;
  total_parts_margin: number;
  total_labor_hours: number;
  jobs_under_budget: number;
  jobs_over_budget: number;
  jobs_no_budget: number;
}

export interface ProfitabilityReport {
  period_start: string;
  period_end: string;
  by_job: JobProfitability[];
  totals: CompanyProfitabilityTotals;
}

/** Job profitability analysis for a date range */
export async function getProfitability(params: {
  start_date: string;
  end_date: string;
  job_id?: number;
}): Promise<ProfitabilityReport> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ProfitabilityReport>>(
        '/reports/profitability',
        { params },
      );
      return data.data!;
    },
    async () => {
      const { getProfitability } = await import('../local/services/report-service');
      return getProfitability(params) as unknown as ProfitabilityReport;
    },
  );
}


// ── Bookkeeper Exports ────────────────────────────────────────────

/** Generate a bookkeeper-formatted export file */
export async function generateBookkeeperExport(params: {
  format: 'quickbooks' | 'general_ledger' | 'payroll';
  job_ids?: number[];
  period_start: string;
  period_end: string;
  include_labor?: boolean;
  include_parts?: boolean;
}): Promise<Blob> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post('/reports/exports/bookkeeper', params, {
        responseType: 'blob',
      });
      return data;
    },
    async () => {
      const { generateBookkeeperExport } = await import('../local/services/report-service');
      return generateBookkeeperExport(params) as unknown as Blob;
    },
  );
}


// ── Report Annotations ────────────────────────────────────────────

export interface ReportAnnotation {
  id: number;
  report_type: string;
  context_key: string;
  content: string;
  author_id: number;
  author_name: string;
  created_at: string;
  updated_at: string;
}

export async function getAnnotations(reportType: string, contextKey: string): Promise<ReportAnnotation[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ReportAnnotation[]>>('/reports/annotations', {
        params: { report_type: reportType, context_key: contextKey },
      });
      return data.data!;
    },
    async () => {
      const { getAnnotations } = await import('../local/services/report-service');
      return getAnnotations(reportType, contextKey) as unknown as ReportAnnotation[];
    },
  );
}

export async function createAnnotation(body: {
  report_type: string;
  context_key: string;
  content: string;
}): Promise<ReportAnnotation> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<ReportAnnotation>>('/reports/annotations', body);
      return data.data!;
    },
    async () => {
      const { createAnnotation } = await import('../local/services/report-service');
      return createAnnotation({ ...body, author_id: 0 } as any) as unknown as ReportAnnotation;
    },
  );
}

export async function updateAnnotation(id: number, content: string): Promise<ReportAnnotation> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<ReportAnnotation>>(`/reports/annotations/${id}`, { content });
      return data.data!;
    },
    async () => {
      const { updateAnnotation } = await import('../local/services/report-service');
      return updateAnnotation(id, { content } as any) as unknown as ReportAnnotation;
    },
  );
}

export async function deleteAnnotation(id: number): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.delete(`/reports/annotations/${id}`);
    },
    async () => {
      const { deleteAnnotation } = await import('../local/services/report-service');
      await deleteAnnotation(id) as any;
    },
  );
}


// ── Report Templates ──────────────────────────────────────────────

export interface ReportTemplate {
  id: number;
  name: string;
  report_type: string;
  config_json: Record<string, unknown>;
  created_by: number;
  created_at: string;
  updated_at: string;
}

export async function getTemplates(reportType?: string): Promise<ReportTemplate[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ReportTemplate[]>>('/reports/templates', {
        params: reportType ? { report_type: reportType } : {},
      });
      return data.data!;
    },
    async () => {
      const { listTemplates } = await import('../local/services/report-service');
      return listTemplates(reportType) as unknown as ReportTemplate[];
    },
  );
}

export async function createTemplate(body: {
  name: string;
  report_type: string;
  config_json: Record<string, unknown>;
}): Promise<ReportTemplate> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<ReportTemplate>>('/reports/templates', body);
      return data.data!;
    },
    async () => {
      const { createTemplate } = await import('../local/services/report-service');
      return createTemplate({ ...body, created_by: 0 } as any) as unknown as ReportTemplate;
    },
  );
}

export async function updateTemplate(id: number, body: {
  name?: string;
  config_json?: Record<string, unknown>;
}): Promise<ReportTemplate> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<ReportTemplate>>(`/reports/templates/${id}`, body);
      return data.data!;
    },
    async () => {
      const { updateTemplate } = await import('../local/services/report-service');
      return updateTemplate(id, body) as unknown as ReportTemplate;
    },
  );
}

export async function deleteTemplate(id: number): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.delete(`/reports/templates/${id}`);
    },
    async () => {
      const { deleteTemplate } = await import('../local/services/report-service');
      await deleteTemplate(id) as any;
    },
  );
}


// ── Report Share Tokens ───────────────────────────────────────────

export interface ReportShareToken {
  id: number;
  token: string;
  report_type: string;
  context_params: Record<string, unknown>;
  label: string | null;
  created_by: number;
  expires_at: string | null;
  last_accessed_at: string | null;
  is_active: boolean;
  created_at: string;
  share_url: string;
}

export async function createShareToken(body: {
  report_type: string;
  context_params: Record<string, unknown>;
  label?: string;
  expires_in_days?: number;
}): Promise<ReportShareToken> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<ReportShareToken>>('/reports/share-tokens', body);
      return data.data!;
    },
    async () => {
      const { createShareToken } = await import('../local/services/report-service');
      return createShareToken({ ...body, created_by: 0 } as any) as unknown as ReportShareToken;
    },
  );
}

export async function getShareTokens(): Promise<ReportShareToken[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ReportShareToken[]>>('/reports/share-tokens');
      return data.data!;
    },
    async () => {
      const { listShareTokens } = await import('../local/services/report-service');
      return listShareTokens() as unknown as ReportShareToken[];
    },
  );
}

export async function revokeShareToken(id: number): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.delete(`/reports/share-tokens/${id}`);
    },
    async () => {
      const { deactivateShareToken } = await import('../local/services/report-service');
      await deactivateShareToken(id) as any;
    },
  );
}


// ── Export Bundle ─────────────────────────────────────────────────

export interface ExportBundleItem {
  report_type: string;
  format?: string;
  job_id?: number;
  employee_id?: number;
  start_date: string;
  end_date: string;
}

export async function generateExportBundle(exports: ExportBundleItem[]): Promise<Blob> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post('/reports/exports/bundle', { exports }, {
        responseType: 'blob',
      });
      return data;
    },
    async () => {
      const { generateExportBundle } = await import('../local/services/report-service');
      return generateExportBundle(exports) as unknown as Blob;
    },
  );
}


// ── Public Report ─────────────────────────────────────────────────

export interface PublicReportData {
  report_type: string;
  label: string | null;
  generated_at: string;
  context_params: Record<string, unknown>;
  data: Record<string, unknown>;
  annotations: ReportAnnotation[];
}

export async function getPublicReport(token: string): Promise<PublicReportData> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PublicReportData>>(`/public/reports/${token}`);
      return data.data!;
    },
    async () => {
      const { getPublicReport } = await import('../local/services/report-service');
      return getPublicReport(token) as unknown as PublicReportData;
    },
  );
}
