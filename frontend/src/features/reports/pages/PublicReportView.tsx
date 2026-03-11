/**
 * PublicReportView — renders a shared report via token.
 *
 * This page lives OUTSIDE the AppShell (no auth required).
 * It fetches report data via the public API and displays it
 * with a clean read-only layout optimized for printing.
 */

import { useParams } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { getPublicReport, type PublicReportData } from '../../../api/reports';


export default function PublicReportView() {
  const { token } = useParams<{ token: string }>();

  const { data: report, isLoading, error } = useQuery({
    queryKey: ['public-report', token],
    queryFn: () => getPublicReport(token!),
    enabled: !!token,
    retry: false,
  });

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50 dark:bg-gray-900">
        <div className="text-center">
          <div className="animate-spin w-10 h-10 border-4 border-blue-500 border-t-transparent rounded-full mx-auto mb-4" />
          <p className="text-gray-600 dark:text-gray-400">Loading report…</p>
        </div>
      </div>
    );
  }

  if (error) {
    const msg =
      (error as { response?: { status: number } })?.response?.status === 410
        ? 'This share link has expired or been revoked.'
        : 'Report not found. The link may be invalid.';
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50 dark:bg-gray-900">
        <div className="text-center max-w-md mx-4">
          <div className="text-5xl mb-4">🔗</div>
          <h1 className="text-xl font-semibold text-gray-800 dark:text-white mb-2">
            Link Unavailable
          </h1>
          <p className="text-gray-600 dark:text-gray-400">{msg}</p>
        </div>
      </div>
    );
  }

  if (!report) return null;

  return (
    <div className="min-h-screen bg-white dark:bg-gray-900">
      {/* Header bar */}
      <header className="bg-gradient-to-r from-blue-600 to-blue-700 text-white px-6 py-4 no-print">
        <div className="max-w-5xl mx-auto flex items-center justify-between">
          <div>
            <h1 className="text-lg font-semibold">
              {report.label || formatReportType(report.report_type)}
            </h1>
            <p className="text-blue-100 text-sm">
              Generated {new Date(report.generated_at).toLocaleString()}
            </p>
          </div>
          <button
            onClick={() => window.print()}
            className="px-4 py-2 bg-white/20 hover:bg-white/30 rounded-lg text-sm font-medium"
          >
            🖨️ Print
          </button>
        </div>
      </header>

      {/* Report content */}
      <main className="max-w-5xl mx-auto px-6 py-8">
        <ReportDataRenderer report={report} />

        {/* Annotations */}
        {report.annotations.length > 0 && (
          <div className="mt-8 border-t border-gray-200 dark:border-gray-700 pt-6">
            <h2 className="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-3">
              Notes ({report.annotations.length})
            </h2>
            <div className="space-y-2">
              {report.annotations.map((a) => (
                <div key={a.id} className="bg-gray-50 dark:bg-gray-800 rounded-lg p-3">
                  <p className="text-sm text-gray-800 dark:text-gray-200 whitespace-pre-wrap">
                    {a.content}
                  </p>
                  <p className="text-xs text-gray-500 mt-1">
                    — {a.author_name}, {new Date(a.created_at).toLocaleDateString()}
                  </p>
                </div>
              ))}
            </div>
          </div>
        )}
      </main>

      {/* Footer */}
      <footer className="text-center py-6 text-xs text-gray-400 no-print">
        Shared report · Read-only view
      </footer>
    </div>
  );
}


function formatReportType(type: string): string {
  return type
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (l) => l.toUpperCase());
}


/** Renders the data dict based on report_type */
function ReportDataRenderer({ report }: { report: PublicReportData }) {
  const { report_type, data } = report;

  if (data.error) {
    return (
      <div className="bg-red-50 dark:bg-red-900/30 text-red-700 dark:text-red-300 rounded-lg p-4">
        {String(data.error)}
      </div>
    );
  }

  if (report_type === 'pre_billing') {
    return <PreBillingView data={data} />;
  }
  if (report_type === 'timesheet') {
    return <TimesheetView data={data} />;
  }
  if (report_type === 'labor_overview') {
    return <LaborOverviewView data={data} />;
  }
  if (report_type === 'profitability') {
    return <ProfitabilityView data={data} />;
  }
  if (report_type === 'daily_report') {
    return <DailyReportView data={data} />;
  }

  return (
    <div className="bg-gray-50 dark:bg-gray-800 rounded-lg p-4">
      <pre className="text-xs overflow-x-auto">{JSON.stringify(data, null, 2)}</pre>
    </div>
  );
}


