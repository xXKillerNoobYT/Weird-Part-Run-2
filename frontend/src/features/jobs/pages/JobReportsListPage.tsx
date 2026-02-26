/**
 * JobReportsListPage — Displays all daily reports across all jobs.
 *
 * Features:
 * - Date range filtering (from/to pickers)
 * - Report cards grouped by date, showing job name, worker count, hours, cost
 * - Click through to the full DailyReportView for each report
 *
 * This page aggregates reports from every job, making it easy for the boss
 * to review what happened across all job sites on any given day.
 */

import { useState, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import {
  FileText, Calendar, Users, Clock, Package, ChevronRight,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { Badge } from '../../../components/ui/Badge';
import { EmptyState } from '../../../components/ui/EmptyState';
import { getAllReports } from '../../../api/jobs';
import type { DailyReportResponse, ReportStatus } from '../../../lib/types';

const STATUS_VARIANTS: Record<ReportStatus, 'default' | 'success' | 'warning'> = {
  generated: 'default',
  reviewed: 'success',
  locked: 'warning',
};

function formatDate(dateStr: string): string {
  try {
    const d = new Date(dateStr + 'T00:00:00');
    return d.toLocaleDateString([], { weekday: 'short', year: 'numeric', month: 'short', day: 'numeric' });
  } catch {
    return dateStr;
  }
}

export function JobReportsListPage() {
  const navigate = useNavigate();

  // Date range filters
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');

  const { data: reports, isLoading } = useQuery({
    queryKey: ['all-reports', dateFrom, dateTo],
    queryFn: () =>
      getAllReports({
        date_from: dateFrom || undefined,
        date_to: dateTo || undefined,
      }),
    staleTime: 30_000,
  });

  // Group reports by date
  const groupedReports = useMemo(() => {
    if (!reports) return new Map<string, DailyReportResponse[]>();

    const map = new Map<string, DailyReportResponse[]>();
    for (const report of reports) {
      const existing = map.get(report.report_date) ?? [];
      existing.push(report);
      map.set(report.report_date, existing);
    }
    return map;
  }, [reports]);

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
            Daily Reports
          </h2>
          <p className="text-sm text-gray-500 dark:text-gray-400">
            Auto-generated reports across all jobs
          </p>
        </div>
      </div>

      {/* Date Range Filters */}
      <div className="flex items-center gap-3 flex-wrap">
        <div className="flex items-center gap-2">
          <Calendar className="h-4 w-4 text-gray-400 dark:text-gray-500" />
          <label className="text-xs text-gray-500 dark:text-gray-400">From:</label>
          <input
            type="date"
            value={dateFrom}
            onChange={(e) => setDateFrom(e.target.value)}
            className="px-2 py-1.5 text-xs border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
          />
        </div>
        <div className="flex items-center gap-2">
          <label className="text-xs text-gray-500 dark:text-gray-400">To:</label>
          <input
            type="date"
            value={dateTo}
            onChange={(e) => setDateTo(e.target.value)}
            className="px-2 py-1.5 text-xs border border-border rounded-md bg-surface text-gray-900 dark:text-gray-100"
          />
        </div>
        {(dateFrom || dateTo) && (
          <button
            onClick={() => { setDateFrom(''); setDateTo(''); }}
            className="text-xs text-blue-500 hover:text-blue-600 transition-colors"
          >
            Clear dates
          </button>
        )}
      </div>

      {/* Content */}
      {isLoading ? (
        <PageSpinner label="Loading reports..." />
      ) : !reports || reports.length === 0 ? (
        <EmptyState
          icon={<FileText className="h-12 w-12" />}
          title="No Reports Yet"
          description="Daily reports are auto-generated at midnight for jobs with labor activity. Check back tomorrow!"
        />
      ) : (
        <div className="space-y-6">
          {[...groupedReports.entries()].map(([date, dayReports]) => (
            <div key={date}>
              {/* Date header */}
              <div className="flex items-center gap-2 mb-2 pb-1 border-b border-border">
                <Calendar className="h-4 w-4 text-gray-400 dark:text-gray-500" />
                <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
                  {formatDate(date)}
                </h3>
                <span className="text-xs text-gray-400 dark:text-gray-500">
                  ({dayReports.length} report{dayReports.length !== 1 ? 's' : ''})
                </span>
              </div>

              {/* Report cards for this date */}
              <div className="space-y-2">
                {dayReports.map((report) => (
                  <div
                    key={report.id}
                    onClick={() => navigate(`/jobs/${report.job_id}/report/${report.report_date}`)}
                    className="flex items-center gap-3 p-3 bg-surface border border-border rounded-lg hover:border-blue-300 dark:hover:border-blue-600 transition-colors cursor-pointer group"
                  >
                    {/* Job info */}
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="text-xs font-mono text-gray-500 dark:text-gray-400">
                          #{report.job_number}
                        </span>
                        <Badge variant={STATUS_VARIANTS[report.status]}>{report.status}</Badge>
                      </div>
                      <p className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate mt-0.5">
                        {report.job_name}
                      </p>
                    </div>

                    {/* Stats */}
                    <div className="flex items-center gap-4 text-xs text-gray-500 dark:text-gray-400 shrink-0">
                      <span className="flex items-center gap-1" title="Workers">
                        <Users className="h-3.5 w-3.5" />
                        {report.worker_count}
                      </span>
                      <span className="flex items-center gap-1" title="Labor hours">
                        <Clock className="h-3.5 w-3.5" />
                        {report.total_labor_hours.toFixed(1)}h
                      </span>
                      {report.total_parts_cost > 0 && (
                        <span className="flex items-center gap-1 text-green-600 dark:text-green-400" title="Parts cost">
                          <Package className="h-3.5 w-3.5" />
                          ${report.total_parts_cost.toFixed(0)}
                        </span>
                      )}
                    </div>

                    {/* Chevron */}
                    <ChevronRight className="h-4 w-4 text-gray-400 dark:text-gray-500 opacity-0 group-hover:opacity-100 transition-opacity" />
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
