/**
 * DailyReportTab — Live daily report for the Dashboard.
 *
 * Always shows current real-time data (no date picker):
 *   - Pending actions count with links
 *   - Expected deliveries this week
 *   - Overdue items highlighted
 *   - Today's activity summary
 *   - Budget alerts
 *
 * Permission: requires `show_dollar_values` to view (parent-gated).
 * Refreshes every 60 seconds for a "live" feel.
 */

import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import {
  Truck, AlertTriangle, Activity,
  DollarSign, ArrowRight, Package, RotateCcw, ShoppingCart,
} from 'lucide-react';
import { Card, CardHeader } from '../../../components/ui/Card';
import { Badge } from '../../../components/ui/Badge';
import { Spinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { getDailyReport } from '../../../api/costs';
import type { DailyReportDelivery, BudgetAlert } from '../../../lib/types';


export function DailyReportTab() {
  const navigate = useNavigate();

  const { data: report, isLoading, error } = useQuery({
    queryKey: ['daily-report'],
    queryFn: getDailyReport,
    staleTime: 30_000,
    refetchInterval: 60_000, // Auto-refresh every 60s for "live" view
  });

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Spinner size="lg" />
      </div>
    );
  }

  if (error || !report) {
    return (
      <EmptyState
        icon={<Activity className="h-12 w-12" />}
        title="Report Unavailable"
        description="Could not load the daily report. Try refreshing."
      />
    );
  }

  const { pending_actions, expected_deliveries, overdue_items, todays_activity, budget_alerts } = report;
  const totalPending =
    pending_actions.jpos_awaiting_approval +
    pending_actions.pos_to_submit +
    pending_actions.returns_to_sort +
    pending_actions.overdue_deliveries;

  return (
    <div className="space-y-5">
      {/* ── Overdue Alert Banner ─────────────────────────── */}
      {overdue_items.length > 0 && (
        <div className="flex items-center gap-3 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
          <AlertTriangle className="h-5 w-5 text-red-500 flex-shrink-0" />
          <div className="flex-1 min-w-0">
            <p className="text-sm font-medium text-red-700 dark:text-red-300">
              {overdue_items.length} overdue {overdue_items.length === 1 ? 'delivery' : 'deliveries'}
            </p>
            <p className="text-xs text-red-600/70 dark:text-red-400/70">
              Immediate attention required
            </p>
          </div>
        </div>
      )}

      {/* ── Pending Actions ──────────────────────────────── */}
      <Card>
        <CardHeader
          title="Pending Actions"
          action={
            totalPending > 0 ? (
              <Badge variant="warning">{totalPending}</Badge>
            ) : (
              <Badge variant="success">All clear</Badge>
            )
          }
        />
        <div className="px-4 pb-4 space-y-2">
          <ActionRow
            label="JPOs awaiting approval"
            count={pending_actions.jpos_awaiting_approval}
            icon={<ShoppingCart className="h-4 w-4" />}
            onClick={() => navigate('/office/requests')}
          />
          <ActionRow
            label="POs to submit"
            count={pending_actions.pos_to_submit}
            icon={<Package className="h-4 w-4" />}
            onClick={() => navigate('/office/purchase-orders')}
          />
          <ActionRow
            label="Returns to sort"
            count={pending_actions.returns_to_sort}
            icon={<RotateCcw className="h-4 w-4" />}
            onClick={() => navigate('/warehouse/returns')}
          />
          <ActionRow
            label="Overdue deliveries"
            count={pending_actions.overdue_deliveries}
            icon={<AlertTriangle className="h-4 w-4" />}
            onClick={() => navigate('/office/purchase-orders')}
            urgent
          />
        </div>
      </Card>

      {/* ── Today's Activity ─────────────────────────────── */}
      <Card>
        <CardHeader
          title="Today's Activity"
        />
        <div className="px-4 pb-4">
          <div className="grid grid-cols-3 gap-3">
            <ActivityStat label="Orders Created" value={todays_activity.orders_created} color="blue" />
            <ActivityStat label="Items Received" value={todays_activity.items_received} color="green" />
            <ActivityStat label="Returns Processed" value={todays_activity.returns_processed} color="purple" />
          </div>
        </div>
      </Card>

      {/* ── Expected Deliveries ──────────────────────────── */}
      <Card>
        <CardHeader
          title="Expected Deliveries This Week"
          action={
            expected_deliveries.length > 0 ? (
              <Badge variant="default">{expected_deliveries.length}</Badge>
            ) : null
          }
        />
        <div className="px-4 pb-4">
          {expected_deliveries.length === 0 ? (
            <p className="text-sm text-gray-500 dark:text-gray-400 py-3 text-center">
              No deliveries expected this week.
            </p>
          ) : (
            <div className="space-y-2">
              {expected_deliveries.map((d) => (
                <DeliveryRow key={d.po_id} delivery={d} />
              ))}
            </div>
          )}
        </div>
      </Card>

      {/* ── Overdue Items (detailed) ─────────────────────── */}
      {overdue_items.length > 0 && (
        <Card>
          <CardHeader
            title="Overdue Deliveries"
          />
          <div className="px-4 pb-4 space-y-2">
            {overdue_items.map((d) => (
              <DeliveryRow key={d.po_id} delivery={d} />
            ))}
          </div>
        </Card>
      )}

      {/* ── Budget Alerts ────────────────────────────────── */}
      {budget_alerts.length > 0 && (
        <Card>
          <CardHeader
            title="Budget Alerts"
          />
          <div className="px-4 pb-4 space-y-2">
            {budget_alerts.map((alert) => (
              <BudgetAlertRow key={alert.job_id} alert={alert} />
            ))}
          </div>
        </Card>
      )}

      {/* ── Live indicator ───────────────────────────────── */}
      <p className="text-center text-xs text-gray-400 dark:text-gray-500">
        <span className="inline-block h-2 w-2 rounded-full bg-green-400 mr-1.5 animate-pulse" />
        Live — updates every 60 seconds
      </p>
    </div>
  );
}


