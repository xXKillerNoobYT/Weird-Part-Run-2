/**
 * ProfitabilityPage — cost analysis per job: labor cost, parts margin, budget utilization.
 *
 * Shows labor cost (hours × employee pay rate), parts cost vs sell price,
 * and budget tracking. Dollar billing rates are handled externally by the bookkeeper.
 */

import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { DollarSign, TrendingUp, AlertTriangle, Download, BarChart3 } from 'lucide-react';
import { Card, CardHeader } from '../../../components/ui/Card';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { toast } from '../../../lib/toast';
import { getProfitability, generateExport, downloadBlob } from '../../../api/reports';
import type { JobProfitability } from '../../../api/reports';


export function ProfitabilityPage() {
  const [startDate, setStartDate] = useState(() => {
    const d = new Date();
    d.setDate(1);
    return d.toISOString().split('T')[0];
  });
  const [endDate, setEndDate] = useState(() =>
    new Date().toISOString().split('T')[0],
  );
  const [hasGenerated, setHasGenerated] = useState(false);
  const [exporting, setExporting] = useState(false);

  const reportQuery = useQuery({
    queryKey: ['profitability', startDate, endDate],
    queryFn: () => getProfitability({ start_date: startDate, end_date: endDate }),
    enabled: hasGenerated,
    staleTime: 30_000,
    retry: 1,
  });

  const report = reportQuery.data;

  const handleExportCSV = async () => {
    setExporting(true);
    try {
      const blob = await generateExport({
        report_type: 'profitability',
        format: 'csv',
        start_date: startDate,
        end_date: endDate,
      });
      downloadBlob(blob, `profitability_${startDate}_to_${endDate}.csv`);
      toast.success('Report downloaded');
    } catch {
      toast.error('Export failed');
    } finally {
      setExporting(false);
    }
  };

  return (
    <div className="space-y-6">
      {/* Controls */}
      <Card>
        <div className="flex items-end flex-wrap gap-4">
          <div className="min-w-[140px]">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">From</label>
            <input
              type="date"
              value={startDate}
              onChange={(e) => { setStartDate(e.target.value); setHasGenerated(false); }}
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
              onChange={(e) => { setEndDate(e.target.value); setHasGenerated(false); }}
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600
                         bg-white dark:bg-gray-700 px-3 py-2 text-sm
                         text-gray-900 dark:text-gray-100 min-h-[44px]"
            />
          </div>
          <button
            onClick={() => setHasGenerated(true)}
            className="inline-flex items-center gap-2 px-6 py-2.5 text-sm font-medium
                       bg-primary-600 text-white rounded-lg hover:bg-primary-700
                       min-h-[44px]"
          >
            <BarChart3 className="h-4 w-4" />
            Generate
          </button>
          {report && (
            <button
              onClick={handleExportCSV}
              disabled={exporting}
              className="inline-flex items-center gap-2 px-4 py-2.5 text-sm font-medium
                         border border-gray-300 dark:border-gray-600 rounded-lg
                         text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700
                         disabled:opacity-50 min-h-[44px]"
            >
              <Download className="h-4 w-4" />
              <span className="hidden sm:inline">Export CSV</span>
            </button>
          )}
        </div>
      </Card>

      {/* Loading / Empty */}
      {reportQuery.isLoading && <PageSpinner label="Generating profitability report..." />}
      {hasGenerated && !reportQuery.isLoading && !report && (
        <EmptyState
          icon={<BarChart3 className="h-12 w-12" />}
          title="No Data"
          description="No cost data found for the selected period."
        />
      )}

      {/* Summary Cards */}
      {report && (
        <>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <SummaryCard
              label="Total Labor Cost"
              value={`$${report.totals.total_labor_cost.toLocaleString()}`}
              sub={`${report.totals.total_labor_hours.toLocaleString()} hrs`}
              icon={<DollarSign className="h-5 w-5" />}
            />
            <SummaryCard
              label="Total Parts Cost"
              value={`$${report.totals.total_parts_cost.toLocaleString()}`}
              sub={`Sell: $${report.totals.total_parts_sell.toLocaleString()}`}
              icon={<DollarSign className="h-5 w-5" />}
            />
            <SummaryCard
              label="Parts Margin"
              value={`$${report.totals.total_parts_margin.toLocaleString()}`}
              sub={report.totals.total_parts_cost > 0
                ? `${((report.totals.total_parts_margin / report.totals.total_parts_cost) * 100).toFixed(1)}%`
                : '—'}
              icon={<TrendingUp className="h-5 w-5" />}
              color={report.totals.total_parts_margin >= 0 ? 'green' : 'red'}
            />
            <SummaryCard
              label="Combined Cost"
              value={`$${report.totals.total_combined_cost.toLocaleString()}`}
              sub={`${report.totals.jobs_over_budget} over budget`}
              icon={<AlertTriangle className="h-5 w-5" />}
              color={report.totals.jobs_over_budget > 0 ? 'red' : 'green'}
            />
          </div>

          {/* Budget Status Bar */}
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <Card className="text-center">
              <p className="text-2xl font-bold text-green-600 dark:text-green-400">{report.totals.jobs_under_budget}</p>
              <p className="text-sm text-gray-500 dark:text-gray-400">Under Budget</p>
            </Card>
            <Card className="text-center">
              <p className="text-2xl font-bold text-red-600 dark:text-red-400">{report.totals.jobs_over_budget}</p>
              <p className="text-sm text-gray-500 dark:text-gray-400">Over Budget</p>
            </Card>
            <Card className="text-center">
              <p className="text-2xl font-bold text-gray-500 dark:text-gray-400">{report.totals.jobs_no_budget}</p>
              <p className="text-sm text-gray-500 dark:text-gray-400">No Budget Set</p>
            </Card>
          </div>

          {/* Job Profitability Table */}
          <Card noPadding>
            <CardHeader title="Job Cost Analysis" subtitle={`${report.by_job.length} jobs`} />
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/50">
                    <th className="text-left px-4 py-3 font-medium text-gray-500 dark:text-gray-400">Job</th>
                    <th className="text-right px-4 py-3 font-medium text-gray-500 dark:text-gray-400">Labor Hrs</th>
                    <th className="text-right px-4 py-3 font-medium text-gray-500 dark:text-gray-400 hidden md:table-cell">Labor Cost</th>
                    <th className="text-right px-4 py-3 font-medium text-gray-500 dark:text-gray-400 hidden md:table-cell">Parts Cost</th>
                    <th className="text-right px-4 py-3 font-medium text-gray-500 dark:text-gray-400 hidden lg:table-cell">Parts Sell</th>
                    <th className="text-right px-4 py-3 font-medium text-gray-500 dark:text-gray-400">Total Cost</th>
                    <th className="text-right px-4 py-3 font-medium text-gray-500 dark:text-gray-400 hidden sm:table-cell">Parts Margin</th>
                    <th className="text-right px-4 py-3 font-medium text-gray-500 dark:text-gray-400 hidden lg:table-cell">Budget</th>
                    <th className="text-right px-4 py-3 font-medium text-gray-500 dark:text-gray-400 hidden md:table-cell">Budget %</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100 dark:divide-gray-700/50">
                  {report.by_job.map((job) => (
                    <JobRow key={job.job_id} job={job} />
                  ))}
                </tbody>
              </table>
            </div>
          </Card>
        </>
      )}
    </div>
  );
}


