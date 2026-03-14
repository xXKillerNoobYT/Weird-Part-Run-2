/**
 * CostsTab — Job cost rollup with budget progress bar.
 * Extracted from JobDetailPage.
 *
 * Permission: only rendered when canSeeCosts is true (gated at parent level).
 * Shows: parts cost, labor cost, combined total, budget status, and a
 * breakdown of cost sources.
 */

import { useQuery } from '@tanstack/react-query';
import { Package, Clock, DollarSign, TrendingUp, Layers, AlertTriangle } from 'lucide-react';
import { PageSpinner } from '../../../../components/ui/Spinner';
import { EmptyState } from '../../../../components/ui/EmptyState';
import { Card, CardHeader } from '../../../../components/ui/Card';
import { getJobCostRollup, getJobBudgetStatus } from '../../../../api/costs';

export function CostsTab({ jobId, jobName: _jobName }: { jobId: number; jobName: string }) {
  const { data: rollup, isLoading: loadingRollup } = useQuery({
    queryKey: ['job-cost-rollup', jobId],
    queryFn: () => getJobCostRollup(jobId),
    staleTime: 30_000,
  });

  const { data: _budget } = useQuery({
    queryKey: ['job-budget-status', jobId],
    queryFn: () => getJobBudgetStatus(jobId),
    staleTime: 30_000,
  });

  const fmt = (v: number) =>
    `$${v.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

  if (loadingRollup) return <PageSpinner label="Loading cost data..." />;
  if (!rollup) {
    return (
      <EmptyState
        icon={<DollarSign className="h-12 w-12" />}
        title="No Cost Data"
        description="Cost information will appear once parts are ordered or labor is recorded for this job."
      />
    );
  }

  const hasBudget = rollup.budget_limit != null && rollup.budget_limit > 0;
  const budgetPct = rollup.budget_pct ?? 0;

  // Color scheme for budget progress
  const budgetColor =
    budgetPct >= 100
      ? 'red'
      : budgetPct >= (rollup.budget_alert_percent ?? 80)
        ? 'amber'
        : 'green';

  const barColorClass = {
    green: 'bg-green-500',
    amber: 'bg-amber-500',
    red: 'bg-red-500',
  }[budgetColor];

  const bgColorClass = {
    green: 'bg-green-50 dark:bg-green-900/20 border-green-200 dark:border-green-800',
    amber: 'bg-amber-50 dark:bg-amber-900/20 border-amber-200 dark:border-amber-800',
    red: 'bg-red-50 dark:bg-red-900/20 border-red-200 dark:border-red-800',
  }[budgetColor];

  const textColorClass = {
    green: 'text-green-700 dark:text-green-300',
    amber: 'text-amber-700 dark:text-amber-300',
    red: 'text-red-700 dark:text-red-300',
  }[budgetColor];

  return (
    <div className="space-y-4">
      {/* Budget Alert Banner — only if budget is set and approaching/over limit */}
      {hasBudget && budgetPct >= (rollup.budget_alert_percent ?? 80) && (
        <div className={`flex items-center gap-3 p-3 rounded-lg border ${bgColorClass}`}>
          <AlertTriangle className={`h-5 w-5 flex-shrink-0 ${budgetColor === 'red' ? 'text-red-500' : 'text-amber-500'
            }`} />
          <div className="flex-1 min-w-0">
            <p className={`text-sm font-medium ${textColorClass}`}>
              {budgetPct >= 100
                ? `Budget exceeded \u2014 ${budgetPct.toFixed(0)}% used`
                : `Budget warning \u2014 ${budgetPct.toFixed(0)}% used`}
            </p>
            <p className="text-xs text-gray-500 dark:text-gray-400">
              {fmt(rollup.combined_total)} spent of {fmt(rollup.budget_limit!)} budget
            </p>
          </div>
        </div>
      )}

      {/* Cost Summary KPIs */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <CostKPIBox
          label="Parts Cost"
          value={fmt(rollup.total_parts_cost)}
          icon={<Package className="h-4 w-4" />}
        />
        <CostKPIBox
          label="Labor Cost"
          value={fmt(rollup.total_labor_cost)}
          icon={<Clock className="h-4 w-4" />}
          sub={rollup.total_labor_hours != null ? `${rollup.total_labor_hours.toFixed(1)} hrs` : undefined}
        />
        <CostKPIBox
          label="Combined Total"
          value={fmt(rollup.combined_total)}
          icon={<TrendingUp className="h-4 w-4" />}
          highlight
        />
        <CostKPIBox
          label={hasBudget ? 'Budget Remaining' : 'Budget'}
          value={hasBudget ? fmt(rollup.budget_remaining ?? 0) : 'Not Set'}
          icon={<Layers className="h-4 w-4" />}
          sub={hasBudget ? `of ${fmt(rollup.budget_limit!)}` : undefined}
        />
      </div>

      {/* Budget Progress Bar */}
      {hasBudget && (
        <Card>
          <CardHeader title="Budget Progress" />
          <div className="px-4 pb-4">
            <div className="flex items-center justify-between text-sm mb-2">
              <span className="text-gray-500 dark:text-gray-400">
                {fmt(rollup.combined_total)} spent
              </span>
              <span className={`font-medium ${textColorClass}`}>
                {budgetPct.toFixed(1)}%
              </span>
            </div>
            <div className="h-3 bg-gray-200 dark:bg-gray-700 rounded-full overflow-hidden">
              <div
                className={`h-full rounded-full transition-all duration-500 ${barColorClass}`}
                style={{ width: `${Math.min(budgetPct, 100)}%` }}
              />
            </div>
            {budgetPct > 100 && (
              <div className="flex items-center gap-1.5 mt-2">
                <AlertTriangle className="h-3.5 w-3.5 text-red-500" />
                <span className="text-xs text-red-600 dark:text-red-400 font-medium">
                  Over budget by {fmt(rollup.combined_total - rollup.budget_limit!)}
                </span>
              </div>
            )}
          </div>
        </Card>
      )}

      {/* Cost Breakdown */}
      <Card>
        <CardHeader title="Cost Breakdown" />
        <div className="px-4 pb-4 space-y-3">
          <CostBreakdownRow
            label="Parts / Materials"
            value={fmt(rollup.total_parts_cost)}
            pct={rollup.combined_total > 0
              ? (rollup.total_parts_cost / rollup.combined_total * 100)
              : 0}
            color="bg-blue-500"
          />
          <CostBreakdownRow
            label="Labor"
            value={fmt(rollup.total_labor_cost)}
            pct={rollup.combined_total > 0
              ? (rollup.total_labor_cost / rollup.combined_total * 100)
              : 0}
            color="bg-green-500"
          />
          {rollup.billing_rate != null && rollup.billing_rate > 0 && (
            <div className="pt-2 border-t border-gray-200 dark:border-gray-700 flex justify-between text-sm">
              <span className="text-gray-500 dark:text-gray-400">Billing Rate</span>
              <span className="text-gray-900 dark:text-gray-100 font-medium">
                {fmt(rollup.billing_rate)}/hr
              </span>
            </div>
          )}
        </div>
      </Card>
    </div>
  );
}


/** KPI box for the job costs grid */
function CostKPIBox({
  label, value, icon, sub, highlight,
}: {
  label: string; value: string; icon: React.ReactNode;
  sub?: string; highlight?: boolean;
}) {
  return (
    <div className="bg-white dark:bg-gray-800 rounded-lg p-3 border border-gray-200 dark:border-gray-700">
      <div className="flex items-center gap-1.5 mb-1">
        <span className="text-gray-400 dark:text-gray-500">{icon}</span>
        <span className="text-xs text-gray-500 dark:text-gray-400">{label}</span>
      </div>
      <p className={`text-lg font-bold ${highlight
        ? 'text-primary-600 dark:text-primary-400'
        : 'text-gray-900 dark:text-gray-100'
        }`}>
        {value}
      </p>
      {sub && (
        <p className="text-xs text-gray-400 dark:text-gray-500 mt-0.5">{sub}</p>
      )}
    </div>
  );
}


/** Horizontal breakdown row with proportional bar */
function CostBreakdownRow({
  label, value, pct, color,
}: {
  label: string; value: string; pct: number; color: string;
}) {
  return (
    <div>
      <div className="flex items-center justify-between text-sm mb-1">
        <span className="text-gray-700 dark:text-gray-300">{label}</span>
        <div className="flex items-center gap-2">
          <span className="text-xs text-gray-400">{pct.toFixed(0)}%</span>
          <span className="font-medium text-gray-900 dark:text-gray-100">{value}</span>
        </div>
      </div>
      <div className="h-2 bg-gray-200 dark:bg-gray-700 rounded-full overflow-hidden">
        <div
          className={`h-full rounded-full transition-all ${color}`}
          style={{ width: `${Math.max(pct, 1)}%` }}
        />
      </div>
    </div>
  );
}
