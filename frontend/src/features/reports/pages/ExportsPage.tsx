/**
 * ExportsPage — generate and download report exports (CSV) and bookkeeper formats.
 *
 * Two sections:
 * 1. Standard Reports — Pre-Billing, Timesheet, Labor Overview CSVs
 * 2. Bookkeeper Exports — QuickBooks IIF, General Ledger CSV, Payroll CSV
 */

import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  Download, FileText, Clock, BarChart3, Receipt,
  BookOpen, DollarSign, Users,
} from 'lucide-react';
import { Card } from '../../../components/ui/Card';
import { toast } from '../../../lib/toast';
import { getActiveJobs } from '../../../api/jobs';
import { getEmployees } from '../../../api/people';
import {
  generateExport, downloadBlob, generateBookkeeperExport,
} from '../../../api/reports';


type ReportType = 'pre-billing' | 'timesheet' | 'labor-overview';
type BookkeeperFormat = 'quickbooks' | 'general_ledger' | 'payroll';

const REPORT_TYPES: { key: ReportType; label: string; icon: React.ReactNode; description: string }[] = [
  {
    key: 'pre-billing',
    label: 'Pre-Billing',
    icon: <Receipt className="h-5 w-5" />,
    description: 'Labor hours + parts cost for a specific job',
  },
  {
    key: 'timesheet',
    label: 'Timesheet',
    icon: <Clock className="h-5 w-5" />,
    description: 'Clock entries grouped by day for one or all employees',
  },
  {
    key: 'labor-overview',
    label: 'Labor Overview',
    icon: <BarChart3 className="h-5 w-5" />,
    description: 'Cross-job labor breakdown by employee, job, and rate type',
  },
];

const BOOKKEEPER_FORMATS: { key: BookkeeperFormat; label: string; icon: React.ReactNode; description: string }[] = [
  {
    key: 'quickbooks',
    label: 'QuickBooks IIF',
    icon: <BookOpen className="h-5 w-5" />,
    description: 'Import-ready IIF file for QuickBooks Desktop',
  },
  {
    key: 'general_ledger',
    label: 'General Ledger',
    icon: <DollarSign className="h-5 w-5" />,
    description: 'Debit/credit CSV for any accounting system',
  },
  {
    key: 'payroll',
    label: 'Payroll',
    icon: <Users className="h-5 w-5" />,
    description: 'Employee hours + pay rates for ADP, Gusto, etc.',
  },
];


