/**
 * Reports API functions — pre-billing, timesheets, labor overview, exports.
 *
 * All functions follow: call apiClient → unwrap ApiResponse → return typed data.
 *
 * NOTE: Labor data is HOURS ONLY — no dollar amounts.
 * The bookkeeper handles actual bill-out rates externally.
 */

import apiClient from './client';
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
  const { data } = await apiClient.get<ApiResponse<PreBillingJobSummary[]>>(
    '/reports/pre-billing/all-jobs',
    { params },
  );
  return data.data ?? [];
}

/** Pre-billing bundle for a job + date range */
export async function getPreBilling(params: {
  job_id: number;
  start_date: string;
  end_date: string;
}): Promise<PreBillingBundle> {
  const { data } = await apiClient.get<ApiResponse<PreBillingBundle>>(
    '/reports/pre-billing',
    { params },
  );
  return data.data!;
}

/** Employee timesheet for a date range */
export async function getTimesheets(params: {
  start_date: string;
  end_date: string;
  employee_id?: number;
  group_by?: 'day' | 'week' | 'pay_period';
}): Promise<TimesheetReport> {
  const { data } = await apiClient.get<ApiResponse<TimesheetReport>>(
    '/reports/timesheets',
    { params },
  );
  return data.data!;
}

/** Cross-job labor overview for a date range */
export async function getLaborOverview(params: {
  start_date: string;
  end_date: string;
  job_id?: number;
}): Promise<LaborOverviewReport> {
  const { data } = await apiClient.get<ApiResponse<LaborOverviewReport>>(
    '/reports/labor-overview',
    { params },
  );
  return data.data!;
}

/** Generate and download a CSV export */
export async function generateExport(params: {
  report_type: 'pre-billing' | 'timesheet' | 'labor-overview';
  format: 'csv' | 'pdf';
  job_id?: number;
  employee_id?: number;
  start_date?: string;
  end_date?: string;
}): Promise<Blob> {
  const { data } = await apiClient.post('/reports/exports', params, {
    responseType: 'blob',
  });
  return data;
}

/** Helper: trigger browser download of a blob */
export function downloadBlob(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
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
  const { data } = await apiClient.get<ApiResponse<BillingPeriod[]>>(
    '/reports/billing-periods',
    { params },
  );
  return data.data!;
}

/** Create a new (open) billing period */
export async function createBillingPeriod(body: {
  job_id?: number;
  period_start: string;
  period_end: string;
  notes?: string;
}): Promise<BillingPeriod> {
  const { data } = await apiClient.post<ApiResponse<BillingPeriod>>(
    '/reports/billing-periods',
    body,
  );
  return data.data!;
}

/** Lock a billing period */
export async function lockBillingPeriod(periodId: number): Promise<BillingPeriod> {
  const { data } = await apiClient.patch<ApiResponse<BillingPeriod>>(
    `/reports/billing-periods/${periodId}/lock`,
  );
  return data.data!;
}

/** Unlock a billing period */
export async function unlockBillingPeriod(periodId: number): Promise<BillingPeriod> {
  const { data } = await apiClient.patch<ApiResponse<BillingPeriod>>(
    `/reports/billing-periods/${periodId}/unlock`,
  );
  return data.data!;
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
  const { data } = await apiClient.get<ApiResponse<ProfitabilityReport>>(
    '/reports/profitability',
    { params },
  );
  return data.data!;
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
  const { data } = await apiClient.post('/reports/exports/bookkeeper', params, {
    responseType: 'blob',
  });
  return data;
}
