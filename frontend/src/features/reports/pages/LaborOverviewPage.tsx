/**
 * LaborOverviewPage — cross-job labor analytics.
 *
 * Shows hours breakdown by employee, by job, and by bill rate type.
 * Hours only — no dollar amounts (bookkeeper handles rates).
 */

import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  BarChart3, Clock, Users, Briefcase, Calendar, Download,
} from 'lucide-react';
import { Card } from '../../../components/ui/Card';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { toast } from '../../../lib/toast';
import {
  getLaborOverview, generateExport, downloadBlob,
} from '../../../api/reports';


type TabKey = 'employee' | 'job' | 'rate';

export function LaborOverviewPage() {
  // ── Controls ──────────────────────────────────────────────
  const [startDate, setStartDate] = useState(() => {
    const d = new Date();
    d.setDate(1);
    return d.toISOString().split('T')[0];
  });
  const [endDate, setEndDate] = useState(() =>
    new Date().toISOString().split('T')[0],
  );
  const [submitted, setSubmitted] = useState(false);
  const [activeTab, setActiveTab] = useState<TabKey>('employee');
  const [exporting, setExporting] = useState(false);

  // ── Data ──────────────────────────────────────────────────
  const reportQuery = useQuery({
    queryKey: ['reports', 'labor-overview', startDate, endDate],
    queryFn: () => getLaborOverview({ start_date: startDate, end_date: endDate }),
    enabled: submitted,
    staleTime: 30_000,
  });

  const data = reportQuery.data;

  // ── Export ────────────────────────────────────────────────
  const handleExport = async () => {
    setExporting(true);
    try {
      const blob = await generateExport({
        report_type: 'labor-overview',
        format: 'csv',
        start_date: startDate,
        end_date: endDate,
      });
      downloadBlob(blob, `labor_overview_${startDate}_to_${endDate}.csv`);
      toast.success('CSV downloaded');
    } catch {
      toast.error('Export failed');
    } finally {
      setExporting(false);
    }
  };

  const tabs: { key: TabKey; label: string; icon: React.ReactNode }[] = [
    { key: 'employee', label: 'By Employee', icon: <Users className="h-4 w-4" /> },
    { key: 'job', label: 'By Job', icon: <Briefcase className="h-4 w-4" /> },
    { key: 'rate', label: 'By Rate Type', icon: <BarChart3 className="h-4 w-4" /> },
  ];

  // ── Render ────────────────────────────────────────────────
  return (
    <div className="space-y-6">
      {/* Controls */}
      <Card>
        <div className="flex items-center justify-between flex-wrap gap-3 mb-4">
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
            Labor Overview
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

      {/* Empty / Loading */}
      {!submitted && (
        <EmptyState
          icon={<BarChart3 className="h-12 w-12" />}
          title="Generate Labor Overview"
          description="Select a date range and click Generate to see labor analytics."
        />
      )}

      {submitted && reportQuery.isLoading && <PageSpinner label="Loading overview..." />}

      {submitted && reportQuery.isError && (
        <EmptyState
          icon={<BarChart3 className="h-12 w-12" />}
          title="Error Loading Overview"
          description="Failed to load labor data. Please try again."
        />
      )}

      {/* Results */}
      {data && (
        <>
          {/* KPI Cards */}
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
            <KPICard icon={<Clock className="h-5 w-5" />} label="Total Hours" value={data.totals.total_hours.toFixed(1)} />
            <KPICard icon={<Clock className="h-5 w-5" />} label="Regular" value={data.totals.regular_hours.toFixed(1)} />
            <KPICard
              icon={<Clock className="h-5 w-5" />}
              label="Overtime"
              value={data.totals.overtime_hours.toFixed(1)}
              highlight={data.totals.overtime_hours > 0}
            />
            <KPICard icon={<Users className="h-5 w-5" />} label="Employees" value={String(data.totals.total_employees)} />
            <KPICard icon={<Briefcase className="h-5 w-5" />} label="Jobs" value={String(data.totals.total_jobs)} />
            <KPICard icon={<Calendar className="h-5 w-5" />} label="Work Days" value={String(data.totals.total_days)} />
          </div>

          {/* Tabs */}
          <Card noPadding>
            <div className="flex border-b border-gray-200 dark:border-gray-700 overflow-x-auto whitespace-nowrap">
              {tabs.map((tab) => (
                <button
                  key={tab.key}
                  onClick={() => setActiveTab(tab.key)}
                  className={`flex items-center gap-2 px-4 py-3 text-sm font-medium
                    border-b-2 transition-colors min-h-[44px]
                    ${activeTab === tab.key
                      ? 'border-primary-500 text-primary-600 dark:text-primary-400'
                      : 'border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
                    }`}
                >
                  {tab.icon}
                  <span className="hidden sm:inline">{tab.label}</span>
                </button>
              ))}
            </div>

            <div className="p-4">
              {activeTab === 'employee' && <ByEmployeeTable data={data.by_employee} />}
              {activeTab === 'job' && <ByJobTable data={data.by_job} />}
              {activeTab === 'rate' && <ByRateTable data={data.by_bill_rate} />}
            </div>
          </Card>
        </>
      )}
    </div>
  );
}


