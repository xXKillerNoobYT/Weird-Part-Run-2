/**
 * Report Exports — CSV/PDF generation, bookkeeper exports, export bundles, and public report access.
 */

import { toCsv, safeSelect } from './helpers';
import { getPreBilling, getPreBillingAllJobs } from './pre-billing';
import { getTimesheets } from './timesheets';
import { getLaborOverview } from './labor-overview';
import { getProfitability } from './profitability';
import { getAnnotations, type ReportAnnotation } from './annotations';
import { getShareTokenByValue, recordTokenAccess } from './share-tokens';

// ── Functions ──────────────────────────────────────────────────────

/** Generate a CSV/PDF export blob locally. PDF falls back to CSV. */
export async function generateExport(params: {
  report_type: 'pre-billing' | 'timesheet' | 'labor-overview' | 'profitability';
  format: 'csv' | 'pdf';
  job_id?: number;
  employee_id?: number;
  start_date?: string;
  end_date?: string;
}): Promise<Blob> {
  const start = params.start_date ?? '2000-01-01';
  const end = params.end_date ?? '2099-12-31';

  let csvText = '';

  switch (params.report_type) {
    case 'pre-billing': {
      if (params.job_id) {
        const bundle = await getPreBilling({ job_id: params.job_id, start_date: start, end_date: end });
        // Labor sheet
        csvText += '=== LABOR ===\n';
        csvText += toCsv(bundle.labor);
        csvText += '\n\n=== PARTS ===\n';
        csvText += toCsv(bundle.parts);
        csvText += '\n\n=== MOVEMENTS ===\n';
        csvText += toCsv(bundle.movements);
        csvText += '\n\n=== SUMMARY ===\n';
        csvText += toCsv([bundle.summary as any]);
      } else {
        const allJobs = await getPreBillingAllJobs({ start_date: start, end_date: end });
        csvText = toCsv(allJobs);
      }
      break;
    }
    case 'timesheet': {
      const report = await getTimesheets({
        start_date: start,
        end_date: end,
        employee_id: params.employee_id,
      });
      csvText = toCsv(report.entries.map(e => ({
        date: e.date,
        job_number: e.job_number,
        job_name: e.job_name,
        clock_in: e.clock_in,
        clock_out: e.clock_out ?? '',
        regular_hours: e.regular_hours,
        overtime_hours: e.overtime_hours,
        total_hours: e.total_hours,
        bill_rate_type: e.bill_rate_type ?? '',
      })));
      break;
    }
    case 'labor-overview': {
      const report = await getLaborOverview({
        start_date: start,
        end_date: end,
        job_id: params.job_id,
      });
      csvText += '=== BY EMPLOYEE ===\n';
      csvText += toCsv(report.by_employee);
      csvText += '\n\n=== BY JOB ===\n';
      csvText += toCsv(report.by_job);
      csvText += '\n\n=== BY BILL RATE ===\n';
      csvText += toCsv(report.by_bill_rate);
      csvText += '\n\n=== TOTALS ===\n';
      csvText += toCsv([report.totals as any]);
      break;
    }
    case 'profitability': {
      const report = await getProfitability({
        start_date: start,
        end_date: end,
        job_id: params.job_id,
      });
      csvText = toCsv(report.by_job);
      csvText += '\n\n=== TOTALS ===\n';
      csvText += toCsv([report.totals as any]);
      break;
    }
  }

  return new Blob([csvText], { type: 'text/csv' });
}

/** Generate a bookkeeper-formatted export (QuickBooks, General Ledger, Payroll). */
export async function generateBookkeeperExport(params: {
  format: 'quickbooks' | 'general_ledger' | 'payroll';
  job_ids?: number[];
  period_start: string;
  period_end: string;
  include_labor?: boolean;
  include_parts?: boolean;
}): Promise<Blob> {
  const { format, job_ids, period_start, period_end, include_labor = true, include_parts = true } = params;

  const sections: string[] = [];

  // Determine which jobs to include
  const jobList = job_ids && job_ids.length > 0
    ? job_ids
    : (await safeSelect<{ id: number }>(
        `SELECT id FROM jobs WHERE deleted_at IS NULL ORDER BY job_number`,
      )).map(j => j.id);

  for (const jobId of jobList) {
    const bundle = await getPreBilling({ job_id: jobId, start_date: period_start, end_date: period_end });

    if (format === 'quickbooks') {
      // QuickBooks IIF-like CSV format
      if (include_labor && bundle.labor.length > 0) {
        sections.push(`!TIMEACT\tDATE\tJOB\tEMPLOYEE\tDURATION\tBILLABLESTATUS`);
        for (const entry of bundle.labor) {
          sections.push(`TIMEACT\t${entry.date}\t${bundle.job_number}\t${entry.employee}\t${entry.total_hours}\tBillable`);
        }
      }
      if (include_parts && bundle.parts.length > 0) {
        sections.push(`!TRNS\tDATE\tACCNT\tNAME\tAMOUNT\tMEMO`);
        for (const part of bundle.parts) {
          sections.push(`TRNS\t${period_end}\tCost of Goods\t${bundle.job_number}\t${part.total_cost}\t${part.part_name}`);
        }
      }
    } else if (format === 'general_ledger') {
      // General ledger format
      if (include_labor) {
        sections.push(`Date,Account,Description,Debit,Credit,Job`);
        for (const entry of bundle.labor) {
          const amount = Math.round(entry.total_hours * (bundle.bill_rate_type ? 50 : 50) * 100) / 100; // placeholder rate
          sections.push(`${entry.date},5000 - Labor,${entry.employee} - ${bundle.job_number},${amount},,${bundle.job_number}`);
        }
      }
      if (include_parts) {
        for (const part of bundle.parts) {
          sections.push(`${period_end},5100 - Materials,${part.part_name} - ${bundle.job_number},${part.total_cost},,${bundle.job_number}`);
        }
      }
    } else {
      // Payroll format
      if (include_labor) {
        sections.push(`Employee,Date,Job,Regular Hours,Overtime Hours,Total Hours`);
        for (const entry of bundle.labor) {
          sections.push(`${entry.employee},${entry.date},${bundle.job_number},${entry.regular_hours},${entry.overtime_hours},${entry.total_hours}`);
        }
      }
    }
  }

  const csvText = sections.join('\n');
  return new Blob([csvText], { type: 'text/csv' });
}