export function ExportsPage() {
  // ── Standard Export State ───────────────────────────────────
  const [reportType, setReportType] = useState<ReportType>('pre-billing');
  const [jobId, setJobId] = useState<number | undefined>(undefined);
  const [employeeId, setEmployeeId] = useState<number | undefined>(undefined);
  const [startDate, setStartDate] = useState(() => {
    const d = new Date();
    d.setDate(1);
    return d.toISOString().split('T')[0];
  });
  const [endDate, setEndDate] = useState(() =>
    new Date().toISOString().split('T')[0],
  );
  const [generating, setGenerating] = useState(false);

  // ── Bookkeeper Export State ─────────────────────────────────
  const [bkFormat, setBkFormat] = useState<BookkeeperFormat>('quickbooks');
  const [bkStartDate, setBkStartDate] = useState(() => {
    const d = new Date();
    d.setDate(1);
    return d.toISOString().split('T')[0];
  });
  const [bkEndDate, setBkEndDate] = useState(() =>
    new Date().toISOString().split('T')[0],
  );
  const [bkIncludeLabor, setBkIncludeLabor] = useState(true);
  const [bkIncludeParts, setBkIncludeParts] = useState(true);
  const [bkGenerating, setBkGenerating] = useState(false);

  // ── Reference Data ──────────────────────────────────────────
  const jobsQuery = useQuery({
    queryKey: ['jobs', 'active'],
    queryFn: () => getActiveJobs(),
    staleTime: 60_000,
  });

  const employeesQuery = useQuery({
    queryKey: ['employees', 'list'],
    queryFn: () => getEmployees({ page_size: 200, is_active: true }),
    staleTime: 60_000,
  });

  // ── Standard Export Handler ─────────────────────────────────
  const handleGenerate = async () => {
    if (reportType === 'pre-billing' && !jobId) {
      toast.error('Please select a job for the pre-billing report');
      return;
    }

    setGenerating(true);
    try {
      const blob = await generateExport({
        report_type: reportType,
        format: 'csv',
        job_id: reportType === 'pre-billing' ? jobId : undefined,
        employee_id: reportType === 'timesheet' ? employeeId : undefined,
        start_date: startDate,
        end_date: endDate,
      });

      const filename = `${reportType}_${startDate}_to_${endDate}.csv`;
      downloadBlob(blob, filename);
      toast.success('Report downloaded');
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Export failed';
      toast.error(msg);
    } finally {
      setGenerating(false);
    }
  };

  // ── Bookkeeper Export Handler ───────────────────────────────
  const handleBookkeeperExport = async () => {
    setBkGenerating(true);
    try {
      const blob = await generateBookkeeperExport({
        format: bkFormat,
        period_start: bkStartDate,
        period_end: bkEndDate,
        include_labor: bkIncludeLabor,
        include_parts: bkIncludeParts,
      });

      const ext = bkFormat === 'quickbooks' ? 'iif' : 'csv';
      const filename = `${bkFormat}_${bkStartDate}_to_${bkEndDate}.${ext}`;
      downloadBlob(blob, filename);
      toast.success('Bookkeeper export downloaded');
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Export failed';
      toast.error(msg);
    } finally {
      setBkGenerating(false);
    }
  };

  // ── Render ──────────────────────────────────────────────────
  return (
    <div className="space-y-6">
      {/* ═══ Section 1: Standard Reports ═══ */}
      <Card>
        <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-4">
          Standard Report Exports
        </h2>

        {/* Report Type Selector */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-6">
          {REPORT_TYPES.map((rt) => (
            <button
              key={rt.key}
              onClick={() => setReportType(rt.key)}
              className={`flex items-start gap-3 p-4 rounded-lg border-2 transition-colors text-left min-h-[44px]
                ${reportType === rt.key
                  ? 'border-primary-500 bg-primary-50 dark:bg-primary-900/20'
                  : 'border-gray-200 dark:border-gray-700 hover:border-gray-300 dark:hover:border-gray-600'
                }`}
            >
              <div className={`flex-shrink-0 mt-0.5 ${
                reportType === rt.key ? 'text-primary-500' : 'text-gray-400'
              }`}>
                {rt.icon}
              </div>
              <div>
                <p className={`font-medium text-sm ${
                  reportType === rt.key
                    ? 'text-primary-700 dark:text-primary-300'
                    : 'text-gray-900 dark:text-gray-100'
                }`}>
                  {rt.label}
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                  {rt.description}
                </p>
              </div>
            </button>
          ))}
        </div>

        {/* Parameters */}
        <div className="flex items-end flex-wrap gap-4 mb-6">
          {reportType === 'pre-billing' && (
            <div className="flex-1 min-w-[200px]">
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Job *
              </label>
              <select
                value={jobId ?? ''}
                onChange={(e) => setJobId(e.target.value ? Number(e.target.value) : undefined)}
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600
                           bg-white dark:bg-gray-700 px-3 py-2 text-sm
                           text-gray-900 dark:text-gray-100 min-h-[44px]"
              >
                <option value="">Select a job...</option>
                {jobsQuery.data?.map((j: { id: number; job_number: string; job_name: string }) => (
                  <option key={j.id} value={j.id}>
                    {j.job_number} — {j.job_name}
                  </option>
                ))}
              </select>
            </div>
          )}

          {reportType === 'timesheet' && (
            <div className="flex-1 min-w-[200px]">
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Employee
              </label>
              <select
                value={employeeId ?? ''}
                onChange={(e) => setEmployeeId(e.target.value ? Number(e.target.value) : undefined)}
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600
                           bg-white dark:bg-gray-700 px-3 py-2 text-sm
                           text-gray-900 dark:text-gray-100 min-h-[44px]"
              >
                <option value="">All Employees</option>
                {employeesQuery.data?.items.map((emp) => (
                  <option key={emp.id} value={emp.id}>
                    {emp.display_name}
                  </option>
                ))}
              </select>
            </div>
          )}

          <div className="min-w-[140px]">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">From</label>
            <input
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600
                         bg-white dark:bg-gray-700 px-3 py-2 text-sm
                         text-gray-900 dark:text-gray-100 min-h-[44px]"
            />
          </div>
          <div className="min-w-[140px]">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">To</label>
            <input
              type="date"
              value={endDate}
              onChange={(e) => setEndDate(e.target.value)}
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600
                         bg-white dark:bg-gray-700 px-3 py-2 text-sm
                         text-gray-900 dark:text-gray-100 min-h-[44px]"
            />
          </div>
        </div>

        <div className="flex items-center justify-between flex-wrap gap-3 pt-4 border-t border-gray-200 dark:border-gray-700">
          <div className="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
            <FileText className="h-4 w-4" />
            <span>Format: CSV</span>
          </div>

          <button
            onClick={handleGenerate}
            disabled={generating}
            className="inline-flex items-center gap-2 px-6 py-2.5 text-sm font-medium
                       bg-primary-600 text-white rounded-lg hover:bg-primary-700
                       disabled:opacity-50 min-h-[44px]"
          >
            <Download className="h-4 w-4" />
            {generating ? 'Generating...' : 'Generate & Download'}
          </button>
        </div>
      </Card>

      {/* ═══ Section 2: Bookkeeper Exports ═══ */}
      <Card>
        <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-1">
          Bookkeeper Exports
        </h2>
        <p className="text-sm text-gray-500 dark:text-gray-400 mb-4">
          Structured exports for your bookkeeper's accounting software.
        </p>

        {/* Bookkeeper Format Selector */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-6">
          {BOOKKEEPER_FORMATS.map((fmt) => (
            <button
              key={fmt.key}
              onClick={() => setBkFormat(fmt.key)}
              className={`flex items-start gap-3 p-4 rounded-lg border-2 transition-colors text-left min-h-[44px]
                ${bkFormat === fmt.key
                  ? 'border-primary-500 bg-primary-50 dark:bg-primary-900/20'
                  : 'border-gray-200 dark:border-gray-700 hover:border-gray-300 dark:hover:border-gray-600'
                }`}
            >
              <div className={`flex-shrink-0 mt-0.5 ${
                bkFormat === fmt.key ? 'text-primary-500' : 'text-gray-400'
              }`}>
                {fmt.icon}
              </div>
              <div>
                <p className={`font-medium text-sm ${
                  bkFormat === fmt.key
                    ? 'text-primary-700 dark:text-primary-300'
                    : 'text-gray-900 dark:text-gray-100'
                }`}>
                  {fmt.label}
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                  {fmt.description}
                </p>
              </div>
            </button>
          ))}
        </div>

        {/* Date Range + Options */}
        <div className="flex items-end flex-wrap gap-4 mb-6">
          <div className="min-w-[140px]">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">From</label>
            <input
              type="date"
              value={bkStartDate}
              onChange={(e) => setBkStartDate(e.target.value)}
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600
                         bg-white dark:bg-gray-700 px-3 py-2 text-sm
                         text-gray-900 dark:text-gray-100 min-h-[44px]"
            />
          </div>
          <div className="min-w-[140px]">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">To</label>
            <input
              type="date"
              value={bkEndDate}
              onChange={(e) => setBkEndDate(e.target.value)}
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600
                         bg-white dark:bg-gray-700 px-3 py-2 text-sm
                         text-gray-900 dark:text-gray-100 min-h-[44px]"
            />
          </div>

          {/* Include checkboxes (not shown for payroll — always labor) */}
          {bkFormat !== 'payroll' && (
            <div className="flex flex-wrap items-center gap-4">
              <label className="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300 cursor-pointer min-h-[44px]">
                <input
                  type="checkbox"
                  checked={bkIncludeLabor}
                  onChange={(e) => setBkIncludeLabor(e.target.checked)}
                  className="rounded border-gray-300 dark:border-gray-600"
                />
                Include Labor
              </label>
              <label className="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300 cursor-pointer min-h-[44px]">
                <input
                  type="checkbox"
                  checked={bkIncludeParts}
                  onChange={(e) => setBkIncludeParts(e.target.checked)}
                  className="rounded border-gray-300 dark:border-gray-600"
                />
                Include Parts
              </label>
            </div>
          )}
        </div>

        <div className="flex items-center justify-between flex-wrap gap-3 pt-4 border-t border-gray-200 dark:border-gray-700">
          <div className="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
            <BookOpen className="h-4 w-4" />
            <span>
              {bkFormat === 'quickbooks' ? 'IIF Format' :
               bkFormat === 'general_ledger' ? 'CSV (Debit/Credit)' :
               'CSV (Payroll)'}
            </span>
          </div>

          <button
            onClick={handleBookkeeperExport}
            disabled={bkGenerating}
            className="inline-flex items-center gap-2 px-6 py-2.5 text-sm font-medium
                       bg-primary-600 text-white rounded-lg hover:bg-primary-700
                       disabled:opacity-50 min-h-[44px]"
          >
            <Download className="h-4 w-4" />
            {bkGenerating ? 'Generating...' : 'Generate & Download'}
          </button>
        </div>
      </Card>

      {/* Info Card */}
      <Card>
        <div className="flex items-start gap-3">
          <FileText className="h-5 w-5 text-gray-400 flex-shrink-0 mt-0.5" />
          <div>
            <h3 className="font-medium text-gray-900 dark:text-gray-100 text-sm">About Exports</h3>
            <ul className="mt-2 space-y-1 text-sm text-gray-500 dark:text-gray-400">
              <li>- <strong>Pre-Billing:</strong> Labor hours + parts cost/sell for a specific job. Give this to the bookkeeper.</li>
              <li>- <strong>Timesheet:</strong> Clock entries with in/out times, regular and overtime hours.</li>
              <li>- <strong>Labor Overview:</strong> Breakdowns by employee, job, and bill rate type for the period.</li>
              <li className="pt-2">- <strong>QuickBooks IIF:</strong> Import directly into QuickBooks Desktop. Uses standard account names.</li>
              <li>- <strong>General Ledger:</strong> Debit/credit format compatible with any accounting system.</li>
              <li>- <strong>Payroll:</strong> Employee hours + pay rates for payroll processors (ADP, Gusto, etc.).</li>
            </ul>
          </div>
        </div>
      </Card>
    </div>
  );
}
