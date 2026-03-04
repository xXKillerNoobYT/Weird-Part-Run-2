/**
 * DashboardPage — main landing page after login.
 *
 * Shows:
 *   1. Welcome header
 *   2. Fast Drive card (vehicle + destination quick-start)
 *   3. Live KPI cards (parts, jobs, orders, low stock)
 *   4. Quick Actions (navigable shortcuts)
 */

import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import {
  LayoutDashboard,
  Package,
  Briefcase,
  ShoppingCart,
  AlertTriangle,
  Search,
  ArrowRightLeft,
  Loader2,
} from 'lucide-react';

import { Card, CardHeader } from '../../../components/ui/Card';
import { FastDriveCard } from '../components/FastDriveCard';
import { getDashboard } from '../../../api/dashboard';


// ── Icon lookup for quick actions (backend sends icon name strings) ──

const ICON_MAP: Record<string, React.ReactNode> = {
  'briefcase':       <Briefcase className="h-5 w-5" />,
  'shopping-cart':   <ShoppingCart className="h-5 w-5" />,
  'search':          <Search className="h-5 w-5" />,
  'arrow-right-left': <ArrowRightLeft className="h-5 w-5" />,
  'package':         <Package className="h-5 w-5" />,
};


// ── KPI card config (maps backend keys to labels / icons / colors) ──

const KPI_CONFIG = [
  {
    key: 'total_parts' as const,
    label: 'Total Parts',
    icon: <Package className="h-5 w-5 text-blue-500" />,
    bg: 'bg-blue-50 dark:bg-blue-900/20',
  },
  {
    key: 'active_jobs' as const,
    label: 'Active Jobs',
    icon: <Briefcase className="h-5 w-5 text-green-500" />,
    bg: 'bg-green-50 dark:bg-green-900/20',
  },
  {
    key: 'pending_orders' as const,
    label: 'Pending Orders',
    icon: <ShoppingCart className="h-5 w-5 text-amber-500" />,
    bg: 'bg-amber-50 dark:bg-amber-900/20',
  },
  {
    key: 'low_stock_alerts' as const,
    label: 'Low Stock Alerts',
    icon: <AlertTriangle className="h-5 w-5 text-red-500" />,
    bg: 'bg-red-50 dark:bg-red-900/20',
  },
] as const;


export function DashboardPage() {
  const navigate = useNavigate();

  const { data: dashboard, isLoading } = useQuery({
    queryKey: ['dashboard'],
    queryFn: getDashboard,
    staleTime: 30_000,  // refresh every 30s
  });

  const kpis = dashboard?.kpis;

  return (
    <div className="space-y-6">
      {/* ── Welcome card ─────────────────────────────────── */}
      <Card>
        <div className="flex items-center gap-4">
          <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-primary-50 dark:bg-primary-900/20">
            <LayoutDashboard className="h-6 w-6 text-primary-500" />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">
              {dashboard
                ? `Welcome, ${dashboard.user_name}`
                : 'Welcome to Wired Part'}
            </h1>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              Your HVAC parts, trucks, and job management hub.
            </p>
          </div>
        </div>
      </Card>

      {/* ── Fast Drive ───────────────────────────────────── */}
      <FastDriveCard />

      {/* ── KPI grid ─────────────────────────────────────── */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        {KPI_CONFIG.map((cfg) => (
          <Card key={cfg.key}>
            <div className="flex items-center gap-3 sm:gap-4">
              <div
                className={`flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-lg ${cfg.bg}`}
              >
                {cfg.icon}
              </div>
              <div className="min-w-0">
                <p className="text-xs sm:text-sm font-medium text-gray-500 dark:text-gray-400 truncate">
                  {cfg.label}
                </p>
                {isLoading ? (
                  <Loader2 className="h-5 w-5 animate-spin text-gray-300 mt-1" />
                ) : (
                  <p className="text-xl sm:text-2xl font-bold text-gray-900 dark:text-gray-100">
                    {kpis?.[cfg.key] ?? 0}
                  </p>
                )}
              </div>
            </div>
          </Card>
        ))}
      </div>

      {/* ── Quick Actions ────────────────────────────────── */}
      <Card>
        <CardHeader
          title="Quick Actions"
          subtitle="Shortcuts to common tasks"
        />
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          {(dashboard?.quick_actions ?? []).map((action) => (
            <button
              key={action.label}
              onClick={() => navigate(action.route)}
              className="flex flex-col items-center gap-2 rounded-lg border border-gray-200 p-4 text-sm font-medium text-gray-600 transition-colors hover:bg-gray-50 dark:border-gray-700 dark:text-gray-300 dark:hover:bg-gray-800"
            >
              {ICON_MAP[action.icon] ?? <Package className="h-5 w-5" />}
              {action.label}
            </button>
          ))}
        </div>
      </Card>
    </div>
  );
}
