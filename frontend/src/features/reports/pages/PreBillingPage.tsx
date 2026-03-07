/**
 * PreBillingPage — review labor hours, parts consumed, and movements for a job
 * before sending data to the bookkeeper for billing.
 *
 * Labor shows HOURS ONLY — no dollar rates. The bookkeeper handles actual
 * bill-out rates externally.
 */

import { useState } from 'react';
import { useQuery, useQueryClient, useMutation } from '@tanstack/react-query';
import {
  Receipt, ChevronDown, ChevronRight, Download, Clock,
  Package, ArrowRightLeft, BarChart3, Lock, Unlock,
} from 'lucide-react';
import { Card } from '../../../components/ui/Card';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { toast } from '../../../lib/toast';
import { useAuthStore } from '../../../stores/auth-store';
import { getActiveJobs } from '../../../api/jobs';
import {
  getPreBilling, generateExport, downloadBlob,
  getBillingPeriods, createBillingPeriod, lockBillingPeriod, unlockBillingPeriod,
} from '../../../api/reports';
import type { BillingPeriod } from '../../../api/reports';


export function PreBillingPage() {
  // ── Controls ──────────────────────────────────────────────
  const [jobId, setJobId] = useState<number | null>(null);
  const [startDate, setStartDate] = useState(() => {
    const d = new Date();
    d.setDate(1);
    return d.toISOString().split('T')[0];
  });
  const [endDate, setEndDate] = useState(() =>
    new Date().toISOString().split('T')[0],
  );
  const [exporting, setExporting] = useState(false);

  // Collapsible sections
  const [laborOpen, setLaborOpen] = useState(true);
  const [partsOpen, setPartsOpen] = useState(true);
  const [movementsOpen, setMovementsOpen] = useState(false);

  // ── Data ──────────────────────────────────────────────────
  const queryClient = useQueryClient();
  const canLock = useAuthStore((s) => s.hasPermission('lock_billing_periods'));

  const jobsQuery = useQuery({
    queryKey: ['jobs', 'active'],
    queryFn: () => getActiveJobs(),
    staleTime: 60_000,
  });

  const reportQuery = useQuery({
    queryKey: ['reports', 'pre-billing', jobId, startDate, endDate],
    queryFn: () => getPreBilling({ job_id: jobId!, start_date: startDate, end_date: endDate }),
    enabled: !!jobId,
    staleTime: 30_000,
  });

  const data = reportQuery.data;

  // ── Period Locking ──────────────────────────────────────────
  const periodsQuery = useQuery({
    queryKey: ['billing-periods', jobId],
    queryFn: () => getBillingPeriods({ job_id: jobId ?? undefined }),
    enabled: !!jobId,
    staleTime: 30_000,
  });

  // Find matching period for current date range
  const matchingPeriod: BillingPeriod | undefined = periodsQuery.data?.find(
    (p) => p.period_start === startDate && p.period_end === endDate,
  );

  const createPeriodMutation = useMutation({
    mutationFn: () => createBillingPeriod({ job_id: jobId ?? undefined, period_start: startDate, period_end: endDate }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['billing-periods'] });
      toast.success('Billing period created');
    },
    onError: () => toast.error('Failed to create billing period'),
  });

  const lockMutation = useMutation({
    mutationFn: (periodId: number) => lockBillingPeriod(periodId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['billing-periods'] });
      toast.success('Period locked');
    },
    onError: () => toast.error('Failed to lock period'),
  });

  const unlockMutation = useMutation({
    mutationFn: (periodId: number) => unlockBillingPeriod(periodId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['billing-periods'] });
      toast.success('Period unlocked');
    },
    onError: () => toast.error('Failed to unlock period'),
  });

  // ── Export Handler ────────────────────────────────────────
  const handleExport = async () => {
    if (!jobId) return;
    setExporting(true);
    try {
      const blob = await generateExport({
        report_type: 'pre-billing',
        format: 'csv',
        job_id: jobId,
        start_date: startDate,
        end_date: endDate,
      });
      downloadBlob(blob, `pre-billing_${startDate}_to_${endDate}.csv`);
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
            Pre-Billing Report
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
          {/* Job Selector */}
          <div className="flex-1 min-w-[200px]">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Job
            </label>
            <select
              value={jobId ?? ''}
              onChange={(e) => setJobId(e.target.value ? Number(e.target.value) : null)}
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
        </div>
      </Card>

      {/* Loading / Empty States */}
      {!jobId && (
        <EmptyState
          icon={<Receipt className="h-12 w-12" />}
          title="Select a Job"
          description="Choose a job above to generate a pre-billing report."
        />
      )}

      {jobId && reportQuery.isLoading && <PageSpinner label="Generating report..." />}

      {jobId && reportQuery.isError && (
        <EmptyState
          icon={<Receipt className="h-12 w-12" />}
          title="Error Loading Report"
          description="Failed to load pre-billing data. Please try again."
        />
      )}

      {/* Report Data */}
      {data && (
        <>
          {/* Job Header + Period Lock */}
          <Card>
            <div className="flex items-center justify-between flex-wrap gap-3">
              <div>
                <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
                  {data.job_number} — {data.job_name}
                </h3>
                <p className="text-sm text-gray-500 dark:text-gray-400">
                  {data.period_start} to {data.period_end}
                  {data.bill_rate_type && ` · ${data.bill_rate_type}`}
                </p>
              </div>

              {/* Period Lock Controls */}
              {canLock && (
                <div className="flex items-center gap-2">
                  {matchingPeriod?.locked_at ? (
                    <button
                      onClick={() => unlockMutation.mutate(matchingPeriod.id)}
                      disabled={unlockMutation.isPending}
                      className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium
                                 bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-300
                                 rounded-lg hover:bg-amber-200 dark:hover:bg-amber-900/50
                                 disabled:opacity-50 min-h-[44px]"
                    >
                      <Unlock className="h-4 w-4" />
                      <span className="hidden sm:inline">Unlock Period</span>
                    </button>
                  ) : matchingPeriod ? (
                    <button
                      onClick={() => lockMutation.mutate(matchingPeriod.id)}
                      disabled={lockMutation.isPending}
                      className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium
                                 bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300
                                 rounded-lg hover:bg-green-200 dark:hover:bg-green-900/50
                                 disabled:opacity-50 min-h-[44px]"
                    >
                      <Lock className="h-4 w-4" />
                      <span className="hidden sm:inline">Lock Period</span>
                    </button>
                  ) : (
                    <button
                      onClick={() => createPeriodMutation.mutate()}
                      disabled={createPeriodMutation.isPending}
                      className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium
                                 border border-gray-300 dark:border-gray-600 rounded-lg
                                 text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700
                                 disabled:opacity-50 min-h-[44px]"
                    >
                      <Lock className="h-4 w-4" />
                      <span className="hidden sm:inline">Create Period</span>
                    </button>
                  )}
                </div>
              )}
            </div>

            {/* Period status banner */}
            {matchingPeriod?.locked_at && (
              <div className="mt-3 flex items-center gap-2 px-3 py-2 rounded-lg
                              bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800">
                <Lock className="h-4 w-4 text-amber-600 dark:text-amber-400 flex-shrink-0" />
                <span className="text-sm text-amber-700 dark:text-amber-300">
                  Period locked{matchingPeriod.locked_by_name ? ` by ${matchingPeriod.locked_by_name}` : ''}
                  {matchingPeriod.locked_at ? ` on ${new Date(matchingPeriod.locked_at).toLocaleDateString()}` : ''}
                  — edits to labor and parts are disabled.
                </span>
              </div>
            )}
          </Card>

          {/* Summary Cards */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <SummaryCard
              icon={<Clock className="h-5 w-5" />}
              label="Total Hours"
              value={data.summary.total_labor_hours.toFixed(1)}
              sub={`${data.summary.total_regular_hours.toFixed(1)} reg + ${data.summary.total_overtime_hours.toFixed(1)} OT`}
            />
            <SummaryCard
              icon={<Package className="h-5 w-5" />}
              label="Parts Cost"
              value={`$${data.summary.total_parts_cost.toLocaleString(undefined, { minimumFractionDigits: 2 })}`}
            />
            <SummaryCard
              icon={<BarChart3 className="h-5 w-5" />}
              label="Parts Sell"
              value={`$${data.summary.total_parts_sell.toLocaleString(undefined, { minimumFractionDigits: 2 })}`}
            />
            <SummaryCard
              icon={<Receipt className="h-5 w-5" />}
              label="Budget"
              value={data.summary.budget_limit
                ? `$${data.summary.budget_limit.toLocaleString()}`
                : 'N/A'}
              sub={data.summary.budget_used_pct != null
                ? `${data.summary.budget_used_pct}% used (parts)`
                : undefined}
            />
          </div>

          {/* Labor Section */}
          <CollapsibleSection
            title="Labor"
            count={data.labor.length}
            icon={<Clock className="h-5 w-5" />}
            isOpen={laborOpen}
            onToggle={() => setLaborOpen(!laborOpen)}
          >
            {data.labor.length === 0 ? (
              <p className="text-sm text-gray-500 dark:text-gray-400 py-4 text-center">
                No labor entries in this period
              </p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-gray-200 dark:border-gray-700 text-left">
                      <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300">Employee</th>
                      <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300">Date</th>
                      <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right">Regular</th>
                      <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right">OT</th>
                      <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right">Total</th>
                      <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 hidden md:table-cell">Type</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.labor.map((entry, i) => (
                      <tr key={i} className="border-b border-gray-100 dark:border-gray-700/50">
                        <td className="py-2 px-3 text-gray-900 dark:text-gray-100">{entry.employee}</td>
                        <td className="py-2 px-3 text-gray-600 dark:text-gray-400">{entry.date}</td>
                        <td className="py-2 px-3 text-right text-gray-900 dark:text-gray-100">{entry.regular_hours.toFixed(1)}</td>
                        <td className="py-2 px-3 text-right text-gray-900 dark:text-gray-100">
                          {entry.overtime_hours > 0 ? (
                            <span className="text-amber-600 dark:text-amber-400 font-medium">
                              {entry.overtime_hours.toFixed(1)}
                            </span>
                          ) : '—'}
                        </td>
                        <td className="py-2 px-3 text-right font-medium text-gray-900 dark:text-gray-100">
                          {entry.total_hours.toFixed(1)}
                        </td>
                        <td className="py-2 px-3 text-gray-500 dark:text-gray-400 hidden md:table-cell">
                          {entry.bill_rate_type || '—'}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </CollapsibleSection>

          {/* Parts Section */}
          <CollapsibleSection
            title="Parts"
            count={data.parts.length}
            icon={<Package className="h-5 w-5" />}
            isOpen={partsOpen}
            onToggle={() => setPartsOpen(!partsOpen)}
          >
            {data.parts.length === 0 ? (
              <p className="text-sm text-gray-500 dark:text-gray-400 py-4 text-center">
                No parts consumed in this period
              </p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-gray-200 dark:border-gray-700 text-left">
                      <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300">Part</th>
                      <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 hidden sm:table-cell">Code</th>
                      <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right">Qty</th>
                      <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right hidden md:table-cell">Unit Cost</th>
                      <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right">Cost</th>
                      <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right">Sell</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.parts.map((part, i) => (
                      <tr key={i} className="border-b border-gray-100 dark:border-gray-700/50">
                        <td className="py-2 px-3 text-gray-900 dark:text-gray-100">{part.part_name}</td>
                        <td className="py-2 px-3 text-gray-500 dark:text-gray-400 hidden sm:table-cell">{part.part_code || '—'}</td>
                        <td className="py-2 px-3 text-right text-gray-900 dark:text-gray-100">{part.qty}</td>
                        <td className="py-2 px-3 text-right text-gray-600 dark:text-gray-400 hidden md:table-cell">
                          ${part.unit_cost.toFixed(2)}
                        </td>
                        <td className="py-2 px-3 text-right text-gray-900 dark:text-gray-100">
                          ${part.total_cost.toFixed(2)}
                        </td>
                        <td className="py-2 px-3 text-right font-medium text-green-600 dark:text-green-400">
                          ${part.total_sell.toFixed(2)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </CollapsibleSection>

          {/* Movements Section */}
          <CollapsibleSection
            title="Stock Movements"
            count={data.movements.length}
            icon={<ArrowRightLeft className="h-5 w-5" />}
            isOpen={movementsOpen}
            onToggle={() => setMovementsOpen(!movementsOpen)}
          >
            {data.movements.length === 0 ? (
              <p className="text-sm text-gray-500 dark:text-gray-400 py-4 text-center">
                No movements in this period
              </p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-gray-200 dark:border-gray-700 text-left">
                      <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300">Date</th>
                      <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300">Part</th>
                      <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 hidden sm:table-cell">From</th>
                      <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 hidden sm:table-cell">To</th>
                      <th className="py-2 px-3 font-medium text-gray-700 dark:text-gray-300 text-right">Qty</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.movements.map((m, i) => (
                      <tr key={i} className="border-b border-gray-100 dark:border-gray-700/50">
                        <td className="py-2 px-3 text-gray-600 dark:text-gray-400">{m.date}</td>
                        <td className="py-2 px-3 text-gray-900 dark:text-gray-100">{m.part_name}</td>
                        <td className="py-2 px-3 text-gray-500 dark:text-gray-400 hidden sm:table-cell">{m.from_location || '—'}</td>
                        <td className="py-2 px-3 text-gray-500 dark:text-gray-400 hidden sm:table-cell">{m.to_location || '—'}</td>
                        <td className="py-2 px-3 text-right text-gray-900 dark:text-gray-100">{m.qty}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </CollapsibleSection>
        </>
      )}
    </div>
  );
}


// ── Helper Components ─────────────────────────────────────────

function SummaryCard({ icon, label, value, sub }: {
  icon: React.ReactNode;
  label: string;
  value: string;
  sub?: string;
}) {
  return (
    <Card className="flex items-start gap-3">
      <div className="flex-shrink-0 text-primary-500">{icon}</div>
      <div className="min-w-0">
        <p className="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wide">
          {label}
        </p>
        <p className="text-lg font-bold text-gray-900 dark:text-gray-100 truncate">{value}</p>
        {sub && (
          <p className="text-xs text-gray-500 dark:text-gray-400 truncate">{sub}</p>
        )}
      </div>
    </Card>
  );
}

function CollapsibleSection({ title, count, icon, isOpen, onToggle, children }: {
  title: string;
  count: number;
  icon: React.ReactNode;
  isOpen: boolean;
  onToggle: () => void;
  children: React.ReactNode;
}) {
  return (
    <Card noPadding>
      <button
        onClick={onToggle}
        className="w-full flex items-center gap-3 p-4 hover:bg-gray-50 dark:hover:bg-gray-700/50
                   transition-colors min-h-[44px]"
      >
        {isOpen ? <ChevronDown className="h-4 w-4 text-gray-400" /> : <ChevronRight className="h-4 w-4 text-gray-400" />}
        <span className="text-primary-500">{icon}</span>
        <span className="font-semibold text-gray-900 dark:text-gray-100">{title}</span>
        <span className="text-sm text-gray-500 dark:text-gray-400">({count})</span>
      </button>
      {isOpen && <div className="px-4 pb-4">{children}</div>}
    </Card>
  );
}
