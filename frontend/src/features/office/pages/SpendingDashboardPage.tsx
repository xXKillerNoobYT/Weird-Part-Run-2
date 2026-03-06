/**
 * SpendingDashboardPage — Office analytics for cost tracking & procurement.
 *
 * Sections:
 *   1. Spending KPIs (total spend, orders, avg order, active suppliers)
 *   2. Spending by Supplier (horizontal bar chart)
 *   3. Spending by Category (horizontal bar chart)
 *   4. Spending by Job (table with budget progress bars)
 *   5. Monthly Spending Trend (bar chart)
 *   6. Price Variance Report (table with severity badges)
 *   7. Budget Alerts (active warnings)
 *   8. Company Settings (default margin, enforce default button)
 *
 * Permission: requires `show_dollar_values` to view.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  DollarSign, TrendingUp, ShoppingCart, Users, BarChart3,
  AlertTriangle, Settings2, RotateCcw, PieChart, Briefcase,
  Lock, Layers, ArrowUpDown,
} from 'lucide-react';
import { Card, CardHeader } from '../../../components/ui/Card';
import { Button } from '../../../components/ui/Button';
import { Badge } from '../../../components/ui/Badge';
import { Spinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Modal } from '../../../components/ui/Modal';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
  getSpendingSummary,
  getSpendingBySupplier,
  getSpendingByCategory,
  getSpendingByJob,
  getSpendingTrend,
  getPriceVarianceReport,
  getBudgetAlerts,
  getCompanySettings,
  updateCompanySetting,
  enforceDefaultMargin,
} from '../../../api/costs';


export function SpendingDashboardPage() {
  const { hasPermission } = useAuthStore();
  const canSeePricing = hasPermission(PERMISSIONS.SHOW_DOLLAR_VALUES);

  if (!canSeePricing) {
    return (
      <EmptyState
        icon={<Lock className="h-12 w-12" />}
        title="Permission Required"
        description="You need the 'Show Dollar Values' permission to view spending analytics."
      />
    );
  }

  return <DashboardContent />;
}


// ═══════════════════════════════════════════════════════════════
// Inner component (avoids hook issues from conditional early return)
// ═══════════════════════════════════════════════════════════════

function DashboardContent() {
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canEdit = hasPermission(PERMISSIONS.EDIT_PRICING);

  // ── Confirm modal for enforce default ──────────
  const [showEnforceModal, setShowEnforceModal] = useState(false);

  // ── Queries ────────────────────────────────────
  const { data: summary, isLoading: loadingSummary } = useQuery({
    queryKey: ['spending-summary'],
    queryFn: () => getSpendingSummary(),
    staleTime: 60_000,
  });

  const { data: suppliers } = useQuery({
    queryKey: ['spending-by-supplier'],
    queryFn: () => getSpendingBySupplier(),
    staleTime: 60_000,
  });

  const { data: categories } = useQuery({
    queryKey: ['spending-by-category'],
    queryFn: () => getSpendingByCategory(),
    staleTime: 60_000,
  });

  const { data: jobs } = useQuery({
    queryKey: ['spending-by-job'],
    queryFn: () => getSpendingByJob(),
    staleTime: 60_000,
  });

  const { data: trend } = useQuery({
    queryKey: ['spending-trend'],
    queryFn: () => getSpendingTrend({ group_by: 'month' }),
    staleTime: 120_000,
  });

  const { data: variance } = useQuery({
    queryKey: ['price-variance'],
    queryFn: () => getPriceVarianceReport(),
    staleTime: 120_000,
  });

  const { data: alerts } = useQuery({
    queryKey: ['budget-alerts'],
    queryFn: () => getBudgetAlerts(),
    staleTime: 30_000,
  });

  const { data: settings } = useQuery({
    queryKey: ['company-cost-settings'],
    queryFn: () => getCompanySettings(),
    staleTime: 60_000,
  });

  // ── Mutations ──────────────────────────────────
  const enforceMutation = useMutation({
    mutationFn: () => enforceDefaultMargin(),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['spending'] });
      queryClient.invalidateQueries({ queryKey: ['parts'] });
      queryClient.invalidateQueries({ queryKey: ['part-cost-summary'] });
      setShowEnforceModal(false);
    },
  });

  // ── Format helpers ─────────────────────────────
  const fmt = (v: number) => {
    if (v >= 1_000_000) return `$${(v / 1_000_000).toFixed(1)}M`;
    if (v >= 1_000) return `$${(v / 1_000).toFixed(1)}K`;
    return `$${v.toFixed(2)}`;
  };
  const fmtFull = (v: number) => `$${v.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

  const defaultMargin = settings?.find(s => s.setting_key === 'default_margin_percent');

  if (loadingSummary) {
    return (
      <div className="flex items-center justify-center py-12">
        <Spinner size="lg" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* ── Budget Alerts Banner ──────────────────── */}
      {alerts && alerts.length > 0 && (
        <Card className="border-amber-300 dark:border-amber-700 bg-amber-50 dark:bg-amber-900/20">
          <div className="flex items-start gap-3">
            <AlertTriangle className="h-5 w-5 text-amber-500 shrink-0 mt-0.5" />
            <div className="flex-1 min-w-0">
              <h3 className="text-sm font-semibold text-amber-800 dark:text-amber-300 mb-1">
                Budget Alerts ({alerts.length})
              </h3>
              <div className="space-y-1">
                {alerts.map((alert) => (
                  <div key={alert.job_id} className="flex items-center gap-2 text-sm">
                    <Badge variant={alert.alert_level === 'danger' ? 'danger' : 'warning'}>
                      {alert.pct_used.toFixed(0)}%
                    </Badge>
                    <span className="text-amber-700 dark:text-amber-400 truncate">
                      {alert.job_name} — {fmtFull(alert.current_spend)} of {fmtFull(alert.budget_limit)}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </Card>
      )}

      {/* ── KPI Cards ────────────────────────────── */}
      {summary && (
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <KPICard
            label="Total Spend"
            value={fmt(summary.total_spend)}
            icon={<DollarSign className="h-5 w-5" />}
            subtitle={summary.period_label}
          />
          <KPICard
            label="Orders"
            value={String(summary.order_count)}
            icon={<ShoppingCart className="h-5 w-5" />}
          />
          <KPICard
            label="Avg Order Size"
            value={fmt(summary.avg_order_size)}
            icon={<TrendingUp className="h-5 w-5" />}
          />
          <KPICard
            label="Active Suppliers"
            value={String(summary.active_suppliers)}
            icon={<Users className="h-5 w-5" />}
          />
        </div>
      )}

      {/* ── Two-column layout for breakdowns ────── */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Supplier Breakdown */}
        <Card>
          <CardHeader title="By Supplier" subtitle="Top suppliers by spend" />
          {suppliers && suppliers.length > 0 ? (
            <div className="space-y-3">
              {suppliers.slice(0, 8).map((s) => (
                <HorizontalBar
                  key={s.supplier_id}
                  label={s.supplier_name}
                  value={fmtFull(s.total_spend)}
                  percent={s.pct_of_total}
                  sublabel={`${s.order_count} orders`}
                />
              ))}
            </div>
          ) : (
            <p className="text-sm text-gray-400 dark:text-gray-500">No supplier data yet.</p>
          )}
        </Card>

        {/* Category Breakdown */}
        <Card>
          <CardHeader title="By Category" subtitle="Spend distribution" />
          {categories && categories.length > 0 ? (
            <div className="space-y-3">
              {categories.slice(0, 8).map((c, i) => (
                <HorizontalBar
                  key={c.category_id ?? i}
                  label={c.category_name}
                  value={fmtFull(c.total_spend)}
                  percent={
                    summary && summary.total_spend > 0
                      ? (c.total_spend / summary.total_spend) * 100
                      : 0
                  }
                  sublabel={`${c.item_count} items`}
                />
              ))}
            </div>
          ) : (
            <p className="text-sm text-gray-400 dark:text-gray-500">No category data yet.</p>
          )}
        </Card>
      </div>

      {/* ── Spending Trend ───────────────────────── */}
      {trend && trend.length > 0 && (
        <Card>
          <CardHeader title="Spending Trend" subtitle="Monthly totals" />
          <TrendChart data={trend} />
        </Card>
      )}

      {/* ── Job Spending Table ────────────────────── */}
      {jobs && jobs.length > 0 && (
        <Card noPadding>
          <div className="p-6 pb-3">
            <CardHeader title="By Job" subtitle="Spending per job with budget tracking" />
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-gray-200 dark:border-gray-700 text-gray-500 dark:text-gray-400">
                  <th className="text-left px-6 py-2 font-medium">Job</th>
                  <th className="text-right px-4 py-2 font-medium">Total Spend</th>
                  <th className="text-right px-4 py-2 font-medium">Budget</th>
                  <th className="px-4 py-2 font-medium text-left min-w-[120px]">Usage</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100 dark:divide-gray-700/50">
                {jobs.map((j) => (
                  <tr key={j.job_id} className="text-gray-700 dark:text-gray-300">
                    <td className="px-6 py-3 font-medium">{j.job_name}</td>
                    <td className="px-4 py-3 text-right">{fmtFull(j.total_spend)}</td>
                    <td className="px-4 py-3 text-right">
                      {j.budget_limit != null ? fmtFull(j.budget_limit) : '—'}
                    </td>
                    <td className="px-4 py-3">
                      {j.budget_pct != null ? (
                        <BudgetBar percent={j.budget_pct} />
                      ) : (
                        <span className="text-gray-400 text-xs">No budget</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {/* ── Price Variance Report ─────────────────── */}
      {variance && variance.length > 0 && (
        <Card noPadding>
          <div className="p-6 pb-3">
            <CardHeader
              title="Price Variance"
              subtitle="Received vs quoted price deviations"
              action={
                <Badge variant="default">
                  <ArrowUpDown className="h-3 w-3 mr-1" />
                  {variance.length} items
                </Badge>
              }
            />
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-gray-200 dark:border-gray-700 text-gray-500 dark:text-gray-400">
                  <th className="text-left px-6 py-2 font-medium">Part</th>
                  <th className="text-left px-4 py-2 font-medium hidden sm:table-cell">Supplier</th>
                  <th className="text-left px-4 py-2 font-medium hidden md:table-cell">PO</th>
                  <th className="text-right px-4 py-2 font-medium">Quoted</th>
                  <th className="text-right px-4 py-2 font-medium">Actual</th>
                  <th className="text-right px-4 py-2 font-medium">Variance</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100 dark:divide-gray-700/50">
                {variance.slice(0, 15).map((v, i) => (
                  <tr key={i} className="text-gray-700 dark:text-gray-300">
                    <td className="px-6 py-2.5 font-medium">{v.part_name}</td>
                    <td className="px-4 py-2.5 hidden sm:table-cell text-gray-500 dark:text-gray-400">{v.supplier_name}</td>
                    <td className="px-4 py-2.5 hidden md:table-cell text-primary-600 dark:text-primary-400">{v.po_number}</td>
                    <td className="px-4 py-2.5 text-right">${v.quoted_price.toFixed(2)}</td>
                    <td className="px-4 py-2.5 text-right">${v.actual_price.toFixed(2)}</td>
                    <td className="px-4 py-2.5 text-right">
                      <Badge
                        variant={
                          v.variance_level === 'danger' ? 'danger'
                            : v.variance_level === 'warning' ? 'warning'
                              : 'success'
                        }
                      >
                        {v.variance_amount >= 0 ? '+' : ''}{v.variance_amount.toFixed(2)} ({v.variance_pct.toFixed(1)}%)
                      </Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {/* ── Company Settings & Enforce Default ──── */}
      {canEdit && (
        <Card>
          <CardHeader
            title="Cost Settings"
            subtitle="Company-wide margin and pricing configuration"
            action={<Settings2 className="h-4 w-4 text-gray-400" />}
          />
          <div className="flex flex-wrap items-center gap-4">
            <div className="flex items-center gap-2 text-sm">
              <span className="text-gray-500 dark:text-gray-400">Default Margin:</span>
              <span className="font-semibold text-gray-900 dark:text-gray-100">
                {defaultMargin?.setting_value ?? '25'}%
              </span>
            </div>
            <Button
              variant="secondary"
              size="sm"
              onClick={() => setShowEnforceModal(true)}
              icon={<RotateCcw className="h-3.5 w-3.5" />}
            >
              Enforce Default Margin
            </Button>
          </div>
        </Card>
      )}

      {/* ── Enforce Margin Confirmation Modal ───── */}
      <Modal
        isOpen={showEnforceModal}
        onClose={() => setShowEnforceModal(false)}
        title="Enforce Default Margin"
        size="sm"
      >
        <div className="space-y-4">
          <p className="text-sm text-gray-600 dark:text-gray-400">
            This will reset <strong>all parts</strong> to the company default margin
            of <strong>{defaultMargin?.setting_value ?? '25'}%</strong>.
            Any custom per-part margins will be cleared.
          </p>
          <p className="text-sm text-amber-600 dark:text-amber-400 font-medium">
            This action cannot be undone.
          </p>
          <div className="flex justify-end gap-2 pt-2">
            <Button
              variant="secondary"
              size="sm"
              onClick={() => setShowEnforceModal(false)}
            >
              Cancel
            </Button>
            <Button
              variant="danger"
              size="sm"
              onClick={() => enforceMutation.mutate()}
              isLoading={enforceMutation.isPending}
            >
              Reset All Margins
            </Button>
          </div>

          {enforceMutation.isSuccess && (
            <div className="p-2 bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded text-sm text-green-700 dark:text-green-400">
              Done! {(enforceMutation.data as any)?.cleared_count ?? 0} custom margins cleared.
            </div>
          )}
        </div>
      </Modal>
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════
// Sub-components
// ═══════════════════════════════════════════════════════════════

/** KPI stat card with icon, label, value, and optional subtitle. */
function KPICard({
  label,
  value,
  icon,
  subtitle,
}: {
  label: string;
  value: string;
  icon: React.ReactNode;
  subtitle?: string;
}) {
  return (
    <Card>
      <div className="flex items-start gap-3">
        <div className="p-2 bg-primary-50 dark:bg-primary-900/30 rounded-lg text-primary-600 dark:text-primary-400 shrink-0">
          {icon}
        </div>
        <div className="min-w-0">
          <p className="text-xs text-gray-500 dark:text-gray-400 truncate">{label}</p>
          <p className="text-xl font-bold text-gray-900 dark:text-gray-100 truncate">{value}</p>
          {subtitle && (
            <p className="text-xs text-gray-400 dark:text-gray-500 truncate">{subtitle}</p>
          )}
        </div>
      </div>
    </Card>
  );
}


/** Horizontal bar with label, value, and proportional fill. */
function HorizontalBar({
  label,
  value,
  percent,
  sublabel,
}: {
  label: string;
  value: string;
  percent: number;
  sublabel?: string;
}) {
  return (
    <div>
      <div className="flex items-center justify-between mb-1">
        <span className="text-sm font-medium text-gray-700 dark:text-gray-300 truncate">{label}</span>
        <span className="text-sm text-gray-600 dark:text-gray-400 shrink-0 ml-2">{value}</span>
      </div>
      <div className="h-2 bg-gray-100 dark:bg-gray-700 rounded-full overflow-hidden">
        <div
          className="h-full bg-primary-500 dark:bg-primary-400 rounded-full transition-all duration-500"
          style={{ width: `${Math.min(percent, 100)}%` }}
        />
      </div>
      {sublabel && (
        <p className="text-xs text-gray-400 dark:text-gray-500 mt-0.5">{sublabel}</p>
      )}
    </div>
  );
}


/** Budget usage bar with color coding. */
function BudgetBar({ percent }: { percent: number }) {
  const color =
    percent >= 95 ? 'bg-red-500' :
      percent >= 80 ? 'bg-amber-500' :
        'bg-green-500';

  return (
    <div className="flex items-center gap-2">
      <div className="flex-1 h-2 bg-gray-100 dark:bg-gray-700 rounded-full overflow-hidden">
        <div
          className={`h-full rounded-full transition-all duration-500 ${color}`}
          style={{ width: `${Math.min(percent, 100)}%` }}
        />
      </div>
      <span className="text-xs font-medium text-gray-600 dark:text-gray-400 w-10 text-right shrink-0">
        {percent.toFixed(0)}%
      </span>
    </div>
  );
}


/**
 * TrendChart — lightweight inline SVG bar chart for monthly spending trend.
 *
 * No charting library needed — uses simple SVG rects.
 */
function TrendChart({ data }: { data: { period_label: string; total_spend: number }[] }) {
  if (data.length === 0) return null;

  const maxSpend = Math.max(...data.map(d => d.total_spend), 1);
  const barWidth = Math.max(24, Math.min(48, 600 / data.length - 8));
  const chartHeight = 120;
  const labelHeight = 20;
  const totalHeight = chartHeight + labelHeight + 4;
  const totalWidth = data.length * (barWidth + 8) + 8;

  return (
    <div className="overflow-x-auto">
      <svg
        width={totalWidth}
        height={totalHeight}
        viewBox={`0 0 ${totalWidth} ${totalHeight}`}
        className="block"
      >
        {data.map((d, i) => {
          const barH = (d.total_spend / maxSpend) * chartHeight;
          const x = 8 + i * (barWidth + 8);
          const y = chartHeight - barH;

          return (
            <g key={i}>
              {/* Bar */}
              <rect
                x={x}
                y={y}
                width={barWidth}
                height={barH}
                rx={3}
                className="fill-primary-500 dark:fill-primary-400"
              />
              {/* Label */}
              <text
                x={x + barWidth / 2}
                y={chartHeight + labelHeight}
                textAnchor="middle"
                className="fill-gray-400 dark:fill-gray-500"
                style={{ fontSize: '10px' }}
              >
                {d.period_label}
              </text>
            </g>
          );
        })}
      </svg>
    </div>
  );
}