/** Generate an export bundle (multiple reports). In local mode, concatenates into a single CSV. */
export async function generateExportBundle(exports: Array<{
  report_type: string;
  format?: string;
  job_id?: number;
  employee_id?: number;
  start_date: string;
  end_date: string;
}>): Promise<Blob> {
  const parts: string[] = [];

  for (const exp of exports) {
    const reportType = exp.report_type as 'pre-billing' | 'timesheet' | 'labor-overview' | 'profitability';
    const blob = await generateExport({
      report_type: reportType,
      format: (exp.format as 'csv' | 'pdf') ?? 'csv',
      job_id: exp.job_id,
      employee_id: exp.employee_id,
      start_date: exp.start_date,
      end_date: exp.end_date,
    });
    const text = await blob.text();
    parts.push(`\n========== ${exp.report_type.toUpperCase()} (${exp.start_date} to ${exp.end_date}) ==========\n`);
    parts.push(text);
  }

  return new Blob(parts, { type: 'text/csv' });
}

/** Get a public report by share token (local mode: look up token, generate report data). */
export async function getPublicReport(token: string): Promise<{
  report_type: string;
  label: string | null;
  generated_at: string;
  context_params: Record<string, any>;
  data: Record<string, any>;
  annotations: ReportAnnotation[];
}> {
  // Look up the token
  const tokenRecord = await getShareTokenByValue(token);

  if (!tokenRecord || !tokenRecord.is_active) {
    throw new Error('Invalid or expired share token');
  }

  // Check expiration
  if (tokenRecord.expires_at && new Date(tokenRecord.expires_at) < new Date()) {
    throw new Error('Share token has expired');
  }

  // Record the access
  await recordTokenAccess(tokenRecord.id);

  // Parse context params
  const contextParams: Record<string, any> = typeof tokenRecord.context_params === 'string'
    ? JSON.parse(tokenRecord.context_params)
    : tokenRecord.context_params;

  // Generate the report data based on type and context
  let reportData: Record<string, any> = {};
  const start = contextParams.start_date ?? contextParams.period_start ?? '2000-01-01';
  const end = contextParams.end_date ?? contextParams.period_end ?? '2099-12-31';

  switch (tokenRecord.report_type) {
    case 'pre-billing': {
      if (contextParams.job_id) {
        reportData = await getPreBilling({ job_id: contextParams.job_id, start_date: start, end_date: end });
      } else {
        reportData = { jobs: await getPreBillingAllJobs({ start_date: start, end_date: end }) };
      }
      break;
    }
    case 'timesheet': {
      reportData = await getTimesheets({
        start_date: start,
        end_date: end,
        employee_id: contextParams.employee_id,
      });
      break;
    }
    case 'labor-overview': {
      reportData = await getLaborOverview({
        start_date: start,
        end_date: end,
        job_id: contextParams.job_id,
      });
      break;
    }
    case 'profitability': {
      reportData = await getProfitability({
        start_date: start,
        end_date: end,
        job_id: contextParams.job_id,
      });
      break;
    }
    default:
      reportData = { error: `Unknown report type: ${tokenRecord.report_type}` };
  }

  // Get annotations for this report context
  const contextKey = contextParams.context_key ?? `${tokenRecord.report_type}:${start}:${end}`;
  const annotations = await getAnnotations(tokenRecord.report_type, contextKey);

  return {
    report_type: tokenRecord.report_type,
    label: tokenRecord.label,
    generated_at: new Date().toISOString(),
    context_params: contextParams,
    data: reportData,
    annotations,
  };
}