// ── Sub-components ──────────────────────────────────────────────────

function ActionRow({
  label, count, icon, onClick, urgent,
}: {
  label: string; count: number; icon: React.ReactNode;
  onClick: () => void; urgent?: boolean;
}) {
  const hasItems = count > 0;

  return (
    <button
      onClick={onClick}
      disabled={!hasItems}
      className={`w-full flex items-center gap-3 p-2.5 rounded-lg text-left transition-colors ${
        hasItems
          ? 'hover:bg-gray-50 dark:hover:bg-gray-800 cursor-pointer'
          : 'opacity-50 cursor-default'
      }`}
    >
      <span className={`${
        urgent && hasItems ? 'text-red-500' : 'text-gray-400 dark:text-gray-500'
      }`}>
        {icon}
      </span>
      <span className="flex-1 text-sm text-gray-700 dark:text-gray-300">{label}</span>
      <span className={`text-sm font-bold ${
        hasItems
          ? urgent
            ? 'text-red-600 dark:text-red-400'
            : 'text-amber-600 dark:text-amber-400'
          : 'text-gray-400 dark:text-gray-500'
      }`}>
        {count}
      </span>
      {hasItems && (
        <ArrowRight className="h-3.5 w-3.5 text-gray-400 dark:text-gray-500" />
      )}
    </button>
  );
}


function ActivityStat({
  label, value, color,
}: {
  label: string; value: number; color: 'blue' | 'green' | 'purple';
}) {
  const colorClasses = {
    blue: 'text-blue-600 dark:text-blue-400',
    green: 'text-green-600 dark:text-green-400',
    purple: 'text-purple-600 dark:text-purple-400',
  }[color];

  return (
    <div className="text-center p-3 bg-surface-secondary rounded-lg">
      <p className={`text-2xl font-bold ${colorClasses}`}>{value}</p>
      <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">{label}</p>
    </div>
  );
}


function DeliveryRow({ delivery }: { delivery: DailyReportDelivery }) {
  const expectedDate = new Date(delivery.expected_delivery + 'T00:00:00');
  const dateStr = expectedDate.toLocaleDateString('en-US', {
    weekday: 'short', month: 'short', day: 'numeric',
  });

  return (
    <div className={`flex items-center gap-3 p-2.5 rounded-lg border ${
      delivery.is_overdue
        ? 'border-red-200 dark:border-red-800 bg-red-50/50 dark:bg-red-900/10'
        : 'border-gray-200 dark:border-gray-700'
    }`}>
      <Truck className={`h-4 w-4 flex-shrink-0 ${
        delivery.is_overdue ? 'text-red-500' : 'text-gray-400 dark:text-gray-500'
      }`} />
      <div className="flex-1 min-w-0">
        <p className="text-sm text-gray-900 dark:text-gray-100 truncate">
          {delivery.po_number} — {delivery.supplier_name}
        </p>
        <p className="text-xs text-gray-500 dark:text-gray-400">
          {delivery.line_count} {delivery.line_count === 1 ? 'item' : 'items'}
        </p>
      </div>
      <div className="text-right flex-shrink-0">
        <p className={`text-xs font-medium ${
          delivery.is_overdue ? 'text-red-600 dark:text-red-400' : 'text-gray-600 dark:text-gray-300'
        }`}>
          {dateStr}
        </p>
        {delivery.is_overdue && (
          <Badge variant="danger">Overdue</Badge>
        )}
      </div>
    </div>
  );
}


function BudgetAlertRow({ alert }: { alert: BudgetAlert }) {
  const fmt = (v: number) =>
    `$${v.toLocaleString(undefined, { minimumFractionDigits: 0, maximumFractionDigits: 0 })}`;

  return (
    <div className={`flex items-center gap-3 p-2.5 rounded-lg border ${
      alert.alert_level === 'danger'
        ? 'border-red-200 dark:border-red-800 bg-red-50/50 dark:bg-red-900/10'
        : 'border-amber-200 dark:border-amber-800 bg-amber-50/50 dark:bg-amber-900/10'
    }`}>
      <DollarSign className={`h-4 w-4 flex-shrink-0 ${
        alert.alert_level === 'danger' ? 'text-red-500' : 'text-amber-500'
      }`} />
      <div className="flex-1 min-w-0">
        <p className="text-sm text-gray-900 dark:text-gray-100 truncate">
          {alert.job_name}
        </p>
        <p className="text-xs text-gray-500 dark:text-gray-400">
          {fmt(alert.current_spend)} of {fmt(alert.budget_limit)}
        </p>
      </div>
      <div className="text-right flex-shrink-0">
        <Badge variant={alert.alert_level === 'danger' ? 'danger' : 'warning'}>
          {alert.pct_used.toFixed(0)}%
        </Badge>
      </div>
    </div>
  );
}