function SummaryCard({
  label,
  value,
  sub,
  icon,
  color = 'default',
}: {
  label: string;
  value: string;
  sub: string;
  icon: React.ReactNode;
  color?: 'default' | 'green' | 'red';
}) {
  const colorClasses = {
    default: 'text-primary-500',
    green: 'text-green-500',
    red: 'text-red-500',
  };

  return (
    <Card>
      <div className="flex items-center gap-3">
        <div className={`flex-shrink-0 ${colorClasses[color]}`}>{icon}</div>
        <div className="min-w-0">
          <p className="text-xs text-gray-500 dark:text-gray-400 truncate">{label}</p>
          <p className="text-lg font-bold text-gray-900 dark:text-gray-100 truncate">{value}</p>
          <p className="text-xs text-gray-400 dark:text-gray-500 truncate">{sub}</p>
        </div>
      </div>
    </Card>
  );
}


function JobRow({ job }: { job: JobProfitability }) {
  // Color-code by budget utilization
  const getBudgetColor = () => {
    if (!job.budget_utilization_pct) return '';
    if (job.budget_utilization_pct >= 100) return 'bg-red-50 dark:bg-red-900/10';
    if (job.budget_utilization_pct >= 80) return 'bg-yellow-50 dark:bg-yellow-900/10';
    return '';
  };

  const getMarginColor = () => {
    if (job.parts_margin > 0) return 'text-green-600 dark:text-green-400';
    if (job.parts_margin < 0) return 'text-red-600 dark:text-red-400';
    return 'text-gray-500 dark:text-gray-400';
  };

  return (
    <tr className={`hover:bg-gray-50 dark:hover:bg-gray-800/30 ${getBudgetColor()}`}>
      <td className="px-4 py-3">
        <p className="font-medium text-gray-900 dark:text-gray-100">{job.job_name}</p>
        <p className="text-xs text-gray-500 dark:text-gray-400">{job.job_number}</p>
      </td>
      <td className="text-right px-4 py-3 text-gray-900 dark:text-gray-100">
        {job.labor_hours.toLocaleString()}
      </td>
      <td className="text-right px-4 py-3 text-gray-900 dark:text-gray-100 hidden md:table-cell">
        ${job.labor_cost.toLocaleString()}
      </td>
      <td className="text-right px-4 py-3 text-gray-900 dark:text-gray-100 hidden md:table-cell">
        ${job.parts_cost.toLocaleString()}
      </td>
      <td className="text-right px-4 py-3 text-gray-900 dark:text-gray-100 hidden lg:table-cell">
        ${job.parts_sell.toLocaleString()}
      </td>
      <td className="text-right px-4 py-3 font-medium text-gray-900 dark:text-gray-100">
        ${job.total_cost.toLocaleString()}
      </td>
      <td className={`text-right px-4 py-3 font-medium hidden sm:table-cell ${getMarginColor()}`}>
        ${job.parts_margin.toLocaleString()}
      </td>
      <td className="text-right px-4 py-3 text-gray-900 dark:text-gray-100 hidden lg:table-cell">
        {job.budget_limit != null ? `$${job.budget_limit.toLocaleString()}` : '—'}
      </td>
      <td className="text-right px-4 py-3 hidden md:table-cell">
        {job.budget_utilization_pct != null ? (
          <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium
            ${job.budget_utilization_pct >= 100
              ? 'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300'
              : job.budget_utilization_pct >= 80
                ? 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-300'
                : 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300'
            }`}
          >
            {job.budget_utilization_pct.toFixed(1)}%
          </span>
        ) : (
          <span className="text-gray-400 dark:text-gray-500">—</span>
        )}
      </td>
    </tr>
  );
}