// eslint-disable-next-line @typescript-eslint/no-explicit-any
function PreBillingView({ data }: { data: any }) {
  const entries = data.entries || [];
  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-lg font-semibold text-gray-800 dark:text-white">
          Pre-Billing Report — Job #{data.job_id}
        </h2>
        <span className="text-sm text-gray-500">
          Total: {Number(data.total_hours || 0).toFixed(1)}h
        </span>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-sm border-collapse">
          <thead>
            <tr className="border-b-2 border-gray-300 dark:border-gray-600">
              <th className="text-left py-2 px-3 font-medium text-gray-600 dark:text-gray-400">Employee</th>
              <th className="text-left py-2 px-3 font-medium text-gray-600 dark:text-gray-400">Date</th>
              <th className="text-right py-2 px-3 font-medium text-gray-600 dark:text-gray-400">Regular</th>
              <th className="text-right py-2 px-3 font-medium text-gray-600 dark:text-gray-400">OT</th>
              <th className="text-right py-2 px-3 font-medium text-gray-600 dark:text-gray-400">Total</th>
              <th className="text-left py-2 px-3 font-medium text-gray-600 dark:text-gray-400">Rate Type</th>
            </tr>
          </thead>
          <tbody>
            {entries.map((e: Record<string, unknown>, i: number) => (
              <tr key={i} className="border-b border-gray-200 dark:border-gray-700">
                <td className="py-2 px-3">{String(e.employee)}</td>
                <td className="py-2 px-3">{String(e.work_date)}</td>
                <td className="text-right py-2 px-3">{Number(e.regular_hours || 0).toFixed(1)}</td>
                <td className="text-right py-2 px-3">{Number(e.overtime_hours || 0).toFixed(1)}</td>
                <td className="text-right py-2 px-3 font-medium">{Number(e.total || 0).toFixed(1)}</td>
                <td className="py-2 px-3">{String(e.bill_rate_type || 'Standard')}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}


// eslint-disable-next-line @typescript-eslint/no-explicit-any
function TimesheetView({ data }: { data: any }) {
  const entries = data.entries || [];
  return (
    <div>
      <h2 className="text-lg font-semibold text-gray-800 dark:text-white mb-4">Timesheet</h2>
      <div className="overflow-x-auto">
        <table className="w-full text-sm border-collapse">
          <thead>
            <tr className="border-b-2 border-gray-300 dark:border-gray-600">
              <th className="text-left py-2 px-3 font-medium text-gray-600 dark:text-gray-400">Employee</th>
              <th className="text-left py-2 px-3 font-medium text-gray-600 dark:text-gray-400">Date</th>
              <th className="text-left py-2 px-3 font-medium text-gray-600 dark:text-gray-400">Clock In</th>
              <th className="text-left py-2 px-3 font-medium text-gray-600 dark:text-gray-400">Clock Out</th>
              <th className="text-right py-2 px-3 font-medium text-gray-600 dark:text-gray-400">Regular</th>
              <th className="text-right py-2 px-3 font-medium text-gray-600 dark:text-gray-400">OT</th>
            </tr>
          </thead>
          <tbody>
            {entries.map((e: Record<string, unknown>, i: number) => (
              <tr key={i} className="border-b border-gray-200 dark:border-gray-700">
                <td className="py-2 px-3">{String(e.employee)}</td>
                <td className="py-2 px-3">{String(e.work_date)}</td>
                <td className="py-2 px-3">{e.clock_in ? String(e.clock_in) : '—'}</td>
                <td className="py-2 px-3">{e.clock_out ? String(e.clock_out) : '—'}</td>
                <td className="text-right py-2 px-3">{Number(e.regular_hours || 0).toFixed(1)}</td>
                <td className="text-right py-2 px-3">{Number(e.overtime_hours || 0).toFixed(1)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}


// eslint-disable-next-line @typescript-eslint/no-explicit-any
function LaborOverviewView({ data }: { data: any }) {
  const entries = data.entries || [];
  return (
    <div>
      <h2 className="text-lg font-semibold text-gray-800 dark:text-white mb-4">Labor Overview</h2>
      <div className="overflow-x-auto">
        <table className="w-full text-sm border-collapse">
          <thead>
            <tr className="border-b-2 border-gray-300 dark:border-gray-600">
              <th className="text-left py-2 px-3 font-medium text-gray-600 dark:text-gray-400">Employee</th>
              <th className="text-left py-2 px-3 font-medium text-gray-600 dark:text-gray-400">Job</th>
              <th className="text-right py-2 px-3 font-medium text-gray-600 dark:text-gray-400">Regular</th>
              <th className="text-right py-2 px-3 font-medium text-gray-600 dark:text-gray-400">OT</th>
              <th className="text-right py-2 px-3 font-medium text-gray-600 dark:text-gray-400">Total</th>
            </tr>
          </thead>
          <tbody>
            {entries.map((e: Record<string, unknown>, i: number) => (
              <tr key={i} className="border-b border-gray-200 dark:border-gray-700">
                <td className="py-2 px-3">{String(e.employee)}</td>
                <td className="py-2 px-3">{String(e.job_name)}</td>
                <td className="text-right py-2 px-3">{Number(e.regular || 0).toFixed(1)}</td>
                <td className="text-right py-2 px-3">{Number(e.overtime || 0).toFixed(1)}</td>
                <td className="text-right py-2 px-3 font-medium">{Number(e.total || 0).toFixed(1)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}


// eslint-disable-next-line @typescript-eslint/no-explicit-any
function ProfitabilityView({ data }: { data: any }) {
  const jobs = data.jobs || [];
  return (
    <div>
      <h2 className="text-lg font-semibold text-gray-800 dark:text-white mb-4">Profitability</h2>
      <div className="overflow-x-auto">
        <table className="w-full text-sm border-collapse">
          <thead>
            <tr className="border-b-2 border-gray-300 dark:border-gray-600">
              <th className="text-left py-2 px-3 font-medium text-gray-600 dark:text-gray-400">Job</th>
              <th className="text-right py-2 px-3 font-medium text-gray-600 dark:text-gray-400">Total Hours</th>
            </tr>
          </thead>
          <tbody>
            {jobs.map((j: Record<string, unknown>, i: number) => (
              <tr key={i} className="border-b border-gray-200 dark:border-gray-700">
                <td className="py-2 px-3">{String(j.job_name)}</td>
                <td className="text-right py-2 px-3 font-medium">{Number(j.total_hours || 0).toFixed(1)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}


// eslint-disable-next-line @typescript-eslint/no-explicit-any
function DailyReportView({ data }: { data: any }) {
  return (
    <div className="space-y-4">
      <h2 className="text-lg font-semibold text-gray-800 dark:text-white">
        Daily Report — {data.job_name}
      </h2>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <InfoCard label="Date" value={data.report_date} />
        <InfoCard label="Weather" value={data.weather_conditions} />
        <InfoCard label="Work Performed" value={data.work_performed} />
        <InfoCard label="Issues" value={data.issues_delays} />
        <InfoCard label="Safety Notes" value={data.safety_incidents} />
        <InfoCard label="Tomorrow's Plan" value={data.plan_for_tomorrow} />
      </div>
    </div>
  );
}


function InfoCard({ label, value }: { label: string; value: unknown }) {
  if (!value) return null;
  return (
    <div className="bg-gray-50 dark:bg-gray-800 rounded-lg p-3">
      <p className="text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">{label}</p>
      <p className="text-sm text-gray-800 dark:text-gray-200 whitespace-pre-wrap">{String(value)}</p>
    </div>
  );
}