// ── Sub-components ──────────────────────────────────────────

function KPICard({ icon, label, value, highlight }: {
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
          highlight ? 'text-amber-600 dark:text-amber-400' : 'text-gray-900 dark:text-gray-100'
        }`}>
          {value}
        </p>
      </div>
    </Card>
  );
}

function ByEmployeeTable({ data }: { data: import('../../../api/reports').LaborByEmployee[] }) {
  if (data.length === 0) {
    return <p className="text-sm text-gray-500 dark:text-gray-400 py-4 text-center">No data</p>;
  }
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-gray-200 dark:border-gray-700 text-left">
            <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300">Employee</th>
            <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right">Total</th>
            <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right hidden sm:table-cell">Reg</th>
            <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right hidden sm:table-cell">OT</th>
            <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right hidden md:table-cell">Jobs</th>
            <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right hidden md:table-cell">Days</th>
            <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right hidden lg:table-cell">Avg/Day</th>
          </tr>
        </thead>
        <tbody>
          {data.map((emp) => (
            <tr key={emp.employee_id} className="border-b border-gray-100 dark:border-gray-700/50">
              <td className="py-2 px-3 text-gray-900 dark:text-gray-100 font-medium">{emp.employee}</td>
              <td className="py-2 px-3 text-right text-gray-900 dark:text-gray-100 font-semibold">{emp.total_hours.toFixed(1)}</td>
              <td className="py-2 px-3 text-right text-gray-600 dark:text-gray-400 hidden sm:table-cell">{emp.regular_hours.toFixed(1)}</td>
              <td className="py-2 px-3 text-right hidden sm:table-cell">
                {emp.overtime_hours > 0 ? (
                  <span className="text-amber-600 dark:text-amber-400 font-medium">{emp.overtime_hours.toFixed(1)}</span>
                ) : '—'}
              </td>
              <td className="py-2 px-3 text-right text-gray-600 dark:text-gray-400 hidden md:table-cell">{emp.jobs_worked}</td>
              <td className="py-2 px-3 text-right text-gray-600 dark:text-gray-400 hidden md:table-cell">{emp.days_worked}</td>
              <td className="py-2 px-3 text-right text-gray-600 dark:text-gray-400 hidden lg:table-cell">{emp.avg_hours_per_day.toFixed(1)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function ByJobTable({ data }: { data: import('../../../api/reports').LaborByJob[] }) {
  if (data.length === 0) {
    return <p className="text-sm text-gray-500 dark:text-gray-400 py-4 text-center">No data</p>;
  }
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-gray-200 dark:border-gray-700 text-left">
            <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300">Job</th>
            <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 hidden sm:table-cell">Number</th>
            <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right">Hours</th>
            <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right">Employees</th>
          </tr>
        </thead>
        <tbody>
          {data.map((job) => (
            <tr key={job.job_id} className="border-b border-gray-100 dark:border-gray-700/50">
              <td className="py-2 px-3 text-gray-900 dark:text-gray-100 font-medium">{job.job_name}</td>
              <td className="py-2 px-3 text-gray-500 dark:text-gray-400 hidden sm:table-cell">{job.job_number}</td>
              <td className="py-2 px-3 text-right text-gray-900 dark:text-gray-100 font-semibold">{job.total_hours.toFixed(1)}</td>
              <td className="py-2 px-3 text-right text-gray-600 dark:text-gray-400">{job.employee_count}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function ByRateTable({ data }: { data: import('../../../api/reports').LaborByBillRate[] }) {
  if (data.length === 0) {
    return <p className="text-sm text-gray-500 dark:text-gray-400 py-4 text-center">No data</p>;
  }
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-gray-200 dark:border-gray-700 text-left">
            <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300">Rate Type</th>
            <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right">Hours</th>
            <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right">Entries</th>
          </tr>
        </thead>
        <tbody>
          {data.map((rate) => (
            <tr key={rate.rate_type} className="border-b border-gray-100 dark:border-gray-700/50">
              <td className="py-2 px-3 text-gray-900 dark:text-gray-100 font-medium">{rate.rate_type}</td>
              <td className="py-2 px-3 text-right text-gray-900 dark:text-gray-100 font-semibold">{rate.total_hours.toFixed(1)}</td>
              <td className="py-2 px-3 text-right text-gray-600 dark:text-gray-400">{rate.entry_count}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
