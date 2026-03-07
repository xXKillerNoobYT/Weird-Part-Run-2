/**
 * TimesheetsPage — employee time entries grouped by day.
 *
 * Shows hours only — no dollar amounts. The bookkeeper handles billing rates.
 * Supports filtering by employee and date range with day grouping.
 */

import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Clock, Download, MapPin, Briefcase, Calendar } from 'lucide-react';
import { Card } from '../../../components/ui/Card';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { toast } from '../../../lib/toast';
import { getEmployees } from '../../../api/people';
import {
  getTimesheets, generateExport, downloadBlob,
} from '../../../api/reports';


export function TimesheetsPage() {
  // ── Controls ──────────────────────────────────────────────
  const [employeeId, setEmployeeId] = useState<number | undefined>(undefined);
  const [startDate, setStartDate] = useState(() => {
    const d = new Date();
    d.setDate(d.getDate() - 6); // last 7 days
    return d.toISOString().split('T')[0];
  });
  const [endDate, setEndDate] = useState(() =>
    new Date().toISOString().split('T')[0],
  );
  const [submitted, setSubmitted] = useState(false);
  const [exporting, setExporting] = useState(false);

  // ── Data ──────────────────────────────────────────────────
  const employeesQuery = useQuery({
    queryKey: ['employees', 'list'],
    queryFn: () => getEmployees({ page_size: 200, is_active: true }),
    staleTime: 60_000,
  });

  const reportQuery = useQuery({
    queryKey: ['reports', 'timesheets', employeeId, startDate, endDate],
    queryFn: () => getTimesheets({
      start_date: startDate,
      end_date: endDate,
      employee_id: employeeId,
      group_by: 'day',
    }),
    enabled: submitted,
    staleTime: 30_000,
  });

  const data = reportQuery.data;

  // ── Export ────────────────────────────────────────────────
  const handleExport = async () => {
    setExporting(true);
    try {
      const blob = await generateExport({
        report_type: 'timesheet',
        format: 'csv',
        employee_id: employeeId,
        start_date: startDate,
        end_date: endDate,
      });
      downloadBlob(blob, `timesheet_${startDate}_to_${endDate}.csv`);
      toast.success('CSV downloaded');
    } catch {
      toast.error('Export failed');
    } finally {
      setExporting(false);
    }
  };

  // ── Render ────────────────────────────────────────────────
  return (
    <div className="space-y-6">
      {/* Controls */}
      <Card>
        <div className="flex items-center justify-between flex-wrap gap-3 mb-4">
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
            Timesheets
          </h2>
          {data && (
            <button
              onClick={handleExport}
              disabled={exporting}
              className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium
                         bg-primary-600 text-white rounded-lg hover:bg-primary-700
                         disabled:opacity-50 min-h-[44px]"
            >
              <Download className="h-4 w-4" />
              <span className="hidden sm:inline">{exporting ? 'Exporting...' : 'Export CSV'}</span>
            </button>
          )}
        </div>

        <div className="flex items-end flex-wrap gap-4">
          {/* Employee Selector */}
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

          {/* Date Range */}
          <div className="min-w-[140px]">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              From
            </label>
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
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              To
            </label>
            <input
              type="date"
              value={endDate}
              onChange={(e) => setEndDate(e.target.value)}
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600
                         bg-white dark:bg-gray-700 px-3 py-2 text-sm
                         text-gray-900 dark:text-gray-100 min-h-[44px]"
            />
          </div>

          {/* Generate Button */}
          <button
            onClick={() => setSubmitted(true)}
            className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium
                       bg-primary-600 text-white rounded-lg hover:bg-primary-700
                       min-h-[44px]"
          >
            Generate
          </button>
        </div>
      </Card>

      {/* Loading / Empty States */}
      {!submitted && (
        <EmptyState
          icon={<Clock className="h-12 w-12" />}
          title="Generate a Timesheet"
          description="Select an employee and date range, then click Generate."
        />
      )}

      {submitted && reportQuery.isLoading && <PageSpinner label="Loading timesheet..." />}

      {submitted && reportQuery.isError && (
        <EmptyState
          icon={<Clock className="h-12 w-12" />}
          title="Error Loading Timesheet"
          description="Failed to load timesheet data. Please try again."
        />
      )}

      {/* Summary */}
      {data && (
        <>
          <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
            <SummaryCard
              icon={<Clock className="h-5 w-5" />}
              label="Total Hours"
              value={data.summary.total_hours.toFixed(1)}
            />
            <SummaryCard
              icon={<Clock className="h-5 w-5" />}
              label="Regular"
              value={data.summary.regular_hours.toFixed(1)}
            />
            <SummaryCard
              icon={<Clock className="h-5 w-5" />}
              label="Overtime"
              value={data.summary.overtime_hours.toFixed(1)}
              highlight={data.summary.overtime_hours > 0}
            />
            <SummaryCard
              icon={<Calendar className="h-5 w-5" />}
              label="Days Worked"
              value={String(data.summary.days_worked)}
            />
            <SummaryCard
              icon={<Briefcase className="h-5 w-5" />}
              label="Jobs Worked"
              value={String(data.summary.jobs_worked)}
            />
          </div>

          {/* Day Groups */}
          {data.day_groups.length === 0 ? (
            <EmptyState
              icon={<Clock className="h-12 w-12" />}
              title="No Entries"
              description="No clock entries found for the selected period."
            />
          ) : (
            data.day_groups.map((group) => (
              <Card key={group.date} noPadding>
                {/* Day Header */}
                <div className="flex items-center justify-between px-4 py-3 bg-gray-50 dark:bg-gray-700/30 border-b border-gray-200 dark:border-gray-700">
                  <div className="flex items-center gap-2">
                    <Calendar className="h-4 w-4 text-gray-400" />
                    <span className="font-semibold text-gray-900 dark:text-gray-100">
                      {formatDate(group.date)}
                    </span>
                  </div>
                  <div className="flex items-center gap-3 text-sm">
                    <span className="text-gray-600 dark:text-gray-400">
                      {group.total_hours.toFixed(1)}h
                    </span>
                    {group.overtime_hours > 0 && (
                      <span className="text-amber-600 dark:text-amber-400 font-medium">
                        +{group.overtime_hours.toFixed(1)} OT
                      </span>
                    )}
                  </div>
                </div>

                {/* Entries Table */}
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="border-b border-gray-200 dark:border-gray-700 text-left">
                        {!employeeId && (
                          <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300">Employee</th>
                        )}
                        <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300">Job</th>
                        <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300">In</th>
                        <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300">Out</th>
                        <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right">Reg</th>
                        <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right">OT</th>
                        <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right">Total</th>
                        <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 hidden lg:table-cell">GPS</th>
                      </tr>
                    </thead>
                    <tbody>
                      {group.entries.map((entry) => (
                        <tr key={entry.id} className="border-b border-gray-100 dark:border-gray-700/50">
                          {!employeeId && (
                            <td className="py-2 px-3 text-gray-900 dark:text-gray-100">—</td>
                          )}
                          <td className="py-2 px-3 text-gray-900 dark:text-gray-100">
                            <span className="text-gray-400 text-xs mr-1">{entry.job_number}</span>
                            {entry.job_name}
                          </td>
                          <td className="py-2 px-3 text-gray-600 dark:text-gray-400 whitespace-nowrap">
                            {formatTime(entry.clock_in)}
                          </td>
                          <td className="py-2 px-3 text-gray-600 dark:text-gray-400 whitespace-nowrap">
                            {entry.clock_out ? formatTime(entry.clock_out) : '—'}
                          </td>
                          <td className="py-2 px-3 text-right text-gray-900 dark:text-gray-100">
                            {entry.regular_hours.toFixed(1)}
                          </td>
                          <td className="py-2 px-3 text-right">
                            {entry.overtime_hours > 0 ? (
                              <span className="text-amber-600 dark:text-amber-400 font-medium">
                                {entry.overtime_hours.toFixed(1)}
                              </span>
                            ) : '—'}
                          </td>
                          <td className="py-2 px-3 text-right font-medium text-gray-900 dark:text-gray-100">
                            {entry.total_hours.toFixed(1)}
                          </td>
                          <td className="py-2 px-3 hidden lg:table-cell">
                            {(entry.gps_in || entry.gps_out) ? (
                              <MapPin className="h-4 w-4 text-green-500" />
                            ) : (
                              <span className="text-gray-300 dark:text-gray-600">—</span>
                            )}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </Card>
            ))
          )}
        </>
      )}
    </div>
  );
}


// ── Helpers ─────────────────────────────────────────────────

function SummaryCard({ icon, label, value, highlight }: {
  icon: React.ReactNode;
  label: string;
  value: string;
  highlight?: boolean;
}) {
  return (
    <Card className="flex items-start gap-3">
      <div className="flex-shrink-0 text-primary-500">{icon}</div>
      <div className="min-w-0">
        <p className="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wide">
          {label}
        </p>
        <p className={`text-lg font-bold truncate ${
          highlight
            ? 'text-amber-600 dark:text-amber-400'
            : 'text-gray-900 dark:text-gray-100'
        }`}>
          {value}
        </p>
      </div>
    </Card>
  );
}

/** Format ISO datetime to time string (HH:MM AM/PM) */
function formatTime(isoString: string): string {
  try {
    const d = new Date(isoString);
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  } catch {
    return isoString;
  }
}

/** Format ISO date to readable string */
function formatDate(dateStr: string): string {
  try {
    const d = new Date(dateStr + 'T00:00:00');
    return d.toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' });
  } catch {
    return dateStr;
  }
}
