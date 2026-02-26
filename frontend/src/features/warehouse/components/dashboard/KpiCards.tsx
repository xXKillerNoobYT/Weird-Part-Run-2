/**
 * KpiCards — 4 summary cards at the top of the warehouse dashboard.
 *
 * Shows stock health %, total units, shortfall count, and pending tasks.
 * Dollar value is permission-gated (SHOW_DOLLAR_VALUES).
 */

import {
  Activity, Package, AlertTriangle, ClipboardList,
} from 'lucide-react';
import { Card } from '../../../../components/ui/Card';
import { cn } from '../../../../lib/utils';
import { useAuthStore } from '../../../../stores/auth-store';
import { PERMISSIONS } from '../../../../lib/constants';
import type { DashboardKPIs } from '../../../../lib/types';

interface KpiCardsProps {
  kpis: DashboardKPIs;
}

export function KpiCards({ kpis }: KpiCardsProps) {
  const { hasPermission } = useAuthStore();
  const showDollars = hasPermission(PERMISSIONS.SHOW_DOLLAR_VALUES);

  const cards = [
    {
      label: 'Stock Health',
      value: `${kpis.stock_health_pct}%`,
      icon: Activity,
      color: kpis.stock_health_pct >= 80
        ? 'text-green-500'
        : kpis.stock_health_pct >= 60
          ? 'text-amber-500'
          : 'text-red-500',
      bgColor: kpis.stock_health_pct >= 80
        ? 'bg-green-50 dark:bg-green-900/20'
        : kpis.stock_health_pct >= 60
          ? 'bg-amber-50 dark:bg-amber-900/20'
          : 'bg-red-50 dark:bg-red-900/20',
    },
    {
      label: showDollars && kpis.warehouse_value != null ? 'Warehouse Value' : 'Total Units',
      value: showDollars && kpis.warehouse_value != null
        ? `$${kpis.warehouse_value.toLocaleString(undefined, { minimumFractionDigits: 0, maximumFractionDigits: 0 })}`
        : kpis.total_units.toLocaleString(),
      icon: Package,
      color: 'text-primary-500',
      bgColor: 'bg-primary-50 dark:bg-primary-900/20',
      sub: showDollars && kpis.warehouse_value != null
        ? `${kpis.total_units.toLocaleString()} units`
        : undefined,
    },
    {
      label: 'Shortfalls',
      value: kpis.shortfall_count.toString(),
      icon: AlertTriangle,
      color: kpis.shortfall_count > 0 ? 'text-red-500' : 'text-green-500',
      bgColor: kpis.shortfall_count > 0
        ? 'bg-red-50 dark:bg-red-900/20'
        : 'bg-green-50 dark:bg-green-900/20',
    },
    {
      label: 'Pending Tasks',
      value: kpis.pending_task_count.toString(),
      icon: ClipboardList,
      color: kpis.pending_task_count > 0 ? 'text-amber-500' : 'text-green-500',
      bgColor: kpis.pending_task_count > 0
        ? 'bg-amber-50 dark:bg-amber-900/20'
        : 'bg-green-50 dark:bg-green-900/20',
    },
  ];

  return (
    <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
      {cards.map((card) => (
        <Card key={card.label} className="flex items-start gap-4">
          <div className={cn('p-2.5 rounded-lg', card.bgColor)}>
            <card.icon className={cn('h-5 w-5', card.color)} />
          </div>
          <div className="min-w-0">
            <p className="text-sm text-gray-500 dark:text-gray-400 truncate">
              {card.label}
            </p>
            <p className="text-2xl font-bold text-gray-900 dark:text-gray-100">
              {card.value}
            </p>
            {card.sub && (
              <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                {card.sub}
              </p>
            )}
          </div>
        </Card>
      ))}
    </div>
  );
}
